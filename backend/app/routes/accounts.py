from __future__ import annotations

from fastapi import APIRouter, HTTPException
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
import json, secrets, traceback

from ..storage import STORE
from ..config import get_endpoint_config
import httpx


router = APIRouter()


class UpsertAccountRequest(BaseModel):
    wallet_address: str = Field(..., description="L1 wallet address")
    account_index: int = Field(..., ge=0, description="Extended subaccount index")
    api_key: Optional[str] = Field(None, description="User-specific Extended API key")
    stark_private_key: Optional[str] = Field(None, description="Optional BE-managed Stark L2 private key")
    stark_public_key: Optional[str] = Field(None, description="Optional Stark L2 public key (hex)")
    vault: Optional[int] = Field(None, description="Optional Stark vault id")


class AccountResponse(BaseModel):
    wallet_address: str
    account_index: int
    has_api_key: bool
    has_stark_key: bool
    has_public_key: bool
    has_vault: bool


@router.post("", response_model=AccountResponse)
def upsert_account(payload: UpsertAccountRequest) -> AccountResponse:
    record = STORE.upsert_user(
        wallet_address=payload.wallet_address,
        account_index=payload.account_index,
        api_key=payload.api_key,
        stark_private_key=payload.stark_private_key,
        stark_public_key=payload.stark_public_key,
        vault=payload.vault,
    )
    return AccountResponse(
        wallet_address=record.wallet_address,
        account_index=record.account_index,
        has_api_key=bool(record.api_key),
        has_stark_key=bool(record.stark_private_key),
        has_public_key=bool(record.stark_public_key),
        has_vault=record.vault is not None,
    )


# ---------- Programmatic API key issuance using user's L1 signatures ----------
L1_SIGNATURE_HEADER = "L1_SIGNATURE"
L1_MESSAGE_TIME_HEADER = "L1_MESSAGE_TIME"
ACTIVE_ACCOUNT_HEADER = "X-X10-ACTIVE-ACCOUNT"


class ApiKeyPrepareRequest(BaseModel):
    wallet_address: str = Field(..., description="User L1 wallet (0x...)")
    account_index: int = Field(..., ge=0)


class ApiKeyPrepareResponse(BaseModel):
    accounts_request_path: str
    accounts_auth_time: str
    accounts_message: str
    create_request_path: str
    create_auth_time: str
    create_message: str


@router.post("/api-key/prepare", response_model=ApiKeyPrepareResponse)
def prepare_api_key(payload: ApiKeyPrepareRequest) -> ApiKeyPrepareResponse:
    rid = secrets.token_hex(4)
    print(f"[APIKEY-PREPARE:{rid}] payload={payload.model_dump_json()}")
    # The mobile app will personal_sign these messages and send signatures to /api-key/issue
    # Format expected by Extended: "<request_path>@<ISO8601_UTC>"
    from datetime import datetime, timezone

    def iso_now():
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    accounts_path = "/api/v1/user/accounts"
    create_path = "/api/v1/user/account/api-key"
    t1 = iso_now()
    t2 = iso_now()
    return ApiKeyPrepareResponse(
        accounts_request_path=accounts_path,
        accounts_auth_time=t1,
        accounts_message=f"{accounts_path}@{t1}",
        create_request_path=create_path,
        create_auth_time=t2,
        create_message=f"{create_path}@{t2}",
    )


class ApiKeyIssueRequest(BaseModel):
    wallet_address: str
    account_index: int
    accounts_auth_time: str
    accounts_signature: str
    create_auth_time: str
    create_signature: str
    description: Optional[str] = Field(default="mobile trading key")


class ApiKeyIssueResponse(BaseModel):
    api_key: str
    account_id: int


@router.post("/api-key/issue", response_model=ApiKeyIssueResponse)
def issue_api_key(payload: ApiKeyIssueRequest) -> ApiKeyIssueResponse:
    cfg = get_endpoint_config()
    base = cfg.onboarding_url
    rid = secrets.token_hex(4)
    print(f"[APIKEY-ISSUE:{rid}] payload={payload.model_dump_json()}")
    # Normalize hex signatures: SDK sends raw hex without 0x; wallets often return 0x-prefixed.
    def _norm(sig: str) -> str:
        s = sig.strip()
        if not (s.startswith("0x") or s.startswith("0X")):
            return "0x" + s
        return s
    # Step 1: fetch accounts using L1 headers
    headers_accounts = {
        L1_SIGNATURE_HEADER: _norm(payload.accounts_signature),
        L1_MESSAGE_TIME_HEADER: payload.accounts_auth_time,
    }
    with httpx.Client(timeout=15.0) as client:
        url_accounts = f"{base}/api/v1/user/accounts"
        print(f"[APIKEY-ISSUE:{rid}] GET {url_accounts} headers={headers_accounts}")
        res_acc = client.get(url_accounts, headers=headers_accounts)
        print(f"[APIKEY-ISSUE:{rid}] ACCOUNTS status={res_acc.status_code} body={res_acc.text}")
        if res_acc.status_code >= 400:
            raise HTTPException(status_code=400, detail=f"Failed to fetch accounts: {res_acc.text}")
        acc_body = res_acc.json() or {}
        accounts: List[Dict[str, Any]] = acc_body.get("data") or []
        status = acc_body.get("status")
        if status and status != "OK":
            raise HTTPException(status_code=400, detail=f"Accounts error: {acc_body.get('error') or acc_body}")
        target = None
        for acc in accounts:
            try:
                idx = acc.get("account_index", acc.get("accountIndex", -1))
                if int(idx) == int(payload.account_index):
                    target = acc
                    break
            except Exception:
                continue
        if not target:
            raise HTTPException(status_code=404, detail="Account with requested index not found")
        account_id = int(target.get("id", target.get("accountId")))
        # Step 2: create API key for that account
        headers_create = {
            L1_SIGNATURE_HEADER: _norm(payload.create_signature),
            L1_MESSAGE_TIME_HEADER: payload.create_auth_time,
            ACTIVE_ACCOUNT_HEADER: str(account_id),
        }
        url_create = f"{base}/api/v1/user/account/api-key"
        body_create = {"description": payload.description}
        print(f"[APIKEY-ISSUE:{rid}] POST {url_create} headers={headers_create} json={json.dumps(body_create)}")
        res_create = client.post(url_create, headers=headers_create, json=body_create)
        print(f"[APIKEY-ISSUE:{rid}] CREATE status={res_create.status_code} body={res_create.text}")
        if res_create.status_code >= 400:
            raise HTTPException(status_code=400, detail=f"Failed to create API key: {res_create.text}")
        create_body = res_create.json() or {}
        key_data = create_body.get("data") or {}
        c_status = create_body.get("status")
        if c_status and c_status != "OK":
            raise HTTPException(status_code=400, detail=f"Create key error: {create_body.get('error') or create_body}")
        api_key = key_data.get("key")
        if not api_key:
            raise HTTPException(status_code=400, detail="No API key returned")
    # Persist in local STORE
    STORE.upsert_user(wallet_address=payload.wallet_address, account_index=payload.account_index, api_key=api_key)
    return ApiKeyIssueResponse(api_key=api_key, account_id=account_id)


