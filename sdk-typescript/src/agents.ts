/**
 * Agent registry / vault read helpers.
 *
 * In production this module reads from an indexer (Subgraph or custom) for
 * fast list/sort/filter, with on-chain fallback for individual lookups.
 * Skeleton ships type-correct stubs; concrete impl wires after first deploy.
 */
import type { Address } from 'viem';
import type { AgentId, AgentInfo, ListAgentsOptions } from './types.js';

export type { AgentInfo, ListAgentsOptions };

/** Read a single agent's full state. */
export async function getAgent(
  _client: unknown,
  _addresses: { AgentRegistry: Address; StakingVault: Address },
  _agentId: AgentId,
): Promise<AgentInfo | null> {
  // TODO: wire AgentRegistry.getAgent() + StakingVault.vaults(agentId) reads
  return null;
}

/** List agents with sort + filter. Uses indexer if provided. */
export async function listAgents(
  _client: unknown,
  _addresses: unknown,
  _opts: ListAgentsOptions = {},
  _indexerUrl?: string,
): Promise<AgentInfo[]> {
  // TODO: indexer fallback to on-chain enumerate
  return [];
}

/**
 * Compute the protocol-level aggregate stats (TVL, agents, fees).
 * Uses the indexer if configured for performance.
 */
export async function getAggregateStats(
  _client: unknown,
  _addresses: unknown,
  _indexerUrl?: string,
): Promise<{
  totalTVL: bigint;
  totalAgents: number;
  activeAgents: number;
  totalBurned: bigint;
  totalFees: bigint;
}> {
  return {
    totalTVL: 0n,
    totalAgents: 0,
    activeAgents: 0,
    totalBurned: 0n,
    totalFees: 0n,
  };
}
