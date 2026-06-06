/**
 * @alphagentic/sdk/react — React + wagmi hooks.
 *
 * Thin convenience layer over wagmi's useReadContract / useWriteContract that
 * pre-binds the LITNUP ABIs and per-network addresses. Callers get
 * type-safe hooks like `useAgentInfo(agentId)` or `useStakerPosition(agentId)`
 * without managing ABI imports themselves.
 *
 * Peer dependencies (NOT installed by the SDK; consumer adds them):
 *   - react ^18.0.0
 *   - wagmi ^2.10.0
 *   - viem  ^2.21.0
 *   - @tanstack/react-query ^5.0.0
 *
 * Usage:
 *   import { useAgentInfo, useStakerPosition } from '@alphagentic/sdk/react';
 *
 *   function AgentCard({ agentId }: { agentId: bigint }) {
 *     const { data: info, isLoading } = useAgentInfo(agentId);
 *     if (isLoading) return <Skeleton />;
 *     return <div>Bond: {info.bond.toString()}</div>;
 *   }
 *
 * IMPORTANT: This file uses `// @ts-ignore` on the wagmi imports so the SDK
 * itself can build without `wagmi` installed. The hooks only fire if the
 * consumer's project provides wagmi. We do NOT add wagmi as a peerDependency
 * to keep the SDK installable in non-React environments.
 */

import { type Address } from 'viem';

// @ts-ignore — wagmi is an optional peer
import { useReadContract, useWriteContract, useAccount, useChainId } from 'wagmi';

import {
  alphaTokenAbi,
  agentRegistryAbi,
  stakingVaultAbi,
  performanceOracleAbi,
  votingEscrowAbi,
  buybackBurnAbi,
} from './abis.js';
import { getAddresses } from './addresses.js';
import type { Network } from './client.js';

// =============================================================================
// Helpers
// =============================================================================

/** Resolve protocol addresses from a wagmi chain id (84532 = Base Sepolia, 8453 = Base). */
function networkFromChainId(chainId: number): Network {
  if (chainId === 8453) return 'base';
  if (chainId === 84532) return 'base-sepolia';
  return 'base-sepolia'; // safe default for testing
}

function useAddresses() {
  // @ts-ignore wagmi optional
  const chainId = useChainId();
  const network = networkFromChainId(chainId ?? 84532);
  return { network, ...getAddresses(network) };
}

// =============================================================================
// Token hooks
// =============================================================================

/** Read $LITNUP balance for the connected account (or a specific account). */
export function useAlphaBalance(account?: Address) {
  const { alphaToken } = useAddresses();
  // @ts-ignore wagmi
  const { address } = useAccount();
  const target = account ?? address;
  return useReadContract({
    abi: alphaTokenAbi,
    address: alphaToken,
    functionName: 'balanceOf',
    args: target ? [target] : undefined,
    query: { enabled: !!target },
  });
}

export function useAlphaTotalSupply() {
  const { alphaToken } = useAddresses();
  return useReadContract({
    abi: alphaTokenAbi,
    address: alphaToken,
    functionName: 'totalSupply',
  });
}

export function useAlphaAllowance(owner?: Address, spender?: Address) {
  const { alphaToken } = useAddresses();
  // @ts-ignore wagmi
  const { address } = useAccount();
  const o = owner ?? address;
  return useReadContract({
    abi: alphaTokenAbi,
    address: alphaToken,
    functionName: 'allowance',
    args: o && spender ? [o, spender] : undefined,
    query: { enabled: !!(o && spender) },
  });
}

export function useApprove() {
  const { alphaToken } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const approve = (spender: Address, value: bigint) =>
    writeContract({
      abi: alphaTokenAbi,
      address: alphaToken,
      functionName: 'approve',
      args: [spender, value],
    });
  return { approve, ...rest };
}

export function useDelegates(account?: Address) {
  const { alphaToken } = useAddresses();
  // @ts-ignore wagmi
  const { address } = useAccount();
  const target = account ?? address;
  return useReadContract({
    abi: alphaTokenAbi,
    address: alphaToken,
    functionName: 'delegates',
    args: target ? [target] : undefined,
    query: { enabled: !!target },
  });
}

export function useDelegate() {
  const { alphaToken } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const delegate = (delegatee: Address) =>
    writeContract({
      abi: alphaTokenAbi,
      address: alphaToken,
      functionName: 'delegate',
      args: [delegatee],
    });
  return { delegate, ...rest };
}

// =============================================================================
// Agent hooks
// =============================================================================

export function useAgentInfo(agentId: bigint | number) {
  const { agentRegistry } = useAddresses();
  return useReadContract({
    abi: agentRegistryAbi,
    address: agentRegistry,
    functionName: 'getAgent',
    args: [BigInt(agentId)],
  });
}

export function useAgentIsActive(agentId: bigint | number) {
  const { agentRegistry } = useAddresses();
  return useReadContract({
    abi: agentRegistryAbi,
    address: agentRegistry,
    functionName: 'isActive',
    args: [BigInt(agentId)],
  });
}

export function useNextAgentId() {
  const { agentRegistry } = useAddresses();
  return useReadContract({
    abi: agentRegistryAbi,
    address: agentRegistry,
    functionName: 'nextAgentId',
  });
}

// =============================================================================
// Staking hooks
// =============================================================================

export function useVault(agentId: bigint | number) {
  const { stakingVault } = useAddresses();
  return useReadContract({
    abi: stakingVaultAbi,
    address: stakingVault,
    functionName: 'vaults',
    args: [BigInt(agentId)],
  });
}

export function useSharePrice(agentId: bigint | number) {
  const { stakingVault } = useAddresses();
  return useReadContract({
    abi: stakingVaultAbi,
    address: stakingVault,
    functionName: 'sharePrice',
    args: [BigInt(agentId)],
  });
}

export function useStakerPosition(agentId: bigint | number, account?: Address) {
  const { stakingVault } = useAddresses();
  // @ts-ignore wagmi
  const { address } = useAccount();
  const target = account ?? address;
  return useReadContract({
    abi: stakingVaultAbi,
    address: stakingVault,
    functionName: 'stakers',
    args: target ? [BigInt(agentId), target] : undefined,
    query: { enabled: !!target },
  });
}

export function usePreviewStake(agentId: bigint | number, amount: bigint) {
  const { stakingVault } = useAddresses();
  return useReadContract({
    abi: stakingVaultAbi,
    address: stakingVault,
    functionName: 'previewStake',
    args: [BigInt(agentId), amount],
    query: { enabled: amount > 0n },
  });
}

export function usePreviewUnstake(agentId: bigint | number, shares: bigint) {
  const { stakingVault } = useAddresses();
  return useReadContract({
    abi: stakingVaultAbi,
    address: stakingVault,
    functionName: 'previewUnstake',
    args: [BigInt(agentId), shares],
    query: { enabled: shares > 0n },
  });
}

export function useStake() {
  const { stakingVault } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const stake = (agentId: bigint | number, amount: bigint) =>
    writeContract({
      abi: stakingVaultAbi,
      address: stakingVault,
      functionName: 'stake',
      args: [BigInt(agentId), amount],
    });
  return { stake, ...rest };
}

export function useUnstakeInit() {
  const { stakingVault } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const unstakeInit = (agentId: bigint | number, shares: bigint) =>
    writeContract({
      abi: stakingVaultAbi,
      address: stakingVault,
      functionName: 'unstakeInit',
      args: [BigInt(agentId), shares],
    });
  return { unstakeInit, ...rest };
}

export function useUnstakeComplete() {
  const { stakingVault } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const unstakeComplete = (agentId: bigint | number) =>
    writeContract({
      abi: stakingVaultAbi,
      address: stakingVault,
      functionName: 'unstakeComplete',
      args: [BigInt(agentId)],
    });
  return { unstakeComplete, ...rest };
}

// =============================================================================
// Governance hooks
// =============================================================================

export function useLockInfo(account?: Address) {
  const { votingEscrow } = useAddresses();
  // @ts-ignore wagmi
  const { address } = useAccount();
  const target = account ?? address;
  return useReadContract({
    abi: votingEscrowAbi,
    address: votingEscrow,
    functionName: 'lockInfo',
    args: target ? [target] : undefined,
    query: { enabled: !!target },
  });
}

export function useVotingWeight(account?: Address) {
  const { votingEscrow } = useAddresses();
  // @ts-ignore wagmi
  const { address } = useAccount();
  const target = account ?? address;
  return useReadContract({
    abi: votingEscrowAbi,
    address: votingEscrow,
    functionName: 'balanceOf',
    args: target ? [target] : undefined,
    query: { enabled: !!target },
  });
}

export function useTotalLocked() {
  const { votingEscrow } = useAddresses();
  return useReadContract({
    abi: votingEscrowAbi,
    address: votingEscrow,
    functionName: 'totalLocked',
  });
}

export function useCreateLock() {
  const { votingEscrow } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const createLock = (amount: bigint, unlockTime: bigint | number) =>
    writeContract({
      abi: votingEscrowAbi,
      address: votingEscrow,
      functionName: 'createLock',
      args: [amount, BigInt(unlockTime)],
    });
  return { createLock, ...rest };
}

export function useIncreaseAmount() {
  const { votingEscrow } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const increaseAmount = (amount: bigint) =>
    writeContract({
      abi: votingEscrowAbi,
      address: votingEscrow,
      functionName: 'increaseAmount',
      args: [amount],
    });
  return { increaseAmount, ...rest };
}

export function useExtendLock() {
  const { votingEscrow } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const extendLock = (newUnlockTime: bigint | number) =>
    writeContract({
      abi: votingEscrowAbi,
      address: votingEscrow,
      functionName: 'extendLock',
      args: [BigInt(newUnlockTime)],
    });
  return { extendLock, ...rest };
}

export function useWithdraw() {
  const { votingEscrow } = useAddresses();
  // @ts-ignore wagmi
  const { writeContract, ...rest } = useWriteContract();
  const withdraw = () =>
    writeContract({
      abi: votingEscrowAbi,
      address: votingEscrow,
      functionName: 'withdraw',
      args: [],
    });
  return { withdraw, ...rest };
}

// =============================================================================
// Oracle / Buyback hooks
// =============================================================================

export function useOracleSigners() {
  const { performanceOracle } = useAddresses();
  return useReadContract({
    abi: performanceOracleAbi,
    address: performanceOracle,
    functionName: 'getSigners',
  });
}

export function useOracleThreshold() {
  const { performanceOracle } = useAddresses();
  return useReadContract({
    abi: performanceOracleAbi,
    address: performanceOracle,
    functionName: 'threshold',
  });
}

export function useEpochExecuted(agentId: bigint | number, epoch: bigint | number) {
  const { performanceOracle } = useAddresses();
  return useReadContract({
    abi: performanceOracleAbi,
    address: performanceOracle,
    functionName: 'executedEpoch',
    args: [BigInt(agentId), BigInt(epoch)],
  });
}

export function useLastBuybackAt() {
  const { buybackBurn } = useAddresses();
  return useReadContract({
    abi: buybackBurnAbi,
    address: buybackBurn,
    functionName: 'lastSwapAt',
  });
}

// =============================================================================
// Aggregations / convenience hooks
// =============================================================================

/** Combine vault + staker position into a "your position" view for an agent. */
export function useMyPosition(agentId: bigint | number) {
  const vault = useVault(agentId);
  const position = useStakerPosition(agentId);
  const sharePrice = useSharePrice(agentId);

  const isLoading = vault.isLoading || position.isLoading || sharePrice.isLoading;
  const isError = vault.isError || position.isError || sharePrice.isError;

  let computedAssets: bigint | undefined;
  if (
    position.data && sharePrice.data && Array.isArray(position.data)
  ) {
    const shares = position.data[0] as bigint;
    computedAssets = (shares * (sharePrice.data as bigint)) / 10n ** 18n;
  }

  return {
    isLoading,
    isError,
    vault: vault.data,
    position: position.data,
    sharePrice: sharePrice.data,
    estimatedAssetValue: computedAssets,
  };
}
