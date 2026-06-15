// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";

contract VotingEscrowTest is Test {
    LitnupToken token;
    VotingEscrow ve;
    address admin = makeAddr("admin");
    address alice = makeAddr("alice");

    uint64 constant WEEK = 7 days;

    function setUp() public {
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        ve = new VotingEscrow(token, admin);

        vm.prank(admin);
        token.transfer(alice, 100_000 ether);
        vm.prank(alice);
        token.approve(address(ve), type(uint256).max);
    }

    function test_createLock_happyPath() public {
        uint64 unlockAt = uint64(block.timestamp + 365 days);
        vm.prank(alice);
        ve.createLock(10_000 ether, unlockAt);

        (uint128 amt, uint64 unlockTime, ) = ve.lockInfo(alice);
        assertEq(uint256(amt), 10_000 ether);
        // Should round down to week boundary
        assertEq(unlockTime % WEEK, 0);
        assertLe(unlockTime, unlockAt);
    }

    function test_createLock_revertsTooShort() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.LockTooShort.selector);
        ve.createLock(1_000 ether, uint64(block.timestamp + 1 days));
    }

    function test_createLock_revertsTooLong() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.LockTooLong.selector);
        ve.createLock(1_000 ether, uint64(block.timestamp + 5 * 365 days));
    }

    function test_balanceOf_decaysLinearly() public {
        // Lock 10,000 for 4 years = should give max weight (≈ amount)
        uint64 unlockAt = uint64(block.timestamp + 4 * 365 days);
        vm.prank(alice);
        ve.createLock(10_000 ether, unlockAt);

        uint256 weight0 = ve.balanceOf(alice);
        // Should be close to but maybe slightly less than 10_000 (week-rounding)
        assertGt(weight0, 9_900 ether);
        assertLe(weight0, 10_000 ether);

        // Fast-forward 2 years — weight should be roughly half
        vm.warp(block.timestamp + 2 * 365 days);
        uint256 weight2y = ve.balanceOf(alice);
        assertApproxEqRel(weight2y, weight0 / 2, 0.01e18); // within 1%

        // Fast-forward to expiry — weight = 0
        vm.warp(block.timestamp + 3 * 365 days);
        assertEq(ve.balanceOf(alice), 0);
    }

    function test_extendLock() public {
        vm.prank(alice);
        ve.createLock(10_000 ether, uint64(block.timestamp + 365 days));

        uint64 newUnlock = uint64(block.timestamp + 2 * 365 days);
        vm.prank(alice);
        ve.extendLock(newUnlock);

        (, uint64 unlockTime, ) = ve.lockInfo(alice);
        // Week-aligned, less than or equal newUnlock
        assertLe(unlockTime, newUnlock);
        assertGt(unlockTime, uint64(block.timestamp + 365 days));
    }

    function test_increaseAmount_topsUp() public {
        vm.prank(alice);
        ve.createLock(10_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(alice);
        ve.increaseAmount(5_000 ether);

        (uint128 amt, , ) = ve.lockInfo(alice);
        assertEq(uint256(amt), 15_000 ether);
    }

    function test_withdraw_requiresExpiry() public {
        vm.prank(alice);
        ve.createLock(10_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(alice);
        vm.expectRevert(VotingEscrow.LockNotExpired.selector);
        ve.withdraw();

        vm.warp(block.timestamp + 366 days);
        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        ve.withdraw();
        assertEq(token.balanceOf(alice) - balBefore, 10_000 ether);
    }

    function test_cannotCreateTwoLocks() public {
        vm.prank(alice);
        ve.createLock(10_000 ether, uint64(block.timestamp + 365 days));

        vm.prank(alice);
        vm.expectRevert(VotingEscrow.LockExists.selector);
        ve.createLock(5_000 ether, uint64(block.timestamp + 365 days));
    }
}
