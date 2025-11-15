from __future__ import annotations

from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

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
    return client.get_private(api_key, "/balances")


@router.get("/positions")
def get_positions(wallet_address: str, account_index: int):
    api_key = _get_api_key(wallet_address, account_index)
    client = ExtendedRESTClient(get_endpoint_config())
    return client.get_private(api_key, "/positions")


@router.get("/orders")
def get_orders(wallet_address: str, account_index: int, status: Optional[str] = Query(None)):
    api_key = _get_api_key(wallet_address, account_index)
    client = ExtendedRESTClient(get_endpoint_config())
    params = {"status": status} if status else None
    return client.get_private(api_key, "/orders", params=params)


