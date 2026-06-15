# Deployment Guide — Hostinger Setup

> **Operating principle:** zero blast radius on your existing KVM2. Static files go to your business hosting via SFTP (completely separate). Anything that needs a server runs in an isolated Docker container that does not touch your existing services.

---

## What we're deploying (and where)

| Asset | Where | Why |
|---|---|---|
| `web/landing-page.html` | **Business hosting** (your domain root) | Pure static. Drop in via SFTP. Zero risk. |
| `web/dashboard.html` | **Business hosting** (`/dashboard/`) | Pure static. |
| `agent-runtime/` (Python) | **KVM2 in a Docker container** | Isolated. Doesn't touch your existing services. Optional — you can also run locally on your laptop. |
| Smart contracts | **Base Sepolia testnet** (free gas via faucet), then **Base mainnet** when audited | Not deployed to your servers — deployed on-chain. |
| `docs/litepaper.md` → HTML | **Business hosting** (`/docs/litepaper.html`) | Convert via `pandoc`, drop in via SFTP. |

---

## Phase 1 — Static site to business hosting (15 minutes, zero risk)

This is the safest possible deployment: just upload HTML files. They sit in their own folder. Nothing else on your hosting is touched.

### What you need
- Your Hostinger Business hosting credentials
- An SFTP client (FileZilla — free, https://filezilla-project.org)
- The four HTML files in `web/` and `deck/`

### Steps

1. **Open Hostinger control panel** → Hosting → Business plan → "FTP Accounts"
2. Create a dedicated FTP account named `agentic-deploy` with password (save in password manager)
3. Note the **FTP host** (usually `files.hostinger.com` or `<yourdomain>.hostinger.io`), **port 21** (FTP) or **22** (SFTP, prefer)
4. **Open FileZilla** → File → Site Manager → New Site
   - Protocol: **SFTP** (preferred) or FTP
   - Host: from step 3
   - User / Password: from step 2
5. Connect. Navigate to `public_html/` (or your domain's web root)
6. Create folder structure:
   ```
   public_html/
   ├── index.html              ← upload web/landing-page.html (rename!)
   ├── dashboard/
   │   └── index.html          ← upload web/dashboard.html (rename!)
   ├── deck/
   │   └── index.html          ← upload deck/pitch-deck.html (rename!)
   └── docs/
       └── (litepaper.html — convert from .md, see below)
   ```
7. **Test live:** open `https://<yourdomain>` in a fresh tab — landing page should render. Then `/dashboard/` and `/deck/`.

### Converting litepaper.md → HTML (optional, but improves SEO)

```bash
# install pandoc (one-time)
# macOS: brew install pandoc
# Ubuntu: sudo apt install pandoc
# Windows: download from https://pandoc.org/installing.html

pandoc docs/litepaper.md -o docs/litepaper.html \
  --standalone --css=https://cdn.simplecss.org/simple.min.css \
  --metadata title="LITNUP Litepaper"

# Then SFTP upload docs/litepaper.html
```

### DNS pointing (if your domain isn't already on Hostinger)

If your domain registrar is somewhere else (Cloudflare/Namecheap/etc), point its DNS to Hostinger:
- A record: `@` → Hostinger's IP (shown in your hosting panel)
- A record: `www` → same IP

Allow 5–60 minutes for propagation.

### Free CDN bonus (no risk)

Add Cloudflare in front of your Hostinger:
1. Add your domain at https://cloudflare.com (free tier)
2. Update nameservers at your registrar to Cloudflare's
3. Set Cloudflare DNS A record pointing to Hostinger IP
4. Enable "Full" SSL mode + "Always Use HTTPS"

This gives you: free CDN, free DDoS protection, free SSL, faster page loads. Doesn't change your hosting at all.

---

## Phase 2 — Agent runtime in Docker (KVM2, isolated)

> **DO NOT** run `apt install` or modify anything system-wide on your KVM2. Everything runs inside a container that you can `docker rm` to fully remove.

### What you need
- SSH access to your KVM2
- Docker already installed (most KVMs have it; if not, instructions below)
- About 200MB disk space + 256MB RAM per agent

### Verify Docker is installed (don't install if not — it can affect other services)

```bash
docker --version
# Should show "Docker version 20.x.x" or similar
```

If Docker is NOT installed and you want to install it without touching your existing services, the safest approach is **Podman** (rootless, doesn't conflict with anything):

```bash
# Ubuntu/Debian
sudo apt install -y podman
# Then use `podman` everywhere instead of `docker`. The CLI is identical.
```

### Pull the agent runtime onto KVM2

Since the repo is local, two options:

**Option A: rsync from your laptop** (recommended)
```bash
# from your laptop, in D:\LITNUP Token\
rsync -avz --exclude '.venv' --exclude '__pycache__' \
  agent-runtime/ user@your-kvm:/home/user/litnup-agent/
```

**Option B: tarball + scp**
```bash
# from your laptop
tar -czf agent-runtime.tar.gz agent-runtime/
scp agent-runtime.tar.gz user@your-kvm:/home/user/

# on KVM2
cd /home/user
tar -xzf agent-runtime.tar.gz
cd agent-runtime
```

### Build the Docker image

The Dockerfile is in `deploy/Dockerfile.agent-runtime`. Move it next to the agent-runtime code:

```bash
cd /home/user/litnup-agent
# (Dockerfile is in this same directory after deploy)

docker build -t litnup-agent .
# This takes 1-2 minutes; nothing else on your system is touched
```

### Run with isolated config

Use `docker-compose` (in `deploy/docker-compose.yml`) for clean lifecycle management:

```bash
# create .env from .env.example, fill in keys
cp .env.example .env
nano .env

# start the agent
docker-compose up -d

# tail logs
docker-compose logs -f

# stop and remove cleanly (no system trace)
docker-compose down
```

The container:
- Runs on its own network namespace (no port conflicts)
- Can only write to `./logs/` on your host
- Auto-restarts if it crashes (`restart: unless-stopped`)
- Uses **no privileged access**, **no host networking**, **no volume mounts other than ./logs**

### Resource budget

Per agent container:
- CPU: ~5% of 1 vCore (idle most of the time)
- Memory: ~150 MB RSS
- Disk: <50 MB total (logs grow ~2 MB/day)
- Network: ~10 KB/min outbound to CoinGecko

You can run 5–10 agents on a KVM2 without breaking a sweat.

---

## Phase 3 — Smart contracts to Base Sepolia (free)

Smart contracts deploy to chains, not servers. Your KVM2 is not involved.

```bash
# from your laptop
cd contracts

# install foundry if not yet
curl -L https://foundry.paradigm.xyz | bash
foundryup

# install deps
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit

# compile
forge build

# test (sanity check)
forge test -vvv

# get free Base Sepolia ETH
# https://www.alchemy.com/faucets/base-sepolia
# OR https://docs.base.org/tools/network-faucets

# create deploy script (sample provided in deploy/Deploy.s.sol)
forge script deploy/Deploy.s.sol \
  --rpc-url https://sepolia.base.org \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY
```

After deploy, copy the addresses into:
- `agent-runtime/.env` (for the agent runtime)
- `web/landing-page.html` (footer "deployed at: 0x..." link)
- `web/dashboard.html` (data source endpoint)

---

## Rollback procedures

### If anything breaks on the static site
- Just delete the uploaded files via SFTP. Your business hosting is back to whatever was there before.

### If anything breaks with the agent container
```bash
docker-compose down
docker rmi litnup-agent
rm -rf /home/user/litnup-agent
```
That fully removes the agent. Your KVM2 services are untouched.

### If a smart contract has a bug
- The contract is on Base Sepolia (testnet) — no real funds at risk
- Just deploy a new version
- Update the addresses in agent-runtime + web

---

## Domain pointing strategy

Recommended setup:

```
yourdomain.com               → Hostinger Business hosting (landing)
app.yourdomain.com           → Cloudflare Pages (free, separate from Hostinger)
docs.yourdomain.com          → Either, or use the /docs/ subpath
```

**Why split `app.yourdomain.com` to Cloudflare Pages later?**
When the dashboard becomes a real Next.js app (not just static HTML), Cloudflare Pages is the cheapest place to host it (free for low traffic, $0.30/M requests above). Keeps the dynamic stuff completely separate from your business hosting.

---

## Security checklist (before going live)

- [ ] `.env` files NEVER committed to git (already in `.gitignore`)
- [ ] FTP/SFTP credentials saved in password manager only, not in shell history
- [ ] KVM2 SSH uses key auth, not password (you already have this)
- [ ] Hostinger 2FA enabled on the account
- [ ] Cloudflare 2FA enabled on the account (when you sign up)
- [ ] Domain registrar 2FA enabled
- [ ] Smart contract deployer key is a fresh keypair generated for testnet — never reused for mainnet
- [ ] Agent oracle signer key is fresh, generated via `scripts/gen_signer.py`

---

## When to upgrade infra

You don't need to upgrade until:
- 1,000+ daily users on the dashboard → need real CDN + edge computing (Cloudflare Pages)
- Multiple agents running 24/7 → need orchestration (k3s on KVM2 or migrate to a $5 fly.io VM)
- Deploying to mainnet contracts handling real money → need monitoring (Tenderly, Forta, OpenZeppelin Defender)

For 6 months, the setup above costs **$0** beyond your existing Hostinger plan.
