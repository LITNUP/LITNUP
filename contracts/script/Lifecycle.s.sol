// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {PerformanceOracle} from "../src/PerformanceOracle.sol";

/// @notice Drives a real end-to-end lifecycle against an already-deployed protocol: enroll an agent,
///         stake, then post a live 3-of-5 EIP-712 attestation (fee=0, so no settlement token needed).
contract Lifecycle is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        AgentRegistry registry = AgentRegistry(vm.envAddress("REGISTRY"));
        StakingVault vault = StakingVault(vm.envAddress("VAULT"));
        PerformanceOracle oracle = PerformanceOracle(vm.envAddress("ORACLE"));

        uint256 agentId = _enrollStake(pk, IERC20(vm.envAddress("TOKEN")), registry, vault);
        _attest(pk, oracle, agentId, vm.addr(pk));
        _log(vault, oracle, IERC20(vm.envAddress("TOKEN")), agentId);
    }

    function _enrollStake(uint256 pk, IERC20 token, AgentRegistry registry, StakingVault vault)
        internal
        returns (uint256 agentId)
    {
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);
        token.approve(address(registry), 10_000 ether);
        agentId = registry.enroll(deployer, 10_000 ether, bytes32("agent-momentum-1"), 1000);
        token.approve(address(vault), 10_000 ether);
        vault.stake(agentId, 10_000 ether);
        vm.stopBroadcast();
    }

    function _attest(uint256 pk, PerformanceOracle oracle, uint256 agentId, address feePayer) internal {
        uint64 epoch = 1;
        uint64 deadline = uint64(block.timestamp + 6 hours);
        int256 pnlDelta = int256(500 ether);
        bytes32 digest = _digest(oracle, agentId, pnlDelta, feePayer, epoch, deadline);

        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(vm.envUint("SK0"), digest);
        sigs[1] = _sign(vm.envUint("SK1"), digest);
        sigs[2] = _sign(vm.envUint("SK2"), digest);

        vm.broadcast(pk);
        oracle.applyAttestation(agentId, pnlDelta, 0, 0, feePayer, epoch, deadline, sigs);
    }

    function _digest(
        PerformanceOracle oracle,
        uint256 agentId,
        int256 pnlDelta,
        address feePayer,
        uint64 epoch,
        uint64 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            oracle.ATTESTATION_TYPEHASH(), agentId, pnlDelta, uint256(0), uint16(0), feePayer, epoch, deadline
        ));
        bytes32 domainSep = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("LITNUPOracle")), keccak256(bytes("1")), block.chainid, address(oracle)
        ));
        return keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
    }

    function _sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _log(StakingVault vault, PerformanceOracle oracle, IERC20 token, uint256 agentId) internal view {
        (uint128 principal,,,, int256 cumPnl,) = vault.vaults(agentId);
        console2.log("agentId            :", agentId);
        console2.log("staked principal   :", uint256(principal));
        console2.log("attested cumPnl    :", uint256(cumPnl >= 0 ? cumPnl : -cumPnl));
        console2.log("sharePrice (1e18)  :", vault.sharePrice(agentId));
        console2.log("vault LITNUP balance:", token.balanceOf(address(vault)));
        console2.log("SOLVENT bal>=principal:", token.balanceOf(address(vault)) >= principal);
        console2.log("epoch1 executed    :", oracle.executedEpoch(agentId, 1));
    }
}
