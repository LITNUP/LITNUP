// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";

contract InsuranceFundTest is Test {
    LitnupToken token;
    InsuranceFund fund;

    address admin = makeAddr("admin");
    address disburser = makeAddr("disburser");
    address victim = makeAddr("victim");
    address alice = makeAddr("alice");

    function setUp() public {
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        fund = new InsuranceFund(token, admin);
        bytes32 disburserRole = fund.DISBURSER_ROLE();
        vm.prank(admin);
        fund.grantRole(disburserRole, disburser);

        // Seed the fund
        vm.prank(admin);
        token.transfer(alice, 5_000_000 ether);
        vm.prank(alice);
        token.approve(address(fund), type(uint256).max);
        vm.prank(alice);
        fund.deposit(token, 5_000_000 ether);
    }

    function test_deposit_increasesBalance() public view {
        assertEq(fund.balanceOf(token), 5_000_000 ether);
    }

    function test_disburse_underCap() public {
        vm.prank(disburser);
        fund.disburse(token, victim, 500_000 ether, "compensation - vault X exploit");
        assertEq(token.balanceOf(victim), 500_000 ether);
    }

    function test_disburse_revertsAboveCap() public {
        vm.prank(disburser);
        fund.disburse(token, victim, 800_000 ether, "first payment");

        // Cap is 1M; second 300k breaks it
        vm.prank(disburser);
        vm.expectRevert(InsuranceFund.EpochCapExceeded.selector);
        fund.disburse(token, victim, 300_000 ether, "second");
    }

    function test_disburse_resetAfterEpoch() public {
        vm.prank(disburser);
        fund.disburse(token, victim, 1_000_000 ether, "first");

        // Move past epoch
        vm.warp(block.timestamp + 8 days);

        vm.prank(disburser);
        fund.disburse(token, victim, 1_000_000 ether, "next epoch");
        assertEq(token.balanceOf(victim), 2_000_000 ether);
    }

    function test_disburse_revertsWhenPaused() public {
        vm.prank(admin);
        fund.setPaused(true);
        vm.prank(disburser);
        vm.expectRevert(InsuranceFund.PausedNow.selector);
        fund.disburse(token, victim, 1 ether, "x");
    }

    function test_onlyDisburserCanDisburse() public {
        vm.prank(victim);
        vm.expectRevert();
        fund.disburse(token, victim, 1 ether, "x");
    }
}
