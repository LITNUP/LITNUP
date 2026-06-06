// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitToken} from "../src/LitToken.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";

/// @notice Edge-case tests for VotingEscrow targeting the linear-decay math,
///         lock extension semantics, and multi-user vote-weight aggregation.
contract VotingEscrowEdgeCases is Test {
    LitToken token;
    VotingEscrow ve;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");
    address carol = makeAddr("carol");

    function setUp() public {
        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();
        ve = new VotingEscrow(token, admin);

        for (uint256 i = 0; i < 3; i++) {
            address a = [alice, bob, carol][i];
            vm.prank(admin);
            token.transfer(a, 100_000 ether);
            vm.prank(a);
            token.approve(address(ve), type(uint256).max);
        }
    }

    function test_zeroAmountLock_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        ve.createLock(0, uint64(block.timestamp + 52 weeks));
    }

    function test_lockBeyondMax_reverts() public {
        // MAX_LOCK is typically 4*52 weeks (4 years)
        vm.prank(alice);
        vm.expectRevert();
        ve.createLock(1_000 ether, uint64(block.timestamp + 5 * 365 days));
    }

    function test_lockInPast_reverts() public {
        vm.warp(1_000_000);
        vm.prank(alice);
        vm.expectRevert();
        ve.createLock(1_000 ether, uint64(block.timestamp - 1));
    }

    function test_decay_halfwayPoint_isApproxHalfWeight() public {
        uint64 unlockAt = uint64(block.timestamp + 100 weeks);
        vm.prank(alice);
        ve.createLock(10_000 ether, unlockAt);

        uint256 wStart = ve.balanceOf(alice);
        vm.warp(block.timestamp + 50 weeks);
        uint256 wMid = ve.balanceOf(alice);

        // Should be roughly half (within 5% tolerance)
        assertApproxEqRel(wMid, wStart / 2, 0.05e18);
    }

    function test_decay_atUnlock_isZero() public {
        uint64 unlockAt = uint64(block.timestamp + 52 weeks);
        vm.prank(alice);
        ve.createLock(1_000 ether, unlockAt);

        vm.warp(uint256(unlockAt) + 1);
        assertEq(ve.balanceOf(alice), 0);
    }

    function test_increaseAmount_addsWeight() public {
        uint64 unlockAt = uint64(block.timestamp + 52 weeks);
        vm.startPrank(alice);
        ve.createLock(1_000 ether, unlockAt);
        uint256 wBefore = ve.balanceOf(alice);
        ve.increaseAmount(1_000 ether);
        uint256 wAfter = ve.balanceOf(alice);
        vm.stopPrank();

        // Doubled amount → roughly doubled weight (allowing a small drift from time passage)
        assertApproxEqRel(wAfter, wBefore * 2, 0.01e18);
    }

    function test_extendLock_increasesWeight() public {
        uint64 unlockAt = uint64(block.timestamp + 26 weeks);
        vm.startPrank(alice);
        ve.createLock(1_000 ether, unlockAt);
        uint256 wBefore = ve.balanceOf(alice);
        ve.extendLock(uint64(block.timestamp + 104 weeks));
        uint256 wAfter = ve.balanceOf(alice);
        vm.stopPrank();
        assertGt(wAfter, wBefore);
    }

    function test_extendLock_shortenAttempt_reverts() public {
        uint64 unlockAt = uint64(block.timestamp + 52 weeks);
        vm.startPrank(alice);
        ve.createLock(1_000 ether, unlockAt);
        vm.expectRevert();
        ve.extendLock(uint64(block.timestamp + 26 weeks));
        vm.stopPrank();
    }

    function test_withdrawBeforeUnlock_reverts() public {
        uint64 unlockAt = uint64(block.timestamp + 52 weeks);
        vm.startPrank(alice);
        ve.createLock(1_000 ether, unlockAt);
        vm.expectRevert();
        ve.withdraw();
        vm.stopPrank();
    }

    function test_withdraw_returnsExactAmount() public {
        uint64 unlockAt = uint64(block.timestamp + 52 weeks);
        vm.startPrank(alice);
        ve.createLock(5_000 ether, unlockAt);
        uint256 balBefore = token.balanceOf(alice);
        vm.warp(uint256(unlockAt) + 1);
        ve.withdraw();
        uint256 balAfter = token.balanceOf(alice);
        vm.stopPrank();
        assertEq(balAfter - balBefore, 5_000 ether);
    }

    function test_multipleUsers_aggregateLocked() public {
        uint64 unlockAt = uint64(block.timestamp + 52 weeks);
        vm.prank(alice); ve.createLock(1_000 ether, unlockAt);
        vm.prank(bob);   ve.createLock(2_000 ether, unlockAt);
        vm.prank(carol); ve.createLock(3_000 ether, unlockAt);
        assertEq(ve.totalLocked(), 6_000 ether);
    }

    function test_doubleCreateLock_reverts() public {
        uint64 unlockAt = uint64(block.timestamp + 52 weeks);
        vm.startPrank(alice);
        ve.createLock(1_000 ether, unlockAt);
        vm.expectRevert();
        ve.createLock(500 ether, unlockAt);
        vm.stopPrank();
    }

    function test_solvent_invariant_holds_after_ops() public {
        vm.prank(alice); ve.createLock(1_000 ether, uint64(block.timestamp + 52 weeks));
        vm.prank(bob);   ve.createLock(2_000 ether, uint64(block.timestamp + 78 weeks));
        vm.prank(alice); ve.increaseAmount(500 ether);

        // Contract balance must equal totalLocked
        assertEq(token.balanceOf(address(ve)), ve.totalLocked());
    }
}
