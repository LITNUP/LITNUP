# Frequently Asked Questions

> Living doc. New questions get added at the top of each section as they come up.

## General

### What is LITNUP?
A permissionless protocol for staking on autonomous AI trading agents. Anyone deploys an agent, anyone stakes the protocol token ($LITNUP) behind it, performance is reported via a threshold-signed oracle, and underperformers get slashed. Protocol fees (collected in USDC) are split per-attestation between buying back and burning $LITNUP and paying stakers USDC yield.

### How is this different from Virtuals or ai16z?
Virtuals is a token launchpad — anyone mints an agent token, performance is unmeasured. ai16z is a single AI-managed DAO/treasury. Bittensor is a tournament-style emission system.

LITNUP is none of those. It's a *staking layer above existing agent frameworks* — you can use ELIZA, AIXBT-style models, or your own code; we provide the on-chain verification + capital allocation primitive.

### What chain is it on?
Base for primary deployment. v2 will add omnichain agent coordination via LayerZero V2.

### When does mainnet launch?
Q4 2026 target. Specifically: when KPIs are met (audit complete, $5M+ TVL on testnet, 50+ agents enrolled, regulatory opinions in hand). Not on a calendar.

### Is there a token now?
Not yet. $LITNUP launches at TGE. The contracts are deployed on Base Sepolia (testnet) for verification.

### Who built this?
A sole founder (Arthur Romanov) bootstrapping with no VC, plus hiring. See `outreach/founder-pitch.md` for bios.

---

## For stakers

### How do I stake?
Once mainnet is live: connect a wallet, choose an agent from the leaderboard, deposit $LITNUP. Your deposit is recorded as principal in that agent's vault; it redeems at principal (subject to slashing), and you earn USDC yield from protocol fees on top.

### What's the minimum stake?
None at the protocol level. Per-agent minimums may exist set by operators.

### Can I lose my stake?
Your stake redeems at principal only — agent PnL never changes your redemption value (PnL is reputation-only, tracked on-chain as `cumulativePnl`). The on-chain invariant is that the vault always holds at least the sum of all stakers' principal in $LITNUP. The risk to your principal is slashing:

- The vault is slashed for confirmed sustained underperformance or misbehavior. This is **not** an automatic on-chain trigger — slashing is executed by the threshold-signed oracle once signers confirm a breach. The *intended policy* (a governance/oracle target, not a hardcoded contract constant) is roughly: a sustained drawdown beyond ~25% from the high-water-mark prompts a vault slash on the order of ~10%, routed to the burn sink, reducing principal pro-rata.

You earn real yield on top of your principal, paid in USDC, funded by protocol fees (see "Where does my fee revenue come from?"). Yield is variable and not guaranteed.

This is by design — no skin in the game means no good agents.

### How long is my stake locked?
Active stake: as long as you want. To unstake: 7-day cooldown after `unstakeInit()`. This protects the vault from flash-stake-then-flash-exit around scheduled attestations.

### Where does my fee revenue come from?
Protocol performance fees, collected in USDC. The fee for each agent is reported via a threshold-signed oracle attestation (an EIP-712 message, not trustlessly derived from raw on-chain PnL — this is a stated trust assumption). Each collected fee is split per-attestation, with the staker/buyback ratio bound into the signature: part goes to BuybackBurn (which buys and burns $LITNUP on a DEX), the rest is paid to stakers as USDC yield. Any "50/50" figure is an illustrative default, not a hardcoded or governance-set protocol parameter. Your principal is never inflated by PnL; yield is paid separately in USDC.

### Can I stake on multiple agents?
Yes. Each agent has its own vault; you hold a separate principal position in each, independently (redeemable at principal, slash-adjusted).

### What happens if my agent gets retired?
If an agent's bond falls below `minBond` due to slashings, status changes to `Slashed` and it stops accepting new stake. Existing stakers can still unstake (after cooldown). The agent does not vanish; it's frozen.

### How do I evaluate an agent before staking?
The leaderboard shows: 30-day PnL, Sharpe ratio, max drawdown, total stake, # of stakers, equity curve. Click an agent for: full attestation history, strategy description, code hash (if open-source), operator's bond size.

If you can't justify staking after looking at all six metrics, don't stake.

---

## For agent operators

### How do I deploy an agent?
1. Generate an EOA keypair for the agent's controller (recommend a fresh hardware-key-backed signer)
2. Approve `AgentRegistry` to spend ≥10,000 $LITNUP from your operator wallet
3. Call `AgentRegistry.enroll(controller, bond, metadataHash, protocolFeeBps)`
4. Run an off-chain agent runtime (template in `agent-runtime/`) that pulls prices, executes trades, and signs attestations matching the on-chain oracle

Full walkthrough in `docs/agent-operator-onboarding.md`.

### What's the minimum bond?
10,000 $LITNUP at v1 launch. Configurable upward by governance.

### Can I top up my bond?
Yes. `AgentRegistry.topUpBond(agentId, amount)` from any address (sponsorships welcome).

### What's the protocol fee rate?
You set it at enrollment, capped at 50% of gross profit. Default suggested: 10–15%. The collected fee is split per-attestation between buyback-and-burn of $LITNUP and USDC yield to stakers; a higher fee means more of both, but it is harder to attract stakers.

### Can I withdraw my bond?
Yes, after a 14-day unbonding period. Call `withdrawInit()`, wait, then `withdrawComplete()`.

### What happens if my agent gets slashed?
Two flavors:
- **Bond slashing** (operator misbehavior — oracle fraud, exploit attempts) — your bond is reduced; if below `minBond` your agent is paused.
- **Vault slashing** (sustained drawdown) — stakers lose pro-rata stake; your bond is unaffected.

### Can I run multiple strategies on one agent?
Yes — but each agent is a single PnL stream. If you want isolated strategies, deploy separate agents (separate enrollments, separate bonds, separate vaults).

### What execution venues are supported in v1?
Initially: Hyperliquid (perps + spot), Aerodrome (Base DEX), Pendle (yield), Drift (Solana — v2). The whitelist is curated in v1; v2 will be permissionless.

### Can my agent be open-source?
Yes — and we encourage it. Operators with open-source code get a "verified strategy" badge and easier onboarding from stakers.

### Can my agent be closed-source?
Yes. The PnL is what's verifiable, not the code. You can keep your edge.

---

## For developers

### Where's the code?
`github.com/LITNUP/LITNUP` — public.

### What's the license?
Smart contracts: BUSL-1.1 (transitions to Apache-2 in 2 years).
Tooling: Apache-2.
Tests + examples: MIT.

### Can I fork it?
Smart contract code: not for commercial use during the BUSL period. Tooling/examples: yes.

### How do I run an agent locally?
```bash
cd agent-runtime
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python scripts/gen_signer.py
python -m agent_runtime.paper_trade --strategy momentum --asset BTC
```

### Can I add a new strategy?
Yes. Subclass `agent_runtime.strategies.base.Strategy`, implement `step(price) -> Signal`. PR welcome.

### Can I add a new venue?
Yes. Subclass `agent_runtime.venues.base.Venue`. v1 supports Paper + Hyperliquid (stub).

### Are the contracts upgradeable?
No. Intentional. v2 will be a fresh deployment with a documented migration path. Upgradeability is an attack surface that costs more than it gains for a launch.

---

## Tokenomics

### What's the total supply?
1,000,000,000 $LITNUP. Hard cap. Zero inflation.

### What's the allocation?
(Matches the canonical table in [`tokenomics.md`](tokenomics.md) — sums to 100%.)

| Allocation | Tokens | % |
| --- | --- | --- |
| Public sale | 50,000,000 | 5% |
| Airdrop S1 | 100,000,000 | 10% |
| Initial DEX liquidity | 30,000,000 | 3% |
| Ecosystem incentives | 170,000,000 | 17% |
| Team | 150,000,000 | 15% |
| Investors (all rounds) | 150,000,000 | 15% |
| Treasury (DAO) | 150,000,000 | 15% |
| Foundation reserve | 100,000,000 | 10% |
| Future airdrops + community | 100,000,000 | 10% |
| **Total** | **1,000,000,000** | **100%** |

(See `docs/tokenomics.md` for full breakdown.)

### What's the use of $LITNUP?
Four sinks:
1. **Agent enrollment bonds** (10,000 minimum)
2. **Stake on agents** (any amount)
3. **veLITNUP governance lock** (4-year max for boosted weight)
4. **Burn target** — a portion of protocol fees (USDC) buys back and burns $LITNUP; the buyback share is set per-attestation, not a fixed protocol-wide percentage

### Will there be an airdrop?
Yes. Season 1 at TGE (10% of supply) to anti-sybil-filtered testnet users + early ecosystem participants. Season 2 (5%) at month 6, Season 3 (5%) at month 12, governance-gated.

### Will the token be on Binance / Coinbase?
Targeting Tier-1 listings 9–14 months post-mainnet. Not guaranteed. Listing is a function of metrics (TVL, volume, holders, audits) — we'll qualify if we hit them.

---

## Security & risk

### Have the contracts been audited?
No third-party audit has been completed or commissioned. The contracts are pre-audit. Plan:
1. Internal review (done)
2. One or more independent security audits planned before mainnet
3. Economic/parameter review planned before TGE

### What if the oracle gets compromised?
The oracle uses EIP-712 threshold signatures (M-of-N) from independent signers, configurable by governance. On testnet it is deployed as 3-of-5; a higher M-of-N is targeted for mainnet. If a quorum of signers were compromised, the protocol pause guardian (separate from the oracle) can halt new attestations. v2 explores ZK-proof attestations.

### What if the smart contracts have a bug?
- A bug bounty is planned post-mainnet
- Initial deposit caps per vault (1M $LITNUP) limit blast radius
- ±50% PnL cap per attestation limits oracle-bug damage (note: PnL is reputation-only and does not affect redemption value)
- An insurance fund (seeded from fees) is planned/roadmap, not yet active

### Is $LITNUP a security?
We don't believe so — it's a utility token (bonding, staking, governance). Final classification depends on jurisdiction and counsel review. No legal opinions exist yet; they are planned. Not legal advice. See `plan/legal-checklist.md`.

### Why should I trust you?
You shouldn't. You should look at:
- The code (public, on-chain)
- The contracts on Base Sepolia
- The agent runtime that round-trips with the on-chain oracle
- The audit reports when they land
- The track record of agents (every PnL on-chain)

Trust nothing; verify everything. That's the protocol's whole thesis.

---

## Random / edge cases

### What if I lose my private key?
You lose access to whatever it controlled. Operator keys, staker keys, signer keys — none are recoverable. Use hardware wallets. Use Safe/Squads multisigs for treasury.

### What if Base goes down?
Trading agents on Base pause until Base recovers. Stakers can still unstake (after Base recovery). v2 omnichain reduces single-chain dependency.

### What if Hyperliquid goes down?
Agents trading on Hyperliquid pause. Their measured PnL freezes at last attestation. Stakers unaffected unless drawdown is triggered.

### Can I run an agent without any AI?
Yes. The protocol doesn't care if your "agent" is a sophisticated LLM, a simple SMA crossover, or a human pressing buttons. It cares about settled PnL.

### Will there be a v3?
We're focused on v1. v2 is scoped (cross-chain, ZK oracle). v3 is whatever the protocol's users tell us they need in 2027.

---

## Where do I get more help?

- **Docs**: litnup.io/docs
- **Discord**: https://discord.gg/Enr6BabmF
- **GitHub**: github.com/LITNUP/LITNUP (issues + discussions)
- **Twitter**: @LITNUP
- **Security**: security@litnup.io (or via Immunefi when live)
