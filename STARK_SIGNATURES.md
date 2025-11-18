# Stark Signatures - Server-Side Signing

## Overview

**Stark signatures are already handled server-side!** Users do NOT need to sign every order.

## How It Works

### During Onboarding
1. User signs **one-time** L1 signature (EIP-712) for account creation
2. Backend derives **Stark private key** from L1 signature using `fast_stark_crypto`
3. Backend stores Stark private key securely in database
4. Stark private key is **never sent to mobile app**

### During Order Placement
1. Mobile app sends order request to backend (no signatures needed)
2. Backend retrieves stored Stark private key from database
3. Backend signs order using `build_signed_limit_order_json()` function
4. Backend submits signed order to Extended Exchange API
5. User never sees signature prompts for orders!

## Code Flow

### Backend Order Signing (`backend/app/routes/orders.py`)
```python
@router.post("/create-and-place")
def create_and_place_order(payload: CreateAndPlaceOrderRequest):
    # Get user record with stored Stark keys
    record = STORE.get_user(...)
    
    # Sign order server-side using stored Stark private key
    order_json = build_signed_limit_order_json(
        api_key=record.api_key,
        stark_private_key_hex=record.stark_private_key,  # From database
        stark_public_key_hex=record.stark_public_key,     # From database
        vault=int(record.vault),
        # ... order parameters
    )
    
    # Submit signed order
    return client.post_private(record.api_key, "/user/order", json=order_json)
```

### Mobile App (`mobile/extended_mobile/lib/main.dart`)
```dart
// User just calls backend - no signatures needed!
final res = await api.createAndPlaceOrder(
  walletAddress: address,
  accountIndex: 0,
  market: 'BTC-USD',
  qty: 0.1,
  price: 50000,
  side: 'BUY',
);
// Order is automatically signed server-side!
```

## Security

- **Stark private key**: Stored securely in backend database, never exposed to mobile
- **L1 wallet**: Only needed for initial onboarding (one-time signature)
- **API key**: Used for authentication, stored locally in mobile app
- **Orders**: Signed automatically server-side, no user interaction needed

## Summary

✅ **Stark signatures are one-time** - derived during onboarding  
✅ **Stored server-side** - never sent to mobile app  
✅ **Orders signed automatically** - no user signatures needed  
✅ **Better UX** - users can place orders without wallet connection after onboarding  

The only signatures users need to provide are:
- **2 EIP-712 signatures** during onboarding (AccountCreation, AccountRegistration)
- **2 personal_sign signatures** for API key issuance

After that, all orders are signed server-side automatically!

