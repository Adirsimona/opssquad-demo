const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const { Pool } = require('pg');
const redis = require('redis');
const amqp = require('amqplib');
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');
const prometheus = require('prom-client');
const winston = require('winston');

const app = express();
const PORT = process.env.PORT || 3003;
const SERVICE_NAME = process.env.SERVICE_NAME || 'transaction-service';

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

const transactionDuration = new prometheus.Histogram({
  name: 'transaction_duration_seconds',
  help: 'Transaction processing duration',
  labelNames: ['type', 'status'],
  buckets: [0.5, 1, 2, 5, 10, 30],
  registers: [register]
});

const downstreamLatency = new prometheus.Histogram({
  name: 'downstream_latency_seconds',
  help: 'Latency of downstream service calls',
  labelNames: ['service'],
  buckets: [0.1, 0.5, 1, 2, 5, 10],
  registers: [register]
});

const transactionErrors = new prometheus.Counter({
  name: 'transaction_errors_total',
  help: 'Total transaction errors',
  labelNames: ['type', 'reason'],
  registers: [register]
});

// =============================================================================
// Issue Simulation Flags
// =============================================================================
const ENABLE_CASCADE_TIMEOUT = process.env.ENABLE_CASCADE_TIMEOUT === 'true';
const DOWNSTREAM_TIMEOUT_MS = parseInt(process.env.DOWNSTREAM_TIMEOUT_MS) || 5000;

// =============================================================================
// Service URLs
// =============================================================================
const FRAUD_SERVICE_URL = process.env.FRAUD_SERVICE_URL || 'http://fraud-detection:3004';
const PAYMENT_SERVICE_URL = process.env.PAYMENT_SERVICE_URL || 'http://payment-processor:3006';

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

// =============================================================================
// Redis Connection
// =============================================================================
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://redis:6379'
});
redisClient.on('error', (err) => logger.error('Redis error:', err));
redisClient.connect().catch(err => logger.error('Redis connection failed:', err));

// =============================================================================
// RabbitMQ Connection
// =============================================================================
let rabbitChannel = null;
const NOTIFICATION_QUEUE = 'notifications';

async function connectRabbitMQ() {
  try {
    const conn = await amqp.connect(process.env.RABBITMQ_URL || 'amqp://fintech:fintech123@rabbitmq:5672');
    rabbitChannel = await conn.createChannel();
    await rabbitChannel.assertQueue(NOTIFICATION_QUEUE, { durable: true });
    logger.info('RabbitMQ connected');
  } catch (err) {
    logger.error('RabbitMQ connection failed:', err);
    setTimeout(connectRabbitMQ, 5000);
  }
}
connectRabbitMQ();

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
  });
  next();
});

// =============================================================================
// Helper Functions
// =============================================================================

async function callFraudService(transaction) {
  const start = Date.now();
  try {
    const timeoutMs = ENABLE_CASCADE_TIMEOUT ? DOWNSTREAM_TIMEOUT_MS : 30000;
    const response = await axios.post(`${FRAUD_SERVICE_URL}/score`, transaction, {
      timeout: timeoutMs
    });
    downstreamLatency.labels('fraud-detection').observe((Date.now() - start) / 1000);
    return response.data;
  } catch (err) {
    downstreamLatency.labels('fraud-detection').observe((Date.now() - start) / 1000);
    if (err.code === 'ECONNABORTED') {
      logger.error('Fraud service timeout');
      throw new Error('Fraud check timeout');
    }
    throw err;
  }
}

async function callPaymentService(payment) {
  const start = Date.now();
  try {
    const timeoutMs = ENABLE_CASCADE_TIMEOUT ? DOWNSTREAM_TIMEOUT_MS : 30000;
    const response = await axios.post(`${PAYMENT_SERVICE_URL}/process`, payment, {
      timeout: timeoutMs
    });
    downstreamLatency.labels('payment-processor').observe((Date.now() - start) / 1000);
    return response.data;
  } catch (err) {
    downstreamLatency.labels('payment-processor').observe((Date.now() - start) / 1000);
    if (err.code === 'ECONNABORTED') {
      logger.error('Payment service timeout');
      throw new Error('Payment processing timeout');
    }
    throw err;
  }
}

async function publishNotification(notification) {
  if (!rabbitChannel) {
    logger.warn('RabbitMQ not connected, skipping notification');
    return;
  }
  try {
    rabbitChannel.sendToQueue(
      NOTIFICATION_QUEUE,
      Buffer.from(JSON.stringify(notification)),
      { persistent: true }
    );
    logger.info(`Notification queued: ${notification.type}`);
  } catch (err) {
    logger.error('Failed to queue notification:', err);
  }
}

// =============================================================================
// Routes
// =============================================================================

// Health check
app.get('/health', async (req, res) => {
  let dbStatus = 'disconnected';
  let rabbitStatus = rabbitChannel ? 'connected' : 'disconnected';

  try {
    await db.query('SELECT 1');
    dbStatus = 'connected';
  } catch (e) {
    dbStatus = 'error';
  }

  res.json({
    status: 'healthy',
    service: SERVICE_NAME,
    timestamp: new Date().toISOString(),
    dependencies: {
      database: dbStatus,
      rabbitmq: rabbitStatus,
      fraudService: FRAUD_SERVICE_URL,
      paymentService: PAYMENT_SERVICE_URL
    },
    issues: {
      cascadeTimeoutEnabled: ENABLE_CASCADE_TIMEOUT,
      downstreamTimeoutMs: DOWNSTREAM_TIMEOUT_MS
    }
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// List transactions
app.get('/transactions', async (req, res) => {
  const { accountId, limit = 50 } = req.query;

  try {
    let query = 'SELECT * FROM transactions';
    const params = [];

    if (accountId) {
      query += ' WHERE from_account_id = $1 OR to_account_id = $1';
      params.push(accountId);
    }

    query += ' ORDER BY created_at DESC LIMIT $' + (params.length + 1);
    params.push(parseInt(limit));

    const result = await db.query(query, params);
    res.json({ transactions: result.rows });
  } catch (err) {
    logger.error('Failed to fetch transactions:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Get transaction by ID
app.get('/transactions/:transactionId', async (req, res) => {
  const { transactionId } = req.params;

  try {
    const result = await db.query('SELECT * FROM transactions WHERE id = $1', [transactionId]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    res.json({ transaction: result.rows[0] });
  } catch (err) {
    logger.error('Failed to fetch transaction:', err);
    res.status(500).json({ error: 'Database error' });
  }
});

// Create transfer - THIS IS THE MAIN ENDPOINT AFFECTED BY CASCADE TIMEOUT
app.post('/transfer', async (req, res) => {
  const startTime = Date.now();
  const { fromAccountId, toAccountId, amount, description } = req.body;

  if (!fromAccountId || !toAccountId || !amount) {
    return res.status(400).json({ error: 'fromAccountId, toAccountId, and amount required' });
  }

  if (amount <= 0) {
    return res.status(400).json({ error: 'Amount must be positive' });
  }

  const transactionId = uuidv4();

  try {
    // Step 1: Create pending transaction
    await db.query(
      `INSERT INTO transactions (id, from_account_id, to_account_id, transaction_type, amount, status, description)
       VALUES ($1, $2, $3, 'transfer', $4, 'pending', $5)`,
      [transactionId, fromAccountId, toAccountId, amount, description || 'Transfer']
    );

    logger.info(`Transaction ${transactionId} created, starting fraud check`);

    // Step 2: Call fraud detection service
    let fraudResult;
    try {
      fraudResult = await callFraudService({
        transactionId,
        fromAccountId,
        toAccountId,
        amount,
        type: 'transfer'
      });

      await db.query(
        'UPDATE transactions SET fraud_score = $1, fraud_check_status = $2 WHERE id = $3',
        [fraudResult.score, fraudResult.decision, transactionId]
      );

      if (fraudResult.decision === 'rejected') {
        await db.query(
          'UPDATE transactions SET status = $1 WHERE id = $2',
          ['failed', transactionId]
        );
        transactionErrors.labels('transfer', 'fraud_rejected').inc();
        transactionDuration.labels('transfer', 'rejected').observe((Date.now() - startTime) / 1000);
        return res.status(400).json({ error: 'Transaction rejected by fraud detection', transactionId });
      }
    } catch (err) {
      // Cascade timeout scenario - fraud service too slow
      if (err.message.includes('timeout')) {
        await db.query('UPDATE transactions SET status = $1 WHERE id = $2', ['failed', transactionId]);
        transactionErrors.labels('transfer', 'fraud_timeout').inc();
        transactionDuration.labels('transfer', 'timeout').observe((Date.now() - startTime) / 1000);
        logger.error(`Transaction ${transactionId} failed: fraud service timeout`);
        return res.status(504).json({ error: 'Fraud check timeout', transactionId });
      }
      throw err;
    }

    // Step 3: Process payment
    let paymentResult;
    try {
      await db.query('UPDATE transactions SET status = $1 WHERE id = $2', ['processing', transactionId]);

      paymentResult = await callPaymentService({
        transactionId,
        fromAccountId,
        toAccountId,
        amount
      });

      if (!paymentResult.success) {
        await db.query('UPDATE transactions SET status = $1 WHERE id = $2', ['failed', transactionId]);
        transactionErrors.labels('transfer', 'payment_failed').inc();
        transactionDuration.labels('transfer', 'failed').observe((Date.now() - startTime) / 1000);
        return res.status(400).json({ error: 'Payment processing failed', transactionId });
      }
    } catch (err) {
      // Cascade timeout scenario - payment service too slow
      if (err.message.includes('timeout')) {
        await db.query('UPDATE transactions SET status = $1 WHERE id = $2', ['failed', transactionId]);
        transactionErrors.labels('transfer', 'payment_timeout').inc();
        transactionDuration.labels('transfer', 'timeout').observe((Date.now() - startTime) / 1000);
        logger.error(`Transaction ${transactionId} failed: payment service timeout`);
        return res.status(504).json({ error: 'Payment processing timeout', transactionId });
      }
      throw err;
    }

    // Step 4: Update balances and complete transaction
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      await client.query(
        'UPDATE accounts SET balance = balance - $1, available_balance = available_balance - $1 WHERE id = $2',
        [amount, fromAccountId]
      );

      await client.query(
        'UPDATE accounts SET balance = balance + $1, available_balance = available_balance + $1 WHERE id = $2',
        [amount, toAccountId]
      );

      await client.query(
        'UPDATE transactions SET status = $1, completed_at = CURRENT_TIMESTAMP WHERE id = $2',
        ['completed', transactionId]
      );

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    // Step 5: Queue notification
    await publishNotification({
      type: 'transfer_completed',
      transactionId,
      fromAccountId,
      toAccountId,
      amount,
      timestamp: new Date().toISOString()
    });

    const duration = (Date.now() - startTime) / 1000;
    transactionDuration.labels('transfer', 'completed').observe(duration);
    logger.info(`Transaction ${transactionId} completed in ${duration}s`);

    res.status(201).json({
      transactionId,
      status: 'completed',
      amount,
      fraudScore: fraudResult.score,
      duration: `${duration}s`
    });
  } catch (err) {
    logger.error(`Transaction ${transactionId} failed:`, err);
    await db.query('UPDATE transactions SET status = $1 WHERE id = $2', ['failed', transactionId]);
    transactionErrors.labels('transfer', 'error').inc();
    res.status(500).json({ error: 'Transaction failed', transactionId });
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

  if (ENABLE_CASCADE_TIMEOUT) {
    logger.warn(`CASCADE TIMEOUT SIMULATION ENABLED: ${DOWNSTREAM_TIMEOUT_MS}ms timeout for downstream calls`);
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down');
  db.end();
  redisClient.disconnect();
  if (rabbitChannel) rabbitChannel.close();
  process.exit(0);
});
