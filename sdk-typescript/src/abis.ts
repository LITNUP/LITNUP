/**
 * Hand-written subset ABIs for the contracts the SDK reads/writes.
 *
 * In production we'll auto-generate from `forge build` + `wagmi cli`. This subset
 * is enough for the read-side of the SDK to work today against Base Sepolia
 * deployments. Functions not needed by the SDK are omitted for type-narrowness.
 *
 * NOTE: Solidity types are encoded with viem's `abitype` conventions.
 */

export const alphaTokenAbi = [
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'totalSupply',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'allowance',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'value', type: 'uint256' },
    ],
    outputs: [{ type: 'bool' }],
  },
  {
    type: 'function',
    name: 'delegates',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'address' }],
  },
  {
    type: 'function',
    name: 'delegate',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'delegatee', type: 'address' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'getVotes',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'MAX_SUPPLY',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
] as const;

export const agentRegistryAbi = [
  {
    type: 'function',
    name: 'getAgent',
    stateMutability: 'view',
    inputs: [{ name: 'agentId', type: 'uint256' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'controller', type: 'address' },
          { name: 'enrolledAt', type: 'uint64' },
          { name: 'unbondedAt', type: 'uint64' },
          { name: 'bond', type: 'uint128' },
          { name: 'status', type: 'uint8' },
          { name: 'metadataHash', type: 'bytes32' },
          { name: 'protocolFeeBps', type: 'uint16' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'isActive',
    stateMutability: 'view',
    inputs: [{ name: 'agentId', type: 'uint256' }],
    outputs: [{ type: 'bool' }],
  },
  {
    type: 'function',
    name: 'nextAgentId',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'enroll',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'controller', type: 'address' },
      { name: 'bondAmount', type: 'uint128' },
      { name: 'metadataHash', type: 'bytes32' },
      { name: 'protocolFeeBps', type: 'uint16' },
    ],
    outputs: [{ name: 'agentId', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'topUpBond',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'amount', type: 'uint128' },
    ],
    outputs: [],
  },
  {
    type: 'event',
    name: 'AgentEnrolled',
    inputs: [
      { name: 'agentId', type: 'uint256', indexed: true },
      { name: 'controller', type: 'address', indexed: true },
      { name: 'bond', type: 'uint128', indexed: false },
      { name: 'metadataHash', type: 'bytes32', indexed: false },
      { name: 'protocolFeeBps', type: 'uint16', indexed: false },
    ],
  },
] as const;

export const stakingVaultAbi = [
  {
    type: 'function',
    name: 'vaults',
    stateMutability: 'view',
    inputs: [{ name: 'agentId', type: 'uint256' }],
    outputs: [
      { name: 'totalAssets', type: 'uint128' },
      { name: 'totalShares', type: 'uint128' },
      { name: 'lastAttestation', type: 'uint64' },
      { name: 'cooldown', type: 'uint64' },
    ],
  },
  {
    type: 'function',
    name: 'stakers',
    stateMutability: 'view',
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'staker', type: 'address' },
    ],
    outputs: [
      { name: 'shares', type: 'uint128' },
      { name: 'unlockAt', type: 'uint64' },
      { name: 'pendingShares', type: 'uint128' },
    ],
  },
  {
    type: 'function',
    name: 'sharePrice',
    stateMutability: 'view',
    inputs: [{ name: 'agentId', type: 'uint256' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'previewStake',
    stateMutability: 'view',
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'amount', type: 'uint128' },
    ],
    outputs: [{ type: 'uint128' }],
  },
  {
    type: 'function',
    name: 'previewUnstake',
    stateMutability: 'view',
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'shares', type: 'uint128' },
    ],
    outputs: [{ type: 'uint128' }],
  },
  {
    type: 'function',
    name: 'stake',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'amount', type: 'uint128' },
    ],
    outputs: [{ name: 'shares', type: 'uint128' }],
  },
  {
    type: 'function',
    name: 'unstakeInit',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'shares', type: 'uint128' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'unstakeComplete',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'agentId', type: 'uint256' }],
    outputs: [{ name: 'amount', type: 'uint128' }],
  },
  {
    type: 'function',
    name: 'perVaultCap',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint128' }],
  },
] as const;

export const performanceOracleAbi = [
  {
    type: 'function',
    name: 'ATTESTATION_TYPEHASH',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'bytes32' }],
  },
  {
    type: 'function',
    name: 'isSigner',
    stateMutability: 'view',
    inputs: [{ name: 'signer', type: 'address' }],
    outputs: [{ type: 'bool' }],
  },
  {
    type: 'function',
    name: 'threshold',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint8' }],
  },
  {
    type: 'function',
    name: 'getSigners',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'address[]' }],
  },
  {
    type: 'function',
    name: 'executedEpoch',
    stateMutability: 'view',
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'epoch', type: 'uint64' },
    ],
    outputs: [{ type: 'bool' }],
  },
  {
    type: 'function',
    name: 'applyAttestation',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'agentId', type: 'uint256' },
      { name: 'pnlDelta', type: 'int256' },
      { name: 'feeOnGross', type: 'uint256' },
      { name: 'toBuybackBps', type: 'uint16' },
      { name: 'epoch', type: 'uint64' },
      { name: 'deadline', type: 'uint64' },
      { name: 'signatures', type: 'bytes[]' },
    ],
    outputs: [],
  },
  {
    type: 'event',
    name: 'AttestationApplied',
    inputs: [
      { name: 'agentId', type: 'uint256', indexed: true },
      { name: 'epoch', type: 'uint64', indexed: true },
      { name: 'pnlDelta', type: 'int256', indexed: false },
      { name: 'feeOnGross', type: 'uint256', indexed: false },
    ],
  },
] as const;

export const votingEscrowAbi = [
  {
    type: 'function',
    name: 'lockInfo',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [
      { name: 'amount', type: 'uint128' },
      { name: 'unlockTime', type: 'uint64' },
      { name: 'currentWeight', type: 'uint256' },
    ],
  },
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'user', type: 'address' }],
    outputs: [{ type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'totalLocked',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint128' }],
  },
  {
    type: 'function',
    name: 'createLock',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'amount', type: 'uint128' },
      { name: 'unlockTime', type: 'uint64' },
    ],
    outputs: [],
  },
  {
    type: 'function',
    name: 'increaseAmount',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint128' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'extendLock',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'newUnlockTime', type: 'uint64' }],
    outputs: [],
  },
  {
    type: 'function',
    name: 'withdraw',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    type: 'function',
    name: 'MAX_LOCK',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint256' }],
  },
] as const;

export const buybackBurnAbi = [
  {
    type: 'function',
    name: 'burnDirect',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    type: 'function',
    name: 'lastSwapAt',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'uint64' }],
  },
  {
    type: 'event',
    name: 'SwapAndBurn',
    inputs: [
      { name: 'token', type: 'address', indexed: true },
      { name: 'inAmount', type: 'uint256', indexed: false },
      { name: 'burned', type: 'uint256', indexed: false },
      { name: 'bounty', type: 'uint256', indexed: false },
    ],
  },
] as const;
