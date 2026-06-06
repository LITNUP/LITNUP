/**
 * Deployed contract addresses per network.
 *
 * NOTE: Mainnet addresses are placeholders (zero) until Q4 2026 deployment.
 * Testnet addresses will be updated as deploys happen.
 */
import type { Address } from 'viem';

export type Network = 'base' | 'base-sepolia';

export interface ContractAddresses {
  LitToken: Address;
  AgentRegistry: Address;
  StakingVault: Address;
  PerformanceOracle: Address;
  BuybackBurn: Address;
  VotingEscrow: Address;
  MerkleAirdrop: Address;
  Vesting: Address;
  InsuranceFund: Address;
  Timelock: Address;
  DelegateRegistry: Address;
  EmissionScheduler: Address;
}

const ZERO = '0x0000000000000000000000000000000000000000' as const;

const BASE_SEPOLIA: ContractAddresses = {
  LitToken: ZERO, // TODO: fill in after first deploy
  AgentRegistry: ZERO,
  StakingVault: ZERO,
  PerformanceOracle: ZERO,
  BuybackBurn: ZERO,
  VotingEscrow: ZERO,
  MerkleAirdrop: ZERO,
  Vesting: ZERO,
  InsuranceFund: ZERO,
  Timelock: ZERO,
  DelegateRegistry: ZERO,
  EmissionScheduler: ZERO,
};

const BASE_MAINNET: ContractAddresses = {
  LitToken: ZERO, // mainnet pending
  AgentRegistry: ZERO,
  StakingVault: ZERO,
  PerformanceOracle: ZERO,
  BuybackBurn: ZERO,
  VotingEscrow: ZERO,
  MerkleAirdrop: ZERO,
  Vesting: ZERO,
  InsuranceFund: ZERO,
  Timelock: ZERO,
  DelegateRegistry: ZERO,
  EmissionScheduler: ZERO,
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
