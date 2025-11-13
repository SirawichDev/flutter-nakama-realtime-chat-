#!/bin/bash

set -e

echo "🚀 Starting Nakama with Podman..."

# Check if podman machine is running
if ! podman info > /dev/null 2>&1; then
    echo "❌ Podman machine is not running. Starting it..."
    podman machine start
    sleep 5
fi

# Build custom Nakama image with modules
echo "🔨 Building custom Nakama image..."
podman build -t nakama-with-modules:latest .

# Create network if it doesn't exist
echo "📡 Creating network..."
podman network create nakama-network 2>/dev/null || echo "Network already exists"

# Start CockroachDB
echo "🗄️  Starting CockroachDB..."
podman stop nakama-db 2>/dev/null || true
podman rm nakama-db 2>/dev/null || true
podman run -d --name nakama-db --network nakama-network \
  -p 26257:26257 -p 8080:8080 \
  cockroachdb/cockroach:latest start-single-node --insecure

echo "⏳ Waiting for database to be ready..."
sleep 5

# Create database
echo "📦 Creating database..."
podman exec nakama-db cockroach sql --insecure -e "CREATE DATABASE IF NOT EXISTS nakama;" 2>/dev/null || sleep 3 && podman exec nakama-db cockroach sql --insecure -e "CREATE DATABASE IF NOT EXISTS nakama;"

# Create data directories
mkdir -p data
mkdir -p data/minio

# Start Minio
echo "🗃️  Starting Minio..."
podman stop nakama-minio 2>/dev/null || true
podman rm nakama-minio 2>/dev/null || true
podman run -d --name nakama-minio --network nakama-network \
  -p 9000:9000 -p 9001:9001 \
  -v $(pwd)/data/minio:/data \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  minio/minio:latest server /data --console-address ":9001"

echo "⏳ Waiting for Minio to be ready..."
sleep 5

# Run database migrations first
echo "🔄 Running database migrations..."
podman run --rm --user root --network nakama-network \
  -e NAKAMA_DATABASE_URL="postgres://root@nakama-db:26257/nakama?sslmode=disable" \
  nakama-with-modules:latest migrate up --database.address nakama-db:26257

# Start Nakama with proper config
echo "🎮 Starting Nakama server..."
podman stop nakama-server 2>/dev/null || true
podman rm nakama-server 2>/dev/null || true

# Use config file with proper database address and --config flag
# Note: Not mounting data directory because modules are already built into the image
podman run -d --user root --name nakama-server --network nakama-network \
  -p 7349:7349 -p 7350:7350 -p 7351:7351 \
  -e NAKAMA_DATABASE_URL="postgres://root@nakama-db:26257/nakama?sslmode=disable" \
  -e MINIO_ENDPOINT=nakama-minio:9000 \
  -e MINIO_ACCESS_KEY=minioadmin \
  -e MINIO_SECRET_KEY=minioadmin \
  -e MINIO_USE_SSL=false \
  -e MINIO_BUCKET=chat-images \
  nakama-with-modules:latest --config /nakama/local.yml --database.address nakama-db:26257

echo "⏳ Waiting for Nakama to start..."
sleep 10

# Check status
if podman ps | grep -q nakama-server; then
    echo "✅ Nakama server is running!"
    echo "📊 Check logs with: podman logs nakama-server"
    echo "🌐 Server URL: http://127.0.0.1:7350"
    echo "📝 Console: http://127.0.0.1:7351 (admin/password)"
    echo "🗃️  Minio Console: http://127.0.0.1:9001 (minioadmin/minioadmin)"
    echo "🔗 Minio API: http://127.0.0.1:9000"
else
    echo "❌ Nakama server failed to start. Check logs:"
    podman logs nakama-server 2>&1 | tail -10
    exit 1
fi

