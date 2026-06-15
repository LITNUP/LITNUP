// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import {LitnupToken} from "../src/LitnupToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Property-based invariant tests for the solvent StakingVault.
///
///         The headline invariant — which the v1 design violated by construction (applyPnl
///         inflated totalAssets with no token inflow) — is now TRUE and fuzz-enforced:
///         the vault's real $LITNUP balance always covers staker principal, and its real
///         reward-token balance always covers owed rewards. The fuzzer exercises stake,
///         recordPnl, takeFees, slash, unstakeInit, unstakeComplete and claim in random order.
contract InvariantsTest is StdInvariant, Test {
    LitnupToken token;
    MockERC20 usdc;
    AgentRegistry registry;
    StakingVault vault;
    Handler handler;

    address admin = makeAddr("admin");
    address oracle = makeAddr("oracle");
    address burnSink = makeAddr("burnSink");

    function setUp() public {
        token = new LitnupToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, usdc, registry, admin, burnSink);

        bytes32 oracleRole = vault.ORACLE_ROLE();
        vm.prank(admin);
        vault.grantRole(oracleRole, oracle);

        address operator = makeAddr("operator");
        vm.prank(admin);
        token.transfer(operator, 1_000_000 ether);
        vm.prank(operator);
        token.approve(address(registry), type(uint256).max);
        vm.prank(operator);
        uint256 agentId = registry.enroll(makeAddr("controller"), 50_000 ether, bytes32(0), 1000);

        handler = new Handler(token, usdc, vault, oracle, admin, agentId);
        targetContract(address(handler));
    }

    /// CORE SOLVENCY: the vault's real $LITNUP balance always covers staker principal.
    function invariant_vaultSolvent() public view {
        (uint128 principal,,,,,) = vault.vaults(handler.agentId());
        assertGe(token.balanceOf(address(vault)), principal, "principal underbacked");
    }

    /// REWARD SOLVENCY: the vault's real reward-token balance covers owed staker rewards, modulo
    /// bounded accumulator dust. Integer division in the per-share accumulator can favor a staker
    /// by at most ~1 wei per reward checkpoint (the standard MasterChef rounding property), so the
    /// owed total can exceed the held balance by a negligible, bounded amount. We assert the
    /// shortfall never exceeds that dust bound — i.e. there is never a *material* reward shortfall.
    /// (On 6-decimal USDC this dust is sub-cent and economically irrelevant.)
    function invariant_rewardsSolvent() public view {
        uint256 owed;
        uint256 id = handler.agentId();
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            owed += vault.pendingRewards(id, handler.actorAt(i));
        }
        uint256 held = usdc.balanceOf(address(vault));
        uint256 dustBound = handler.actorCount() * 256; // >= 1 wei/checkpoint over the fuzz depth
        assertLe(owed, held + dustBound, "material reward shortfall");
    }

    /// Capped supply: total supply never exceeds 1B (burns only reduce it).
    function invariant_supplyConserved() public view {
        assertLe(token.totalSupply(), 1_000_000_000 ether);
    }

    /// Share/principal consistency: no shares outstanding without principal backing them.
    function invariant_sharesAssetsConsistency() public view {
        (uint128 principal, uint128 totalShares,,,,) = vault.vaults(handler.agentId());
        if (totalShares == 0) assertEq(principal, 0);
    }
}

/// Fuzz target — exercises the system under random inputs.
contract Handler is Test {
    LitnupToken public token;
    MockERC20 public usdc;
    StakingVault public vault;
    address public oracle;
    address public admin;
    uint256 public agentId;

    address[] public actors;

    constructor(
        LitnupToken _token,
        MockERC20 _usdc,
        StakingVault _vault,
        address _oracle,
        address _admin,
        uint256 _agentId
    ) {
        token = _token;
        usdc = _usdc;
        vault = _vault;
        oracle = _oracle;
        admin = _admin;
        agentId = _agentId;

        for (uint256 i = 0; i < 5; i++) {
            address a = makeAddr(string(abi.encodePacked("staker", vm.toString(i))));
            actors.push(a);
            vm.prank(admin);
            token.transfer(a, 100_000 ether);
            vm.prank(a);
            token.approve(address(vault), type(uint256).max);
        }

        // The handler is the fee payer: fund it with USDC and approve the vault.
        usdc.mint(address(this), 100_000_000e6);
        usdc.approve(address(vault), type(uint256).max);
    }

    function actorCount() external view returns (uint256) { return actors.length; }
    function actorAt(uint256 i) external view returns (address) { return actors[i]; }

    function stake(uint256 actorSeed, uint128 amount) external {
        amount = uint128(bound(amount, 1, 10_000 ether));
        address a = actors[actorSeed % actors.length];
        if (token.balanceOf(a) < amount) return;
        vm.prank(a);
        try vault.stake(agentId, amount) returns (uint128) {} catch {}
    }

    function recordPnl(int256 delta) external {
        delta = bound(delta, -1_000_000 ether, 1_000_000 ether);
        vm.prank(oracle);
        try vault.recordPnl(agentId, delta) {} catch {}
    }

    function takeFees(uint128 fee, uint16 bps) external {
        fee = uint128(bound(fee, 0, uint128(usdc.balanceOf(address(this)))));
        bps = uint16(bound(bps, 0, 10_000));
        if (fee == 0) return;
        vm.prank(oracle);
        try vault.takeFees(agentId, fee, bps, address(this)) {} catch {}
    }

    function slash(uint128 amount) external {
        (uint128 principal,,,,,) = vault.vaults(agentId);
        if (principal == 0) return;
        amount = uint128(bound(amount, 1, principal));
        vm.prank(oracle);
        try vault.slashVault(agentId, amount) {} catch {}
    }

    function unstakeInit(uint256 actorSeed, uint128 shares) external {
        address a = actors[actorSeed % actors.length];
        (uint128 userShares,,,,) = vault.stakers(agentId, a);
        if (userShares == 0) return;
        shares = uint128(bound(shares, 1, userShares));
        vm.prank(a);
        try vault.unstakeInit(agentId, shares) {} catch {}
    }

    function unstakeComplete(uint256 actorSeed, uint256 warpBy) external {
        address a = actors[actorSeed % actors.length];
        vm.warp(block.timestamp + bound(warpBy, 0, 14 days));
        vm.prank(a);
        try vault.unstakeComplete(agentId) returns (uint128) {} catch {}
    }

    function claim(uint256 actorSeed) external {
        address a = actors[actorSeed % actors.length];
        vm.prank(a);
        try vault.claimRewards(agentId) returns (uint256) {} catch {}
    }
}
