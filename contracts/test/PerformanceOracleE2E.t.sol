// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import {LitnupToken}        from "../src/LitnupToken.sol";
import {AgentRegistry}     from "../src/AgentRegistry.sol";
import {StakingVault}      from "../src/StakingVault.sol";
import {PerformanceOracle} from "../src/PerformanceOracle.sol";
import {MockERC20}         from "./mocks/MockERC20.sol";

/// @notice End-to-end EIP-712 attestation round-trip test (solvent model).
///
/// Proves that:
///   1. The on-chain ATTESTATION_TYPEHASH (incl. toBuybackBps + feePayer) matches what signers sign
///   2. A 3-of-5 threshold attestation records PnL (reputation) and distributes a REAL USDC fee
///   3. Attested PnL never changes redeemable principal (solvency preserved)
///   4. Replay / expiry / unknown-signer / unsorted / insufficient-sig rejection
///   5. Slashing requires an independent threshold-signed action (applySlash)
contract PerformanceOracleE2ETest is Test {
    LitnupToken token;
    MockERC20 usdc;
    AgentRegistry registry;
    StakingVault vault;
    PerformanceOracle oracle;

    address admin   = makeAddr("admin");
    address burnSink = makeAddr("burnSink");
    address operator = makeAddr("operator");
    address controller = makeAddr("controller");
    address staker = makeAddr("staker");

    address[] signers;
    uint256[] keys;

    uint256 agentId;

    function setUp() public {
        for (uint256 i = 0; i < 5; i++) {
            (address a, uint256 k) = makeAddrAndKey(string(abi.encodePacked("sig", vm.toString(i))));
            signers.push(a);
            keys.push(k);
        }
        _sortByAddress();

        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, usdc, registry, admin, burnSink);
        oracle = new PerformanceOracle(vault, registry, signers, 3, admin);

        bytes32 oracleRole = vault.ORACLE_ROLE();
        vm.prank(admin);
        vault.grantRole(oracleRole, address(oracle));

        vm.startPrank(admin);
        token.transfer(operator, 100_000 ether);
        token.transfer(staker, 50_000 ether);
        vm.stopPrank();

        vm.startPrank(operator);
        token.approve(address(registry), type(uint256).max);
        agentId = registry.enroll(controller, 10_000 ether, bytes32("ipfs-cid"), 1500); // 15% fee
        vm.stopPrank();

        vm.startPrank(staker);
        token.approve(address(vault), type(uint256).max);
        vault.stake(agentId, 1_000 ether);
        vm.stopPrank();

        // Operator funds USDC and approves the vault to pull performance fees.
        usdc.mint(operator, 1_000_000e6);
        vm.prank(operator);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ============================================================
    // HAPPY PATH
    // ============================================================

    function test_happyPath_recordsPnlAndDistributesUsdcFee() public {
        int256 pnlDelta = int256(200 ether);
        uint256 fee = 30e6; // 30 USDC
        uint16 toBuybackBps = 5000;
        uint64 epoch = 1;
        uint64 deadline = uint64(block.timestamp) + 1 hours;

        bytes32 digest = _digest(agentId, pnlDelta, fee, toBuybackBps, operator, epoch, deadline);
        bytes[] memory sigs = _signFirst3(digest);

        oracle.applyAttestation(agentId, pnlDelta, fee, toBuybackBps, operator, epoch, deadline, sigs);

        // PnL recorded for reputation; principal untouched (solvency).
        (uint128 principal,,,, int256 cumPnl,) = vault.vaults(agentId);
        assertEq(uint256(principal), 1_000 ether, "principal unchanged by PnL");
        assertEq(cumPnl, 200 ether, "PnL recorded");

        // Real USDC split: 15 to buyback, 15 to staker.
        assertEq(usdc.balanceOf(burnSink), 15e6);
        assertEq(vault.pendingRewards(agentId, staker), 15e6);

        assertGe(token.balanceOf(address(vault)), principal, "solvent");
    }

    function test_happyPath_4of5_alsoWorks() public {
        int256 pnlDelta = int256(100 ether);
        uint64 epoch = 1;
        uint64 deadline = uint64(block.timestamp) + 1 hours;

        bytes32 digest = _digest(agentId, pnlDelta, 0, 0, operator, epoch, deadline);
        bytes[] memory sigs = new bytes[](4);
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[1], digest);
        sigs[2] = _sign(keys[2], digest);
        sigs[3] = _sign(keys[3], digest);

        oracle.applyAttestation(agentId, pnlDelta, 0, 0, operator, epoch, deadline, sigs);

        (,,,, int256 cumPnl,) = vault.vaults(agentId);
        assertEq(cumPnl, 100 ether);
    }

    // ============================================================
    // REJECTION PATHS
    // ============================================================

    function test_rejects_replayOfSameEpoch() public {
        uint64 dl = uint64(block.timestamp) + 1 hours;
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 0, operator, 1, dl);
        bytes[] memory sigs = _signFirst3(digest);

        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, operator, 1, dl, sigs);

        vm.expectRevert(PerformanceOracle.EpochAlreadyExecuted.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, operator, 1, dl, sigs);
    }

    function test_rejects_expiredDeadline() public {
        uint64 deadline = uint64(block.timestamp) - 1;
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 0, operator, 1, deadline);
        bytes[] memory sigs = _signFirst3(digest);

        vm.expectRevert(PerformanceOracle.AttestationExpired.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, operator, 1, deadline, sigs);
    }

    function test_rejects_insufficientSignatures() public {
        uint64 dl = uint64(block.timestamp) + 1 hours;
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 0, operator, 1, dl);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[1], digest);

        vm.expectRevert(PerformanceOracle.InsufficientSignatures.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, operator, 1, dl, sigs);
    }

    function test_rejects_unauthorizedSigner() public {
        (, uint256 rogueKey) = makeAddrAndKey("rogue");
        uint64 dl = uint64(block.timestamp) + 1 hours;
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 0, operator, 1, dl);
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[1], digest);
        sigs[2] = _sign(rogueKey, digest);

        vm.expectRevert();
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, operator, 1, dl, sigs);
    }

    function test_rejects_unsortedSignatures() public {
        uint64 dl = uint64(block.timestamp) + 1 hours;
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 0, operator, 1, dl);
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(keys[2], digest);
        sigs[1] = _sign(keys[1], digest);
        sigs[2] = _sign(keys[0], digest);

        vm.expectRevert(PerformanceOracle.DuplicateSigner.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, operator, 1, dl, sigs);
    }

    // ============================================================
    // SLASHING (independent threshold-signed action)
    // ============================================================

    function test_applySlash_requiresThresholdAndReducesPrincipal() public {
        uint64 dl = uint64(block.timestamp) + 1 hours;
        bytes32 digest = _slashDigest(agentId, 300 ether, 1, dl);
        bytes[] memory sigs = _signFirst3(digest);

        oracle.applySlash(agentId, 300 ether, 1, dl, sigs);

        (uint128 principal,,,,,) = vault.vaults(agentId);
        assertEq(uint256(principal), 700 ether);
        assertEq(token.balanceOf(burnSink), 300 ether);
        assertGe(token.balanceOf(address(vault)), principal, "solvent after slash");
    }

    function test_applySlash_rejectsInsufficientSignatures() public {
        uint64 dl = uint64(block.timestamp) + 1 hours;
        bytes32 digest = _slashDigest(agentId, 300 ether, 1, dl);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[1], digest);

        vm.expectRevert(PerformanceOracle.InsufficientSignatures.selector);
        oracle.applySlash(agentId, 300 ether, 1, dl, sigs);
    }

    // ============================================================
    // SIGNER MANAGEMENT
    // ============================================================

    function test_addSigner_allowsThemToParticipate() public {
        (address newSigner, uint256 newKey) = makeAddrAndKey("sig5");
        vm.prank(admin);
        oracle.addSigner(newSigner);

        address[] memory active = new address[](6);
        uint256[] memory activeKeys = new uint256[](6);
        for (uint256 i = 0; i < 5; i++) { active[i] = signers[i]; activeKeys[i] = keys[i]; }
        active[5] = newSigner; activeKeys[5] = newKey;
        for (uint256 i = 0; i < 6; i++) {
            for (uint256 j = i + 1; j < 6; j++) {
                if (active[i] > active[j]) {
                    (active[i], active[j]) = (active[j], active[i]);
                    (activeKeys[i], activeKeys[j]) = (activeKeys[j], activeKeys[i]);
                }
            }
        }

        uint64 dl = uint64(block.timestamp) + 1 hours;
        bytes32 digest = _digest(agentId, int256(40 ether), 0, 0, operator, 7, dl);
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(activeKeys[0], digest);
        sigs[1] = _sign(activeKeys[1], digest);
        sigs[2] = _sign(activeKeys[2], digest);

        oracle.applyAttestation(agentId, int256(40 ether), 0, 0, operator, 7, dl, sigs);

        (,,,, int256 cumPnl,) = vault.vaults(agentId);
        assertEq(cumPnl, 40 ether);
    }

    // ============================================================
    // INTERNAL HELPERS
    // ============================================================

    function _sortByAddress() internal {
        for (uint256 i = 0; i < signers.length; i++) {
            for (uint256 j = i + 1; j < signers.length; j++) {
                if (signers[i] > signers[j]) {
                    (signers[i], signers[j]) = (signers[j], signers[i]);
                    (keys[i], keys[j]) = (keys[j], keys[i]);
                }
            }
        }
    }

    function _digest(
        uint256 _agentId,
        int256 pnlDelta,
        uint256 feeAmount,
        uint16 toBuybackBps,
        address feePayer,
        uint64 epoch,
        uint64 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            oracle.ATTESTATION_TYPEHASH(),
            _agentId,
            pnlDelta,
            feeAmount,
            toBuybackBps,
            feePayer,
            epoch,
            deadline
        ));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    function _slashDigest(uint256 _agentId, uint256 amount, uint64 epoch, uint64 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(
            oracle.SLASH_TYPEHASH(), _agentId, amount, epoch, deadline
        ));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("LITNUPOracle")),
            keccak256(bytes("1")),
            block.chainid,
            address(oracle)
        ));
    }

    function _sign(uint256 key, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signFirst3(bytes32 digest) internal returns (bytes[] memory) {
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[1], digest);
        sigs[2] = _sign(keys[2], digest);
        return sigs;
    }
}
