from __future__ import annotations

import os
import sys
from decimal import Decimal
from typing import Dict, Optional
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
    from x10.perpetual.order_object import OrderTpslTriggerParam, create_order_object  # type: ignore
    from x10.perpetual.orders import (  # type: ignore
        NewOrderModel,
        OrderPriceType,
        OrderSide,
        OrderTriggerPriceType,
        OrderTpslType,
        TimeInForce,
    )
    from x10.perpetual.fees import DEFAULT_FEES  # type: ignore
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

# Import additional required types for TPSL orders
try:
    from x10.utils.date import to_epoch_millis, utc_now  # type: ignore
    from x10.utils.nonce import generate_nonce  # type: ignore
except ImportError:
    pass

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
    tp_sl_type: Optional[str] = None,
    take_profit_trigger_price: Optional[Decimal] = None,
    take_profit_trigger_price_type: Optional[str] = None,
    take_profit_price: Optional[Decimal] = None,
    take_profit_price_type: Optional[str] = None,
    stop_loss_trigger_price: Optional[Decimal] = None,
    stop_loss_trigger_price_type: Optional[str] = None,
    stop_loss_price: Optional[Decimal] = None,
    stop_loss_price_type: Optional[str] = None,
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

    # Build TP/SL parameters if provided
    tp_sl_type_enum = None
    take_profit_param = None
    stop_loss_param = None

    if tp_sl_type:
        tp_sl_type_enum = OrderTpslType(tp_sl_type.upper())

    if take_profit_trigger_price is not None and take_profit_price is not None:
        if take_profit_trigger_price_type is None:
            take_profit_trigger_price_type = "LAST"
        if take_profit_price_type is None:
            take_profit_price_type = "LIMIT"
        
        # Round TP prices to market precision
        rounded_tp_trigger = market_model.trading_config.round_price(take_profit_trigger_price)
        rounded_tp_price = market_model.trading_config.round_price(take_profit_price)
        
        take_profit_param = OrderTpslTriggerParam(
            trigger_price=rounded_tp_trigger,
            trigger_price_type=OrderTriggerPriceType(take_profit_trigger_price_type.upper()),
            price=rounded_tp_price,
            price_type=OrderPriceType(take_profit_price_type.upper()),
        )
        print(f"[ORDER-SIGNING] Take Profit: trigger={rounded_tp_trigger} ({take_profit_trigger_price_type}), price={rounded_tp_price} ({take_profit_price_type})")

    if stop_loss_trigger_price is not None and stop_loss_price is not None:
        if stop_loss_trigger_price_type is None:
            stop_loss_trigger_price_type = "LAST"
        if stop_loss_price_type is None:
            stop_loss_price_type = "LIMIT"
        
        # Round SL prices to market precision
        rounded_sl_trigger = market_model.trading_config.round_price(stop_loss_trigger_price)
        rounded_sl_price = market_model.trading_config.round_price(stop_loss_price)
        
        stop_loss_param = OrderTpslTriggerParam(
            trigger_price=rounded_sl_trigger,
            trigger_price_type=OrderTriggerPriceType(stop_loss_trigger_price_type.upper()),
            price=rounded_sl_price,
            price_type=OrderPriceType(stop_loss_price_type.upper()),
        )
        print(f"[ORDER-SIGNING] Stop Loss: trigger={rounded_sl_trigger} ({stop_loss_trigger_price_type}), price={rounded_sl_price} ({stop_loss_price_type})")

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
        tp_sl_type=tp_sl_type_enum,
        take_profit=take_profit_param,
        stop_loss=stop_loss_param,
    )

    return order.to_api_request_json(exclude_none=True)


def build_signed_tpsl_position_order_json(
    *,
    api_key: str,
    stark_private_key_hex: str,
    stark_public_key_hex: str,
    vault: int,
    market: str,
    side: str,
    use_mainnet: bool = True,
    take_profit_trigger_price: Optional[Decimal] = None,
    take_profit_trigger_price_type: Optional[str] = None,
    take_profit_price: Optional[Decimal] = None,
    take_profit_price_type: Optional[str] = None,
    stop_loss_trigger_price: Optional[Decimal] = None,
    stop_loss_trigger_price_type: Optional[str] = None,
    stop_loss_price: Optional[Decimal] = None,
    stop_loss_price_type: Optional[str] = None,
) -> Dict:
    """
    Creates a position-level TPSL order (type: "TPSL", tpSlType: "POSITION").
    This monitors the position directly, not attached to a specific order.
    Returns JSON ready for POST /user/order
    """
    from x10.utils.date import to_epoch_millis, utc_now  # type: ignore
    from x10.utils.nonce import generate_nonce  # type: ignore
    from x10.perpetual.order_object_settlement import (  # type: ignore
        SettlementDataCtx,
        create_order_settlement_data,
    )

    side_enum = OrderSide(side)  # validates
    env_cfg = get_endpoint_config("mainnet" if use_mainnet else "testnet")
    x10_env_cfg = _get_env_config(use_mainnet)

    market_model = _fetch_market_model(env_cfg.api_base_url, market)

    account = StarkPerpetualAccount(
        vault=vault,
        private_key=stark_private_key_hex,
        public_key=stark_public_key_hex,
        api_key=api_key,
    )

    # For position-level TPSL, we use qty=0 and price=0
    # The actual position size is monitored automatically
    qty = Decimal("0")
    price = Decimal("0")

    # Generate nonce and expiry
    nonce = generate_nonce()
    expire_time = utc_now() + timedelta(hours=2160)  # 90 days

    fees = account.trading_fee.get(market_model.name, DEFAULT_FEES)

    # Create settlement data for the main TPSL order (qty=0, price=0)
    settlement_data_ctx = SettlementDataCtx(
        market=market_model,
        fees=fees,
        builder_fee=None,
        nonce=nonce,
        collateral_position_id=vault,
        expire_time=expire_time,
        signer=account.sign,
        public_key=account.public_key,
        starknet_domain=x10_env_cfg.starknet_domain,
    )

    # Main order settlement (qty=0, price=0 for position-level TPSL)
    main_settlement = create_order_settlement_data(
        side=side_enum,
        synthetic_amount=qty,
        price=price,
        ctx=settlement_data_ctx,
    )

    # Build order JSON manually (SDK doesn't support type="TPSL")
    # Convert settlement models to JSON-serializable format
    order_json = {
        "id": str(main_settlement.order_hash),
        "market": market_model.name,
        "type": "TPSL",  # Key difference from SDK
        "side": side.upper(),
        "qty": "0",  # Position-level TPSL uses 0
        "price": "0",  # Position-level TPSL uses 0
        "reduceOnly": True,
        "postOnly": False,
        "timeInForce": "GTT",
        "expiryEpochMillis": to_epoch_millis(expire_time),
        "fee": str(fees.taker_fee_rate),
        "nonce": str(nonce),
        "settlement": {
            "signature": {
                "r": hex(main_settlement.settlement.signature.r),
                "s": hex(main_settlement.settlement.signature.s),
            },
            "starkKey": hex(main_settlement.settlement.stark_key),
            "collateralPosition": str(main_settlement.settlement.collateral_position),
        },
        "selfTradeProtectionLevel": "ACCOUNT",
        "tpSlType": "POSITION",  # Monitor position, not order
    }

    # Add Take Profit if provided
    if take_profit_trigger_price is not None:
        if take_profit_trigger_price_type is None:
            take_profit_trigger_price_type = "LAST"
        if take_profit_price_type is None:
            take_profit_price_type = "LIMIT"
        if take_profit_price is None:
            take_profit_price = take_profit_trigger_price

        # Round prices
        rounded_tp_trigger = market_model.trading_config.round_price(take_profit_trigger_price)
        rounded_tp_price = market_model.trading_config.round_price(take_profit_price)

        # Get opposite side for TP/SL
        tp_side = OrderSide.BUY if side_enum == OrderSide.SELL else OrderSide.SELL

        # Create settlement for TP
        tp_settlement = create_order_settlement_data(
            side=tp_side,
            synthetic_amount=Decimal("0"),  # Position-level uses 0
            price=rounded_tp_price,
            ctx=settlement_data_ctx,
        )

        order_json["takeProfit"] = {
            "triggerPrice": str(rounded_tp_trigger),
            "triggerPriceType": take_profit_trigger_price_type.upper(),
            "price": str(rounded_tp_price),
            "priceType": take_profit_price_type.upper(),
            "settlement": {
                "signature": {
                    "r": hex(tp_settlement.settlement.signature.r),
                    "s": hex(tp_settlement.settlement.signature.s),
                },
                "starkKey": hex(tp_settlement.settlement.stark_key),
                "collateralPosition": str(tp_settlement.settlement.collateral_position),
            },
        }

        print(f"[ORDER-SIGNING] Take Profit: trigger={rounded_tp_trigger} ({take_profit_trigger_price_type}), price={rounded_tp_price} ({take_profit_price_type})")

    # Add Stop Loss if provided
    if stop_loss_trigger_price is not None:
        if stop_loss_trigger_price_type is None:
            stop_loss_trigger_price_type = "LAST"
        if stop_loss_price_type is None:
            stop_loss_price_type = "LIMIT"
        if stop_loss_price is None:
            stop_loss_price = stop_loss_trigger_price

        # Round prices
        rounded_sl_trigger = market_model.trading_config.round_price(stop_loss_trigger_price)
        rounded_sl_price = market_model.trading_config.round_price(stop_loss_price)

        # Get opposite side for TP/SL
        sl_side = OrderSide.BUY if side_enum == OrderSide.SELL else OrderSide.SELL

        # Create settlement for SL
        sl_settlement = create_order_settlement_data(
            side=sl_side,
            synthetic_amount=Decimal("0"),  # Position-level uses 0
            price=rounded_sl_price,
            ctx=settlement_data_ctx,
        )

        order_json["stopLoss"] = {
            "triggerPrice": str(rounded_sl_trigger),
            "triggerPriceType": stop_loss_trigger_price_type.upper(),
            "price": str(rounded_sl_price),
            "priceType": stop_loss_price_type.upper(),
            "settlement": {
                "signature": {
                    "r": hex(sl_settlement.settlement.signature.r),
                    "s": hex(sl_settlement.settlement.signature.s),
                },
                "starkKey": hex(sl_settlement.settlement.stark_key),
                "collateralPosition": str(sl_settlement.settlement.collateral_position),
            },
        }

        print(f"[ORDER-SIGNING] Stop Loss: trigger={rounded_sl_trigger} ({stop_loss_trigger_price_type}), price={rounded_sl_price} ({stop_loss_price_type})")

    return order_json


