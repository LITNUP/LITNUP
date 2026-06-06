/**
 * BuybackBurn mappings — every swap-and-burn.
 */
import { SwapAndBurn } from "../generated/BuybackBurn/BuybackBurn";
import { BurnEvent } from "../generated/schema";
import { getOrCreateProtocolStats, getOrCreateDaily, eventId } from "./shared";

export function handleSwapAndBurn(event: SwapAndBurn): void {
  const ev = new BurnEvent(eventId(event));
  ev.inputToken = event.params.token;
  ev.inputAmount = event.params.inAmount;
  ev.burnedAmount = event.params.burned;
  ev.bountyAmount = event.params.bounty;
  ev.blockNumber = event.block.number;
  ev.timestamp = event.block.timestamp;
  ev.txHash = event.transaction.hash;
  ev.save();

  const stats = getOrCreateProtocolStats(event.block.timestamp);
  stats.cumulativeBurnedTokens = stats.cumulativeBurnedTokens.plus(event.params.burned);
  stats.lastUpdatedAt = event.block.timestamp;
  stats.save();

  const daily = getOrCreateDaily(event.block.timestamp);
  daily.tokensBurned = daily.tokensBurned.plus(event.params.burned);
  daily.save();
}
