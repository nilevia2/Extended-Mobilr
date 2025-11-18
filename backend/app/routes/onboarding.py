from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from datetime import datetime, timezone
import httpx
import secrets, json

from ..config import get_endpoint_config
from ..storage import STORE


router = APIRouter()


class OnboardingStartRequest(BaseModel):
    wallet_address: str = Field(..., description="L1 wallet address (0x...)")
    account_index: int = Field(..., ge=0, description="Subaccount index")


class OnboardingStartResponse(BaseModel):
    typed_data: dict
    registration_typed_data: dict


@router.post("/start", response_model=OnboardingStartResponse)
def onboarding_start(payload: OnboardingStartRequest) -> OnboardingStartResponse:
    rid = secrets.token_hex(4)
    print(f"[ONBOARD-START:{rid}] payload={payload.model_dump_json()}")
    cfg = get_endpoint_config()
    # EIP-712 typed data for key derivation (AccountCreation)
    typed_data = {
        "types": {
            "EIP712Domain": [{"name": "name", "type": "string"}],
            "AccountCreation": [
                {"name": "accountIndex", "type": "int8"},
                {"name": "wallet", "type": "address"},
                {"name": "tosAccepted", "type": "bool"},
            ],
        },
        "domain": {"name": cfg.signing_domain},
        "primaryType": "AccountCreation",
        "message": {
            "accountIndex": payload.account_index,
            "wallet": payload.wallet_address,
            "tosAccepted": True,
        },
    }
    # EIP-712 typed data for account registration (used by /auth/onboard)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    registration_typed_data = {
        "types": {
            "EIP712Domain": [{"name": "name", "type": "string"}],
            "AccountRegistration": [
                {"name": "accountIndex", "type": "int8"},
                {"name": "wallet", "type": "address"},
                {"name": "tosAccepted", "type": "bool"},
                {"name": "time", "type": "string"},
                {"name": "action", "type": "string"},
                {"name": "host", "type": "string"},
            ],
        },
        "domain": {"name": cfg.signing_domain},
        "primaryType": "AccountRegistration",
        "message": {
            "accountIndex": payload.account_index,
            "wallet": payload.wallet_address,
            "tosAccepted": True,
            "time": now,
            "action": "REGISTER",
            "host": cfg.onboarding_url,
        },
    }
    print(f"[ONBOARD-START:{rid}] creation_typed={json.dumps(typed_data)}")
    print(f"[ONBOARD-START:{rid}] registration_typed={json.dumps(registration_typed_data)}")
    return OnboardingStartResponse(typed_data=typed_data, registration_typed_data=registration_typed_data)


class OnboardingCompleteRequest(BaseModel):
    wallet_address: str = Field(...)
    account_index: int = Field(..., ge=0)
    l1_signature: str = Field(..., description="0x... signature from eth_signTypedData_v4")
    registration_signature: str = Field(..., description="0x... signature for AccountRegistration struct")
    registration_time: str = Field(..., description="ISO8601 time used in AccountRegistration message")
    registration_host: str = Field(..., description="Host used in AccountRegistration message (e.g. https://api.starknet.sepolia.extended.exchange)")


class OnboardingCompleteResponse(BaseModel):
    stark_private_key: str
    stark_public_key: str
    account_index: int
    wallet_address: str


@router.post("/complete", response_model=OnboardingCompleteResponse)
def onboarding_complete(payload: OnboardingCompleteRequest) -> OnboardingCompleteResponse:
    try:
        rid = secrets.token_hex(4)
        print(f"[ONBOARD-COMPLETE:{rid}] payload={payload.model_dump_json()}")
        # Derive L2 keys from L1 signature using fast_stark_crypto
        from fast_stark_crypto import generate_keypair_from_eth_signature, pedersen_hash  # type: ignore
        from fast_stark_crypto import sign as stark_sign  # type: ignore

        (private_int, public_int) = generate_keypair_from_eth_signature(payload.l1_signature)
        priv_hex = hex(private_int)
        pub_hex = hex(public_int)

        # Build onboarding payload and send to Extended /auth/onboard
        cfg = get_endpoint_config()
        l2_msg = pedersen_hash(int(payload.wallet_address, 16), public_int)
        r, s = stark_sign(msg_hash=l2_msg, private_key=private_int)
        onboarding_payload = {
            "l1Signature": payload.registration_signature,
            "l2Key": pub_hex,
            "l2Signature": {"r": hex(r), "s": hex(s)},
            "accountCreation": {
                "accountIndex": payload.account_index,
                "wallet": payload.wallet_address,
                "tosAccepted": True,
                "time": payload.registration_time,
                "action": "REGISTER",
                "host": payload.registration_host,
            },
            "referralCode": "ADMIN",
        }
        url = f"{cfg.onboarding_url}/auth/onboard"
        with httpx.Client(timeout=20.0) as client:
            print(f"[ONBOARD-COMPLETE:{rid}] POST {url} json={json.dumps(onboarding_payload)}")
            res = client.post(url, json=onboarding_payload)
            print(f"[ONBOARD-COMPLETE:{rid}] status={res.status_code} body={res.text}")
            if res.status_code >= 400:
                raise HTTPException(status_code=400, detail=f"Onboarding POST failed: {res.text}")
            body = res.json() or {}
            if body.get("status") != "OK":
                raise HTTPException(status_code=400, detail=f"Onboarding error: {body.get('error') or body}")

        STORE.upsert_user(
            wallet_address=payload.wallet_address, account_index=payload.account_index, stark_private_key=priv_hex, stark_public_key=pub_hex
        )

        return OnboardingCompleteResponse(stark_private_key=priv_hex, stark_public_key=pub_hex, account_index=payload.account_index, wallet_address=payload.wallet_address)
    except Exception as e:
        print(f"[ONBOARD-COMPLETE:ERR] {e}")
        raise HTTPException(status_code=400, detail=f"Onboarding failed: {e}")


