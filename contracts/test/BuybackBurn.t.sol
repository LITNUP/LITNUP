// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {LitToken} from "../src/LitToken.sol";
import {BuybackBurn, ISwapRouter} from "../src/BuybackBurn.sol";

contract MockRouter is ISwapRouter {
    LitToken public alpha;
    constructor(LitToken _a) { alpha = _a; }
    function exactInputSingle(ExactInputSingleParams calldata p) external payable returns (uint256 amountOut) {
        // 1:1 mock swap, ignoring tokenIn
        amountOut = p.amountIn;
        alpha.transfer(p.recipient, amountOut);
    }
}

contract BuybackBurnTest is Test {
    LitToken token;
    BuybackBurn buyback;
    MockRouter router;

    address admin = makeAddr("admin");

    function setUp() public {
        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        router = new MockRouter(token);

        // Seed router with $LIT liquidity for swap-and-burn tests
        vm.prank(admin);
        token.transfer(address(router), 100_000 ether);

        buyback = new BuybackBurn(token, ISwapRouter(address(router)), admin);
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

    // swapAndBurn fully tested with a fork-test against real router; mock test pending.
}
