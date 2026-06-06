// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal Uniswap V3-like swap router interface (works for Aerodrome/Velodrome v3 too).
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IBurnable {
    function burn(uint256 amount) external;
}

/// @title BuybackBurn
/// @notice Receives fee revenue (in $LIT, USDC, or other accepted tokens), swaps non-native
///         to $LIT via the router, and burns it. Burns are batched and execute on `swapAndBurn()`
///         which can be called by anyone (gas-paid by caller, optional bounty).
contract BuybackBurn is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    IERC20 public immutable alphaToken;
    ISwapRouter public router;

    /// @notice Whitelisted input tokens (e.g. USDC) and their fee tier for the router pool.
    mapping(address => uint24) public inputTokenFeeTier;

    /// @notice Caller bounty: tiny rebate from swap to gas-pay the keeper.
    uint16 public callerBountyBps = 10; // 0.1%
    /// @notice Slippage cap on swap (bps).
    uint16 public maxSlippageBps = 200; // 2%
    /// @notice Cooldown between swaps to prevent gaming.
    uint64 public lastSwapAt;
    uint64 public minSwapInterval = 4 hours;

    // -------- events --------

    event SwapAndBurn(address indexed token, uint256 inAmount, uint256 burned, uint256 bounty);
    event RouterUpdated(address router);
    event InputTokenAllowed(address token, uint24 fee);
    event ConfigUpdated();

    // -------- errors --------

    error TokenNotAllowed();
    error CooldownActive();
    error NoBalance();

    constructor(IERC20 _alpha, ISwapRouter _router, address _admin) {
        alphaToken = _alpha;
        router = _router;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
    }

    // -------- main --------

    /// @notice Burn $LIT currently in the contract. No swap needed if already in token.
    function burnDirect() public nonReentrant {
        uint256 bal = alphaToken.balanceOf(address(this));
        if (bal == 0) revert NoBalance();
        IBurnable(address(alphaToken)).burn(bal);
        emit SwapAndBurn(address(alphaToken), bal, bal, 0);
    }

    /// @notice Swap a whitelisted input token into $LIT and burn the proceeds.
    /// @param tokenIn Whitelisted ERC20 (e.g. USDC)
    /// @param amountIn How much to swap; 0 = full balance
    /// @param expectedAmountOut Off-chain quoted output (callers protect against MEV)
    function swapAndBurn(address tokenIn, uint256 amountIn, uint256 expectedAmountOut) external nonReentrant {
        if (block.timestamp < lastSwapAt + minSwapInterval) revert CooldownActive();
        uint24 fee = inputTokenFeeTier[tokenIn];
        if (fee == 0) revert TokenNotAllowed();

        uint256 bal = IERC20(tokenIn).balanceOf(address(this));
        if (amountIn == 0 || amountIn > bal) amountIn = bal;
        if (amountIn == 0) revert NoBalance();

        uint256 minOut = (expectedAmountOut * (10_000 - maxSlippageBps)) / 10_000;

        IERC20(tokenIn).approve(address(router), 0);
        IERC20(tokenIn).approve(address(router), amountIn);

        uint256 amountOut = router.exactInputSingle(ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: address(alphaToken),
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp + 600,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        }));

        // Caller bounty
        uint256 bounty = (amountOut * callerBountyBps) / 10_000;
        uint256 toBurn = amountOut - bounty;
        if (bounty > 0) alphaToken.safeTransfer(msg.sender, bounty);
        IBurnable(address(alphaToken)).burn(toBurn);

        lastSwapAt = uint64(block.timestamp);
        emit SwapAndBurn(tokenIn, amountIn, toBurn, bounty);
    }

    // -------- config --------

    function setRouter(ISwapRouter r) external onlyRole(CONFIG_ROLE) {
        router = r;
        emit RouterUpdated(address(r));
    }

    function setInputToken(address token, uint24 fee) external onlyRole(CONFIG_ROLE) {
        inputTokenFeeTier[token] = fee;
        emit InputTokenAllowed(token, fee);
    }

    function setParams(uint16 _bountyBps, uint16 _slippageBps, uint64 _minInterval) external onlyRole(CONFIG_ROLE) {
        require(_bountyBps <= 200 && _slippageBps <= 1_000 && _minInterval <= 7 days, "cap");
        callerBountyBps = _bountyBps;
        maxSlippageBps = _slippageBps;
        minSwapInterval = _minInterval;
        emit ConfigUpdated();
    }
}
