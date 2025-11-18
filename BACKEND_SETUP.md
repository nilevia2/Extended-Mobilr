# Backend Setup Guide - Local Development

## Quick Start

### Option 1: ADB Reverse Tunneling (Recommended for Android)

This method forwards your Mac's `localhost:8080` to your Android device's `localhost:8080`, bypassing VPN issues.

#### Step 1: Start Backend on Mac

```bash
cd backend
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install -r requirements.txt  # if not already installed
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

**Important**: Use `--host 0.0.0.0` so it listens on all interfaces, not just localhost.

#### Step 2: Connect Android Device via USB

```bash
# Check if device is connected
adb devices

# Should show your device, e.g.:
# List of devices attached
# ABC123XYZ    device
```

#### Step 3: Forward Port 8080

```bash
# Forward Mac's localhost:8080 to device's localhost:8080
adb reverse tcp:8080 tcp:8080

# Verify it worked
adb reverse --list
# Should show: tcp:8080 tcp:8080
```

#### Step 4: Configure Mobile App

Edit `mobile/extended_mobile/assets/env`:
```
API_BASE_URL=http://localhost:8080
```

#### Step 5: Test Connection

```bash
# From your Mac, test if backend is accessible
curl http://localhost:8080/onboarding/referral-code

# Should return JSON with referral_code
```

#### Step 6: Run Flutter App

```bash
cd mobile/extended_mobile
flutter run
```

**Benefits**:
- ✅ Works even with VPN ON (localhost bypasses VPN)
- ✅ No need to find your Mac's IP address
- ✅ Works with emulator and physical device
- ✅ Backend stays on Mac (no need to deploy)

---

### Option 2: Local Network IP (Alternative)

If ADB reverse doesn't work, use your Mac's local network IP.

#### Step 1: Find Your Mac's IP Address

```bash
# On Mac
ifconfig | grep "inet " | grep -v 127.0.0.1

# Or use this command:
ipconfig getifaddr en0  # For WiFi
ipconfig getifaddr en1  # For Ethernet

# Example output: 192.168.1.100
```

#### Step 2: Start Backend

```bash
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

**Important**: Must use `--host 0.0.0.0` to listen on all interfaces.

#### Step 3: Configure Mobile App

Edit `mobile/extended_mobile/assets/env`:
```
API_BASE_URL=http://192.168.1.100:8080
```

Replace `192.168.1.100` with your Mac's actual IP.

#### Step 4: Ensure Same Network

- Mac and mobile device must be on the **same WiFi network**
- If using VPN, ensure it doesn't block local network traffic
- Some VPNs isolate devices - disable VPN if needed

#### Step 5: Test Connection

```bash
# From Mac, test backend
curl http://localhost:8080/onboarding/referral-code

# From mobile device browser (if possible), test:
# http://192.168.1.100:8080/onboarding/referral-code
```

#### Step 6: Run Flutter App

```bash
cd mobile/extended_mobile
flutter run
```

**Limitations**:
- ⚠️ Requires same WiFi network
- ⚠️ VPN may block local network
- ⚠️ IP address changes if you reconnect to WiFi

---

### Option 3: ngrok (For Testing Across Networks)

If you need to test from a different network or share with others.

#### Step 1: Install ngrok

```bash
# Download from https://ngrok.com/download
# Or via Homebrew:
brew install ngrok
```

#### Step 2: Start Backend

```bash
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

#### Step 3: Create ngrok Tunnel

```bash
ngrok http 8080
```

**Output**:
```
Forwarding  https://abc123.ngrok.io -> http://localhost:8080
```

#### Step 4: Configure Mobile App

Edit `mobile/extended_mobile/assets/env`:
```
API_BASE_URL=https://abc123.ngrok.io
```

**Limitations**:
- ⚠️ Free tier has request limits
- ⚠️ URL changes each time you restart ngrok
- ⚠️ Requires internet connection

---

## Troubleshooting

### Backend Not Starting

```bash
# Check if port 8080 is already in use
lsof -i :8080

# Kill process if needed
kill -9 <PID>

# Or use a different port
uvicorn app.main:app --reload --host 0.0.0.0 --port 8081
```

### ADB Reverse Not Working

```bash
# Check ADB connection
adb devices

# Restart ADB server
adb kill-server
adb start-server

# Try reverse again
adb reverse tcp:8080 tcp:8080

# Check if it's active
adb reverse --list
```

### Connection Timeout in App

1. **Check backend is running**:
   ```bash
   curl http://localhost:8080/onboarding/referral-code
   ```

2. **Check firewall**:
   ```bash
   # Mac: System Settings > Network > Firewall
   # Allow incoming connections for Python/uvicorn
   ```

3. **Check VPN**:
   - Disable VPN temporarily to test
   - Some VPNs block localhost/private IPs

4. **Check network**:
   - Ensure Mac and device on same WiFi
   - Try pinging Mac IP from device (if possible)

### "Cannot reach backend" Error

1. **Verify backend URL in `assets/env`**:
   ```
   API_BASE_URL=http://localhost:8080  # For ADB reverse
   # OR
   API_BASE_URL=http://192.168.1.100:8080  # For local network IP
   ```

2. **Test backend directly**:
   ```bash
   curl http://localhost:8080/onboarding/referral-code
   ```

3. **Check backend logs**:
   - Should see requests coming in when app tries to connect
   - If no logs, backend isn't receiving requests

4. **Restart Flutter app**:
   ```bash
   # Hot restart (r in terminal)
   # Or full restart
   flutter run
   ```

---

## Recommended Setup for Development

**Best Practice**: Use **ADB Reverse Tunneling**

1. ✅ Start backend: `uvicorn app.main:app --reload --host 0.0.0.0 --port 8080`
2. ✅ Connect device: `adb devices`
3. ✅ Forward port: `adb reverse tcp:8080 tcp:8080`
4. ✅ Set env: `API_BASE_URL=http://localhost:8080`
5. ✅ Run app: `flutter run`

**Why ADB Reverse?**
- Works with VPN ON (localhost bypasses VPN)
- No IP address management
- Works with emulator and physical device
- Simple and reliable

---

## Environment Variables

### Backend `.env` (Optional)

Create `backend/.env`:
```
EXTENDED_ENV=testnet
REFERRAL_CODE=ADMIN
```

### Mobile `assets/env`

```
API_BASE_URL=http://localhost:8080
EXTENDED_PUBLIC_BASE_URL=https://starknet.app.extended.exchange/api/v1
WC_PROJECT_ID=dc4fcfe4bd21d90a26bd7ce7b8e78d85
WC_EVM_CHAIN_ID=1
```

---

## Quick Reference Commands

```bash
# Start backend
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080

# ADB reverse (in new terminal)
adb reverse tcp:8080 tcp:8080

# Run Flutter app (in new terminal)
cd mobile/extended_mobile
flutter run

# Test backend
curl http://localhost:8080/onboarding/referral-code
```

---

## Next Steps

After backend is accessible:
1. Connect wallet in app
2. Auto-onboarding should trigger
3. Signatures will be requested
4. API key will be issued automatically
5. Balances will load automatically

