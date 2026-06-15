/**
 * Governance module — veAGENTIC locks + proposals.
 *
 * Reads VotingEscrow contract; writes via WalletClient. Proposals integration
 * uses Snapshot off-chain by default; on-chain Governor reads as fallback.
 */
import type { Address, Hex } from 'viem';
import type { LockParams, GovernanceLock } from './types.js';

export async function createLock(
  _client: unknown,
  _votingEscrow: Address,
  _params: LockParams,
): Promise<Hex> {
  throw new Error('Not yet implemented — wire VotingEscrow.createLock() ABI');
}

export async function increaseLockAmount(
  _client: unknown,
  _votingEscrow: Address,
  _amount: bigint,
): Promise<Hex> {
  throw new Error('Not yet implemented');
}

export async function extendLock(
  _client: unknown,
  _votingEscrow: Address,
  _newUnlockTime: number,
): Promise<Hex> {
  throw new Error('Not yet implemented');
}

export async function withdrawLock(
  _client: unknown,
  _votingEscrow: Address,
): Promise<Hex> {
  throw new Error('Not yet implemented');
}

export async function getLock(
  _client: unknown,
  _votingEscrow: Address,
  _user: Address,
): Promise<GovernanceLock | null> {
  return null;
}

export async function listProposals(
  _spaceId: string = 'litnup.eth',
): Promise<unknown[]> {
  // Snapshot GraphQL query
  return [];
}

/** Linear-decay voting weight: amount × (timeLeft / MAX_LOCK). */
export function computeVotingWeight(amount: bigint, unlockTime: number, now: number = Math.floor(Date.now() / 1000)): bigint {
  const MAX_LOCK = 4 * 365 * 24 * 3600; // 4 years
  if (now >= unlockTime) return 0n;
  const timeLeft = unlockTime - now;
  if (timeLeft >= MAX_LOCK) return amount;
  return (amount * BigInt(timeLeft)) / BigInt(MAX_LOCK);
}
