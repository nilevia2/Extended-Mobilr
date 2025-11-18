# Order Flow - Backend Signing

## Yes, All Orders Go Through Backend

**Every order is submitted through our backend**, which handles Stark signature generation automatically.

## Flow

```
Mobile App
    ↓
User creates order (no signatures needed)
    ↓
POST /orders/create-and-place → Backend
    ↓
Backend retrieves stored Stark private key from database
    ↓
Backend signs order using build_signed_limit_order_json()
    ↓
Backend submits signed order to Extended Exchange API
    ↓
Order placed successfully
```

## Why Backend Signing?

1. **Security**: Stark private key never leaves backend
2. **UX**: Users don't need to sign every order
3. **Simplicity**: Mobile app just sends order parameters
4. **Reliability**: Backend handles all signature complexity

## Mobile App Changes

- ✅ **Removed manual API key input** - API keys are auto-generated during onboarding
- ✅ **Encrypted storage** - API keys stored using `flutter_secure_storage` (encrypted)
- ✅ **Auto-load balances** - Automatically loads balances when app opens if API key exists
- ✅ **Error handling** - Shows "Error, try to login again" toast and disconnects wallet if API key fails

## Security

- **API Key**: Encrypted in secure storage (Keychain on iOS, EncryptedSharedPreferences on Android)
- **Stark Private Key**: Stored only in backend database, never sent to mobile
- **Orders**: Signed server-side, mobile never sees private keys

