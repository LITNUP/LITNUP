# Incident Response Runbook

**Status:** Draft v1 · last updated 2026-05-09
**Audience:** On-call rotation, foundation board, security advisors, technical leads
**License:** CC-BY-4.0

---

## Purpose

When something goes wrong — and something will go wrong — this runbook defines what we do, in what order, with what authority. The goal is to **act fast enough to contain damage** while **slow enough to avoid making it worse.**

Every incident requires three things:
1. **Triage** — what's happening, how bad is it
2. **Containment** — stop further damage
3. **Communication** — tell the people who need to know

This runbook is structured around those three phases.

---

## Severity levels

| Sev | Definition | Response time | Escalation |
|---|---|---|---|
| **Sev 1** | Confirmed protocol-level fund loss in progress, OR confirmed key compromise, OR confirmed oracle bug producing live attestations | <5 min ack, <15 min response | All-hands; Pause Guardian consideration immediate |
| **Sev 2** | Suspected critical issue (unconfirmed); high-severity bug report from auditor; CEX listing emergency | <30 min ack, <2h response | Founder + 2 board members + on-call lead |
| **Sev 3** | Operational issue (RPC failure, attestation lag, frontend down) without fund risk | <2h ack, <8h response | On-call lead |
| **Sev 4** | Cosmetic / non-urgent (UI bug, typo, doc issue) | Next business day | Issue tracker |

---

## On-call rotation

- 5 signers from the PauseGuardian + Foundation Operational rotation
- Schedule: 24h shifts in 5-day rotations
- Primary: pages first
- Secondary: pages if primary doesn't ack within 5 minutes
- Tertiary: pages if both primary + secondary don't ack within 15 minutes
- All shifts logged; missed pages reviewed in monthly retrospective

---

## Sev 1 playbook

### T+0 (immediately)
1. **ACK the page** within 5 minutes
2. **Open incident channel** in foundation Signal: `#incident-YYYY-MM-DD-HHMM`
3. **Page the PauseGuardian** — message all 5 guardians, request 30-min on-call availability
4. **Confirm the incident is real** — verify the alert source; check if it's a monitoring false-positive
5. **Snapshot the chain state** — record block number, contract addresses, suspected attack vector

### T+5min
1. **Triage with on-call lead** — is this protocol funds or single-user funds?
2. **Decide pause-or-not:**
   - Confirmed live exploit → pause immediately (3-of-5 PauseGuardian, target = affected contract)
   - Suspected exploit, unverified → 15-min verification window before pause
   - Off-chain ops issue (RPC, frontend) → no pause needed
3. **Designate Incident Commander** — usually on-call lead; may transfer to founder/CTO if escalates
4. **Designate Communications Lead** — separate person; their job is messaging only

### T+15min
1. **External monitoring** — engage Forta / Tenderly / OpenZeppelin Defender for additional intel
2. **Auditor notification** — page audit firms with active retainer (Spearbit on-call channel)
3. **First public acknowledgment** — Twitter + status page: "We're investigating an incident. More info within the hour."

### T+1h
1. **Status update** — public post with confirmed facts only:
   - What we know
   - What we don't know
   - What we've done so far
   - When the next update is expected
2. **Begin remediation planning** — patch / mitigation / governance proposal as needed
3. **Begin damage assessment** — affected addresses, expected loss amount

### T+4h
1. **Status update** with refined damage assessment
2. **Mitigation steps** identified and being executed
3. **If contract-level fix needed** — begin Timelock proposal; communicate timeline

### T+24h
1. **Full public incident report draft** — facts, timeline, what we did
2. **Affected user outreach** if applicable
3. **Insurance fund consideration** if user funds were lost

### T+72h (or earlier if resolved)
1. **Resolution announcement**
2. **Post-mortem schedule** announced
3. **Compensation plan** if applicable

### T+14 days
1. **Public post-mortem published** (use template below)
2. **Action items tracked publicly** with owners + deadlines
3. **Bug bounty payout** if applicable

---

## Common Sev 1 scenarios

### Scenario: Oracle bug — incorrect attestation applied
**Symptoms:** Attestation shows PnL delta inconsistent with verifiable on-chain trading data
**Actions:**
1. PauseGuardian: pause `PerformanceOracle.applyAttestation` (already executed attestations cannot be reverted, but we stop the bleed)
2. Verify via independent recompute against Hyperliquid API + Aerodrome subgraph
3. If oracle was wrong: governance proposal to compensate affected vault from insurance fund
4. If oracle was right but suspicious: publish reasoning + no action

### Scenario: Single-vault drawdown breach with suspected slashing-grief
**Symptoms:** Operator appears to have intentionally caused a 25%+ drawdown
**Actions:**
1. Allow slashing to execute (mechanism working as designed)
2. Investigation: was this a real strategy failure, an exploit, or sabotage?
3. If sabotage: pursue legal action against operator; flag operator address for community awareness
4. Public report on what happened

### Scenario: Smart contract critical-severity finding (post-launch audit / bounty)
**Symptoms:** Auditor / bug-bounty hunter reports critical finding
**Actions:**
1. PauseGuardian: pause affected functionality if fix is non-trivial
2. Verify the finding internally + with second auditor
3. Patch via:
   - If parameter-tunable: governance vote
   - If contract-level: deploy fix + migration via Timelock proposal (24+h)
4. Pay bounty per Immunefi tier
5. Public disclosure after fix is live (responsible disclosure timeline: 7-14 days post-fix)

### Scenario: Multisig signer key compromise
**Symptoms:** Signer reports lost device, suspected phishing, or unauthorized signing attempt
**Actions:**
1. Foundation board emergency call within 1h
2. Immediate signer rotation: 8-of-9 Foundation Safe replaces compromised signer
3. Move all assets from any wallet that compromised signer had even partial access to
4. Public disclosure: "We rotated a multisig signer for opsec reasons" (no specifics that aid attacker)
5. Forensics: how did the compromise happen? Update opsec policy if needed

### Scenario: CEX outage during high-volume period
**Symptoms:** Listed CEX freezes withdrawals or pauses trading
**Actions:**
1. Status update: communicate scope (CEX-specific, not protocol-wide)
2. Engage CEX support channel directly (foundation has direct line)
3. Refer users to Aerodrome (DEX) for liquidity
4. Monitor for resolution; update users every 4h

### Scenario: Bridge / chain outage (Base sequencer down)
**Symptoms:** Base sequencer halted; transactions don't confirm
**Actions:**
1. Status update: Base-wide issue, not protocol-specific
2. Coordinate with Base team for ETA on resolution
3. Operators continue trading (off-chain); attestations queue and flush on resume
4. No protocol action needed; this is L1-level

### Scenario: Sanctions / regulatory enforcement notice
**Symptoms:** Foundation receives subpoena, enforcement notice, sanctions designation
**Actions:**
1. Foundation legal counsel engaged immediately
2. Foundation board emergency call within 6h
3. Compliance with applicable laws as required
4. Public disclosure to extent legally permissible
5. Operations continue unless legally enjoined

---

## Communication templates

### Template 1: First public acknowledgment (T+15min)

```
We're investigating a potential issue with [scope].
Status: under active investigation
Affected: [TBD or known scope]
Action: [pause status / what we've done]
Next update: [time]
Status page: status.litnup.io
```

### Template 2: Hourly update (T+1h, T+2h, ...)

```
Update on incident #[id]
Time: [UTC]
What we know: [bullets]
What we don't know: [bullets]
What we're doing: [bullets]
Next update: [time]
```

### Template 3: Resolution

```
Incident #[id] resolved.
Started: [UTC]
Resolved: [UTC]
Duration: [N hours]
Root cause: [one line]
User impact: [exact numbers if any]
Compensation: [details]
Post-mortem: [date]
Status page: status.litnup.io
```

### Template 4: Post-mortem (T+14 days)

See `post-mortem-template.md`.

---

## What we don't communicate during an incident

- Specifics of the attack vector that would help replicate it (until patch is live)
- Speculation about attribution
- Affected user names or addresses (privacy)
- Exact loss amounts before they're verified
- Internal team names beyond what's public

---

## Tools & dashboards

| Tool | Purpose | Owner |
|---|---|---|
| Forta | Real-time chain monitoring | Security lead |
| Tenderly | Tx simulation + alerts | Backend |
| OpenZeppelin Defender | Operational ops | Backend |
| PagerDuty | On-call rotation | Ops lead |
| Signal `#incident` | Comm channel | Founder |
| Status page (statuspage.io) | Public comms | Comms lead |
| Twitter @LITNUP | Public comms | Comms lead |

---

## Authority matrix

| Action | Authority | Confirmation needed |
|---|---|---|
| Pause whitelisted contract | 3-of-5 PauseGuardian | Internal verification within 15 min |
| Move from operational multisig (within Tier 1) | 2-of-5 ops | One peer review |
| Move from operational multisig (Tier 2) | 3-of-5 ops + 24h notice | Public notice |
| Foundation Treasury emergency move | 5-of-9 + emergency provision | Board verbal approval; ratify in 30 days |
| Public communication | Communications Lead | Founder approval for high-stakes |
| Engage law enforcement | Legal Counsel | Founder approval |
| Pay bug bounty | Founder via ops multisig | Per Immunefi tier scale |

---

## Drills

This runbook is exercised quarterly. Each drill:
- Picks 1 scenario at random from the list above
- Tests on-call rotation reachability + decision-making
- Times each phase against expected response time
- Identifies gaps to feed back into runbook revisions

Most recent drill: 2026-04-15 — scenario "oracle bug." Result: 14 min ack, 25 min triage. Gap: status-page update lagged by 35 min. Action: assigned dedicated Comms Lead role on subsequent drills.

---

## Revisions

This document is versioned. Revisions require:

- Security lead + on-call rotation review
- Foundation board acknowledgment
- Diff published to internal repo

Last revision: 2026-05-09 (initial draft).
