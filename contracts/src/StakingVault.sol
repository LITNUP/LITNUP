// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {AgentRegistry} from "./AgentRegistry.sol";

/// @title StakingVault
/// @notice One vault, many agents. Stakers deposit $LITNUP against a specific agentId as a
///         bonded conviction stake (curation + skin-in-the-game), NOT as a trading position.
///
///         SOLVENCY MODEL (v2):
///         The off-chain trading never touches staked $LITNUP. Therefore staked principal is
///         redeemable at PRINCIPAL value and is only ever *reduced* by slashing — attested PnL
///         does NOT inflate redeemable assets (that was the v1 insolvency bug: crediting profit
///         that no token backed). The protocol's core solvency invariant is:
///
///             litnupToken.balanceOf(this) >= Σ_agents vaults[agent].totalPrincipal
///
///         and it holds by construction: principal only enters via stake() and only leaves via
///         unstakeComplete() / slashVault(), each moving exactly the accounted amount.
///
///         YIELD:
///         Stakers earn real, exogenous yield paid by operators as a performance fee in an
///         external settlement asset (rewardToken, e.g. USDC) via takeFees(). Rewards accrue
///         per-agent through an accRewardPerShare accumulator and are claimed separately; they
///         are never minted or assumed — only credited when real tokens are transferred in.
///
///         PnL attestations drive reputation/ranking (recordPnl) and the fee basis, not share price.
contract StakingVault is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using SafeCast for uint256;

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Fixed-point precision for the reward-per-share accumulator.
    uint256 private constant ACC_PRECISION = 1e18;

    /// @notice The staked/bonded asset.
    IERC20 public immutable litnupToken;
    /// @notice The reward/settlement asset paid to stakers (e.g. USDC). Exogenous value.
    IERC20 public immutable rewardToken;
    AgentRegistry public immutable registry;
    address public buybackBurnSink;

    /// @notice Per-agent vault state.
    struct Vault {
        uint128 totalPrincipal;     // real $LITNUP backing this agent's stakers (only stake/unstake/slash move it)
        uint128 totalShares;        // outstanding shares (active + cooling-down)
        uint128 rewardShares;       // active shares only — the base that earns reward-token yield
        uint64 cooldown;            // seconds; default 7 days
        int256 cumulativePnl;       // attested cumulative PnL (reputation/fee basis only; never moves assets)
        uint256 accRewardPerShare;  // accumulated reward-token per active share, scaled by ACC_PRECISION
    }

    /// @notice Per-(agent, staker) state.
    struct StakerInfo {
        uint128 shares;         // active shares (earning + redeemable)
        uint128 pendingShares;  // cooling-down shares (redeemable at current price, not earning)
        uint64 unlockAt;        // timestamp when cooling shares become withdrawable
        uint256 rewardDebt;     // shares * accRewardPerShare / ACC at last settle
        uint256 claimable;      // settled reward-token owed to this staker
    }

    mapping(uint256 agentId => Vault) public vaults;
    mapping(uint256 agentId => mapping(address staker => StakerInfo)) public stakers;

    /// @notice Cap on total principal a single vault can hold (initial safety, raisable by governance)
    uint128 public perVaultCap = 1_000_000 ether; // 1M $LITNUP default

    // -------- events --------

    event Staked(uint256 indexed agentId, address indexed staker, uint128 amount, uint128 shares);
    event UnstakeInit(uint256 indexed agentId, address indexed staker, uint128 shares, uint64 unlockAt);
    event Unstaked(uint256 indexed agentId, address indexed staker, uint128 shares, uint128 amount);
    event PnlRecorded(uint256 indexed agentId, int256 delta, int256 cumulativePnl);
    event FeesTaken(uint256 indexed agentId, uint128 toBuyback, uint128 toStakers);
    event RewardsClaimed(uint256 indexed agentId, address indexed staker, uint256 amount);
    event StakerSlashed(uint256 indexed agentId, uint128 amount);
    event PerVaultCapUpdated(uint128 newCap);
    event BuybackBurnSinkUpdated(address newSink);
    event CooldownUpdated(uint256 indexed agentId, uint64 cooldown);

    // -------- errors --------

    error AgentNotActive();
    error InsufficientShares();
    error VaultCapExceeded();
    error CooldownNotElapsed();
    error NothingToWithdraw();
    error ZeroAmount();
    error ZeroShares();
    error NoActiveStakers();

    constructor(
        IERC20 _litnupToken,
        IERC20 _rewardToken,
        AgentRegistry _registry,
        address _admin,
        address _buybackBurnSink
    ) {
        require(address(_litnupToken) != address(0), "litnup=0");
        require(address(_rewardToken) != address(0), "reward=0");
        require(address(_registry) != address(0), "registry=0");
        require(_admin != address(0), "admin=0");
        require(_buybackBurnSink != address(0), "sink=0");
        litnupToken = _litnupToken;
        rewardToken = _rewardToken;
        registry = _registry;
        buybackBurnSink = _buybackBurnSink;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    // -------- staker entrypoints --------

    /// @notice Stake $LITNUP against an active agent. Mints shares pro-rata to redeemable principal.
    function stake(uint256 agentId, uint128 amount)
        external
        nonReentrant
        whenNotPaused
        returns (uint128 shares)
    {
        if (amount == 0) revert ZeroAmount();
        if (!registry.isActive(agentId)) revert AgentNotActive();
        Vault storage v = vaults[agentId];
        if (uint256(v.totalPrincipal) + amount > perVaultCap) revert VaultCapExceeded();

        // Initialize cooldown for first staker
        if (v.cooldown == 0) v.cooldown = 7 days;

        StakerInfo storage s = stakers[agentId][msg.sender];
        _settle(v, s);

        shares = _toShares(v, amount);
        if (shares == 0) revert ZeroShares();

        v.totalPrincipal += amount;
        v.totalShares += shares;
        v.rewardShares += shares;
        s.shares += shares;
        _resetRewardDebt(v, s);

        litnupToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(agentId, msg.sender, amount, shares);
    }

    /// @notice Initiate unstake. Moves `shares` into a cooling-down bucket for the cooldown period.
    ///         Cooling shares stop earning yield but remain redeemable at the current (slash-adjusted)
    ///         share price and remain slashable until completion.
    function unstakeInit(uint256 agentId, uint128 shares) external nonReentrant {
        if (shares == 0) revert ZeroAmount();
        Vault storage v = vaults[agentId];
        StakerInfo storage s = stakers[agentId][msg.sender];
        if (shares > s.shares) revert InsufficientShares();

        _settle(v, s);

        s.shares -= shares;
        s.pendingShares += shares;
        v.rewardShares -= shares; // cooling shares no longer earn; totalShares unchanged (still claim principal)
        s.unlockAt = uint64(block.timestamp) + v.cooldown;
        _resetRewardDebt(v, s);

        emit UnstakeInit(agentId, msg.sender, shares, s.unlockAt);
    }

    /// @notice Complete unstake after cooldown elapsed. Pays out principal at the current share price.
    function unstakeComplete(uint256 agentId) external nonReentrant returns (uint128 amount) {
        StakerInfo storage s = stakers[agentId][msg.sender];
        if (s.pendingShares == 0) revert NothingToWithdraw();
        if (block.timestamp < s.unlockAt) revert CooldownNotElapsed();

        Vault storage v = vaults[agentId];
        uint128 pending = s.pendingShares;
        amount = _toAssets(v, pending);

        v.totalShares -= pending;
        v.totalPrincipal -= amount;
        s.pendingShares = 0;
        s.unlockAt = 0;

        emit Unstaked(agentId, msg.sender, pending, amount);
        litnupToken.safeTransfer(msg.sender, amount);
    }

    /// @notice Claim accrued reward-token (e.g. USDC) yield for an agent.
    function claimRewards(uint256 agentId) external nonReentrant returns (uint256 amount) {
        Vault storage v = vaults[agentId];
        StakerInfo storage s = stakers[agentId][msg.sender];
        _settle(v, s);
        amount = s.claimable;
        if (amount == 0) revert NothingToWithdraw();
        s.claimable = 0;
        rewardToken.safeTransfer(msg.sender, amount);
        emit RewardsClaimed(agentId, msg.sender, amount);
    }

    // -------- oracle entrypoints --------

    /// @notice Record an attested PnL delta for an agent. Reputation/fee basis ONLY — moves no assets.
    /// @dev This is the safe replacement for v1's applyPnl, which inflated redeemable assets with
    ///      tokens that did not exist. Off-chain trading PnL is informational on-chain.
    function recordPnl(uint256 agentId, int256 delta) external onlyRole(ORACLE_ROLE) whenNotPaused {
        Vault storage v = vaults[agentId];
        v.cumulativePnl += delta;
        emit PnlRecorded(agentId, delta, v.cumulativePnl);
    }

    /// @notice Take a performance fee in the reward token (USDC) and split it between the buyback
    ///         sink and the agent's stakers. The fee is pulled as REAL tokens from `feePayer`;
    ///         nothing is credited unless the transfer succeeds (no phantom accounting).
    /// @param agentId Agent
    /// @param feeAmount Total fee in reward-token units to pull from feePayer
    /// @param toBuybackBps Fraction of the fee directed to buyback (rest streams to stakers)
    /// @param feePayer Address that has approved this vault to pull the fee (the operator)
    function takeFees(uint256 agentId, uint128 feeAmount, uint16 toBuybackBps, address feePayer)
        external
        onlyRole(ORACLE_ROLE)
        nonReentrant
        whenNotPaused
    {
        require(toBuybackBps <= 10_000, "bps");
        if (feeAmount == 0) revert ZeroAmount();
        Vault storage v = vaults[agentId];

        // Pull the real fee in first (checks-effects: we only account what actually arrived).
        rewardToken.safeTransferFrom(feePayer, address(this), feeAmount);

        uint128 toBuyback = uint128((uint256(feeAmount) * toBuybackBps) / 10_000);
        uint128 toStakers = feeAmount - toBuyback;

        // If there are no active stakers, the whole fee goes to buyback (no funds get stranded).
        if (v.rewardShares == 0) {
            toBuyback = feeAmount;
            toStakers = 0;
        } else if (toStakers > 0) {
            v.accRewardPerShare += (uint256(toStakers) * ACC_PRECISION) / v.rewardShares;
        }

        if (toBuyback > 0) {
            rewardToken.safeTransfer(buybackBurnSink, toBuyback);
        }

        emit FeesTaken(agentId, toBuyback, toStakers);
    }

    /// @notice Slash a fraction of staker principal in a vault (confirmed misbehavior / breach).
    /// @dev Slashed principal (real $LITNUP) is sent to the burn sink; share price drops honestly.
    function slashVault(uint256 agentId, uint128 amount)
        external
        onlyRole(ORACLE_ROLE)
        nonReentrant
        whenNotPaused
    {
        Vault storage v = vaults[agentId];
        uint128 slashAmt = amount > v.totalPrincipal ? v.totalPrincipal : amount;
        if (slashAmt == 0) revert ZeroAmount();
        v.totalPrincipal -= slashAmt;
        litnupToken.safeTransfer(buybackBurnSink, slashAmt);
        emit StakerSlashed(agentId, slashAmt);
    }

    // -------- config --------

    function setPerVaultCap(uint128 v) external onlyRole(CONFIG_ROLE) {
        perVaultCap = v;
        emit PerVaultCapUpdated(v);
    }

    function setBuybackBurnSink(address sink) external onlyRole(CONFIG_ROLE) {
        require(sink != address(0), "sink=0");
        buybackBurnSink = sink;
        emit BuybackBurnSinkUpdated(sink);
    }

    function setCooldown(uint256 agentId, uint64 cooldown) external onlyRole(CONFIG_ROLE) {
        require(cooldown <= 30 days, "cap");
        vaults[agentId].cooldown = cooldown;
        emit CooldownUpdated(agentId, cooldown);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // -------- views --------

    function previewStake(uint256 agentId, uint128 amount) external view returns (uint128) {
        return _toShares(vaults[agentId], amount);
    }

    function previewUnstake(uint256 agentId, uint128 shares) external view returns (uint128) {
        return _toAssets(vaults[agentId], shares);
    }

    /// @notice Redeemable principal per share, scaled by 1e18. Starts at 1.0 and only drops on slash.
    function sharePrice(uint256 agentId) external view returns (uint256) {
        Vault memory v = vaults[agentId];
        if (v.totalShares == 0) return 1e18;
        return (uint256(v.totalPrincipal) * 1e18) / v.totalShares;
    }

    /// @notice Pending (unclaimed) reward-token yield for a staker on an agent.
    function pendingRewards(uint256 agentId, address staker) external view returns (uint256) {
        Vault memory v = vaults[agentId];
        StakerInfo memory s = stakers[agentId][staker];
        uint256 accrued = (uint256(s.shares) * v.accRewardPerShare) / ACC_PRECISION;
        uint256 newPart = accrued > s.rewardDebt ? accrued - s.rewardDebt : 0;
        return s.claimable + newPart;
    }

    // -------- internal --------

    /// @dev Settle a staker's accrued rewards into `claimable` based on their ACTIVE shares, and
    ///      advance rewardDebt to the current accrual so the same rewards are never credited twice
    ///      (the standard MasterChef accumulator pattern). Callers that then change `shares` must
    ///      follow with _resetRewardDebt to re-anchor the debt to the new share count.
    function _settle(Vault storage v, StakerInfo storage s) internal {
        uint256 accrued = (uint256(s.shares) * v.accRewardPerShare) / ACC_PRECISION;
        if (accrued > s.rewardDebt) {
            s.claimable += accrued - s.rewardDebt;
        }
        s.rewardDebt = accrued;
    }

    function _resetRewardDebt(Vault storage v, StakerInfo storage s) internal {
        s.rewardDebt = (uint256(s.shares) * v.accRewardPerShare) / ACC_PRECISION;
    }

    /// @dev Shares for a deposit. Internal accounting (not balanceOf) defeats donation/inflation attacks.
    ///      Share price never rises (no PnL inflation), so totalShares >= totalPrincipal always and
    ///      rounding-to-zero cannot strip a non-trivial deposit; the ZeroShares guard backstops dust.
    function _toShares(Vault memory v, uint128 amount) internal pure returns (uint128) {
        if (v.totalShares == 0 || v.totalPrincipal == 0) {
            return amount;
        }
        return uint256(amount).mulDiv(v.totalShares, v.totalPrincipal).toUint128();
    }

    function _toAssets(Vault memory v, uint128 shares) internal pure returns (uint128) {
        if (v.totalShares == 0) return 0;
        return uint256(shares).mulDiv(v.totalPrincipal, v.totalShares).toUint128();
    }
}
