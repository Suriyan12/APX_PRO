-- 1. Users Table
CREATE TABLE users (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20) UNIQUE NULL,
    full_name VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL CHECK (role IN ('patient', 'admin')),
    is_active BIT NOT NULL DEFAULT 1,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_phone ON users(phone);

-- 2. Refresh Tokens Table
CREATE TABLE refresh_tokens (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    user_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(512) UNIQUE NOT NULL,
    expires_at DATETIME2 NOT NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);
CREATE INDEX idx_refresh_tokens_token ON refresh_tokens(token);

-- 3. Discount Codes Table
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

-- Seed discount codes
INSERT INTO discount_codes (id, code, discount_type, discount_value, max_uses, is_active)
VALUES
    (NEWID(), 'APX10', 'percentage', 10.00, NULL, 1),
    (NEWID(), 'APX20', 'percentage', 20.00, NULL, 1),
    (NEWID(), 'FLAT100', 'flat', 100.00, 50, 1),
    (NEWID(), 'FLAT200', 'flat', 200.00, 20, 1);

-- 4. Appointments Table
CREATE TABLE appointments (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    patient_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES users(id) ON DELETE CASCADE,
    admin_id UNIQUEIDENTIFIER NULL FOREIGN KEY REFERENCES users(id) ON DELETE SET NULL,
    start_time DATETIME2 NOT NULL,
    end_time DATETIME2 NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'scheduled', 'completed', 'cancelled', 'rescheduled')),
    notes NVARCHAR(MAX) NULL,
    consultation_fee DECIMAL(10, 2) NOT NULL DEFAULT 500.00,
    discount_code_id UNIQUEIDENTIFIER NULL REFERENCES discount_codes(id) ON DELETE SET NULL,
    discount_code_used VARCHAR(50) NULL,
    discount_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    final_amount DECIMAL(10, 2) NOT NULL DEFAULT 500.00,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

-- 5. Medical Reports / Assessment Charts Table
CREATE TABLE medical_reports (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    patient_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES users(id) ON DELETE CASCADE,
    title NVARCHAR(150) NOT NULL,
    file_path VARCHAR(512) NOT NULL, -- S3 URL or key
    file_type VARCHAR(50) NOT NULL,
    uploaded_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

-- 5. Posture Scans Table
CREATE TABLE posture_scans (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    patient_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES users(id) ON DELETE CASCADE,
    video_path VARCHAR(512) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'uploading' CHECK (status IN ('uploading', 'pending_review', 'reviewed')),
    feedback NVARCHAR(MAX) NULL,
    reviewed_by UNIQUEIDENTIFIER NULL FOREIGN KEY REFERENCES users(id) ON DELETE SET NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

-- 6. Exercise Programs Table
CREATE TABLE exercise_programs (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    title NVARCHAR(150) NOT NULL,
    description NVARCHAR(MAX) NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

-- 7. User Assigned Programs
CREATE TABLE user_assigned_programs (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    user_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES users(id) ON DELETE CASCADE,
    program_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES exercise_programs(id) ON DELETE CASCADE,
    assigned_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    is_active BIT NOT NULL DEFAULT 1
);

-- 8. Exercises Table
CREATE TABLE exercises (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    program_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES exercise_programs(id) ON DELETE CASCADE,
    name NVARCHAR(150) NOT NULL,
    description NVARCHAR(MAX) NULL,
    video_url VARCHAR(512) NOT NULL, -- CloudFront CDN
    day_number INT NOT NULL,
    sets INT NOT NULL DEFAULT 3,
    reps INT NULL,
    duration_seconds INT NULL,
    order_index INT NOT NULL
);

-- 9. Workout Completion Log Table
CREATE TABLE workout_logs (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    user_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES users(id) ON DELETE CASCADE,
    exercise_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES exercises(id) ON DELETE CASCADE,
    completed_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

-- 10. Progress Tracking Table (Weight & Metrics)
CREATE TABLE progress_logs (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    user_id UNIQUEIDENTIFIER NOT NULL FOREIGN KEY REFERENCES users(id) ON DELETE CASCADE,
    log_date DATE NOT NULL DEFAULT CAST(GETUTCDATE() AS DATE),
    weight NUMERIC(5, 2) NULL,
    chest NUMERIC(5, 2) NULL,
    waist NUMERIC(5, 2) NULL,
    hips NUMERIC(5, 2) NULL,
    systolic_bp INT NULL,
    diastolic_bp INT NULL,
    created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_user_log_date UNIQUE (user_id, log_date)
);
