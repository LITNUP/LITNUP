// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title VotingEscrow (veLITNUP)
/// @notice Lock $LITNUP for up to MAX_LOCK to receive boosted governance weight + fee rebates.
///         Linear decay model: weight = locked * (timeLeft / MAX_LOCK).
///         Inspired by Curve's veCRV. Simplified: no transfer NFTs in v1, integer math, no checkpoints.
contract VotingEscrow is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    uint256 public constant MAX_LOCK = 4 * 365 days; // 4 years
    uint256 public constant MIN_LOCK = 7 days;
    uint256 public constant WEEK = 7 days;

    IERC20 public immutable token;

    struct LockInfo {
        uint128 amount;
        uint64 unlockTime; // unix timestamp, week-aligned
        uint64 createdAt;
    }

    /// @notice Per-user lock. One active lock per user; subsequent calls extend or top up.
    mapping(address => LockInfo) public locks;

    /// @notice Total locked $LITNUP across all users.
    uint128 public totalLocked;

    // -------- events --------

    event Locked(address indexed user, uint128 amount, uint64 unlockTime);
    event LockExtended(address indexed user, uint64 newUnlockTime);
    event LockToppedUp(address indexed user, uint128 added, uint128 newAmount);
    event Withdrawn(address indexed user, uint128 amount);

    // -------- errors --------

    error LockTooShort();
    error LockTooLong();
    error LockExists();
    error NoLock();
    error LockNotExpired();
    error UnlockTimeMustIncrease();
    error ZeroAmount();
    error NotAlignedToWeek();

    constructor(IERC20 _token, address _admin) {
        token = _token;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
    }

    // -------- user entrypoints --------

    /// @notice Create a new lock. `unlockTime` must be >= block.timestamp + MIN_LOCK and <= +MAX_LOCK,
    ///         and aligned to a week boundary (rounded down).
    function createLock(uint128 amount, uint64 unlockTime) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        LockInfo storage lock = locks[msg.sender];
        if (lock.amount > 0) revert LockExists();

        uint64 t = _floorToWeek(unlockTime);
        if (t < block.timestamp + MIN_LOCK) revert LockTooShort();
        if (t > block.timestamp + MAX_LOCK) revert LockTooLong();

        lock.amount = amount;
        lock.unlockTime = t;
        lock.createdAt = uint64(block.timestamp);
        totalLocked += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, amount, t);
    }

    /// @notice Increase the locked amount (does not change unlock time).
    function increaseAmount(uint128 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        LockInfo storage lock = locks[msg.sender];
        if (lock.amount == 0) revert NoLock();
        if (lock.unlockTime <= block.timestamp) revert LockNotExpired(); // already expired; withdraw first

        lock.amount += amount;
        totalLocked += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit LockToppedUp(msg.sender, amount, lock.amount);
    }

    /// @notice Extend lock to a later unlock time (must increase, within [MIN_LOCK, MAX_LOCK]).
    function extendLock(uint64 newUnlockTime) external nonReentrant {
        LockInfo storage lock = locks[msg.sender];
        if (lock.amount == 0) revert NoLock();

        uint64 t = _floorToWeek(newUnlockTime);
        if (t <= lock.unlockTime) revert UnlockTimeMustIncrease();
        if (t < block.timestamp + MIN_LOCK) revert LockTooShort();
        if (t > block.timestamp + MAX_LOCK) revert LockTooLong();

        lock.unlockTime = t;
        emit LockExtended(msg.sender, t);
    }

    /// @notice Withdraw fully after lock has expired. Closes the lock entirely.
    function withdraw() external nonReentrant {
        LockInfo storage lock = locks[msg.sender];
        if (lock.amount == 0) revert NoLock();
        if (block.timestamp < lock.unlockTime) revert LockNotExpired();

        uint128 amt = lock.amount;
        lock.amount = 0;
        lock.unlockTime = 0;
        totalLocked -= amt;

        token.safeTransfer(msg.sender, amt);
        emit Withdrawn(msg.sender, amt);
    }

    // -------- views --------

    /// @notice Current voting weight (linear decay).
    /// @dev weight = amount * timeLeft / MAX_LOCK; clamped to [0, amount].
    function balanceOf(address user) public view returns (uint256) {
        LockInfo memory lock = locks[user];
        if (lock.amount == 0 || block.timestamp >= lock.unlockTime) return 0;
        uint256 timeLeft = lock.unlockTime - block.timestamp;
        if (timeLeft >= MAX_LOCK) return lock.amount;
        return (uint256(lock.amount) * timeLeft) / MAX_LOCK;
    }

    /// @notice Approximate total ve weight across all users (sum of balanceOf at this instant).
    /// @dev O(n) on-chain is impractical; consumers should use a checkpointed off-chain index.
    ///      This view is for unit-tests / small registries. NOT used by the protocol critical path.
    function totalSupply() external view returns (uint256) {
        // Placeholder — production must use a checkpoint mechanism (Curve-style point history).
        // Returning totalLocked is a conservative upper bound: every locker gets at most 1.0x.
        return totalLocked;
    }

    /// @notice Lock data for a user.
    function lockInfo(address user) external view returns (uint128 amount, uint64 unlockTime, uint256 currentWeight) {
        LockInfo memory lock = locks[user];
        return (lock.amount, lock.unlockTime, balanceOf(user));
    }

    // -------- internal --------

    function _floorToWeek(uint64 t) internal pure returns (uint64) {
        return uint64((t / WEEK) * WEEK);
    }
}
