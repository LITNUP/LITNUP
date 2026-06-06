/**
 * EIP-712 attestation utilities.
 *
 * Mirrors the on-chain `PerformanceOracle.ATTESTATION_TYPEHASH` exactly.
 * Importantly: this MUST stay in sync with the Solidity contract. CI runs
 * a round-trip test from Python → Solidity to detect drift.
 */
import {
  hashTypedData,
  recoverTypedDataAddress,
  type Address,
  type Hex,
} from 'viem';

import type { Attestation, SignedAttestation } from './types.js';

const DOMAIN_NAME = 'LITNUPOracle';
const DOMAIN_VERSION = '1';

const TYPES = {
  Attestation: [
    { name: 'agentId',    type: 'uint256' },
    { name: 'pnlDelta',   type: 'int256' },
    { name: 'feeOnGross', type: 'uint256' },
    { name: 'epoch',      type: 'uint64' },
    { name: 'deadline',   type: 'uint64' },
  ],
} as const;

export interface BuildTypedDataParams {
  attestation: Attestation;
  chainId: number;
  oracleAddress: Address;
}

/** Construct the EIP-712 typed data for an attestation. */
export function buildTypedData(params: BuildTypedDataParams) {
  return {
    domain: {
      name: DOMAIN_NAME,
      version: DOMAIN_VERSION,
      chainId: params.chainId,
      verifyingContract: params.oracleAddress,
    },
    types: TYPES,
    primaryType: 'Attestation' as const,
    message: {
      agentId: params.attestation.agentId,
      pnlDelta: params.attestation.pnlDelta,
      feeOnGross: params.attestation.feeOnGross,
      epoch: params.attestation.epoch,
      deadline: params.attestation.deadline,
    },
  };
}

/** Compute the EIP-712 digest (hash) for an attestation. */
export function digest(params: BuildTypedDataParams): Hex {
  return hashTypedData(buildTypedData(params));
}

export interface VerifyAttestationParams {
  attestation: Attestation;
  signature: Hex;
  expectedSigner: Address;
  chainId: number;
  oracleAddress: Address;
}

/**
 * Verify an attestation signature.
 *
 * Returns true iff the signature recovers to the expected signer for the given
 * (chainId, oracleAddress) pair. Useful for off-chain UI verification before
 * surfacing PnL data to users.
 */
export async function verifyAttestation(params: VerifyAttestationParams): Promise<boolean> {
  const recovered = await recoverTypedDataAddress({
    ...buildTypedData(params),
    signature: params.signature,
  });
  return recovered.toLowerCase() === params.expectedSigner.toLowerCase();
}

/**
 * Build a signed-attestation object from raw inputs (for logging / submission to the
 * on-chain `applyAttestation()`).
 */
export function packSigned(
  attestation: Attestation,
  signer: Address,
  signature: Hex,
  chainId: number,
  oracleAddress: Address,
): SignedAttestation {
  return {
    attestation,
    signer,
    signature,
    domain: {
      name: DOMAIN_NAME,
      version: DOMAIN_VERSION,
      chainId,
      verifyingContract: oracleAddress,
    },
  };
}
