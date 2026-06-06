// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {StakingVault} from "./StakingVault.sol";
import {AgentRegistry} from "./AgentRegistry.sol";

/// @title PerformanceOracle
/// @notice Multi-signer oracle that posts agent PnL attestations on-chain. Signers
///         sign EIP-712 typed data. A configurable threshold (e.g. 5-of-7) is required.
///         The oracle calls into StakingVault.applyPnl / takeFees / slashVault.
/// @dev v2 will replace this with ZK-proof or SGX-attested computation.
contract PerformanceOracle is AccessControl, EIP712 {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant SIGNER_MANAGER_ROLE = keccak256("SIGNER_MANAGER_ROLE");

    /// @notice EIP-712 typed-data struct hash for an attestation.
    bytes32 public constant ATTESTATION_TYPEHASH = keccak256(
        "Attestation(uint256 agentId,int256 pnlDelta,uint256 feeOnGross,uint64 epoch,uint64 deadline)"
    );

    StakingVault public immutable vault;
    AgentRegistry public immutable registry;

    /// @notice Authorized signer set (rotatable by SIGNER_MANAGER_ROLE).
    mapping(address => bool) public isSigner;
    address[] public signers;

    /// @notice Number of signatures required for an attestation to apply.
    uint8 public threshold;

    /// @notice Bitmap of executed (agentId, epoch) → prevent replay.
    mapping(uint256 agentId => mapping(uint64 epoch => bool)) public executedEpoch;

    /// @notice Drawdown threshold below which `slashVault` triggers (in bps of high-water mark).
    uint16 public drawdownSlashBps = 2500; // 25%
    /// @notice Slash size as fraction of vault on drawdown breach.
    uint16 public drawdownSlashSizeBps = 1000; // 10%

    /// @notice Per-agent high-water-mark of total vault assets (informational; oracle uses off-chain HWM).
    mapping(uint256 agentId => uint128) public highWaterMark;

    // -------- events --------

    event AttestationApplied(uint256 indexed agentId, uint64 indexed epoch, int256 pnlDelta, uint256 feeOnGross);
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

    /// @notice Apply an attestation signed by `threshold` signers.
    /// @param agentId The agent
    /// @param pnlDelta Signed PnL change in $LITNUP for this epoch
    /// @param feeOnGross Fee portion (taken only on positive PnL)
    /// @param toBuybackBps Fraction of fee to buyback (rest to stakers)
    /// @param epoch Monotonic epoch counter; used for replay protection
    /// @param deadline Block.timestamp deadline
    /// @param signatures Concatenated 65-byte ECDSA sigs sorted by signer address
    function applyAttestation(
        uint256 agentId,
        int256 pnlDelta,
        uint256 feeOnGross,
        uint16 toBuybackBps,
        uint64 epoch,
        uint64 deadline,
        bytes[] calldata signatures
    ) external {
        if (executedEpoch[agentId][epoch]) revert EpochAlreadyExecuted();
        if (block.timestamp > deadline) revert AttestationExpired();
        if (signatures.length < threshold) revert InsufficientSignatures();

        bytes32 structHash = keccak256(abi.encode(
            ATTESTATION_TYPEHASH,
            agentId,
            pnlDelta,
            feeOnGross,
            epoch,
            deadline
        ));
        bytes32 digest = _hashTypedDataV4(structHash);

        // Verify signatures: must be from `threshold` distinct authorized signers in sorted order
        address lastSigner = address(0);
        uint8 valid = 0;
        for (uint256 i = 0; i < signatures.length; i++) {
            address recovered = digest.recover(signatures[i]);
            if (!isSigner[recovered]) revert UnknownSigner();
            if (recovered <= lastSigner) revert DuplicateSigner();
            lastSigner = recovered;
            valid++;
        }
        if (valid < threshold) revert InsufficientSignatures();

        executedEpoch[agentId][epoch] = true;

        // Apply to vault
        vault.applyPnl(agentId, int128(pnlDelta));
        if (pnlDelta > 0 && feeOnGross > 0) {
            vault.takeFees(agentId, uint128(feeOnGross), toBuybackBps);
        }

        // Track HWM and drawdown for off-chain monitoring
        // (Slashing path is exposed separately so off-chain logic chooses when to trigger)
        emit AttestationApplied(agentId, epoch, pnlDelta, feeOnGross);
    }

    /// @notice Trigger drawdown-based slash. Oracle off-chain monitors HWM; calls this
    ///         when sustained drawdown exceeds `drawdownSlashBps` for the agent.
    function triggerDrawdownSlash(uint256 agentId, uint128 vaultTotalAtBreach) external onlyRole(SIGNER_MANAGER_ROLE) {
        uint128 amount = uint128((uint256(vaultTotalAtBreach) * drawdownSlashSizeBps) / 10_000);
        vault.slashVault(agentId, amount);
    }

    // -------- signer management --------

    function addSigner(address s) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (isSigner[s]) revert SignerAlreadyExists();
        isSigner[s] = true;
        signers.push(s);
        emit SignerAdded(s);
    }

    function removeSigner(address s) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (!isSigner[s]) revert UnknownSigner();
        isSigner[s] = false;
        // Compact signers array
        uint256 n = signers.length;
        for (uint256 i = 0; i < n; i++) {
            if (signers[i] == s) {
                signers[i] = signers[n - 1];
                signers.pop();
                break;
            }
        }
        if (threshold > signers.length) threshold = uint8(signers.length);
        emit SignerRemoved(s);
    }

    function setThreshold(uint8 t) external onlyRole(SIGNER_MANAGER_ROLE) {
        if (t == 0 || t > signers.length) revert InvalidThreshold();
        threshold = t;
        emit ThresholdUpdated(t);
    }

    function setDrawdownParams(uint16 _drawdownBps, uint16 _slashSizeBps) external onlyRole(SIGNER_MANAGER_ROLE) {
        require(_drawdownBps <= 10_000 && _slashSizeBps <= 5_000, "cap");
        drawdownSlashBps = _drawdownBps;
        drawdownSlashSizeBps = _slashSizeBps;
    }

    // -------- views --------

    function getSigners() external view returns (address[] memory) { return signers; }
}
