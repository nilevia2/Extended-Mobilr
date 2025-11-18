import os
from typing import Optional
from pydantic import BaseModel
from pathlib import Path

# Load .env file if it exists
try:
    from dotenv import load_dotenv
    env_path = Path(__file__).parent.parent / '.env'
    if env_path.exists():
        load_dotenv(env_path)
except ImportError:
    pass  # python-dotenv not installed, use system env vars only


class EndpointConfig(BaseModel):
    api_base_url: str
    stream_url: str
    onboarding_url: str
    signing_domain: str
    referral_code: str = ""  # Default referral code (empty), can be overridden via env


def get_endpoint_config(env: Optional[str] = None) -> EndpointConfig:
    selected = (env or os.getenv("EXTENDED_ENV", "mainnet")).lower()
    referral_code = os.getenv("REFERRAL_CODE", "")
    if selected == "mainnet":
        return EndpointConfig(
            api_base_url="https://api.starknet.extended.exchange/api/v1",
            stream_url="wss://api.starknet.extended.exchange/stream.extended.exchange/v1",
            onboarding_url="https://api.starknet.extended.exchange",
            signing_domain="extended.exchange",
            referral_code=referral_code,
        )
    return EndpointConfig(
        api_base_url="https://api.starknet.sepolia.extended.exchange/api/v1",
        stream_url="wss://api.starknet.sepolia.extended.exchange/stream.extended.exchange/v1",
        onboarding_url="https://api.starknet.sepolia.extended.exchange",
        signing_domain="starknet.sepolia.extended.exchange",
        referral_code=referral_code,
    )


