// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title EmissionScheduler
/// @notice Streams ecosystem-incentive $LITNUP to authorized recipient contracts (e.g.
///         a stake-rewards distributor, a gauge controller, an LP-incentive contract)
///         on a fixed linear schedule.
///
///         The scheduler holds the ecosystem-incentive bucket (~17% of supply per tokenomics).
///         It releases tokens linearly over `durationSeconds` to one or more registered
///         recipients, weighted by per-recipient `weight`. Weights sum to 10,000 (= 100%).
///
///         Governance can add/remove recipients and reweight (subject to timelock).
///         Recipients pull their share via `pull()`; recipients can be regular wallets
///         or smart contracts.
contract EmissionScheduler is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    IERC20 public immutable token;

    /// @notice Schedule parameters
    uint64  public immutable startTime;
    uint64  public immutable durationSeconds;
    uint128 public immutable totalEmission;     // total tokens scheduled

    /// @notice Per-recipient state
    struct Recipient {
        uint16 weightBps;       // out of 10_000
        uint128 totalPulled;
        bool active;
    }
    mapping(address => Recipient) public recipients;
    address[] public recipientList;
    uint16 public totalWeightBps;               // sum across active recipients (must equal 10_000 to release)

    /// @notice Cumulative tokens already pulled by all recipients
    uint128 public totalPulled;

    // -------- events --------

    event RecipientSet(address indexed recipient, uint16 weightBps, bool active);
    event Pulled(address indexed recipient, uint128 amount);

    // -------- errors --------

    error WeightOutOfRange();
    error WeightsMustSumTo10000();
    error NotRecipient();
    error NothingClaimable();
    error TooEarly();

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

    /// @notice Set or update a recipient's weight. Pass weightBps = 0 to deactivate.
    /// @dev Requires totalWeightBps to equal 10_000 across all active recipients before any pull is allowed.
    function setRecipient(address recipient, uint16 weightBps) external onlyRole(CONFIG_ROLE) {
        if (weightBps > 10_000) revert WeightOutOfRange();
        Recipient storage r = recipients[recipient];

        // Update totalWeightBps based on previous and new weights
        if (r.active) {
            totalWeightBps -= r.weightBps;
        } else if (weightBps > 0) {
            recipientList.push(recipient);
        }

        r.weightBps = weightBps;
        r.active = weightBps > 0;
        if (r.active) totalWeightBps += weightBps;

        emit RecipientSet(recipient, weightBps, r.active);
    }

    // -------- recipients --------

    /// @notice Pull whatever is currently claimable to the caller.
    function pull() external nonReentrant returns (uint128 amount) {
        Recipient storage r = recipients[msg.sender];
        if (!r.active) revert NotRecipient();
        if (totalWeightBps != 10_000) revert WeightsMustSumTo10000();

        amount = uint128(claimable(msg.sender));
        if (amount == 0) revert NothingClaimable();

        r.totalPulled += amount;
        totalPulled += amount;
        token.safeTransfer(msg.sender, amount);
        emit Pulled(msg.sender, amount);
    }

    // -------- views --------

    /// @notice Returns the cumulative emitted amount up to `block.timestamp`.
    function emittedToDate() public view returns (uint256) {
        if (block.timestamp <= startTime) return 0;
        uint256 elapsed = block.timestamp - startTime;
        if (elapsed >= durationSeconds) return totalEmission;
        return (uint256(totalEmission) * elapsed) / durationSeconds;
    }

    /// @notice Returns the amount the recipient can pull right now.
    function claimable(address recipient) public view returns (uint256) {
        Recipient memory r = recipients[recipient];
        if (!r.active || totalWeightBps != 10_000) return 0;
        uint256 totalEmitted = emittedToDate();
        uint256 recipientShare = (totalEmitted * r.weightBps) / 10_000;
        if (recipientShare <= r.totalPulled) return 0;
        return recipientShare - r.totalPulled;
    }

    /// @notice Returns full list of registered recipients.
    function getRecipients() external view returns (address[] memory) {
        return recipientList;
    }
}
