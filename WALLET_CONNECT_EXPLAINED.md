# WalletConnect vs API Key - Why Reconnect?

## The Confusion

You're right to be confused! Here's what's happening:

### Two Different Things:

1. **WalletConnect Session** (Temporary)
   - Used for: Signing messages, connecting to your wallet
   - Persists: **NO** - Lost when app closes
   - Purpose: Active communication with wallet app

2. **API Key** (Permanent)
   - Used for: Accessing Extended Exchange API
   - Persists: **YES** - Stored encrypted locally
   - Purpose: Authentication with Extended Exchange

## Why You Need to Reconnect Wallet?

### When App Restarts:

1. **WalletConnect session is lost** (by design - it's temporary)
2. **API key is still there** (stored locally, encrypted)
3. **App shows "Connect Wallet"** because WalletConnect session is gone

### But You Don't Actually Need to Reconnect!

**You can use the app WITHOUT reconnecting the wallet:**

- ✅ **Fetch balances** - Works with API key only
- ✅ **View account info** - Works with API key only  
- ✅ **Read-only operations** - All work with API key only

**You only need wallet connection for:**
- ⚠️ **Placing orders** - Needs wallet signatures (for now, until we implement client-side signing)
- ⚠️ **Onboarding new accounts** - Needs wallet signatures
- ⚠️ **Issuing new API keys** - Needs wallet signatures

## Current Behavior

### App Restart Flow:

```
App Starts
    ↓
Check: Is WalletConnect connected? → NO (session lost)
    ↓
Show: "Connect Wallet" button
    ↓
BUT ALSO:
Check: Is API key stored locally? → YES
    ↓
Show: "API Key Mode: 0x..." (read-only mode)
    ↓
User can fetch balances WITHOUT reconnecting wallet!
```

## The Two Modes

### Mode 1: Full Mode (Wallet Connected)
- WalletConnect session active
- Can sign messages
- Can place orders
- Can onboard new accounts

### Mode 2: Read-Only Mode (API Key Only)
- No WalletConnect session
- API key stored locally
- Can fetch balances
- Can view account info
- **Cannot** place orders (needs signatures)

## Why This Design?

### WalletConnect Sessions Are Temporary By Design:

1. **Security**: Sessions expire for security
2. **Privacy**: Not stored permanently
3. **Wallet Control**: Wallet app controls the session

### API Keys Are Permanent:

1. **Convenience**: Don't need to reconnect every time
2. **Read Access**: Can check balances without wallet
3. **Stored Securely**: Encrypted in secure storage

## What Happens When You Reconnect?

When you reconnect wallet after app restart:

1. **New WalletConnect session** created
2. **API key is still there** (no need to re-onboard)
3. **App syncs** - Checks if API key matches connected wallet
4. **Full functionality** restored

## Summary

**You're right - you already have everything!**

- ✅ API key is stored (encrypted)
- ✅ You can use the app in read-only mode
- ✅ No need to reconnect unless you want to place orders

**The "Connect Wallet" button is optional:**
- Click it → Full mode (can place orders)
- Don't click it → Read-only mode (can view balances)

The app should make this clearer! Currently it shows "Connect Wallet" but you can still use it with just the API key.

