-- FinTech Demo Database Schema
-- This creates a realistic banking database for demo purposes

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- Users Table
-- =============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'closed')),
    kyc_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status);

-- =============================================================================
-- Accounts Table
-- =============================================================================
CREATE TABLE accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id),
    account_number VARCHAR(20) UNIQUE NOT NULL,
    account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('checking', 'savings', 'investment')),
    currency VARCHAR(3) DEFAULT 'USD',
    balance DECIMAL(15, 2) DEFAULT 0.00,
    available_balance DECIMAL(15, 2) DEFAULT 0.00,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'frozen', 'closed')),
    daily_limit DECIMAL(15, 2) DEFAULT 10000.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_accounts_user ON accounts(user_id);
CREATE INDEX idx_accounts_number ON accounts(account_number);
CREATE INDEX idx_accounts_status ON accounts(status);

-- =============================================================================
-- Transactions Table
-- =============================================================================
CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    from_account_id UUID REFERENCES accounts(id),
    to_account_id UUID REFERENCES accounts(id),
    transaction_type VARCHAR(30) NOT NULL CHECK (transaction_type IN ('transfer', 'deposit', 'withdrawal', 'payment', 'refund', 'fee')),
    amount DECIMAL(15, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'reversed')),
    description TEXT,
    reference_id VARCHAR(50),
    fraud_score DECIMAL(5, 4),
    fraud_check_status VARCHAR(20) CHECK (fraud_check_status IN ('pending', 'approved', 'flagged', 'rejected')),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_transactions_from_account ON transactions(from_account_id);
CREATE INDEX idx_transactions_to_account ON transactions(to_account_id);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_created ON transactions(created_at DESC);
CREATE INDEX idx_transactions_type ON transactions(transaction_type);

-- =============================================================================
-- Notifications Table
-- =============================================================================
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id),
    type VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    channel VARCHAR(20) CHECK (channel IN ('email', 'sms', 'push', 'in_app')),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'failed')),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_status ON notifications(status);

-- =============================================================================
-- Audit Log Table
-- =============================================================================
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50),
    resource_id UUID,
    ip_address INET,
    user_agent TEXT,
    details JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_user ON audit_log(user_id);
CREATE INDEX idx_audit_action ON audit_log(action);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);

-- =============================================================================
-- Sessions Table (for Redis backup/persistence)
-- =============================================================================
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id),
    token_hash VARCHAR(255) NOT NULL,
    device_info JSONB DEFAULT '{}',
    ip_address INET,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);

-- =============================================================================
-- Seed Data - Demo Users
-- =============================================================================
INSERT INTO users (id, email, password_hash, first_name, last_name, phone, kyc_verified) VALUES
    ('11111111-1111-1111-1111-111111111111', 'john.smith@example.com', '$2b$10$demo-hash-1', 'John', 'Smith', '+1-555-0101', true),
    ('22222222-2222-2222-2222-222222222222', 'jane.doe@example.com', '$2b$10$demo-hash-2', 'Jane', 'Doe', '+1-555-0102', true),
    ('33333333-3333-3333-3333-333333333333', 'bob.wilson@example.com', '$2b$10$demo-hash-3', 'Bob', 'Wilson', '+1-555-0103', true),
    ('44444444-4444-4444-4444-444444444444', 'alice.johnson@example.com', '$2b$10$demo-hash-4', 'Alice', 'Johnson', '+1-555-0104', false),
    ('55555555-5555-5555-5555-555555555555', 'charlie.brown@example.com', '$2b$10$demo-hash-5', 'Charlie', 'Brown', '+1-555-0105', true);

-- =============================================================================
-- Seed Data - Demo Accounts
-- =============================================================================
INSERT INTO accounts (id, user_id, account_number, account_type, balance, available_balance) VALUES
    -- John Smith's accounts
    ('aaaa1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'CHK-001-12345', 'checking', 15000.00, 14500.00),
    ('aaaa2222-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'SAV-001-12345', 'savings', 50000.00, 50000.00),
    -- Jane Doe's accounts
    ('bbbb1111-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'CHK-002-12345', 'checking', 8500.00, 8500.00),
    ('bbbb2222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222', 'INV-002-12345', 'investment', 125000.00, 125000.00),
    -- Bob Wilson's accounts
    ('cccc1111-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'CHK-003-12345', 'checking', 3200.00, 3200.00),
    -- Alice Johnson's accounts
    ('dddd1111-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', 'CHK-004-12345', 'checking', 12000.00, 11500.00),
    ('dddd2222-4444-4444-4444-444444444444', '44444444-4444-4444-4444-444444444444', 'SAV-004-12345', 'savings', 35000.00, 35000.00),
    -- Charlie Brown's accounts
    ('eeee1111-5555-5555-5555-555555555555', '55555555-5555-5555-5555-555555555555', 'CHK-005-12345', 'checking', 950.00, 950.00);

-- =============================================================================
-- Seed Data - Sample Transactions
-- =============================================================================
INSERT INTO transactions (from_account_id, to_account_id, transaction_type, amount, status, description, fraud_score, fraud_check_status, created_at) VALUES
    -- Recent transfers
    ('aaaa1111-1111-1111-1111-111111111111', 'bbbb1111-2222-2222-2222-222222222222', 'transfer', 500.00, 'completed', 'Monthly rent payment', 0.05, 'approved', NOW() - INTERVAL '2 hours'),
    ('bbbb1111-2222-2222-2222-222222222222', 'cccc1111-3333-3333-3333-333333333333', 'transfer', 150.00, 'completed', 'Dinner split', 0.02, 'approved', NOW() - INTERVAL '4 hours'),
    ('dddd1111-4444-4444-4444-444444444444', 'eeee1111-5555-5555-5555-555555555555', 'transfer', 200.00, 'completed', 'Gift', 0.03, 'approved', NOW() - INTERVAL '1 day'),
    -- Pending transactions
    ('aaaa1111-1111-1111-1111-111111111111', 'cccc1111-3333-3333-3333-333333333333', 'transfer', 1000.00, 'pending', 'Invoice payment', NULL, 'pending', NOW() - INTERVAL '5 minutes'),
    ('bbbb1111-2222-2222-2222-222222222222', 'dddd1111-4444-4444-4444-444444444444', 'transfer', 750.00, 'processing', 'Service fee', 0.15, 'approved', NOW() - INTERVAL '10 minutes');

-- =============================================================================
-- Helper function for updated_at
-- =============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON accounts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- Grant permissions
-- =============================================================================
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO fintech;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO fintech;
