# Testing Backend from Phone Browser

## Quick Test URLs

Since you're using **ADB reverse tunneling**, your phone can access the backend via `localhost:8080`.

### Open These URLs in Your Phone's Browser:

1. **Referral Code Endpoint** (Public, no auth needed):
   ```
   http://localhost:8080/onboarding/referral-code
   ```
   **Expected Response**: `{"referral_code":""}` or `{"referral_code":"ADMIN"}`

2. **API Documentation** (FastAPI auto-generated):
   ```
   http://localhost:8080/docs
   ```
   **Expected**: Interactive API documentation page

3. **Alternative Docs** (ReDoc format):
   ```
   http://localhost:8080/redoc
   ```
   **Expected**: Alternative API documentation

4. **OpenAPI JSON**:
   ```
   http://localhost:8080/openapi.json
   ```
   **Expected**: JSON schema of all API endpoints

---

## Step-by-Step Test

### On Your Phone:

1. **Open any browser** (Chrome, Safari, etc.)

2. **Type in address bar**:
   ```
   http://localhost:8080/onboarding/referral-code
   ```

3. **Expected Result**:
   - ✅ **Success**: You see `{"referral_code":""}` or `{"referral_code":"ADMIN"}`
   - ❌ **Failure**: "This site can't be reached" or timeout

### If It Works:

✅ Backend is accessible from phone  
✅ ADB reverse is working correctly  
✅ Flutter app should be able to connect  

### If It Doesn't Work:

1. **Check ADB reverse is active**:
   ```bash
   adb reverse --list
   # Should show: UsbFfs tcp:8080 tcp:8080
   ```

2. **Restart ADB reverse**:
   ```bash
   adb reverse --remove-all
   adb reverse tcp:8080 tcp:8080
   ```

3. **Check backend is running**:
   ```bash
   curl http://localhost:8080/onboarding/referral-code
   # Should return JSON
   ```

4. **Check backend is listening on 0.0.0.0**:
   ```bash
   # Backend should be started with:
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
   # NOT: --host 127.0.0.1 (this won't work)
   ```

---

## Testing Other Endpoints

### Public Endpoints (No Auth):

- `GET /onboarding/referral-code` - Get referral code
- `GET /docs` - API documentation
- `GET /openapi.json` - OpenAPI schema

### Private Endpoints (Need Auth):

These require API keys or signatures, so they won't work from browser directly:
- `POST /onboarding/start` - Needs wallet address
- `POST /onboarding/complete` - Needs signatures
- `GET /balances` - Needs API key

---

## Troubleshooting

### "This site can't be reached"

**Possible causes**:
1. Backend not running
2. ADB reverse not active
3. Wrong URL (should be `localhost:8080`, not `127.0.0.1:8080`)

**Fix**:
```bash
# Check backend is running
curl http://localhost:8080/onboarding/referral-code

# Restart ADB reverse
adb reverse --remove-all
adb reverse tcp:8080 tcp:8080

# Verify
adb reverse --list
```

### Timeout

**Possible causes**:
1. Backend crashed
2. Port conflict
3. Firewall blocking

**Fix**:
```bash
# Check if port is in use
lsof -i :8080

# Restart backend
# Kill existing process if needed
kill -9 <PID>

# Start backend again
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

### Wrong Response

If you see a different website or error:
- Make sure you're using `http://localhost:8080` (not `https://`)
- Make sure backend is actually running
- Check backend logs for errors

---

## Quick Test Checklist

- [ ] Backend running: `curl http://localhost:8080/onboarding/referral-code` works
- [ ] ADB reverse active: `adb reverse --list` shows `tcp:8080 tcp:8080`
- [ ] Phone browser can access: `http://localhost:8080/onboarding/referral-code`
- [ ] Phone browser can access: `http://localhost:8080/docs`
- [ ] Flutter app can connect (check logs)

---

## Next Steps

Once browser test works:
1. ✅ Backend is accessible
2. ✅ ADB reverse is working
3. ✅ Flutter app should connect automatically
4. ✅ Try connecting wallet in app
5. ✅ Auto-onboarding should trigger

