# LITNUP Contracts

Solidity 0.8.24, Foundry-based. Deployed to Base (mainnet) and Base Sepolia (testnet).

## Layout

```
contracts/
├── foundry.toml
├── src/
│   ├── LitToken.sol         ← $LITNUP token (ERC20Votes + Permit, capped 1B)
│   ├── AgentRegistry.sol      ← agent enrollment, bonds, slashing hooks
│   ├── StakingVault.sol       ← per-agent share-based staking
│   ├── PerformanceOracle.sol  ← multisig PnL attestation
│   └── BuybackBurn.sol        ← fee → buyback → burn pipeline
└── test/
    ├── LitToken.t.sol
    ├── AgentRegistry.t.sol
    ├── StakingVault.t.sol
    ├── PerformanceOracle.t.sol
    └── BuybackBurn.t.sol
```

## Setup (first time)

Foundry is not pre-installed on this machine. To install:

```bash
# install foundryup
curl -L https://foundry.paradigm.xyz | bash
# restart shell, then
foundryup

# pull dependencies
cd contracts
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit

# compile
forge build

# run tests
forge test -vvv

# gas report
forge test --gas-report
```

## Deployment (when ready)

```bash
# set env vars
export BASE_SEPOLIA_RPC_URL=...
export DEPLOYER_PRIVATE_KEY=...
export BASESCAN_API_KEY=...

# deploy to testnet
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify
```

(Deploy script is a stub at this point — to be written when first audit-ready release is cut.)

## Design principles

1. **Minimal surface.** Each contract does one thing. Composition is in the deploy script and config.
2. **No upgrades in v1.** Use a fresh deployment for v2 with a documented migration path. Upgradeability is a security risk that costs more than it gains for a launch.
3. **OpenZeppelin where possible.** Battle-tested base contracts. Custom code only where there's no choice.
4. **Reentrancy paranoia.** Every state change before any external call. `nonReentrant` on every external entrypoint with token movement.
5. **Caps and limits.** Initial deposit cap on staking vault. Slashing capped per epoch. Bond rates upper-bounded.
6. **Oracle as MultiSig in v1.** ZK-proof migration in v2.

## Audit plan

| Phase | When | Cost | Auditor target |
|---|---|---|---|
| 1. Internal review | Pre-mainnet | $0 | Self + co-founder |
| 2. Code4rena contest | Pre-mainnet | ~$25k (paid in tokens or stables from grant) | Code4rena warden community |
| 3. Sherlock or Spearbit | Pre-Tier-1 CEX listing | $40k–$80k | Whoever gives best response |
| 4. Economic audit | Pre-TGE | $25k–$50k | Gauntlet or Chaos Labs |

## Status (as of 2026-05-05)

| Contract | LOC | Tests | Audit |
|---|---|---|---|
| LitToken.sol | ~80 | stub | not started |
| AgentRegistry.sol | ~140 | stub | not started |
| StakingVault.sol | ~200 | stub | not started |
| PerformanceOracle.sol | ~150 | stub | not started |
| BuybackBurn.sol | ~110 | stub | not started |

**These contracts have not been compiled or tested.** First action when machine is set up: `forge build && forge test`.

## Known limitations / TODOs

- [ ] Buyback uses a stub Uniswap V3 router interface; concrete swap path TBD per chain
- [ ] PerformanceOracle's signer set is hardcoded in constructor; v1 should govern signer rotation via timelock
- [ ] StakingVault slashing path needs to handle rounding edge cases on small share amounts
- [ ] Need a `Pausable` mux for emergency on every external entrypoint
- [ ] Need a comprehensive invariant test suite (separate file)
- [ ] Add SafeERC20 for any token transfers beyond $LITNUP
- [ ] Consider rate-limiting stake/unstake to mitigate flash-staking around oracle attestation timing
