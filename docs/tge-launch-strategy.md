# LITNUP TGE & Launch Strategy

**Status:** Draft v1 · last updated 2026-05-09
**Audience:** Internal team, advisors, lead investors, market-making partners
**License:** Proprietary — do not distribute outside the named audience without written permission

---

## TL;DR

We are launching $LITNUP on **Base mainnet**, after a Base Sepolia testnet phase that runs from **M-3 to M-1** (3 months pre-TGE). The token's first liquid moment is the TGE itself — there is no presale, no IDO, no public discount round. The protocol generates revenue from day one; price discovery happens on Aerodrome and one centralized exchange (CEX) listing in week 1.

**Key design choices:**

- **Bootstrap-first capital ladder** before TGE: bug bounties → grants → angels → seed → TGE. We do NOT raise a $5M seed round to spend on marketing; we raise the minimum to fund audits + 12 months runway.
- **No private sale tokens vest before public.** Every cohort that gets tokens (team, investors, advisors, contributors) vests on the same schedule the public sees — 6-month cliff, 36-month linear thereafter, with vest-into-stake default on.
- **Liquidity bootstrap auction (LBA)** for the first 1.5% of supply, run on Balancer's LBP framework on Base. Replaces traditional bonding curve / fair launch / IDO.
- **Single-CEX listing in week 1**, with explicit no-payment-for-listing policy. We accept market-maker arrangements only on terms we publish.
- **Market-making partner** committed to two-sided quoting on day 1, with public disclosure of inventory loan terms.
- **First buyback+burn epoch** runs on day 8. We need 7 days of fee accrual to make the first burn meaningful.

This document outlines the calendar, the mechanics, the contingencies, and the explicit "we won't do this" list.

---

## The launch calendar

### M-12 to M-6 — pre-launch foundation
- Audits #1 and #2 commissioned (Spearbit + Trail of Bits, parallel)
- Code4ena + Cantina contests run in parallel with audits
- Testnet launch on Base Sepolia
- Operator alpha program: 3-5 hand-picked agent operators run real strategies on testnet PnL with mock token incentives
- Bug bounty live on Immunefi at $100K cap
- Marketing surface complete; weekly transparency reports published

### M-6 to M-3 — testnet ramp
- Open testnet for any operator who passes the operator-onboarding flow
- Public staking on testnet (no real yield, but full UX flow)
- Subgraph live, indexing testnet contracts
- 3rd audit if needed
- Final tokenomics frozen
- Legal: Cayman foundation incorporated, opinion letters in hand

### M-3 to M-1 — final readiness
- Audit reports published
- Legal opinions published (token classification, tax treatment in primary jurisdictions)
- Investor commitments closed (seed round, no further changes)
- TGE ops handbook frozen
- Market-maker contracts signed
- CEX listing arrangement signed (no payment)
- Genesis snapshot taken (for airdrop eligibility)

### TGE Day 0 (Tuesday recommended)
- 09:00 UTC: All contracts deployed to Base mainnet
- 09:30 UTC: Initial liquidity seeded on Aerodrome (1.5% of supply + matched USDC)
- 10:00 UTC: Balancer LBP starts (1.5% of supply over 72h, weighted descent)
- 12:00 UTC: Operator enrollment opens; first 5 agents enroll within 1 hour (reference operators from testnet)
- 14:00 UTC: First production attestation cycle runs
- 16:00 UTC: Staking opens to public
- 20:00 UTC: First operator vault crosses 100K $LITNUP TVL

### TGE Day 1-7
- Day 1: LBP continues; FDV likely overshoots fundamentals
- Day 2: First retail-stake events
- Day 3-5: LBP completes; price discovery on Aerodrome only
- Day 6: First DAO public council call (telemetry + observations)
- Day 7: Buyback+burn epoch 1 calculated (fee accrual since TGE)

### TGE Day 8
- First buyback+burn execution
- veAGENTIC voting power calculation kicks in (any locks made between Day 0 and 7 now count)
- First weekly transparency report

### TGE Day 14
- CEX listing goes live (single CEX; no payment to list)
- Market-maker active on both venues

### TGE Day 30
- First quarterly transparency report (in-depth)
- First slashing event likely happened (well-run protocol — first slash is usually around Day 20-40)
- v1.5 governance proposal considered (parameter-tuning only)

---

## Capital structure at TGE

**Total Supply: 1,000,000,000 $LITNUP (1B, capped, no inflation)**

| Bucket | % | Amount | Vesting / Use |
|---|---:|---:|---|
| Public liquidity (LBP + AMM seed) | 3% | 30M | Fully liquid Day 0; LBP-weighted release over 72h |
| Airdrop (genesis users) | 5% | 50M | Merkle, claim window 90 days; unclaimed → treasury |
| Staking emissions (operator+staker) | 17% | 170M | 24-month linear via EmissionScheduler |
| Treasury (governance) | 25% | 250M | 6mo cliff + 48mo linear; spend req. veAGENTIC vote |
| Team + early contributors | 20% | 200M | 6mo cliff + 36mo linear; vest-into-stake default ON |
| Advisors + ecosystem | 5% | 50M | 6mo cliff + 24mo linear; vest-into-stake default ON |
| Seed investors | 10% | 100M | 12mo cliff + 24mo linear; vest-into-stake default ON |
| Liquidity / partner reserve | 10% | 100M | Locked 24mo; release vote-gated |
| Insurance fund seed | 5% | 50M | Locked 12mo; releasable to InsuranceFund post-mainnet |

**Float on Day 0:**
- LBP + Aerodrome: ~30M (3%)
- Airdrop claim eligibility: ~50M cumulative if 100% claimed (realistically ~25M in week 1)
- Operator/staker rewards: ~0 in week 1 (emission stream just started; small amounts)

**Effective circulating Day 0: ~3-4% of total supply**

This intentionally low float prevents a price-overhang that would crash the launch. Early holders are concentrated in those who participated in the LBP at fair-value pricing.

---

## Why no private sale tokens vest before public

Every cohort vests the same schedule. The earliest unlock for ANY token-recipient (team, advisor, seed investor) is the same 6-month cliff that's published.

**We do not:**
- Give team unlock advantage over investors
- Give investors unlock advantage over the public
- Have a "founder allocation" with a different schedule
- Have secret allocations for influential parties

This isn't moral preening — it's economic. If insiders unlock before the public, every market participant prices in the dump risk and the token underperforms its fundamentals. The boring schedule is the high-Sharpe schedule.

---

## The Liquidity Bootstrap Auction (LBP)

We use Balancer's LBP framework with the following parameters:

- **Token allocation:** 1.5% of supply (15M $LITNUP)
- **Paired asset:** USDC
- **Initial weight:** 96/4 ($LITNUP / USDC)
- **End weight:** 50/50 (after 72h)
- **Initial USDC seed:** $300K (from treasury reserves)
- **Decay schedule:** Linear weight shift over 72 hours

The LBP creates a continuously-decaying price floor: starting weighted heavily toward $LITNUP, the curve incentivizes early buyers to wait (price drops as weight rebalances) and discourages snipe-and-dump (incoming buys move price up but the weight rebalance means later buyers get smaller bags for the same USDC).

This is fairer than:
- **IDO (single-price)**: snipers eat all retail; bots vs humans
- **Bonding curve**: same problem, with worse fee dynamics
- **Single-block fair launch**: 100% MEV captured by bots
- **CEX listing as TGE event**: zero retail access

After 72h, residual liquidity migrates to Aerodrome on a 1:1 basis at the LBP-final price. AMM trading continues from there.

---

## CEX listing approach

We are listing on **one** centralized exchange in week 1. We are NOT paying for the listing (no listing fee, no token grant, no market-making token loan paid to the exchange).

**Why one CEX and not five?**
- More CEXs = more demand for tokens to fund their market-making books = more sell pressure
- One CEX with strong API + retail volume gets us 90% of the trading benefit
- Fewer integration risks (custody, withdrawal pause, API changes)

**Which CEX?** Will be announced 7 days before listing. We are evaluating based on:
- No listing fee
- Crypto-native user base
- Reliable withdrawal infrastructure
- API quality for market-making partners
- No history of listing-and-delisting alts

**What we won't accept from a CEX:**
- Any payment for listing (token or USD)
- Required market-making allocation > 0.5% of supply on-loan
- Required volume/depth commitments that incentivize wash trading
- Lockup / staking requirements paid to the exchange's own staking products

---

## Market-making strategy

We have signed a single market-making partner. Their terms are public:

- **Inventory loan:** 0.4% of supply (4M $LITNUP) on a 12-month no-cost loan
- **Quote obligation:** ±2% spread, $50K depth at minimum, on both venues
- **Rebate share:** 50% of net positive PnL returned to treasury on loan close
- **Inventory return:** All 4M tokens returned at end of loan (or equivalent value if lost — they bear loss risk)
- **Conflict-of-interest disclosure:** they cannot prop-trade $LITNUP for their own book during the loan period

This is published in `legal/market-maker-agreement.md` (signed copy). We will publish quarterly market-making PnL reports.

---

## Airdrop design

5% of supply is reserved for the genesis airdrop. We snapshot **Base mainnet activity** between **Q1 2026 and Q1 2026-end**, looking at:

- Aerodrome LP activity (weighted)
- Hyperliquid trading volume (weighted; via Base bridge address)
- Any address that staked on the LITNUP testnet for 30+ days
- Any address that signed a public attestation of the LITNUP litepaper (a small "I read this" tx)
- Bug-bounty contributors (weighted by impact)

We avoid:
- Pure activity-farming addresses (clustered behavior, sybil patterns)
- Addresses with no other on-chain activity outside our snapshot set
- Wallets clearly used as relays / mixers

The airdrop is designed to reward real users, not farmers. We expect ~30K eligible addresses, with median grant ~1,500 $LITNUP.

Unclaimed tokens after 90 days return to treasury (governance-controlled).

---

## Founder & team token allocation

- **Founder:** 8% of supply, 6-month cliff + 36-month linear, vest-into-stake ON, no exception
- **Early team (3-5 people post-seed):** 8% of supply, 6-month cliff + 36-month linear, vest-into-stake ON
- **Advisors:** 4% of supply, 6-month cliff + 24-month linear, vest-into-stake ON

These are equal-treatment with the seed-investor cohort (12mo cliff + 24mo linear there is intentionally tighter because investors put in capital). Team and founders accept a lighter cliff in exchange for the work they put in pre-revenue.

**Founder pledge (public):** I will not sell any team-allocated $LITNUP for at least 18 months post-TGE. After that, sales will only happen through the protocol's quarterly OTC window with full disclosure. This pledge is non-binding legally but enforceable socially: it will be tracked publicly and any breach is the founder's reputation.

---

## What the launch is NOT

To preempt confusion:

- **Not a presale.** No tokens are sold to the public before TGE.
- **Not a fair launch.** A fair launch is single-block discovery; we use LBP for fairness with smoother dynamics.
- **Not a bonding curve.** No continuous token issuance against bonded reserves.
- **Not airdrop-only.** Airdrop is one of several pathways; not the launch mechanism.
- **Not a meme launch.** This token has a real-revenue thesis. We are competing on substance, not narrative.

---

## Risk scenarios + contingencies

### Scenario A: Audit finds critical issue 2 weeks before launch
**Action:** Delay TGE by minimum 6 weeks. Publish issue + remediation plan. Re-audit affected scope. We have 12+ months runway in the foundation, so a 6-week delay is not existentially risky.

### Scenario B: Market crash 1 week before launch (BTC -30%)
**Action:** Delay LBP by 2-4 weeks. Keep contract deployment + initial AMM seed live (low-volume, low-attention). Public re-launch when conditions stabilize. The protocol earns fees regardless of macro; we don't NEED a hot market to launch successfully.

### Scenario C: LBP price collapses below initial seed level
**Action:** This is the LBP's intended design — price discovery to fair value. We do NOT intervene with treasury buybacks during LBP. We let the market price.

### Scenario D: First operator slash on Day 5
**Action:** Run the public incident runbook. Publish the slash event with full attribution. Do NOT pause the protocol unless it's an oracle bug rather than a strategy failure.

### Scenario E: A regulator issues an opinion on $LITNUP
**Action:** Pre-positioned legal team handles. Foundation board has a contingency-comms plan. We do NOT halt operations preemptively unless legally required.

### Scenario F: Bridge / Base outage on Day 0
**Action:** TGE proceeds on schedule. The contracts deployed on Base will be live; user-facing UX may degrade if Base sequencer is down. Aerodrome trading depends on Base; CEX listing goes ahead and provides off-Base price discovery. We tolerate up to 4h delay; beyond that, we issue a coordinated reschedule.

---

## Communications plan

**Pre-TGE:**
- Litepaper + whitepaper public (already are)
- Weekly transparency reports
- Operator interviews on testnet experience
- Auditor public-comment period

**TGE Week 1:**
- Daily public "what happened today" recap (max 200 words)
- All metrics live in the public dashboard
- 1 founder Twitter/X long-form post per day (max)
- 1 podcast / interview slot per week max (we are not selling — we are explaining)

**Post-TGE:**
- Weekly transparency reports continue
- Monthly governance call (live, recorded, transcript published)
- Quarterly in-depth report (financials, parameter performance, what we got wrong)

---

## What we're not measuring success by

We will resist the following vanity metrics:

- **Twitter follower count.** Mostly bots.
- **Telegram member count.** Mostly bots.
- **Discord member count.** Some bots, some lurkers.
- **Number of CEX listings.** More listings ≠ better.
- **Announcement of partnerships before they ship.** We announce when integrations work, not before.
- **YouTube influencer hype.** Pay-to-promote is poison.
- **Headline FDV.** Float is so low at TGE that FDV is misleading; we focus on circulating market cap.

Success metrics we DO care about:

- **Total Value Staked across vaults.** Real capital backing real agents.
- **Cumulative protocol fee revenue.** Real money the protocol earned.
- **Cumulative buyback+burn.** Real tokens removed from supply.
- **Operator slashing rate.** A measure of mechanism design correctness.
- **Time-from-unlock-to-sell on team/investor cohorts.** A measure of long-term alignment.
- **veAGENTIC lock distribution.** Concentration vs. distribution of governance.
- **Audit-bounty payouts in 12 months.** A measure of the security surface.

---

## Sign-offs needed before TGE goes live

This list is the gating checklist that must be 100% green before we deploy mainnet contracts:

- [ ] All audits complete; all critical findings remediated and re-audited
- [ ] All testnet integration tests passing for 30+ consecutive days
- [ ] Insurance fund seeded with at least 5% of supply
- [ ] Foundation entity formed; opinion letters in hand
- [ ] Market-maker contract signed
- [ ] CEX listing confirmed
- [ ] Bug bounty live and at $250K cap
- [ ] Multisig signers (5-of-9) all hardware-key, geographically diverse, identity-verified
- [ ] Timelock at 48h for all governance actions
- [ ] PauseGuardian wired with explicit action whitelist; threshold 3-of-5
- [ ] Public dashboards live and rendering real testnet data
- [ ] Whitepaper + tokenomics + transparency pages all complete
- [ ] All vesting schedules created on-chain (not paper agreements alone)
- [ ] Founder pledge published

---

## A note on humility

Most TGE plans don't survive contact with the market. This one won't either. We will get something wrong on Day 1. The point of writing this down is to make our pre-launch reasoning visible so that when we adjust mid-flight, we can show what we changed and why.

We are not the smartest people in the room. We are not the most-funded protocol launching this quarter. We're not even the most hyped. What we are is the protocol that publishes its launch plan three months before launch and accepts public critique. That alone moves us up the trust curve.

— The LITNUP team

*Comments on this plan can be sent to plan@alphagentic.xyz or filed as a PR on the public docs repo.*
