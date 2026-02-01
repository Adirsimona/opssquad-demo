const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const amqp = require('amqplib');
const redis = require('redis');
const prometheus = require('prom-client');
const winston = require('winston');

const app = express();
const PORT = process.env.PORT || 3005;
const SERVICE_NAME = process.env.SERVICE_NAME || 'notification-service';

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

const notificationsProcessed = new prometheus.Counter({
  name: 'notifications_processed_total',
  help: 'Total notifications processed',
  labelNames: ['type', 'channel'],
  registers: [register]
});

const notificationDuration = new prometheus.Histogram({
  name: 'notification_processing_duration_seconds',
  help: 'Time to process a notification',
  buckets: [0.1, 0.5, 1, 2, 5, 10],
  registers: [register]
});

const queueDepth = new prometheus.Gauge({
  name: 'notification_queue_depth',
  help: 'Current number of messages in queue',
  registers: [register]
});

const queueBacklog = new prometheus.Counter({
  name: 'notification_queue_backlog_total',
  help: 'Total messages that entered backlog',
  registers: [register]
});

// =============================================================================
// Issue Simulation Flags
// =============================================================================
const ENABLE_SLOW_CONSUMER = process.env.ENABLE_SLOW_CONSUMER === 'true';
const CONSUMER_DELAY_MS = parseInt(process.env.CONSUMER_DELAY_MS) || 5000;

// =============================================================================
// Notification state
// =============================================================================
let messagesProcessed = 0;
let currentQueueDepth = 0;
let isConsuming = false;

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
const NOTIFICATION_QUEUE = 'notifications';
let rabbitChannel = null;
let rabbitConnection = null;

async function connectRabbitMQ() {
  try {
    rabbitConnection = await amqp.connect(process.env.RABBITMQ_URL || 'amqp://fintech:fintech123@rabbitmq:5672');
    rabbitChannel = await rabbitConnection.createChannel();
    await rabbitChannel.assertQueue(NOTIFICATION_QUEUE, { durable: true });

    // Prefetch 1 message at a time (important for slow consumer scenario)
    await rabbitChannel.prefetch(1);

    logger.info('RabbitMQ connected, starting consumer');
    startConsumer();
  } catch (err) {
    logger.error('RabbitMQ connection failed:', err);
    setTimeout(connectRabbitMQ, 5000);
  }
}

// =============================================================================
// Message Consumer
// =============================================================================
async function startConsumer() {
  if (!rabbitChannel || isConsuming) return;
  isConsuming = true;

  rabbitChannel.consume(NOTIFICATION_QUEUE, async (msg) => {
    if (!msg) return;

    const startTime = Date.now();
    currentQueueDepth++;
    queueDepth.set(currentQueueDepth);

    try {
      const notification = JSON.parse(msg.content.toString());
      logger.info(`Processing notification: ${notification.type} for transaction ${notification.transactionId}`);

      // ISSUE SIMULATION: Slow consumer causing queue backlog
      if (ENABLE_SLOW_CONSUMER) {
        logger.warn(`Slow consumer: delaying ${CONSUMER_DELAY_MS}ms`);
        queueBacklog.inc();
        await new Promise(resolve => setTimeout(resolve, CONSUMER_DELAY_MS));
      }

      // Simulate sending notification
      await processNotification(notification);

      // Acknowledge message
      rabbitChannel.ack(msg);
      messagesProcessed++;
      currentQueueDepth--;
      queueDepth.set(currentQueueDepth);

      const duration = (Date.now() - startTime) / 1000;
      notificationDuration.observe(duration);
      notificationsProcessed.labels(notification.type, 'all').inc();

      logger.info(`Notification processed in ${duration}s, total: ${messagesProcessed}`);
    } catch (err) {
      logger.error('Failed to process notification:', err);
      // Negative acknowledge - requeue the message
      rabbitChannel.nack(msg, false, true);
      currentQueueDepth--;
      queueDepth.set(currentQueueDepth);
    }
  });
}

async function processNotification(notification) {
  // Simulate notification delivery
  // In production, this would call email/SMS/push services

  switch (notification.type) {
    case 'transfer_completed':
      logger.info(`[EMAIL] Transfer of $${notification.amount} completed`);
      logger.info(`[PUSH] Transaction ${notification.transactionId} successful`);
      break;

    case 'transfer_failed':
      logger.info(`[EMAIL] Transfer of $${notification.amount} failed`);
      logger.info(`[SMS] Urgent: Transaction ${notification.transactionId} failed`);
      break;

    case 'fraud_alert':
      logger.info(`[SMS] ALERT: Suspicious activity on your account`);
      logger.info(`[EMAIL] Security alert for transaction ${notification.transactionId}`);
      break;

    default:
      logger.info(`[ALL] Generic notification: ${notification.type}`);
  }

  // Store notification status in Redis
  try {
    await redisClient.setEx(
      `notification:${notification.transactionId}`,
      3600,
      JSON.stringify({
        ...notification,
        status: 'sent',
        sentAt: new Date().toISOString()
      })
    );
  } catch (err) {
    logger.error('Failed to store notification status:', err);
  }
}

// =============================================================================
// Middleware
// =============================================================================
app.use(cors());
app.use(express.json());
app.use(morgan('combined', { stream: { write: msg => logger.info(msg.trim()) } }));

// =============================================================================
// Routes
// =============================================================================

// Health check
app.get('/health', async (req, res) => {
  let rabbitStatus = rabbitChannel ? 'connected' : 'disconnected';
  let queueInfo = null;

  try {
    if (rabbitChannel) {
      const info = await rabbitChannel.checkQueue(NOTIFICATION_QUEUE);
      queueInfo = {
        messageCount: info.messageCount,
        consumerCount: info.consumerCount
      };
    }
  } catch (e) {
    queueInfo = { error: 'Failed to get queue info' };
  }

  res.json({
    status: 'healthy',
    service: SERVICE_NAME,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    stats: {
      messagesProcessed,
      currentQueueDepth
    },
    rabbitmq: rabbitStatus,
    queue: queueInfo,
    issues: {
      slowConsumerEnabled: ENABLE_SLOW_CONSUMER,
      consumerDelayMs: CONSUMER_DELAY_MS
    }
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Get notification status
app.get('/notifications/:transactionId', async (req, res) => {
  const { transactionId } = req.params;

  try {
    const status = await redisClient.get(`notification:${transactionId}`);
    if (!status) {
      return res.status(404).json({ error: 'Notification not found' });
    }
    res.json(JSON.parse(status));
  } catch (err) {
    logger.error('Failed to get notification status:', err);
    res.status(500).json({ error: 'Failed to get status' });
  }
});

// Manual notification send (for testing)
app.post('/send', async (req, res) => {
  const { type, userId, message, channel } = req.body;

  if (!type || !userId || !message) {
    return res.status(400).json({ error: 'type, userId, and message required' });
  }

  // Queue the notification
  if (rabbitChannel) {
    rabbitChannel.sendToQueue(
      NOTIFICATION_QUEUE,
      Buffer.from(JSON.stringify({
        type,
        userId,
        message,
        channel: channel || 'all',
        transactionId: `manual-${Date.now()}`,
        timestamp: new Date().toISOString()
      })),
      { persistent: true }
    );
    res.json({ success: true, message: 'Notification queued' });
  } else {
    res.status(503).json({ error: 'RabbitMQ not connected' });
  }
});

// Queue stats
app.get('/queue-stats', async (req, res) => {
  if (!rabbitChannel) {
    return res.status(503).json({ error: 'RabbitMQ not connected' });
  }

  try {
    const info = await rabbitChannel.checkQueue(NOTIFICATION_QUEUE);
    res.json({
      queue: NOTIFICATION_QUEUE,
      messageCount: info.messageCount,
      consumerCount: info.consumerCount,
      messagesProcessed,
      slowConsumerActive: ENABLE_SLOW_CONSUMER
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get queue stats' });
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

  if (ENABLE_SLOW_CONSUMER) {
    logger.warn(`SLOW CONSUMER SIMULATION ENABLED: ${CONSUMER_DELAY_MS}ms delay per message`);
  }

  // Connect to RabbitMQ
  connectRabbitMQ();
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down');
  isConsuming = false;
  if (rabbitChannel) rabbitChannel.close();
  if (rabbitConnection) rabbitConnection.close();
  redisClient.disconnect();
  process.exit(0);
});
