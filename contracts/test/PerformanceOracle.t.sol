// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {PerformanceOracle} from "../src/PerformanceOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Signer-management unit tests. The full EIP-712 attestation round-trip lives in
///         PerformanceOracleE2E.t.sol.
contract PerformanceOracleTest is Test {
    LitnupToken token;
    MockERC20 usdc;
    AgentRegistry registry;
    StakingVault vault;
    PerformanceOracle oracle;

    address admin = makeAddr("admin");
    address burnSink = makeAddr("burnSink");

    address[] signers;
    uint256[] signerKeys;

    function setUp() public {
        for (uint256 i = 0; i < 5; i++) {
            (address s, uint256 k) = makeAddrAndKey(string(abi.encodePacked("signer", vm.toString(i))));
            signers.push(s);
            signerKeys.push(k);
        }

        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, usdc, registry, admin, burnSink);

        _sortAddresses(signers, signerKeys);

        oracle = new PerformanceOracle(vault, registry, signers, 3, admin);

        bytes32 oracleRole = vault.ORACLE_ROLE();
        vm.prank(admin);
        vault.grantRole(oracleRole, address(oracle));
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
        assertEq(oracle.threshold(), 3);
    }

    function test_removeSigner_lowersThresholdIfNeeded() public {
        // Remove down to 2 signers; threshold (3) must clamp to signer count.
        vm.startPrank(admin);
        oracle.removeSigner(signers[0]);
        oracle.removeSigner(signers[1]);
        oracle.removeSigner(signers[2]);
        vm.stopPrank();
        assertEq(oracle.signerCount(), 2);
        assertEq(oracle.threshold(), 2);
    }

    function test_setThreshold_revertsAboveSignerCount() public {
        vm.prank(admin);
        vm.expectRevert(PerformanceOracle.InvalidThreshold.selector);
        oracle.setThreshold(6);
    }

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
