/**
 * LITNUP — top-level client.
 *
 * Wraps a viem PublicClient (read) or WalletClient (read + write) and
 * exposes namespaced submodules. Read paths are wired via real ABIs;
 * write paths require a WalletClient.
 */
import type { PublicClient, WalletClient, Address, Hex } from 'viem';

import {
  getAddresses,
  getChainId,
  type ContractAddresses,
  type Network,
} from './addresses.js';

import {
  alphaTokenAbi,
  agentRegistryAbi,
  stakingVaultAbi,
  performanceOracleAbi,
  votingEscrowAbi,
} from './abis.js';

import type {
  AgentId,
  AgentInfo,
  AgentStatus,
  AgentStrategy,
  ListAgentsOptions,
  StakerPosition,
  StakeParams,
  UnstakeInitParams,
  EnrollParams,
  LockParams,
  GovernanceLock,
} from './types.js';

export type Client = PublicClient | WalletClient;

export interface LITNUPConfig {
  client: Client;
  network: Network;
  /** Optional indexer endpoint (Subgraph or custom) for fast list/sort queries. */
  indexerUrl?: string;
}

/**
 * Top-level entry point. Construct once per app session.
 *
 * Read methods work with either PublicClient or WalletClient.
 * Write methods (stake, unstakeInit, enroll, etc.) require WalletClient and
 * throw if a PublicClient was provided.
 */
export class LITNUP {
  readonly client: Client;
  readonly network: Network;
  readonly addresses: ContractAddresses;
  readonly chainId: number;
  readonly indexerUrl?: string;

  constructor(config: LITNUPConfig) {
    this.client = config.client;
    this.network = config.network;
    this.addresses = getAddresses(config.network);
    this.chainId = getChainId(config.network);
    this.indexerUrl = config.indexerUrl;
  }

  // ============================================================
  // INTERNAL HELPERS
  // ============================================================

  private get publicClient(): PublicClient {
    return this.client as PublicClient;
  }

  private requireWallet(): WalletClient {
    if (!('writeContract' in this.client)) {
      throw new Error('This call requires a WalletClient. Construct LITNUP with createWalletClient().');
    }
    const wc = this.client as WalletClient;
    if (!wc.account) {
      throw new Error('WalletClient has no account; pass account: at construction time.');
    }
    return wc;
  }

  // ============================================================
  // PROTOCOL-LEVEL READS
  // ============================================================

  /**
   * Total $LIT staked across all agent vaults.
   * Indexer is preferred; fallback enumerates on-chain.
   */
  async getTotalTVL(): Promise<bigint> {
    if (this.indexerUrl) {
      try {
        const res = await fetch(`${this.indexerUrl}/totals`);
        if (res.ok) {
          const j = (await res.json()) as { totalTVL?: string };
          if (j.totalTVL) return BigInt(j.totalTVL);
        }
      } catch {
        // fall through to on-chain
      }
    }
    const nextId = (await this.publicClient.readContract({
      address: this.addresses.AgentRegistry,
      abi: agentRegistryAbi,
      functionName: 'nextAgentId',
    })) as bigint;
    let total = 0n;
    for (let i = 1n; i < nextId; i++) {
      const v = (await this.publicClient.readContract({
        address: this.addresses.StakingVault,
        abi: stakingVaultAbi,
        functionName: 'vaults',
        args: [i],
      })) as readonly [bigint, bigint, bigint, bigint];
      total += v[0];
    }
    return total;
  }

  /** Total $LIT burned (computed: MAX_SUPPLY - currentSupply). */
  async getTotalBurned(): Promise<bigint> {
    const max = (await this.publicClient.readContract({
      address: this.addresses.LitToken,
      abi: alphaTokenAbi,
      functionName: 'MAX_SUPPLY',
    })) as bigint;
    const current = (await this.publicClient.readContract({
      address: this.addresses.LitToken,
      abi: alphaTokenAbi,
      functionName: 'totalSupply',
    })) as bigint;
    return max - current;
  }

  // ============================================================
  // AGENTS
  // ============================================================
  agents = {
    list: async (opts: ListAgentsOptions = {}): Promise<AgentInfo[]> => {
      if (this.indexerUrl) {
        try {
          const params = new URLSearchParams();
          if (opts.sortBy) params.set('sortBy', opts.sortBy);
          if (opts.status && opts.status !== 'all') params.set('status', opts.status);
          if (opts.strategy && opts.strategy !== 'all') params.set('strategy', opts.strategy);
          if (opts.limit !== undefined) params.set('limit', String(opts.limit));
          if (opts.offset !== undefined) params.set('offset', String(opts.offset));
          const res = await fetch(`${this.indexerUrl}/agents?${params}`);
          if (res.ok) return (await res.json()) as AgentInfo[];
        } catch {
          // fall through to on-chain
        }
      }
      const nextId = (await this.publicClient.readContract({
        address: this.addresses.AgentRegistry,
        abi: agentRegistryAbi,
        functionName: 'nextAgentId',
      })) as bigint;
      const cap = Math.min(Number(nextId) - 1, 100);
      const out: AgentInfo[] = [];
      for (let i = 1; i <= cap; i++) {
        const info = await this.agents.get(BigInt(i));
        if (info) out.push(info);
      }
      return out;
    },

    get: async (agentId: AgentId): Promise<AgentInfo | null> => {
      const a = (await this.publicClient.readContract({
        address: this.addresses.AgentRegistry,
        abi: agentRegistryAbi,
        functionName: 'getAgent',
        args: [agentId],
      })) as {
        controller: Address;
        enrolledAt: bigint;
        unbondedAt: bigint;
        bond: bigint;
        status: number;
        metadataHash: Hex;
        protocolFeeBps: number;
      };
      if (a.controller === '0x0000000000000000000000000000000000000000') return null;

      const v = (await this.publicClient.readContract({
        address: this.addresses.StakingVault,
        abi: stakingVaultAbi,
        functionName: 'vaults',
        args: [agentId],
      })) as readonly [bigint, bigint, bigint, bigint];

      const sharePrice = (await this.publicClient.readContract({
        address: this.addresses.StakingVault,
        abi: stakingVaultAbi,
        functionName: 'sharePrice',
        args: [agentId],
      })) as bigint;

      const status: AgentStatus =
        a.status === 0 ? 'active' :
        a.status === 1 ? 'paused' :
        a.status === 2 ? 'slashed' : 'withdrawn';

      return {
        agentId,
        name: `Agent #${agentId}`,
        controller: a.controller,
        status,
        strategy: 'custom' as AgentStrategy,
        bond: a.bond,
        protocolFeeBps: a.protocolFeeBps,
        metadataHash: a.metadataHash,
        enrolledAt: Number(a.enrolledAt),
        totalAssets: v[0],
        totalShares: v[1],
        sharePrice,
        pnl30dPct: 0,
        sharpe30d: 0,
        maxDrawdownPct: 0,
        numStakers: 0,
      };
    },

    enroll: async (params: EnrollParams): Promise<Hex> => {
      const wc = this.requireWallet();
      return wc.writeContract({
        chain: wc.chain ?? null,
        account: wc.account!,
        address: this.addresses.AgentRegistry,
        abi: agentRegistryAbi,
        functionName: 'enroll',
        args: [params.controller, params.bond, params.metadataHash, params.protocolFeeBps],
      } as never);
    },

    isActive: async (agentId: AgentId): Promise<boolean> => {
      return (await this.publicClient.readContract({
        address: this.addresses.AgentRegistry,
        abi: agentRegistryAbi,
        functionName: 'isActive',
        args: [agentId],
      })) as boolean;
    },
  };

  // ============================================================
  // STAKING
  // ============================================================
  async stake(params: StakeParams): Promise<Hex> {
    const wc = this.requireWallet();
    return wc.writeContract({
      chain: wc.chain ?? null,
      account: wc.account!,
      address: this.addresses.StakingVault,
      abi: stakingVaultAbi,
      functionName: 'stake',
      args: [params.agentId, params.amount],
    } as never);
  }

  async unstakeInit(params: UnstakeInitParams): Promise<Hex> {
    const wc = this.requireWallet();
    return wc.writeContract({
      chain: wc.chain ?? null,
      account: wc.account!,
      address: this.addresses.StakingVault,
      abi: stakingVaultAbi,
      functionName: 'unstakeInit',
      args: [params.agentId, params.shares],
    } as never);
  }

  async unstakeComplete(agentId: AgentId): Promise<Hex> {
    const wc = this.requireWallet();
    return wc.writeContract({
      chain: wc.chain ?? null,
      account: wc.account!,
      address: this.addresses.StakingVault,
      abi: stakingVaultAbi,
      functionName: 'unstakeComplete',
      args: [agentId],
    } as never);
  }

  async getPosition(agentId: AgentId, staker: Address): Promise<StakerPosition | null> {
    const s = (await this.publicClient.readContract({
      address: this.addresses.StakingVault,
      abi: stakingVaultAbi,
      functionName: 'stakers',
      args: [agentId, staker],
    })) as readonly [bigint, bigint, bigint];
    const shares = s[0];
    const pendingShares = s[2];
    if (shares === 0n && pendingShares === 0n) return null;

    const sharePrice = (await this.publicClient.readContract({
      address: this.addresses.StakingVault,
      abi: stakingVaultAbi,
      functionName: 'sharePrice',
      args: [agentId],
    })) as bigint;

    return {
      agentId,
      staker,
      shares,
      pendingShares,
      unlockAt: Number(s[1]),
      estimatedAssets: (shares * sharePrice) / 10n ** 18n,
    };
  }

  async previewStake(agentId: AgentId, amount: bigint): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: this.addresses.StakingVault,
      abi: stakingVaultAbi,
      functionName: 'previewStake',
      args: [agentId, amount],
    })) as bigint;
  }

  async previewUnstake(agentId: AgentId, shares: bigint): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: this.addresses.StakingVault,
      abi: stakingVaultAbi,
      functionName: 'previewUnstake',
      args: [agentId, shares],
    })) as bigint;
  }

  // ============================================================
  // GOVERNANCE (veAGENTIC)
  // ============================================================
  governance = {
    lock: async (params: LockParams): Promise<Hex> => {
      const wc = this.requireWallet();
      return wc.writeContract({
        chain: wc.chain ?? null,
        account: wc.account!,
        address: this.addresses.VotingEscrow,
        abi: votingEscrowAbi,
        functionName: 'createLock',
        args: [params.amount, BigInt(params.unlockTime)],
      } as never);
    },

    increase: async (amount: bigint): Promise<Hex> => {
      const wc = this.requireWallet();
      return wc.writeContract({
        chain: wc.chain ?? null,
        account: wc.account!,
        address: this.addresses.VotingEscrow,
        abi: votingEscrowAbi,
        functionName: 'increaseAmount',
        args: [amount],
      } as never);
    },

    extend: async (newUnlockTime: number): Promise<Hex> => {
      const wc = this.requireWallet();
      return wc.writeContract({
        chain: wc.chain ?? null,
        account: wc.account!,
        address: this.addresses.VotingEscrow,
        abi: votingEscrowAbi,
        functionName: 'extendLock',
        args: [BigInt(newUnlockTime)],
      } as never);
    },

    withdraw: async (): Promise<Hex> => {
      const wc = this.requireWallet();
      return wc.writeContract({
        chain: wc.chain ?? null,
        account: wc.account!,
        address: this.addresses.VotingEscrow,
        abi: votingEscrowAbi,
        functionName: 'withdraw',
        args: [],
      } as never);
    },

    getLock: async (user: Address): Promise<GovernanceLock | null> => {
      const lock = (await this.publicClient.readContract({
        address: this.addresses.VotingEscrow,
        abi: votingEscrowAbi,
        functionName: 'lockInfo',
        args: [user],
      })) as readonly [bigint, bigint, bigint];
      if (lock[0] === 0n) return null;
      return {
        amount: lock[0],
        unlockTime: Number(lock[1]),
        votingWeight: lock[2],
        createdAt: 0,
      };
    },
  };

  // ============================================================
  // TOKEN
  // ============================================================
  token = {
    balanceOf: async (account: Address): Promise<bigint> => {
      return (await this.publicClient.readContract({
        address: this.addresses.LitToken,
        abi: alphaTokenAbi,
        functionName: 'balanceOf',
        args: [account],
      })) as bigint;
    },

    allowance: async (owner: Address, spender: Address): Promise<bigint> => {
      return (await this.publicClient.readContract({
        address: this.addresses.LitToken,
        abi: alphaTokenAbi,
        functionName: 'allowance',
        args: [owner, spender],
      })) as bigint;
    },

    approve: async (spender: Address, amount: bigint): Promise<Hex> => {
      const wc = this.requireWallet();
      return wc.writeContract({
        chain: wc.chain ?? null,
        account: wc.account!,
        address: this.addresses.LitToken,
        abi: alphaTokenAbi,
        functionName: 'approve',
        args: [spender, amount],
      } as never);
    },

    totalSupply: async (): Promise<bigint> => {
      return (await this.publicClient.readContract({
        address: this.addresses.LitToken,
        abi: alphaTokenAbi,
        functionName: 'totalSupply',
      })) as bigint;
    },

    delegates: async (user: Address): Promise<Address> => {
      return (await this.publicClient.readContract({
        address: this.addresses.LitToken,
        abi: alphaTokenAbi,
        functionName: 'delegates',
        args: [user],
      })) as Address;
    },

    delegate: async (delegatee: Address): Promise<Hex> => {
      const wc = this.requireWallet();
      return wc.writeContract({
        chain: wc.chain ?? null,
        account: wc.account!,
        address: this.addresses.LitToken,
        abi: alphaTokenAbi,
        functionName: 'delegate',
        args: [delegatee],
      } as never);
    },

    getVotes: async (account: Address): Promise<bigint> => {
      return (await this.publicClient.readContract({
        address: this.addresses.LitToken,
        abi: alphaTokenAbi,
        functionName: 'getVotes',
        args: [account],
      })) as bigint;
    },
  };

  // ============================================================
  // ORACLE (read-only — attestations come from off-chain runtime)
  // ============================================================
  oracle = {
    getSigners: async (): Promise<Address[]> => {
      const sigs = (await this.publicClient.readContract({
        address: this.addresses.PerformanceOracle,
        abi: performanceOracleAbi,
        functionName: 'getSigners',
      })) as readonly Address[];
      return [...sigs];
    },

    getThreshold: async (): Promise<number> => {
      const t = (await this.publicClient.readContract({
        address: this.addresses.PerformanceOracle,
        abi: performanceOracleAbi,
        functionName: 'threshold',
      })) as number;
      return Number(t);
    },

    isSigner: async (address: Address): Promise<boolean> => {
      return (await this.publicClient.readContract({
        address: this.addresses.PerformanceOracle,
        abi: performanceOracleAbi,
        functionName: 'isSigner',
        args: [address],
      })) as boolean;
    },

    isExecuted: async (agentId: AgentId, epoch: bigint): Promise<boolean> => {
      return (await this.publicClient.readContract({
        address: this.addresses.PerformanceOracle,
        abi: performanceOracleAbi,
        functionName: 'executedEpoch',
        args: [agentId, epoch],
      })) as boolean;
    },
  };
}
