// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {StakingVault} from "./StakingVault.sol";
import {AgentRegistry} from "./AgentRegistry.sol";

/// @title PerformanceOracle
/// @notice Multi-signer oracle that posts agent attestations on-chain. Signers sign EIP-712 typed
///         data; a configurable threshold (e.g. 5-of-9) is required for any state change.
///
///         An attestation does three things, all driven by the SAME signed payload so a relayer
///         cannot alter economically-relevant parameters (fee split, fee payer):
///           1. records attested PnL for reputation/ranking (recordPnl — moves no assets);
///           2. pulls a REAL performance fee (in the vault's reward token, e.g. USDC) from the
///              operator and splits it between buyback and stakers (takeFees).
///         Slashing is a separate, independently-threshold-signed action (applySlash) so seizing
///         staker funds can never be a single-key decision.
/// @dev    "Attested" is not "trustless": this proves a threshold of signers agreed on a number.
///         A future version should root attestations in venue/TEE/ZK settlement proofs.
contract PerformanceOracle is AccessControl, EIP712 {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeCast for uint256;

    bytes32 public constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");

    /// @notice EIP-712 typed-data struct hash for a performance attestation.
    /// @dev toBuybackBps and feePayer are part of the signed struct: a relayer cannot change the
    ///      fee split or who pays. (v1 bug: toBuybackBps was an unsigned call parameter.)
    bytes32 public constant ATTESTATION_TYPEHASH = keccak256(
        "Attestation(uint256 agentId,int256 pnlDelta,uint256 feeAmount,uint16 toBuybackBps,address feePayer,uint64 epoch,uint64 deadline)"
    );

    /// @notice EIP-712 typed-data struct hash for a vault (staker principal) slash.
    bytes32 public constant SLASH_TYPEHASH = keccak256(
        "Slash(uint256 agentId,uint256 amount,uint64 epoch,uint64 deadline)"
    );

    /// @notice EIP-712 typed-data struct hash for an operator-bond slash (registry).
    bytes32 public constant SLASH_BOND_TYPEHASH = keccak256(
        "SlashBond(uint256 agentId,uint256 amount,uint64 epoch,uint64 deadline)"
    );

    StakingVault public immutable vault;
    AgentRegistry public immutable registry;

    /// @notice Authorized signer set (rotatable by SIGNER_MANAGER_ROLE, expected to be a timelock).
    mapping(address => bool) public isSigner;
    address[] public signers;

    /// @notice Number of signatures required for an action to apply.
    uint8 public threshold;

    /// @notice Replay protection, separate namespaces for attestations and slashes.
    mapping(uint256 agentId => mapping(uint64 epoch => bool)) public executedEpoch;
    mapping(uint256 agentId => mapping(uint64 epoch => bool)) public executedSlashEpoch;
    mapping(uint256 agentId => mapping(uint64 epoch => bool)) public executedBondSlashEpoch;

    // -------- events --------

    event AttestationApplied(uint256 indexed agentId, uint64 indexed epoch, int256 pnlDelta, uint256 feeAmount);
    event SlashApplied(uint256 indexed agentId, uint64 indexed epoch, uint256 amount);
    event BondSlashApplied(uint256 indexed agentId, uint64 indexed epoch, uint256 amount);
    event SignerAdded(address signer);
    event SignerRemoved(address signer);
    event ThresholdUpdated(uint8 newThreshold);

    // -------- errors --------

    error EpochAlreadyExecuted();
    error AttestationExpired();
    error InsufficientSignatures();
    error DuplicateSigner();
    error UnknownSigner();
    error SignerAlreadyExists();
    error InvalidThreshold();

    constructor(
        StakingVault _vault,
        AgentRegistry _registry,
        address[] memory _initialSigners,
        uint8 _threshold,
        address _admin
    ) EIP712("LITNUPOracle", "1") {
        if (_threshold == 0 || _threshold > _initialSigners.length) revert InvalidThreshold();
        vault = _vault;
        registry = _registry;

        for (uint256 i = 0; i < _initialSigners.length; i++) {
            address s = _initialSigners[i];
            if (s == address(0)) revert UnknownSigner();
            if (isSigner[s]) revert DuplicateSigner();
            isSigner[s] = true;
            signers.push(s);
            emit SignerAdded(s);
        }
        threshold = _threshold;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SIGNER_MANAGER_ROLE, _admin);
    }

    // -------- core --------

    /// @notice Apply a performance attestation signed by `threshold` signers.
    /// @param agentId The agent
    /// @param pnlDelta Signed PnL change for this epoch (reputation/fee basis; moves no assets)
    /// @param feeAmount Performance fee in the vault's reward token (e.g. USDC); pulled from feePayer
    /// @param toBuybackBps Fraction of fee to buyback (rest streams to stakers)
    /// @param feePayer Address that approved the vault to pull `feeAmount` (the operator)
    /// @param epoch Monotonic epoch counter; used for replay protection
    /// @param deadline block.timestamp deadline
    /// @param signatures Concatenated 65-byte ECDSA sigs from distinct signers in ascending address order
    function applyAttestation(
        uint256 agentId,
        int256 pnlDelta,
        uint256 feeAmount,
        uint16 toBuybackBps,
        address feePayer,
        uint64 epoch,
        uint64 deadline,
        bytes[] calldata signatures
    ) external {
        if (executedEpoch[agentId][epoch]) revert EpochAlreadyExecuted();
        if (block.timestamp > deadline) revert AttestationExpired();

        bytes32 structHash = keccak256(abi.encode(
            ATTESTATION_TYPEHASH,
            agentId,
            pnlDelta,
            feeAmount,
            toBuybackBps,
            feePayer,
            epoch,
            deadline
        ));
        _verifySignatures(_hashTypedDataV4(structHash), signatures);

        executedEpoch[agentId][epoch] = true;

        vault.recordPnl(agentId, pnlDelta);
        if (feeAmount > 0) {
            // SafeCast: an out-of-range feeAmount reverts instead of silently truncating.
            vault.takeFees(agentId, feeAmount.toUint128(), toBuybackBps, feePayer);
        }

        emit AttestationApplied(agentId, epoch, pnlDelta, feeAmount);
    }

    /// @notice Apply a slash, independently signed by `threshold` signers. Seizing staker funds is
    ///         never a single-key action.
    function applySlash(
        uint256 agentId,
        uint256 amount,
        uint64 epoch,
        uint64 deadline,
        bytes[] calldata signatures
    ) external {
        if (executedSlashEpoch[agentId][epoch]) revert EpochAlreadyExecuted();
        if (block.timestamp > deadline) revert AttestationExpired();

        bytes32 structHash = keccak256(abi.encode(SLASH_TYPEHASH, agentId, amount, epoch, deadline));
        _verifySignatures(_hashTypedDataV4(structHash), signatures);

        executedSlashEpoch[agentId][epoch] = true;

        vault.slashVault(agentId, amount.toUint128());
        emit SlashApplied(agentId, epoch, amount);
    }

    /// @notice Slash an operator's BOND in the registry, independently signed by `threshold` signers.
    ///         This is the on-chain path that was previously dead (SLASHER_ROLE was granted to a
    ///         contract that never called it). The oracle must hold SLASHER_ROLE on the registry.
    function slashBond(
        uint256 agentId,
        uint256 amount,
        uint64 epoch,
        uint64 deadline,
        bytes[] calldata signatures
    ) external {
        if (executedBondSlashEpoch[agentId][epoch]) revert EpochAlreadyExecuted();
        if (block.timestamp > deadline) revert AttestationExpired();

        bytes32 structHash = keccak256(abi.encode(SLASH_BOND_TYPEHASH, agentId, amount, epoch, deadline));
        _verifySignatures(_hashTypedDataV4(structHash), signatures);

        executedBondSlashEpoch[agentId][epoch] = true;

        registry.slash(agentId, amount.toUint128());
        emit BondSlashApplied(agentId, epoch, amount);
    }

    // -------- signature verification --------

    /// @dev Verifies `threshold` distinct authorized signers signed `digest`, supplied in strictly
    ///      ascending address order (which also enforces distinctness).
    function _verifySignatures(bytes32 digest, bytes[] calldata signatures) internal view {
        if (signatures.length < threshold) revert InsufficientSignatures();
        address lastSigner = address(0);
        uint256 valid = 0;
        for (uint256 i = 0; i < signatures.length; i++) {
            address recovered = digest.recover(signatures[i]);
            if (!isSigner[recovered]) revert UnknownSigner();
            if (recovered <= lastSigner) revert DuplicateSigner();
            lastSigner = recovered;
            valid++;
        }
        if (valid < threshold) revert InsufficientSignatures();
    }

    // -------- signer management (expected to be timelock-governed) --------

    function addSigner(address s) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (s == address(0)) revert UnknownSigner();
        if (isSigner[s]) revert SignerAlreadyExists();
        isSigner[s] = true;
        signers.push(s);
        emit SignerAdded(s);
    }

    function removeSigner(address s) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (!isSigner[s]) revert UnknownSigner();
        isSigner[s] = false;
        uint256 n = signers.length;
        for (uint256 i = 0; i < n; i++) {
            if (signers[i] == s) {
                signers[i] = signers[n - 1];
                signers.pop();
                break;
            }
        }
        if (threshold > signers.length) {
            threshold = uint8(signers.length);
            emit ThresholdUpdated(threshold);
        }
        emit SignerRemoved(s);
    }

    function setThreshold(uint8 t) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (t == 0 || t > signers.length) revert InvalidThreshold();
        threshold = t;
        emit ThresholdUpdated(t);
    }

    // -------- views --------

    function getSigners() external view returns (address[] memory) { return signers; }

    function signerCount() external view returns (uint256) { return signers.length; }
}
