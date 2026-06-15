// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Vesting
/// @notice Cliff-then-linear vesting of $LITNUP for team, investors, and advisors.
///         Each schedule is identified by a beneficiary; one schedule per beneficiary.
///         Tokens accrue continuously after cliff; beneficiaries claim by calling release().
///
///         Optional "vest-into-stake" mode: a fraction of each release is auto-deposited
///         into a target StakingVault to suppress dump pressure on cliff days.
contract Vesting is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    struct Schedule {
        uint128 totalAmount;       // total $LITNUP vested over the full schedule
        uint128 released;          // amount already released
        uint64  startTime;         // unix; vesting math is anchored here
        uint64  cliffSeconds;      // duration of cliff from start
        uint64  durationSeconds;   // total duration including cliff
        bool    revocable;         // can the admin revoke (e.g. terminated employee)?
        bool    revoked;
    }

    IERC20 public immutable token;

    mapping(address => Schedule) public schedules;

    /// @notice Total tokens reserved across all unrevoked schedules. Used by the contract to know
    ///         how much it can sweep if needed.
    uint128 public totalReserved;

    // -------- events --------

    event ScheduleCreated(address indexed beneficiary, uint128 amount, uint64 start, uint64 cliff, uint64 duration);
    event Released(address indexed beneficiary, uint128 amount);
    event ScheduleRevoked(address indexed beneficiary, uint128 unvestedReclaimed);

    // -------- errors --------

    error ScheduleAlreadyExists();
    error ScheduleNotFound();
    error AlreadyRevoked();
    error NotRevocable();
    error NothingVested();
    error InvalidParams();

    constructor(IERC20 _token, address _admin) {
        token = _token;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
    }

    // -------- admin --------

    /// @notice Create a vesting schedule for a beneficiary. Tokens are pulled from the caller.
    function createSchedule(
        address beneficiary,
        uint128 amount,
        uint64 startTime,
        uint64 cliffSeconds,
        uint64 durationSeconds,
        bool revocable
    ) external onlyRole(CONFIG_ROLE) nonReentrant {
        if (beneficiary == address(0) || amount == 0 || durationSeconds == 0) revert InvalidParams();
        if (cliffSeconds > durationSeconds) revert InvalidParams();
        Schedule storage s = schedules[beneficiary];
        if (s.totalAmount > 0) revert ScheduleAlreadyExists();

        schedules[beneficiary] = Schedule({
            totalAmount: amount,
            released: 0,
            startTime: startTime == 0 ? uint64(block.timestamp) : startTime,
            cliffSeconds: cliffSeconds,
            durationSeconds: durationSeconds,
            revocable: revocable,
            revoked: false
        });
        totalReserved += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit ScheduleCreated(beneficiary, amount, schedules[beneficiary].startTime, cliffSeconds, durationSeconds);
    }

    /// @notice Revoke an unvested portion. Only works if `revocable` was set true at creation.
    ///         Vested-but-unreleased portion is preserved for the beneficiary.
    function revoke(address beneficiary) external onlyRole(CONFIG_ROLE) nonReentrant returns (uint128 reclaimed) {
        Schedule storage s = schedules[beneficiary];
        if (s.totalAmount == 0) revert ScheduleNotFound();
        if (!s.revocable) revert NotRevocable();
        if (s.revoked) revert AlreadyRevoked();

        uint128 vested = uint128(_vestedAmount(s));
        // Beneficiary keeps everything vested so far; only the UNVESTED remainder returns to admin.
        reclaimed = s.totalAmount - vested;
        s.totalAmount = vested;
        // Freeze the schedule as fully-vested at `vested`, so release() pays exactly the
        // already-vested amount (no curve-shrink under-payment) and can never underflow.
        s.cliffSeconds = 0;
        uint64 elapsed = block.timestamp > s.startTime ? uint64(block.timestamp - s.startTime) : 0;
        s.durationSeconds = elapsed == 0 ? 1 : elapsed;
        s.revoked = true;
        totalReserved -= reclaimed;

        if (reclaimed > 0) {
            token.safeTransfer(msg.sender, reclaimed);
        }
        emit ScheduleRevoked(beneficiary, reclaimed);
    }

    // -------- beneficiary --------

    /// @notice Release all currently vested-but-unreleased tokens to the beneficiary.
    function release() external nonReentrant returns (uint128 amount) {
        Schedule storage s = schedules[msg.sender];
        if (s.totalAmount == 0) revert ScheduleNotFound();

        uint128 vested = uint128(_vestedAmount(s));
        amount = vested - s.released;
        if (amount == 0) revert NothingVested();
        s.released = vested;

        totalReserved -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Released(msg.sender, amount);
    }

    // -------- views --------

    function vestedAmount(address beneficiary) external view returns (uint256) {
        return _vestedAmount(schedules[beneficiary]);
    }

    function releasable(address beneficiary) external view returns (uint256) {
        Schedule memory s = schedules[beneficiary];
        if (s.totalAmount == 0) return 0;
        uint256 vested = _vestedAmount(s);
        return vested > s.released ? vested - s.released : 0;
    }

    // -------- internal --------

    function _vestedAmount(Schedule memory s) internal view returns (uint256) {
        if (block.timestamp < s.startTime + s.cliffSeconds) return 0;
        if (block.timestamp >= s.startTime + s.durationSeconds) return s.totalAmount;
        // Linear vesting from startTime to startTime + durationSeconds
        uint256 elapsed = block.timestamp - s.startTime;
        return (uint256(s.totalAmount) * elapsed) / s.durationSeconds;
    }
}
