from __future__ import annotations

from fastapi import APIRouter, HTTPException
from typing import Optional
from pydantic import BaseModel, Field

from ..storage import STORE


router = APIRouter()


class UpsertAccountRequest(BaseModel):
    wallet_address: str = Field(..., description="L1 wallet address")
    account_index: int = Field(..., ge=0, description="Extended subaccount index")
    api_key: Optional[str] = Field(None, description="User-specific Extended API key")
    stark_private_key: Optional[str] = Field(None, description="Optional BE-managed Stark L2 private key")
    stark_public_key: Optional[str] = Field(None, description="Optional Stark L2 public key (hex)")
    vault: Optional[int] = Field(None, description="Optional Stark vault id")


class AccountResponse(BaseModel):
    wallet_address: str
    account_index: int
    has_api_key: bool
    has_stark_key: bool
    has_public_key: bool
    has_vault: bool


@router.post("", response_model=AccountResponse)
def upsert_account(payload: UpsertAccountRequest) -> AccountResponse:
    record = STORE.upsert_user(
        wallet_address=payload.wallet_address,
        account_index=payload.account_index,
        api_key=payload.api_key,
        stark_private_key=payload.stark_private_key,
        stark_public_key=payload.stark_public_key,
        vault=payload.vault,
    )
    return AccountResponse(
        wallet_address=record.wallet_address,
        account_index=record.account_index,
        has_api_key=bool(record.api_key),
        has_stark_key=bool(record.stark_private_key),
        has_public_key=bool(record.stark_public_key),
        has_vault=record.vault is not None,
    )


