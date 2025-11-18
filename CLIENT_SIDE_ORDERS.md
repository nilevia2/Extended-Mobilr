# Client-Side Order Signing - Implementation Status

## ✅ Completed

1. **Stark Keys Stored Locally (Encrypted)**
   - Stark private key stored in `flutter_secure_storage` (encrypted)
   - Stark public key stored in `flutter_secure_storage` (encrypted)
   - Vault ID stored in regular SharedPreferences (not sensitive)
   - Keys fetched from backend during onboarding and stored locally

2. **Direct Extended API Client**
   - Created `ExtendedClient` class for direct API calls
   - Balances fetched directly from Extended API (no backend)
   - Account info fetched directly from Extended API
   - Ready for direct order submission

3. **Reduced Backend Dependency**
   - Balances: ✅ Direct to Extended API
   - Account Info: ✅ Direct to Extended API
   - Orders: ⚠️ Still needs Stark signing implementation

## ⚠️ TODO: Client-Side Stark Signature

**Current Status**: Orders still require backend for signing (temporary)

**What's Needed**:
- Implement Pedersen hash computation in Dart
- Implement Stark signature algorithm (ECDSA-like on Stark curve)
- Build order payload with proper settlement data
- Sign order hash with Stark private key

**Options**:
1. **Use FFI (Foreign Function Interface)** to call native crypto libraries
   - Wrap `fast_stark_crypto` Rust library via FFI
   - Requires native code compilation

2. **Implement in Dart** (complex)
   - Pedersen hash: ~2000 lines of crypto code
   - Stark signature: ECDSA variant on Stark curve
   - High complexity, potential bugs

3. **Use Platform Channels** (recommended for now)
   - Call native code (Swift/Kotlin) that uses existing crypto libraries
   - Medium complexity, more maintainable

4. **Temporary: Optimized Backend Signing**
   - Keep backend signing but optimize it
   - Use connection pooling, caching
   - Still faster than current implementation

## Current Flow

### Balances (✅ Direct)
```
Mobile App
    ↓
ExtendedClient.getBalances(apiKey)
    ↓
Extended API /user/balance
    ↓
Balances returned
```

### Orders (⚠️ Needs Signing)
```
Mobile App
    ↓
[Need: Sign order with Stark private key]
    ↓
ExtendedClient.placeOrder(apiKey, signedOrder)
    ↓
Extended API /user/order
    ↓
Order placed
```

## Recommendation

**Short-term**: Keep backend signing but optimize it
- Backend can cache market data
- Backend can reuse connections
- Backend can batch operations

**Long-term**: Implement client-side signing
- Use FFI to wrap `fast_stark_crypto` Rust library
- Or use platform channels to call native crypto
- Provides best UX (no backend dependency)

## Files Ready for Client-Side Signing

- ✅ `ExtendedClient` - Direct API client ready
- ✅ `LocalStore.saveStarkKeys()` - Stores keys encrypted
- ✅ `LocalStore.loadStarkKeys()` - Loads keys for signing
- ⚠️ Need: Stark signature implementation

## Next Steps

1. Research Dart/Flutter Stark crypto libraries
2. Or implement FFI wrapper for `fast_stark_crypto`
3. Or use platform channels for native crypto
4. Implement order payload construction
5. Test client-side order signing

