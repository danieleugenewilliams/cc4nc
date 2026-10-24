"""Account-transfer logic for the demo bank."""

from dataclasses import dataclass


class InsufficientFunds(Exception):
    """Raised when an account lacks the balance for a debit."""


@dataclass
class Account:
    id: str
    owner_id: str
    balance: int  # whole cents


def _assert_transfer_allowed(source: Account, amount: int, acting_user_id: str) -> None:
    """Raise if this transfer must not proceed."""
    if source.owner_id != acting_user_id:
        raise PermissionError(f"user {acting_user_id} does not own account {source.id}")
    if amount <= 0:
        raise ValueError("transfer amount must be positive")
    if source.balance < amount:
        raise InsufficientFunds(f"account {source.id} has {source.balance}, needs {amount}")


def transfer(source: Account, dest: Account, amount: int, acting_user_id: str) -> None:
    """Move ``amount`` cents from ``source`` to ``dest`` on behalf of ``acting_user_id``."""
    _assert_transfer_allowed(source, amount, acting_user_id)

    source.balance -= amount
    dest.balance += amount
