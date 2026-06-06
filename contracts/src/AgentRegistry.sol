// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AgentRegistry
/// @notice Permissionless registry for autonomous trading agents. Operators post a $LIT bond
///         to enroll. Bonds are slashed by the StakingVault on confirmed misbehavior (oracle fraud,
///         exploit attempts, sustained drawdown beyond limit).
contract AgentRegistry is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");

    enum AgentStatus { Active, Paused, Slashed, Withdrawn }

    struct Agent {
        address controller;       // address authorized to update agent metadata + post attestations
        uint64 enrolledAt;        // block.timestamp at enrollment
        uint64 unbondedAt;        // 0 unless withdraw initiated
        uint128 bond;             // $LIT posted at enrollment (incl. top-ups)
        AgentStatus status;
        bytes32 metadataHash;     // IPFS CID of off-chain manifest (strategy, venues, code hash)
        uint16 protocolFeeBps;    // protocol fee on agent gross profit, in bps (e.g. 1000 = 10%)
    }

    IERC20 public immutable alphaToken;

    /// @notice Minimum bond required to enroll (configurable)
    uint128 public minBond = 10_000 ether; // 10,000 $LIT default

    /// @notice Cooldown before bond can be withdrawn after `withdrawInit`
    uint64 public unbondingPeriod = 14 days;

    /// @notice Max protocol fee an agent can charge (bps; cap protects stakers)
    uint16 public maxProtocolFeeBps = 5000; // 50%

    uint256 public nextAgentId = 1;
    mapping(uint256 => Agent) public agents;

    // -------- events --------

    event AgentEnrolled(uint256 indexed agentId, address indexed controller, uint128 bond, bytes32 metadataHash, uint16 protocolFeeBps);
    event AgentBondTopUp(uint256 indexed agentId, uint128 amount);
    event AgentMetadataUpdated(uint256 indexed agentId, bytes32 metadataHash);
    event AgentPaused(uint256 indexed agentId);
    event AgentResumed(uint256 indexed agentId);
    event AgentSlashed(uint256 indexed agentId, uint128 slashedAmount, address indexed slasher);
    event AgentWithdrawInit(uint256 indexed agentId, uint64 unbondedAt);
    event AgentWithdrawn(uint256 indexed agentId, uint128 returnedBond);

    // -------- errors --------

    error InvalidController();
    error AgentNotFound();
    error NotController();
    error NotActive();
    error InsufficientBond();
    error UnbondingNotStarted();
    error UnbondingNotComplete();
    error FeeTooHigh();

    constructor(IERC20 _alphaToken, address _admin) {
        alphaToken = _alphaToken;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(CONFIG_ROLE, _admin);
    }

    // -------- agent operator entrypoints --------

    /// @notice Enroll a new agent.
    /// @param controller The address that controls metadata + (in v1) signs price/PnL updates.
    /// @param bondAmount Tokens to lock as bond. Must be >= minBond.
    /// @param metadataHash IPFS CID (or other content-address) of agent's off-chain manifest.
    /// @param protocolFeeBps Fee on agent gross profit in basis points.
    function enroll(
        address controller,
        uint128 bondAmount,
        bytes32 metadataHash,
        uint16 protocolFeeBps
    ) external nonReentrant returns (uint256 agentId) {
        if (controller == address(0)) revert InvalidController();
        if (bondAmount < minBond) revert InsufficientBond();
        if (protocolFeeBps > maxProtocolFeeBps) revert FeeTooHigh();

        agentId = nextAgentId++;
        agents[agentId] = Agent({
            controller: controller,
            enrolledAt: uint64(block.timestamp),
            unbondedAt: 0,
            bond: bondAmount,
            status: AgentStatus.Active,
            metadataHash: metadataHash,
            protocolFeeBps: protocolFeeBps
        });

        alphaToken.safeTransferFrom(msg.sender, address(this), bondAmount);
        emit AgentEnrolled(agentId, controller, bondAmount, metadataHash, protocolFeeBps);
    }

    /// @notice Top up an existing agent's bond. Anyone can pay (sponsorship friendly).
    function topUpBond(uint256 agentId, uint128 amount) external nonReentrant {
        Agent storage a = agents[agentId];
        if (a.controller == address(0)) revert AgentNotFound();
        if (a.status != AgentStatus.Active) revert NotActive();

        a.bond += amount;
        alphaToken.safeTransferFrom(msg.sender, address(this), amount);
        emit AgentBondTopUp(agentId, amount);
    }

    /// @notice Update agent metadata (controller only).
    function updateMetadata(uint256 agentId, bytes32 newHash) external {
        Agent storage a = agents[agentId];
        if (msg.sender != a.controller) revert NotController();
        a.metadataHash = newHash;
        emit AgentMetadataUpdated(agentId, newHash);
    }

    /// @notice Initiate bond withdrawal. Sets unbondedAt; bond is locked for `unbondingPeriod`.
    function withdrawInit(uint256 agentId) external {
        Agent storage a = agents[agentId];
        if (msg.sender != a.controller) revert NotController();
        if (a.status != AgentStatus.Active && a.status != AgentStatus.Paused) revert NotActive();

        a.unbondedAt = uint64(block.timestamp);
        a.status = AgentStatus.Paused;
        emit AgentWithdrawInit(agentId, a.unbondedAt);
    }

    /// @notice Complete bond withdrawal after cooldown.
    function withdrawComplete(uint256 agentId) external nonReentrant {
        Agent storage a = agents[agentId];
        if (msg.sender != a.controller) revert NotController();
        if (a.unbondedAt == 0) revert UnbondingNotStarted();
        if (block.timestamp < a.unbondedAt + unbondingPeriod) revert UnbondingNotComplete();

        uint128 amount = a.bond;
        a.bond = 0;
        a.status = AgentStatus.Withdrawn;
        alphaToken.safeTransfer(a.controller, amount);
        emit AgentWithdrawn(agentId, amount);
    }

    // -------- governance / slasher entrypoints --------

    /// @notice Slash a fraction of the bond. Slashed tokens are sent to the burn address (sink).
    /// @dev Call from StakingVault or governance when oracle confirms misbehavior.
    function slash(uint256 agentId, uint128 amount, address burnSink) external onlyRole(SLASHER_ROLE) nonReentrant {
        Agent storage a = agents[agentId];
        if (a.controller == address(0)) revert AgentNotFound();

        uint128 slashAmt = amount > a.bond ? a.bond : amount;
        a.bond -= slashAmt;
        if (a.bond < minBond) {
            a.status = AgentStatus.Slashed;
        }
        alphaToken.safeTransfer(burnSink, slashAmt);
        emit AgentSlashed(agentId, slashAmt, msg.sender);
    }

    function pauseAgent(uint256 agentId) external onlyRole(CONFIG_ROLE) {
        agents[agentId].status = AgentStatus.Paused;
        emit AgentPaused(agentId);
    }

    function resumeAgent(uint256 agentId) external onlyRole(CONFIG_ROLE) {
        agents[agentId].status = AgentStatus.Active;
        emit AgentResumed(agentId);
    }

    // -------- config --------

    function setMinBond(uint128 v) external onlyRole(CONFIG_ROLE) { minBond = v; }
    function setUnbondingPeriod(uint64 v) external onlyRole(CONFIG_ROLE) { unbondingPeriod = v; }
    function setMaxProtocolFeeBps(uint16 v) external onlyRole(CONFIG_ROLE) { maxProtocolFeeBps = v; }

    // -------- views --------

    function isActive(uint256 agentId) external view returns (bool) {
        return agents[agentId].status == AgentStatus.Active;
    }

    function getAgent(uint256 agentId) external view returns (Agent memory) {
        return agents[agentId];
    }
}
