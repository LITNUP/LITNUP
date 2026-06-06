// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitToken} from "../src/LitToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";

contract StakingVaultTest is Test {
    LitToken token;
    AgentRegistry registry;
    StakingVault vault;

    address admin = makeAddr("admin");
    address oracle = makeAddr("oracle");
    address operator = makeAddr("operator");
    address controller = makeAddr("controller");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address burnSink = makeAddr("burnSink");

    uint256 agentId;

    function setUp() public {
        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, registry, admin, burnSink);

        vm.prank(admin);
        vault.grantRole(vault.ORACLE_ROLE(), oracle);

        // Distribute tokens
        vm.startPrank(admin);
        token.transfer(operator, 100_000 ether);
        token.transfer(alice, 50_000 ether);
        token.transfer(bob, 50_000 ether);
        vm.stopPrank();

        // Enroll an agent
        vm.startPrank(operator);
        token.approve(address(registry), type(uint256).max);
        agentId = registry.enroll(controller, 10_000 ether, bytes32(0), 1000);
        vm.stopPrank();

        // Approve vault for stakers
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    function test_stake_firstStakerGetsOneToOneShares() public {
        vm.prank(alice);
        uint128 shares = vault.stake(agentId, 1000 ether);
        assertEq(uint256(shares), 1000 ether);

        (uint128 totalAssets, uint128 totalShares,,) = vault.vaults(agentId);
        assertEq(uint256(totalAssets), 1000 ether);
        assertEq(uint256(totalShares), 1000 ether);
    }

    function test_stake_pnlScalesSharePrice() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);

        // Apply +500 PnL
        vm.prank(oracle);
        vault.applyPnl(agentId, 500 ether);

        // Bob stakes 1500 — should get 1000 shares since totalAssets is now 1500 / shares is 1000
        vm.prank(bob);
        uint128 bobShares = vault.stake(agentId, 1500 ether);
        assertApproxEqAbs(uint256(bobShares), 1000 ether, 1);
    }

    function test_unstake_requiresCooldown() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);

        vm.prank(alice);
        vault.unstakeInit(agentId, 1000 ether);

        vm.prank(alice);
        vm.expectRevert(StakingVault.CooldownNotElapsed.selector);
        vault.unstakeComplete(agentId);

        vm.warp(block.timestamp + 7 days + 1);
        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.unstakeComplete(agentId);
        assertEq(token.balanceOf(alice) - balBefore, 1000 ether);
    }

    function test_pnlCap_revertsOnHugeDelta() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);

        // 51% gain should revert (cap is 50%)
        vm.prank(oracle);
        vm.expectRevert(StakingVault.InvalidPnlSize.selector);
        vault.applyPnl(agentId, 510 ether);
    }

    function test_takeFees_splitToBuybackAndStakers() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);

        vm.prank(oracle);
        vault.applyPnl(agentId, 200 ether);

        // Take 100 ether fee, 50% to buyback
        vm.prank(oracle);
        vault.takeFees(agentId, 100 ether, 5000);

        // 50 should land in burn sink
        assertEq(token.balanceOf(burnSink), 50 ether);

        // Vault assets should be 1200 - 50 (toStakers stays in vault, toBuyback leaves)
        (uint128 totalAssets,,,) = vault.vaults(agentId);
        assertEq(uint256(totalAssets), 1150 ether);
    }
}
