# LITNUP deployment runbook

Single source of truth for deploying the protocol. The canonical script is
[`contracts/script/Deploy.s.sol`](../contracts/script/Deploy.s.sol) — it deploys **all** contracts,
wires the functional cross-contract roles, and (when a real governance Safe is supplied) hands every
privileged role to the Safe + Timelock and **renounces the deployer EOA**.

> The previous `deploy/Deploy.s.sol` was deleted: it imported a renamed file (`LitToken.sol`) and could
> not compile. Do not recreate it — `contracts/script/Deploy.s.sol` is the only deploy script.

---

## 0. Prerequisites

- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`).
- Dependencies vendored: `forge install` is not used (deps are pinned clones in `contracts/lib`:
  `openzeppelin-contracts@v5.1.0`, `forge-std@v1.9.4`). `forge build` must be green and
  `forge test` must pass (157 tests) before any deploy.
- A funded deployer key (use a **fresh** key: `cast wallet new`).

## 1. Environment

| Var | Required | Notes |
|---|---|---|
| `DEPLOYER_PRIVATE_KEY` | always | broadcast key; fresh, deploy-only |
| `GOVERNANCE_SAFE` | **mainnet** | Safe multisig; becomes admin/treasury. If unset, defaults to the deployer (**testnet only**) and the handoff is skipped |
| `ORACLE_SIGNERS` | **mainnet** | comma-separated 3–9 real, geographically-distributed hardware-key signer addresses |
| `ORACLE_THRESHOLD` | optional | defaults to ceil(2N/3) (e.g. 5-of-7, 6-of-9) |
| `REWARD_TOKEN` | optional | USDC. Defaults to Base / Base-Sepolia USDC |
| `UNISWAP_ROUTER` | optional | V3 SwapRouter for BuybackBurn; defaults to a sentinel (burnDirect works without it) |
| `GUARDIANS` / `GUARDIAN_THRESHOLD` | optional | PauseGuardian multisig (default 3-of-5) |
| `TIMELOCK_DELAY` | optional | seconds; default 48h |

## 2. Testnet (Base Sepolia)

```bash
cd contracts
export DEPLOYER_PRIVATE_KEY=0x...
forge script script/Deploy.s.sol \
  --rpc-url base_sepolia --broadcast --verify -vvv
```

On testnet with no `GOVERNANCE_SAFE`, the deployer remains admin (a `WARNING` is logged), the full 1B
supply is minted and the EmissionScheduler is funded — so you can exercise the system immediately.
Addresses are written to `contracts/deployments/<chainId>.json`.

### Post-deploy (testnet)
1. `registry.enroll(controller, bond, metadataHash, feeBps)` from operator wallets.
2. Stakers `approve` + `vault.stake(agentId, amount)`.
3. Operators `approve` USDC to the vault (fees are pulled from the operator).
4. Run the agent runtime + oracle signer; submit `applyAttestation`.
5. Publish addresses to the SDK (`sdk-typescript/src/addresses.ts`) and subgraph (`networks.json`).

## 3. Mainnet (Base) — gated

**Do not run until the mainnet gates in §5 are satisfied.** The script enforces:
`GOVERNANCE_SAFE != deployer` and `>= 5` real oracle signers.

```bash
cd contracts
export DEPLOYER_PRIVATE_KEY=0x...        # fresh key, or use --ledger
export GOVERNANCE_SAFE=0x...             # the 5-of-9 Safe
export ORACLE_SIGNERS=0x..,0x..,0x..,0x..,0x..,0x..,0x..   # real signers
export GUARDIANS=0x..,0x..,0x..,0x..,0x..
forge script script/Deploy.s.sol --rpc-url base_mainnet --broadcast --verify -vvv
```

The script hands off and renounces automatically. The token is **not** minted by the script on
mainnet — the Safe calls `token.mintInitialSupply()` as a governed action afterward.

### Post-deploy governance actions (via the Safe / Timelock)
These cannot be done by the deploy EOA (by design — it has renounced):
1. **Mint:** Safe calls `LitnupToken.mintInitialSupply()` (one-time, to the Safe).
2. **Fund EmissionScheduler:** Safe transfers the 170M ecosystem bucket; set recipients via the
   Timelock (`EmissionScheduler.setRecipient`) so weights sum to 10000.
3. **PauseGuardian whitelist:** the Timelock (holder of `WHITELIST_ROLE`) calls
   `guardian.allowAction(target, selector)` for each pausable target/selector, e.g.
   `StakingVault.pause.selector`, `AgentRegistry.pause.selector`, `BuybackBurn.pause.selector`.
4. **Keepers:** Safe grants `BuybackBurn.KEEPER_ROLE` to the buyback keeper bot.
5. **InsuranceFund:** seed it and set the per-token USDC cap (`setMaxDisbursementPerEpoch(USDC, cap)`).
6. **MerkleAirdrop (when running a season):** deploy with a placeholder root, then `setMerkleRoot`
   with the real root before the first claim.

## 4. Role model after handoff

| Role | Holder | Rationale |
|---|---|---|
| `DEFAULT_ADMIN_ROLE` (all) | Governance Safe | can manage roles; multisig, not an EOA |
| `CONFIG_ROLE` (registry/vault/buyback) | Timelock | parameter changes behind a 48h delay |
| `SIGNER_MANAGER_ROLE` (oracle) | Timelock | signer-set rotation behind a delay |
| `PAUSER_ROLE` (registry/vault/buyback) | PauseGuardian + Safe | fast circuit breaker (minutes) |
| `ORACLE_ROLE` (vault) | PerformanceOracle | only the threshold-signed oracle moves PnL/fees |
| `SLASHER_ROLE` (registry) | PerformanceOracle | bond slashing requires threshold signatures |
| `KEEPER_ROLE` (buyback) | keeper bot (Safe-granted) | triggers swaps with a fresh quote |
| Deployer EOA | **nothing** (renounced) | no single-EOA god mode |

## 5. Mainnet gates (MUST precede a mainnet run)

These are out of scope for the code and require external action:

- [ ] Independent external audit of the (fixed) contracts + economic model; findings remediated.
- [ ] Legal / securities opinion (staking on managed performance is close to the Howey test; the
      Cayman foundation + geofencing posture must be reviewed by counsel).
- [ ] 5-of-9 Safe stood up with hardware keys distributed to real, geographically-distinct signers.
- [ ] Real oracle signer set generated on hardware (not the anvil defaults).
- [ ] Monitoring + alerting (OZ Defender / Forta / Tenderly) and a written incident-response +
      pause runbook.
- [ ] LP funding + market-making decision; communications plan.

## 6. Safety rules (from LITNUP_BUILD_PLAN)

Never deploy to mainnet on a Friday. Never deploy without a funded ops account for emergency
response. Never deploy without a tested rollback/pause plan. Full ownership renounce of governance is
a separate post-stability vote, not a day-0 decision.
