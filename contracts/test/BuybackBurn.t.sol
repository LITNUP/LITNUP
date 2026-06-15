// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitnupToken} from "../src/LitnupToken.sol";
import {BuybackBurn, ISwapRouter} from "../src/BuybackBurn.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MockRouter is ISwapRouter {
    LitnupToken public alpha;
    constructor(LitnupToken _a) { alpha = _a; }
    function exactInputSingle(ExactInputSingleParams calldata p) external payable returns (uint256 amountOut) {
        // 1:1 mock swap (test only): pull tokenIn, send equal $LITNUP out.
        amountOut = p.amountIn;
        alpha.transfer(p.recipient, amountOut);
    }
}

contract BuybackBurnTest is Test {
    LitnupToken token;
    MockERC20 usdc;
    BuybackBurn buyback;
    MockRouter router;

    address admin = makeAddr("admin");
    address keeper = makeAddr("keeper");
    address rando = makeAddr("rando");

    function setUp() public {
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        router = new MockRouter(token);

        // Seed router with $LITNUP liquidity for swap-and-burn tests
        vm.prank(admin);
        token.transfer(address(router), 100_000 ether);

        buyback = new BuybackBurn(token, ISwapRouter(address(router)), admin);

        bytes32 keeperRole = buyback.KEEPER_ROLE();
        vm.prank(admin);
        buyback.grantRole(keeperRole, keeper);
        vm.prank(admin);
        buyback.setInputToken(address(usdc), 500); // whitelist USDC with a fee tier
    }

    function test_burnDirect_burnsContractBalance() public {
        vm.prank(admin);
        token.transfer(address(buyback), 1000 ether);

        uint256 supplyBefore = token.totalSupply();
        buyback.burnDirect();
        assertEq(token.totalSupply(), supplyBefore - 1000 ether);
        assertEq(token.balanceOf(address(buyback)), 0);
    }

    function test_burnDirect_revertsOnZero() public {
        vm.expectRevert(BuybackBurn.NoBalance.selector);
        buyback.burnDirect();
    }

    function test_swapAndBurn_keeperSwapsAndBurns() public {
        // Note: MockRouter swaps 1:1, so 1000 USDC -> 1000 "LITNUP" units out.
        usdc.mint(address(buyback), 1000); // 1000 base units of USDC (6dp)
        // Fund router with matching $LITNUP already done in setUp.

        uint256 supplyBefore = token.totalSupply();
        vm.prank(keeper);
        buyback.swapAndBurn(address(usdc), 0, 1000); // expectedAmountOut = 1000

        // 1000 LITNUP units swapped in, minus 0.1% bounty to keeper, rest burned.
        uint256 bounty = (1000 * buyback.callerBountyBps()) / 10_000;
        assertEq(token.totalSupply(), supplyBefore - (1000 - bounty));
        assertEq(token.balanceOf(keeper), bounty);
    }

    function test_swapAndBurn_revertsForNonKeeper() public {
        usdc.mint(address(buyback), 1000);
        vm.prank(rando);
        vm.expectRevert();
        buyback.swapAndBurn(address(usdc), 0, 1000);
    }

    function test_swapAndBurn_revertsOnZeroQuote() public {
        usdc.mint(address(buyback), 1000);
        vm.prank(keeper);
        vm.expectRevert(BuybackBurn.InvalidQuote.selector);
        buyback.swapAndBurn(address(usdc), 0, 0); // expectedAmountOut = 0 (the v1 sandwich vector)
    }

    function test_swapAndBurn_revertsForUnlistedToken() public {
        MockERC20 other = new MockERC20("X", "X", 18);
        other.mint(address(buyback), 1 ether);
        vm.prank(keeper);
        vm.expectRevert(BuybackBurn.TokenNotAllowed.selector);
        buyback.swapAndBurn(address(other), 0, 1 ether);
    }

    function test_pause_blocksBurns() public {
        vm.prank(admin);
        buyback.pause();
        vm.prank(admin);
        token.transfer(address(buyback), 1000 ether);
        vm.expectRevert();
        buyback.burnDirect();
    }
}
