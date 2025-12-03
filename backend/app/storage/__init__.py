from __future__ import annotations

from typing import Optional

from .memory import MemoryStore
from .db import DatabaseStore, get_db_url_from_env


def _init_store():
    db_url: Optional[str] = get_db_url_from_env()
    if db_url:
        try:
            print(f"[STORAGE] DATABASE_URL found, initializing DatabaseStore...")
            store = DatabaseStore(db_url)
            print(f"[STORAGE] ✅ DatabaseStore initialized successfully")
            return store
        except Exception as e:
            print(f"[STORAGE] ⚠️ Failed to initialize DatabaseStore: {e}")
            print(f"[STORAGE] Falling back to MemoryStore")
            pass
    else:
        print(f"[STORAGE] ⚠️ No DATABASE_URL found, using MemoryStore (data will be lost on restart)")
    return MemoryStore()


STORE = _init_store()


