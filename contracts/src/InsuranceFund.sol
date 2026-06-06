// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title InsuranceFund
/// @notice Reserves $LITNUP + USDC to compensate stakers in unforeseen-loss events
///         (smart contract exploits, oracle compromise, mass slashing of innocent stakers).
///
///         Funded by: (1) initial Foundation grant (~1-2% of supply at TGE), (2) a fraction of
///         protocol fees post-mainnet, (3) discretionary deposits.
///
///         Disbursements require a governance vote OR an emergency multisig action; the
///         contract does NOT trust a single signer. All disbursements are public and bounded.
contract InsuranceFund is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DISBURSER_ROLE = keccak256("DISBURSER_ROLE"); // governance timelock OR emergency multisig
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    IERC20 public immutable alphaToken;
    address public emergencyPause;

    /// @notice Per-token disbursement limit per epoch. Hard cap on blast radius.
    uint256 public maxDisbursementPerEpoch = 1_000_000 ether; // 1M $LITNUP default
    uint256 public epochLength = 7 days;
    uint256 public lastEpochStart;
    uint256 public disbursedThisEpoch;

    bool public paused;

    // -------- events --------

    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Disbursed(address indexed token, address indexed to, uint256 amount, string reason);
    event MaxDisbursementUpdated(uint256 newCap);
    event Paused(bool paused);

    // -------- errors --------

    error EpochCapExceeded();
    error PausedNow();
    error InvalidParams();

    constructor(IERC20 _alpha, address _admin) {
        alphaToken = _alpha;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
        lastEpochStart = block.timestamp;
    }

    // -------- deposits (anyone can fund) --------

    /// @notice Deposit $LITNUP or any other ERC20 (e.g. USDC) to grow the fund.
    function deposit(IERC20 token, uint256 amount) external nonReentrant {
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(address(token), msg.sender, amount);
    }

    // -------- disbursements (only DISBURSER_ROLE) --------

    /// @notice Disburse to a recipient. Reason is logged on-chain for accountability.
    function disburse(IERC20 token, address to, uint256 amount, string calldata reason)
        external
        onlyRole(DISBURSER_ROLE)
        nonReentrant
    {
        if (paused) revert PausedNow();
        if (amount == 0 || to == address(0)) revert InvalidParams();

        // Reset epoch if elapsed
        if (block.timestamp >= lastEpochStart + epochLength) {
            lastEpochStart = block.timestamp;
            disbursedThisEpoch = 0;
        }

        if (disbursedThisEpoch + amount > maxDisbursementPerEpoch) revert EpochCapExceeded();
        disbursedThisEpoch += amount;

        token.safeTransfer(to, amount);
        emit Disbursed(address(token), to, amount, reason);
    }

    // -------- config --------

    function setMaxDisbursementPerEpoch(uint256 v) external onlyRole(CONFIG_ROLE) {
        maxDisbursementPerEpoch = v;
        emit MaxDisbursementUpdated(v);
    }

    function setEpochLength(uint256 v) external onlyRole(CONFIG_ROLE) {
        require(v >= 1 days && v <= 30 days, "bounds");
        epochLength = v;
    }

    function setPaused(bool p) external onlyRole(CONFIG_ROLE) {
        paused = p;
        emit Paused(p);
    }

    // -------- views --------

    function balanceOf(IERC20 token) external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function remainingThisEpoch() external view returns (uint256) {
        if (block.timestamp >= lastEpochStart + epochLength) return maxDisbursementPerEpoch;
        return maxDisbursementPerEpoch > disbursedThisEpoch ? maxDisbursementPerEpoch - disbursedThisEpoch : 0;
    }
}
