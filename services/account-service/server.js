const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const { Pool } = require('pg');
const redis = require('redis');
const prometheus = require('prom-client');
const winston = require('winston');

const app = express();
const PORT = process.env.PORT || 3002;
const SERVICE_NAME = process.env.SERVICE_NAME || 'account-service';

// =============================================================================
// Logger Setup
// =============================================================================
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: SERVICE_NAME },
  transports: [new winston.transports.Console()]
});

// =============================================================================
// Prometheus Metrics
// =============================================================================
const register = new prometheus.Registry();
prometheus.collectDefaultMetrics({ register });

const httpRequestsTotal = new prometheus.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

const httpRequestDuration = new prometheus.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration',
  labelNames: ['method', 'route'],
  buckets: [0.1, 0.5, 1, 2, 5],
  registers: [register]
});

const memoryLeakGauge = new prometheus.Gauge({
  name: 'memory_leak_bytes',
  help: 'Bytes leaked due to memory leak simulation',
  registers: [register]
});

const dbConnectionsGauge = new prometheus.Gauge({
  name: 'db_connections_leaked',
  help: 'Number of leaked database connections',
  registers: [register]
});

// =============================================================================
// Issue Simulation Flags
// =============================================================================
const ENABLE_MEMORY_LEAK = process.env.ENABLE_MEMORY_LEAK === 'true';
const MEMORY_LEAK_RATE_MB = parseInt(process.env.MEMORY_LEAK_RATE_MB) || 5;
const ENABLE_CONNECTION_LEAK = process.env.ENABLE_CONNECTION_LEAK === 'true';

// Memory leak storage (intentionally never cleared)
const memoryLeakStorage = [];
let totalLeakedBytes = 0;

// Connection leak storage
const leakedConnections = [];

// =============================================================================
// Database Connection
// =============================================================================
const db = new Pool({
  host: process.env.DB_HOST || 'postgres',
  port: parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME || 'fintech',
  user: process.env.DB_USER || 'fintech',
  password: process.env.DB_PASSWORD || 'fintech123',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000
});

db.on('error', (err) => logger.error('Database pool error:', err));

// =============================================================================
// Redis Connection
// =============================================================================
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://redis:6379',
  socket: {
    reconnectStrategy: (retries) => Math.min(retries * 100, 3000)
  }
});

redisClient.on('error', (err) => logger.error('Redis error:', err));
redisClient.connect().catch(err => logger.error('Redis connection failed:', err));

// =============================================================================
// Middleware
// =============================================================================
app.use(cors());
app.use(express.json());
app.use(morgan('combined', { stream: { write: msg => logger.info(msg.trim()) } }));

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestsTotal.labels(req.method, req.route?.path || req.path, res.statusCode).inc();
    httpRequestDuration.labels(req.method, req.route?.path || req.path).observe(duration);
  });
  next();
});

// =============================================================================
// Routes
// =============================================================================

// Health check
app.get('/health', (req, res) => {
  const memUsage = process.memoryUsage();
  res.json({
    status: 'healthy',
    service: SERVICE_NAME,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    memory: {
      rss: `${Math.round(memUsage.rss / 1024 / 1024)}MB`,
      heapUsed: `${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`,
      heapTotal: `${Math.round(memUsage.heapTotal / 1024 / 1024)}MB`
    },
    issues: {
      memoryLeakEnabled: ENABLE_MEMORY_LEAK,
      memoryLeakedMB: Math.round(totalLeakedBytes / 1024 / 1024),
      connectionLeakEnabled: ENABLE_CONNECTION_LEAK,
      leakedConnections: leakedConnections.length
    }
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// List accounts for user
app.get('/users/:userId/accounts', async (req, res) => {
  const { userId } = req.params;

  try {
    const result = await db.query(
      'SELECT id, account_number, account_type, currency, balance, available_balance, status FROM accounts WHERE user_id = $1',
      [userId]
    );

    res.json({ accounts: result.rows });
  } catch (err) {
    logger.error('Failed to fetch accounts:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Get account by ID
app.get('/accounts/:accountId', async (req, res) => {
  const { accountId } = req.params;

  try {
    const result = await db.query(
      'SELECT a.*, u.email, u.first_name, u.last_name FROM accounts a JOIN users u ON a.user_id = u.id WHERE a.id = $1',
      [accountId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Account not found' });
    }

    res.json({ account: result.rows[0] });
  } catch (err) {
    logger.error('Failed to fetch account:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Get account balance - THIS ENDPOINT HAS THE MEMORY LEAK BUG
app.get('/accounts/:accountId/balance', async (req, res) => {
  const { accountId } = req.params;

  try {
    // ISSUE SIMULATION: Memory leak - store balance history that's never cleared
    if (ENABLE_MEMORY_LEAK) {
      // Create a large chunk of data that will never be garbage collected
      const leakChunk = new Array(MEMORY_LEAK_RATE_MB * 1024 * 128).fill({
        timestamp: new Date().toISOString(),
        accountId,
        randomData: Math.random().toString(36).repeat(100)
      });
      memoryLeakStorage.push(leakChunk);
      totalLeakedBytes += MEMORY_LEAK_RATE_MB * 1024 * 1024;
      memoryLeakGauge.set(totalLeakedBytes);

      logger.warn(`Memory leak: Added ${MEMORY_LEAK_RATE_MB}MB, total leaked: ${Math.round(totalLeakedBytes / 1024 / 1024)}MB`);
    }

    // ISSUE SIMULATION: Connection leak - get connection but never release it
    if (ENABLE_CONNECTION_LEAK) {
      const leakedClient = await db.connect();
      leakedConnections.push(leakedClient);
      dbConnectionsGauge.set(leakedConnections.length);
      // NOTE: We NEVER call leakedClient.release() - THIS IS THE BUG!
      logger.warn(`Connection leak: ${leakedConnections.length} connections leaked`);
    }

    const result = await db.query(
      'SELECT balance, available_balance, currency FROM accounts WHERE id = $1',
      [accountId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Account not found' });
    }

    res.json({
      accountId,
      ...result.rows[0],
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    logger.error('Failed to fetch balance:', err);
    res.status(500).json({ error: err.message });
  }
});

// Update account
app.patch('/accounts/:accountId', async (req, res) => {
  const { accountId } = req.params;
  const { daily_limit, status } = req.body;

  try {
    const updates = [];
    const values = [];
    let paramCount = 1;

    if (daily_limit !== undefined) {
      updates.push(`daily_limit = $${paramCount++}`);
      values.push(daily_limit);
    }
    if (status !== undefined) {
      updates.push(`status = $${paramCount++}`);
      values.push(status);
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No updates provided' });
    }

    values.push(accountId);
    const result = await db.query(
      `UPDATE accounts SET ${updates.join(', ')}, updated_at = CURRENT_TIMESTAMP WHERE id = $${paramCount} RETURNING *`,
      values
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Account not found' });
    }

    res.json({ account: result.rows[0] });
  } catch (err) {
    logger.error('Failed to update account:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Create account
app.post('/accounts', async (req, res) => {
  const { userId, accountType, currency } = req.body;

  if (!userId || !accountType) {
    return res.status(400).json({ error: 'userId and accountType required' });
  }

  const accountNumber = `${accountType.toUpperCase().substring(0, 3)}-${Date.now()}-${Math.random().toString(36).substring(7)}`;

  try {
    const result = await db.query(
      'INSERT INTO accounts (user_id, account_number, account_type, currency) VALUES ($1, $2, $3, $4) RETURNING *',
      [userId, accountNumber, accountType, currency || 'USD']
    );

    res.status(201).json({ account: result.rows[0] });
  } catch (err) {
    logger.error('Failed to create account:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Get all accounts (for demo purposes)
app.get('/accounts', async (req, res) => {
  try {
    const result = await db.query(
      'SELECT a.id, a.account_number, a.account_type, a.balance, a.status, u.email FROM accounts a JOIN users u ON a.user_id = u.id ORDER BY a.created_at DESC LIMIT 50'
    );
    res.json({ accounts: result.rows });
  } catch (err) {
    logger.error('Failed to fetch accounts:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// =============================================================================
// Error handling
// =============================================================================
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// =============================================================================
// Start server
// =============================================================================
app.listen(PORT, '0.0.0.0', () => {
  logger.info(`${SERVICE_NAME} started on port ${PORT}`);

  if (ENABLE_MEMORY_LEAK) {
    logger.warn(`MEMORY LEAK SIMULATION ENABLED: ${MEMORY_LEAK_RATE_MB}MB per /balance request`);
  }
  if (ENABLE_CONNECTION_LEAK) {
    logger.warn('CONNECTION LEAK SIMULATION ENABLED: DB connections will be leaked');
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down');
  // Release leaked connections on shutdown
  leakedConnections.forEach(client => client.release());
  db.end();
  redisClient.disconnect();
  process.exit(0);
});
