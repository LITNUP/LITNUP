// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title RewardsDistributor
/// @notice Periodic merkle-root reward distribution for veLITNUP lockers and
///         agent operators. Each "epoch" the protocol publishes a single root
///         covering all eligible recipients; recipients pull at any time.
///
///         Why merkle-root over per-recipient transfer? Two reasons:
///         1) Gas. A single root replaces N transfers, computed off-chain.
///         2) Audit. The root commits to a complete recipient list at a moment
///            in time; anyone can verify a recipient's inclusion or exclusion.
///
///         Each recipient may have multiple "channels" (rewards from different
///         buckets — e.g. veLITNUP weekly emission, operator performance fees,
///         insurance-fund payouts). Each channel has independent merkle roots.
contract RewardsDistributor is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant FUNDER_ROLE      = keccak256("FUNDER_ROLE");

    IERC20 public immutable rewardToken;

    /// @notice Per-channel merkle root, set once per epoch.
    /// channelId is a free-form bytes32 (e.g. keccak256("ve-week-12") or keccak256("operator-q3")).
    mapping(bytes32 channelId => bytes32 root) public roots;

    /// @notice Per-channel cumulative claim record by user. Stored as cumulative-amount
    /// so that one merkle proof can supersede earlier claims (saves recipient gas if
    /// they don't claim every epoch). Recipient claims `amount - claimed[channel][user]`.
    mapping(bytes32 channelId => mapping(address user => uint256 claimedSoFar)) public claimedSoFar;

    /// @notice Per-channel total amount funded into the contract.
    mapping(bytes32 channelId => uint256 funded) public funded;

    /// @notice Per-channel total amount claimed.
    mapping(bytes32 channelId => uint256 claimed) public totalClaimed;

    /// @notice Channel metadata for indexers + UI.
    struct Channel {
        string  description;     // human label e.g. "veLITNUP weekly"
        uint64  publishedAt;
        bool    active;
    }
    mapping(bytes32 channelId => Channel) public channels;

    // -------- events --------

    event ChannelRegistered(bytes32 indexed channelId, string description);
    event RootPublished(bytes32 indexed channelId, bytes32 root, uint256 totalAmount);
    event Funded(bytes32 indexed channelId, uint256 amount);
    event Claimed(bytes32 indexed channelId, address indexed user, uint256 amount, uint256 cumulative);
    event ChannelDeactivated(bytes32 indexed channelId);

    // -------- errors --------

    error ChannelInactive();
    error ChannelStillActive();
    error InvalidProof();
    error AlreadyFullyClaimed();
    error InsufficientFunding();
    error NothingToRecover();

    event FundsRecovered(bytes32 indexed channelId, address indexed to, uint256 amount);

    constructor(IERC20 _rewardToken, address _admin) {
        rewardToken = _rewardToken;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _admin);
        _grantRole(FUNDER_ROLE, _admin);
    }

    // ============================================================
    // ADMIN
    // ============================================================

    function registerChannel(bytes32 channelId, string calldata description)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        channels[channelId] = Channel({
            description: description,
            publishedAt: uint64(block.timestamp),
            active: true
        });
        emit ChannelRegistered(channelId, description);
    }

    function publishRoot(bytes32 channelId, bytes32 root, uint256 epochTotalAmount)
        external
        onlyRole(DISTRIBUTOR_ROLE)
    {
        if (!channels[channelId].active) revert ChannelInactive();
        roots[channelId] = root;
        // We don't track per-epoch totals — we just emit for indexers.
        emit RootPublished(channelId, root, epochTotalAmount);
    }

    function fundChannel(bytes32 channelId, uint256 amount) external onlyRole(FUNDER_ROLE) {
        if (!channels[channelId].active) revert ChannelInactive();
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        funded[channelId] += amount;
        emit Funded(channelId, amount);
    }

    function deactivateChannel(bytes32 channelId) external onlyRole(DISTRIBUTOR_ROLE) {
        channels[channelId].active = false;
        emit ChannelDeactivated(channelId);
    }

    /// @notice Recover the unclaimed funded balance of a DEACTIVATED channel (e.g. over-funding or a
    ///         retired/erroneous channel). Prevents funds being permanently frozen by deactivation.
    /// @dev Requires the channel to be inactive first, so it cannot rug in-flight legitimate claims.
    function recoverChannelFunds(bytes32 channelId, address to)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        if (channels[channelId].active) revert ChannelStillActive();
        uint256 remaining = funded[channelId] - totalClaimed[channelId];
        if (remaining == 0) revert NothingToRecover();
        funded[channelId] = totalClaimed[channelId]; // zero out the recoverable remainder
        rewardToken.safeTransfer(to, remaining);
        emit FundsRecovered(channelId, to, remaining);
    }

    // ============================================================
    // CLAIMS
    // ============================================================

    /// @notice Claim rewards. `cumulativeAmount` is the user's total cumulative entitlement
    ///         across all epochs covered by the current root. The contract subtracts
    ///         `claimedSoFar` to compute the actual transfer.
    function claim(
        bytes32 channelId,
        address user,
        uint256 cumulativeAmount,
        bytes32[] calldata proof
    ) external nonReentrant returns (uint256 paid) {
        if (!channels[channelId].active) revert ChannelInactive();

        // channelId is bound into the leaf so a proof for one channel cannot be replayed against
        // another channel that happens to share the same root.
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(channelId, user, cumulativeAmount))));
        if (!MerkleProof.verify(proof, roots[channelId], leaf)) revert InvalidProof();

        uint256 already = claimedSoFar[channelId][user];
        if (cumulativeAmount <= already) revert AlreadyFullyClaimed();

        paid = cumulativeAmount - already;
        if (totalClaimed[channelId] + paid > funded[channelId]) revert InsufficientFunding();

        claimedSoFar[channelId][user] = cumulativeAmount;
        totalClaimed[channelId] += paid;

        rewardToken.safeTransfer(user, paid);
        emit Claimed(channelId, user, paid, cumulativeAmount);
    }

    /// @notice Multi-channel claim helper for UX.
    function claimMany(
        bytes32[] calldata channelIds,
        address user,
        uint256[] calldata cumulativeAmounts,
        bytes32[][] calldata proofs
    ) external nonReentrant returns (uint256 totalPaid) {
        require(channelIds.length == cumulativeAmounts.length, "len");
        require(channelIds.length == proofs.length, "len");

        for (uint256 i = 0; i < channelIds.length; i++) {
            bytes32 cid = channelIds[i];
            if (!channels[cid].active) continue;

            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(cid, user, cumulativeAmounts[i]))));
            if (!MerkleProof.verify(proofs[i], roots[cid], leaf)) continue;

            uint256 already = claimedSoFar[cid][user];
            if (cumulativeAmounts[i] <= already) continue;
            uint256 paid = cumulativeAmounts[i] - already;
            if (totalClaimed[cid] + paid > funded[cid]) continue;

            claimedSoFar[cid][user] = cumulativeAmounts[i];
            totalClaimed[cid] += paid;
            totalPaid += paid;
            rewardToken.safeTransfer(user, paid);
            emit Claimed(cid, user, paid, cumulativeAmounts[i]);
        }
    }

    // ============================================================
    // VIEWS
    // ============================================================

    function pendingClaim(bytes32 channelId, address user, uint256 cumulativeAmount)
        external
        view
        returns (uint256)
    {
        uint256 already = claimedSoFar[channelId][user];
        if (cumulativeAmount <= already) return 0;
        return cumulativeAmount - already;
    }

    function unclaimedFunds(bytes32 channelId) external view returns (uint256) {
        return funded[channelId] - totalClaimed[channelId];
    }
}
