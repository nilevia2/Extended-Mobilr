#!/bin/bash
# Railway deployment script for Extended Backend

set -e

echo "🚀 Starting Extended Backend..."

# Install dependencies
echo "📦 Installing Python dependencies..."
pip install -r backend/requirements.txt

# Start the FastAPI server
echo "🌐 Starting FastAPI server..."
exec uvicorn backend.app.main:app --host 0.0.0.0 --port ${PORT:-8080}

