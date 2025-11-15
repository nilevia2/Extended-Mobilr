from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..clients.extended_rest import ExtendedRESTClient
from ..config import get_endpoint_config
from ..storage import STORE


router = APIRouter()


class CreateOrderRequest(BaseModel):
    wallet_address: str = Field(..., description="L1 wallet address")
    account_index: int = Field(..., ge=0, description="Extended subaccount index")
    order: dict = Field(..., description="Order payload expected by Extended private REST API (must include signatures if required)")


def _get_api_key(wallet_address: str, account_index: int) -> str:
    record = STORE.get_user(wallet_address=wallet_address, account_index=account_index)
    if not record or not record.api_key:
        raise HTTPException(status_code=401, detail="API key not found for user")
    return record.api_key


@router.post("")
def create_order(payload: CreateOrderRequest):
    api_key = _get_api_key(payload.wallet_address, payload.account_index)
    client = ExtendedRESTClient(get_endpoint_config())
    # Expect client-side (or BE) to provide a fully-formed, signed order body.
    return client.post_private(api_key, "/user/order", json=payload.order)


class CreateAndPlaceOrderRequest(BaseModel):
    wallet_address: str = Field(..., description="L1 wallet address")
    account_index: int = Field(..., ge=0, description="Extended subaccount index")
    market: str = Field(..., description="Market name, e.g., BTC-USD")
    qty: float = Field(..., description="Synthetic asset quantity")
    price: float = Field(..., description="Order price")
    side: str = Field(..., pattern="^(BUY|SELL)$")
    post_only: bool = False
    reduce_only: bool = False
    time_in_force: str = Field("GTT", pattern="^(GTT|IOC)$")
    use_mainnet: bool = False


@router.post("/create-and-place")
def create_and_place_order(payload: CreateAndPlaceOrderRequest):
    # Lazy import to avoid failing on Python<3.10 during app import
    try:
        from decimal import Decimal
        from ..services.order_signing import build_signed_limit_order_json  # type: ignore
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail="Server-side signing not available in this runtime. Ensure Python >= 3.10 and vendored SDK present.",
        ) from e

    record = STORE.get_user(wallet_address=payload.wallet_address, account_index=payload.account_index)
    if not record:
        raise HTTPException(status_code=404, detail="User not found")
    if not record.api_key:
        raise HTTPException(status_code=401, detail="API key not found for user")
    if not record.stark_private_key or not record.stark_public_key or record.vault is None:
        raise HTTPException(status_code=400, detail="Missing L2 credentials: private/public key or vault")

    # Build signed order using vendored SDK
    order_json = build_signed_limit_order_json(
        api_key=record.api_key,
        stark_private_key_hex=record.stark_private_key,
        stark_public_key_hex=record.stark_public_key,
        vault=int(record.vault),
        market=payload.market,
        qty=Decimal(str(payload.qty)),
        price=Decimal(str(payload.price)),
        side=payload.side,
        post_only=payload.post_only,
        reduce_only=payload.reduce_only,
        time_in_force=payload.time_in_force,
        use_mainnet=payload.use_mainnet,
    )

    # Place order via private REST
    client = ExtendedRESTClient(get_endpoint_config("mainnet" if payload.use_mainnet else "testnet"))
    return client.post_private(record.api_key, "/user/order", json=order_json)


