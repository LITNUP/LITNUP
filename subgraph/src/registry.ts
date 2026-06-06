/**
 * AgentRegistry mappings.
 *
 * Indexes operator enrollments + bond changes + slashing into the Agent +
 * Operator + BondChange entities defined in schema.graphql.
 */
import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  AgentEnrolled,
  AgentBondTopUp,
  AgentMetadataUpdated,
  AgentPaused,
  AgentResumed,
  AgentSlashed,
  AgentWithdrawInit,
  AgentWithdrawn,
} from "../generated/AgentRegistry/AgentRegistry";
import {
  Agent,
  Operator,
  BondChange,
} from "../generated/schema";
import { getOrCreateOperator, getOrCreateProtocolStats, eventId } from "./shared";

export function handleAgentEnrolled(event: AgentEnrolled): void {
  const agentId = event.params.agentId.toString();
  let agent = new Agent(agentId);
  agent.agentId = event.params.agentId;
  agent.controller = event.params.controller;
  const op = getOrCreateOperator(event.params.controller, event.block.timestamp);
  agent.operator = op.id;
  agent.enrolledAt = event.block.timestamp;
  agent.bond = event.params.bond;
  agent.metadataHash = event.params.metadataHash;
  agent.protocolFeeBps = event.params.protocolFeeBps;
  agent.status = "Active";

  agent.totalAssets = BigInt.zero();
  agent.totalShares = BigInt.zero();
  agent.sharePrice = BigInt.fromI64(1_000_000_000_000_000_000).toBigDecimal();
  agent.totalStakers = 0;
  agent.cumulativeStakedDeposits = BigInt.zero();
  agent.cumulativeStakedWithdrawals = BigInt.zero();
  agent.cumulativePnL = BigInt.zero();
  agent.cumulativeFees = BigInt.zero();
  agent.cumulativeBuybackPortion = BigInt.zero();
  agent.cumulativeStakerPortion = BigInt.zero();
  agent.cumulativeSlashed = BigInt.zero();
  agent.pnl30dPct = BigInt.zero().toBigDecimal();
  agent.sharpe30d = BigInt.zero().toBigDecimal();
  agent.maxDrawdownPct = BigInt.zero().toBigDecimal();

  agent.save();

  op.totalAgentsEnrolled = op.totalAgentsEnrolled + 1;
  op.totalBondPosted = op.totalBondPosted.plus(event.params.bond);
  op.save();

  const bc = new BondChange(eventId(event));
  bc.agent = agent.id;
  bc.delta = event.params.bond;
  bc.kind = "Enroll";
  bc.blockNumber = event.block.number;
  bc.timestamp = event.block.timestamp;
  bc.txHash = event.transaction.hash;
  bc.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalActiveAgents = stats.totalActiveAgents + 1;
  stats.totalAgentsEverEnrolled = stats.totalAgentsEverEnrolled + 1;
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();
}

export function handleBondTopUp(event: AgentBondTopUp): void {
  const agent = Agent.load(event.params.agentId.toString());
  if (agent == null) return;
  agent.bond = agent.bond.plus(event.params.amount);
  agent.save();

  const bc = new BondChange(eventId(event));
  bc.agent = agent.id;
  bc.delta = event.params.amount;
  bc.kind = "TopUp";
  bc.blockNumber = event.block.number;
  bc.timestamp = event.block.timestamp;
  bc.txHash = event.transaction.hash;
  bc.save();
}

export function handleMetadataUpdated(event: AgentMetadataUpdated): void {
  const agent = Agent.load(event.params.agentId.toString());
  if (agent == null) return;
  agent.metadataHash = event.params.metadataHash;
  agent.save();
}

export function handleAgentPaused(event: AgentPaused): void {
  const agent = Agent.load(event.params.agentId.toString());
  if (agent == null) return;
  agent.status = "Paused";
  agent.save();
  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalActiveAgents = stats.totalActiveAgents - 1;
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();
}

export function handleAgentResumed(event: AgentResumed): void {
  const agent = Agent.load(event.params.agentId.toString());
  if (agent == null) return;
  agent.status = "Active";
  agent.save();
  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalActiveAgents = stats.totalActiveAgents + 1;
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();
}

export function handleAgentSlashed(event: AgentSlashed): void {
  const agent = Agent.load(event.params.agentId.toString());
  if (agent == null) return;
  agent.bond = agent.bond.minus(event.params.amount);
  if (agent.bond.lt(BigInt.zero())) agent.bond = BigInt.zero();
  agent.cumulativeSlashed = agent.cumulativeSlashed.plus(event.params.amount);
  agent.save();

  const op = Operator.load(agent.operator);
  if (op != null) {
    op.totalBondSlashed = op.totalBondSlashed.plus(event.params.amount);
    op.save();
  }

  const bc = new BondChange(eventId(event));
  bc.agent = agent.id;
  bc.delta = event.params.amount.neg();
  bc.kind = "Slash";
  bc.blockNumber = event.block.number;
  bc.timestamp = event.block.timestamp;
  bc.txHash = event.transaction.hash;
  bc.save();
}

export function handleAgentWithdrawInit(event: AgentWithdrawInit): void {
  const agent = Agent.load(event.params.agentId.toString());
  if (agent == null) return;
  agent.unbondedAt = event.block.timestamp;
  agent.save();

  const bc = new BondChange(eventId(event));
  bc.agent = agent.id;
  bc.delta = BigInt.zero();
  bc.kind = "WithdrawInit";
  bc.blockNumber = event.block.number;
  bc.timestamp = event.block.timestamp;
  bc.txHash = event.transaction.hash;
  bc.save();
}

export function handleAgentWithdrawn(event: AgentWithdrawn): void {
  const agent = Agent.load(event.params.agentId.toString());
  if (agent == null) return;
  agent.status = "Withdrawn";
  agent.bond = BigInt.zero();
  agent.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalActiveAgents = stats.totalActiveAgents - 1;
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();

  const bc = new BondChange(eventId(event));
  bc.agent = agent.id;
  bc.delta = event.params.amount.neg();
  bc.kind = "WithdrawComplete";
  bc.blockNumber = event.block.number;
  bc.timestamp = event.block.timestamp;
  bc.txHash = event.transaction.hash;
  bc.save();
}
