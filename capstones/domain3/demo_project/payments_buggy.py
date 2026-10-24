"""Account-transfer logic for the demo bank."""

from dataclasses import dataclass


class InsufficientFunds(Exception):
    """Raised when an account lacks the balance for a debit."""


@dataclass
class Account:
    id: str
    owner_id: str
    balance: int  # whole cents


def transfer(source: Account, dest: Account, amount: int, acting_user_id: str) -> None:
    """Move ``amount`` cents from ``source`` to ``dest``."""
    source.balance -= amount
    dest.balance += amount
