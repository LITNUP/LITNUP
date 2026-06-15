# SDK examples

Standalone reference implementations showing how to use `@litnup/sdk` and the contracts directly.

## staking-ui.html

A single self-contained HTML file demonstrating:

- Reading protocol state (total supply, vault TVL, share price)
- Reading per-wallet state (balance, voting weight, staked position)
- Writing: approve → stake → unstakeInit → unstakeComplete
- Live console for transaction status

**Usage:**

1. Replace the placeholder addresses in `CONTRACT_ADDRESSES` near the top of the script tag with your deployment (or copy from `/sdk-typescript/src/addresses.ts` post-mainnet).
2. Open the file directly in a browser (no build step required). It imports viem 2.21 via ESM CDN.
3. Click "Connect wallet" — needs MetaMask / Rabby / any EIP-1193 wallet pointed at Base Sepolia.

**Limitations:**

- Uses CDN imports — not suitable for production. Bundle locally with vite/esbuild/etc.
- Hard-codes Base Sepolia. For a real app, derive chain from wallet `chainId`.
- No transaction-receipt polling — just logs the hash. Real UI should `waitForTransactionReceipt`.
- Minimal styling. Adapt to your design system.

**Why a single HTML file:**

This example is intentionally low-tech so newcomers can read every line and understand exactly what's happening. Production apps will want the SDK + a framework. See `/sdk-typescript/src/react.ts` for the wagmi React hooks layer.

## Roadmap for additional examples

- `next-app/` — a complete Next.js + wagmi staking dApp using the React hooks
- `cli-staker/` — a Node CLI for batch operations from a server-side hot wallet
- `subgraph-dashboard.html` — example queries of the LITNUP subgraph
- `oracle-signer-bot/` — Python service that watches for attestation requests and co-signs
