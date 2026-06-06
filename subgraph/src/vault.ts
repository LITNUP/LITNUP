/**
 * StakingVault mappings — stakes, unstakes, PnL, fees, slashes.
 */
import { BigInt, BigDecimal } from "@graphprotocol/graph-ts";
import {
  Staked,
  UnstakeInit,
  Unstaked,
  PnlApplied,
  FeesTaken,
  StakerSlashed,
} from "../generated/StakingVault/StakingVault";
import {
  Agent,
  StakeEvent,
  UnstakeEvent,
  PnlEvent,
  FeeEvent,
  SlashEvent,
} from "../generated/schema";
import {
  getOrCreateStaker,
  getOrCreatePosition,
  getOrCreateProtocolStats,
  getOrCreateDaily,
  eventId,
} from "./shared";

const ONE_E18 = BigInt.fromI64(1_000_000_000_000_000_000);

function recomputeSharePrice(agent: Agent): void {
  if (agent.totalShares.isZero()) {
    agent.sharePrice = ONE_E18.toBigDecimal();
    return;
  }
  agent.sharePrice = agent.totalAssets.toBigDecimal()
    .times(ONE_E18.toBigDecimal())
    .div(agent.totalShares.toBigDecimal());
}

export function handleStaked(event: Staked): void {
  const agentIdStr = event.params.agentId.toString();
  const agent = Agent.load(agentIdStr);
  if (agent == null) return;

  const staker = getOrCreateStaker(event.params.staker, event.block.timestamp);
  const position = getOrCreatePosition(agentIdStr, event.params.staker);
  if (position.shares.isZero() && position.cumulativeDeposits.isZero()) {
    agent.totalStakers = agent.totalStakers + 1;
  }
  position.shares = position.shares.plus(event.params.shares);
  position.cumulativeDeposits = position.cumulativeDeposits.plus(event.params.amount);
  position.save();

  staker.totalSharesAcrossAgents = staker.totalSharesAcrossAgents.plus(event.params.shares);
  staker.cumulativeStaked = staker.cumulativeStaked.plus(event.params.amount);
  staker.save();

  agent.totalAssets = agent.totalAssets.plus(event.params.amount);
  agent.totalShares = agent.totalShares.plus(event.params.shares);
  agent.cumulativeStakedDeposits = agent.cumulativeStakedDeposits.plus(event.params.amount);
  recomputeSharePrice(agent);
  agent.save();

  const ev = new StakeEvent(eventId(event));
  ev.agent = agentIdStr;
  ev.staker = event.params.staker;
  ev.amount = event.params.amount;
  ev.shares = event.params.shares;
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalTVL = stats.totalTVL.plus(event.params.amount);
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();

  const daily = getOrCreateDaily(event.block.timestamp);
  daily.totalTVL = stats.totalTVL;
  daily.save();
}

export function handleUnstakeInit(event: UnstakeInit): void {
  const agentIdStr = event.params.agentId.toString();
  const position = getOrCreatePosition(agentIdStr, event.params.staker);
  position.pendingShares = position.pendingShares.plus(event.params.shares);
  position.unlockAt = BigInt.fromI64(event.params.unlockAt);
  position.save();

  const ev = new UnstakeEvent(eventId(event));
  ev.agent = agentIdStr;
  ev.staker = event.params.staker;
  ev.shares = event.params.shares;
  ev.amount = BigInt.zero();
  ev.phase = "Init";
  ev.unlockAt = BigInt.fromI64(event.params.unlockAt);
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();
}

export function handleUnstaked(event: Unstaked): void {
  const agentIdStr = event.params.agentId.toString();
  const agent = Agent.load(agentIdStr);
  if (agent == null) return;
  const position = getOrCreatePosition(agentIdStr, event.params.staker);

  position.pendingShares = position.pendingShares.minus(event.params.shares);
  if (position.pendingShares.lt(BigInt.zero())) position.pendingShares = BigInt.zero();
  position.cumulativeWithdrawals = position.cumulativeWithdrawals.plus(event.params.amount);
  position.save();

  agent.totalAssets = agent.totalAssets.minus(event.params.amount);
  if (agent.totalAssets.lt(BigInt.zero())) agent.totalAssets = BigInt.zero();
  agent.totalShares = agent.totalShares.minus(event.params.shares);
  if (agent.totalShares.lt(BigInt.zero())) agent.totalShares = BigInt.zero();
  agent.cumulativeStakedWithdrawals = agent.cumulativeStakedWithdrawals.plus(event.params.amount);
  recomputeSharePrice(agent);
  agent.save();

  const ev = new UnstakeEvent(eventId(event));
  ev.agent = agentIdStr;
  ev.staker = event.params.staker;
  ev.shares = event.params.shares;
  ev.amount = event.params.amount;
  ev.phase = "Complete";
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalTVL = stats.totalTVL.minus(event.params.amount);
  if (stats.totalTVL.lt(BigInt.zero())) stats.totalTVL = BigInt.zero();
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();
}

export function handlePnlApplied(event: PnlApplied): void {
  const agentIdStr = event.params.agentId.toString();
  const agent = Agent.load(agentIdStr);
  if (agent == null) return;

  agent.totalAssets = event.params.newTotalAssets;
  agent.cumulativePnL = agent.cumulativePnL.plus(event.params.delta);
  recomputeSharePrice(agent);
  agent.save();

  const ev = new PnlEvent(eventId(event));
  ev.agent = agentIdStr;
  ev.delta = event.params.delta;
  ev.newTotalAssets = event.params.newTotalAssets;
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();

  const daily = getOrCreateDaily(event.block.timestamp);
  daily.netPnl = daily.netPnl.plus(event.params.delta);
  daily.save();
}

export function handleFeesTaken(event: FeesTaken): void {
  const agentIdStr = event.params.agentId.toString();
  const agent = Agent.load(agentIdStr);
  if (agent == null) return;

  const total = event.params.toBuyback.plus(event.params.toStakers);
  agent.cumulativeFees = agent.cumulativeFees.plus(total);
  agent.cumulativeBuybackPortion = agent.cumulativeBuybackPortion.plus(event.params.toBuyback);
  agent.cumulativeStakerPortion = agent.cumulativeStakerPortion.plus(event.params.toStakers);
  // toBuyback already removed from totalAssets at oracle time; toStakers stays in vault
  agent.save();

  const ev = new FeeEvent(eventId(event));
  ev.agent = agentIdStr;
  ev.toBuyback = event.params.toBuyback;
  ev.toStakers = event.params.toStakers;
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();

  const daily = getOrCreateDaily(event.block.timestamp);
  daily.feesCollected = daily.feesCollected.plus(total);
  daily.save();
}

export function handleStakerSlashed(event: StakerSlashed): void {
  const agentIdStr = event.params.agentId.toString();
  const agent = Agent.load(agentIdStr);
  if (agent == null) return;

  agent.totalAssets = agent.totalAssets.minus(event.params.amount);
  if (agent.totalAssets.lt(BigInt.zero())) agent.totalAssets = BigInt.zero();
  agent.cumulativeSlashed = agent.cumulativeSlashed.plus(event.params.amount);
  recomputeSharePrice(agent);
  agent.save();

  const ev = new SlashEvent(eventId(event));
  ev.agent = agentIdStr;
  ev.amount = event.params.amount;
  ev.reason = "VaultDrawdown";
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();
}
