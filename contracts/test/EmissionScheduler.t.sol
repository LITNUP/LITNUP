// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {EmissionScheduler} from "../src/EmissionScheduler.sol";

contract EmissionSchedulerTest is Test {
    LitnupToken token;
    EmissionScheduler sched;

    address admin = makeAddr("admin");
    address rew1  = makeAddr("rew1");
    address rew2  = makeAddr("rew2");
    address rew3  = makeAddr("rew3");

    uint128 constant TOTAL = 170_000_000 ether; // 17% of supply
    uint64  constant DURATION = 730 days;       // M0–M24

    function setUp() public {
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        // Seed scheduler at start
        sched = new EmissionScheduler(token, uint64(block.timestamp), DURATION, TOTAL, admin);

        // Treasury (admin) funds the scheduler
        vm.prank(admin);
        token.transfer(address(sched), TOTAL);
    }

    function test_emittedToDate_zeroAtStart() public view {
        assertEq(sched.emittedToDate(), 0);
    }

    function test_emittedToDate_linear() public {
        vm.warp(block.timestamp + DURATION / 4);
        // ~25% emitted
        assertApproxEqRel(sched.emittedToDate(), TOTAL / 4, 0.001e18);
    }

    function test_emittedToDate_full() public {
        vm.warp(block.timestamp + DURATION + 1 days);
        assertEq(sched.emittedToDate(), TOTAL);
    }

    function test_pull_revertsBeforeWeightsSet() public {
        vm.prank(rew1);
        vm.expectRevert(EmissionScheduler.NotRecipient.selector);
        sched.pull();
    }

    function test_pull_revertsIfWeightsDontSumTo10000() public {
        vm.prank(admin);
        sched.setRecipient(rew1, 5000);
        // Only 50% allocated; pull should revert
        vm.warp(block.timestamp + DURATION / 4);
        vm.prank(rew1);
        vm.expectRevert(EmissionScheduler.WeightsMustSumTo10000.selector);
        sched.pull();
    }

    function test_pull_singleRecipient_full() public {
        vm.prank(admin);
        sched.setRecipient(rew1, 10_000); // 100%
        vm.warp(block.timestamp + DURATION / 4);

        vm.prank(rew1);
        uint128 amt = sched.pull();
        assertApproxEqRel(amt, TOTAL / 4, 0.001e18);
        assertEq(token.balanceOf(rew1), amt);
    }

    function test_pull_threeRecipients_proportionalSplit() public {
        vm.startPrank(admin);
        sched.setRecipient(rew1, 5000); // 50%
        sched.setRecipient(rew2, 3000); // 30%
        sched.setRecipient(rew3, 2000); // 20%
        vm.stopPrank();

        vm.warp(block.timestamp + DURATION / 2);

        vm.prank(rew1);
        uint128 a1 = sched.pull();
        vm.prank(rew2);
        uint128 a2 = sched.pull();
        vm.prank(rew3);
        uint128 a3 = sched.pull();

        // Total emitted at half = TOTAL/2; 50/30/20 split
        assertApproxEqRel(a1, (TOTAL / 2) * 5000 / 10_000, 0.001e18);
        assertApproxEqRel(a2, (TOTAL / 2) * 3000 / 10_000, 0.001e18);
        assertApproxEqRel(a3, (TOTAL / 2) * 2000 / 10_000, 0.001e18);
    }

    function test_pull_idempotentPullsZero() public {
        vm.prank(admin);
        sched.setRecipient(rew1, 10_000);
        vm.warp(block.timestamp + DURATION / 2);
        vm.prank(rew1);
        sched.pull();
        // Same block — should revert with NothingClaimable
        vm.prank(rew1);
        vm.expectRevert(EmissionScheduler.NothingClaimable.selector);
        sched.pull();
    }

    function test_setRecipient_deactivate() public {
        vm.prank(admin);
        sched.setRecipient(rew1, 10_000);
        // Deactivate
        vm.prank(admin);
        sched.setRecipient(rew1, 0);
        // Now totalWeightBps is 0
        assertEq(sched.totalWeightBps(), 0);
    }

    function test_claimable_returnsZeroIfWeightsIncomplete() public {
        vm.prank(admin);
        sched.setRecipient(rew1, 5000); // only 50%
        vm.warp(block.timestamp + DURATION / 4);
        assertEq(sched.claimable(rew1), 0);
    }
}
