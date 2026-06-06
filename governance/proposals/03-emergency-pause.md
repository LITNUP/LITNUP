# AAIP-NNN: EMERGENCY — Pause [Contract.Function]

**Proposal type:** Emergency pause action (NO Timelock — guardian-multisig action)
**Author:** [PauseGuardian member handle]
**Activation channel:** PauseGuardian contract (3-of-5 threshold)
**Public notice deadline:** Within 1 hour of execution

---

## ⚠️ EMERGENCY ACTION

This is NOT a normal governance proposal. This template is used to **document** an emergency pause action that is being executed (or has just been executed) via the PauseGuardian multisig.

### When to use

Only when **all** of the following conditions are met:
1. There is a confirmed protocol-level threat (oracle bug, exploit-in-progress, etc.)
2. Waiting 48h for a Timelock proposal would result in material harm
3. The pause action is on the PauseGuardian's pre-approved whitelist
4. At least 2 other guardian signers are reachable for the 3-of-5 threshold

### When NOT to use

- For non-emergency parameter changes (use AAIP-01 template)
- For oversight/concern about an operator's behavior (use Forum + AAIP-01)
- For functions NOT on the PauseGuardian whitelist (file AAIP-04 first to whitelist)

---

## Threat assessment

| Field | Value |
|---|---|
| Threat type | [Oracle bug / exploit / sequencer issue / etc.] |
| First detected at | [UTC timestamp] |
| Detected by | [Person/system] |
| Verification method | [How was it confirmed real?] |
| Estimated damage if unaddressed | [USD amount + per-hour rate] |
| Affected contract | [Contract name + address] |
| Affected function | [Function name + selector] |

---

## Action

### Pause being requested

```
target:   0x[contract address]
selector: 0x[4-byte selector]
calldata: 0x[full calldata if function takes args]
```

This corresponds to: `[ContractName].[functionName]([args])`

This action IS on the PauseGuardian whitelist.
Whitelist entry hash: 0x[actionId from PauseGuardian.getActionId]

### Cooldown

Action cooldown for this (target, selector): [N hours / minutes / 0]
Last execution time of this action: [timestamp / never]
Next eligible execution: [timestamp]

---

## Guardian approvals

| Guardian | Approved at | Tx hash |
|---|---|---|
| 0x... | [timestamp] | 0x[approve tx] |
| 0x... | [timestamp] | 0x[approve tx] |
| 0x... | [timestamp] | 0x[approve tx] |

Threshold reached at: [timestamp]
Execution tx: 0x[execute tx]

---

## Public communication

Within 1 hour of execution, the following will be published:

1. **Twitter/X:** [Initial public alert template — use Template 1 from incident-runbook.md]
2. **Status page:** Full incident summary
3. **Forum thread:** This proposal with all details

---

## Recovery plan

### Immediate next steps (T+0 → T+24h)

1. [Investigate root cause]
2. [Determine fix]
3. [Coordinate with auditors]

### Pause-lift conditions

The pause will be lifted when:
- [ ] Root cause confirmed
- [ ] Fix implemented and tested
- [ ] Audit firm sign-off received (if smart-contract change)
- [ ] AAIP-01 normal-governance proposal queued (or AAIP-04 whitelist update if needed)
- [ ] Affected users compensated (if applicable)

### Estimated time to lift

[Best estimate; with 50% confidence interval]

---

## Authority audit

PauseGuardian can ONLY:
- ✅ Call functions on the pre-approved whitelist
- ❌ Move funds (no transfer/withdraw on whitelist)
- ❌ Mint tokens (no mint on whitelist)
- ❌ Add new whitelist entries (requires Timelock proposal)
- ❌ Change threshold (requires Timelock proposal)

This action complies with the above limits.

---

## Post-incident action items

The following will follow this emergency pause:

1. **AAIP-NN:** Public post-mortem (using `post-mortem-template.md`)
2. **AAIP-NN:** Permanent fix proposal (parameter change or contract migration)
3. **AAIP-NN:** Whitelist update if needed
4. **Drill:** Tabletop exercise reviewing this incident's response
