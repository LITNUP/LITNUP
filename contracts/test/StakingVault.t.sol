// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract StakingVaultTest is Test {
    LitnupToken token;
    MockERC20 usdc;
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
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        usdc = new MockERC20("USD Coin", "USDC", 6);

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, usdc, registry, admin, burnSink);

        bytes32 oracleRole = vault.ORACLE_ROLE();
        vm.prank(admin);
        vault.grantRole(oracleRole, oracle);

        vm.startPrank(admin);
        token.transfer(operator, 100_000 ether);
        token.transfer(alice, 50_000 ether);
        token.transfer(bob, 50_000 ether);
        vm.stopPrank();

        vm.startPrank(operator);
        token.approve(address(registry), type(uint256).max);
        agentId = registry.enroll(controller, 10_000 ether, bytes32(0), 1000);
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);

        // Operator funds USDC for performance fees and approves the vault to pull.
        usdc.mint(operator, 1_000_000e6);
        vm.prank(operator);
        usdc.approve(address(vault), type(uint256).max);
    }

    // -------- core solvency property --------

    /// Total real $LITNUP held by the vault must always cover the sum of agent principals.
    function _assertSolvent() internal view {
        (uint128 principal,,,,,) = vault.vaults(agentId);
        assertGe(token.balanceOf(address(vault)), principal, "vault insolvent");
    }

    function test_stake_firstStakerGetsOneToOneShares() public {
        vm.prank(alice);
        uint128 shares = vault.stake(agentId, 1000 ether);
        assertEq(uint256(shares), 1000 ether);

        (uint128 principal, uint128 totalShares,,,,) = vault.vaults(agentId);
        assertEq(uint256(principal), 1000 ether);
        assertEq(uint256(totalShares), 1000 ether);
        _assertSolvent();
    }

    /// Attested PnL must NOT change redeemable share price (the v1 insolvency bug is gone).
    function test_recordPnl_doesNotInflateSharePrice() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);

        uint256 priceBefore = vault.sharePrice(agentId);
        vm.prank(oracle);
        vault.recordPnl(agentId, 500 ether);
        assertEq(vault.sharePrice(agentId), priceBefore, "price must not move on PnL");

        // Bob staking 1000 still gets 1000 shares — no phantom appreciation.
        vm.prank(bob);
        uint128 bobShares = vault.stake(agentId, 1000 ether);
        assertEq(uint256(bobShares), 1000 ether);

        (, , , , int256 cumPnl, ) = vault.vaults(agentId);
        assertEq(cumPnl, 500 ether, "PnL recorded for reputation");
        _assertSolvent();
    }

    function test_unstake_requiresCooldown_andReturnsPrincipal() public {
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
        _assertSolvent();
    }

    // -------- real USDC fee yield --------

    function test_takeFees_splitsRealUsdcToBuybackAndStakers() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);

        // 1000 USDC fee, 50% to buyback, 50% streams to stakers.
        vm.prank(oracle);
        vault.takeFees(agentId, 1000e6, 5000, operator);

        // Buyback sink received real USDC.
        assertEq(usdc.balanceOf(burnSink), 500e6);

        // Alice (sole staker) can claim ~500 USDC.
        assertEq(vault.pendingRewards(agentId, alice), 500e6);
        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        vault.claimRewards(agentId);
        assertEq(usdc.balanceOf(alice) - before, 500e6);

        // Staking principal is untouched by fees — still fully solvent.
        (uint128 principal,,,,,) = vault.vaults(agentId);
        assertEq(uint256(principal), 1000 ether);
        _assertSolvent();
    }

    function test_takeFees_proRataAcrossStakers() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);
        vm.prank(bob);
        vault.stake(agentId, 3000 ether);

        // 4000 USDC fee, all to stakers.
        vm.prank(oracle);
        vault.takeFees(agentId, 4000e6, 0, operator);

        // Alice 25%, Bob 75%.
        assertApproxEqAbs(vault.pendingRewards(agentId, alice), 1000e6, 1);
        assertApproxEqAbs(vault.pendingRewards(agentId, bob), 3000e6, 1);
    }

    function test_takeFees_noStakers_allToBuyback() public {
        // No one staked yet; whole fee routes to buyback (nothing stranded).
        vm.prank(oracle);
        vault.takeFees(agentId, 1000e6, 0, operator);
        assertEq(usdc.balanceOf(burnSink), 1000e6);
    }

    // -------- slashing --------

    function test_slash_reducesPrincipalAndSharePrice() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);

        vm.prank(oracle);
        vault.slashVault(agentId, 200 ether);

        // Real tokens moved to burn sink; price dropped to 0.8.
        assertEq(token.balanceOf(burnSink), 200 ether);
        assertEq(vault.sharePrice(agentId), 0.8 ether);
        _assertSolvent();

        // Alice redeems her reduced principal.
        vm.prank(alice);
        vault.unstakeInit(agentId, 1000 ether);
        vm.warp(block.timestamp + 7 days + 1);
        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.unstakeComplete(agentId);
        assertEq(token.balanceOf(alice) - balBefore, 800 ether);
        _assertSolvent();
    }

    // -------- guards --------

    function test_stake_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(StakingVault.ZeroAmount.selector);
        vault.stake(agentId, 0);
    }

    function test_stake_revertsOverVaultCap() public {
        vm.prank(admin);
        vault.setPerVaultCap(500 ether);
        vm.prank(alice);
        vm.expectRevert(StakingVault.VaultCapExceeded.selector);
        vault.stake(agentId, 1000 ether);
    }

    function test_onlyOracleCanRecordPnlAndFees() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.recordPnl(agentId, 1);

        vm.prank(alice);
        vm.expectRevert();
        vault.takeFees(agentId, 1e6, 0, operator);
    }

    function test_pause_blocksStakeButAllowsExit() public {
        vm.prank(alice);
        vault.stake(agentId, 1000 ether);

        vm.prank(admin);
        vault.pause();

        vm.prank(bob);
        vm.expectRevert();
        vault.stake(agentId, 1000 ether);

        // Exit still works while paused.
        vm.prank(alice);
        vault.unstakeInit(agentId, 1000 ether);
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(alice);
        vault.unstakeComplete(agentId);
        _assertSolvent();
    }
}
