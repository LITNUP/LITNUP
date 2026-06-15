/**
 * @litnup/sdk — top-level entry.
 *
 * Status: alpha. API stable enough to build on; expect refinements through mainnet (Q4 2026).
 */

export { LITNUP } from './client.js';
export type { LITNUPConfig, Network } from './client.js';

export { addresses, getAddresses } from './addresses.js';

export type {
  AgentId,
  AgentInfo,
  AgentStatus,
  AgentStrategy,
  StakerPosition,
  Attestation,
  GovernanceLock,
} from './types.js';

// Sub-module re-exports
export * as attestation from './attestation.js';
export * as agents from './agents.js';
export * as staking from './staking.js';
export * as governance from './governance.js';
export * as token from './token.js';
