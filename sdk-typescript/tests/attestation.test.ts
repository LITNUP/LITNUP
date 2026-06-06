/** Vitest tests for the attestation utilities. */
import { describe, it, expect } from 'vitest';
import { privateKeyToAccount } from 'viem/accounts';
import { signTypedData } from 'viem/actions';
import { createWalletClient, http } from 'viem';
import { baseSepolia } from 'viem/chains';

import {
  buildTypedData,
  digest,
  verifyAttestation,
  packSigned,
} from '../src/attestation.js';
import type { Attestation } from '../src/types.js';

const TEST_KEY = '0x1111111111111111111111111111111111111111111111111111111111111111';
const ORACLE_ADDR = '0xababababababababababababababababababab' as const;

const sampleAttestation: Attestation = {
  agentId: 42n,
  pnlDelta: 250n * 10n ** 18n,
  feeOnGross: 25n * 10n ** 18n,
  epoch: 7n,
  deadline: 2_000_000_000n,
};

describe('attestation/buildTypedData', () => {
  it('produces the canonical EIP-712 structure', () => {
    const td = buildTypedData({
      attestation: sampleAttestation,
      chainId: 84532,
      oracleAddress: ORACLE_ADDR as `0x${string}`,
    });
    expect(td.primaryType).toBe('Attestation');
    expect(td.domain.name).toBe('LITNUPOracle');
    expect(td.domain.version).toBe('1');
    expect(td.domain.chainId).toBe(84532);
    expect(td.message.agentId).toBe(42n);
  });

  it('digest is deterministic', () => {
    const d1 = digest({
      attestation: sampleAttestation,
      chainId: 84532,
      oracleAddress: ORACLE_ADDR as `0x${string}`,
    });
    const d2 = digest({
      attestation: sampleAttestation,
      chainId: 84532,
      oracleAddress: ORACLE_ADDR as `0x${string}`,
    });
    expect(d1).toBe(d2);
  });

  it('different chainId produces different digest', () => {
    const dA = digest({
      attestation: sampleAttestation,
      chainId: 1,
      oracleAddress: ORACLE_ADDR as `0x${string}`,
    });
    const dB = digest({
      attestation: sampleAttestation,
      chainId: 84532,
      oracleAddress: ORACLE_ADDR as `0x${string}`,
    });
    expect(dA).not.toBe(dB);
  });
});

describe('attestation/verifyAttestation', () => {
  it('round-trips signing + verification', async () => {
    const account = privateKeyToAccount(TEST_KEY as `0x${string}`);
    const client = createWalletClient({
      account,
      chain: baseSepolia,
      transport: http(),
    });
    const td = buildTypedData({
      attestation: sampleAttestation,
      chainId: 84532,
      oracleAddress: ORACLE_ADDR as `0x${string}`,
    });
    const sig = await signTypedData(client, td);

    const valid = await verifyAttestation({
      attestation: sampleAttestation,
      signature: sig,
      expectedSigner: account.address,
      chainId: 84532,
      oracleAddress: ORACLE_ADDR as `0x${string}`,
    });
    expect(valid).toBe(true);
  });
});

describe('attestation/packSigned', () => {
  it('packs all fields including domain', () => {
    const packed = packSigned(
      sampleAttestation,
      '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef' as `0x${string}`,
      '0x00' as `0x${string}`,
      84532,
      ORACLE_ADDR as `0x${string}`,
    );
    expect(packed.attestation).toEqual(sampleAttestation);
    expect(packed.domain.chainId).toBe(84532);
    expect(packed.domain.name).toBe('LITNUPOracle');
  });
});
