# FinTech Demo Scenarios

Detailed documentation for each incident scenario in the FinTech demo environment.

---

## Scenario 1: Memory Leak

### Overview
The account service has a memory leak that causes it to consume memory until it crashes with an OOM error.

### Configuration
```bash
./scripts/start-demo.sh memory-leak
```

### Technical Details

**Location**: `services/account-service/server.js` - `/accounts/:id/balance` endpoint

**Bug**: An array stores balance history data on every request but is never cleared:

```javascript
// BUG: This array grows forever
const memoryLeakStorage = [];

app.get('/accounts/:accountId/balance', async (req, res) => {
  if (ENABLE_MEMORY_LEAK) {
    // Create chunk that won't be garbage collected
    const leakChunk = new Array(MEMORY_LEAK_RATE_MB * 1024 * 128).fill({...});
    memoryLeakStorage.push(leakChunk);  // Never removed!
  }
  // ...
});
```

### Symptoms Timeline

1. **0-2 min**: Normal operation
2. **2-5 min**: Memory usage climbing (visible in /health)
3. **5-10 min**: Response times increasing
4. **10-15 min**: Container approaching 256MB limit
5. **15+ min**: OOM kill, service restarts

### Investigation Steps

1. Check health endpoint:
   ```bash
   curl http://localhost:3002/health | jq '.issues'
   ```

2. Monitor container memory:
   ```bash
   docker stats fintech-account-service
   ```

3. Check Node.js heap:
   ```bash
   docker exec fintech-account-service node -e "console.log(process.memoryUsage())"
   ```

4. Find the leak in logs:
   ```bash
   docker logs fintech-account-service | grep "Memory leak"
   ```

### Resolution
- **Immediate**: Restart the service
- **Fix**: Remove the unbounded array or implement proper cleanup

---

## Scenario 2: Database Connection Exhaustion

### Overview
Database connections are acquired but never released, eventually exhausting the connection pool.

### Configuration
```bash
./scripts/start-demo.sh db-exhaustion
```

### Technical Details

**Location**: `services/account-service/server.js` - connection leak in balance endpoint

**Bug**: Database clients are never released back to the pool:

```javascript
if (ENABLE_CONNECTION_LEAK) {
  const leakedClient = await db.connect();
  leakedConnections.push(leakedClient);
  // NOTE: We NEVER call leakedClient.release() - THIS IS THE BUG!
}
```

**Settings**:
- PostgreSQL max_connections: 20 (intentionally low)
- Node.js pool size: 20

### Symptoms Timeline

1. **0-1 min**: Normal operation
2. **After ~20 requests**: Connection pool exhausted
3. **Continued traffic**: "too many connections" errors
4. **All DB services**: Start failing (transaction, account)

### Investigation Steps

1. Check PostgreSQL connections:
   ```bash
   docker exec fintech-postgres psql -U fintech -d fintech -c \
     "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"
   ```

2. Check account service health:
   ```bash
   curl http://localhost:3002/health | jq '.issues.leakedConnections'
   ```

3. Monitor error logs:
   ```bash
   docker logs fintech-account-service | grep "connection"
   ```

### Resolution
- **Immediate**: Restart account-service
- **Fix**: Add `client.release()` after database operations

---

## Scenario 3: Message Queue Backlog

### Overview
The notification service processes messages too slowly, causing a growing backlog.

### Configuration
```bash
./scripts/start-demo.sh queue-backlog
```

### Technical Details

**Location**: `services/notification-service/server.js` - slow consumer

**Bug**: Each message takes 5 seconds to process:

```javascript
if (ENABLE_SLOW_CONSUMER) {
  await new Promise(resolve => setTimeout(resolve, CONSUMER_DELAY_MS));
}
```

### Symptoms Timeline

1. **0-2 min**: Notifications slightly delayed
2. **5 min**: Queue depth growing
3. **10+ min**: RabbitMQ memory pressure
4. **Eventually**: Message publishing blocked

### Investigation Steps

1. Check RabbitMQ queue depth:
   ```bash
   curl -u fintech:fintech123 http://localhost:15672/api/queues/%2F/notifications | jq
   ```

2. Check notification service stats:
   ```bash
   curl http://localhost:3005/queue-stats | jq
   ```

3. Monitor RabbitMQ management:
   - Open http://localhost:15672
   - Login: fintech/fintech123
   - Check "notifications" queue

### Resolution
- **Immediate**: Scale up notification consumers
- **Fix**: Optimize message processing, add more workers

---

## Scenario 4: Cascading Timeout

### Overview
Slow downstream services (fraud, payment) cause transaction service to timeout.

### Configuration
```bash
./scripts/start-demo.sh cascade-timeout
```

### Technical Details

**Chain of failure**:
1. Payment Processor: 10s delay
2. Fraud Detection: 8s delay
3. Transaction Service: 5s timeout for downstream calls

**Configuration**:
```javascript
// Transaction service
DOWNSTREAM_TIMEOUT_MS=5000  // Waits max 5s

// Fraud detection
SCORING_DELAY_MS=8000  // Takes 8s

// Payment processor
PAYMENT_DELAY_MS=10000  // Takes 10s
```

### Symptoms

- 504 Gateway Timeout on /api/transactions/transfer
- Transaction service logs show timeout errors
- Transactions stuck in "pending" or "failed" state

### Investigation Steps

1. Make a transfer and observe timeout:
   ```bash
   curl -X POST http://localhost:8080/api/transactions/transfer \
     -H "Content-Type: application/json" \
     -d '{"fromAccountId":"aaaa1111-1111-1111-1111-111111111111","toAccountId":"bbbb1111-2222-2222-2222-222222222222","amount":100}'
   ```

2. Check each service's latency:
   ```bash
   # Fraud service
   time curl http://localhost:3004/health

   # Payment service
   time curl http://localhost:3006/health
   ```

3. Review transaction service logs:
   ```bash
   docker logs fintech-transaction-service | grep "timeout"
   ```

### Resolution
- **Immediate**: Increase timeout values
- **Fix**: Optimize downstream services, add circuit breakers

---

## Scenario 5: Authentication Failure

### Overview
Random token verification failures combined with Redis memory pressure causing session issues.

### Configuration
```bash
./scripts/start-demo.sh auth-failure
```

### Technical Details

**Two compounding issues**:

1. **Token Verification Failures** (30%):
   ```javascript
   if (ENABLE_TOKEN_FAILURE && Math.random() < TOKEN_FAILURE_RATE) {
     return res.status(401).json({ error: 'Token verification failed' });
   }
   ```

2. **Redis Memory Pressure** (32MB limit):
   - Sessions get evicted
   - Users randomly logged out

### Symptoms

- Intermittent 401 Unauthorized errors
- Users report random logouts
- Some sessions work, others don't

### Investigation Steps

1. Test token verification multiple times:
   ```bash
   for i in {1..10}; do
     curl -s -o /dev/null -w "%{http_code}\n" \
       -X POST http://localhost:3001/verify \
       -H "Content-Type: application/json" \
       -d '{"token":"test"}'
   done
   ```

2. Check Redis memory:
   ```bash
   docker exec fintech-redis redis-cli INFO memory
   ```

3. Check auth service logs:
   ```bash
   docker logs fintech-auth-service | grep "simulated failure"
   ```

### Resolution
- **Immediate**: Increase Redis memory, disable token failure
- **Fix**: Fix token verification logic, scale Redis

---

## Scenario 6: Payment Processing Slowdown

### Overview
External payment service is degraded with 20% failures and 5s delays.

### Configuration
```bash
./scripts/start-demo.sh payment-slow
```

### Technical Details

**Configuration**:
```javascript
ENABLE_SLOW_PAYMENTS=true
PAYMENT_DELAY_MS=5000
ENABLE_PAYMENT_FAILURES=true
PAYMENT_FAILURE_RATE=0.2
```

### Symptoms

- ~80% payment success rate
- 5+ second latency on all payments
- Error messages include: INSUFFICIENT_FUNDS, NETWORK_TIMEOUT, etc.

### Investigation Steps

1. Check payment service health:
   ```bash
   curl http://localhost:3006/health | jq '.stats'
   ```

2. Make test payments:
   ```bash
   for i in {1..10}; do
     curl -s -X POST http://localhost:3006/process \
       -H "Content-Type: application/json" \
       -d '{"transactionId":"test-'$i'","fromAccountId":"a","toAccountId":"b","amount":100}' | jq
   done
   ```

3. Review network status:
   ```bash
   curl http://localhost:3006/networks | jq
   ```

### Resolution
- **Immediate**: Contact payment provider, enable fallback processor
- **Fix**: Implement retry logic, circuit breaker, alternative providers

---

## Running Multiple Scenarios

You can only run one scenario overlay at a time due to conflicting configurations. To switch scenarios:

```bash
# Stop current environment
./scripts/stop-demo.sh

# Start new scenario
./scripts/start-demo.sh cascade-timeout
```

## Creating Custom Scenarios

Create a new `docker-compose.custom.yml`:

```yaml
services:
  account-service:
    environment:
      - ENABLE_MEMORY_LEAK=true
      - ENABLE_CONNECTION_LEAK=true  # Multiple issues!

  auth-service:
    environment:
      - ENABLE_TOKEN_FAILURE=true
```

Run with:
```bash
docker-compose -f docker-compose.yml -f docker-compose.custom.yml up -d
```
