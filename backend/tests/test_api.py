from fastapi.testclient import TestClient

from backend.app.main import app


client = TestClient(app)


def test_session_start():
    res = client.post("/session/start", json={"wallet_address": "0xabcDEF123"})
    assert res.status_code == 200
    data = res.json()
    assert "nonce" in data and data["nonce"]
    assert "message" in data and "Nonce" in data["message"]


def test_accounts_upsert_and_get_balances_requires_api_key():
    # Upsert without api_key first
    res = client.post(
        "/accounts",
        json={
            "wallet_address": "0xabcDEF123",
            "account_index": 0,
        },
    )
    assert res.status_code == 200
    data = res.json()
    assert data["wallet_address"].lower() == "0xabcdef123"
    assert data["account_index"] == 0
    assert data["has_api_key"] is False

    # Proxy endpoints should fail without api_key
    res = client.get("/balances", params={"wallet_address": "0xabcDEF123", "account_index": 0})
    assert res.status_code == 401
    assert res.json()["detail"] == "API key not found for user"


