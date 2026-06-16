# Comprehensive FAQ — by role

This is the deep-dive FAQ. The short version is at `/faq`.

This version is organized by **who is asking**: stakers, operators, governance participants, builders, press, and regulators each have different concerns. Find your role and skip the rest.

---

## Stakers

### Why would I stake $LITNUP on an agent?

You earn a share of the protocol fees that agent collects from running its trading strategy, paid to you as **USDC yield**. Your stake itself redeems at **principal only** — deposited $LITNUP is never inflated by the agent's PnL. PnL is reputation-only (it builds the agent's track record but does not change your redemption value). You can withdraw your principal at any time after a 7-day cooldown.

In effect: you're funding an autonomous AI trader's strategy, with the AI providing the alpha and you providing the capital. You are rewarded in USDC out of the protocol fees that strategy generates, not by your stake growing in token terms.

### What's the realistic yield I can expect?

There is **no guaranteed or fixed yield**. Any APY figure you see is illustrative/target only, is variable, and is not a promise. Your yield is paid in **USDC** out of the protocol fees the agent's strategy actually generates — so it depends entirely on real trading performance and fee flow.

We do NOT promise a yield. The protocol distributes only what agents actually earn from real trading. If an agent generates no fees, stakers earn no yield. Note that your stake redeems at principal regardless — a loss does not reduce your principal, but it does mean little or no USDC yield.

### What's my downside?

Three possibilities:
1. **Strategy underperformance.** The agent earns little or nothing, so your USDC yield is low or zero. Your principal is not reduced by trading losses (it redeems at principal), but you forgo the yield you were staking for. Mitigation: pick a well-performing agent; diversify across multiple agents.
2. **Drawdown slashing.** If the agent's vault hits 25% drawdown for one full attestation cycle (4 hours), 10% of the vault is slashed. You lose 10% of your staked principal. The remaining 90% continues to participate normally.
3. **Smart contract bug.** An undisclosed contract bug could result in loss of stake. Mitigated by a planned independent audit before mainnet, a bug bounty, and the insurance fund. (Note: an insurance-fund design that would cover a portion — e.g. 50% — of first-time slash losses is *planned/roadmap*, not currently implemented in the contracts.)

### What's the worst-case scenario?

A complete-loss scenario for one staker: 100% of one vault is slashed in a series of consecutive 25% drawdown breaches without you exiting. With cooldown of 7 days, you have 7 days from when warnings start to exit. So this requires you to be inattentive for 7+ days while the strategy implodes.

For comparison: this is similar to keeping money in a single hedge fund that goes to zero. An insurance fund is intended to backstop protocol-wide losses if multiple vaults blow up simultaneously, but its loss-coverage behavior is *planned/roadmap* and not yet implemented in the contracts. Per-vault risk is real.

### Can I lose more than I deposited?

No. Stake is a deposit. The most you can lose is what you deposited.

### How do I pick an agent?

The Agent Catalog at /agents shows for each agent:
- Strategy type (momentum, mean reversion, etc.)
- Operator track record
- Historical PnL (if any)
- Drawdown history
- Operator's bond (skin in the game)
- Current TVL
- Cumulative PnL / yield-distribution history (reputation track record; does not change your principal redemption)

Pick based on:
1. **Operator bond size** — more bond = more skin in the game = more aligned
2. **Strategy diversity** — diversify across at least 3 different strategy types
3. **Historical drawdown** — agents with low historical DD are less likely to slash
4. **Operator KYC status** — KYC'd operators are accountable; anonymous ones are not
5. **Total vault TVL** — higher = more market signal that others trust this operator

### Why is there a 7-day cooldown?

To prevent run-on-the-bank dynamics. If TVL could exit instantly on bad news, every minor blip would cause cascading withdrawals. 7 days gives the protocol time to absorb shocks without forced selling.

### Can I unstake during a slashing event?

You can initiate an unstake but it will only complete after the 7-day cooldown. If a slash happens during cooldown, your staked principal is reduced by the slash percentage at that moment.

### What's "vest-into-stake"?

This is a *planned/roadmap* design intent — it is **not implemented in the current contracts**. As designed, if you receive vested $LITNUP tokens (e.g., as a team member, advisor, or seed investor), they would auto-stake into a vault on unlock by default, and you would be able to:
- Override the default and have tokens go to your wallet
- Pick which agent to back
- Set a "monthly cash" portion that goes to wallet
- Unstake at any time on the standard 7-day cooldown

The intent is opt-out rather than opt-in. Treat this as forward-looking until it ships on-chain.

### How do I claim staking rewards?

Staking rewards are **USDC yield** that accrues to you as the protocol's fee revenue is distributed to stakers. You claim the accrued USDC from the vault via the public dashboard or SDK. Your $LITNUP principal stays as principal — it is never inflated by PnL, so unstaking returns the principal you deposited (less any slashing), separate from the USDC yield you claim.

For governance / emission rewards, claim via the RewardsDistributor contract using the public dashboard or SDK.

---

## Operators

### How do I become an operator?

1. Read `docs/agent-operator-onboarding.md`
2. Run an agent on testnet for at least 30 days; demonstrate positive expected behavior
3. Pass the operator-onboarding form: KYC + jurisdictional disclosure + strategy description
4. Post a bond in $LITNUP (minimum currently 10,000 $LITNUP, configurable by governance)
5. Submit metadata IPFS hash to the AgentRegistry
6. Wait for council approval (informal, 24-48h)
7. Stakers can begin staking on your agent

### What's the minimum bond?

10,000 $LITNUP. This is governance-tunable.

### What does the bond do?

- Demonstrates skin in the game (operators with no bond are unstakeable)
- Acts as a slashing reserve (if your agent drawdowns hit 25%, your bond gets slashed too — not just stakers)
- Funds your share of protocol fees back to you (you get the operator portion)

### What fees do I earn as an operator?

The performance fee is **reported via a threshold-signed EIP-712 oracle attestation** (it is not trustlessly derived from raw on-chain PnL — see the oracle question below). Each collected fee is denominated in **USDC** and split per-attestation according to a `toBuybackBps` value bound in the signature (0–10000):
- The buyback portion goes to BuybackBurn, which buys and burns $LITNUP on a DEX (reduces total supply, benefits all token holders)
- The remainder is distributed to stakers as **USDC yield** (not as share-price appreciation; principal is never inflated)

Any specific split (e.g., 50/50) is illustrative/default, not a hardcoded protocol parameter — there is no global on-chain "buybackBps" governance setting. The operator's own share of fees is configured per your enrollment within governance limits.

Fees accrue per attestation cycle (4 hours).

### What if my agent is under-performing?

You don't get slashed for being a bad trader. You get slashed for blowing up risk management.

Specifically:
- Negative PnL (losing money slowly) = stakers leave, your TVL falls, you earn less; not slashing
- Drawdown breach (25% from peak in one cycle) = slashing 10% of vault

So a small consistent loss is just bad performance. A blowup is slashing. The mechanism punishes risk failures, not trade failures.

### Can I run my own custom strategy?

Yes. The reference strategies in `agent-runtime/strategies` are just examples. You can plug in any strategy you want by implementing the `Strategy` interface (a `decide_position(context)` method).

You're responsible for:
- Implementing the strategy code
- Backtesting + paper-testing (the protocol only knows about your live performance)
- Risk management (the protocol's drawdown threshold is the floor, not your only constraint)
- Compliance with applicable laws in your jurisdiction

### How does the oracle attestation work?

Every 4 hours, your agent runtime computes its PnL since last attestation and an EIP-712 attestation is threshold-signed by independent oracle co-signers. The threshold is **3-of-5 on testnet**; it is configurable by governance, with a higher M-of-N targeted for mainnet. When enough signatures collect, anyone can submit them on-chain to apply the attestation.

Be aware this is a **trust assumption**: the reported PnL (and the resulting fee) is what the co-signer set attests to under EIP-712 — it is not trustlessly derived from raw on-chain PnL. The co-signers run independent verification of your PnL claim before signing.

### What if the oracle decides my reported PnL is wrong?

If the signing threshold isn't met, your attestation doesn't apply. No fee is recorded and no USDC yield is distributed to stakers for that period, and you don't earn fees for that period. This is the off-chain check on operator-reported numbers.

If you believe the oracle is wrong: post in the public Forum. The next governance cycle can address it.

### Can I exit being an operator?

Yes. Call `unbond()` on the AgentRegistry. This initiates a 30-day exit period (longer than staker cooldown to discourage operator flip-flopping). After 30 days, you withdraw your bond and the agent is marked Withdrawn.

Stakers in your vault can unstake as normal. They have the standard 7-day cooldown.

---

## Governance participants

### What is veLITNUP?

Vote-escrowed $LITNUP. Lock $LITNUP for up to 4 years; receive vote weight proportional to lock duration. Weight decays linearly to zero at unlock.

### How do I vote?

Two ways:
1. **Snapshot.** Off-chain signal vote on the LITNUP Snapshot space (`litnup.eth`). Free.
2. **On-chain Timelock.** After Snapshot passes, a proposer queues the action to the Timelock. Anyone with veLITNUP can vote here too.

### What's the Timelock?

A 48-hour delay between proposal queueing and execution. Provides:
- Public visibility of upcoming changes
- Time to migrate / exit if you disagree with a passed proposal
- Time to detect malicious proposals (e.g., signer compromises)

### What can governance NOT change?

The protocol is BUSL-1.1 and lacks an upgrade pattern. Governance cannot:
- Mint new tokens beyond the 1B cap
- Drain treasury without proper proposals
- Change the slashing mechanism's basic structure (only its parameters)
- Bypass the Timelock (except via PauseGuardian on whitelisted actions)
- Re-enable revoked PauseGuardian whitelist entries (requires another Timelock proposal)

### What can governance change?

- Drawdown threshold (currently 25%) within a band [10%, 50%]
- Slash size (currently 10%) within a band [3%, 30%]
- Cooldown duration (currently 7 days) within a band [1 day, 30 days]
- Per-vault cap (currently 1M $LITNUP)
- Protocol fee split between buyback+burn and stakers
- Emission scheduler weights and recipients
- Oracle signer set + threshold
- PauseGuardian whitelist
- Treasury spending tier limits
- Policy documents (treasury, opsec, incident runbook)

### How are proposals submitted?

Use templates in `governance/proposals/`. Each template defines structure, calldata, and rationale fields. Proposals must:
- Have at least 7 days of discussion before Snapshot vote
- Use exactly one template
- Reach quorum + threshold per the proposal tier

### Can I delegate my vote?

Yes. The DelegateRegistry contract lets you delegate by class:
- `vote` class — your veLITNUP weight is voted by your delegate
- `claim` class — your claim transactions execute on your delegate's call

You retain ownership; delegate just handles the action.

### What's the team's voting policy?

The Foundation reserve holds 10% of supply and the DAO treasury holds 15% (per the published allocation), but the Foundation votes only on Tier 1 (technical) proposals. We abstain on Tier 2/3 proposals affecting our own interests. We publish all our votes.

---

## Builders / integrators

### How do I integrate with LITNUP?

Three layers:
1. **Smart contract level.** Read state from public view functions; submit txs via your own wallet logic
2. **TypeScript SDK.** `@litnup/sdk` (and `@litnup/sdk/react` for hooks)
3. **The Graph subgraph.** Query indexed events for analytics / dashboards

### Where are the contract addresses?

Deployed addresses live in the SDK at `sdk-typescript/src/addresses.ts`. Base Sepolia (testnet) addresses are populated there now; Base mainnet is not deployed yet (pending).

The SDK auto-resolves by chainId from that module; you don't need to manage addresses manually.

### Are there integration grants?

Post-mainnet: yes. The Builder Grants Program will fund integrations that bring meaningful TVL or volume to the protocol. Pre-launch: not yet, because we have no fee revenue to fund it from.

For now: the Open Source Builder Recognition program lists integrations on the protocol's `/builders` page in exchange for: open-source code + a working integration + at least 30 days of operational uptime.

### Can I fork LITNUP?

The smart contracts are BUSL-1.1: source-available but not openly licensed for forking until 2028 (when they auto-relicense to Apache-2). The runtime, SDK, and docs are Apache-2 / CC-BY-4.0 — fork those freely.

If you need to fork the protocol earlier, contact the foundation. We'll consider commercial license terms case-by-case.

### How do I file a bug?

- For non-security bugs: GitHub Issues at `github.com/LITNUP/LITNUP`
- For security bugs: Immunefi at the official bounty URL. **Do not** file security issues on GitHub — that's public.

---

## Press / journalists

### What's LITNUP in one sentence?

LITNUP is a protocol where you stake tokens behind autonomous AI trading agents and earn from their real trading performance, with on-chain proof of every trade and automatic slashing if an agent's vault drawdowns past a threshold.

### Why is this different from other AI-trading projects?

Most "AI agent" tokens have no measurement: a chatbot brand-wraps a meme token, no real PnL is tracked, no real consequences exist. LITNUP ties operator pay and staker rewards to **publicly-verified PnL** (multi-sig oracle attestations on Hyperliquid + Aerodrome trade data) and **automatic slashing** of operators who blow risk limits.

### What's your competitive thesis?

Three differentiators:
1. **Measured accountability.** Operators get slashed for risk failures, not just for being unpopular.
2. **Real revenue flywheel.** Protocol fees buy back tokens. Tokens ↓ supply over time.
3. **Immutable contracts.** No backdoor admin pattern. What's deployed is what runs.

### Who's the team?

Arthur Romanov — sole founder and Chair of the LITNUP Foundation. Open to expansion through the foundation hiring process post-TGE. Specific operator-cohort and advisor list published at `/about`.

### What's the chain choice?

Base for mainnet (low fees + L2 scaling + EVM compatibility). Hyperliquid as primary execution venue for live trading. Aerodrome for DEX liquidity on Base.

### When is launch?

Target: Q4 2026 (after independent audit(s) planned before mainnet + 90 days testnet ramp). The protocol is currently testnet-only (Base Sepolia); mainnet is not deployed. Specific date posted 7 days in advance once all gating items pass.

### Can I get an interview?

We do approximately 1 podcast / interview per week post-TGE. Contact press@litnup.io with: outlet name, expected publish date, audience size, sample of past interviews.

### What's NOT for press?

- Pre-launch CEX listing identity
- Specific operator cohort identities (until they post their bond + go public themselves)
- Internal foundation operations
- Active incident-response details (only post-mortems)

---

## Regulators / compliance officers

### What's the legal structure?

- LITNUP Foundation, Cayman Islands (operating entity) — currently **in formation**
- Foundation is intended to hold the IP, treasury, and contracts

(Any additional operating subsidiaries are not finalized; see the flagged note below.)

### Is $LITNUP a security?

We do **not** currently hold any legal opinions; independent legal opinions are **planned**, not completed. The intended design is for $LITNUP to function as a utility token: it grants protocol access, governance rights, and staking utility. It is not equity in any company, and the Foundation is not a shareholder. This is our design intent, not a legal conclusion.

We intend to publish any opinions publicly once obtained, and to comply with the laws of each jurisdiction we operate in. Where the position is ambiguous, we err on the side of stricter compliance.

### How do you handle US persons?

Pre-TGE: foundation domicile excludes US persons from the airdrop and from the LBP via geo-fencing on the official frontend. US persons can interact with the contracts permissionlessly via any other interface.

Post-TGE: we treat the protocol as borderless and permissionless. US-specific compliance is the user's responsibility.

### Is there KYC?

For:
- Operators: yes (KYC required to enroll an agent)
- Foundation employees / contractors: yes
- Multisig signers: yes
- Stakers, governance participants, public users: no — the protocol is permissionless

### What about sanctions compliance?

The foundation operates from a sanctions-compliant jurisdiction. We use chain-analytics tools (Chainalysis / TRM Labs) to flag sanctioned addresses interacting with the protocol; flagged addresses cannot enroll as operators or receive treasury disbursements. The protocol contracts themselves don't enforce sanctions (they're permissionless), but the foundation's discretion does.

### Where can I see your compliance posture?

`docs/legal-checklist.md` and `legal/` directory in the public repo. Updated quarterly.

### What if you receive a subpoena?

We comply with applicable law. The incident runbook covers our process. We notify users via public communication to the extent legally permissible.

### What about AML/KYT?

The protocol is permissionless and contracts don't enforce AML. The foundation, operators, and any centralized service interacting with us implements AML per their own jurisdictional requirements.

---

## Common cross-role questions

### What chains is this on?

- Base Sepolia (testnet) — currently deployed
- Base mainnet (intended primary chain) — not deployed yet (pending)
- Future v2: cross-chain via LayerZero V2 (chains TBD by governance)

### What's the token contract address?

Base Sepolia (testnet), chainId 84532: `0x8027bb077D668407D6c0bb33Ba343c2dC44661d4` (LitnupToken), verified on Base Sepolia Basescan. Base mainnet is not deployed yet (pending). Deployed addresses are also resolvable from the SDK at `sdk-typescript/src/addresses.ts`.

### Where's the source code?

`github.com/LITNUP/LITNUP` (smart contracts, runtime, SDK, docs, marketing, governance — single monorepo).

### Where's the official communication?

- Twitter/X: `@LITNUP` (official, verified)
- Forum: `forum.litnup.io`
- Discord: https://discord.gg/Enr6BabmF
- Email: `team@litnup.io`

We do NOT use Telegram for official announcements. Any Telegram channel claiming to be official is a scam.

### Where can I get help?

- Read the docs: `docs.litnup.io`
- Forum: `forum.litnup.io` (slow, thoughtful answers)
- Discord: https://discord.gg/Enr6BabmF (faster, less precise)
- Github issues: `github.com/LITNUP/LITNUP/issues` (technical only)

We do NOT do customer support via DMs. If someone DMs you offering help, it's a scam.
