// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {AgentRegistry} from "./AgentRegistry.sol";

/// @title StakingVault
/// @notice One vault, many agents. Stakers deposit $LITNUP against a specific agentId.
///         Vault uses share accounting (ERC4626-style) per-agent: shares track each staker's
///         pro-rata claim on that agent's vault. PnL credited or debited by the PerformanceOracle
///         scales the totalAssets per agent, changing share price.
contract StakingVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    IERC20 public immutable alphaToken;
    AgentRegistry public immutable registry;
    address public buybackBurnSink;

    /// @notice Per-agent vault state.
    struct Vault {
        uint128 totalAssets;     // total $LITNUP backing this agent's stakers
        uint128 totalShares;     // outstanding shares for this agent's vault
        uint64 lastAttestation;  // timestamp of last PnL attestation
        uint64 cooldown;         // seconds; default 7 days
    }

    /// @notice Per-(agent, staker) state.
    struct StakerInfo {
        uint128 shares;
        uint64 unlockAt;       // timestamp when withdraw becomes possible after init
        uint128 pendingShares; // shares queued for withdraw
    }

    mapping(uint256 agentId => Vault) public vaults;
    mapping(uint256 agentId => mapping(address staker => StakerInfo)) public stakers;

    /// @notice Cap on total assets a single vault can hold (initial safety, can be raised by governance)
    uint128 public perVaultCap = 1_000_000 ether; // 1M $LITNUP default

    // -------- events --------

    event Staked(uint256 indexed agentId, address indexed staker, uint128 amount, uint128 shares);
    event UnstakeInit(uint256 indexed agentId, address indexed staker, uint128 shares, uint64 unlockAt);
    event Unstaked(uint256 indexed agentId, address indexed staker, uint128 shares, uint128 amount);
    event PnlApplied(uint256 indexed agentId, int128 delta, uint128 newTotalAssets);
    event FeesTaken(uint256 indexed agentId, uint128 toBuyback, uint128 toStakers);
    event StakerSlashed(uint256 indexed agentId, uint128 amount);
    event PerVaultCapUpdated(uint128 newCap);
    event BuybackBurnSinkUpdated(address newSink);

    // -------- errors --------

    error AgentNotActive();
    error InsufficientShares();
    error VaultCapExceeded();
    error CooldownNotElapsed();
    error NothingToWithdraw();
    error InvalidPnlSize();

    constructor(
        IERC20 _alphaToken,
        AgentRegistry _registry,
        address _admin,
        address _buybackBurnSink
    ) {
        alphaToken = _alphaToken;
        registry = _registry;
        buybackBurnSink = _buybackBurnSink;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
    }

    // -------- staker entrypoints --------

    /// @notice Stake $LITNUP against an active agent. Mints shares pro-rata.
    function stake(uint256 agentId, uint128 amount) external nonReentrant returns (uint128 shares) {
        if (!registry.isActive(agentId)) revert AgentNotActive();
        Vault storage v = vaults[agentId];
        if (v.totalAssets + amount > perVaultCap) revert VaultCapExceeded();

        shares = _toShares(v, amount);

        // Initialize cooldown for first staker
        if (v.cooldown == 0) v.cooldown = 7 days;

        v.totalAssets += amount;
        v.totalShares += shares;
        stakers[agentId][msg.sender].shares += shares;

        alphaToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(agentId, msg.sender, amount, shares);
    }

    /// @notice Initiate unstake. Locks `shares` for cooldown period.
    function unstakeInit(uint256 agentId, uint128 shares) external {
        StakerInfo storage s = stakers[agentId][msg.sender];
        if (shares > s.shares) revert InsufficientShares();
        s.shares -= shares;
        s.pendingShares += shares;
        s.unlockAt = uint64(block.timestamp) + vaults[agentId].cooldown;
        emit UnstakeInit(agentId, msg.sender, shares, s.unlockAt);
    }

    /// @notice Complete unstake after cooldown elapsed.
    function unstakeComplete(uint256 agentId) external nonReentrant returns (uint128 amount) {
        StakerInfo storage s = stakers[agentId][msg.sender];
        if (s.pendingShares == 0) revert NothingToWithdraw();
        if (block.timestamp < s.unlockAt) revert CooldownNotElapsed();

        Vault storage v = vaults[agentId];
        amount = _toAssets(v, s.pendingShares);

        // burn pending shares against the vault
        v.totalShares -= s.pendingShares;
        v.totalAssets -= amount;

        emit Unstaked(agentId, msg.sender, s.pendingShares, amount);
        s.pendingShares = 0;
        s.unlockAt = 0;

        alphaToken.safeTransfer(msg.sender, amount);
    }

    // -------- oracle entrypoints --------

    /// @notice Apply a PnL delta (signed) to an agent's vault. Positive = profit, negative = loss.
    /// @dev Called by PerformanceOracle. Caps protect against oracle bugs.
    function applyPnl(uint256 agentId, int128 delta) external onlyRole(ORACLE_ROLE) {
        Vault storage v = vaults[agentId];
        // Cap delta at +/-50% of vault to limit blast radius of an oracle bug
        uint128 cap = v.totalAssets / 2;
        if (delta > 0 && uint128(delta) > cap) revert InvalidPnlSize();
        if (delta < 0 && uint128(-delta) > cap) revert InvalidPnlSize();

        if (delta > 0) {
            v.totalAssets += uint128(delta);
        } else if (delta < 0) {
            uint128 loss = uint128(-delta);
            v.totalAssets = loss > v.totalAssets ? 0 : v.totalAssets - loss;
        }
        v.lastAttestation = uint64(block.timestamp);
        emit PnlApplied(agentId, delta, v.totalAssets);
    }

    /// @notice Take protocol fees on positive PnL. Splits between buyback sink and stakers.
    /// @param agentId Agent
    /// @param feeOnGross Total fee in $LITNUP to remove from vault
    /// @param toBuybackBps Fraction of fee directed to buyback (rest stays in vault for stakers)
    function takeFees(uint256 agentId, uint128 feeOnGross, uint16 toBuybackBps)
        external
        onlyRole(ORACLE_ROLE)
        nonReentrant
    {
        require(toBuybackBps <= 10_000, "bps");
        Vault storage v = vaults[agentId];
        if (feeOnGross > v.totalAssets) feeOnGross = v.totalAssets;
        v.totalAssets -= feeOnGross;

        uint128 toBuyback = uint128((uint256(feeOnGross) * toBuybackBps) / 10_000);
        uint128 toStakers = feeOnGross - toBuyback;

        if (toBuyback > 0) {
            alphaToken.safeTransfer(buybackBurnSink, toBuyback);
        }
        // `toStakers` stays in vault: it lifts share price for current stakers.
        // (We removed it from totalAssets above; return it.)
        v.totalAssets += toStakers;

        emit FeesTaken(agentId, toBuyback, toStakers);
    }

    /// @notice Slash a fraction of staker funds in a vault (sustained drawdown breach).
    /// @dev Slashed assets sent to burn sink. Vault total assets decrease; share price drops.
    function slashVault(uint256 agentId, uint128 amount) external onlyRole(ORACLE_ROLE) nonReentrant {
        Vault storage v = vaults[agentId];
        uint128 slashAmt = amount > v.totalAssets ? v.totalAssets : amount;
        v.totalAssets -= slashAmt;
        alphaToken.safeTransfer(buybackBurnSink, slashAmt);
        emit StakerSlashed(agentId, slashAmt);
    }

    // -------- config --------

    function setPerVaultCap(uint128 v) external onlyRole(CONFIG_ROLE) {
        perVaultCap = v;
        emit PerVaultCapUpdated(v);
    }

    function setBuybackBurnSink(address sink) external onlyRole(CONFIG_ROLE) {
        buybackBurnSink = sink;
        emit BuybackBurnSinkUpdated(sink);
    }

    function setCooldown(uint256 agentId, uint64 cooldown) external onlyRole(CONFIG_ROLE) {
        require(cooldown <= 30 days, "cap");
        vaults[agentId].cooldown = cooldown;
    }

    // -------- views --------

    function previewStake(uint256 agentId, uint128 amount) external view returns (uint128) {
        return _toShares(vaults[agentId], amount);
    }

    function previewUnstake(uint256 agentId, uint128 shares) external view returns (uint128) {
        return _toAssets(vaults[agentId], shares);
    }

    function sharePrice(uint256 agentId) external view returns (uint256) {
        Vault memory v = vaults[agentId];
        if (v.totalShares == 0) return 1e18;
        return (uint256(v.totalAssets) * 1e18) / v.totalShares;
    }

    // -------- internal --------

    function _toShares(Vault memory v, uint128 amount) internal pure returns (uint128) {
        if (v.totalShares == 0 || v.totalAssets == 0) {
            return amount;
        }
        return uint128(uint256(amount).mulDiv(v.totalShares, v.totalAssets));
    }

    function _toAssets(Vault memory v, uint128 shares) internal pure returns (uint128) {
        if (v.totalShares == 0) return 0;
        return uint128(uint256(shares).mulDiv(v.totalAssets, v.totalShares));
    }
}
