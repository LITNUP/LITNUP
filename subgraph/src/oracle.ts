/**
 * PerformanceOracle mappings — attestations + signer events.
 */
import { BigInt } from "@graphprotocol/graph-ts";
import {
  AttestationApplied,
  SignerAdded,
  SignerRemoved,
  ThresholdUpdated,
} from "../generated/PerformanceOracle/PerformanceOracle";
import {
  Attestation,
  OracleSigner,
  OracleConfig,
} from "../generated/schema";
import { getOrCreateProtocolStats, getOrCreateDaily } from "./shared";

export function handleAttestationApplied(event: AttestationApplied): void {
  const id = event.params.agentId.toString() + "-" + event.params.epoch.toString();
  let att = new Attestation(id);
  att.agent = event.params.agentId.toString();
  att.epoch = BigInt.fromI64(event.params.epoch);
  att.pnlDelta = event.params.pnlDelta;
  att.feeOnGross = event.params.feeOnGross;
  att.blockNumber = event.block.number;
  att.timestamp = event.block.timestamp;
  att.txHash = event.transaction.hash;
  att.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.cumulativeAttestations = stats.cumulativeAttestations + 1;
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();

  const daily = getOrCreateDaily(event.block.timestamp);
  daily.attestations = daily.attestations + 1;
  daily.save();
}

function getConfig(ts: BigInt): OracleConfig {
  let c = OracleConfig.load("singleton");
  if (c != null) return c as OracleConfig;
  c = new OracleConfig("singleton");
  c.threshold = 0;
  c.signerCount = 0;
  c.lastUpdatedAt = ts;
  c.save();
  return c as OracleConfig;
}

export function handleSignerAdded(event: SignerAdded): void {
  const id = event.params.signer.toHex();
  let s = OracleSigner.load(id);
  if (s == null) {
    s = new OracleSigner(id);
    s.address = event.params.signer;
    s.addedAt = event.block.timestamp;
  }
  s.active = true;
  s.removedAt = null;
  s.save();

  const cfg = getConfig(event.block.timestamp);
  cfg.signerCount = cfg.signerCount + 1;
  cfg.lastUpdatedAt = event.block.timestamp;
  cfg.save();
}

export function handleSignerRemoved(event: SignerRemoved): void {
  const id = event.params.signer.toHex();
  const s = OracleSigner.load(id);
  if (s == null) return;
  s.active = false;
  s.removedAt = event.block.timestamp;
  s.save();

  const cfg = getConfig(event.block.timestamp);
  cfg.signerCount = cfg.signerCount - 1;
  if (cfg.signerCount < 0) cfg.signerCount = 0;
  cfg.lastUpdatedAt = event.block.timestamp;
  cfg.save();
}

export function handleThresholdUpdated(event: ThresholdUpdated): void {
  const cfg = getConfig(event.block.timestamp);
  cfg.threshold = event.params.threshold;
  cfg.lastUpdatedAt = event.block.timestamp;
  cfg.save();
}
