// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title PauseGuardian
/// @notice An emergency-pause multisig with a tightly-scoped action whitelist.
///
///         Why this exists, and why it is its own contract:
///         The protocol is otherwise immutable — no upgrade pattern, no admin
///         backdoors. But circuit-breaker authority is a real risk-management
///         primitive: a confirmed oracle bug, a confirmed router exploit, or a
///         confirmed slashing-mass-event needs to be paused FAST (minutes, not
///         the 48h timelock).
///
///         The guardian is therefore a small N-of-M multisig (default 3-of-5)
///         that can ONLY call functions from an admin-managed whitelist of
///         (target, selector) pairs. It cannot move funds, mint, or escalate
///         privileges. It can only flip booleans on contracts that were
///         pre-approved as "things the guardian can pause."
///
///         The whitelist is itself governed by the timelock — adding a new
///         (target, selector) requires a 48h timelock proposal. So even if all
///         five guardian keys are compromised, the worst they can do is pause
///         pre-approved targets. They cannot grant themselves new powers.
contract PauseGuardian is AccessControlEnumerable, ReentrancyGuard {
    bytes32 public constant GUARDIAN_ROLE   = keccak256("GUARDIAN_ROLE");
    bytes32 public constant WHITELIST_ROLE  = keccak256("WHITELIST_ROLE"); // held by Timelock

    /// @notice (target, selector) pair the guardians may invoke.
    struct Action {
        address target;
        bytes4  selector;
    }

    /// @notice Hash of (target, selector) → enabled.
    mapping(bytes32 actionId => bool enabled) public allowedAction;

    /// @notice Number of guardian approvals required to execute. Default 3 of 5.
    uint8 public threshold;

    /// @notice Per-action approval bitmap: actionHash → approver → bool.
    mapping(bytes32 actionHash => mapping(address guardian => bool)) public hasApproved;

    /// @notice Per-action approval count.
    mapping(bytes32 actionHash => uint8 count) public approvalCount;

    /// @notice Per-action list of approvers, so an approval bundle can be FULLY cleared on reset
    /// (without this, hasApproved entries persisted and permanently locked guardians out of
    /// re-approving the same action — bricking any repeat pause/unpause).
    mapping(bytes32 actionHash => address[]) private _approvers;

    /// @notice Auto-clear timestamp: if action isn't executed within 24h, approvals reset.
    uint64 public approvalWindow = 24 hours;

    /// @notice Per-action first-approval timestamp.
    mapping(bytes32 actionHash => uint64 ts) public firstApprovalAt;

    /// @notice Optional cooldown between executions per (target, selector).
    /// Prevents grief-pause-loops. Default 0; can be set per-action.
    mapping(bytes32 actionId => uint64 cooldown) public actionCooldown;
    mapping(bytes32 actionId => uint64 lastExecAt) public lastExecAt;

    // -------- events --------

    event ActionAllowed(bytes32 indexed actionId, address target, bytes4 selector);
    event ActionRevoked(bytes32 indexed actionId);
    event ActionApproved(bytes32 indexed actionHash, address indexed guardian, uint8 count);
    event ActionExecuted(bytes32 indexed actionHash, address indexed target, bytes4 selector, bytes returnData);
    event ApprovalsReset(bytes32 indexed actionHash);
    event ThresholdUpdated(uint8 newThreshold);
    event ApprovalWindowUpdated(uint64 newWindow);
    event ActionCooldownUpdated(bytes32 indexed actionId, uint64 cooldown);

    // -------- errors --------

    error ActionNotAllowed();
    error AlreadyApproved();
    error InsufficientApprovals();
    error InvalidThreshold();
    error CooldownActive();
    error CallFailed();

    constructor(address _admin, address _timelock, address[] memory guardians, uint8 _threshold) {
        if (_threshold == 0 || _threshold > guardians.length) revert InvalidThreshold();
        threshold = _threshold;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(WHITELIST_ROLE, _timelock);
        for (uint256 i = 0; i < guardians.length; i++) {
            _grantRole(GUARDIAN_ROLE, guardians[i]);
        }
    }

    // ============================================================
    // WHITELIST MANAGEMENT (callable by timelock only)
    // ============================================================

    function allowAction(address target, bytes4 selector) external onlyRole(WHITELIST_ROLE) {
        bytes32 id = _actionId(target, selector);
        allowedAction[id] = true;
        emit ActionAllowed(id, target, selector);
    }

    function revokeAction(address target, bytes4 selector) external onlyRole(WHITELIST_ROLE) {
        bytes32 id = _actionId(target, selector);
        allowedAction[id] = false;
        emit ActionRevoked(id);
    }

    function setThreshold(uint8 newThreshold) external onlyRole(WHITELIST_ROLE) {
        // Bound by the live guardian count — otherwise governance could set the
        // threshold above the number of guardians, making it impossible to ever
        // reach quorum and bricking the emergency pause/unpause path entirely.
        if (newThreshold == 0 || newThreshold > getRoleMemberCount(GUARDIAN_ROLE)) revert InvalidThreshold();
        threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    function setApprovalWindow(uint64 newWindow) external onlyRole(WHITELIST_ROLE) {
        approvalWindow = newWindow;
        emit ApprovalWindowUpdated(newWindow);
    }

    function setActionCooldown(address target, bytes4 selector, uint64 cooldown) external onlyRole(WHITELIST_ROLE) {
        bytes32 id = _actionId(target, selector);
        actionCooldown[id] = cooldown;
        emit ActionCooldownUpdated(id, cooldown);
    }

    // ============================================================
    // GUARDIAN APPROVAL FLOW
    // ============================================================

    /// @notice Approve (and execute, if threshold reached) a guardian action.
    /// @dev `data` is the full calldata for the target call, e.g. abi.encodeWithSelector(IPausable.pause.selector).
    function approveAndMaybeExecute(address target, bytes calldata data)
        external
        onlyRole(GUARDIAN_ROLE)
        nonReentrant
        returns (bool executed, bytes memory ret)
    {
        bytes4 selector = bytes4(data);
        bytes32 actionId = _actionId(target, selector);
        if (!allowedAction[actionId]) revert ActionNotAllowed();

        // Hash the full calldata so different argument values are tracked separately.
        bytes32 actionHash = keccak256(abi.encodePacked(target, data));

        // Reset stale approval bundles.
        if (firstApprovalAt[actionHash] != 0
            && block.timestamp > firstApprovalAt[actionHash] + approvalWindow) {
            // Window expired — wipe and start fresh
            _resetApprovals(actionHash);
        }

        if (hasApproved[actionHash][msg.sender]) revert AlreadyApproved();
        hasApproved[actionHash][msg.sender] = true;
        _approvers[actionHash].push(msg.sender);

        if (firstApprovalAt[actionHash] == 0) {
            firstApprovalAt[actionHash] = uint64(block.timestamp);
        }

        uint8 c = approvalCount[actionHash] + 1;
        approvalCount[actionHash] = c;
        emit ActionApproved(actionHash, msg.sender, c);

        if (c >= threshold) {
            // Cooldown check
            uint64 cd = actionCooldown[actionId];
            // Only enforce the cooldown after a prior execution (lastExecAt != 0); otherwise the
            // very first execution would falsely trip when block.timestamp < cd.
            if (cd > 0 && lastExecAt[actionId] != 0 && lastExecAt[actionId] + cd > block.timestamp) {
                revert CooldownActive();
            }

            (bool ok, bytes memory r) = target.call(data);
            if (!ok) revert CallFailed();

            lastExecAt[actionId] = uint64(block.timestamp);
            _resetApprovals(actionHash);
            emit ActionExecuted(actionHash, target, selector, r);
            return (true, r);
        }
        return (false, "");
    }

    /// @notice Anyone can clear a stale (expired) approval bundle.
    function clearStaleApprovals(bytes32 actionHash) external {
        require(firstApprovalAt[actionHash] != 0, "no approvals");
        require(block.timestamp > firstApprovalAt[actionHash] + approvalWindow, "not stale");
        _resetApprovals(actionHash);
    }

    function _resetApprovals(bytes32 actionHash) internal {
        // Clear each approver's flag so the same guardians can approve the action again next time.
        address[] storage appr = _approvers[actionHash];
        uint256 n = appr.length;
        for (uint256 i = 0; i < n; i++) {
            hasApproved[actionHash][appr[i]] = false;
        }
        delete _approvers[actionHash];
        approvalCount[actionHash] = 0;
        firstApprovalAt[actionHash] = 0;
        emit ApprovalsReset(actionHash);
    }

    function _actionId(address target, bytes4 selector) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(target, selector));
    }

    // ============================================================
    // VIEWS
    // ============================================================

    function getActionId(address target, bytes4 selector) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(target, selector));
    }

    function getActionHash(address target, bytes calldata data) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(target, data));
    }
}
