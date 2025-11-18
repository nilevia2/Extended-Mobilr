# Ready to Run Checklist

## ✅ Flutter App - READY

- ✅ All dependencies installed (`flutter pub get` successful)
- ✅ `ExtendedClient` imported and used correctly
- ✅ Environment file configured (`assets/env`)
- ✅ No lint errors
- ✅ All imports resolved

**To run Flutter app:**
```bash
cd mobile/extended_mobile
flutter run
```

## ⚠️ Backend - Needs Dependencies Installed

The backend code is ready, but Python dependencies need to be installed.

**To set up backend:**

1. **Install dependencies:**
   ```bash
   cd backend
   python3 -m venv .venv  # if not already created
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. **Create `.env` file (optional, for referral code):**
   ```bash
   cd backend
   cp .env.example .env
   # Edit .env and set REFERRAL_CODE=your_code if needed
   ```

3. **Run backend:**
   ```bash
   uvicorn backend.app.main:app --reload --port 8080
   ```

## Configuration Files

### Backend `.env` (optional)
- Location: `backend/.env`
- Purpose: Set `REFERRAL_CODE` environment variable
- Template: `backend/.env.example`

### Flutter `assets/env`
- Location: `mobile/extended_mobile/assets/env`
- Contains:
  - `API_BASE_URL` - Backend URL (currently `http://10.165.69.68:8080`)
  - `EXTENDED_PUBLIC_BASE_URL` - Extended API URL
  - `WC_PROJECT_ID` - WalletConnect project ID
  - `WC_EVM_CHAIN_ID` - EVM chain ID

## Quick Start

1. **Start Backend:**
   ```bash
   cd backend
   source .venv/bin/activate  # or your venv activation
   uvicorn backend.app.main:app --reload --port 8080
   ```

2. **Start Flutter App:**
   ```bash
   cd mobile/extended_mobile
   flutter run
   ```

## What's Working

- ✅ Wallet connection via WalletConnect
- ✅ Onboarding flow (with referral code from backend)
- ✅ API key issuance
- ✅ Direct Extended API calls for balances/account info
- ✅ Encrypted local storage for API keys and Stark keys
- ✅ Auto-load balances on app start
- ✅ Error handling with user-friendly messages

## What's Pending

- ⚠️ Client-side Stark signature for orders (still uses backend for signing)
- ✅ Everything else is ready!

