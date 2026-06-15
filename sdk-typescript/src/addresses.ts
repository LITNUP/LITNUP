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
  litnupToken: '0xD37458934255e9F4858A3E8C104b016716c558d1',
  agentRegistry: '0x4D4dE869e9a155A43CD80C1b8a71088bfC337176',
  stakingVault: '0xa08Dd6479cfDcC06a2E6777c627EA9483847238D',
  performanceOracle: '0xeD4ba8D90Af146FbfcFAbe60b320940a980C37fE',
  buybackBurn: '0x64aca73C3D7E11f3B6455dae513FB9Ad0A047f03',
  votingEscrow: '0x560da62460b5e8F9B748cFA9c4D3E8E8BaB591F5',
  merkleAirdrop: ZERO,
  vesting: '0xc907F9038163F33BA8D992769343F10A068ae331',
  insuranceFund: '0xFe740A3F89175A287c7f2c474e227aE8591dFc05',
  timelock: '0x6E859b5001f61a520962918d65dF64ca7A3eE727',
  delegateRegistry: '0xbFDC1279A6E165E3BaceB604DF2AA7B08af1e83A',
  emissionScheduler: '0x74f7F6F0B4376D3992048F56312347363C2Ae942',
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
