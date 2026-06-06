/**
 * Shared helpers across mappings.
 */
import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  Operator,
  Staker,
  StakerPosition,
  ProtocolStats,
  DailyStats,
} from "../generated/schema";

export function eventId(event: ethereum.Event): string {
  return event.transaction.hash.toHex() + "-" + event.logIndex.toString();
}

export function dayId(timestamp: BigInt): string {
  // Unix midnight key
  const day = timestamp.toI64() / 86_400;
  // Format: YYYY-MM-DD via JS-style date math; for AssemblyScript we approximate with day index
  return day.toString();
}

export function getOrCreateOperator(addr: Bytes, ts: BigInt): Operator {
  let op = Operator.load(addr.toHex());
  if (op != null) return op as Operator;
  op = new Operator(addr.toHex());
  op.address = addr;
  op.totalAgentsEnrolled = 0;
  op.totalBondPosted = BigInt.zero();
  op.totalBondSlashed = BigInt.zero();
  op.firstSeenAt = ts;
  op.save();
  return op as Operator;
}

export function getOrCreateStaker(addr: Bytes, ts: BigInt): Staker {
  let s = Staker.load(addr.toHex());
  if (s != null) return s as Staker;
  s = new Staker(addr.toHex());
  s.address = addr;
  s.totalSharesAcrossAgents = BigInt.zero();
  s.cumulativeStaked = BigInt.zero();
  s.cumulativeUnstaked = BigInt.zero();
  s.firstStakeAt = ts;
  s.save();
  return s as Staker;
}

export function getOrCreatePosition(agentId: string, stakerAddr: Bytes): StakerPosition {
  const id = agentId + "-" + stakerAddr.toHex();
  let p = StakerPosition.load(id);
  if (p != null) return p as StakerPosition;
  p = new StakerPosition(id);
  p.agent = agentId;
  p.staker = stakerAddr.toHex();
  p.shares = BigInt.zero();
  p.pendingShares = BigInt.zero();
  p.unlockAt = BigInt.zero();
  p.cumulativeDeposits = BigInt.zero();
  p.cumulativeWithdrawals = BigInt.zero();
  p.realizedPnL = BigInt.zero();
  p.save();
  return p as StakerPosition;
}

export function getOrCreateProtocolStats(ts: BigInt): ProtocolStats {
  let s = ProtocolStats.load("singleton");
  if (s != null) return s as ProtocolStats;
  s = new ProtocolStats("singleton");
  s.totalActiveAgents = 0;
  s.totalAgentsEverEnrolled = 0;
  s.totalTVL = BigInt.zero();
  s.totalStakers = 0;
  s.cumulativeAttestations = 0;
  s.cumulativeFeesUsd = BigInt.zero().toBigDecimal();
  s.cumulativeBurnedTokens = BigInt.zero();
  s.cumulativeBurnedUsd = BigInt.zero().toBigDecimal();
  s.totalLocked = BigInt.zero();
  s.lastUpdatedAt = ts;
  s.save();
  return s as ProtocolStats;
}

export function getOrCreateDaily(ts: BigInt): DailyStats {
  const id = dayId(ts);
  let d = DailyStats.load(id);
  if (d != null) return d as DailyStats;
  d = new DailyStats(id);
  d.date = BigInt.fromI64(ts.toI64() - (ts.toI64() % 86_400));
  d.agentsActive = 0;
  d.agentsEnrolled = 0;
  d.totalTVL = BigInt.zero();
  d.attestations = 0;
  d.netPnl = BigInt.zero();
  d.feesCollected = BigInt.zero();
  d.tokensBurned = BigInt.zero();
  d.newStakers = 0;
  d.save();
  return d as DailyStats;
}
