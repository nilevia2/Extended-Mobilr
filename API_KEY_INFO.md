# API Key Information

## API Key Expiry

**Based on Extended Exchange API documentation review:**

**API keys do NOT expire.** They are permanent credentials that remain valid until:
- The user manually revokes/regenerates them via the Extended Exchange UI
- The account is deleted

There is no expiration date or expiry mechanism mentioned in the Extended API documentation. API keys are long-lived credentials that should be stored securely.

## What You Need: Just the API Key

After the complete onboarding flow, you only need to store:
- **User's API Key** - This is the only credential needed to authenticate with Extended Exchange API

The API key is:
- Generated during the API key issuance flow (after onboarding)
- Stored locally in the mobile app
- Synced to the backend database
- Used in the `X-Api-Key` header for all authenticated API requests

## Referral Code Configuration

The referral code is now configurable via environment variables:

### Mobile App (`mobile/extended_mobile/assets/env`)
```env
REFERRAL_CODE=ADMIN
```

### Backend (set as environment variable)
```bash
export REFERRAL_CODE=ADMIN
```

Or in your backend `.env` file:
```env
REFERRAL_CODE=ADMIN
```

The referral code is set during onboarding and cannot be changed afterward (it's part of the account creation). To use a different referral code, you need to change it in the env file before onboarding.

## Auto-Onboarding Flow

The app now automatically handles onboarding:

1. **User connects wallet** → WalletConnect session established
2. **Auto-check**: App checks if API key exists for this wallet
3. **If no API key**:
   - Automatically starts onboarding (no manual button click needed)
   - User signs 2 EIP-712 signatures (AccountCreation, AccountRegistration)
   - Account created on Extended Exchange
   - API key automatically issued (2 more signatures)
   - User is ready to use Extended API
4. **If API key exists**:
   - Syncs API key to backend
   - User is immediately ready to use Extended API

## Summary

- ✅ **API keys do NOT expire** - they're permanent
- ✅ **Only need to store the API key** - that's the only credential
- ✅ **Referral code configurable** - set via `REFERRAL_CODE` env variable
- ✅ **Auto-onboarding** - happens automatically after wallet connection

