// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script}    from "forge-std/Script.sol";
import {console2}  from "forge-std/console2.sol";
import {IERC20}    from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LitnupToken}        from "../src/LitnupToken.sol";
import {AgentRegistry}      from "../src/AgentRegistry.sol";
import {StakingVault}       from "../src/StakingVault.sol";
import {BuybackBurn, ISwapRouter} from "../src/BuybackBurn.sol";
import {PerformanceOracle}  from "../src/PerformanceOracle.sol";
import {VotingEscrow}       from "../src/VotingEscrow.sol";
import {Vesting}            from "../src/Vesting.sol";
import {InsuranceFund}      from "../src/InsuranceFund.sol";
import {LITNUPTimelock}     from "../src/Timelock.sol";
import {DelegateRegistry}   from "../src/DelegateRegistry.sol";
import {EmissionScheduler}  from "../src/EmissionScheduler.sol";
import {PauseGuardian}      from "../src/PauseGuardian.sol";
import {RewardsDistributor} from "../src/RewardsDistributor.sol";

/// @title Deploy — canonical LITNUP deployment (all contracts + role wiring + governance handoff)
/// @notice Single source of truth for deploying the protocol. Deploys every contract, wires the
///         functional cross-contract roles, and (when a real governance Safe is supplied) hands ALL
///         privileged roles to the Safe + Timelock and RENOUNCES the deployer EOA — closing the v1
///         "single-EOA god mode" finding. See deploy/DEPLOYMENT.md for the full runbook, the
///         post-deploy governance steps (PauseGuardian whitelist, emission recipients), and the
///         mainnet gates (audit, legal, multisig ceremony) that MUST precede a mainnet run.
contract Deploy is Script {
    uint256 internal constant BASE_MAINNET = 8453;
    uint128 internal constant EMISSION_TOTAL = 170_000_000 ether; // 17% ecosystem bucket

    struct Deployed {
        address token; address timelock; address registry; address buyback; address vault;
        address oracle; address ve; address vesting; address insurance; address delegates;
        address emissions; address guardian; address rewards;
    }

    struct Cfg {
        address deployer; address safe; address rewardToken; address router;
        address[] signers; uint8 threshold; address[] guardians; uint8 guardianThreshold;
        uint256 timelockDelay; bool isMainnet; bool doHandoff;
    }

    function run() external returns (Deployed memory d) {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Cfg memory c = _config(vm.addr(pk));
        if (c.isMainnet) _requireMainnetConfig(c.safe, c.deployer, c.signers);

        console2.log("=== LITNUP deploy === chainId:", block.chainid);
        console2.log("deployer:", c.deployer);
        console2.log("governance safe:", c.safe);

        vm.startBroadcast(pk);

        // 1. token (owner = Safe) + timelock
        LitnupToken token = new LitnupToken(c.safe);
        LITNUPTimelock timelock = _deployTimelock(c.safe, c.timelockDelay);

        // 2. core protocol (deployer is transient admin to allow wiring)
        AgentRegistry registry = new AgentRegistry(IERC20(address(token)), c.deployer);
        BuybackBurn buyback = new BuybackBurn(IERC20(address(token)), ISwapRouter(c.router), c.deployer);
        StakingVault vault = new StakingVault(
            IERC20(address(token)), IERC20(c.rewardToken), registry, c.deployer, address(buyback)
        );
        PerformanceOracle oracle = new PerformanceOracle(vault, registry, c.signers, c.threshold, c.deployer);

        d.token = address(token); d.timelock = address(timelock); d.registry = address(registry);
        d.buyback = address(buyback); d.vault = address(vault); d.oracle = address(oracle);

        // 3. governance + supporting infra (admin = Safe directly; addresses only)
        _deployInfra(d, IERC20(address(token)), c.safe, address(timelock), c.guardians, c.guardianThreshold);

        // 4. wire functional cross-contract roles
        vault.grantRole(vault.ORACLE_ROLE(), address(oracle));
        registry.grantRole(registry.SLASHER_ROLE(), address(oracle));
        registry.setSlashSink(address(buyback));
        vault.grantRole(vault.PAUSER_ROLE(), d.guardian);
        registry.grantRole(registry.PAUSER_ROLE(), d.guardian);
        buyback.grantRole(buyback.PAUSER_ROLE(), d.guardian);

        // 5. testnet-only bootstrap (mint + fund emissions). On mainnet the mint is a Safe action.
        if (!c.isMainnet && c.safe == c.deployer) {
            token.mintInitialSupply();
            token.transfer(d.emissions, EMISSION_TOTAL);
            console2.log("testnet: minted 1B + funded EmissionScheduler 170M");
        }

        // 6. governance handoff: roles -> Safe + Timelock, renounce deployer
        if (c.doHandoff) {
            _handoff(registry, buyback, vault, oracle, c.safe, address(timelock), c.deployer);
            console2.log("roles handed to Safe+Timelock; deployer renounced");
        } else {
            console2.log("WARNING: deployer retains admin (no GOVERNANCE_SAFE supplied) - TESTNET ONLY");
        }

        vm.stopBroadcast();

        _writeJson(d, c.signers, c.threshold);
        _print(d);
    }

    // -----------------------------------------------------------------
    // Deployment helpers (split out to avoid stack-too-deep)
    // -----------------------------------------------------------------

    function _deployTimelock(address safe, uint256 delay) internal returns (LITNUPTimelock) {
        address[] memory proposers = new address[](1);
        proposers[0] = safe;
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open executor: anyone may execute AFTER the delay
        return new LITNUPTimelock(delay, proposers, executors, safe);
    }

    function _deployInfra(
        Deployed memory d,
        IERC20 token,
        address safe,
        address timelock,
        address[] memory guardians,
        uint8 guardianThreshold
    ) internal {
        d.ve = address(new VotingEscrow(token, safe));
        d.vesting = address(new Vesting(token, safe));
        d.insurance = address(new InsuranceFund(token, safe));
        d.delegates = address(new DelegateRegistry(safe));
        d.emissions = address(new EmissionScheduler(token, uint64(block.timestamp), 730 days, EMISSION_TOTAL, safe));
        d.guardian = address(new PauseGuardian(safe, timelock, guardians, guardianThreshold));
        d.rewards = address(new RewardsDistributor(token, safe));
    }

    /// @dev Grants every privileged role on the deployer-admin'd contracts to the Safe (admin) and
    ///      Timelock (delayed-sensitive config/signer management), then renounces the deployer's
    ///      roles so no EOA retains god-mode. SLASHER/ORACLE/PAUSER are contract-held and left wired.
    function _handoff(
        AgentRegistry registry,
        BuybackBurn buyback,
        StakingVault vault,
        PerformanceOracle oracle,
        address safe,
        address timelock,
        address deployer
    ) internal {
        registry.grantRole(registry.DEFAULT_ADMIN_ROLE(), safe);
        registry.grantRole(registry.CONFIG_ROLE(), timelock);
        registry.grantRole(registry.PAUSER_ROLE(), safe);
        registry.renounceRole(registry.CONFIG_ROLE(), deployer);
        registry.renounceRole(registry.PAUSER_ROLE(), deployer);
        registry.renounceRole(registry.DEFAULT_ADMIN_ROLE(), deployer);

        buyback.grantRole(buyback.DEFAULT_ADMIN_ROLE(), safe);
        buyback.grantRole(buyback.CONFIG_ROLE(), timelock);
        buyback.grantRole(buyback.PAUSER_ROLE(), safe);
        buyback.renounceRole(buyback.KEEPER_ROLE(), deployer);
        buyback.renounceRole(buyback.CONFIG_ROLE(), deployer);
        buyback.renounceRole(buyback.PAUSER_ROLE(), deployer);
        buyback.renounceRole(buyback.DEFAULT_ADMIN_ROLE(), deployer);

        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), safe);
        vault.grantRole(vault.CONFIG_ROLE(), timelock);
        vault.grantRole(vault.PAUSER_ROLE(), safe);
        vault.renounceRole(vault.CONFIG_ROLE(), deployer);
        vault.renounceRole(vault.PAUSER_ROLE(), deployer);
        vault.renounceRole(vault.DEFAULT_ADMIN_ROLE(), deployer);

        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), safe);
        oracle.grantRole(oracle.SIGNER_MANAGER_ROLE(), timelock);
        oracle.renounceRole(oracle.SIGNER_MANAGER_ROLE(), deployer);
        oracle.renounceRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);
    }

    // -----------------------------------------------------------------
    // Config / env
    // -----------------------------------------------------------------

    function _config(address deployer) internal view returns (Cfg memory c) {
        c.deployer = deployer;
        c.safe = vm.envOr("GOVERNANCE_SAFE", deployer);
        c.rewardToken = vm.envOr(
            "REWARD_TOKEN",
            block.chainid == BASE_MAINNET
                ? address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)  // Base USDC
                : address(0x036CbD53842c5426634e7929541eC2318f3dCF7e)  // Base Sepolia USDC
        );
        c.router = vm.envOr("UNISWAP_ROUTER", address(0x0000000000000000000000000000000000000001));
        c.signers = _resolveSigners();
        c.threshold = _resolveThreshold(uint8(c.signers.length));
        c.guardians = _resolveGuardians();
        uint256 gt = vm.envOr("GUARDIAN_THRESHOLD", uint256(3));
        c.guardianThreshold = gt > c.guardians.length ? uint8(c.guardians.length) : uint8(gt);
        c.timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(48 hours));
        c.isMainnet = block.chainid == BASE_MAINNET;
        c.doHandoff = c.safe != deployer;
    }

    function _requireMainnetConfig(address safe, address deployer, address[] memory signers) internal pure {
        require(safe != deployer, "MAINNET: GOVERNANCE_SAFE must be a real Safe, not the deployer");
        require(signers.length >= 5, "MAINNET: provide >=5 real oracle signers");
    }

    function _defaultTestSigners() internal pure returns (address[] memory s) {
        s = new address[](5);
        s[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        s[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        s[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
        s[3] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
        s[4] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    }

    function _resolveSigners() internal view returns (address[] memory) {
        try vm.envAddress("ORACLE_SIGNERS", ",") returns (address[] memory s) {
            require(s.length >= 3 && s.length <= 9, "ORACLE_SIGNERS: need 3-9 addresses");
            return s;
        } catch {
            require(block.chainid != BASE_MAINNET, "ORACLE_SIGNERS required on Base mainnet");
            return _defaultTestSigners();
        }
    }

    function _resolveGuardians() internal view returns (address[] memory) {
        try vm.envAddress("GUARDIANS", ",") returns (address[] memory g) {
            require(g.length >= 1 && g.length <= 9, "GUARDIANS: need 1-9 addresses");
            return g;
        } catch {
            return _defaultTestSigners();
        }
    }

    function _resolveThreshold(uint8 signerCount) internal view returns (uint8) {
        uint256 t = vm.envOr("ORACLE_THRESHOLD", uint256(0));
        if (t == 0) t = (uint256(signerCount) * 2 + 2) / 3; // ceil(2N/3)
        require(t > 0 && t <= signerCount, "Bad ORACLE_THRESHOLD");
        return uint8(t);
    }

    // -----------------------------------------------------------------
    // Output
    // -----------------------------------------------------------------

    function _writeJson(Deployed memory d, address[] memory signers, uint8 threshold) internal {
        string memory signersJson = "[";
        for (uint256 i = 0; i < signers.length; i++) {
            signersJson = string.concat(signersJson, i == 0 ? "" : ", ", '"', vm.toString(signers[i]), '"');
        }
        signersJson = string.concat(signersJson, "]");

        // Built incrementally (reassigning `j`) to keep the stack shallow.
        string memory j = string.concat("{\n", _kv("chainId", vm.toString(block.chainid), false));
        j = string.concat(j, _kv("litnupToken", vm.toString(d.token), true));
        j = string.concat(j, _kv("timelock", vm.toString(d.timelock), true));
        j = string.concat(j, _kv("agentRegistry", vm.toString(d.registry), true));
        j = string.concat(j, _kv("buybackBurn", vm.toString(d.buyback), true));
        j = string.concat(j, _kv("stakingVault", vm.toString(d.vault), true));
        j = string.concat(j, _kv("performanceOracle", vm.toString(d.oracle), true));
        j = string.concat(j, _kv("votingEscrow", vm.toString(d.ve), true));
        j = string.concat(j, _kv("vesting", vm.toString(d.vesting), true));
        j = string.concat(j, _kv("insuranceFund", vm.toString(d.insurance), true));
        j = string.concat(j, _kv("delegateRegistry", vm.toString(d.delegates), true));
        j = string.concat(j, _kv("emissionScheduler", vm.toString(d.emissions), true));
        j = string.concat(j, _kv("pauseGuardian", vm.toString(d.guardian), true));
        j = string.concat(j, _kv("rewardsDistributor", vm.toString(d.rewards), true));
        j = string.concat(j, '  "oracleSigners": ', signersJson, ",\n");
        j = string.concat(j, '  "oracleThreshold": ', vm.toString(uint256(threshold)), "\n}\n");

        vm.writeFile(string.concat("deployments/", vm.toString(block.chainid), ".json"), j);
    }

    /// @dev One JSON key/value line. `quoted` wraps the value in quotes (for addresses/strings).
    function _kv(string memory key, string memory value, bool quoted) internal pure returns (string memory) {
        if (quoted) return string.concat('  "', key, '": "', value, '",\n');
        return string.concat('  "', key, '": ', value, ",\n");
    }

    function _print(Deployed memory d) internal pure {
        console2.log("LitnupToken       :", d.token);
        console2.log("Timelock          :", d.timelock);
        console2.log("AgentRegistry     :", d.registry);
        console2.log("BuybackBurn       :", d.buyback);
        console2.log("StakingVault      :", d.vault);
        console2.log("PerformanceOracle :", d.oracle);
        console2.log("VotingEscrow      :", d.ve);
        console2.log("Vesting           :", d.vesting);
        console2.log("InsuranceFund     :", d.insurance);
        console2.log("DelegateRegistry  :", d.delegates);
        console2.log("EmissionScheduler :", d.emissions);
        console2.log("PauseGuardian     :", d.guardian);
        console2.log("RewardsDistributor:", d.rewards);
    }
}
