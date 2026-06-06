/**
 * Staking module — stake / unstake / position queries.
 *
 * Skeleton: type signatures match the eventual API. Concrete viem write calls
 * filled in once contract ABIs are imported.
 */
import type { Address, Hex } from 'viem';
import type { AgentId, StakeParams, UnstakeInitParams, StakerPosition } from './types.js';

export async function stake(
  _client: unknown,
  _stakingVault: Address,
  _params: StakeParams,
): Promise<Hex> {
  throw new Error('Not yet implemented — wire StakingVault.stake() ABI');
}

export async function unstakeInit(
  _client: unknown,
  _stakingVault: Address,
  _params: UnstakeInitParams,
): Promise<Hex> {
  throw new Error('Not yet implemented');
}

export async function unstakeComplete(
  _client: unknown,
  _stakingVault: Address,
  _agentId: AgentId,
): Promise<Hex> {
  throw new Error('Not yet implemented');
}

export async function getPosition(
  _client: unknown,
  _stakingVault: Address,
  _agentId: AgentId,
  _staker: Address,
): Promise<StakerPosition | null> {
  return null;
}

/**
 * Preview the shares received for a given stake amount, given current vault state.
 * Pure read; no transaction.
 */
export async function previewStake(
  _client: unknown,
  _stakingVault: Address,
  _agentId: AgentId,
  _amount: bigint,
): Promise<bigint> {
  return 0n;
}

/**
 * Preview the assets returned for a given share amount.
 */
export async function previewUnstake(
  _client: unknown,
  _stakingVault: Address,
  _agentId: AgentId,
  _shares: bigint,
): Promise<bigint> {
  return 0n;
}
