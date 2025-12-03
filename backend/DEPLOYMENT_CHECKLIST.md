# Backend Deployment Checklist

## ✅ Pre-Deployment Review

### Security
- ✅ No private keys logged (Stark keys are never printed)
- ✅ API keys only partially logged (first 8 chars for verification)
- ✅ Sensitive data stored securely (in-memory or database)
- ⚠️ **CORS**: Not configured - add if mobile app needs CORS headers

### Functionality
- ✅ Order signing with Stark keys working
- ✅ Vault storage and retrieval working
- ✅ Price/quantity rounding to market precision
- ✅ Partial fill handling (mobile app side)
- ✅ Error handling with detailed messages
- ✅ Fallback to market stats if orderbook empty

### Configuration
- ✅ Environment variables:
  - `EXTENDED_ENV` (default: `mainnet`, or `testnet`)
  - `REFERRAL_CODE` (optional)
  - `DATABASE_URL` or `DB_URL` (optional, falls back to memory store)

### Dependencies
- ✅ All dependencies in `requirements.txt`
- ✅ Python version: 3.10+ (for type hints)

## 🚀 Deployment Steps

### 1. Environment Setup
```bash
# Set environment variables
export EXTENDED_ENV=mainnet  # or testnet
export REFERRAL_CODE=your_code  # optional
export DATABASE_URL=postgresql+psycopg://user:pass@host:5432/dbname  # optional
```

### 2. Install Dependencies
```bash
pip install -r requirements.txt
```

### 3. Run Server
```bash
# Development
uvicorn backend.app.main:app --reload --port 8080

# Production (with gunicorn)
gunicorn backend.app.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8080
```

### 4. Health Check
```bash
curl http://localhost:8080/docs  # Should show FastAPI docs
```

## 📝 Notes

- **Storage**: Uses in-memory store by default. Set `DATABASE_URL` for persistent storage.
- **Logging**: All logs go to stdout/stderr. Configure logging in production.
- **CORS**: Add CORS middleware if mobile app needs it:
  ```python
  from fastapi.middleware.cors import CORSMiddleware
  app.add_middleware(CORSMiddleware, allow_origins=["*"])
  ```

## 🔍 Testing

Test endpoints:
- `POST /onboarding/start` - Start onboarding
- `POST /onboarding/complete` - Complete onboarding
- `POST /accounts/api-key/issue` - Issue API key
- `POST /orders/create-and-place` - Create and place order

## ⚠️ Production Considerations

1. **Database**: Use PostgreSQL for persistent storage (set `DATABASE_URL`)
2. **Rate Limiting**: Consider adding rate limiting middleware
3. **Monitoring**: Add logging/monitoring (e.g., Sentry)
4. **HTTPS**: Use HTTPS in production
5. **Secrets**: Store sensitive data in environment variables or secret manager

