from __future__ import annotations

from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
import secrets, json
import httpx

from ..clients.extended_rest import ExtendedRESTClient
from ..config import get_endpoint_config
from ..storage import STORE


router = APIRouter()


class PrivateQuery(BaseModel):
    wallet_address: str
    account_index: int


def _get_api_key(wallet_address: str, account_index: int) -> str:
    record = STORE.get_user(wallet_address=wallet_address, account_index=account_index)
    if not record or not record.api_key:
        raise HTTPException(status_code=401, detail="API key not found for user")
    return record.api_key


@router.get("/balances")
def get_balances(wallet_address: str, account_index: int):
    api_key = _get_api_key(wallet_address, account_index)
    client = ExtendedRESTClient(get_endpoint_config())
    try:
        return client.get_private(api_key, "/user/balance")
    except httpx.HTTPStatusError as e:
        # Fallback: some envs expose balance via account info
        if e.response.status_code == 404:
            return client.get_private(api_key, "/user/account/info")
        raise


@router.get("/positions")
def get_positions(wallet_address: str, account_index: int):
    api_key = _get_api_key(wallet_address, account_index)
    client = ExtendedRESTClient(get_endpoint_config())
    return client.get_private(api_key, "/user/positions")


@router.get("/orders")
def get_orders(wallet_address: str, account_index: int, status: Optional[str] = Query(None)):
    api_key = _get_api_key(wallet_address, account_index)
    client = ExtendedRESTClient(get_endpoint_config())
    params = {"status": status} if status else None
    return client.get_private(api_key, "/user/orders", params=params)


@router.get("/trades")
def get_trades(wallet_address: str, account_index: int, market: Optional[str] = Query(None)):
    api_key = _get_api_key(wallet_address, account_index)
    client = ExtendedRESTClient(get_endpoint_config())
    params = {"market": market} if market else None
    return client.get_private(api_key, "/user/trades", params=params)


@router.get("/positions/history")
def get_positions_history(wallet_address: str, account_index: int, market: Optional[str] = Query(None)):
    api_key = _get_api_key(wallet_address, account_index)
    client = ExtendedRESTClient(get_endpoint_config())
    params = {"market": market} if market else None
    return client.get_private(api_key, "/user/positions/history", params=params)


class ReferralRequest(BaseModel):
    wallet_address: str
    account_index: int
    code: str


@router.post("/referral")
def set_referral(payload: ReferralRequest):
    rid = secrets.token_hex(4)
    print(f"[REFERRAL:{rid}] payload={payload.model_dump_json()}")
    # Referral is already set during onboarding via referralCode.
    # No-op here to avoid 405 on non-existent endpoint; keep for compatibility.
    return {"status": "OK", "code": payload.code, "note": "referral handled at onboarding"}


