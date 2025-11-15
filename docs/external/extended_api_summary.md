### Extended API quick reference (offline)

Source: `https://api.docs.extended.exchange/#extended-api-documentation`

This is a condensed, offline-friendly index of the Extended API. Refer to the online docs for full schemas and examples.

- Overview
  - Hybrid CLOB exchange: off-chain matching; settlement on-chain via StarkEx.
  - Async REST workflow: order placement returns immediately; track via Order stream.
  - Rate limits, auth schemes, pagination: see online docs.

- Environments (SDK defaults)
  - Mainnet:
    - REST base: `https://api.extended.exchange/api/v1`
    - WS base: `wss://api.extended.exchange/stream.extended.exchange/v1`
    - Onboarding: `https://api.extended.exchange`
  - Testnet:
    - REST base: `https://api.testnet.extended.exchange/api/v1`
    - WS base: `wss://api.testnet.extended.exchange/stream.extended.exchange/v1`
    - Onboarding: `https://api.testnet.extended.exchange`

- Public REST-API
  - Get markets
  - Get market statistics
  - Get market order book
  - Get market last trades
  - Get candles history
  - Get funding rates history

- Private REST-API
  - Account
  - Get balance
  - Get deposits, withdrawals, transfers history
  - Get positions
  - Get positions history
  - Get open orders
  - Get orders history
  - Get trades
  - Get funding payments
  - Get current leverage
  - Update leverage
  - Get fees
  - Order management
  - Create or edit order
  - Cancel order
  - Mass Cancel
  - Mass Auto-Cancel (Dead Man's Switch)
  - Deposits
  - Create transfer
  - Withdrawals
  - Create slow withdrawal
  - Referrals
    - Get affiliate data
    - Get referral status
    - Get referral links
    - Get referral dashboard
    - Use referral link
    - Create referral link code
    - Update referral link code
  - Rewards

- Public WebSocket streams
  - Order book stream
    - GET `/stream.extended.exchange/v1/orderbooks/{market}`
    - Depth modes: full (100ms push; periodic snapshots), best bid/ask (`?depth=1`)
  - Trades stream
  - Funding rates stream
  - Candles stream
  - Mark price stream
  - Index price stream

- Private WebSocket streams
  - Account updates stream

- Selected fields (example: market stats)
  - `data.askPrice` (string) — Best ask
  - `data.bidPrice` (string) — Best bid
  - `data.markPrice` (string) — Mark price
  - `data.indexPrice` (string) — Index price
  - `data.fundingRate` (string) — Funding rate (per minute)
  - `data.nextFundingRate` (number) — Next funding timestamp
  - `data.openInterest` (string) — OI (collateral asset)
  - `data.openInterestBase` (string) — OI (base asset)
  - `data.deleverageLevels` (enum) — ADL levels 1–4


