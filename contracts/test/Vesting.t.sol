// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {Vesting} from "../src/Vesting.sol";

contract VestingTest is Test {
    LitnupToken token;
    Vesting vesting;
    address admin = makeAddr("admin");
    address alice = makeAddr("alice");

    function setUp() public {
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();
        vesting = new Vesting(token, admin);
        vm.prank(admin);
        token.approve(address(vesting), type(uint256).max);
    }

    function test_create_pullsTokens() public {
        vm.prank(admin);
        vesting.createSchedule(alice, 1000 ether, 0, 365 days, 4 * 365 days, false);
        assertEq(token.balanceOf(address(vesting)), 1000 ether);
        assertEq(vesting.totalReserved(), 1000 ether);
    }

    function test_release_zeroBeforeCliff() public {
        vm.prank(admin);
        vesting.createSchedule(alice, 1000 ether, uint64(block.timestamp), 365 days, 4 * 365 days, false);

        // Before cliff
        vm.warp(block.timestamp + 100 days);
        assertEq(vesting.releasable(alice), 0);
        vm.prank(alice);
        vm.expectRevert(Vesting.NothingVested.selector);
        vesting.release();
    }

    function test_release_linearAfterCliff() public {
        uint64 start = uint64(block.timestamp);
        vm.prank(admin);
        vesting.createSchedule(alice, 1000 ether, start, 365 days, 4 * 365 days, false);

        // At cliff exactly
        vm.warp(start + 365 days);
        // Vested = 1000 * (365 / 1460) ≈ 250
        uint256 expected = 1000 ether * 365 days / (4 * 365 days);
        assertApproxEqAbs(vesting.releasable(alice), expected, 1);

        // Halfway through total period
        vm.warp(start + 2 * 365 days);
        assertApproxEqRel(vesting.vestedAmount(alice), 500 ether, 0.01e18);

        // End of vesting
        vm.warp(start + 4 * 365 days + 1);
        assertEq(vesting.vestedAmount(alice), 1000 ether);

        vm.prank(alice);
        uint128 released = vesting.release();
        assertEq(uint256(released), 1000 ether);
        assertEq(token.balanceOf(alice), 1000 ether);
    }

    function test_revoke_returnsUnvested() public {
        uint64 start = uint64(block.timestamp);
        vm.prank(admin);
        vesting.createSchedule(alice, 1000 ether, start, 365 days, 4 * 365 days, true);

        // Halfway
        vm.warp(start + 2 * 365 days);
        vm.prank(admin);
        uint128 reclaimed = vesting.revoke(alice);
        // Vested ≈ 500; reclaimed ≈ 500
        assertApproxEqRel(uint256(reclaimed), 500 ether, 0.01e18);

        // Beneficiary can still claim vested portion
        vm.prank(alice);
        vesting.release();
        assertApproxEqRel(token.balanceOf(alice), 500 ether, 0.01e18);
    }

    function test_revoke_revertsIfNotRevocable() public {
        vm.prank(admin);
        vesting.createSchedule(alice, 1000 ether, 0, 365 days, 4 * 365 days, false);
        vm.prank(admin);
        vm.expectRevert(Vesting.NotRevocable.selector);
        vesting.revoke(alice);
    }

    function test_cannotCreateTwoSchedules() public {
        vm.prank(admin);
        vesting.createSchedule(alice, 1000 ether, 0, 100 days, 365 days, false);
        vm.prank(admin);
        vm.expectRevert(Vesting.ScheduleAlreadyExists.selector);
        vesting.createSchedule(alice, 500 ether, 0, 100 days, 365 days, false);
    }
}
