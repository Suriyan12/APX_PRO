-- Migration 001: Add discount_codes table and pricing columns to appointments
-- Run this once against an existing database.
-- For a FRESH install use schema.sql instead (it already includes these).

-- 1. Discount Codes Table
CREATE TABLE discount_codes (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    code VARCHAR(50) UNIQUE NOT NULL,
    discount_type VARCHAR(20) NOT NULL CHECK (discount_type IN ('percentage', 'flat')),
    discount_value DECIMAL(10, 2) NOT NULL,
    max_uses INT NULL,
    used_count INT NOT NULL DEFAULT 0,
    valid_from DATETIME2 NULL,
    valid_until DATETIME2 NULL,
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
CREATE INDEX idx_discount_codes_code ON discount_codes(code);

-- 2. Add pricing columns to appointments (existing rows get sensible defaults)
ALTER TABLE appointments ADD consultation_fee DECIMAL(10, 2) NOT NULL DEFAULT 500.00;
ALTER TABLE appointments ADD discount_code_id UNIQUEIDENTIFIER NULL REFERENCES discount_codes(id) ON DELETE SET NULL;
ALTER TABLE appointments ADD discount_code_used VARCHAR(50) NULL;
ALTER TABLE appointments ADD discount_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE appointments ADD final_amount DECIMAL(10, 2) NOT NULL DEFAULT 500.00;

-- 3. Seed: example discount codes for testing
INSERT INTO discount_codes (id, code, discount_type, discount_value, max_uses, is_active)
VALUES
    (NEWID(), 'APX10', 'percentage', 10.00, NULL, 1),   -- 10% off, unlimited
    (NEWID(), 'APX20', 'percentage', 20.00, NULL, 1),   -- 20% off, unlimited
    (NEWID(), 'FLAT100', 'flat', 100.00, 50, 1),        -- ₹100 off, 50 uses
    (NEWID(), 'FLAT200', 'flat', 200.00, 20, 1);        -- ₹200 off, 20 uses
