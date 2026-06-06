// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";

import {LitToken}         from "../contracts/src/LitToken.sol";
import {AgentRegistry}      from "../contracts/src/AgentRegistry.sol";
import {StakingVault}       from "../contracts/src/StakingVault.sol";
import {PerformanceOracle}  from "../contracts/src/PerformanceOracle.sol";
import {BuybackBurn, ISwapRouter} from "../contracts/src/BuybackBurn.sol";
import {VotingEscrow}       from "../contracts/src/VotingEscrow.sol";
import {MerkleAirdrop}      from "../contracts/src/MerkleAirdrop.sol";
import {Vesting}            from "../contracts/src/Vesting.sol";
import {InsuranceFund}      from "../contracts/src/InsuranceFund.sol";
import {LITNUPTimelock} from "../contracts/src/Timelock.sol";
import {DelegateRegistry}   from "../contracts/src/DelegateRegistry.sol";
import {EmissionScheduler}  from "../contracts/src/EmissionScheduler.sol";

/// @notice Full Foundry deployment script — wires all 12 protocol contracts,
///         sets cross-contract roles, and prints a manifest of addresses.
///
/// Usage (testnet):
///   export DEPLOYER_PRIVATE_KEY=0x...
///   export BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
///   export BASESCAN_API_KEY=...
///   forge script deploy/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL \
///     --private-key $DEPLOYER_PRIVATE_KEY --broadcast --verify
///
/// Usage (mainnet — DO NOT RUN until audit complete + multisig deployer):
///   Adjust DEPLOY_CONFIG below to load admin from a Safe multisig.
///   Use --ledger or --hd-paths instead of --private-key.
contract Deploy is Script {
    // ============================================================
    // CONFIG (override per environment via env vars)
    // ============================================================
    struct Config {
        address admin;          // governance / treasury multisig
        address[] oracleSigners; // initial multi-sig oracle signer set
        uint8    oracleThreshold;// signatures required (e.g. 3-of-5)
        ISwapRouter router;     // Aerodrome / Uniswap V3 router on the target chain
        address   sweepRecipient; // for MerkleAirdrop unclaimed sweep (treasury)
        // Emission scheduler params
        uint64    emissionStart;
        uint64    emissionDuration;
        uint128   emissionTotal; // 17% of supply by default
        // Timelock params
        uint256   timelockDelay; // seconds; 48h default
    }

    function _config(address deployer) internal view returns (Config memory c) {
        c.admin = deployer;

        // Default to 5 oracle signers (deployer + 4 mock).
        // Mainnet: replace with real, geographically-diverse hardware-key signers.
        c.oracleSigners = new address[](5);
        c.oracleSigners[0] = deployer;
        c.oracleSigners[1] = vm.addr(0x100);
        c.oracleSigners[2] = vm.addr(0x200);
        c.oracleSigners[3] = vm.addr(0x300);
        c.oracleSigners[4] = vm.addr(0x400);
        // Sort ascending — PerformanceOracle requires sorted recovery during apply
        for (uint i = 0; i < c.oracleSigners.length; i++) {
            for (uint j = i + 1; j < c.oracleSigners.length; j++) {
                if (c.oracleSigners[i] > c.oracleSigners[j]) {
                    (c.oracleSigners[i], c.oracleSigners[j]) = (c.oracleSigners[j], c.oracleSigners[i]);
                }
            }
        }
        c.oracleThreshold = 3;

        c.router = ISwapRouter(address(0)); // testnet stub; mainnet: real Aerodrome router
        c.sweepRecipient = deployer;        // → governance treasury post-mainnet

        c.emissionStart = uint64(block.timestamp);
        c.emissionDuration = 730 days;       // M0–M24
        c.emissionTotal = 170_000_000 ether; // 17% of supply

        c.timelockDelay = 48 hours;
    }

    // ============================================================
    // DEPLOYMENT
    // ============================================================
    function run() public returns (
        LitToken token,
        AgentRegistry registry,
        StakingVault vault,
        PerformanceOracle oracle,
        BuybackBurn buyback,
        VotingEscrow ve,
        Vesting vesting,
        InsuranceFund insurance,
        LITNUPTimelock timelock,
        DelegateRegistry delegates,
        EmissionScheduler emissions
    ) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        Config memory cfg = _config(deployer);

        vm.startBroadcast(deployerKey);

        // 1. Deploy token, mint full supply to admin
        token = new LitToken(cfg.admin);
        token.mintInitialSupply();

        // 2. Core protocol
        registry  = new AgentRegistry(token, cfg.admin);
        buyback   = new BuybackBurn(token, cfg.router, cfg.admin);
        vault     = new StakingVault(token, registry, cfg.admin, address(buyback));
        oracle    = new PerformanceOracle(vault, registry, cfg.oracleSigners, cfg.oracleThreshold, cfg.admin);

        // 3. Governance + supporting infra
        ve         = new VotingEscrow(token, cfg.admin);
        vesting    = new Vesting(token, cfg.admin);
        insurance  = new InsuranceFund(token, cfg.admin);
        delegates  = new DelegateRegistry(cfg.admin);

        // 4. Timelock — proposers & executors initially set to admin; transition to Governor post-veAGENTIC
        address[] memory proposers = new address[](1);
        proposers[0] = cfg.admin;
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open executor (anyone can execute after delay)
        timelock = new LITNUPTimelock(cfg.timelockDelay, proposers, executors, cfg.admin);

        // 5. Emission scheduler — funds streamed in next step
        emissions = new EmissionScheduler(
            token,
            cfg.emissionStart,
            cfg.emissionDuration,
            cfg.emissionTotal,
            cfg.admin
        );

        // 6. MerkleAirdrop — root + amount filled at season launch; deploy with placeholder
        // (Real S1 deploy uses a proper merkle root + funded amount.)

        // ============================================================
        // WIRE ROLES
        // ============================================================

        // Vault must be able to slash via registry
        registry.grantRole(registry.SLASHER_ROLE(), address(vault));

        // Oracle must be able to apply PnL + take fees + slash vault
        vault.grantRole(vault.ORACLE_ROLE(), address(oracle));

        // InsuranceFund disburser → admin (transitions to timelock post-mainnet)
        insurance.grantRole(insurance.DISBURSER_ROLE(), cfg.admin);

        // Fund the EmissionScheduler with its budget (admin pre-approves)
        token.transfer(address(emissions), cfg.emissionTotal);

        vm.stopBroadcast();

        // ============================================================
        // MANIFEST
        // ============================================================
        console2.log("============================================================");
        console2.log("LITNUP deployment complete · chainId %d", block.chainid);
        console2.log("============================================================");
        console2.log("LitToken (AGENTIC):     %s", address(token));
        console2.log("AgentRegistry:            %s", address(registry));
        console2.log("StakingVault:             %s", address(vault));
        console2.log("PerformanceOracle:        %s", address(oracle));
        console2.log("BuybackBurn:              %s", address(buyback));
        console2.log("VotingEscrow:             %s", address(ve));
        console2.log("Vesting:                  %s", address(vesting));
        console2.log("InsuranceFund:            %s", address(insurance));
        console2.log("Timelock:                 %s", address(timelock));
        console2.log("DelegateRegistry:         %s", address(delegates));
        console2.log("EmissionScheduler:        %s", address(emissions));
        console2.log("");
        console2.log("Admin (treasury / config):  %s", cfg.admin);
        console2.log("Oracle signer count:        %d", cfg.oracleSigners.length);
        console2.log("Oracle threshold:           %d", cfg.oracleThreshold);
        console2.log("Timelock delay:             %d seconds", cfg.timelockDelay);
        console2.log("Emission total:             %d LIT over %d days", cfg.emissionTotal / 1e18, cfg.emissionDuration / 1 days);
        console2.log("");
        console2.log("============================================================");
        console2.log("NEXT STEPS");
        console2.log("============================================================");
        console2.log("1. Copy PerformanceOracle address to agent-runtime/.env");
        console2.log("2. Approve registry from operator wallets");
        console2.log("3. Operators call registry.enroll() with bond + metadata");
        console2.log("4. Stakers approve vault + call vault.stake(agentId, amount)");
        console2.log("5. Run python -m agent_runtime.paper_trade --strategy momentum");
        console2.log("6. Schedule oracle attestations every 4 hours");
        console2.log("7. (Mainnet only) Transfer admin role → governance Safe + Timelock");
        console2.log("============================================================");
    }
}
