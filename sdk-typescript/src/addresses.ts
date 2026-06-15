/**
 * Deployed contract addresses per network.
 *
 * NOTE: Mainnet addresses are placeholders (zero) until Q4 2026 deployment.
 * Testnet addresses will be updated as deploys happen.
 */
import type { Address } from 'viem';

export type Network = 'base' | 'base-sepolia';

export interface ContractAddresses {
  litnupToken: Address;
  agentRegistry: Address;
  stakingVault: Address;
  performanceOracle: Address;
  buybackBurn: Address;
  votingEscrow: Address;
  merkleAirdrop: Address;
  vesting: Address;
  insuranceFund: Address;
  timelock: Address;
  delegateRegistry: Address;
  emissionScheduler: Address;
}

const ZERO = '0x0000000000000000000000000000000000000000' as const;

const BASE_SEPOLIA: ContractAddresses = {
  litnupToken: ZERO, // TODO: fill in after first deploy
  agentRegistry: ZERO,
  stakingVault: ZERO,
  performanceOracle: ZERO,
  buybackBurn: ZERO,
  votingEscrow: ZERO,
  merkleAirdrop: ZERO,
  vesting: ZERO,
  insuranceFund: ZERO,
  timelock: ZERO,
  delegateRegistry: ZERO,
  emissionScheduler: ZERO,
};

const BASE_MAINNET: ContractAddresses = {
  litnupToken: ZERO, // mainnet pending
  agentRegistry: ZERO,
  stakingVault: ZERO,
  performanceOracle: ZERO,
  buybackBurn: ZERO,
  votingEscrow: ZERO,
  merkleAirdrop: ZERO,
  vesting: ZERO,
  insuranceFund: ZERO,
  timelock: ZERO,
  delegateRegistry: ZERO,
  emissionScheduler: ZERO,
};

export const addresses: Record<Network, ContractAddresses> = {
  'base': BASE_MAINNET,
  'base-sepolia': BASE_SEPOLIA,
};

export function getAddresses(network: Network): ContractAddresses {
  const a = addresses[network];
  if (!a) throw new Error(`Unknown network: ${network}`);
  return a;
}

export function getChainId(network: Network): number {
  switch (network) {
    case 'base': return 8453;
    case 'base-sepolia': return 84532;
    default:
      throw new Error(`Unknown network: ${network}`);
  }
}
