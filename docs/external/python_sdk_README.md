### Extended Python SDK (vendored) — offline notes

Upstream: `https://github.com/x10xchange/python_sdk`
Local path: `vendor/python_sdk/`

- Install (from PyPI)
  - `pip install x10-python-trading-starknet` (Python 3.10+ recommended)
  - Uses a Rust library for signing/hashing (prebuilt for common OS/arch).

- Environment configuration (since 0.3.0)
  - Controlled by an `EndpointConfiguration` passed to clients.
  - Helpers available for Mainnet/Testnet, including legacy signing domain variant for older mainnet onboarding.

- Onboarding via SDK
  - `onboard(referral_code: Optional[str] = None) -> OnBoardedAccount`
  - `onboard_subaccount(account_index: int, description: str | None = None) -> OnBoardedAccount`
  - `get_accounts() -> List[OnBoardedAccount]`
  - `create_account_api_key(account: AccountModel, description: str | None) -> str`
  - L1 actions:
    - `perform_l1_withdrawal() -> str`
    - `available_l1_withdrawal_balance() -> Decimal`

- Key derivation (from Ethereum account)
  - EIP‑712 typed data sign of an `AccountCreation` struct (`accountIndex`, `wallet`, `tosAccepted`).
  - Stark private key derived from Ethereum signature via `stark_sign.grind_key`.

- Deposits (since 0.3.0)
  - `deposit` function on `AccountModule` to deposit USDC into StarkEx account.
  - See `contract.py` (`call_stark_perpetual_deposit`). 

- Examples
  - See `vendor/python_sdk/examples/` (e.g., `placed_order_example.py`).
  - Typical flow:
    - Instantiate `StarkPerpetualAccount` with API creds and endpoint config.
    - Place/edit/cancel orders; query balances/positions/trades; subscribe to streams.

- Development
  - `make format` — format with black
  - `make lint` — safety, black, flake8, mypy
  - `make test` — run tests
  - Project uses Poetry (`poetry install`).


