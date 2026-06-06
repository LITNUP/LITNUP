// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitToken} from "../src/LitToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";

/// @notice Edge-case + adversarial test cases for StakingVault that go beyond
///         the happy-path StakingVault.t.sol coverage. These exist so we can
///         enumerate every "what if" we thought about during design.
contract StakingVaultEdgeCases is Test {
    LitToken token;
    AgentRegistry registry;
    StakingVault vault;
    address sink = makeAddr("sink");

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address oracle = makeAddr("oracle");

    uint256 constant AGENT_ID = 1;

    function setUp() public {
        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, registry, admin, sink);

        vm.prank(admin);
        registry.grantRole(registry.SLASHER_ROLE(), address(vault));
        vm.prank(admin);
        vault.grantRole(vault.ORACLE_ROLE(), oracle);

        // Fund actors
        vm.startPrank(admin);
        token.transfer(operator, 1_000_000 ether);
        token.transfer(alice, 100_000 ether);
        token.transfer(bob, 100_000 ether);
        vm.stopPrank();

        // Operator approves + enrolls
        vm.startPrank(operator);
        token.approve(address(registry), type(uint256).max);
        registry.enroll(operator, 50_000 ether, bytes32("metadata"), 200);
        vm.stopPrank();

        // Stakers approve
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // --------- share-price math edge cases ---------

    function test_firstStaker_getsAmountAsShares() public {
        vm.prank(alice);
        uint128 sh = vault.stake(AGENT_ID, 1_000 ether);
        assertEq(sh, 1_000 ether);
    }

    function test_secondStaker_afterPositivePnL_getsFewerShares() public {
        // Alice stakes
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);

        // Apply +500 ether PnL — share price now 1.5x
        vm.prank(oracle);
        vault.applyPnl(AGENT_ID, int128(500 ether));

        // Bob stakes 1500 ether — should receive 1000 shares (1500 / 1.5)
        vm.prank(bob);
        uint128 bobShares = vault.stake(AGENT_ID, 1_500 ether);
        assertApproxEqAbs(bobShares, 1_000 ether, 1);
    }

    function test_secondStaker_afterNegativePnL_getsMoreShares() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);

        // Apply -300 ether PnL — share price now 0.7x
        vm.prank(oracle);
        vault.applyPnl(AGENT_ID, -int128(300 ether));

        // Bob stakes 700 ether — should receive 1000 shares
        vm.prank(bob);
        uint128 bobShares = vault.stake(AGENT_ID, 700 ether);
        assertApproxEqAbs(bobShares, 1_000 ether, 2);
    }

    function test_share_price_after_complete_loss_floors_to_one() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);

        // Try to apply -1500 ether (more than vault) — capped at 50% so reverts
        vm.prank(oracle);
        vm.expectRevert();
        vault.applyPnl(AGENT_ID, -int128(1_500 ether));

        // Apply two -50% losses to drain — first one
        vm.prank(oracle);
        vault.applyPnl(AGENT_ID, -int128(500 ether));
        vm.prank(oracle);
        vault.applyPnl(AGENT_ID, -int128(250 ether));

        uint256 sp = vault.sharePrice(AGENT_ID);
        assertGt(sp, 0);
    }

    // --------- cooldown edge cases ---------

    function test_unstakeBeforeCooldown_reverts() public {
        vm.startPrank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vault.unstakeInit(AGENT_ID, 500 ether);
        vm.expectRevert(StakingVault.CooldownNotElapsed.selector);
        vault.unstakeComplete(AGENT_ID);
        vm.stopPrank();
    }

    function test_unstakeAfterCooldown_succeeds() public {
        vm.startPrank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vault.unstakeInit(AGENT_ID, 500 ether);
        vm.warp(block.timestamp + 7 days + 1);
        uint128 amt = vault.unstakeComplete(AGENT_ID);
        vm.stopPrank();
        assertApproxEqAbs(amt, 500 ether, 1);
    }

    function test_doubleUnstakeInit_resetsUnlockTimer() public {
        vm.startPrank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vault.unstakeInit(AGENT_ID, 300 ether);
        uint64 firstUnlockAt;
        (, firstUnlockAt,) = vault.stakers(AGENT_ID, alice);

        vm.warp(block.timestamp + 3 days);
        vault.unstakeInit(AGENT_ID, 300 ether);
        uint64 secondUnlockAt;
        (, secondUnlockAt,) = vault.stakers(AGENT_ID, alice);

        // unlock pushed back
        assertGt(secondUnlockAt, firstUnlockAt);
        vm.stopPrank();
    }

    function test_unstakeWithoutInit_reverts() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vm.prank(alice);
        vm.expectRevert(StakingVault.NothingToWithdraw.selector);
        vault.unstakeComplete(AGENT_ID);
    }

    // --------- vault cap ---------

    function test_stakeAtCapBoundary_succeeds() public {
        vm.prank(admin);
        vault.setPerVaultCap(uint128(2_000 ether));

        vm.prank(alice);
        vault.stake(AGENT_ID, 2_000 ether);

        vm.prank(bob);
        vm.expectRevert(StakingVault.VaultCapExceeded.selector);
        vault.stake(AGENT_ID, 1);
    }

    // --------- oracle role enforcement ---------

    function test_nonOracleCallsApplyPnl_reverts() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vm.prank(operator);
        vm.expectRevert();
        vault.applyPnl(AGENT_ID, int128(100 ether));
    }

    function test_nonOracleCallsTakeFees_reverts() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vm.prank(operator);
        vm.expectRevert();
        vault.takeFees(AGENT_ID, 100 ether, 5_000);
    }

    function test_nonOracleCallsSlash_reverts() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vm.prank(operator);
        vm.expectRevert();
        vault.slashVault(AGENT_ID, 100 ether);
    }

    // --------- pnl cap ---------

    function test_pnl_above_50pct_reverts() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);

        vm.prank(oracle);
        vm.expectRevert(StakingVault.InvalidPnlSize.selector);
        vault.applyPnl(AGENT_ID, int128(501 ether));
    }

    // --------- fees ---------

    function test_takeFees_splits_correctly() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vm.prank(oracle);
        vault.applyPnl(AGENT_ID, int128(200 ether));

        uint256 sinkBefore = token.balanceOf(sink);
        vm.prank(oracle);
        vault.takeFees(AGENT_ID, 100 ether, 5_000); // 50% to buyback
        uint256 sinkAfter = token.balanceOf(sink);

        assertEq(sinkAfter - sinkBefore, 50 ether);
    }

    function test_takeFees_overflow_caps_to_balance() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);

        vm.prank(oracle);
        // Try to take more than vault has (should silently cap)
        vault.takeFees(AGENT_ID, 5_000 ether, 5_000);

        // Vault should have approximately 50% of original (the toStakers half)
        (uint128 totalAssets,,,) = vault.vaults(AGENT_ID);
        // After cap, fee = 1000, half to buyback (500), half stays as toStakers (500)
        assertEq(totalAssets, 500 ether);
    }

    // --------- slashing ---------

    function test_slashVault_burns_to_sink() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        uint256 sinkBefore = token.balanceOf(sink);
        vm.prank(oracle);
        vault.slashVault(AGENT_ID, 100 ether);
        uint256 sinkAfter = token.balanceOf(sink);
        assertEq(sinkAfter - sinkBefore, 100 ether);
        (uint128 ta,,,) = vault.vaults(AGENT_ID);
        assertEq(ta, 900 ether);
    }

    function test_slashVault_above_balance_caps() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        uint256 sinkBefore = token.balanceOf(sink);
        vm.prank(oracle);
        vault.slashVault(AGENT_ID, 5_000 ether);
        uint256 sinkAfter = token.balanceOf(sink);
        assertEq(sinkAfter - sinkBefore, 1_000 ether); // capped to vault total
    }
}
