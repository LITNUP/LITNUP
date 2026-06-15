# @alphagentic/sdk

TypeScript SDK for LITNUP. Read protocol state, stake on agents, enroll new agents, and verify EIP-712 oracle attestations from any browser or Node environment.

Built on [viem](https://viem.sh) (peer dep) — no `ethers.js` legacy.

> **Status: alpha (v0.1).** API surface is stable enough to build on but expect refinements through mainnet launch (Q4 2026).

## Install

```bash
npm install @alphagentic/sdk viem
# or
pnpm add @alphagentic/sdk viem
# or
bun add @alphagentic/sdk viem
```

## Quick start — read protocol state

```ts
import { createPublicClient, http } from 'viem';
import { base } from 'viem/chains';
import { LITNUP } from '@alphagentic/sdk';

const client = createPublicClient({
  chain: base,
  transport: http(),
});

const protocol = new LITNUP({ client, network: 'base' });

// Read current TVL across all vaults
const tvl = await protocol.getTotalTVL();
console.log(`Total staked: ${tvl} $LITNUP`);

// Get top agents by 30-day Sharpe
const top = await protocol.agents.list({ sortBy: 'sharpe', limit: 10 });
top.forEach(a => console.log(`#${a.agentId} ${a.name} — Sharpe ${a.sharpe30d}`));

// Get a specific agent's full state
const agent = await protocol.agents.get(42);
console.log(agent);
```

## Quick start — stake (write transaction)

```ts
import { createWalletClient, custom, parseEther } from 'viem';
import { LITNUP } from '@alphagentic/sdk';

const wallet = createWalletClient({
  chain: base,
  transport: custom(window.ethereum),
});

const protocol = new LITNUP({ client: wallet, network: 'base' });

// 1. Approve $LITNUP for the vault
const approvalTx = await protocol.token.approve(
  protocol.addresses.StakingVault,
  parseEther('1000')
);
await client.waitForTransactionReceipt({ hash: approvalTx });

// 2. Stake
const stakeTx = await protocol.stake({
  agentId: 42,
  amount: parseEther('1000'),
});
console.log('Staked:', stakeTx);
```

## Quick start — verify an attestation off-chain

```ts
import { verifyAttestation } from '@alphagentic/sdk/attestation';

const isValid = await verifyAttestation({
  attestation: {
    agentId: 42n,
    pnlDelta: 250n * 10n ** 18n,
    feeOnGross: 25n * 10n ** 18n,
    epoch: 7n,
    deadline: 2_000_000_000n,
  },
  signature: '0x...',
  expectedSigner: '0xab...cd',
  chainId: 8453,
  oracleAddress: '0x...',
});

console.log('Signature valid:', isValid);
```

## API surface

### `LITNUP` (top-level client)

- `protocol.agents.list(opts?)` — list agents with sort / filter / pagination
- `protocol.agents.get(agentId)` — full state of one agent
- `protocol.agents.enroll(params)` — register a new agent (operator-only)
- `protocol.stake({ agentId, amount })` — stake into an agent vault
- `protocol.unstakeInit({ agentId, shares })` — start unstake cooldown
- `protocol.unstakeComplete({ agentId })` — claim after 7-day cooldown
- `protocol.governance.lock({ amount, unlockTime })` — veAGENTIC lock
- `protocol.governance.proposals()` — list active proposals
- `protocol.token.balanceOf(address)` — $LITNUP balance
- `protocol.token.approve(spender, amount)` — token approval

### `attestation/`

- `verifyAttestation(params)` — verify an EIP-712 oracle attestation
- `buildTypedData(params)` — produce the EIP-712 typed data for signing
- `recoverSigner(signature, typedData)` — recover the signer address

### `react/` (optional)

- `useAgent(agentId)` — react hook for live agent state
- `useStake(agentId)` — staking state + actions
- `useGovernance()` — governance lock + proposals

## Architecture

```
sdk-typescript/
├── src/
│   ├── index.ts            ← top-level LITNUP client
│   ├── addresses.ts        ← deployed contract addresses per network
│   ├── abis/               ← contract ABIs (auto-generated from forge build)
│   ├── agents.ts           ← agent registry / vault module
│   ├── staking.ts          ← stake / unstake actions
│   ├── governance.ts       ← veAGENTIC + proposal queries
│   ├── attestation.ts      ← EIP-712 attestation verification
│   ├── token.ts            ← LitToken module
│   └── types.ts            ← shared types
├── package.json
└── tsconfig.json
```

## Versioning

Pre-mainnet versions follow `0.x.y`. v1.0 ships at TGE. We follow strict semver after that.

## License

Apache-2.0. See LICENSE in repo root.

## Contributing

PRs welcome. Issues for bugs and proposed APIs at github.com/alphagentic.
