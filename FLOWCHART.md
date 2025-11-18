# Flowchart: Wallet Connect → User Balance

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         FLUTTER MOBILE APP                               │
└─────────────────────────────────────────────────────────────────────────┘

1. INITIALIZE WALLET CONNECT
   ┌─────────────────────────────────────┐
   │ WalletService.init()                │
   │ - Load WC_PROJECT_ID from env       │
   │ - Create Web3App instance            │
   │ - Connect to WalletConnect relay     │
   └──────────────┬──────────────────────┘
                  │
                  ▼
2. CONNECT WALLET
   ┌─────────────────────────────────────┐
   │ User clicks "Connect"               │
   │ WalletService.connect()             │
   │ - Generate pairing URI              │
   │ - Return wc:// URI                 │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Open Wallet App                     │
   │ - Try MetaMask deep link            │
   │ - Try Trust Wallet deep link        │
   │ - Try Rainbow Wallet deep link      │
   │ - Fallback: Show QR code            │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ User approves connection in wallet  │
   │ WalletConnect session established   │
   │ - Session topic saved               │
   │ - Wallet address extracted           │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Wallet Connected ✓                  │
   │ Address: 0x9b00f582...             │
   └──────────────┬──────────────────────┘
                  │
                  ▼
3. ONBOARDING (First Time Only)
   ┌─────────────────────────────────────┐
   │ User clicks "Onboard"              │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ POST /onboarding/start              │
   │ → Backend                          │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Backend generates EIP-712 data:     │
   │ 1. AccountCreation typed data       │
   │ 2. AccountRegistration typed data   │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Request Signature #1                │
   │ signTypedDataV4(AccountCreation)    │
   │ - Auto-opens wallet                 │
   │ - User approves in wallet           │
   │ - Returns signature                 │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Request Signature #2                │
   │ signTypedDataV4(AccountRegistration)│
   │ - Auto-opens wallet                 │
   │ - User approves in wallet           │
   │ - Returns signature                 │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ POST /onboarding/complete           │
   │ → Backend                          │
   │ Payload:                            │
   │ - l1_signature (AccountCreation)    │
   │ - registration_signature             │
   │ - registration_time                 │
   │ - registration_host                  │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Backend → Extended API              │
   │ POST /auth/onboard                  │
   │ - Derives L2 key from L1 sig       │
   │ - Creates account on Extended       │
   │ - Sets referral code "ADMIN"       │
   │ - Returns account_id               │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Onboarding Complete ✓               │
   │ Account created on Extended         │
   └──────────────┬──────────────────────┘
                  │
                  ▼
4. API KEY ISSUANCE (Automatic after onboarding)
   ┌─────────────────────────────────────┐
   │ POST /accounts/api-key/prepare      │
   │ → Backend                          │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Backend returns 2 messages:         │
   │ 1. "/api/v1/user/accounts@<time>"   │
   │ 2. "/api/v1/user/account/api-key@<time>"│
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Request Signature #1                │
   │ personalSign(message: accounts)     │
   │ - Auto-opens wallet                 │
   │ - User approves in wallet           │
   │ - Returns signature                 │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Request Signature #2                │
   │ personalSign(message: create_key)   │
   │ - Auto-opens wallet                 │
   │ - User approves in wallet           │
   │ - Returns signature                 │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ POST /accounts/api-key/issue         │
   │ → Backend                          │
   │ Payload:                            │
   │ - accounts_signature                │
   │ - accounts_auth_time                │
   │ - create_signature                  │
   │ - create_auth_time                  │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Backend → Extended API              │
   │ Step 1: GET /user/accounts           │
   │   Headers:                          │
   │   - L1_SIGNATURE: accounts_sig     │
   │   - L1_MESSAGE_TIME: accounts_time  │
   │   → Returns account_id              │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Backend → Extended API              │
   │ Step 2: POST /user/account/api-key   │
   │   Headers:                          │
   │   - L1_SIGNATURE: create_sig       │
   │   - L1_MESSAGE_TIME: create_time    │
   │   - X-X10-ACTIVE-ACCOUNT: account_id│
   │   → Returns API key                 │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Save API Key                        │
   │ - LocalStore.saveApiKey()           │
   │ - Backend.upsertAccount()           │
   │ API Key stored locally & in DB      │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ API Key Ready ✓                     │
   └──────────────┬──────────────────────┘
                  │
                  ▼
5. FETCH BALANCES
   ┌─────────────────────────────────────┐
   │ User clicks "Fetch Balances"         │
   │ OR auto-fetched after onboarding     │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Check for API Key                   │
   │ - Load from LocalStore               │
   │ - If missing: show error            │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ GET /balances                        │
   │ → Backend                          │
   │ Query params:                       │
   │ - wallet_address                    │
   │ - account_index                     │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Backend retrieves API key           │
   │ from database                       │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Backend → Extended API              │
   │ GET /user/balance                    │
   │ Headers:                            │
   │ - X-Api-Key: <user_api_key>         │
   │ → Returns balance data              │
   └──────────────┬──────────────────────┘
                  │
                  ▼
   ┌─────────────────────────────────────┐
   │ Display Balances ✓                  │
   │ Balance data shown in UI            │
   └─────────────────────────────────────┘
```

## Detailed Step Breakdown

### Step 1: Wallet Connect Initialization
- **Location**: `lib/core/wallet_connect.dart` → `WalletService.init()`
- **What happens**:
  - Loads `WC_PROJECT_ID` from environment
  - Creates `Web3App` instance with WalletConnect relay
  - Sets up session event listeners

### Step 2: Connect Wallet
- **Location**: `lib/main.dart` → `_connectWallet()`
- **What happens**:
  - Generates WalletConnect pairing URI
  - Tries wallet-specific deep links (MetaMask, Trust, Rainbow)
  - Falls back to QR code if deep links fail
  - User approves connection in wallet app
  - Session established, wallet address extracted

### Step 3: Onboarding
- **Location**: `lib/main.dart` → `_startOnboarding()`
- **Backend**: `backend/app/routes/onboarding.py`
- **What happens**:
  1. **Start**: Request EIP-712 typed data for two signatures
  2. **Sign #1**: User signs `AccountCreation` typed data (derives L2 key)
  3. **Sign #2**: User signs `AccountRegistration` typed data (registers account)
  4. **Complete**: Backend sends both signatures to Extended API `/auth/onboard`
  5. **Result**: Account created on Extended Exchange with account_id

### Step 4: API Key Issuance
- **Location**: `lib/main.dart` → `_autoIssueApiKey()`
- **Backend**: `backend/app/routes/accounts.py`
- **What happens**:
  1. **Prepare**: Backend generates two messages to sign:
     - `/api/v1/user/accounts@<timestamp>`
     - `/api/v1/user/account/api-key@<timestamp>`
  2. **Sign #1**: User signs accounts message (personal_sign)
  3. **Sign #2**: User signs create key message (personal_sign)
  4. **Issue**: Backend uses signatures to:
     - Fetch account_id from Extended API
     - Create API key via Extended API
  5. **Store**: API key saved locally and in backend database

### Step 5: Fetch Balances
- **Location**: `lib/main.dart` → `_fetchBalances()`
- **Backend**: `backend/app/routes/proxy.py`
- **What happens**:
  1. Load API key from local storage
  2. Backend retrieves API key from database
  3. Backend calls Extended API `/user/balance` with `X-Api-Key` header
  4. Balance data returned and displayed

## Key Components

### Mobile App (Flutter)
- **WalletService**: Manages WalletConnect connection and signatures
- **BackendClient**: HTTP client for backend API calls
- **LocalStore**: Local storage for API keys

### Backend (FastAPI)
- **Onboarding Routes**: Handle account creation
- **Account Routes**: Handle API key issuance
- **Proxy Routes**: Proxy requests to Extended API with authentication

### External APIs
- **WalletConnect Relay**: Manages wallet connections
- **Extended Exchange API**: Main trading API (requires API key)

## Authentication Flow

```
User Wallet (L1)
    │
    │ EIP-712 signatures
    ▼
Extended Exchange
    │
    │ Derives L2 key from L1 signature
    │ Creates account
    │ Issues API key
    ▼
Backend Database
    │
    │ Stores API key
    ▼
Mobile App
    │
    │ Uses API key for authenticated requests
    ▼
Extended Exchange API
```

## Signature Requirements

### Onboarding (2 signatures)
1. **AccountCreation**: EIP-712 typed data → Derives L2 private key
2. **AccountRegistration**: EIP-712 typed data → Registers account

### API Key Issuance (2 signatures)
1. **Accounts message**: Personal sign → Authenticates account access
2. **Create key message**: Personal sign → Authorizes API key creation

## Error Handling

- **Wallet not connected**: Show error, prompt to connect
- **Onboarding failed**: Show error, allow retry
- **API key missing**: Show 401 error, prompt to complete onboarding
- **Network errors**: Show timeout/connection errors
- **App lifecycle**: Handle background/foreground transitions gracefully

## State Management

- **Wallet state**: Managed by `WalletService` (Riverpod provider)
- **UI state**: Managed by `_PortfolioBodyState` (loading flags, balances)
- **API key**: Cached in memory and persisted locally

