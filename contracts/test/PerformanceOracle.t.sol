// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitToken} from "../src/LitToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {PerformanceOracle} from "../src/PerformanceOracle.sol";

/// @notice Stub. Extend with full EIP-712 attestation flow before audit.
contract PerformanceOracleTest is Test {
    LitToken token;
    AgentRegistry registry;
    StakingVault vault;
    PerformanceOracle oracle;

    address admin = makeAddr("admin");
    address burnSink = makeAddr("burnSink");

    address[] signers;
    uint256[] signerKeys;

    function setUp() public {
        // Generate 5 signer keypairs
        for (uint256 i = 0; i < 5; i++) {
            (address s, uint256 k) = makeAddrAndKey(string(abi.encodePacked("signer", vm.toString(i))));
            signers.push(s);
            signerKeys.push(k);
        }

        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, registry, admin, burnSink);

        // Sort signers ascending (oracle requires sorted recovery)
        _sortAddresses(signers, signerKeys);

        oracle = new PerformanceOracle(vault, registry, signers, 3, admin);

        vm.prank(admin);
        vault.grantRole(vault.ORACLE_ROLE(), address(oracle));
    }

    function test_signers_initializedCorrectly() public view {
        address[] memory got = oracle.getSigners();
        assertEq(got.length, 5);
        assertEq(oracle.threshold(), 3);
    }

    function test_addSigner_increasesSet() public {
        address newSigner = makeAddr("newSigner");
        vm.prank(admin);
        oracle.addSigner(newSigner);
        assertTrue(oracle.isSigner(newSigner));
    }

    function test_removeSigner_compactsArray() public {
        vm.prank(admin);
        oracle.removeSigner(signers[2]);
        assertFalse(oracle.isSigner(signers[2]));
        // Threshold should remain 3 (still 4 signers >= 3)
        assertEq(oracle.threshold(), 3);
    }

    // TODO: full EIP-712 signed attestation roundtrip — requires building digest and signing.
    // Add before audit. Sketch below.
    /*
    function test_applyAttestation_happyPath() public {
        // 1. Set up agent + stake
        // 2. Build EIP-712 digest from (agentId, pnlDelta, feeOnGross, epoch, deadline)
        // 3. Sign with 3 keys, sort by signer address
        // 4. Call oracle.applyAttestation(...)
        // 5. Assert vault state changed correctly
    }
    */

    function _sortAddresses(address[] storage arr, uint256[] storage keys) internal {
        uint256 n = arr.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                if (arr[i] > arr[j]) {
                    (arr[i], arr[j]) = (arr[j], arr[i]);
                    (keys[i], keys[j]) = (keys[j], keys[i]);
                }
            }
        }
    }
}
