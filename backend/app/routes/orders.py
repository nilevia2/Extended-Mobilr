from __future__ import annotations

from fastapi import APIRouter, HTTPException
import httpx
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
    use_mainnet: bool = True
    # TP/SL parameters
    tp_sl_type: str | None = Field(None, pattern="^(ORDER|POSITION)$", description="TPSL type: ORDER or POSITION")
    take_profit_trigger_price: float | None = Field(None, description="Take Profit trigger price")
    take_profit_trigger_price_type: str | None = Field(None, pattern="^(LAST|MARK|INDEX)$", description="TP trigger price type: LAST, MARK, or INDEX")
    take_profit_price: float | None = Field(None, description="Take Profit execution price")
    take_profit_price_type: str | None = Field(None, pattern="^(MARKET|LIMIT)$", description="TP execution price type: MARKET or LIMIT")
    stop_loss_trigger_price: float | None = Field(None, description="Stop Loss trigger price")
    stop_loss_trigger_price_type: str | None = Field(None, pattern="^(LAST|MARK|INDEX)$", description="SL trigger price type: LAST, MARK, or INDEX")
    stop_loss_price: float | None = Field(None, description="Stop Loss execution price")
    stop_loss_price_type: str | None = Field(None, pattern="^(MARKET|LIMIT)$", description="SL execution price type: MARKET or LIMIT")


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

    # Normalize wallet address (database stores lowercase)
    normalized_wallet = payload.wallet_address.lower()
    record = STORE.get_user(wallet_address=normalized_wallet, account_index=payload.account_index)
    if not record:
        raise HTTPException(status_code=404, detail="User not found")
    if not record.api_key:
        raise HTTPException(status_code=401, detail="API key not found for user")
    if not record.stark_private_key or not record.stark_public_key:
        raise HTTPException(status_code=400, detail="Missing L2 credentials: private/public key")
    
    # Fetch vault if missing
    vault = record.vault
    if vault is None or vault == 0:
        print(f"[ORDER] Vault is missing or 0, fetching from Extended API...")
        try:
            client_temp = ExtendedRESTClient(get_endpoint_config("mainnet"))
            account_info = client_temp.get_private(record.api_key, "/user/account/info")
            vault_from_api = account_info.get("data", {}).get("l2Vault")
            if vault_from_api:
                vault = int(vault_from_api)
                # Update vault in database for future use
                STORE.upsert_user(
                    wallet_address=normalized_wallet,
                    account_index=payload.account_index,
                    vault=vault,
                )
                print(f"[ORDER] Fetched and stored vault {vault} from mainnet")
            else:
                raise HTTPException(
                    status_code=400,
                    detail="Vault not found in account info response"
                )
        except Exception as e:
            raise HTTPException(
                status_code=400, 
                detail=f"Vault not found and could not be fetched from Extended API mainnet: {str(e)}"
            )
    
    if vault is None or vault == 0:
        raise HTTPException(
            status_code=400, 
            detail="Vault ID is required but not available. Please ensure API key issuance completed successfully."
        )

    # Build signed order using vendored SDK
    # Allow single-leg TP/SL: if trigger is set but execution price is None, default to MARKET at trigger
    take_profit_price = payload.take_profit_price
    take_profit_price_type = payload.take_profit_price_type
    stop_loss_price = payload.stop_loss_price
    stop_loss_price_type = payload.stop_loss_price_type
    tp_trigger_type = payload.take_profit_trigger_price_type
    sl_trigger_type = payload.stop_loss_trigger_price_type

    # Extended SDK does NOT support TPSL price_type MARKET; default to LIMIT at the trigger.
    if payload.take_profit_trigger_price is not None:
        if take_profit_price is None:
            take_profit_price = payload.take_profit_trigger_price
        if take_profit_price_type is None or take_profit_price_type == "MARKET":
            take_profit_price_type = "LIMIT"
        if tp_trigger_type is None:
            tp_trigger_type = "LAST"
    if payload.stop_loss_trigger_price is not None:
        if stop_loss_price is None:
            stop_loss_price = payload.stop_loss_trigger_price
        if stop_loss_price_type is None or stop_loss_price_type == "MARKET":
            stop_loss_price_type = "LIMIT"
        if sl_trigger_type is None:
            sl_trigger_type = "LAST"

    # If neither TP nor SL provided, drop tp_sl_type to avoid API rejection
    tp_sl_type = payload.tp_sl_type if (payload.take_profit_trigger_price is not None or payload.stop_loss_trigger_price is not None) else None

    order_json = build_signed_limit_order_json(
        api_key=record.api_key,
        stark_private_key_hex=record.stark_private_key,
        stark_public_key_hex=record.stark_public_key,
        vault=int(vault),
        market=payload.market,
        qty=Decimal(str(payload.qty)),
        price=Decimal(str(payload.price)),
        side=payload.side,
        post_only=payload.post_only,
        reduce_only=payload.reduce_only,
        time_in_force=payload.time_in_force,
        use_mainnet=payload.use_mainnet,
        tp_sl_type=tp_sl_type,
        take_profit_trigger_price=Decimal(str(payload.take_profit_trigger_price)) if payload.take_profit_trigger_price is not None else None,
        take_profit_trigger_price_type=tp_trigger_type,
        take_profit_price=Decimal(str(take_profit_price)) if take_profit_price is not None else None,
        take_profit_price_type=take_profit_price_type,
        stop_loss_trigger_price=Decimal(str(payload.stop_loss_trigger_price)) if payload.stop_loss_trigger_price is not None else None,
        stop_loss_trigger_price_type=sl_trigger_type,
        stop_loss_price=Decimal(str(stop_loss_price)) if stop_loss_price is not None else None,
        stop_loss_price_type=stop_loss_price_type,
    )

    print("[ORDER] Payload prepared for signing:")
    print(order_json)

    # Place order via private REST
    client = ExtendedRESTClient(get_endpoint_config("mainnet" if payload.use_mainnet else "testnet"))
    
    print(f"[ORDER] ========================================")
    print(f"[ORDER] Placing order:")
    print(f"[ORDER]   Market: {payload.market}")
    print(f"[ORDER]   Side: {payload.side}")
    print(f"[ORDER]   Qty: {payload.qty}")
    print(f"[ORDER]   Price: {payload.price}")
    print(f"[ORDER]   Reduce Only: {payload.reduce_only}")
    print(f"[ORDER]   Time In Force: {payload.time_in_force}")
    if payload.tp_sl_type:
        print(f"[ORDER]   TP/SL Type: {payload.tp_sl_type}")
    if payload.take_profit_trigger_price is not None:
        print(f"[ORDER]   Take Profit: trigger={payload.take_profit_trigger_price} ({payload.take_profit_trigger_price_type}), price={payload.take_profit_price} ({payload.take_profit_price_type})")
    if payload.stop_loss_trigger_price is not None:
        print(f"[ORDER]   Stop Loss: trigger={payload.stop_loss_trigger_price} ({payload.stop_loss_trigger_price_type}), price={payload.stop_loss_price} ({payload.stop_loss_price_type})")
    print(f"[ORDER] ========================================")
    
    try:
        order_response = client.post_private(record.api_key, "/user/order", json=order_json)
    except httpx.HTTPStatusError as e:
        # Forward Extended API errors instead of bubbling as 500
        status = e.response.status_code
        detail = e.response.json() if e.response else {"message": str(e)}
        raise HTTPException(status_code=status, detail=detail)
    
    # Log order response for debugging
    print(f"[ORDER] Order placed successfully. Response: {order_response}")
    order_status = order_response.get("data", {}).get("status") if isinstance(order_response.get("data"), dict) else None
    order_id = order_response.get("data", {}).get("id") if isinstance(order_response.get("data"), dict) else None
    if order_status:
        print(f"[ORDER] Order ID: {order_id}, Status: {order_status}")
        if order_status in ["REJECTED", "CANCELLED"]:
            status_reason = order_response.get("data", {}).get("statusReason", "Unknown reason")
            print(f"[ORDER] WARNING: Order was {order_status}. Reason: {status_reason}")
    
    return order_response


