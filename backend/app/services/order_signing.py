from __future__ import annotations

import os
import sys
from decimal import Decimal
from typing import Dict

import httpx

# Ensure vendored SDK is importable
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
VENDOR_SDK_PATH = os.path.join(PROJECT_ROOT, "vendor", "python_sdk")
if VENDOR_SDK_PATH not in sys.path:
    sys.path.insert(0, VENDOR_SDK_PATH)

from x10.perpetual.accounts import StarkPerpetualAccount  # type: ignore
from x10.perpetual.configuration import MAINNET_CONFIG, TESTNET_CONFIG  # type: ignore
from x10.perpetual.markets import MarketModel  # type: ignore
from x10.perpetual.order_object import create_order_object  # type: ignore
from x10.perpetual.orders import (  # type: ignore
    NewOrderModel,
    OrderSide,
    TimeInForce,
)

from ..config import get_endpoint_config


def _get_env_config(use_mainnet: bool):
    return MAINNET_CONFIG if use_mainnet else TESTNET_CONFIG


def _fetch_market_model(api_base_url: str, market_name: str) -> MarketModel:
    url = f"{api_base_url}/info/markets"
    with httpx.Client(timeout=15.0) as client:
        res = client.get(url, params={"market": market_name})
        res.raise_for_status()
        data = res.json().get("data") or []
        if not data:
            raise ValueError(f"Market '{market_name}' not found from {url}")
        return MarketModel.model_validate(data[0])


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
    use_mainnet: bool = False,
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

    account = StarkPerpetualAccount(
        vault=vault,
        private_key=stark_private_key_hex,
        public_key=stark_public_key_hex,
        api_key=api_key,
    )

    order: NewOrderModel = create_order_object(
        account=account,
        market=market_model,
        amount_of_synthetic=qty,
        price=price,
        side=side_enum,
        post_only=post_only,
        reduce_only=reduce_only,
        starknet_domain=x10_env_cfg.starknet_domain,
        time_in_force=tif_enum,
    )

    return order.to_api_request_json(exclude_none=True)


