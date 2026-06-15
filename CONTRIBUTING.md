# Contributing to LITNUP

Thanks for considering a contribution. This guide tells you how to work with the codebase productively.

---

## Quick start

```bash
# Clone
git clone https://github.com/LITNUP/LITNUP.git
cd litnup

# Smart contracts
cd contracts
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
forge build
forge test

# Agent runtime
cd ../agent-runtime
python -m venv .venv
source .venv/bin/activate    # or .venv\Scripts\activate on Windows
pip install -r requirements.txt
python scripts/gen_signer.py
python -m agent_runtime.paper_trade --strategy momentum --asset BTC --duration 1h --interval 30s
```

---

## How we work

- **`main` is always green.** No broken main, ever. CI must pass before merge.
- **Small PRs.** A 200-line PR gets reviewed today; a 2,000-line PR gets reviewed next week.
- **One concern per PR.** Don't bundle a refactor with a feature. Two PRs.
- **Tests come with code.** New contract function → new test. New strategy → new backtest result.

## What lives where

```
contracts/        ← Solidity. Foundry-managed. Audit-target.
agent-runtime/    ← Python. The off-chain agent. EIP-712 signs attestations.
web/              ← Static HTML. Landing + dashboard. No build step.
deck/             ← Pitch deck (HTML).
docs/             ← Litepaper, tokenomics. Markdown + interactive HTML simulator.
plan/             ← Strategy / capital / risk / legal. Markdown.
outreach/         ← Grant apps, accelerator apps, Twitter content, KOL list.
brand/            ← Logo SVG, brand guide.
deploy/           ← Hostinger guide, Dockerfile, Foundry deploy script.
.github/          ← CI workflows + issue/PR templates.
content/          ← Blog posts, demo script.
PROJECT_LOG.md    ← Append-only project diary. Read first.
```

## Coding standards

### Solidity
- Solidity `0.8.24`, SPDX `BUSL-1.1` for protocol code, `MIT` for tests.
- OpenZeppelin contracts where possible. No custom auth, no custom math.
- All state-changing externals: `nonReentrant`. All state writes happen *before* external calls.
- Custom errors (`error InsufficientBond();`) over revert strings.
- Natspec on every public/external function. Why, not just what.
- Slither must pass at `--fail-on medium` or higher. Document every supressed finding.

### Python
- Python 3.11+. `from __future__ import annotations` at the top of every module.
- Type hints required on public APIs.
- Avoid runtime dependencies beyond what's in `requirements.txt`. Justify every new dep in your PR.
- Errors should be loud. No silent `except Exception: pass`.

### HTML / CSS / JS
- Single-file deliverables. No build step. No npm. No bundlers.
- System fonts. No Google Fonts (privacy + speed).
- CSS variables for color tokens (see `brand/brand-guide.md`).
- Mobile-friendly: every page must work on 375px wide viewport.

## Commit messages

```
<type>: <subject>

<optional body>
<optional footer>
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `style`, `perf`.

Subjects: imperative mood, ≤72 chars, no trailing period.

Examples:
- `feat: add VotingEscrow contract with 4-year max lock`
- `fix: correct rounding in StakingVault._toAssets for small share amounts`
- `test: add Merkle airdrop fuzz coverage for invalid proofs`

## Pull request review

We review for, in order:

1. **Security.** Does this introduce attack surface? Is access control correct?
2. **Correctness.** Does the code do what it claims?
3. **Test coverage.** Are edge cases covered?
4. **Style/clarity.** Is it readable in 5 years?

PRs without tests will be sent back. Tests-only PRs are welcome.

## Security

If you discover a security vulnerability, **do not open a public issue.**

- Email: `security@litnup.xyz`
- Or report through our Immunefi program (when live)

We pay for valid findings. See [SECURITY.md](SECURITY.md).

## License

By contributing, you agree your contributions will be licensed under:
- BUSL-1.1 for protocol code
- Apache-2 for tooling and docs
- MIT for tests and examples

## Communication

- Github discussions: long-form questions
- Discord: real-time chat
- Twitter: announcements + product
- For private/sensitive: `team@litnup.xyz`
