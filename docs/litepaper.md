# LITNUP — Litepaper

**Version 0.1 (draft) · 2026-05-05**

> The staking layer for autonomous on-chain trading agents.

---

## Abstract

LITNUP is a permissionless protocol that turns the open question — *"which AI agents can actually trade well?"* — into a market with on-chain answers. Anyone can deploy an autonomous agent. Anyone can stake tokens behind the agents they believe in. Performance is verified by a hybrid oracle of on-chain settlement records and multi-signer attestations, denominated in USD-equivalents. Underperforming agents get slashed. Fees flow to stakers and to a buyback-and-burn engine on the protocol token, **$LITNUP**. The result: a meritocratic, capital-efficient marketplace for the AI-agent economy that, unlike every comparable protocol, makes the central question — *is this agent any good?* — answerable.

---

## 1. The problem

The AI-agent narrative in crypto has produced over $10 billion of token market cap and tens of thousands of agents. Yet the basic question — *which of these agents actually generate alpha?* — remains unanswered. Existing protocols do one of three things:

1. **Launchpad model (Virtuals, Clanker):** anyone can mint an agent token. Performance is unmeasured. Agent quality follows a power law where 99% of tokens go to zero.
2. **Framework model (ai16z / ELIZA):** open-source agent frameworks. Agents exist but aren't comparable; performance isn't quantified.
3. **Subnet model (Bittensor):** agents compete for emissions in a tournament-style network, but not specifically for trading; rewards correlate poorly with end-user value.

None of them answer: *which agents make money for the people who back them, and how do I put capital behind the ones that do?*

## 2. The insight

Trading is the one agent task with **costless, high-frequency, ground-truth measurement**: PnL. Every other agent task — research, support, coding — requires subjective evaluation. Trading just settles. So:

> **If we build a marketplace whose unit of account is *settled, attestable PnL*, and we let anyone stake the protocol token behind the agents they believe in, with slashing for losers and pro-rata fees for winners, we get a Hyperliquid-style flywheel for AI agents that nobody else has.**

This is the design of LITNUP.

## 3. System architecture

```
                     ┌──────────────────────┐
                     │     $LITNUP token   │
                     │  ERC20Votes / Permit │
                     └──────────┬───────────┘
                                │
    ┌───────────────┬───────────┴────────────┬───────────────┐
    │               │                        │               │
    ▼               ▼                        ▼               ▼
┌─────────┐   ┌────────────┐          ┌─────────────┐  ┌──────────┐
│ Agent   │   │ Staking    │          │ Performance │  │ Buyback  │
│ Registry│◄──┤ Vault      │◄──fees──►│ Oracle      │  │ Burn     │
└─────────┘   └─────┬──────┘          └──────┬──────┘  └────▲─────┘
     ▲              │                        │              │
     │              │ slash                  │ attest        │ revenue
     │              ▼                        │               │
     │        Stakers earn,                  │               │
     └────────  losers slashed ◄─────────────┘               │
                                                             │
                                              Protocol fees ─┘
```

### 3.1 Components

**$LITNUP token (ERC20Votes + Permit, capped supply 1B).** The unit of account for staking, bonding, and governance. Capped, deflationary via buyback-and-burn, and gas-less approvals via EIP-2612.

**Agent Registry.** A permissionless registry where any address can enroll an "agent." Enrollment requires posting a $LITNUP bond (configurable, e.g. 10,000 $LITNUP). The bond is at risk if the agent commits a registry-level offense (oracle fraud, exploit attempts).

**Staking Vault.** For each registered agent, anyone can stake $LITNUP. Stakes earn share-based exposure to the agent's trading PnL, denominated in $LITNUP. The vault uses ERC4626-style share accounting. Withdrawals are subject to a cooldown (default 7 days) to prevent front-running of slashing events.

**Performance Oracle.** A multi-signer oracle (5-of-7 at launch, transitioning to 13-of-21, then ZK-proven) that attests to each agent's PnL on a regular cadence (every 4 hours initially). Attestations are cryptographically signed, recorded on-chain, and feed into the vault's pricing.

**Buyback & Burn.** Protocol fees (10–25% of agent gross profits, configurable per agent at enrollment) flow into a buyback contract that periodically buys $LITNUP on the open market and burns it. Creates persistent buy pressure proportional to total agent profit.

### 3.2 Agent lifecycle

1. **Deploy.** A developer publishes their agent (any execution venue: Hyperliquid, Aerodrome, Pendle, Drift, etc.) and registers a controller address on `AgentRegistry.enroll()`.
2. **Bond.** The controller posts a $LITNUP bond. The agent goes live with a unique `agentId`.
3. **Stake.** Stakers call `StakingVault.stake(agentId, amount)`. They receive shares.
4. **Trade.** The agent's controller executes trades on its chosen venue(s). Each venue has either: (a) an on-chain settlement record (the case for Hyperliquid spot, perp DEXs, AMMs); or (b) a verifiable off-chain record signed by the venue.
5. **Attest.** Every 4 hours, the Performance Oracle queries the agent's positions/PnL across whitelisted venues and attests on-chain. The vault marks-to-market.
6. **Earn / Slash.** If PnL is positive, fees accrue: a portion to stakers, a portion to buyback. If PnL goes below a configurable threshold (e.g. -25% drawdown over 7 days), the agent is auto-slashed: a fraction of the bond + a fraction of the stake is burned.
7. **Withdraw.** Stakers may unstake after the cooldown.

### 3.3 What's *not* in v1

- Cross-chain trading by a single agent (planned v2 via LayerZero)
- ZK-proof attestations (planned v2 — initial oracle is multisig)
- Permissionless venue whitelisting (planned v2 — initial set is curated)
- Margin / leverage management on the protocol level (agents handle their own)
- Insurance fund (planned post-mainnet, funded from fees)

## 4. Why this works (mechanism design)

**Skin in the game.** Agent operators post bonds. Stakers risk slashing. Both have incentives aligned with sustained good performance, not short-term metric games.

**Provability.** Every PnL number is rooted in either an on-chain settlement or a multi-signer attestation. No agent can claim performance it didn't deliver.

**Capital concentration to winners.** Top-performing agents accumulate stake organically. This is the same mechanism that lets the top 10% of Hyperliquid vault traders manage 80%+ of vault TVL.

**Token utility from day one.** $LITNUP is needed for: bonding, staking, governance (vote-escrow / veAGENTIC), and fee-rebate tiers. Demand sinks scale with TVL.

**Buy pressure proportional to ecosystem profit.** Unlike most "buyback" tokens where buyback depends on fees of an unrelated business, $LITNUP buyback is directly proportional to *total agent profit*. As the protocol succeeds, the token compounds.

## 5. Differentiation

| Feature | LITNUP | Virtuals | ai16z / ELIZA | Bittensor | Olas |
|---|:-:|:-:|:-:|:-:|:-:|
| Provable on-chain PnL | ✓ | ✗ | ✗ | indirect | ✗ |
| Stake-to-back specific agents | ✓ | ✗ | ✗ | ✓ | ✗ |
| Slashing for bad performance | ✓ | ✗ | ✗ | indirect | ✗ |
| Trading-specialized | ✓ | general | general | general ML | services |
| Buyback & burn from real revenue | ✓ | ✗ | ✗ | ✗ | ✗ |
| Agent operator bonds | ✓ | ✗ | ✗ | ✓ | ✗ |
| Cross-venue agents | v2 | ✗ | possible | ✗ | partial |

The closest comp is **Bittensor's subnet 8 (Taoshi) for prediction-market agents** — but that's tournament-style emissions, not user-staking on individual agents, and it is not denominated in USD/PnL.

## 6. Tokenomics

**Total supply:** 1,000,000,000 $LITNUP (hard cap, no inflation)

| Allocation | % | Vesting | Notes |
|---|---:|---|---|
| Public sale (LBP / Echo) | 5% | unlocked at TGE | Cash raise into treasury |
| Airdrop S1 | 10% | 4-month linear vest into stake | Anti-sybil filtered testnet users |
| Initial DEX liquidity | 3% | locked 12 mo | Paired with treasury stables |
| Ecosystem incentives | 17% | streamed M0–M24 | Stakers + agents + integrators |
| Team | 15% | 4y vest, 1y cliff | Vest into stake by default |
| Investors (angel + seed + strategic) | 15% | 3y vest, 1y cliff | Pro-rata across rounds |
| Treasury (DAO-controlled) | 15% | unlock-on-vote | Future grants, audits, BD |
| Foundation reserve | 10% | locked 24 mo | Buyback fund, emergency |
| Future airdrops + community | 10% | streaming, governance-gated | S2, S3, ecosystem |

**Demand sinks:**

1. **Agent-launch bonds:** every new agent locks ≥10,000 $LITNUP.
2. **Staking lockups:** stakers' $LITNUP is locked while staked + 7-day cooldown.
3. **veAGENTIC governance lock:** up to 4-year lock for governance weight + fee rebates.
4. **Buyback & burn:** 50% of all protocol fees → buy & burn $LITNUP.

**Emission schedule:** all unlocks listed are linear except airdrop (which streams into stake to suppress dump).

**Supply trajectory (estimated circulating):**
- TGE: 11%
- Month 6: 22%
- Month 12: 38% (cliff begins)
- Month 18: 55%
- Month 24: 72%
- Month 36: 90%
- Month 48: 100%

## 7. Use of funds (capital plan summary)

| Stage | Source | Capital | Use |
|---|---|---:|---|
| 0 | Founder bootstrap | $0 | MVP build |
| 1 | Hackathons + grants | $80k | Audits, infra, tools |
| 2 | Accelerator | $250k | First hire + audit |
| 3 | Angels | $400k | Mainnet + community |
| 4 | Pre-seed/Seed | $1.5M | Team, audits, marketing |
| 5 | Strategic CEX | $2–5M (optional) | Listings + MM |
| 6 | TGE LBP | $3–10M | Public participation |

Full plan in [`plan/capital-raise-plan.html`](../plan/capital-raise-plan.html).

## 8. Roadmap

**Q2 2026 (now)** — MVP contracts on Base Sepolia. First reference agent. Litepaper public. First grants + hackathons.

**Q3 2026** — Public testnet. 50 agents. Phantom TVL competition. Accelerator acceptance. Audit kicks off.

**Q4 2026** — Mainnet launch (Base). $5M+ TVL target. Pre-seed close. KOL partnerships. First Tier-3 CEX listings.

**Q1 2027** — Tier-2 CEX listings. Cross-chain v2. veAGENTIC governance live. Insurance fund seeded.

**Q2–Q3 2027** — Tier-1 CEX target window. ZK-proof attestations. Permissionless venue whitelisting. DAO transition.

## 9. Team

*(To be populated. For investor-readability, follow this template:)*

**Founder 1 — [Name], CEO/Protocol**
- Background: [...]
- Why this: [...]

**Founder 2 — [Name], Engineering Lead**
- Background: [...]
- Why this: [...]

**Advisors (target):**
- One DeFi-protocol founder
- One ML/agent researcher
- One securities lawyer (formal advisor, not just retainer)

## 10. Risk factors

- **Smart-contract risk.** Mitigated by 3 audits + bug bounty + initial deposit caps.
- **Oracle risk.** Multi-sig oracle is a centralization vector at launch; ZK migration in v2.
- **Agent gaming.** Wash-trading, mark-to-market manipulation. Mitigated by mark-to-fair-price formulas, drawdown limits, and slashing.
- **Regulatory risk.** Staking-like rewards on a token are securities-adjacent in some jurisdictions. Mitigated by structuring as a protocol-fee distribution (not a yield product), no US public sale, and MiCA-compliant whitepaper for EU.
- **Market timing.** Bear-market launches see -70% to -90% FDV draws. Mitigated by deferring TGE until KPI-met, not calendar-met.
- **Concentration / forks.** Open-source code can be forked. Mitigated by liquidity moat + agent-builder network effect + brand.

Full register: [`plan/risk-register.md`](../plan/risk-register.md).

## 11. Legal & compliance

The $LITNUP token is intended to function as a **utility token for protocol use** (bonding, staking, governance) and a **fee-rebate / governance instrument**. It is NOT a security, NOT an investment contract, and NOT marketed to retail investors in the United States. The protocol foundation is intended to incorporate in [Cayman Islands / BVI / Marshall Islands — pending counsel guidance]. Public sale and airdrop will exclude US persons via geofencing and on-chain attestation. EU participants will be served via a MiCA-compliant whitepaper.

Full structure: [`plan/legal-checklist.md`](../plan/legal-checklist.md).

## 12. References & prior art

- **Bittensor whitepaper** (subnets, TAO incentive design).
- **Hyperliquid vaults** (capital-share pattern for trader-led funds).
- **dYdX trading v4** (perp-DEX architecture for agent execution venue).
- **Pendle YT mechanism** (yield-tokenization model for agent revenue claims, future v2).
- **Compound governance** (vote-escrow patterns).
- **OpenZeppelin Governor + Votes** (standard governance contracts; v1 will use these directly).
- **Chainlink CCIP, LayerZero V2** (cross-chain messaging for v2 omnichain agents).

---

*This is a draft litepaper. Numbers and structure are subject to change pending legal, technical, and economic review. Not an offer to sell or solicitation to buy any token. Not investment advice.*
