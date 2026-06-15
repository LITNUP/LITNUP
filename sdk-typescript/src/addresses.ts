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

// Deployed to Base Sepolia (chainId 84532) on 2026-06-15. See contracts/deployments/84532.json.
// MerkleAirdrop is deployed per airdrop season (not in the core deploy) — left as ZERO.
const BASE_SEPOLIA: ContractAddresses = {
  litnupToken: '0x8027bb077D668407D6c0bb33Ba343c2dC44661d4',
  agentRegistry: '0xDdd34BdcCbC28a137f514b949274A8fDdBF20dE2',
  stakingVault: '0xdad52a9c40240269943b7ED451a4b02eB595b225',
  performanceOracle: '0x1a8318dd3315C8C259177cd477940F33799D0272',
  buybackBurn: '0x4B2d6604efdd707CaF96AbA2C65Ee726dAC136D4',
  votingEscrow: '0x8347fAa4c62637a00c96a5F5554Fb27c412D210a',
  merkleAirdrop: ZERO,
  vesting: '0x2154fDB056475c0e2169fEE7E31D85Bc32990F0f',
  insuranceFund: '0xa3a96128DB5578c4AC474e8D3490FBd13e92f420',
  timelock: '0xdD0c734Eb90B369BA7fcbFBb45ecb9859c8251aC',
  delegateRegistry: '0xB0961EE07380019Ea09D2f7FB0e8e38143138955',
  emissionScheduler: '0xb85A9D387227A9138ddfE594e8deAC6f8A50aD99',
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
