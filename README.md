# LITNUP

> **L**iquid **I**ntelligence **T**rading **N**etwork & **U**nderwriting **P**rotocol
>
> The verification layer underneath the AI agent economy. Every PnL is provable on-chain. Bad agents get slashed. Half of every fee burns $LITNUP permanently.

**Status:** Pre-mainnet · Live on Base Sepolia · Mainnet Q4 2026 (post-audit)
**Token:** `$LITNUP` · 1B capped supply · ERC-20 on Base
**Founder:** Arthur Romanov · LITNUP Foundation (Cayman Islands)
**License:** BUSL-1.1 → Apache-2 (2028)

---

## What LITNUP is

LITNUP is the **only protocol with provable PnL and skin-in-the-game for trading agents.** Operators bond ≥10,000 $LITNUP to put an agent on-chain. Stakers deposit $LITNUP into ERC4626-style vaults. Performance is attested through a multi-sig oracle. Bad attestations get slashed. 50% of every protocol fee buys $LITNUP on-market and burns it permanently.

Real revenue. Real burn. Real team. Real code.

If all crypto and financial markets and traders fail or disappear — then so does this protocol. Until then · we keep working.

---

## Quick links

- **Landing page:** [`web/landing-page.html`](web/landing-page.html) — the marketing site
- **Master plan:** [`web/master-plan.html`](web/master-plan.html) — single-source-of-truth document (tier-aware: public / investor / internal)
- **Investor portal:** [`web/investors.html`](web/investors.html) — gated IR materials for accredited contacts
- **Manifesto:** [`web/manifesto.html`](web/manifesto.html) — why we exist
- **Contracts:** [`contracts/src/`](contracts/src/) — Solidity, Foundry-based
- **Agent runtime:** [`agent-runtime/`](agent-runtime/) — Python SDK + reference agents
- **SDK:** [`sdk-typescript/`](sdk-typescript/) — TypeScript SDK for integrations
- **Subgraph:** [`subgraph/`](subgraph/) — The Graph indexer for on-chain events

---

## Repository structure

```
.
├── README.md                          ← you are here
├── PROJECT_LOG.md                     ← append-only log of plan vs. executed
├── LICENSE                            ← BUSL-1.1
├── CONTRIBUTING.md                    ← contribution guide
├── CODE_OF_CONDUCT.md                 ← community standards
├── SECURITY.md                        ← vulnerability disclosure
│
├── web/                               ← marketing site + master plan + portals
│   ├── landing-page.html              ← main marketing page
│   ├── master-plan.html               ← tier-aware single-source-of-truth doc
│   ├── master-plan-public.html        ← public-tier shim
│   ├── master-plan-investor.html      ← investor-tier shim
│   ├── master-plan-internal.html      ← internal-tier shim (gated)
│   ├── investors.html                 ← IR portal (gated)
│   ├── manifesto.html                 ← brand manifesto
│   ├── brand-kit.html                 ← brand assets + guidelines
│   ├── press.html                     ← press kit
│   ├── design-system.css              ← shared CSS for all marketing pages
│   ├── design-system.js               ← shared JS chrome
│   ├── brand/logo.svg                 ← canonical brand mark (power button)
│   └── ...                            ← agents, builders, careers, docs, faq, etc.
│
├── contracts/                         ← Solidity (Foundry)
│   ├── foundry.toml
│   ├── src/
│   │   ├── LitToken.sol               ← ERC-20Votes + Permit, capped 1B
│   │   ├── AgentRegistry.sol          ← permissionless enrollment + bonds
│   │   ├── StakingVault.sol           ← per-agent ERC-4626 vaults
│   │   ├── PerformanceOracle.sol      ← EIP-712 multi-sig attestations
│   │   └── BuybackBurn.sol            ← fee → swap → burn pipeline
│   └── test/                          ← Foundry test suite
│
├── agent-runtime/                     ← Python reference runtime
│   ├── requirements.txt
│   ├── .env.example
│   └── README.md
│
├── sdk-typescript/                    ← TypeScript SDK
├── subgraph/                          ← The Graph manifests
├── deploy/                            ← deployment scripts + verification
├── ops/                               ← runbooks, monitoring, on-call
├── governance/                        ← Snapshot space + DAO transition plan
├── legal/                             ← jurisdictional analysis, foundation bylaws
├── outreach/                          ← BD playbooks, press contacts
├── docs/                              ← litepaper, tokenomics simulator
├── deck/                              ← pitch deck (HTML)
├── plan/                              ← strategy, research, risk register
├── content/                           ← blog posts, narratives
└── logo/                              ← brand asset pack (PNG variants)
```

---

## Run the marketing site locally

The site is plain HTML/CSS/JS — no build step required.

```bash
# From repo root
cd web
python3 -m http.server 8000
# or: npx serve
```

Open `http://localhost:8000/landing-page.html`.

The deployment target is a static host (Vercel, Netlify, Cloudflare Pages) with clean-URL rewrites configured to map `/landing-page` → `landing-page.html`, etc.

---

## Build the contracts

```bash
cd contracts
forge install
forge build
forge test
```

See [`contracts/README.md`](contracts/README.md) for deployment instructions.

---

## Run the agent runtime

```bash
cd agent-runtime
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # edit with your keys
python -m litnup.cli --help
```

---

## How the protocol works

1. **Operator** bonds ≥10,000 $LITNUP and registers an agent on `AgentRegistry`.
2. **Stakers** deposit $LITNUP into the agent's `StakingVault` and receive vault shares (ERC-4626).
3. **Agent** trades. PnL is attested on-chain by a multi-sig oracle (EIP-712 signatures).
4. **Fees** are split: 50% to stakers as yield, 50% to `BuybackBurn` which buys $LITNUP on-market and burns it.
5. **Bad attestations** (false PnL claims) trigger slashing of the operator's bond. Slashed $LITNUP also flows to the burn.

Real revenue funds real burn. No emissions, no founder wallet, no Notion-page promises.

---

## Foundation & governance

- **Foundation:** LITNUP Foundation, registered in the Cayman Islands as a non-profit company limited by guarantee.
- **Founder & Chair:** Arthur Romanov ([`arthur@litnup.io`](mailto:arthur@litnup.io))
- **Treasury:** 5-of-9 multi-signature, signers geographically distributed across three jurisdictions.
- **Governance transition:** Q3 2027 → on-chain DAO via veAGENTIC (4-year vote-escrow).

For institutional inquiries, materials, and direct introductions: [`ir@litnup.io`](mailto:ir@litnup.io) and the [Investor Relations portal](web/investors.html).

---

## Security

If you've found a vulnerability, **do not open a public issue**. Follow the disclosure process in [`SECURITY.md`](SECURITY.md) or report through the Immunefi bounty (link in [`SECURITY.md`](SECURITY.md)).

The Solidity contracts are audited by:
- Spearbit
- Trail of Bits
- Cantina (competitive contest)

Audit reports become public on completion.

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the contribution workflow, code style, and review process. All contributors agree to the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

---

## License

Source code is licensed under the [Business Source License 1.1](LICENSE) with an automatic conversion to **Apache 2.0 on January 1, 2028**. Until then, commercial use requires written permission from the Foundation.

Brand assets in [`logo/`](logo/) and [`web/brand/`](web/brand/) are **CC-BY-NC-4.0**. Attribute LITNUP, don't sell, email [`brand@litnup.io`](mailto:brand@litnup.io) for commercial use.

---

## Stay close

- **Web:** [litnup.io](https://litnup.io)
- **X / Twitter:** [@LITNUP](https://x.com/LITNUP)
- **GitHub:** [github.com/litnup](https://github.com/litnup)
- **Email:** [hello@litnup.io](mailto:hello@litnup.io) · [ir@litnup.io](mailto:ir@litnup.io) · [arthur@litnup.io](mailto:arthur@litnup.io)
- **Foundation:** LITNUP Foundation · Cayman Islands · 2026

---

*Lights it turns up — periodically.*
