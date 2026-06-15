# LITNUP — Base Sepolia launch plan (the investor proof pack)

Goal: produce the exact three things the VCs asked for — **verified contracts, live attestations,
2–3 real agents** — on Base Sepolia, plus a public repo and a live dashboard. None of this needs
mainnet, a token sale, or the legal/audit gates. It is achievable with the code as it stands today.

> Honesty rules for this whole plan: testnet PnL must come from **real** paper/live venue trading,
> attestations are labelled **"attested"** (a signer set agreed on a number), and nothing is called
> "audited" or "mainnet." Under-promise; let the live data speak.

---

## Phase 0 — Prerequisites (you provide; ~1 day)

| Item | How |
|---|---|
| Funded deployer key | `cast wallet new`; fund with Base Sepolia ETH (free faucet) |
| Small governance Safe | Create a 2-of-3 (or solo for now) Safe on Base Sepolia → this is `GOVERNANCE_SAFE` |
| Oracle signer set | 3–5 keys you control on separate machines/devices (start 3-of-5). These are real keys, not the anvil defaults |
| Guardian set | 3 keys for the PauseGuardian (can overlap with signers initially) |
| RPC + Basescan key | Base Sepolia RPC (`https://sepolia.base.org`) + a free Basescan API key |
| USDC | Base Sepolia USDC is already the default in the deploy (`0x036C…F7e`); get some from a faucet to pay test fees |

## Phase 1 — Deploy + verify (½ day)

```bash
cd contracts
export DEPLOYER_PRIVATE_KEY=0x...
export GOVERNANCE_SAFE=0x...              # your Safe
export ORACLE_SIGNERS=0x..,0x..,0x..,0x..,0x..
export GUARDIANS=0x..,0x..,0x..
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify -vvv
```

Output: a real address manifest in `contracts/deployments/84532.json`, contracts **verified on
Basescan**, and (because a real Safe was supplied) the deployer EOA renounced.

Post-deploy:
1. Paste addresses into `sdk-typescript/src/addresses.ts` (base-sepolia) and
   `subgraph/networks.json` + `subgraph.yaml` (with the real `startBlock`).
2. Safe action: `LitnupToken.mintInitialSupply()`; fund the EmissionScheduler; set emission recipients.
3. Timelock: whitelist PauseGuardian actions (`StakingVault.pause`, etc.). See `deploy/DEPLOYMENT.md`.

## Phase 2 — 3 real agents posting live attestations (3–5 days)

The runtime already exists (`agent-runtime/`). For each of 3 agents:
1. Enroll on-chain: `registry.enroll(controller, 10_000e18 bond, metadataHash, feeBps)`.
2. Run the agent against a **real venue in paper mode first** (start with the `paper`/Hyperliquid
   testnet venue), 3 distinct strategies (e.g. `momentum`, `meanrev`, `funding_arb`).
3. Each epoch (e.g. every 4–6h): the oracle signer set independently signs the EIP-712 attestation
   (`python -m agent_runtime.oracle_signer …` per signer), a relayer submits `applyAttestation`.
   This writes a **live, timestamped, on-chain attestation** anyone can verify against the signers.
4. Operators pay the USDC performance fee on positive epochs → stakers accrue real USDC yield, half
   buys+burns $LITNUP. (Use small amounts; it's testnet.)

Deliverable: an on-chain history of attested PnL per agent, with the signer set and methodology public.

## Phase 3 — Public dashboard (2–3 days)

1. Deploy the subgraph: `graph codegen && graph build && graph deploy` to a Sepolia subgraph
   (run codegen against the freshly-verified ABIs — the source handlers are already fixed).
2. A minimal page (reuse `sdk-typescript/examples/staking-ui.html`) reading on-chain state:
   per-agent attested PnL, cumulative, stake TVL, USDC yield distributed, $LITNUP burned.
3. Link it from the repo README and the site. This IS the "live attestations" proof surface.

## Phase 4 — Make the repo public (½ day)

1. `gh auth login`; create the repo: `gh repo create <org>/litnup --public --source=. --push`
   (or add the remote and push `main` + the `audit-remediation` PR).
2. Pin `AUDIT_REMEDIATION.md` and the green CI badge in the README.

## What to send investors (maps 1:1 to their ask)

- **"verified contracts"** → Basescan links to the verified contracts + `deployments/84532.json`.
- **"live attestations"** → the dashboard + a few attestation tx hashes; "here are N agents, here is
  their independently-signed, tamper-evident track record, here is the exact methodology."
- **"clear public repo"** → the public GitHub repo, green CI, `AUDIT_REMEDIATION.md`.
- **"real agents"** → 3 agents trading on a real venue (paper→live), with on-chain PnL history.

## Realistic timeline

| Week | Milestone |
|---|---|
| 1 | Phase 0–1: deployed + verified on Base Sepolia; addresses published |
| 2 | Phase 2: 3 agents live, first weeks of attestations accumulating |
| 3 | Phase 3–4: dashboard live, repo public, investor pack assembled |
| 4+ | Accumulate a 3–4 week track record before the next raise conversation |

## What this does NOT do (be explicit with investors)

Testnet ≠ mainnet. No real capital is at risk, the token isn't live, attestation is a signer
committee (not yet ZK/TEE-proven), and the external audit + legal opinion + 5-of-9 hardware-key
ceremony are still required before mainnet (`AUDIT_REMEDIATION.md` §6). The pitch is: *"the mechanism
works, here it is running live and verifiable; mainnet follows audit + legal."*
