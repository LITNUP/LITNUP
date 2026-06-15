// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EmissionScheduler
/// @notice Streams the pre-funded ecosystem-incentive $LITNUP bucket (~17% of supply per tokenomics)
///         linearly to weighted recipients. This is NOT inflation: the scheduler is funded once with
///         pre-minted tokens; it only meters their release.
///
///         REWEIGHT SAFETY (v2): emissions accrued up to a weight change are CHECKPOINTED into each
///         recipient's `credited` balance at the weights then in effect, before the new weights take
///         hold. v1 multiplied the *current* weight by *all* emissions-to-date, so reweighting
///         retroactively re-priced the entire past stream — letting a reweight steal already-earned
///         emissions from co-recipients (or strand them). Only the forward stream uses new weights.
contract EmissionScheduler is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    IERC20 public immutable token;

    uint64  public immutable startTime;
    uint64  public immutable durationSeconds;
    uint128 public immutable totalEmission;

    struct Recipient {
        uint16 weightBps;       // out of 10_000
        uint128 totalPulled;
        bool active;
    }
    mapping(address => Recipient) public recipients;
    address[] public recipientList;
    mapping(address => bool) public everListed;     // guards against duplicate recipientList entries
    uint16 public totalWeightBps;                   // sum across active recipients (must equal 10_000 to pull)

    /// @notice Cumulative tokens already pulled by all recipients.
    uint128 public totalPulled;

    /// @notice Per-recipient entitlement locked in at past weight checkpoints.
    mapping(address => uint128) public credited;
    /// @notice Cumulative emitted amount that has already been distributed into `credited`.
    uint256 public settledEmitted;

    /// @notice If non-zero, emissions are frozen at this timestamp (governance stop).
    uint64 public stoppedAt;

    // -------- events --------

    event RecipientSet(address indexed recipient, uint16 weightBps, bool active);
    event Pulled(address indexed recipient, uint128 amount);
    event EmissionsStopped(uint64 at);

    // -------- errors --------

    error WeightOutOfRange();
    error WeightsMustSumTo10000();
    error NotRecipient();
    error NothingClaimable();
    error AlreadyStopped();

    constructor(
        IERC20 _token,
        uint64 _startTime,
        uint64 _durationSeconds,
        uint128 _totalEmission,
        address _admin
    ) {
        require(_durationSeconds > 0 && _totalEmission > 0, "params");
        token = _token;
        startTime = _startTime == 0 ? uint64(block.timestamp) : _startTime;
        durationSeconds = _durationSeconds;
        totalEmission = _totalEmission;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
    }

    // -------- governance / config --------

    /// @notice Set or update a recipient's weight (weightBps = 0 deactivates). Past emissions are
    ///         checkpointed at the OLD weights first, so reweighting never re-prices the past.
    function setRecipient(address recipient, uint16 weightBps) external onlyRole(CONFIG_ROLE) {
        if (weightBps > 10_000) revert WeightOutOfRange();
        _settleAll();

        Recipient storage r = recipients[recipient];
        if (r.active) {
            totalWeightBps -= r.weightBps;
        } else if (weightBps > 0 && !everListed[recipient]) {
            recipientList.push(recipient);
            everListed[recipient] = true;
        }

        r.weightBps = weightBps;
        r.active = weightBps > 0;
        if (r.active) totalWeightBps += weightBps;

        emit RecipientSet(recipient, weightBps, r.active);
    }

    /// @notice Freeze emissions at the current timestamp (tokenomics promised "governance can pause").
    function stopEmissions() external onlyRole(CONFIG_ROLE) {
        if (stoppedAt != 0) revert AlreadyStopped();
        _settleAll();
        stoppedAt = uint64(block.timestamp);
        emit EmissionsStopped(stoppedAt);
    }

    // -------- recipients --------

    /// @notice Pull whatever is currently claimable to the caller.
    function pull() external nonReentrant returns (uint128 amount) {
        Recipient storage r = recipients[msg.sender];
        if (!r.active) revert NotRecipient();
        if (totalWeightBps != 10_000) revert WeightsMustSumTo10000();

        _settleAll();
        uint256 owed = credited[msg.sender];
        if (owed <= r.totalPulled) revert NothingClaimable();
        amount = uint128(owed - r.totalPulled);

        r.totalPulled += amount;
        totalPulled += amount;
        token.safeTransfer(msg.sender, amount);
        emit Pulled(msg.sender, amount);
    }

    // -------- views --------

    /// @notice Cumulative emitted amount up to now (or to the stop time, if stopped).
    function emittedToDate() public view returns (uint256) {
        uint256 t = (stoppedAt != 0 && stoppedAt < block.timestamp) ? stoppedAt : block.timestamp;
        if (t <= startTime) return 0;
        uint256 elapsed = t - startTime;
        if (elapsed >= durationSeconds) return totalEmission;
        return (uint256(totalEmission) * elapsed) / durationSeconds;
    }

    /// @notice Amount the recipient can pull right now (checkpointed past + live tail).
    function claimable(address recipient) public view returns (uint256) {
        Recipient memory r = recipients[recipient];
        uint256 owed = credited[recipient];
        if (r.active && totalWeightBps == 10_000) {
            owed += ((emittedToDate() - settledEmitted) * r.weightBps) / 10_000;
        }
        return owed > r.totalPulled ? owed - r.totalPulled : 0;
    }

    function getRecipients() external view returns (address[] memory) {
        return recipientList;
    }

    // -------- internal --------

    /// @dev Lock the emissions accrued since the last checkpoint into each active recipient's
    ///      `credited` balance at the CURRENT weights, then advance the settled marker.
    function _settleAll() internal {
        uint256 emitted = emittedToDate();
        uint256 delta = emitted - settledEmitted;
        if (delta == 0) return;
        uint256 n = recipientList.length;
        for (uint256 i = 0; i < n; i++) {
            address addr = recipientList[i];
            Recipient storage rec = recipients[addr];
            if (rec.active && rec.weightBps > 0) {
                credited[addr] += uint128((delta * rec.weightBps) / 10_000);
            }
        }
        settledEmitted = emitted;
    }
}
