from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Optional, Tuple

from sqlalchemy import String, create_engine, select
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    wallet_address: Mapped[str] = mapped_column(String(80), primary_key=True)
    account_index: Mapped[int] = mapped_column(primary_key=True)
    api_key: Mapped[Optional[str]] = mapped_column(String(256), nullable=True)
    stark_private_key: Mapped[Optional[str]] = mapped_column(String(256), nullable=True)
    stark_public_key: Mapped[Optional[str]] = mapped_column(String(256), nullable=True)
    vault: Mapped[Optional[int]] = mapped_column(nullable=True)


@dataclass
class UserRecord:
    wallet_address: str
    account_index: int
    api_key: Optional[str]
    stark_private_key: Optional[str]
    stark_public_key: Optional[str]
    vault: Optional[int]


class DatabaseStore:
    def __init__(self, db_url: str) -> None:
        self._engine = create_engine(db_url, pool_pre_ping=True)
        Base.metadata.create_all(self._engine)

    def upsert_user(
        self,
        wallet_address: str,
        account_index: int,
        api_key: Optional[str] = None,
        stark_private_key: Optional[str] = None,
        stark_public_key: Optional[str] = None,
        vault: Optional[int] = None,
    ) -> UserRecord:
        wallet_key = wallet_address.lower()
        with Session(self._engine) as session:
            user = session.get(User, (wallet_key, account_index))
            if user is None:
                user = User(
                    wallet_address=wallet_key,
                    account_index=account_index,
                    api_key=api_key,
                    stark_private_key=stark_private_key,
                    stark_public_key=stark_public_key,
                    vault=vault,
                )
                session.add(user)
            else:
                if api_key is not None:
                    user.api_key = api_key
                if stark_private_key is not None:
                    user.stark_private_key = stark_private_key
                if stark_public_key is not None:
                    user.stark_public_key = stark_public_key
                if vault is not None:
                    user.vault = vault
            session.commit()
            return UserRecord(
                wallet_address=user.wallet_address,
                account_index=user.account_index,
                api_key=user.api_key,
                stark_private_key=user.stark_private_key,
                stark_public_key=user.stark_public_key,
                vault=user.vault,
            )

    def get_user(self, wallet_address: str, account_index: int) -> Optional[UserRecord]:
        wallet_key = wallet_address.lower()
        with Session(self._engine) as session:
            user = session.get(User, (wallet_key, account_index))
            if not user:
                return None
            return UserRecord(
                wallet_address=user.wallet_address,
                account_index=user.account_index,
                api_key=user.api_key,
                stark_private_key=user.stark_private_key,
                stark_public_key=user.stark_public_key,
                vault=user.vault,
            )


def get_db_url_from_env() -> Optional[str]:
    # Example: postgresql+psycopg://user:pass@host:5432/dbname
    return os.getenv("DATABASE_URL") or os.getenv("DB_URL")


