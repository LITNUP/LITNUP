# LITNUP Subgraph

Indexer for the LITNUP protocol. Powers fast queries for the dApp, the public dashboard, and the SDK's `indexerUrl` fast path.

## Status

Schema + manifest ship as part of this repo. Mapping handlers (`src/*.ts` AssemblyScript files referenced in `subgraph.yaml`) are NOT in this repo yet — they're trivial event-to-entity translations and will be written during the public-testnet rollout (Q3 2026), when the contract addresses are settled.

If you're a contributor and want to take a stab at the mappings before then, follow [The Graph's quick-start guide](https://thegraph.com/docs/en/quick-start/) and submit a PR.

## Layout

```
subgraph/
├── subgraph.yaml      # data sources + event handlers
├── schema.graphql     # entity types
├── README.md          # this file
└── src/               # AssemblyScript mapping handlers (TBD)
    ├── registry.ts
    ├── vault.ts
    ├── oracle.ts
    ├── buyback.ts
    └── voting.ts
```

## Sample queries

### Top 10 agents by 30-day Sharpe

```graphql
{
  agents(
    first: 10
    orderBy: sharpe30d
    orderDirection: desc
    where: { status: Active }
  ) {
    id
    agentId
    operator { address }
    bond
    totalAssets
    sharpe30d
    pnl30dPct
    maxDrawdownPct
    totalStakers
  }
}
```

### Stakers' position across all their agents

```graphql
{
  staker(id: "0xabcd...") {
    cumulativeStaked
    cumulativeUnstaked
    positions(where: { shares_gt: "0" }) {
      agent {
        agentId
        sharePrice
      }
      shares
      cumulativeDeposits
      realizedPnL
    }
  }
}
```

### Daily protocol-level stats

```graphql
{
  dailyStats(first: 30, orderBy: date, orderDirection: desc) {
    date
    agentsActive
    totalTVL
    attestations
    feesCollected
    tokensBurned
  }
}
```

### Cumulative burn over time

```graphql
{
  protocolStats(id: "singleton") {
    totalTVL
    cumulativeBurnedTokens
    cumulativeBurnedUsd
    totalLocked
  }
}
```

### Recent attestations for one agent

```graphql
{
  agent(id: "42") {
    attestations(first: 50, orderBy: epoch, orderDirection: desc) {
      epoch
      pnlDelta
      feeOnGross
      timestamp
    }
  }
}
```

### Slashing events (cross-protocol)

```graphql
{
  slashEvents(first: 100, orderBy: timestamp, orderDirection: desc) {
    agent { agentId }
    amount
    reason
    timestamp
    txHash
  }
}
```

## Deployment

Once mainnet contracts deploy:

```bash
# 1. Replace zero addresses + startBlocks in subgraph.yaml
# 2. Auth with The Graph CLI
graph auth --product hosted-service <ACCESS_TOKEN>

# 3. Codegen + build
graph codegen
graph build

# 4. Deploy
graph deploy --product hosted-service alphagentic/protocol
```

Or self-host on a Graph node — see https://thegraph.com/docs/en/operating-graph-node/

## SDK integration

When the subgraph is live, the SDK reads from it via the `indexerUrl` config:

```ts
const protocol = new LITNUP({
  client,
  network: 'base',
  indexerUrl: 'https://api.thegraph.com/subgraphs/name/alphagentic/protocol',
});

// Fast list (uses indexer)
const top = await protocol.agents.list({ sortBy: 'sharpe', limit: 10 });
```

Without `indexerUrl`, the SDK falls back to on-chain enumeration (slower, fine for one-off lookups).

## Versioning

The subgraph schema follows the same semver as the SDK. Breaking schema changes require coordination with the dApp team and a deprecation window of at least 30 days.
