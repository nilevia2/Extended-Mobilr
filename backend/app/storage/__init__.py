from __future__ import annotations

from typing import Optional

from .memory import MemoryStore
from .db import DatabaseStore, get_db_url_from_env


def _init_store():
    db_url: Optional[str] = get_db_url_from_env()
    if db_url:
        try:
            return DatabaseStore(db_url)
        except Exception:
            pass
    return MemoryStore()


STORE = _init_store()


