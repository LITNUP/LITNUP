/** Shared types for the LITNUP SDK. */
import type { Address, Hex } from 'viem';

export type AgentId = bigint;

export type AgentStatus = 'active' | 'paused' | 'slashed' | 'withdrawn';

export type AgentStrategy =
  | 'momentum'
  | 'mean-reversion'
  | 'basis-trade'
  | 'vol-carry'
  | 'stat-arb'
  | 'funding-arb'
  | 'pairs-trade'
  | 'options-carry'
  | 'custom';

export interface AgentInfo {
  agentId: AgentId;
  name: string;
  controller: Address;
  status: AgentStatus;
  strategy: AgentStrategy;
  bond: bigint;            // current bond amount in $LITNUP wei
  protocolFeeBps: number;  // 0..10_000
  metadataHash: Hex;       // IPFS CID hash
  enrolledAt: number;      // unix seconds

  // Vault state (joined from StakingVault)
  totalAssets: bigint;
  totalShares: bigint;
  sharePrice: bigint;     // 1e18-scaled

  // Computed metrics (off-chain index)
  pnl30dPct: number;
  sharpe30d: number;
  maxDrawdownPct: number;
  numStakers: number;
}

export interface StakerPosition {
  agentId: AgentId;
  staker: Address;
  shares: bigint;
  pendingShares: bigint;     // shares queued for unstake
  unlockAt: number;          // unix seconds; 0 if no pending
  estimatedAssets: bigint;   // shares * sharePrice
}

export interface Attestation {
  agentId: bigint;
  pnlDelta: bigint;        // signed; positive = profit
  feeOnGross: bigint;      // unsigned
  epoch: bigint;
  deadline: bigint;        // unix seconds
}

export interface SignedAttestation {
  attestation: Attestation;
  signer: Address;
  signature: Hex;
  domain: {
    name: string;
    version: string;
    chainId: number;
    verifyingContract: Address;
  };
}

export interface GovernanceLock {
  amount: bigint;
  unlockTime: number;       // unix seconds
  votingWeight: bigint;     // current decayed weight
  createdAt: number;
}

export interface ListAgentsOptions {
  sortBy?: 'sharpe' | 'pnl' | 'tvl' | 'drawdown' | 'age';
  status?: AgentStatus | 'all';
  strategy?: AgentStrategy | 'all';
  limit?: number;
  offset?: number;
}

export interface StakeParams {
  agentId: AgentId;
  amount: bigint;
}

export interface UnstakeInitParams {
  agentId: AgentId;
  shares: bigint;
}

export interface EnrollParams {
  controller: Address;
  bond: bigint;
  metadataHash: Hex;
  protocolFeeBps: number; // 0..5000
}

export interface LockParams {
  amount: bigint;
  unlockTime: number; // unix seconds; max 4 yrs from now
}
