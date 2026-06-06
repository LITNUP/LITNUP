# AAIP-NNN: Policy Revision — [Document Name]

**Proposal type:** Policy revision (treasury, opsec, incident runbook, post-mortem template)
**Tier:** Constitutional (20% quorum, 67% supermajority)
**Author:** [handle]

---

## TL;DR

We propose to revise the [DOCUMENT NAME] policy.

Document path: `docs/ops/[name].md`
Current version: [v1 / v2 / etc.]
Proposed version: [v2 / v3 / etc.]

Key changes (1-3 bullets):
- [...]
- [...]
- [...]

---

## Background

[Why does this policy need revising? What has changed since the last version?]

Current version was published: [YYYY-MM-DD]
Last incident or event prompting this revision: [...]

---

## Diff

### Section being changed: "[Section title]"

**Before (current):**

```
[Current text being replaced]
```

**After (proposed):**

```
[New text]
```

### Section being added (if any): "[Section title]"

**New text:**

```
[Full text of new section]
```

### Section being removed (if any): "[Section title]"

**Reason for removal:**

```
[Why is this section no longer needed?]
```

[Repeat for each change.]

---

## Rationale per change

For each change above:

### Change 1: [section name]
- Why: [...]
- Expected effect: [...]
- Alternative considered: [...]

### Change 2: [section name]
- Why: [...]
- Expected effect: [...]

[etc.]

---

## Stakeholder impact

| Stakeholder | Impact |
|---|---|
| Treasury signers | [...] |
| Oracle signers | [...] |
| PauseGuardian signers | [...] |
| Operators | [...] |
| Stakers | [...] |
| External auditors | [...] |
| Regulators (informational) | [...] |

---

## Implementation

### Documentation changes

This proposal changes a markdown document in the public docs repository. Implementation:

1. After Snapshot vote passes, the foundation merges the proposed PR to `main`
2. The diff is published with the revision date
3. The previous version is archived under `docs/ops/archive/[name]-vN.md`
4. A changelog entry is added to `docs/ops/CHANGELOG.md`
5. Affected stakeholders (signers, on-call, etc.) are notified

### Operational changes (if any)

If the revision changes operational behavior:

- [ ] Signers must acknowledge new policy in writing
- [ ] Drill exercises updated to reflect new procedures
- [ ] Onboarding materials updated
- [ ] External-facing docs updated

---

## Backwards compatibility

### Will signers/contributors who haven't read the new version cause issues?

[Yes / no — explanation]

### Are there any in-flight processes (active drills, ongoing incidents) that this change affects?

[Yes / no]

### Is there a transition period?

[If applicable: e.g., "The old policy applies for 30 days; both are valid simultaneously"]

---

## Risk assessment

### What if this revision introduces unintended weakness?

[Honest threat-model analysis]

### Reversibility

[Trivial: file another AAIP-07 to revert. Standard 14-day public comment period applies.]

---

## Voting

Vote **FOR** if you believe the revision improves the policy.

Vote **AGAINST** if you believe the current version is better or the changes introduce risk.

Vote **ABSTAIN** if you have insufficient context.

---

## Reporting

Within 7 days of execution:
- Diff published on docs repo
- Notification posted to [Forum / Twitter]
- Affected parties acknowledged

Within 30 days:
- First drill / exercise under new policy
- Initial assessment of policy effectiveness
