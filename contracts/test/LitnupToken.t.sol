// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";

/// @notice LitnupToken unit tests.
contract LitnupTokenTest is Test {
    LitnupToken token;
    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");

    function setUp() public {
        token = new LitnupToken(treasury);
        vm.prank(treasury);
        token.mintInitialSupply();
    }

    function test_initialMint_sendsAllToTreasury() public view {
        assertEq(token.totalSupply(), token.MAX_SUPPLY());
        assertEq(token.balanceOf(treasury), token.MAX_SUPPLY());
    }

    function test_cannotMintTwice() public {
        vm.prank(treasury);
        vm.expectRevert(LitnupToken.InitialMintAlreadyDone.selector);
        token.mintInitialSupply();
    }

    function test_burn_reducesSupply() public {
        vm.prank(treasury);
        token.transfer(alice, 1000 ether);
        vm.prank(alice);
        token.burn(400 ether);
        assertEq(token.totalSupply(), token.MAX_SUPPLY() - 400 ether);
        assertEq(token.balanceOf(alice), 600 ether);
    }

    function test_burnFrom_requiresAllowance() public {
        vm.prank(treasury);
        token.transfer(alice, 1000 ether);
        // Without approval, this should revert
        vm.expectRevert();
        token.burnFrom(alice, 100 ether);
    }

    function test_votes_delegateToSelf() public {
        vm.prank(treasury);
        token.transfer(alice, 1000 ether);
        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 1000 ether);
    }
}
