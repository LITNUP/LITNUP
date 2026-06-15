# Ops Documentation Changelog

This file tracks revisions to the operational policies in `docs/ops/`.

Each entry is keyed by the document being changed + the AAIP that authorized the change. Entries are appended; previous versions are archived under `docs/ops/archive/`.

Format:
```
## [YYYY-MM-DD] — [Doc] vN → vN+1 — AAIP-NNN
- Brief summary of changes
- Diff link
- Vote / approval reference
```

---

## [2026-05-09] — Initial drafts

**Documents created:**
- `treasury-policy.md` v1
- `opsec-key-management.md` v1
- `incident-runbook.md` v1
- `post-mortem-template.md` v1 (template, not a policy doc; revisions don't require AAIP)

**Approval:** Foundation board internal review prior to public publication. Not yet ratified by veLITNUP vote (requires post-TGE governance to ratify).

**Effective:** 2026-05-09 (publication date).

**Note:** The first ratification vote (AAIP-001) will be filed after TGE to ratify the published policies as the canonical v1. Until ratification, these documents represent the foundation board's stated policy but are not on-chain governance-binding.

---

## [Future revisions will be logged here]

When a policy revision passes a Tier-Constitutional vote (per AAIP-07 template), append an entry here with:
- Date of execution
- Document changed + version bump
- AAIP reference
- 1-3 line summary of changes
- Link to full diff in the public docs repo
- Voter quorum + result

The previous version of the document gets archived to `docs/ops/archive/[name]-vN-YYYY-MM-DD.md` for historical record.

---

## Reading guide

- Latest version of each document lives at `docs/ops/[name].md`
- Archived versions live at `docs/ops/archive/[name]-vN-YYYY-MM-DD.md`
- This changelog is the audit trail
- Each AAIP is preserved in `governance/proposals/passed/AAIP-NNN.md` post-execution

---

*Maintained by the foundation operations team. Edits require board signoff.*
