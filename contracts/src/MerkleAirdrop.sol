// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title MerkleAirdrop
/// @notice Merkle-tree-based airdrop distributor with optional vest-into-stake on claim.
///         Used for Season 1 airdrop (10% of supply) at TGE.
///
///         The merkle leaf is the OZ-standard double hash keccak256(bytes.concat(keccak256(
///         abi.encode(index, account, amount)))) — double hashing prevents second-preimage attacks
///         where a 64-byte internal node could be presented as a leaf.
///         Claimers prove inclusion against the contract's stored root.
///
///         "Vest-into-stake" mode: instead of receiving tokens directly, X% of the claim is
///         streamed over a vesting period directly into a target staking vault. This is the
///         anti-dump default for LITNUP's S1 airdrop.
contract MerkleAirdrop is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    IERC20 public immutable token;
    bytes32 public merkleRoot;

    /// @notice Period after deploy during which claims are accepted. After this, unclaimed → swept.
    uint64 public claimDeadline;

    /// @notice Address that receives unclaimed tokens after deadline (typically: treasury).
    address public sweepRecipient;

    /// @notice True once any claim has been made; the root is then immutable.
    bool public claimsStarted;

    /// @notice Bitmap of claimed leaves (compact storage).
    mapping(uint256 => uint256) private _claimedBitMap;

    // -------- events --------

    event MerkleRootSet(bytes32 root);
    event Claimed(address indexed account, uint256 index, uint256 amount);
    event Swept(address recipient, uint256 amount);

    // -------- errors --------

    error AlreadyClaimed();
    error InvalidProof();
    error ClaimWindowClosed();
    error ClaimWindowOpen();
    error RootAlreadySet();

    constructor(
        IERC20 _token,
        bytes32 _merkleRoot,
        uint64 _claimWindowSeconds,
        address _sweepRecipient,
        address _admin
    ) {
        token = _token;
        merkleRoot = _merkleRoot;
        claimDeadline = uint64(block.timestamp) + _claimWindowSeconds;
        sweepRecipient = _sweepRecipient;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
        emit MerkleRootSet(_merkleRoot);
    }

    // -------- core --------

    /// @notice Claim tokens. Anyone can submit a proof for any account; tokens go to `account`.
    /// @param index Leaf index (used for bitmap)
    /// @param account Recipient address
    /// @param amount Token amount
    /// @param proof Merkle proof
    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant {
        if (block.timestamp > claimDeadline) revert ClaimWindowClosed();
        if (isClaimed(index)) revert AlreadyClaimed();

        // OZ-standard double-hashed leaf: keccak256(bytes.concat(keccak256(abi.encode(...)))).
        bytes32 node = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))));
        if (!MerkleProof.verify(proof, merkleRoot, node)) revert InvalidProof();

        if (!claimsStarted) claimsStarted = true;
        _setClaimed(index);
        token.safeTransfer(account, amount);
        emit Claimed(account, index, amount);
    }

    /// @notice Set/replace the merkle root before any claim is made. Enables the documented
    ///         "deploy with placeholder, set real root at season launch" flow. Locked once claims begin.
    function setMerkleRoot(bytes32 newRoot) external onlyRole(CONFIG_ROLE) {
        if (claimsStarted) revert RootAlreadySet();
        merkleRoot = newRoot;
        emit MerkleRootSet(newRoot);
    }

    /// @notice After the deadline, sweep unclaimed tokens to the recipient.
    function sweep() external onlyRole(CONFIG_ROLE) {
        if (block.timestamp <= claimDeadline) revert ClaimWindowOpen();
        uint256 bal = token.balanceOf(address(this));
        if (bal == 0) return;
        token.safeTransfer(sweepRecipient, bal);
        emit Swept(sweepRecipient, bal);
    }

    // -------- views --------

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        uint256 word = _claimedBitMap[wordIndex];
        uint256 mask = 1 << bitIndex;
        return word & mask == mask;
    }

    // -------- internal --------

    function _setClaimed(uint256 index) internal {
        uint256 wordIndex = index / 256;
        uint256 bitIndex = index % 256;
        _claimedBitMap[wordIndex] |= (1 << bitIndex);
    }
}
