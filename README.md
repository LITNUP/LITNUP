# LITNUP

> **L**iquid **I**ntelligence **T**rading **N**etwork & **U**nderwriting **P**rotocol
>
> The verification layer underneath the AI agent economy. Every PnL is provable on-chain. Bad agents get slashed. Half of every fee burns $LITNUP permanently.

**Status:** Pre-mainnet · Contracts complete + full test suite green · Testnet (Base Sepolia) deployment pending · Mainnet post-audit
**Token:** `$LITNUP` · 1B capped supply · ERC-20 on Base
**Founder:** Arthur Romanov · LITNUP Foundation (Cayman Islands)
**License:** BUSL-1.1 → Apache-2 (2028)

> **Honest status note.** Nothing is deployed yet — there are no live contract addresses, and no
> third-party audit has been completed (audits are planned, not done). The protocol is code-complete
> with a green Foundry test suite (incl. a fuzzed solvency invariant). See [`PROJECT_LOG.md`](PROJECT_LOG.md)
> for the build log and [`deploy/DEPLOYMENT.md`](deploy/DEPLOYMENT.md) for the path to testnet → mainnet.

---

## What LITNUP is

LITNUP is a protocol for **attested PnL and skin-in-the-game for trading agents.** Operators bond ≥10,000 $LITNUP to put an agent on-chain. Stakers deposit $LITNUP against an agent as a bonded conviction stake. Performance is **attested** by a multi-sig oracle (a threshold of signers cryptographically agree on a PnL number — this is attestation, not a trustless proof; rooting attestations in venue/TEE/ZK settlement data is the v2 goal). Stakers earn real, exogenous yield in **USDC** from operator performance fees; 50% of each fee buys $LITNUP on-market and burns it. Bad agents are slashed.

Staked $LITNUP is **always redeemable at its principal** (reduced only by slashing) — attested PnL drives reputation and the fee basis, it does not inflate withdrawable balances. The vault is solvent by construction: on-chain token balance always covers staker principal.

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
│   │   ├── LitnupToken.sol            ← ERC-20Votes + Permit, capped 1B
│   │   ├── AgentRegistry.sol          ← permissionless enrollment + bonds
│   │   ├── StakingVault.sol           ← per-agent principal-redeemable vaults + USDC yield
│   │   ├── PerformanceOracle.sol      ← EIP-712 threshold-signed attestations
│   │   ├── BuybackBurn.sol            ← USDC fee → swap → burn pipeline
│   │   └── … (VotingEscrow, Vesting, EmissionScheduler, InsuranceFund, PauseGuardian, Timelock, …)
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
# Dependencies are pinned and vendored (lib/ is gitignored — clone exact tags):
git clone --depth 1 --branch v5.1.0 https://github.com/OpenZeppelin/openzeppelin-contracts lib/openzeppelin-contracts
git clone --depth 1 --branch v1.9.4 https://github.com/foundry-rs/forge-std lib/forge-std
forge build
forge test          # 157 tests, incl. a fuzzed solvency invariant
```

See [`deploy/DEPLOYMENT.md`](deploy/DEPLOYMENT.md) for deployment + the testnet → mainnet runbook.

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
2. **Stakers** deposit $LITNUP against the agent in `StakingVault` and receive shares. Shares redeem at principal (slash-adjusted) — PnL never inflates them.
3. **Agent** trades off-chain. PnL is attested on-chain by a threshold-signed multi-sig oracle (EIP-712). This records reputation and sets the fee basis.
4. **Fees** are paid by the operator in **USDC** (real, exogenous value) and split: half streams to that agent's stakers as claimable USDC yield, half to `BuybackBurn` which swaps USDC → $LITNUP and burns it.
5. **Confirmed misbehavior** triggers threshold-signed slashing of the operator's bond and/or staker principal; slashed $LITNUP flows to the burn.

Yield and burn are funded by real USDC fees, not by token emissions to stakers. (The protocol does pre-allocate a vesting/ecosystem schedule per the tokenomics — see `docs/tokenomics.md`; "no emissions" refers to no inflationary minting beyond the 1B cap.)

---

## Foundation & governance

- **Foundation:** LITNUP Foundation, a Cayman Islands non-profit foundation (company limited by guarantee), currently in formation.
- **Founder & Chair:** Arthur Romanov ([`arthur@litnup.io`](mailto:arthur@litnup.io))
- **Treasury:** a planned 5-of-9 multi-signature treasury with geographically-distributed signers.
- **Governance transition:** Q3 2027 → on-chain DAO via veLITNUP (4-year vote-escrow).

For institutional inquiries, materials, and direct introductions: [`ir@litnup.io`](mailto:ir@litnup.io) and the [Investor Relations portal](web/investors.html).

---

## Security

If you've found a vulnerability, **do not open a public issue**. Follow the disclosure process in [`SECURITY.md`](SECURITY.md) or report through the Immunefi bounty (link in [`SECURITY.md`](SECURITY.md)).

Audits are **planned, not yet completed**. No third-party audit report exists today and the contracts
have **not** been deployed to any public network. The intended pre-mainnet audit track is an
independent firm review plus a competitive contest; reports will be published here when complete.
Do not treat the current code as audited. See `deploy/DEPLOYMENT.md` §5 for the full list of
mainnet gates (audit, legal opinion, multisig ceremony, monitoring).

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
- **GitHub:** [github.com/LITNUP/LITNUP](https://github.com/LITNUP/LITNUP)
- **Email:** [hello@litnup.io](mailto:hello@litnup.io) · [ir@litnup.io](mailto:ir@litnup.io) · [arthur@litnup.io](mailto:arthur@litnup.io)
- **Foundation:** LITNUP Foundation · Cayman Islands (in formation) · 2026

---

*Lights it turns up — periodically.*
