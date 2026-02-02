# FinTech Banking Platform - System Knowledge Base

## Architecture Overview

This is a microservices-based banking platform with the following components:

| Service | Port | Technology | Purpose |
|---------|------|------------|---------|
| API Gateway | 8080 | nginx | Routes all `/api/*` requests to backend services |
| Auth Service | 3001 | Node.js | JWT authentication, token management |
| Account Service | 3002 | Node.js | Account CRUD, balance inquiries |
| Transaction Service | 3003 | Node.js | Transfers, payments (calls fraud + payment services) |
| Fraud Detection | 3004 | Python | ML-based fraud scoring for transactions |
| Notification Service | 3005 | Node.js | Async notifications via RabbitMQ |
| Payment Processor | 3006 | Node.js | External payment provider integration |

**Infrastructure:** PostgreSQL (5432), Redis (6379), RabbitMQ (5672)

## Service Dependencies

```
User Request → API Gateway → Auth (validates token)
                          → Account Service → PostgreSQL
                          → Transaction Service → Fraud Detection
                                              → Payment Processor
                                              → RabbitMQ → Notification Service
```

## How to Investigate

### 1. Health Endpoints (CHECK THESE FIRST)
Every service exposes a `/health` endpoint with detailed status:

```bash
curl http://localhost:3001/health  # Auth
curl http://localhost:3002/health  # Account
curl http://localhost:3003/health  # Transaction
curl http://localhost:3004/health  # Fraud
curl http://localhost:3005/health  # Notification
curl http://localhost:3006/health  # Payment
```

### 2. Understanding Health Response

Each health endpoint returns an `issues` object showing **active issue flags**:

```json
{
  "status": "healthy",
  "issues": {
    "memoryLeakEnabled": true,      // If true = memory leak is active
    "connectionLeakEnabled": false,  // If true = DB connections leaking
    "tokenFailureEnabled": false,    // If true = auth randomly failing
    "slowScoringEnabled": false,     // If true = fraud service artificially slow
    "slowConsumerEnabled": false,    // If true = notifications processing slowly
    "slowPaymentsEnabled": false,    // If true = payments artificially slow
    "failuresEnabled": false         // If true = payments randomly failing
  }
}
```

**IMPORTANT:** If any `*Enabled` flag is `true`, that's likely the root cause of the issue.

### 3. Key Diagnostic Commands

```bash
# Memory issues
ps aux                              # Check process memory
cat /proc/meminfo                   # System memory

# Database issues
netstat -an | grep 5432             # DB connections
psql -c "SELECT count(*) FROM pg_stat_activity"  # Active connections

# Queue issues
rabbitmqctl list_queues             # Check queue depth

# General
env | grep ENABLE                   # Check enabled issue flags
```

## Common Issue Patterns

| Symptom | Likely Service | What to Check |
|---------|---------------|---------------|
| Slow/timeout on balance | Account Service | `memoryLeakEnabled`, memory stats |
| DB connection errors | Account/Transaction | `connectionLeakEnabled`, pg connections |
| Delayed notifications | Notification Service | `slowConsumerEnabled`, RabbitMQ queue depth |
| Transaction timeouts | Fraud + Payment | `slowScoringEnabled`, `slowPaymentsEnabled` |
| Random 401 errors | Auth Service | `tokenFailureEnabled`, Redis memory |
| Payment failures | Payment Processor | `failuresEnabled`, `slowPaymentsEnabled` |

## Investigation Checklist

1. **Always check health endpoints first** - they reveal active issue flags
2. Look for `*Enabled: true` in the `issues` object
3. Check service logs for errors
4. Verify infrastructure health (DB, Redis, RabbitMQ)
5. Check memory/CPU if performance degradation
