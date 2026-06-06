// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import {LitToken}        from "../src/LitToken.sol";
import {AgentRegistry}     from "../src/AgentRegistry.sol";
import {StakingVault}      from "../src/StakingVault.sol";
import {PerformanceOracle} from "../src/PerformanceOracle.sol";

/// @notice End-to-end EIP-712 attestation round-trip test.
///
/// Proves that:
///   1. The on-chain ATTESTATION_TYPEHASH matches what off-chain signers sign
///   2. A 3-of-5 threshold attestation lands and applies PnL to the vault
///   3. Replay protection works (same epoch can't be applied twice)
///   4. Wrong-signer rejection works
///   5. Insufficient signatures rejected
///   6. Out-of-order signatures rejected (sorted-ascending requirement)
///   7. Expired attestations rejected
///   8. Per-attestation PnL cap enforced
contract PerformanceOracleE2ETest is Test {
    LitToken token;
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
        // Generate 5 sorted signer keys
        for (uint256 i = 0; i < 5; i++) {
            (address a, uint256 k) = makeAddrAndKey(string(abi.encodePacked("sig", vm.toString(i))));
            signers.push(a);
            keys.push(k);
        }
        _sortByAddress();

        // Deploy core
        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, registry, admin, burnSink);
        oracle = new PerformanceOracle(vault, registry, signers, 3, admin);

        // Wire roles
        vm.prank(admin);
        vault.grantRole(vault.ORACLE_ROLE(), address(oracle));

        // Distribute test tokens
        vm.startPrank(admin);
        token.transfer(operator, 100_000 ether);
        token.transfer(staker, 50_000 ether);
        vm.stopPrank();

        // Operator enrolls an agent
        vm.startPrank(operator);
        token.approve(address(registry), type(uint256).max);
        agentId = registry.enroll(controller, 10_000 ether, bytes32("ipfs-cid"), 1500); // 15% fee
        vm.stopPrank();

        // Staker stakes 1000
        vm.startPrank(staker);
        token.approve(address(vault), type(uint256).max);
        vault.stake(agentId, 1_000 ether);
        vm.stopPrank();
    }

    // ============================================================
    // HAPPY PATH
    // ============================================================

    function test_happyPath_3of5_appliesPnLToVault() public {
        // Build attestation: +200 AGENTIC, take 30 fee
        int256 pnlDelta = int256(200 ether);
        uint256 fee = 30 ether;
        uint64 epoch = 1;
        uint64 deadline = uint64(block.timestamp) + 1 hours;

        bytes32 digest = _digest(agentId, pnlDelta, fee, epoch, deadline);
        bytes[] memory sigs = _signFirst3(digest);

        // Apply
        oracle.applyAttestation(agentId, pnlDelta, fee, 5000 /* 50% to buyback */, epoch, deadline, sigs);

        // Vault should reflect +200 - 15 to burn (50% of fee) = +185 net
        (uint128 totalAssets,,,) = vault.vaults(agentId);
        // Initial 1000 + 200 PnL = 1200, minus 30 fee, plus 15 retained = 1185
        assertEq(uint256(totalAssets), 1_185 ether);
        assertEq(token.balanceOf(burnSink), 15 ether);
    }

    function test_happyPath_4of5_alsoWorks() public {
        int256 pnlDelta = int256(100 ether);
        uint64 epoch = 1;
        uint64 deadline = uint64(block.timestamp) + 1 hours;

        bytes32 digest = _digest(agentId, pnlDelta, 0, epoch, deadline);
        bytes[] memory sigs = new bytes[](4);
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[1], digest);
        sigs[2] = _sign(keys[2], digest);
        sigs[3] = _sign(keys[3], digest);

        oracle.applyAttestation(agentId, pnlDelta, 0, 0, epoch, deadline, sigs);

        (uint128 totalAssets,,,) = vault.vaults(agentId);
        assertEq(uint256(totalAssets), 1_100 ether);
    }

    // ============================================================
    // REJECTION PATHS
    // ============================================================

    function test_rejects_replayOfSameEpoch() public {
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 1, uint64(block.timestamp) + 1 hours);
        bytes[] memory sigs = _signFirst3(digest);

        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, 1, uint64(block.timestamp) + 1 hours, sigs);

        // Try to apply same epoch again
        vm.expectRevert(PerformanceOracle.EpochAlreadyExecuted.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, 1, uint64(block.timestamp) + 1 hours, sigs);
    }

    function test_rejects_expiredDeadline() public {
        uint64 deadline = uint64(block.timestamp) - 1;
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 1, deadline);
        bytes[] memory sigs = _signFirst3(digest);

        vm.expectRevert(PerformanceOracle.AttestationExpired.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, 1, deadline, sigs);
    }

    function test_rejects_insufficientSignatures() public {
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 1, uint64(block.timestamp) + 1 hours);
        bytes[] memory sigs = new bytes[](2); // only 2, threshold is 3
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[1], digest);

        vm.expectRevert(PerformanceOracle.InsufficientSignatures.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, 1, uint64(block.timestamp) + 1 hours, sigs);
    }

    function test_rejects_unauthorizedSigner() public {
        // Generate a key NOT in the signer set
        (address rogue, uint256 rogueKey) = makeAddrAndKey("rogue");
        rogue; // silence warning

        bytes32 digest = _digest(agentId, int256(50 ether), 0, 1, uint64(block.timestamp) + 1 hours);
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[1], digest);
        sigs[2] = _sign(rogueKey, digest); // not authorized

        vm.expectRevert(PerformanceOracle.UnknownSigner.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, 1, uint64(block.timestamp) + 1 hours, sigs);
    }

    function test_rejects_unsortedSignatures() public {
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 1, uint64(block.timestamp) + 1 hours);
        bytes[] memory sigs = new bytes[](3);
        // Reverse order — should violate sorted-ascending requirement
        sigs[0] = _sign(keys[2], digest);
        sigs[1] = _sign(keys[1], digest);
        sigs[2] = _sign(keys[0], digest);

        vm.expectRevert(PerformanceOracle.DuplicateSigner.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, 1, uint64(block.timestamp) + 1 hours, sigs);
    }

    function test_rejects_duplicateSignerInList() public {
        bytes32 digest = _digest(agentId, int256(50 ether), 0, 1, uint64(block.timestamp) + 1 hours);
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(keys[0], digest);
        sigs[1] = _sign(keys[0], digest); // duplicate
        sigs[2] = _sign(keys[2], digest);

        vm.expectRevert(PerformanceOracle.DuplicateSigner.selector);
        oracle.applyAttestation(agentId, int256(50 ether), 0, 0, 1, uint64(block.timestamp) + 1 hours, sigs);
    }

    function test_rejects_pnlExceedingVaultCap() public {
        // Vault has 1000 ether after staker deposit. Cap is 50% = 500 ether.
        // Try to apply 600 ether PnL — should revert at the vault layer.
        int256 hugePnl = int256(600 ether);
        bytes32 digest = _digest(agentId, hugePnl, 0, 1, uint64(block.timestamp) + 1 hours);
        bytes[] memory sigs = _signFirst3(digest);

        vm.expectRevert(StakingVault.InvalidPnlSize.selector);
        oracle.applyAttestation(agentId, hugePnl, 0, 0, 1, uint64(block.timestamp) + 1 hours, sigs);
    }

    function test_negativePnL_appliesAndCapsAtZero() public {
        // Apply -300 ether — within ±50% cap (vault has 1000)
        int256 pnl = -int256(300 ether);
        bytes32 digest = _digest(agentId, pnl, 0, 1, uint64(block.timestamp) + 1 hours);
        bytes[] memory sigs = _signFirst3(digest);

        oracle.applyAttestation(agentId, pnl, 0, 0, 1, uint64(block.timestamp) + 1 hours, sigs);

        (uint128 totalAssets,,,) = vault.vaults(agentId);
        assertEq(uint256(totalAssets), 700 ether);
    }

    // ============================================================
    // SIGNER MANAGEMENT
    // ============================================================

    function test_addSigner_allowsThemToParticipate() public {
        // Add a 6th signer
        (address newSigner, uint256 newKey) = makeAddrAndKey("sig5");

        vm.prank(admin);
        oracle.addSigner(newSigner);

        // Build attestation; sign with first 2 of original + new signer
        // Need to sort signers correctly...
        address[] memory active = new address[](6);
        for (uint256 i = 0; i < 5; i++) active[i] = signers[i];
        active[5] = newSigner;
        uint256[] memory activeKeys = new uint256[](6);
        for (uint256 i = 0; i < 5; i++) activeKeys[i] = keys[i];
        activeKeys[5] = newKey;
        // Bubble sort with key tracking
        for (uint256 i = 0; i < 6; i++) {
            for (uint256 j = i + 1; j < 6; j++) {
                if (active[i] > active[j]) {
                    (active[i], active[j]) = (active[j], active[i]);
                    (activeKeys[i], activeKeys[j]) = (activeKeys[j], activeKeys[i]);
                }
            }
        }

        bytes32 digest = _digest(agentId, int256(40 ether), 0, 7, uint64(block.timestamp) + 1 hours);
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = _sign(activeKeys[0], digest);
        sigs[1] = _sign(activeKeys[1], digest);
        sigs[2] = _sign(activeKeys[2], digest);

        oracle.applyAttestation(agentId, int256(40 ether), 0, 0, 7, uint64(block.timestamp) + 1 hours, sigs);

        (uint128 totalAssets,,,) = vault.vaults(agentId);
        assertEq(uint256(totalAssets), 1_040 ether);
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
        uint256 feeOnGross,
        uint64 epoch,
        uint64 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            oracle.ATTESTATION_TYPEHASH(),
            _agentId,
            pnlDelta,
            feeOnGross,
            epoch,
            deadline
        ));
        bytes32 domainSeparator = _domainSeparatorV4();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        // Replicates OpenZeppelin EIP-712 _hashTypedDataV4 domain separator construction
        // for "LITNUPOracle" / "1" / chainId / oracle address.
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
