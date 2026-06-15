// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Edge-case + adversarial tests for the solvent StakingVault. In v2, attested PnL never
///         changes redeemable share price; only slashing reduces principal. Yield is real USDC.
contract StakingVaultEdgeCases is Test {
    LitnupToken token;
    MockERC20 usdc;
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
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, usdc, registry, admin, sink);

        bytes32 slasherRole = registry.SLASHER_ROLE();
        bytes32 oracleRole = vault.ORACLE_ROLE();
        vm.startPrank(admin);
        registry.grantRole(slasherRole, address(vault));
        vault.grantRole(oracleRole, oracle);
        vm.stopPrank();

        vm.startPrank(admin);
        token.transfer(operator, 1_000_000 ether);
        token.transfer(alice, 100_000 ether);
        token.transfer(bob, 100_000 ether);
        vm.stopPrank();

        vm.startPrank(operator);
        token.approve(address(registry), type(uint256).max);
        registry.enroll(operator, 50_000 ether, bytes32("metadata"), 200);
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);

        // Operator funds USDC fees.
        usdc.mint(operator, 1_000_000e6);
        vm.prank(operator);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _principal() internal view returns (uint128 p) {
        (p,,,,,) = vault.vaults(AGENT_ID);
    }

    function _assertSolvent() internal view {
        assertGe(token.balanceOf(address(vault)), _principal(), "insolvent");
    }

    // --------- share-price math: PnL never moves price ---------

    function test_firstStaker_getsAmountAsShares() public {
        vm.prank(alice);
        uint128 sh = vault.stake(AGENT_ID, 1_000 ether);
        assertEq(sh, 1_000 ether);
    }

    function test_recordPnl_doesNotChangeSharePriceOrShares() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);

        vm.prank(oracle);
        vault.recordPnl(AGENT_ID, int256(500 ether));
        assertEq(vault.sharePrice(AGENT_ID), 1 ether);

        // Bob staking 1000 still gets 1000 shares (no phantom appreciation).
        vm.prank(bob);
        uint128 bobShares = vault.stake(AGENT_ID, 1_000 ether);
        assertEq(bobShares, 1_000 ether);
        _assertSolvent();
    }

    function test_negativePnl_alsoDoesNotChangePrice() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vm.prank(oracle);
        vault.recordPnl(AGENT_ID, -int256(300 ether));
        assertEq(vault.sharePrice(AGENT_ID), 1 ether);
        _assertSolvent();
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
        _assertSolvent();
    }

    function test_doubleUnstakeInit_resetsUnlockTimer() public {
        vm.startPrank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        vault.unstakeInit(AGENT_ID, 300 ether);
        (,, uint64 firstUnlockAt,,) = vault.stakers(AGENT_ID, alice);

        vm.warp(block.timestamp + 3 days);
        vault.unstakeInit(AGENT_ID, 300 ether);
        (,, uint64 secondUnlockAt,,) = vault.stakers(AGENT_ID, alice);

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

    function test_nonOracleCallsRecordPnl_reverts() public {
        vm.prank(operator);
        vm.expectRevert();
        vault.recordPnl(AGENT_ID, int256(100 ether));
    }

    function test_nonOracleCallsTakeFees_reverts() public {
        vm.prank(operator);
        vm.expectRevert();
        vault.takeFees(AGENT_ID, 100e6, 5_000, operator);
    }

    function test_nonOracleCallsSlash_reverts() public {
        vm.prank(operator);
        vm.expectRevert();
        vault.slashVault(AGENT_ID, 100 ether);
    }

    // --------- USDC fees ---------

    function test_takeFees_splitsRealUsdc() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);

        uint256 sinkBefore = usdc.balanceOf(sink);
        vm.prank(oracle);
        vault.takeFees(AGENT_ID, 100e6, 5_000, operator); // 50% to buyback
        assertEq(usdc.balanceOf(sink) - sinkBefore, 50e6);
        assertEq(vault.pendingRewards(AGENT_ID, alice), 50e6);

        // Principal untouched.
        assertEq(_principal(), 1_000 ether);
        _assertSolvent();
    }

    function test_takeFees_noStakers_allToBuyback() public {
        uint256 sinkBefore = usdc.balanceOf(sink);
        vm.prank(oracle);
        vault.takeFees(AGENT_ID, 100e6, 0, operator);
        assertEq(usdc.balanceOf(sink) - sinkBefore, 100e6);
    }

    // --------- slashing ---------

    function test_slashVault_burns_to_sink() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        uint256 sinkBefore = token.balanceOf(sink);
        vm.prank(oracle);
        vault.slashVault(AGENT_ID, 100 ether);
        assertEq(token.balanceOf(sink) - sinkBefore, 100 ether);
        assertEq(_principal(), 900 ether);
        _assertSolvent();
    }

    function test_slashVault_above_balance_caps() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether);
        uint256 sinkBefore = token.balanceOf(sink);
        vm.prank(oracle);
        vault.slashVault(AGENT_ID, 5_000 ether);
        assertEq(token.balanceOf(sink) - sinkBefore, 1_000 ether); // capped to principal
        assertEq(_principal(), 0);
        _assertSolvent();
    }

    function test_slash_thenNewStaker_getsMoreSharesForSameTokens() public {
        vm.prank(alice);
        vault.stake(AGENT_ID, 1_000 ether); // price 1.0

        vm.prank(oracle);
        vault.slashVault(AGENT_ID, 500 ether); // price now 0.5

        // Bob stakes 500 tokens; at price 0.5 he should receive ~1000 shares.
        vm.prank(bob);
        uint128 bobShares = vault.stake(AGENT_ID, 500 ether);
        assertApproxEqAbs(bobShares, 1_000 ether, 2);
        _assertSolvent();
    }
}
