from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from ..storage import STORE


router = APIRouter()


class StartSessionRequest(BaseModel):
    wallet_address: str = Field(..., description="User's L1 wallet address (0x...)")


class StartSessionResponse(BaseModel):
    nonce: str
    message: str


@router.post("/start", response_model=StartSessionResponse)
def start_session(payload: StartSessionRequest) -> StartSessionResponse:
    nonce = STORE.create_session_nonce(payload.wallet_address)
    message = f"Extended login\nNonce: {nonce}\nWallet: {payload.wallet_address.lower()}"
    return StartSessionResponse(nonce=nonce, message=message)


