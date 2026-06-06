/**
 * VotingEscrow mappings — locks, extensions, top-ups, withdraws.
 */
import { BigInt } from "@graphprotocol/graph-ts";
import {
  Locked,
  LockExtended,
  LockToppedUp,
  Withdrawn,
} from "../generated/VotingEscrow/VotingEscrow";
import { Lock, LockEvent } from "../generated/schema";
import { getOrCreateProtocolStats, eventId } from "./shared";

export function handleLocked(event: Locked): void {
  const id = event.params.user.toHex();
  let lock = Lock.load(id);
  if (lock == null) {
    lock = new Lock(id);
    lock.user = event.params.user;
    lock.createdAt = event.block.timestamp;
  }
  lock.amount = event.params.amount;
  lock.unlockTime = BigInt.fromI64(event.params.unlockTime);
  lock.save();

  const ev = new LockEvent(eventId(event));
  ev.lock = lock.id;
  ev.kind = "Locked";
  ev.amountDelta = event.params.amount;
  ev.newUnlockTime = BigInt.fromI64(event.params.unlockTime);
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalLocked = stats.totalLocked.plus(event.params.amount);
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();
}

export function handleLockExtended(event: LockExtended): void {
  const id = event.params.user.toHex();
  const lock = Lock.load(id);
  if (lock == null) return;
  lock.unlockTime = BigInt.fromI64(event.params.newUnlockTime);
  lock.save();

  const ev = new LockEvent(eventId(event));
  ev.lock = lock.id;
  ev.kind = "Extended";
  ev.newUnlockTime = BigInt.fromI64(event.params.newUnlockTime);
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();
}

export function handleLockToppedUp(event: LockToppedUp): void {
  const id = event.params.user.toHex();
  const lock = Lock.load(id);
  if (lock == null) return;
  lock.amount = lock.amount.plus(event.params.delta);
  lock.save();

  const ev = new LockEvent(eventId(event));
  ev.lock = lock.id;
  ev.kind = "ToppedUp";
  ev.amountDelta = event.params.delta;
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalLocked = stats.totalLocked.plus(event.params.delta);
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();
}

export function handleWithdrawn(event: Withdrawn): void {
  const id = event.params.user.toHex();
  const lock = Lock.load(id);
  if (lock == null) return;

  const ev = new LockEvent(eventId(event));
  ev.lock = lock.id;
  ev.kind = "Withdrawn";
  ev.amountDelta = event.params.amount.neg();
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.totalLocked = stats.totalLocked.minus(event.params.amount);
  if (stats.totalLocked.lt(BigInt.zero())) stats.totalLocked = BigInt.zero();
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();

  lock.amount = BigInt.zero();
  lock.save();
}
