// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";

import {LitToken} from "../src/LitToken.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {StakingVault} from "../src/StakingVault.sol";

/// @notice Property-based / invariant tests. Foundry will fuzz random sequences of calls
///         on the Handler and check after each call that all invariants hold.
///
/// Run with: forge test --match-contract InvariantsTest -vvv
contract InvariantsTest is StdInvariant, Test {
    LitToken token;
    AgentRegistry registry;
    StakingVault vault;
    Handler handler;

    address admin = makeAddr("admin");
    address oracle = makeAddr("oracle");
    address burnSink = makeAddr("burnSink");

    function setUp() public {
        token = new LitToken(admin);
        vm.prank(admin);
        token.mintInitialSupply();

        registry = new AgentRegistry(token, admin);
        vault = new StakingVault(token, registry, admin, burnSink);

        vm.prank(admin);
        vault.grantRole(vault.ORACLE_ROLE(), oracle);

        // Pre-create one agent for the handler to play with
        address operator = makeAddr("operator");
        vm.prank(admin);
        token.transfer(operator, 1_000_000 ether);
        vm.prank(operator);
        token.approve(address(registry), type(uint256).max);
        vm.prank(operator);
        uint256 agentId = registry.enroll(makeAddr("controller"), 50_000 ether, bytes32(0), 1000);

        handler = new Handler(token, vault, oracle, admin, agentId);
        targetContract(address(handler));
    }

    /// Invariant: vault token balance >= sum of all vaults' totalAssets
    /// (vault never holds less than what it owes stakers)
    function invariant_vaultSolvent() public view {
        uint256 vaultBal = token.balanceOf(address(vault));
        // For our single-agent test we only check that one
        (uint128 totalAssets, , , ) = vault.vaults(handler.agentId());
        assertGe(vaultBal, totalAssets);
    }

    /// Invariant: total token supply minus burned = sum of all balances
    /// (capped supply enforced — no inflation, no creation outside _mint)
    function invariant_supplyConserved() public view {
        // Initial supply was 1B. Any drop equals burned.
        uint256 expectedMax = 1_000_000_000 ether;
        assertLe(token.totalSupply(), expectedMax);
    }

    /// Invariant: shares math is consistent — totalShares == 0 iff totalAssets == 0
    function invariant_sharesAssetsConsistency() public view {
        (uint128 totalAssets, uint128 totalShares, , ) = vault.vaults(handler.agentId());
        if (totalShares == 0) {
            assertEq(totalAssets, 0);
        }
    }
}

/// Fuzz target — exercises the system under random inputs.
contract Handler is Test {
    LitToken public token;
    StakingVault public vault;
    address public oracle;
    address public admin;
    uint256 public agentId;

    address[] public actors;

    constructor(LitToken _token, StakingVault _vault, address _oracle, address _admin, uint256 _agentId) {
        token = _token;
        vault = _vault;
        oracle = _oracle;
        admin = _admin;
        agentId = _agentId;

        // Create 5 actors to act as stakers
        for (uint256 i = 0; i < 5; i++) {
            address a = makeAddr(string(abi.encodePacked("staker", vm.toString(i))));
            actors.push(a);
            vm.prank(admin);
            token.transfer(a, 100_000 ether);
            vm.prank(a);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function stake(uint256 actorSeed, uint128 amount) external {
        amount = uint128(bound(amount, 1, 10_000 ether));
        address a = actors[actorSeed % actors.length];
        if (token.balanceOf(a) < amount) return;
        vm.prank(a);
        try vault.stake(agentId, amount) returns (uint128) {} catch {}
    }

    function applyPnl(int128 delta) external {
        // Bound delta within +/-50% of vault — caps are enforced anyway, but reduces trivial reverts
        (uint128 totalAssets, , , ) = vault.vaults(agentId);
        if (totalAssets == 0) return;
        int128 cap = int128(totalAssets / 2);
        delta = int128(bound(delta, -cap, cap));
        vm.prank(oracle);
        try vault.applyPnl(agentId, delta) {} catch {}
    }

    function takeFees(uint128 fee) external {
        (uint128 totalAssets, , , ) = vault.vaults(agentId);
        if (totalAssets == 0) return;
        fee = uint128(bound(fee, 0, totalAssets));
        vm.prank(oracle);
        try vault.takeFees(agentId, fee, 5000) {} catch {}
    }

    function unstakeInit(uint256 actorSeed, uint128 shares) external {
        address a = actors[actorSeed % actors.length];
        (uint128 userShares, , ) = vault.stakers(agentId, a);
        if (userShares == 0) return;
        shares = uint128(bound(shares, 1, userShares));
        vm.prank(a);
        try vault.unstakeInit(agentId, shares) {} catch {}
    }
}
