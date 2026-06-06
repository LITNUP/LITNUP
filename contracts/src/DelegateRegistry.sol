// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title DelegateRegistry
/// @notice Allows holders of $LITNUP to delegate certain rights without transferring tokens.
///         Currently supports two delegation classes:
///         (1) `vote` — governance voting weight (used alongside ERC20Votes built-in delegation)
///         (2) `claim` — airdrop claim authority for a wallet (e.g., delegate to a hot wallet)
///
///         Designed to be lightweight: per-(delegator, class) → delegate address mapping.
///         Off-chain agents and dApp frontends should index `Delegated` events.
///
///         No tokens move. No ETH escrowed. No reentrancy surface.
contract DelegateRegistry is AccessControl {
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    /// @notice delegator => class hash => delegate
    mapping(address => mapping(bytes32 => address)) public delegateOf;

    /// @notice Reverse index: delegate => class hash => list of delegators
    /// @dev Iterating off-chain via events is preferred; this view is for small registries.
    mapping(address => mapping(bytes32 => address[])) private _delegators;

    /// @notice Whitelist of allowed delegation classes. Governance can add new ones.
    mapping(bytes32 => bool) public allowedClass;

    bytes32 public constant CLASS_VOTE  = keccak256("vote");
    bytes32 public constant CLASS_CLAIM = keccak256("claim");

    event Delegated(address indexed delegator, bytes32 indexed class, address indexed delegate, address previous);
    event ClassEnabled(bytes32 indexed class);
    event ClassDisabled(bytes32 indexed class);

    error UnknownClass();
    error NoChange();

    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
        // Whitelist the two default classes
        allowedClass[CLASS_VOTE] = true;
        allowedClass[CLASS_CLAIM] = true;
        emit ClassEnabled(CLASS_VOTE);
        emit ClassEnabled(CLASS_CLAIM);
    }

    // -------- delegators --------

    /// @notice Set or clear a delegate for a given class.
    /// @param class The delegation class (e.g. CLASS_VOTE, CLASS_CLAIM).
    /// @param delegate The address to delegate to. Pass address(0) to clear.
    function setDelegate(bytes32 class, address delegate) external {
        if (!allowedClass[class]) revert UnknownClass();
        address prev = delegateOf[msg.sender][class];
        if (prev == delegate) revert NoChange();
        delegateOf[msg.sender][class] = delegate;
        if (delegate != address(0)) {
            _delegators[delegate][class].push(msg.sender);
        }
        emit Delegated(msg.sender, class, delegate, prev);
    }

    /// @notice Convenience: clear all default classes for the caller.
    function clearAll() external {
        if (delegateOf[msg.sender][CLASS_VOTE] != address(0)) {
            address prev = delegateOf[msg.sender][CLASS_VOTE];
            delegateOf[msg.sender][CLASS_VOTE] = address(0);
            emit Delegated(msg.sender, CLASS_VOTE, address(0), prev);
        }
        if (delegateOf[msg.sender][CLASS_CLAIM] != address(0)) {
            address prev = delegateOf[msg.sender][CLASS_CLAIM];
            delegateOf[msg.sender][CLASS_CLAIM] = address(0);
            emit Delegated(msg.sender, CLASS_CLAIM, address(0), prev);
        }
    }

    // -------- governance --------

    function enableClass(bytes32 class) external onlyRole(CONFIG_ROLE) {
        if (!allowedClass[class]) {
            allowedClass[class] = true;
            emit ClassEnabled(class);
        }
    }

    function disableClass(bytes32 class) external onlyRole(CONFIG_ROLE) {
        if (allowedClass[class]) {
            allowedClass[class] = false;
            emit ClassDisabled(class);
        }
    }

    // -------- views --------

    /// @notice Get the delegate address for a (delegator, class) pair, or address(0) if unset.
    function getDelegate(address delegator, bytes32 class) external view returns (address) {
        return delegateOf[delegator][class];
    }

    /// @notice Get the recorded delegators for a (delegate, class) pair.
    /// @dev May contain stale entries (a delegator may have changed delegates since being added).
    ///      Consumers must verify via `delegateOf` before relying on the list.
    function delegatorsOf(address delegate, bytes32 class) external view returns (address[] memory) {
        return _delegators[delegate][class];
    }

    /// @notice Hash a class name string into the canonical class identifier.
    function hashClass(string memory name) external pure returns (bytes32) {
        return keccak256(bytes(name));
    }
}
