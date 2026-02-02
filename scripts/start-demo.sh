#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

cd "$DEMO_DIR"

SCENARIO="${1:-}"

echo "========================================"
echo "  FinTech Demo Environment"
echo "========================================"
echo ""

# Auto-generate .env from nodes.json if nodes.json exists
if [ -f "$DEMO_DIR/nodes.json" ]; then
    if [ ! -f "$DEMO_DIR/.env" ] || [ "$DEMO_DIR/nodes.json" -nt "$DEMO_DIR/.env" ]; then
        echo "Generating .env from nodes.json..."
        "$SCRIPT_DIR/generate-env.sh"
    fi
fi

# Build base images
echo "Building Docker images..."
docker-compose build

# Start based on scenario
if [ -n "$SCENARIO" ]; then
    case "$SCENARIO" in
        memory-leak)
            echo "Starting with MEMORY LEAK scenario..."
            docker-compose -f docker-compose.yml -f docker-compose.memory-leak.yml up -d
            echo ""
            echo "Scenario: Memory Leak in Account Service"
            echo "- Memory grows 5MB/min until OOM (256MB limit)"
            echo "- Hit /api/accounts/accounts/:id/balance to trigger"
            ;;
        db-exhaustion)
            echo "Starting with DB CONNECTION EXHAUSTION scenario..."
            docker-compose -f docker-compose.yml -f docker-compose.db-exhaustion.yml up -d
            echo ""
            echo "Scenario: Database Connection Exhaustion"
            echo "- max_connections=20, connections leaked"
            echo "- Hit /api/accounts/accounts/:id/balance to trigger"
            ;;
        queue-backlog)
            echo "Starting with QUEUE BACKLOG scenario..."
            docker-compose -f docker-compose.yml -f docker-compose.queue-backlog.yml up -d
            echo ""
            echo "Scenario: Message Queue Backlog"
            echo "- Notification service processes slowly (5s/msg)"
            echo "- Make transfers to queue notifications"
            ;;
        cascade-timeout)
            echo "Starting with CASCADE TIMEOUT scenario..."
            docker-compose -f docker-compose.yml -f docker-compose.cascade-timeout.yml up -d
            echo ""
            echo "Scenario: Cascading Timeout"
            echo "- Payment (10s) + Fraud (8s) services slow"
            echo "- Transaction service times out (5s)"
            ;;
        auth-failure)
            echo "Starting with AUTH FAILURE scenario..."
            docker-compose -f docker-compose.yml -f docker-compose.auth-failure.yml up -d
            echo ""
            echo "Scenario: Authentication Failures"
            echo "- 30% token verification failures"
            echo "- Redis memory pressure (32MB limit)"
            ;;
        payment-slow)
            echo "Starting with PAYMENT SLOWDOWN scenario..."
            docker-compose -f docker-compose.yml -f docker-compose.payment-slow.yml up -d
            echo ""
            echo "Scenario: Payment Processing Slowdown"
            echo "- 20% payment failures"
            echo "- 5s average latency"
            ;;
        *)
            echo "Unknown scenario: $SCENARIO"
            echo ""
            echo "Available scenarios:"
            echo "  memory-leak     - Memory leak in account service"
            echo "  db-exhaustion   - Database connection exhaustion"
            echo "  queue-backlog   - Message queue backlog"
            echo "  cascade-timeout - Cascading timeout from slow services"
            echo "  auth-failure    - Random authentication failures"
            echo "  payment-slow    - Payment processing slowdown"
            exit 1
            ;;
    esac
else
    echo "Starting healthy environment..."
    docker-compose up -d
    echo ""
    echo "No scenario selected - running in healthy mode"
fi

echo ""
echo "========================================"
echo "  Services Starting..."
echo "========================================"
echo ""

# Wait for services
echo "Waiting for services to be ready..."
sleep 10

echo ""
echo "========================================"
echo "  Access Points"
echo "========================================"
echo ""
echo "  Dashboard:    http://localhost:3000"
echo "  API Gateway:  http://localhost:8080"
echo "  RabbitMQ:     http://localhost:15672 (fintech/fintech123)"
echo "  Prometheus:   http://localhost:9090"
echo ""
echo "  Service Ports:"
echo "    Auth:         http://localhost:3001"
echo "    Account:      http://localhost:3002"
echo "    Transaction:  http://localhost:3003"
echo "    Fraud:        http://localhost:3004"
echo "    Notification: http://localhost:3005"
echo "    Payment:      http://localhost:3006"
echo ""
echo "========================================"
echo ""
echo "Use './scripts/traffic-generator.sh' to generate load"
echo "Use './scripts/stop-demo.sh' to stop all services"
echo ""
