# Backend vs Direct Extended API - Current Status

## ✅ **NO BACKEND NEEDED** (Direct Extended API)

### 1. **Get Balance** ✅
- **Current**: Uses `ExtendedClient.getBalances()` → Direct to Extended API
- **Needs**: Only API key (stored locally)
- **VPN**: ✅ Works with VPN ON (Extended API accessible)

### 2. **Get Account Info** ✅
- **Current**: Uses `ExtendedClient.getAccountInfo()` → Direct to Extended API  
- **Needs**: Only API key (stored locally)
- **VPN**: ✅ Works with VPN ON

### 3. **Get Positions** ✅ (if implemented)
- Would use `ExtendedClient.getPositions()` → Direct to Extended API
- **VPN**: ✅ Works with VPN ON

### 4. **Get Orders** ✅ (if implemented)
- Would use `ExtendedClient.getOrders()` → Direct to Extended API
- **VPN**: ✅ Works with VPN ON

---

## ⚠️ **REQUIRES BACKEND** (VPN Issue!)

### 1. **Onboarding** ⚠️
- **Current**: `BackendClient.onboardingStart()` → Backend → Extended API
- **Why Backend**: 
  - Derives Stark private/public keys from L1 signature (crypto operation)
  - Signs L2 message with Stark key
  - Calls Extended `/auth/onboard`
- **VPN**: ❌ Needs VPN ON for Extended API, but VPN blocks localhost backend
- **Solution**: Use local network IP (already set: `10.165.69.68:8080`)

### 2. **API Key Issuance** ⚠️
- **Current**: `BackendClient.apiKeyPrepare()` + `apiKeyIssue()` → Backend → Extended API
- **Why Backend**:
  - Prepares L1 signature messages
  - Calls Extended `/user/accounts` with L1 signature headers
  - Calls Extended `/user/account/api-key` with L1 signature headers
- **VPN**: ❌ Needs VPN ON for Extended API, but VPN blocks localhost backend
- **Solution**: Use local network IP (already set: `10.165.69.68:8080`)

### 3. **Get Referral Code** ⚠️
- **Current**: `BackendClient.getReferralCode()` → Backend endpoint
- **Why Backend**: Reads from backend `.env` file
- **VPN**: ❌ VPN blocks localhost backend
- **Solution**: Could be moved to mobile config, or use local network IP

### 4. **Place Orders** ⚠️
- **Current**: `BackendClient.createAndPlaceOrder()` → Backend → Extended API
- **Why Backend**: Signs orders with Stark private key (crypto operation)
- **VPN**: ❌ Needs VPN ON for Extended API, but VPN blocks localhost backend
- **Solution**: Use local network IP, or implement client-side signing

---

## 🔧 **VPN Issue Solutions**

### Current Setup
Your `assets/env` already uses local network IP:
```
API_BASE_URL=http://10.165.69.68:8080
```

### Problem
- **VPN ON**: Can reach Extended API ✅, but VPN blocks `10.165.69.68` ❌
- **VPN OFF**: Can reach backend ✅, but can't reach Extended API ❌

### Solutions

#### Option 1: **Use ADB Reverse Tunneling** (Recommended)
```bash
# Forward localhost:8080 to device
adb reverse tcp:8080 tcp:8080
```
Then set `API_BASE_URL=http://localhost:8080` in mobile app
- Backend runs on Mac `localhost:8080`
- ADB forwards to device's `localhost:8080`
- VPN doesn't interfere with localhost

#### Option 2: **Deploy Backend to Cloud**
- Deploy backend to a server accessible with VPN
- Update `API_BASE_URL` to cloud URL
- All operations work with VPN ON

#### Option 3: **Split Operations**
- **With VPN ON**: Use direct Extended API (balances, account info) ✅
- **With VPN OFF**: Use backend for onboarding/API key (one-time setup)
- After onboarding, most operations don't need backend!

---

## 📊 **Summary Table**

| Operation | Backend Needed? | VPN Required? | Current Status |
|-----------|----------------|---------------|----------------|
| **Get Balance** | ❌ No | ✅ Yes (Extended API) | ✅ Direct API |
| **Get Account Info** | ❌ No | ✅ Yes (Extended API) | ✅ Direct API |
| **Onboarding** | ✅ Yes | ✅ Yes (Extended API) | ⚠️ Backend |
| **API Key Issuance** | ✅ Yes | ✅ Yes (Extended API) | ⚠️ Backend |
| **Get Referral Code** | ✅ Yes | ❌ No | ⚠️ Backend |
| **Place Orders** | ✅ Yes | ✅ Yes (Extended API) | ⚠️ Backend |

---

## 💡 **Recommendation**

**Best approach for VPN issues:**

1. **Use ADB reverse tunneling** for development
   - Backend on `localhost:8080` (Mac)
   - ADB forwards to device
   - VPN doesn't block localhost

2. **After onboarding, most operations are direct!**
   - Once user has API key, balances/account info work directly
   - Only orders need backend (for now)

3. **Future**: Move order signing client-side
   - Then only onboarding/API key need backend
   - Can be done once, then everything is direct

