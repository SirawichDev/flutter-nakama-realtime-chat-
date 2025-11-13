#!/bin/bash

set -e

echo "🛑 Stopping all Nakama services..."

# Stop containers
echo "Stopping Nakama server..."
podman stop nakama-server 2>/dev/null || echo "Nakama server not running"
podman rm nakama-server 2>/dev/null || echo "Nakama server container removed"

echo "Stopping Minio..."
podman stop nakama-minio 2>/dev/null || echo "Minio not running"
podman rm nakama-minio 2>/dev/null || echo "Minio container removed"

echo "Stopping CockroachDB..."
podman stop nakama-db 2>/dev/null || echo "CockroachDB not running"
podman rm nakama-db 2>/dev/null || echo "CockroachDB container removed"

echo "✅ All services stopped!"




