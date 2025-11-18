### Extended Backend Adapter

Minimal FastAPI backend to support the Extended mobile app.

- Endpoints
  - `POST /session/start` → returns a login nonce and message to sign.
  - `POST /accounts` → upsert user record (stores API key and optional Stark key).
  - `GET /balances?wallet_address&account_index` → proxies to Extended private API.
  - `GET /positions?wallet_address&account_index` → proxies to Extended private API.
  - `GET /orders?wallet_address&account_index[&status]` → proxies to Extended private API.
  - `POST /orders` → forwards a fully-formed order body to Extended private API.

- Config
  - Environment selection via `EXTENDED_ENV` (`testnet` default, or `mainnet`).
  - Endpoint defaults are in `app/config.py`.
  - Referral code via `REFERRAL_CODE` environment variable (optional, defaults to empty).
    - Create a `.env` file in the `backend/` directory with `REFERRAL_CODE=your_code` to set it.
    - See `.env.example` for template.

- Run locally
  - Install deps: `pip install -r backend/requirements.txt`
  - Start: `uvicorn backend.app.main:app --reload --port 8080`

- Notes
  - This adapter stores API keys in memory. Replace with a persistent store for production.
  - Orders must be signed before submission; either sign in the app or extend this backend to sign using a managed Stark key.


