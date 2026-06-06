/**
 * LitToken module — balance queries + approvals.
 *
 * Skeleton ships type-correct stubs. Concrete viem reads/writes wire when ABI is imported.
 */
import type { Address, Hex } from 'viem';

export async function balanceOf(
  _client: unknown,
  _token: Address,
  _user: Address,
): Promise<bigint> {
  return 0n;
}

export async function approve(
  _client: unknown,
  _token: Address,
  _spender: Address,
  _amount: bigint,
): Promise<Hex> {
  throw new Error('Not yet implemented — wire ERC20.approve() ABI');
}

export async function totalSupply(
  _client: unknown,
  _token: Address,
): Promise<bigint> {
  return 0n;
}

export async function totalBurned(
  _client: unknown,
  _token: Address,
): Promise<bigint> {
  // Computed as MAX_SUPPLY - totalSupply()
  const MAX_SUPPLY = 1_000_000_000n * 10n ** 18n;
  const ts = await totalSupply(_client, _token);
  return MAX_SUPPLY - ts;
}

export async function getDelegate(
  _client: unknown,
  _token: Address,
  _user: Address,
): Promise<Address | null> {
  // ERC20Votes.delegates(user)
  return null;
}

export async function delegate(
  _client: unknown,
  _token: Address,
  _delegatee: Address,
): Promise<Hex> {
  throw new Error('Not yet implemented — wire ERC20Votes.delegate() ABI');
}
