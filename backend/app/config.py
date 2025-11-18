import os
from typing import Optional
from pydantic import BaseModel


class EndpointConfig(BaseModel):
    api_base_url: str
    stream_url: str
    onboarding_url: str
    signing_domain: str


def get_endpoint_config(env: Optional[str] = None) -> EndpointConfig:
    selected = (env or os.getenv("EXTENDED_ENV", "testnet")).lower()
    if selected == "mainnet":
        return EndpointConfig(
            api_base_url="https://api.starknet.extended.exchange/api/v1",
            stream_url="wss://api.starknet.extended.exchange/stream.extended.exchange/v1",
            onboarding_url="https://api.starknet.extended.exchange",
            signing_domain="extended.exchange",
        )
    return EndpointConfig(
        api_base_url="https://api.starknet.sepolia.extended.exchange/api/v1",
        stream_url="wss://api.starknet.sepolia.extended.exchange/stream.extended.exchange/v1",
        onboarding_url="https://api.starknet.sepolia.extended.exchange",
        signing_domain="starknet.sepolia.extended.exchange",
    )


