// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";

/// @notice Initial test stub. Expand before audit.
contract AgentRegistryTest is Test {
    LitnupToken token;
    AgentRegistry registry;
    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address controller = makeAddr("controller");
    address burnSink = makeAddr("burnSink");

    function setUp() public {
        token = new LitnupToken(admin);
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

        bytes32 slasherRole = registry.SLASHER_ROLE();
        vm.startPrank(admin);
        registry.grantRole(slasherRole, admin);
        registry.setSlashSink(burnSink);
        registry.slash(id, 3_000 ether);
        vm.stopPrank();

        AgentRegistry.Agent memory a = registry.getAgent(id);
        assertEq(uint256(a.bond), 7_000 ether);
        assertEq(token.balanceOf(burnSink), 3_000 ether);
    }

    function test_slashedAgentCanRecoverResidualBond() public {
        vm.prank(operator);
        uint256 id = registry.enroll(controller, 10_000 ether, bytes32(0), 1000);

        bytes32 slasherRole = registry.SLASHER_ROLE();
        vm.startPrank(admin);
        registry.grantRole(slasherRole, admin);
        registry.setSlashSink(burnSink);
        registry.slash(id, 6_000 ether); // bond -> 4000 < minBond, status becomes Slashed
        vm.stopPrank();
        assertEq(uint8(registry.getAgent(id).status), uint8(AgentRegistry.AgentStatus.Slashed));

        // Residual 4000 must be recoverable (v1 stranded it permanently).
        vm.prank(controller);
        registry.withdrawInit(id);
        vm.warp(block.timestamp + 14 days + 1);
        uint256 balBefore = token.balanceOf(controller);
        vm.prank(controller);
        registry.withdrawComplete(id);
        assertEq(token.balanceOf(controller) - balBefore, 4_000 ether);
    }

    function test_slash_revertsWhenSinkUnset() public {
        vm.prank(operator);
        uint256 id = registry.enroll(controller, 10_000 ether, bytes32(0), 1000);
        bytes32 slasherRole = registry.SLASHER_ROLE();
        vm.prank(admin);
        registry.grantRole(slasherRole, admin);
        vm.prank(admin);
        vm.expectRevert(AgentRegistry.SlashSinkNotSet.selector);
        registry.slash(id, 1_000 ether);
    }
}
