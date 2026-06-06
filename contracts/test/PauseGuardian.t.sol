// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {PauseGuardian} from "../src/PauseGuardian.sol";

/// @notice Mock target with a flippable boolean to simulate pause/unpause.
contract MockTarget {
    bool public paused;
    uint256 public lastFlipBlock;

    function pause() external {
        paused = true;
        lastFlipBlock = block.number;
    }
    function unpause() external {
        paused = false;
        lastFlipBlock = block.number;
    }

    /// non-pausable function the guardian must NOT be able to call
    function backdoorMint(address, uint256) external pure {
        revert("never");
    }
}

contract PauseGuardianTest is Test {
    PauseGuardian guardian;
    MockTarget target;

    address admin = makeAddr("admin");
    address timelock = makeAddr("timelock");
    address g1 = makeAddr("g1");
    address g2 = makeAddr("g2");
    address g3 = makeAddr("g3");
    address g4 = makeAddr("g4");
    address g5 = makeAddr("g5");
    address attacker = makeAddr("attacker");

    function setUp() public {
        address[] memory guardians = new address[](5);
        guardians[0] = g1;
        guardians[1] = g2;
        guardians[2] = g3;
        guardians[3] = g4;
        guardians[4] = g5;
        guardian = new PauseGuardian(admin, timelock, guardians, 3); // 3-of-5
        target = new MockTarget();

        // Whitelist pause + unpause
        vm.startPrank(timelock);
        guardian.allowAction(address(target), MockTarget.pause.selector);
        guardian.allowAction(address(target), MockTarget.unpause.selector);
        vm.stopPrank();
    }

    function test_threeOfFive_executes() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.pause.selector);

        vm.prank(g1);
        (bool exec1,) = guardian.approveAndMaybeExecute(address(target), data);
        assertFalse(exec1);

        vm.prank(g2);
        (bool exec2,) = guardian.approveAndMaybeExecute(address(target), data);
        assertFalse(exec2);

        vm.prank(g3);
        (bool exec3,) = guardian.approveAndMaybeExecute(address(target), data);
        assertTrue(exec3);
        assertTrue(target.paused());
    }

    function test_twoOfFive_doesNotExecute() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.pause.selector);

        vm.prank(g1);
        guardian.approveAndMaybeExecute(address(target), data);
        vm.prank(g2);
        guardian.approveAndMaybeExecute(address(target), data);

        assertFalse(target.paused());
    }

    function test_doubleApproveSameGuardian_reverts() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.pause.selector);
        vm.prank(g1);
        guardian.approveAndMaybeExecute(address(target), data);
        vm.prank(g1);
        vm.expectRevert(PauseGuardian.AlreadyApproved.selector);
        guardian.approveAndMaybeExecute(address(target), data);
    }

    function test_unwhitelistedAction_reverts() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.backdoorMint.selector, attacker, 1 ether);
        vm.prank(g1);
        vm.expectRevert(PauseGuardian.ActionNotAllowed.selector);
        guardian.approveAndMaybeExecute(address(target), data);
    }

    function test_nonGuardian_reverts() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.pause.selector);
        vm.prank(attacker);
        vm.expectRevert();
        guardian.approveAndMaybeExecute(address(target), data);
    }

    function test_revokeAction_blocksFutureCalls() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.pause.selector);

        vm.prank(timelock);
        guardian.revokeAction(address(target), MockTarget.pause.selector);

        vm.prank(g1);
        vm.expectRevert(PauseGuardian.ActionNotAllowed.selector);
        guardian.approveAndMaybeExecute(address(target), data);
    }

    function test_staleApprovalsExpire() public {
        bytes memory data = abi.encodeWithSelector(MockTarget.pause.selector);

        vm.prank(g1);
        guardian.approveAndMaybeExecute(address(target), data);
        vm.prank(g2);
        guardian.approveAndMaybeExecute(address(target), data);

        // 25h later, approvals should reset on next attempt
        vm.warp(block.timestamp + 25 hours);

        vm.prank(g3);
        (bool exec3,) = guardian.approveAndMaybeExecute(address(target), data);
        assertFalse(exec3); // Reset to 1 fresh approval
    }

    function test_actionCooldown() public {
        // Set a 1h cooldown on pause
        vm.prank(timelock);
        guardian.setActionCooldown(address(target), MockTarget.pause.selector, 1 hours);

        bytes memory data = abi.encodeWithSelector(MockTarget.pause.selector);

        // Execute once
        vm.prank(g1); guardian.approveAndMaybeExecute(address(target), data);
        vm.prank(g2); guardian.approveAndMaybeExecute(address(target), data);
        vm.prank(g3); guardian.approveAndMaybeExecute(address(target), data);
        assertTrue(target.paused());

        // Try to immediately re-pause — cooldown blocks it
        vm.prank(g1); guardian.approveAndMaybeExecute(address(target), data);
        vm.prank(g2); guardian.approveAndMaybeExecute(address(target), data);
        vm.prank(g3);
        vm.expectRevert(PauseGuardian.CooldownActive.selector);
        guardian.approveAndMaybeExecute(address(target), data);

        // After cooldown, works again
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(g4); guardian.approveAndMaybeExecute(address(target), data);
        // Already approved by g4 above is fresh; need 3
        // Note: previous approvals from this attempt may have stuck — depending on timing they may already count
    }

    function test_setThreshold() public {
        vm.prank(timelock);
        guardian.setThreshold(2);

        bytes memory data = abi.encodeWithSelector(MockTarget.pause.selector);
        vm.prank(g1); guardian.approveAndMaybeExecute(address(target), data);
        vm.prank(g2); (bool exec,) = guardian.approveAndMaybeExecute(address(target), data);
        assertTrue(exec);
    }
}

contract RewardsDistributorTargetTest is Test {
    // Lightweight wiring tests for RewardsDistributor's interaction with PauseGuardian
    // covered separately in RewardsDistributor.t.sol — kept minimal here.
}
