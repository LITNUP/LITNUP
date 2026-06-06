// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitToken} from "../src/LitToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

/// @notice Initial test stub. Expand before audit.
contract AgentRegistryTest is Test {
    LitToken token;
    AgentRegistry registry;
    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address controller = makeAddr("controller");
    address burnSink = makeAddr("burnSink");

    function setUp() public {
        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        registry = new AgentRegistry(token, admin);

        // Fund operator and approve
        vm.prank(admin);
        token.transfer(operator, 100_000 ether);
        vm.prank(operator);
        token.approve(address(registry), type(uint256).max);
    }

    function test_enroll_happyPath() public {
        vm.prank(operator);
        uint256 id = registry.enroll(controller, 10_000 ether, bytes32("ipfs-cid"), 1000);
        assertEq(id, 1);

        AgentRegistry.Agent memory a = registry.getAgent(id);
        assertEq(a.controller, controller);
        assertEq(uint256(a.bond), 10_000 ether);
        assertEq(a.protocolFeeBps, 1000);
        assertTrue(registry.isActive(id));
    }

    function test_enroll_revertsWhenBondTooSmall() public {
        vm.prank(operator);
        vm.expectRevert(AgentRegistry.InsufficientBond.selector);
        registry.enroll(controller, 100 ether, bytes32(0), 1000);
    }

    function test_enroll_revertsWhenFeeTooHigh() public {
        vm.prank(operator);
        vm.expectRevert(AgentRegistry.FeeTooHigh.selector);
        registry.enroll(controller, 10_000 ether, bytes32(0), 6000); // > 50%
    }

    function test_topUpBond_increasesBond() public {
        vm.prank(operator);
        uint256 id = registry.enroll(controller, 10_000 ether, bytes32(0), 1000);

        vm.prank(operator);
        registry.topUpBond(id, 5_000 ether);

        AgentRegistry.Agent memory a = registry.getAgent(id);
        assertEq(uint256(a.bond), 15_000 ether);
    }

    function test_withdraw_requiresUnbondingPeriod() public {
        vm.prank(operator);
        uint256 id = registry.enroll(controller, 10_000 ether, bytes32(0), 1000);

        vm.prank(controller);
        registry.withdrawInit(id);

        // Cannot complete immediately
        vm.prank(controller);
        vm.expectRevert(AgentRegistry.UnbondingNotComplete.selector);
        registry.withdrawComplete(id);

        // After unbonding period
        vm.warp(block.timestamp + 14 days + 1);
        uint256 balBefore = token.balanceOf(controller);
        vm.prank(controller);
        registry.withdrawComplete(id);
        assertEq(token.balanceOf(controller) - balBefore, 10_000 ether);
    }

    function test_slash_burnsBond() public {
        vm.prank(operator);
        uint256 id = registry.enroll(controller, 10_000 ether, bytes32(0), 1000);

        vm.prank(admin);
        registry.grantRole(registry.SLASHER_ROLE(), admin);

        vm.prank(admin);
        registry.slash(id, 3_000 ether, burnSink);

        AgentRegistry.Agent memory a = registry.getAgent(id);
        assertEq(uint256(a.bond), 7_000 ether);
        assertEq(token.balanceOf(burnSink), 3_000 ether);
    }
}
