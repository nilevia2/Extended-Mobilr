from __future__ import annotations

import secrets
import time
from dataclasses import dataclass
from typing import Dict, Optional, Tuple


@dataclass
class UserRecord:
    wallet_address: str
    account_index: int
    api_key: Optional[str] = None
    stark_private_key: Optional[str] = None
    stark_public_key: Optional[str] = None
    vault: Optional[int] = None


class MemoryStore:
    def __init__(self) -> None:
        self._users: Dict[Tuple[str, int], UserRecord] = {}
        self._session_nonces: Dict[str, Tuple[str, float]] = {}

    def upsert_user(
        self,
        wallet_address: str,
        account_index: int,
        api_key: Optional[str] = None,
        stark_private_key: Optional[str] = None,
        stark_public_key: Optional[str] = None,
        vault: Optional[int] = None,
    ) -> UserRecord:
        key = (wallet_address.lower(), account_index)
        record = self._users.get(key) or UserRecord(wallet_address=wallet_address, account_index=account_index)
        if api_key is not None:
            record.api_key = api_key
        if stark_private_key is not None:
            record.stark_private_key = stark_private_key
        if stark_public_key is not None:
            record.stark_public_key = stark_public_key
        if vault is not None:
            record.vault = vault
        self._users[key] = record
        return record

    def get_user(self, wallet_address: str, account_index: int) -> Optional[UserRecord]:
        return self._users.get((wallet_address.lower(), account_index))

    def create_session_nonce(self, wallet_address: str, ttl_seconds: int = 300) -> str:
        nonce = secrets.token_hex(16)
        self._session_nonces[wallet_address.lower()] = (nonce, time.time() + ttl_seconds)
        return nonce

    def consume_session_nonce(self, wallet_address: str, nonce: str) -> bool:
        entry = self._session_nonces.get(wallet_address.lower())
        if not entry:
            return False
        expected_nonce, expiry = entry
        if time.time() > expiry or expected_nonce != nonce:
            return False
        del self._session_nonces[wallet_address.lower()]
        return True


# Note: The default STORE is now selected in storage/__init__.py


