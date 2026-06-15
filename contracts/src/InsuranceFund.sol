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

    IERC20 public immutable litnupToken;

    /// @notice Per-token disbursement cap per epoch (decimal-aware — set in each token's own units).
    /// @dev v1 used a single 18-decimal cap shared across ALL tokens, which was meaningless for a
    ///      6-decimal token like USDC. Unconfigured tokens default to 0 (disbursement blocked).
    mapping(address => uint256) public maxDisbursementPerEpoch;
    mapping(address => uint256) public disbursedThisEpoch;
    mapping(address => uint256) public lastEpochStart;
    uint256 public epochLength = 7 days;

    bool public paused;

    // -------- events --------

    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Disbursed(address indexed token, address indexed to, uint256 amount, string reason);
    event MaxDisbursementUpdated(address indexed token, uint256 newCap);
    event Paused(bool paused);

    // -------- errors --------

    error EpochCapExceeded();
    error PausedNow();
    error InvalidParams();

    constructor(IERC20 _litnup, address _admin) {
        litnupToken = _litnup;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
        // Seed a sane default cap for the protocol's own 18-decimal token. Other tokens (e.g. USDC)
        // must be configured explicitly via setMaxDisbursementPerEpoch in their own decimals.
        maxDisbursementPerEpoch[address(_litnup)] = 1_000_000 ether;
        lastEpochStart[address(_litnup)] = block.timestamp;
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
        address t = address(token);

        // Reset this token's epoch if elapsed
        if (block.timestamp >= lastEpochStart[t] + epochLength) {
            lastEpochStart[t] = block.timestamp;
            disbursedThisEpoch[t] = 0;
        }

        if (disbursedThisEpoch[t] + amount > maxDisbursementPerEpoch[t]) revert EpochCapExceeded();
        disbursedThisEpoch[t] += amount;

        token.safeTransfer(to, amount);
        emit Disbursed(t, to, amount, reason);
    }

    // -------- config --------

    function setMaxDisbursementPerEpoch(IERC20 token, uint256 v) external onlyRole(CONFIG_ROLE) {
        maxDisbursementPerEpoch[address(token)] = v;
        emit MaxDisbursementUpdated(address(token), v);
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

    function remainingThisEpoch(IERC20 token) external view returns (uint256) {
        address t = address(token);
        uint256 cap = maxDisbursementPerEpoch[t];
        if (block.timestamp >= lastEpochStart[t] + epochLength) return cap;
        return cap > disbursedThisEpoch[t] ? cap - disbursedThisEpoch[t] : 0;
    }
}
