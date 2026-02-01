# FinTech Demo Environment

A fully-featured simulated **FinTech/Banking platform** with intentional, switchable issues designed to demonstrate OpsSquad's AI-powered incident investigation capabilities to potential customers.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Directory Structure](#directory-structure)
- [Quick Start](#quick-start)
- [Available Scenarios](#available-scenarios)
- [Services](#services)
- [Access Points](#access-points)
- [OpsSquad Integration](#opssquad-integration)
- [Scripts](#scripts)
- [Testing API Endpoints](#testing-api-endpoints)
- [Dashboard](#dashboard)
- [Development](#development)
- [Troubleshooting](#troubleshooting)

---

## Overview

This demo environment simulates a realistic banking microservices architecture with:

- **10 interconnected services** (7 application services + 3 infrastructure)
- **6 switchable incident scenarios** that can be activated independently
- **Real-time dashboard** showing service health and transaction flow
- **OpsSquad node integration** on every service for AI investigation
- **Traffic generation tools** to trigger and observe issues

**Use Cases:**
- Customer demos showing OpsSquad's investigation capabilities
- Sales presentations with live incident scenarios
- Training for support/SRE teams
- Testing OpsSquad agent deployments

---

## Architecture

```
                           ┌─────────────────┐
                           │  Demo Dashboard │ :3000
                           │  (React + Vite) │
                           └────────┬────────┘
                                    │
┌───────────────────────────────────┼───────────────────────────────────┐
│                           API Gateway (nginx) :8080                    │
└───────────────────────────────────┼───────────────────────────────────┘
        │           │           │           │           │
   ┌────┴───┐  ┌────┴───┐  ┌────┴───┐  ┌────┴───┐  ┌────┴───┐
   │  Auth  │  │Account │  │  Txn   │  │ Fraud  │  │ Notif  │
   │ :3001  │  │ :3002  │  │ :3003  │  │ :3004  │  │ :3005  │
   └────┬───┘  └────┬───┘  └────┬───┘  └────┬───┘  └────┬───┘
        │           │           │           │           │
        └─────┬─────┴─────┬─────┴─────┬─────┴─────┬─────┘
              │           │           │           │
         ┌────┴───┐  ┌────┴───┐  ┌────┴───┐  ┌────┴───┐
         │Postgres│  │ Redis  │  │RabbitMQ│  │Payment │
         │ :5432  │  │ :6379  │  │ :5672  │  │ :3006  │
         └────────┘  └────────┘  └────────┘  └────────┘

Each application service runs an OpsSquad node for AI-powered investigation
```

### Transaction Flow

When a user initiates a transfer:
1. **API Gateway** routes request to Transaction Service
2. **Transaction Service** creates pending transaction in PostgreSQL
3. **Fraud Detection** (Python/FastAPI) scores the transaction
4. **Payment Processor** executes the bank transfer
5. **Account Service** updates balances
6. **Notification Service** consumes from RabbitMQ and sends alerts
7. **Auth Service** validates JWT tokens throughout

---

## Directory Structure

```
/demo/
│
├── docker-compose.yml                 # Base configuration (healthy state)
├── docker-compose.memory-leak.yml     # Scenario: Memory leak
├── docker-compose.db-exhaustion.yml   # Scenario: DB connection exhaustion
├── docker-compose.queue-backlog.yml   # Scenario: Message queue backlog
├── docker-compose.cascade-timeout.yml # Scenario: Cascading timeouts
├── docker-compose.auth-failure.yml    # Scenario: Authentication failures
├── docker-compose.payment-slow.yml    # Scenario: Payment slowdown
│
├── .env.example                       # Environment template
├── README.md                          # This file
├── SCENARIOS.md                       # Detailed scenario documentation
│
├── services/                          # Application microservices
│   ├── api-gateway/                   # nginx reverse proxy
│   │   ├── Dockerfile
│   │   ├── nginx.conf
│   │   └── entrypoint.sh
│   │
│   ├── auth-service/                  # JWT authentication (Node.js)
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── server.js
│   │   └── entrypoint.sh
│   │
│   ├── account-service/               # Account CRUD (Node.js) - HAS MEMORY/DB LEAK
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── server.js
│   │   └── entrypoint.sh
│   │
│   ├── transaction-service/           # Transfers/payments (Node.js) - HAS CASCADE TIMEOUT
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── server.js
│   │   └── entrypoint.sh
│   │
│   ├── fraud-detection/               # ML scoring mock (Python/FastAPI) - HAS SLOW SCORING
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   ├── main.py
│   │   └── entrypoint.sh
│   │
│   ├── notification-service/          # Queue consumer (Node.js) - HAS SLOW CONSUMER
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── server.js
│   │   └── entrypoint.sh
│   │
│   └── payment-processor/             # External payment mock (Node.js) - HAS SLOW/FAILURES
│       ├── Dockerfile
│       ├── package.json
│       ├── server.js
│       └── entrypoint.sh
│
├── infrastructure/                    # Supporting services
│   ├── postgres/
│   │   └── init.sql                   # Database schema + seed data
│   ├── redis/
│   │   └── redis.conf                 # Redis configuration
│   ├── rabbitmq/
│   │   └── rabbitmq.conf              # RabbitMQ configuration
│   └── prometheus/
│       └── prometheus.yml             # Metrics scraping config
│
├── dashboard/                         # React monitoring dashboard
│   ├── Dockerfile
│   ├── package.json
│   ├── vite.config.ts
│   ├── tsconfig.json
│   ├── tailwind.config.js
│   ├── index.html
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── index.css
│       └── components/
│           ├── ServiceGrid.tsx        # Grid of service cards
│           ├── ServiceCard.tsx        # Individual service status
│           ├── MetricsPanel.tsx       # Request/error/latency metrics
│           ├── TransactionFlow.tsx    # Visual flow diagram
│           └── IncidentBanner.tsx     # Active incident alert
│
├── scripts/                           # Automation scripts
│   ├── start-demo.sh                  # Start with optional scenario
│   ├── stop-demo.sh                   # Stop all services
│   ├── reset-demo.sh                  # Full cleanup and reset
│   ├── traffic-generator.sh           # Generate realistic load
│   └── monitor-health.sh              # Real-time health monitoring
│
└── prompts/agents/                    # OpsSquad AI agent system prompts
    ├── api-gateway-agent.json
    ├── auth-service-agent.json
    ├── account-service-agent.json
    ├── transaction-service-agent.json
    ├── fraud-detection-agent.json
    ├── notification-service-agent.json
    └── payment-processor-agent.json
```

---

## Quick Start

### Prerequisites

- Docker and Docker Compose
- curl (for scripts)
- jq (optional, for pretty JSON output)

### Start the Demo

```bash
cd demo

# Option 1: Start healthy environment (no issues)
./scripts/start-demo.sh

# Option 2: Start with a specific broken scenario
./scripts/start-demo.sh memory-leak
./scripts/start-demo.sh db-exhaustion
./scripts/start-demo.sh queue-backlog
./scripts/start-demo.sh cascade-timeout
./scripts/start-demo.sh auth-failure
./scripts/start-demo.sh payment-slow
```

### Generate Traffic

```bash
# Generate load: 10 requests/second for 5 minutes
./scripts/traffic-generator.sh 300 10

# Light load: 5 requests/second for 2 minutes
./scripts/traffic-generator.sh 120 5
```

### Monitor Health

```bash
# Real-time health dashboard in terminal
./scripts/monitor-health.sh
```

### Stop Everything

```bash
./scripts/stop-demo.sh

# Full reset (removes volumes, rebuilds images)
./scripts/reset-demo.sh
```

---

## Available Scenarios

Each scenario activates specific bugs in the services. Only one scenario can run at a time.

| Scenario | Command | Affected Service | Root Cause | Symptoms |
|----------|---------|------------------|------------|----------|
| **Memory Leak** | `memory-leak` | Account Service | Unbounded array in `/balance` endpoint | Gradual slowdown → OOM crash |
| **DB Exhaustion** | `db-exhaustion` | Account Service → PostgreSQL | Missing `pool.release()` calls | "too many connections" errors |
| **Queue Backlog** | `queue-backlog` | Notification Service | 5s delay per message consumed | Growing queue, delayed notifications |
| **Cascade Timeout** | `cascade-timeout` | Transaction → Fraud → Payment | Fraud (8s) + Payment (10s) > timeout (5s) | 504 Gateway Timeout on transfers |
| **Auth Failure** | `auth-failure` | Auth Service + Redis | 30% token failures + Redis memory pressure | Random 401 errors, session loss |
| **Payment Slow** | `payment-slow` | Payment Processor | 20% failures + 5s delays | ~80% success rate, high latency |

### Scenario Details

#### 1. Memory Leak (`memory-leak`)
```bash
./scripts/start-demo.sh memory-leak
```
- **Trigger**: Every call to `GET /api/accounts/accounts/:id/balance`
- **Behavior**: Allocates 5MB that's never freed
- **Timeline**: ~15 minutes to OOM with moderate traffic
- **Detection**: Check `/health` endpoint for `memoryLeakedMB` value

#### 2. Database Connection Exhaustion (`db-exhaustion`)
```bash
./scripts/start-demo.sh db-exhaustion
```
- **Trigger**: Every call to `GET /api/accounts/accounts/:id/balance`
- **Behavior**: Acquires DB connection, never releases
- **Timeline**: Exhausts 20 connections quickly
- **Detection**: PostgreSQL "too many connections" in logs

#### 3. Message Queue Backlog (`queue-backlog`)
```bash
./scripts/start-demo.sh queue-backlog
```
- **Trigger**: Any transfer (queues notification)
- **Behavior**: Each notification takes 5s to process
- **Timeline**: Queue grows linearly with traffic
- **Detection**: RabbitMQ management shows growing queue

#### 4. Cascading Timeout (`cascade-timeout`)
```bash
./scripts/start-demo.sh cascade-timeout
```
- **Trigger**: `POST /api/transactions/transfer`
- **Behavior**: Downstream services too slow for timeout
- **Timeline**: Immediate 504 errors on transfers
- **Detection**: Transaction logs show timeout errors

#### 5. Authentication Failure (`auth-failure`)
```bash
./scripts/start-demo.sh auth-failure
```
- **Trigger**: Token verification requests
- **Behavior**: 30% random failures + Redis evictions
- **Timeline**: Intermittent from start
- **Detection**: Random 401 errors, check Redis memory

#### 6. Payment Slowdown (`payment-slow`)
```bash
./scripts/start-demo.sh payment-slow
```
- **Trigger**: Any transfer involving payment
- **Behavior**: 20% fail randomly, all take 5s
- **Timeline**: Visible immediately
- **Detection**: Check `/api/payments/health` for stats

---

## Services

### Application Services

| Service | Port | Technology | Description |
|---------|------|------------|-------------|
| API Gateway | 8080 | nginx | Reverse proxy, routing |
| Auth Service | 3001 | Node.js/Express | JWT authentication |
| Account Service | 3002 | Node.js/Express | Account CRUD, balances |
| Transaction Service | 3003 | Node.js/Express | Transfers, payments |
| Fraud Detection | 3004 | Python/FastAPI | ML scoring mock |
| Notification Service | 3005 | Node.js/Express | Queue consumer |
| Payment Processor | 3006 | Node.js/Express | External payment mock |

### Infrastructure Services

| Service | Port | Description |
|---------|------|-------------|
| PostgreSQL | 5432 | Primary database |
| Redis | 6379 | Session storage, caching |
| RabbitMQ | 5672, 15672 | Message queue |
| Prometheus | 9090 | Metrics collection |

---

## Access Points

### Web Interfaces

| Interface | URL | Credentials |
|-----------|-----|-------------|
| **Demo Dashboard** | http://localhost:3000 | - |
| **RabbitMQ Management** | http://localhost:15672 | fintech / fintech123 |
| **Prometheus** | http://localhost:9090 | - |

### API Endpoints

| Service | Base URL | Health Check |
|---------|----------|--------------|
| API Gateway | http://localhost:8080 | /health |
| Auth Service | http://localhost:8080/api/auth | /api/auth/health |
| Account Service | http://localhost:8080/api/accounts | /api/accounts/health |
| Transaction Service | http://localhost:8080/api/transactions | /api/transactions/health |
| Fraud Detection | http://localhost:8080/api/fraud | /api/fraud/health |
| Notification Service | http://localhost:8080/api/notifications | /api/notifications/health |
| Payment Processor | http://localhost:8080/api/payments | /api/payments/health |

---

## OpsSquad Integration

OpsSquad nodes can be easily installed on all containers using a simple JSON configuration file.

### Quick Setup (Recommended)

**Step 1:** Start the demo environment first:
```bash
./scripts/start-demo.sh memory-leak
```

**Step 2:** Create your node configuration:
```bash
cp nodes.example.json nodes.json
```

**Step 3:** Edit `nodes.json` with your credentials from the OpsSquad dashboard:
```json
{
  "global": {
    "token": "your-actual-token"
  },
  "nodes": [
    {
      "name": "API Gateway",
      "container": "fintech-api-gateway",
      "node_id": "paste-node-id-from-dashboard",
      "enabled": true
    },
    ...
  ]
}
```

**Step 4:** Install nodes on all containers with a single command:
```bash
./scripts/install-nodes.sh
```

That's it! All nodes will be installed and started automatically.

### Node Configuration Format

The `nodes.json` file structure:

```json
{
  "global": {
    "token": "your-opssquad-token",
    "socket_url": "socket.opssquad.ai:9000"
  },
  "nodes": [
    {
      "name": "Service Name",
      "container": "docker-container-name",
      "node_id": "uuid-from-dashboard",
      "enabled": true
    }
  ]
}
```

| Field | Description |
|-------|-------------|
| `global.token` | Your OpsSquad token (shared across all nodes) |
| `global.socket_url` | OpsSquad socket server URL |
| `nodes[].name` | Display name for the service |
| `nodes[].container` | Docker container name to install node on |
| `nodes[].node_id` | Node ID from OpsSquad dashboard |
| `nodes[].enabled` | Set to `false` to skip this node |

### Node Management Scripts

| Script | Description |
|--------|-------------|
| `./scripts/install-nodes.sh` | Install and start nodes on all configured containers |
| `./scripts/check-nodes.sh` | Check status of all nodes (running/stopped/not installed) |
| `./scripts/start-nodes.sh` | Start nodes that are installed but not running |
| `./scripts/stop-nodes.sh` | Stop all running nodes |
| `./scripts/uninstall-nodes.sh` | Completely remove nodes from all containers |

### Example Workflow for Demo

```bash
# 1. Start the demo with a scenario
./scripts/start-demo.sh memory-leak

# 2. Configure and install nodes (first time only)
cp nodes.example.json nodes.json
# Edit nodes.json with your credentials
./scripts/install-nodes.sh

# 3. Verify nodes are running
./scripts/check-nodes.sh

# 4. Generate traffic to trigger the issue
./scripts/traffic-generator.sh 300 10

# 5. Use OpsSquad to investigate!
```

### Agent System Prompts

Service-specific investigation guidance is in `/prompts/agents/`. These can be used to configure OpsSquad agents with domain knowledge about each service.

---

## Scripts

### Demo Management

| Script | Usage | Description |
|--------|-------|-------------|
| `start-demo.sh` | `./scripts/start-demo.sh [scenario]` | Start demo with optional scenario |
| `stop-demo.sh` | `./scripts/stop-demo.sh` | Stop all containers |
| `reset-demo.sh` | `./scripts/reset-demo.sh` | Full cleanup (volumes, images) |

### Node Management

| Script | Usage | Description |
|--------|-------|-------------|
| `install-nodes.sh` | `./scripts/install-nodes.sh` | Install nodes from nodes.json |
| `check-nodes.sh` | `./scripts/check-nodes.sh` | Check node status |
| `start-nodes.sh` | `./scripts/start-nodes.sh` | Start stopped nodes |
| `stop-nodes.sh` | `./scripts/stop-nodes.sh` | Stop running nodes |
| `uninstall-nodes.sh` | `./scripts/uninstall-nodes.sh` | Remove nodes |

### Traffic & Monitoring

| Script | Usage | Description |
|--------|-------|-------------|
| `traffic-generator.sh` | `./scripts/traffic-generator.sh [duration] [rate]` | Generate load |
| `monitor-health.sh` | `./scripts/monitor-health.sh` | Real-time health dashboard |

### traffic-generator.sh Details
```bash
./scripts/traffic-generator.sh [duration_seconds] [requests_per_second]
```
Generates realistic traffic:
- 30% balance checks (triggers memory/db leak)
- 20% health checks
- 20% account listings
- 15% token verifications (triggers auth failures)
- 15% transfers (triggers cascade timeout, queue backlog)

---

## Testing API Endpoints

### Health Checks
```bash
# All services via gateway
curl http://localhost:8080/health
curl http://localhost:8080/api/auth/health
curl http://localhost:8080/api/accounts/health
curl http://localhost:8080/api/transactions/health
curl http://localhost:8080/api/fraud/health
curl http://localhost:8080/api/notifications/health
curl http://localhost:8080/api/payments/health
```

### Authentication
```bash
# Login (returns JWT token)
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"john.smith@example.com","password":"demo123"}'

# Verify token
curl -X POST http://localhost:8080/api/auth/verify \
  -H "Content-Type: application/json" \
  -d '{"token":"your-jwt-token"}'
```

### Account Operations
```bash
# List all accounts
curl http://localhost:8080/api/accounts/accounts

# Get specific account
curl http://localhost:8080/api/accounts/accounts/aaaa1111-1111-1111-1111-111111111111

# Get balance (TRIGGERS MEMORY/DB LEAK if enabled)
curl http://localhost:8080/api/accounts/accounts/aaaa1111-1111-1111-1111-111111111111/balance
```

### Transactions
```bash
# List transactions
curl http://localhost:8080/api/transactions/transactions

# Create transfer (TRIGGERS CASCADE TIMEOUT if enabled)
curl -X POST http://localhost:8080/api/transactions/transfer \
  -H "Content-Type: application/json" \
  -d '{
    "fromAccountId": "aaaa1111-1111-1111-1111-111111111111",
    "toAccountId": "bbbb1111-2222-2222-2222-222222222222",
    "amount": 100,
    "description": "Test transfer"
  }'
```

### Fraud Detection
```bash
# Score a transaction
curl -X POST http://localhost:8080/api/fraud/score \
  -H "Content-Type: application/json" \
  -d '{
    "transactionId": "test-123",
    "fromAccountId": "aaaa1111-1111-1111-1111-111111111111",
    "toAccountId": "bbbb1111-2222-2222-2222-222222222222",
    "amount": 5000,
    "type": "transfer"
  }'
```

### Sample Account IDs (from seed data)
```
aaaa1111-1111-1111-1111-111111111111  # John Smith - Checking
aaaa2222-1111-1111-1111-111111111111  # John Smith - Savings
bbbb1111-2222-2222-2222-222222222222  # Jane Doe - Checking
cccc1111-3333-3333-3333-333333333333  # Bob Wilson - Checking
dddd1111-4444-4444-4444-444444444444  # Alice Johnson - Checking
eeee1111-5555-5555-5555-555555555555  # Charlie Brown - Checking
```

---

## Dashboard

The React dashboard provides real-time visibility into the demo environment.

### Features

1. **Service Grid**: Shows all 10 services with health status (green/yellow/red)
2. **Metrics Panel**: Displays request count, error rate, latency, active transactions
3. **Transaction Flow**: Visual diagram showing request path through services
4. **Incident Banner**: Alerts when services are degraded or down

### Local Development

```bash
cd dashboard
npm install
npm run dev
```

Opens at http://localhost:3000 with hot reload.

---

## Development

### Prerequisites

- Docker and Docker Compose
- Node.js 20+ (for dashboard and service development)
- Python 3.11+ (for fraud-detection service)

### Building Individual Services

```bash
# Build all images
docker-compose build

# Build specific service
docker-compose build account-service
```

### Viewing Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f account-service

# Filter for issues
docker-compose logs -f | grep -i "error\|leak\|timeout"
```

### Modifying Services

1. Edit the service code in `services/<service-name>/`
2. Rebuild: `docker-compose build <service-name>`
3. Restart: `docker-compose up -d <service-name>`

### Adding New Scenarios

1. Create `docker-compose.new-scenario.yml`:
   ```yaml
   services:
     some-service:
       environment:
         - ENABLE_NEW_ISSUE=true
   ```

2. Add to `start-demo.sh` case statement

3. Document in `SCENARIOS.md`

---

## Troubleshooting

### Containers Won't Start

```bash
# Check logs
docker-compose logs

# Check disk space
docker system df

# Clean up
docker system prune -f
```

### Services Not Responding

```bash
# Check container status
docker-compose ps

# Restart specific service
docker-compose restart account-service

# Check health endpoints directly
curl http://localhost:3002/health
```

### Database Connection Issues

```bash
# Check PostgreSQL
docker exec fintech-postgres pg_isready

# Check connection count
docker exec fintech-postgres psql -U fintech -c "SELECT count(*) FROM pg_stat_activity;"
```

### RabbitMQ Queue Issues

```bash
# Check queue status
curl -u fintech:fintech123 http://localhost:15672/api/queues/%2F/notifications

# Or use management UI
open http://localhost:15672
```

### Reset Everything

```bash
./scripts/reset-demo.sh
./scripts/start-demo.sh
```

---

## See Also

- [SCENARIOS.md](./SCENARIOS.md) - Detailed scenario documentation with investigation steps
- [OpsSquad Documentation](https://docs.fixpanic.com) - Full OpsSquad documentation
- [Agent Prompts](./prompts/agents/) - Service-specific AI investigation guidance

---

## Support

For issues with this demo environment, contact the OpsSquad team or open an issue in the repository.
