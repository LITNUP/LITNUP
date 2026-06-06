# Post-Mortem Template

**Status:** Template · use for every Sev 1 and Sev 2 incident
**License:** CC-BY-4.0

---

## Pre-publication checklist

Before publishing this document publicly:

- [ ] All facts verified by at least 2 contributors
- [ ] No specific attack-vector details that would enable replication of an unpatched issue
- [ ] No personal information about affected users
- [ ] Legal review (if regulatory implications)
- [ ] Founder review
- [ ] All action items have owners + deadlines

---

# Incident Post-Mortem · #[INCIDENT_ID]

**Author:** [Name + role]
**Date published:** [YYYY-MM-DD]
**Severity:** [Sev 1 / Sev 2]
**Status:** Resolved · monitoring · partial · ongoing

---

## TL;DR

[2-3 sentence summary written for someone who has 30 seconds]

What happened: [...]

Impact: [...]

Resolution: [...]

What we changed: [...]

---

## Timeline (UTC)

```
T+0:00  - Initial event / first detection
T+0:05  - On-call paged
T+0:08  - On-call ack
T+0:15  - Verification + triage complete
T+0:30  - PauseGuardian executes pause / first containment action
T+1:00  - First public update
T+2:30  - Root cause confirmed
T+4:00  - Mitigation deployed
T+5:00  - Resolution / public update
T+24:00 - Damage assessment finalized
T+72:00 - All affected users notified
T+14d   - This post-mortem published
```

Each entry should be a precise wall-clock UTC timestamp, what happened, and who did it.

---

## What happened

### Detection
[How was the incident detected? Monitoring alert? User report? Internal review?]

### Initial response
[What did the on-call do first? Was the response adequate? Were the right people paged?]

### Containment
[What was done to stop further damage? When? By whom?]

### Diagnosis
[What was the root cause investigation? What dead-ends did we go down? When was root cause confirmed?]

### Resolution
[What was the fix? When was it deployed? How did we verify it worked?]

---

## Impact

### User impact
[Number of affected users, exact loss amounts where applicable, % of TVL affected]

### Protocol impact
[Was protocol functionality disrupted? For how long? Which features?]

### Reputation impact
[Honest assessment — did this materially damage trust? How will we rebuild?]

### Financial impact
[Direct losses, remediation costs, insurance payouts, opportunity costs]

---

## Root cause

[Detailed explanation of the underlying cause. This section is the most important.]

### What we found
[The technical or process failure]

### Why it happened
[Why was this possible? Why didn't existing controls prevent it?]

### Why we didn't catch it earlier
[Tests we had that didn't fire. Reviews that missed it. Monitoring that didn't trigger.]

### Contributing factors
[Other factors that made this worse than it could have been]

---

## What went well

[Even in incidents, things work as designed. Acknowledge them honestly.]

- [E.g., monitoring fired within 4 minutes of root event]
- [E.g., on-call rotation responded within SLA]
- [E.g., PauseGuardian achieved 3-of-5 within 8 minutes]

---

## What went poorly

[Be specific and honest. This is where we improve.]

- [E.g., diagnosis took longer than expected because we lacked X dashboard]
- [E.g., communication lag between on-call lead and comms lead caused 30-min gap in public updates]
- [E.g., the fix introduced a regression that required a second deploy]

---

## What we got lucky on

[Things that could have made this much worse but didn't, by chance, not by design.]

- [E.g., the bug only triggered on a specific Path X that few users took]
- [E.g., market conditions limited the loss size]
- [E.g., a vigilant community member spotted the issue and reported it before exploitation]

If we got lucky, we need to design for the case where we don't get lucky next time.

---

## Action items

| # | Action | Owner | Type | Deadline | Status |
|---|---|---|---|---|---|
| 1 | [Specific action] | [Name] | [Engineering / Process / Tooling / Doc] | [Date] | [Open / Done] |
| 2 | ... | ... | ... | ... | ... |

Action types:
- **Engineering:** Code, contract, infrastructure changes
- **Process:** Runbook updates, procedure changes, role definitions
- **Tooling:** New monitoring, dashboards, or automation
- **Doc:** New / updated documentation, training materials

Every action item must have:
- A specific owner (one person, not a team)
- A deadline (specific date, not "next quarter")
- A status that updates publicly until done

---

## Lessons learned

[Generalizable observations beyond the specific action items.]

### About our system
[What did we learn about how the protocol behaves under stress?]

### About our process
[What did we learn about how we operate under stress?]

### About our assumptions
[What assumptions did we have that turned out to be wrong?]

---

## Public commitments

As a result of this incident, we commit to:

- [Specific change with deadline]
- [Another specific change]

These commitments will be tracked publicly until complete. If we miss a deadline, we publish why and a new deadline.

---

## Compensation

[If users were affected financially:]

- **Affected addresses:** [count + total loss in USD-equivalent]
- **Compensation source:** [Insurance fund / treasury / etc.]
- **Compensation rate:** [% of loss covered]
- **Distribution mechanism:** [Merkle drop / direct transfer / etc.]
- **Distribution timeline:** [Date]

---

## Q&A

[Pre-empt questions we expect from the community.]

**Q: Why didn't the audit catch this?**
A: [Honest answer — sometimes audits miss things; sometimes the scope didn't include this; sometimes it was a runtime issue not a code issue]

**Q: Will affected users be made whole?**
A: [Specific answer]

**Q: What's stopping this from happening again?**
A: [Specific controls]

**Q: Why did response take so long?**
A: [Honest answer]

---

## Acknowledgments

- [Person] for finding the issue
- [Person] for leading containment
- [Person] for the fix
- [Person] for communications coordination
- The community for [specific helpful behavior, e.g., patience, providing data, reporting symptoms]

---

## Appendix

### A. Technical details
[For technical readers — full technical writeup, code diffs, transaction hashes]

### B. Monitoring data
[Charts, logs, screenshots — anything that supports the timeline]

### C. References
- [Relevant audit reports]
- [Relevant prior incidents]
- [Related industry incidents we learned from]

---

*This post-mortem is published under CC-BY-4.0. Other protocols are encouraged to use it as a template, with the requested attribution.*

— [Name and role of post-mortem author]
