"""Trading strategies for LITNUP agents."""
from .base import Strategy, Signal
from .momentum import MomentumStrategy
from .meanrev import MeanReversionStrategy
from .basis import BasisTradeStrategy
from .vol_carry import VolCarryStrategy
from .stat_arb import StatArbStrategy
from .funding_arb import FundingArbStrategy
from .pairs import PairsTradeStrategy
from .options_carry import OptionsCarryStrategy

__all__ = [
    "Strategy",
    "Signal",
    "MomentumStrategy",
    "MeanReversionStrategy",
    "BasisTradeStrategy",
    "VolCarryStrategy",
    "StatArbStrategy",
    "FundingArbStrategy",
    "PairsTradeStrategy",
    "OptionsCarryStrategy",
]


def build_strategy(name: str):
    """Factory for CLI-driven strategy selection."""
    name = name.lower()
    registry = {
        "momentum": MomentumStrategy,
        "meanrev": MeanReversionStrategy,
        "basis": BasisTradeStrategy,
        "vol_carry": VolCarryStrategy,
        "volcarry": VolCarryStrategy,
        "stat_arb": StatArbStrategy,
        "statarb": StatArbStrategy,
        "funding_arb": FundingArbStrategy,
        "fundingarb": FundingArbStrategy,
        "pairs": PairsTradeStrategy,
        "options_carry": OptionsCarryStrategy,
        "optionscarry": OptionsCarryStrategy,
    }
    if name not in registry:
        raise ValueError(f"unknown strategy: {name}. Available: {list(registry.keys())}")
    return registry[name]()
