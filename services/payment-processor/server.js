const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const { v4: uuidv4 } = require('uuid');
const prometheus = require('prom-client');
const winston = require('winston');

const app = express();
const PORT = process.env.PORT || 3006;
const SERVICE_NAME = process.env.SERVICE_NAME || 'payment-processor';

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

const paymentsProcessed = new prometheus.Counter({
  name: 'payments_processed_total',
  help: 'Total payments processed',
  labelNames: ['status'],
  registers: [register]
});

const paymentDuration = new prometheus.Histogram({
  name: 'payment_processing_duration_seconds',
  help: 'Payment processing duration',
  buckets: [0.1, 0.5, 1, 2, 5, 10, 30],
  registers: [register]
});

const paymentAmount = new prometheus.Histogram({
  name: 'payment_amount_dollars',
  help: 'Payment amounts in dollars',
  buckets: [10, 50, 100, 500, 1000, 5000, 10000],
  registers: [register]
});

// =============================================================================
// Issue Simulation Flags
// =============================================================================
const ENABLE_SLOW_PAYMENTS = process.env.ENABLE_SLOW_PAYMENTS === 'true';
const PAYMENT_DELAY_MS = parseInt(process.env.PAYMENT_DELAY_MS) || 10000;
const ENABLE_PAYMENT_FAILURES = process.env.ENABLE_PAYMENT_FAILURES === 'true';
const PAYMENT_FAILURE_RATE = parseFloat(process.env.PAYMENT_FAILURE_RATE) || 0.2;

// =============================================================================
// Payment state tracking
// =============================================================================
let totalPayments = 0;
let successfulPayments = 0;
let failedPayments = 0;

// =============================================================================
// Middleware
// =============================================================================
app.use(cors());
app.use(express.json());
app.use(morgan('combined', { stream: { write: msg => logger.info(msg.trim()) } }));

// =============================================================================
// Mock External Payment Network
// =============================================================================
const PAYMENT_NETWORKS = ['SWIFT', 'ACH', 'FedWire', 'SEPA'];
const FAILURE_REASONS = [
  'INSUFFICIENT_FUNDS',
  'NETWORK_TIMEOUT',
  'INVALID_ACCOUNT',
  'BANK_REJECTED',
  'FRAUD_SUSPECTED',
  'LIMIT_EXCEEDED'
];

function simulatePaymentNetwork() {
  return PAYMENT_NETWORKS[Math.floor(Math.random() * PAYMENT_NETWORKS.length)];
}

function simulateFailureReason() {
  return FAILURE_REASONS[Math.floor(Math.random() * FAILURE_REASONS.length)];
}

// =============================================================================
// Routes
// =============================================================================

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: SERVICE_NAME,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    stats: {
      totalPayments,
      successfulPayments,
      failedPayments,
      successRate: totalPayments > 0 ? (successfulPayments / totalPayments * 100).toFixed(2) + '%' : 'N/A'
    },
    issues: {
      slowPaymentsEnabled: ENABLE_SLOW_PAYMENTS,
      paymentDelayMs: PAYMENT_DELAY_MS,
      failuresEnabled: ENABLE_PAYMENT_FAILURES,
      failureRate: PAYMENT_FAILURE_RATE
    }
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Process payment - main endpoint
app.post('/process', async (req, res) => {
  const startTime = Date.now();
  const { transactionId, fromAccountId, toAccountId, amount } = req.body;

  if (!transactionId || !fromAccountId || !toAccountId || !amount) {
    return res.status(400).json({
      success: false,
      error: 'Missing required fields'
    });
  }

  totalPayments++;
  const paymentId = uuidv4();
  const network = simulatePaymentNetwork();

  logger.info(`Processing payment ${paymentId} via ${network}: $${amount}`);

  // ISSUE SIMULATION: Slow payments
  if (ENABLE_SLOW_PAYMENTS) {
    logger.warn(`Slow payment simulation: delaying ${PAYMENT_DELAY_MS}ms`);
    await new Promise(resolve => setTimeout(resolve, PAYMENT_DELAY_MS));
  }

  // ISSUE SIMULATION: Random payment failures
  if (ENABLE_PAYMENT_FAILURES && Math.random() < PAYMENT_FAILURE_RATE) {
    const reason = simulateFailureReason();
    failedPayments++;
    paymentsProcessed.labels('failed').inc();

    const duration = (Date.now() - startTime) / 1000;
    paymentDuration.observe(duration);

    logger.error(`Payment ${paymentId} failed: ${reason}`);

    return res.status(400).json({
      success: false,
      paymentId,
      transactionId,
      error: reason,
      network,
      processingTime: `${duration}s`
    });
  }

  // Simulate successful payment
  successfulPayments++;
  paymentsProcessed.labels('success').inc();
  paymentAmount.observe(amount);

  const duration = (Date.now() - startTime) / 1000;
  paymentDuration.observe(duration);

  logger.info(`Payment ${paymentId} completed in ${duration}s`);

  res.json({
    success: true,
    paymentId,
    transactionId,
    amount,
    network,
    confirmationCode: `${network}-${Date.now()}-${Math.random().toString(36).substring(7).toUpperCase()}`,
    processingTime: `${duration}s`,
    timestamp: new Date().toISOString()
  });
});

// Check payment status
app.get('/status/:paymentId', (req, res) => {
  // Mock: Always return completed for demo
  const { paymentId } = req.params;

  res.json({
    paymentId,
    status: 'completed',
    timestamp: new Date().toISOString()
  });
});

// Refund payment
app.post('/refund', async (req, res) => {
  const { paymentId, amount, reason } = req.body;

  if (!paymentId || !amount) {
    return res.status(400).json({ error: 'paymentId and amount required' });
  }

  // Simulate refund processing
  if (ENABLE_SLOW_PAYMENTS) {
    await new Promise(resolve => setTimeout(resolve, PAYMENT_DELAY_MS / 2));
  }

  const refundId = uuidv4();

  logger.info(`Refund ${refundId} processed for payment ${paymentId}`);

  res.json({
    success: true,
    refundId,
    originalPaymentId: paymentId,
    amount,
    reason: reason || 'Customer request',
    timestamp: new Date().toISOString()
  });
});

// Network status (mock external services)
app.get('/networks', (req, res) => {
  res.json({
    networks: PAYMENT_NETWORKS.map(network => ({
      name: network,
      status: 'operational',
      latency: ENABLE_SLOW_PAYMENTS ? `${PAYMENT_DELAY_MS}ms` : '< 100ms'
    }))
  });
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

  if (ENABLE_SLOW_PAYMENTS) {
    logger.warn(`SLOW PAYMENTS SIMULATION ENABLED: ${PAYMENT_DELAY_MS}ms delay`);
  }

  if (ENABLE_PAYMENT_FAILURES) {
    logger.warn(`PAYMENT FAILURES SIMULATION ENABLED: ${PAYMENT_FAILURE_RATE * 100}% failure rate`);
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down');
  process.exit(0);
});
