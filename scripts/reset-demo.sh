#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

cd "$DEMO_DIR"

echo "Resetting FinTech Demo Environment..."
echo ""

# Stop all containers
echo "Stopping containers..."
docker-compose down -v

# Remove images to force rebuild
echo "Removing images..."
docker-compose down --rmi local

# Clean up volumes
echo "Cleaning volumes..."
docker volume prune -f

echo ""
echo "Reset complete! Run './scripts/start-demo.sh' to start fresh."
