from __future__ import annotations

import os
import sys
from decimal import Decimal
from typing import Dict
from datetime import datetime, timedelta

import httpx

# Ensure vendored SDK is importable
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
VENDOR_SDK_PATH = os.path.join(PROJECT_ROOT, "vendor", "python_sdk")
if VENDOR_SDK_PATH not in sys.path:
    sys.path.insert(0, VENDOR_SDK_PATH)

# Check if SDK path exists
if not os.path.exists(VENDOR_SDK_PATH):
    raise ImportError(
        f"Vendored SDK not found at {VENDOR_SDK_PATH}. "
        "Ensure vendor/python_sdk directory exists."
    )

# Check if x10 package exists
x10_path = os.path.join(VENDOR_SDK_PATH, "x10")
if not os.path.exists(x10_path):
    raise ImportError(
        f"x10 package not found in {VENDOR_SDK_PATH}. "
        "Ensure vendor/python_sdk/x10 directory exists."
    )

try:
    from x10.perpetual.accounts import StarkPerpetualAccount  # type: ignore
    from x10.perpetual.configuration import MAINNET_CONFIG, TESTNET_CONFIG  # type: ignore
    from x10.perpetual.markets import MarketModel  # type: ignore
    from x10.perpetual.order_object import create_order_object  # type: ignore
    from x10.perpetual.orders import (  # type: ignore
        NewOrderModel,
        OrderSide,
        TimeInForce,
    )
except ImportError as e:
    raise ImportError(
        f"Failed to import from vendored SDK at {VENDOR_SDK_PATH}. "
        f"Error: {e}. "
        "Ensure all SDK dependencies are installed: "
        "fast-stark-crypto==0.3.8, pydantic>=2.9.0, aiohttp>=3.10.11, "
        "eth-account>=0.12.0, pyyaml>=6.0.1, sortedcontainers>=2.4.0, "
        "tenacity>=9.1.2, websockets>=12.0,<14.0"
    ) from e

from ..config import get_endpoint_config

# Cache for market models (key: market_name, value: (market_model, expiry_time))
_market_cache: Dict[str, tuple[MarketModel, datetime]] = {}
_CACHE_TTL_MINUTES = 10  # Cache market data for 10 minutes


def _get_env_config(use_mainnet: bool):
    return MAINNET_CONFIG if use_mainnet else TESTNET_CONFIG


def _fetch_market_model(api_base_url: str, market_name: str) -> MarketModel:
    """Fetch market model from mainnet only, with caching."""
    # Check cache first
    now = datetime.now()
    if market_name in _market_cache:
        market_model, expiry = _market_cache[market_name]
        if now < expiry:
            print(f"[ORDER-SIGNING] Using cached market data for {market_name}")
            return market_model
        else:
            # Cache expired, remove it
            del _market_cache[market_name]
    
    # Always use mainnet
    mainnet_url = api_base_url.replace("sepolia.", "") if "sepolia" in api_base_url else api_base_url
    url = f"{mainnet_url}/info/markets"
    print(f"[ORDER-SIGNING] Fetching market data for {market_name} from {url}")
    with httpx.Client(timeout=15.0) as client:
        res = client.get(url, params={"market": market_name})
        res.raise_for_status()
        data = res.json().get("data") or []
        if not data:
            raise ValueError(f"Market '{market_name}' not found on mainnet")
        market_model = MarketModel.model_validate(data[0])
        
        # Cache it
        expiry = now + timedelta(minutes=_CACHE_TTL_MINUTES)
        _market_cache[market_name] = (market_model, expiry)
        print(f"[ORDER-SIGNING] Cached market data for {market_name} (expires in {_CACHE_TTL_MINUTES} minutes)")
        return market_model


def build_signed_limit_order_json(
    *,
    api_key: str,
    stark_private_key_hex: str,
    stark_public_key_hex: str,
    vault: int,
    market: str,
    qty: Decimal,
    price: Decimal,
    side: str,
    post_only: bool = False,
    reduce_only: bool = False,
    time_in_force: str = "GTT",
    use_mainnet: bool = True,
) -> Dict:
    """
    Creates a signed limit order body using vendored SDK.
    Returns JSON ready for POST /user/order
    """
    side_enum = OrderSide(side)  # validates
    tif_enum = TimeInForce(time_in_force)  # validates

    env_cfg = get_endpoint_config("mainnet" if use_mainnet else "testnet")
    x10_env_cfg = _get_env_config(use_mainnet)

    market_model = _fetch_market_model(env_cfg.api_base_url, market)

    # Round quantity to market precision to avoid "Invalid quantity precision" errors
    # The SDK should handle this, but we do it explicitly to ensure correctness
    rounded_qty = market_model.trading_config.round_order_size(qty)
    print(f"[ORDER-SIGNING] Original qty: {qty}, Rounded qty: {rounded_qty}, Market: {market}")
    
    # Round price to market precision to avoid "Invalid price precision" errors
    rounded_price = market_model.trading_config.round_price(price)
    print(f"[ORDER-SIGNING] Original price: {price}, Rounded price: {rounded_price}, Market: {market}")

    account = StarkPerpetualAccount(
        vault=vault,
        private_key=stark_private_key_hex,
        public_key=stark_public_key_hex,
        api_key=api_key,
    )

    order: NewOrderModel = create_order_object(
        account=account,
        market=market_model,
        amount_of_synthetic=rounded_qty,
        price=rounded_price,
        side=side_enum,
        post_only=post_only,
        reduce_only=reduce_only,
        starknet_domain=x10_env_cfg.starknet_domain,
        time_in_force=tif_enum,
    )

    return order.to_api_request_json(exclude_none=True)


