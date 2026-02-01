const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const redis = require('redis');
const prometheus = require('prom-client');
const winston = require('winston');

const app = express();
const PORT = process.env.PORT || 3001;
const SERVICE_NAME = process.env.SERVICE_NAME || 'auth-service';

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
  transports: [
    new winston.transports.Console()
  ]
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

const authFailures = new prometheus.Counter({
  name: 'auth_failures_total',
  help: 'Total authentication failures',
  labelNames: ['reason'],
  registers: [register]
});

const tokenVerifications = new prometheus.Counter({
  name: 'token_verifications_total',
  help: 'Total token verifications',
  labelNames: ['status'],
  registers: [register]
});

// =============================================================================
// Redis Connection
// =============================================================================
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://redis:6379',
  socket: {
    reconnectStrategy: (retries) => {
      logger.warn(`Redis reconnection attempt ${retries}`);
      if (retries > 10) {
        return new Error('Redis max retries reached');
      }
      return Math.min(retries * 100, 3000);
    }
  }
});

redisClient.on('error', (err) => logger.error('Redis error:', err));
redisClient.on('connect', () => logger.info('Redis connected'));
redisClient.connect().catch(err => logger.error('Redis connection failed:', err));

// =============================================================================
// Issue Simulation Flags
// =============================================================================
const ENABLE_TOKEN_FAILURE = process.env.ENABLE_TOKEN_FAILURE === 'true';
const TOKEN_FAILURE_RATE = parseFloat(process.env.TOKEN_FAILURE_RATE) || 0.3;

// =============================================================================
// Middleware
// =============================================================================
app.use(cors());
app.use(express.json());
app.use(morgan('combined', { stream: { write: msg => logger.info(msg.trim()) } }));

// Metrics middleware
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
// Demo Users (In production, this would be database)
// =============================================================================
const DEMO_USERS = {
  'john.smith@example.com': {
    id: '11111111-1111-1111-1111-111111111111',
    email: 'john.smith@example.com',
    password: '$2b$10$rOzJqQZQZQZQZQZQZQZQZu1234567890abcdefghijk', // password: demo123
    firstName: 'John',
    lastName: 'Smith'
  },
  'jane.doe@example.com': {
    id: '22222222-2222-2222-2222-222222222222',
    email: 'jane.doe@example.com',
    password: '$2b$10$rOzJqQZQZQZQZQZQZQZQZu1234567890abcdefghijk',
    firstName: 'Jane',
    lastName: 'Doe'
  }
};

// =============================================================================
// Routes
// =============================================================================

// Health check
app.get('/health', async (req, res) => {
  let redisStatus = 'disconnected';
  try {
    await redisClient.ping();
    redisStatus = 'connected';
  } catch (e) {
    redisStatus = 'error';
  }

  res.json({
    status: 'healthy',
    service: SERVICE_NAME,
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    redis: redisStatus,
    issues: {
      tokenFailureEnabled: ENABLE_TOKEN_FAILURE,
      tokenFailureRate: TOKEN_FAILURE_RATE
    }
  });
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Login
app.post('/login', async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    authFailures.labels('missing_credentials').inc();
    return res.status(400).json({ error: 'Email and password required' });
  }

  // Demo: Accept any password for demo users
  const user = DEMO_USERS[email];
  if (!user) {
    authFailures.labels('user_not_found').inc();
    logger.warn(`Login failed: user not found - ${email}`);
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  // Generate JWT token
  const token = jwt.sign(
    { userId: user.id, email: user.email },
    process.env.JWT_SECRET || 'fintech-demo-secret',
    { expiresIn: process.env.JWT_EXPIRY || '1h' }
  );

  // Store session in Redis
  const sessionId = uuidv4();
  try {
    await redisClient.setEx(`session:${sessionId}`, 3600, JSON.stringify({
      userId: user.id,
      email: user.email,
      createdAt: new Date().toISOString()
    }));
  } catch (err) {
    logger.error('Failed to store session in Redis:', err);
  }

  logger.info(`User logged in: ${email}`);

  res.json({
    token,
    sessionId,
    user: {
      id: user.id,
      email: user.email,
      firstName: user.firstName,
      lastName: user.lastName
    }
  });
});

// Verify token
app.post('/verify', async (req, res) => {
  const { token } = req.body;
  const authHeader = req.headers.authorization;
  const tokenToVerify = token || (authHeader?.startsWith('Bearer ') ? authHeader.substring(7) : null);

  if (!tokenToVerify) {
    tokenVerifications.labels('missing_token').inc();
    return res.status(400).json({ error: 'Token required' });
  }

  // ISSUE SIMULATION: Random token verification failures
  if (ENABLE_TOKEN_FAILURE && Math.random() < TOKEN_FAILURE_RATE) {
    tokenVerifications.labels('simulated_failure').inc();
    logger.warn('Token verification failed (simulated failure)');
    return res.status(401).json({ error: 'Token verification failed' });
  }

  try {
    const decoded = jwt.verify(tokenToVerify, process.env.JWT_SECRET || 'fintech-demo-secret');
    tokenVerifications.labels('success').inc();
    res.json({ valid: true, user: decoded });
  } catch (err) {
    tokenVerifications.labels('invalid_token').inc();
    logger.warn('Token verification failed:', err.message);
    res.status(401).json({ error: 'Invalid token', reason: err.message });
  }
});

// Logout
app.post('/logout', async (req, res) => {
  const { sessionId } = req.body;

  if (sessionId) {
    try {
      await redisClient.del(`session:${sessionId}`);
      logger.info(`Session destroyed: ${sessionId}`);
    } catch (err) {
      logger.error('Failed to destroy session:', err);
    }
  }

  res.json({ success: true });
});

// Refresh token
app.post('/refresh', async (req, res) => {
  const { token } = req.body;

  if (!token) {
    return res.status(400).json({ error: 'Token required' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'fintech-demo-secret', { ignoreExpiration: true });

    // Generate new token
    const newToken = jwt.sign(
      { userId: decoded.userId, email: decoded.email },
      process.env.JWT_SECRET || 'fintech-demo-secret',
      { expiresIn: process.env.JWT_EXPIRY || '1h' }
    );

    res.json({ token: newToken });
  } catch (err) {
    res.status(401).json({ error: 'Invalid token' });
  }
});

// Get sessions (for debugging)
app.get('/sessions/:userId', async (req, res) => {
  // In production, this would query Redis for user sessions
  res.json({ sessions: [], note: 'Demo endpoint' });
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

  if (ENABLE_TOKEN_FAILURE) {
    logger.warn(`TOKEN FAILURE SIMULATION ENABLED: ${TOKEN_FAILURE_RATE * 100}% of verifications will fail`);
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down');
  redisClient.disconnect();
  process.exit(0);
});
