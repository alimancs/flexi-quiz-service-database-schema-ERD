
CREATE DATABASE quiz_service;
\c quiz_service

-- ------------------------------------------------------------
-- 1. USERS
-- ------------------------------------------------------------
CREATE TABLE users (
    id            BIGSERIAL     PRIMARY KEY,
    email         VARCHAR(150)  NOT NULL UNIQUE,
    password_hash VARCHAR(255)  NOT NULL,
    full_name     VARCHAR(120)  NOT NULL,
    role          VARCHAR(20)   NOT NULL DEFAULT 'STUDENT'
                  CHECK (role IN ('STUDENT', 'LECTURER', 'ADMIN')),
    is_active     BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_users_email CHECK (email LIKE '%@%.%')
);

-- ------------------------------------------------------------
-- 2. TOPICS  (for per-topic analytics)
-- ------------------------------------------------------------
CREATE TABLE topics (
    id          SERIAL       PRIMARY KEY,
    name        VARCHAR(80)  NOT NULL UNIQUE,
    description TEXT
);

-- ------------------------------------------------------------
-- 3. EXAMS
-- ------------------------------------------------------------
CREATE TABLE exams (
    id               BIGSERIAL    PRIMARY KEY,
    title            VARCHAR(150) NOT NULL,
    description      TEXT,
    lecturer_id      BIGINT       NOT NULL,
    duration_minutes INT          NOT NULL CHECK (duration_minutes > 0),
    pass_mark        NUMERIC(5,2) NOT NULL DEFAULT 50
                     CHECK (pass_mark BETWEEN 0 AND 100),
    max_attempts     SMALLINT     NOT NULL DEFAULT 1
                     CHECK (max_attempts > 0),
    status           VARCHAR(20)  NOT NULL DEFAULT 'DRAFT'
                     CHECK (status IN ('DRAFT','PUBLISHED','CLOSED','ARCHIVED')),
    opens_at         TIMESTAMPTZ,
    closes_at        TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_exams_lecturer
        FOREIGN KEY (lecturer_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT chk_exams_window
        CHECK (closes_at IS NULL OR opens_at IS NULL OR closes_at > opens_at)
);

-- ------------------------------------------------------------
-- 4. QUESTIONS
-- ------------------------------------------------------------
CREATE TABLE questions (
    id             BIGSERIAL    PRIMARY KEY,
    exam_id        BIGINT       NOT NULL,
    topic_id       INT,
    question_text  TEXT         NOT NULL,
    marks          NUMERIC(5,2) NOT NULL DEFAULT 1 CHECK (marks > 0),
    negative_marks NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (negative_marks >= 0),
    order_index    INT          NOT NULL,

    CONSTRAINT fk_questions_exam
        FOREIGN KEY (exam_id) REFERENCES exams(id) ON DELETE CASCADE,
    CONSTRAINT fk_questions_topic
        FOREIGN KEY (topic_id) REFERENCES topics(id) ON DELETE SET NULL,
    CONSTRAINT uq_questions_order
        UNIQUE (exam_id, order_index),
    CONSTRAINT chk_questions_negative_le_marks
        CHECK (negative_marks <= marks)
);

-- ------------------------------------------------------------
-- 5. OPTIONS  (answer choices)
-- ------------------------------------------------------------
CREATE TABLE options (
    id          BIGSERIAL PRIMARY KEY,
    question_id BIGINT    NOT NULL,
    option_text TEXT      NOT NULL,
    is_correct  BOOLEAN   NOT NULL DEFAULT FALSE,
    order_index SMALLINT  NOT NULL,

    CONSTRAINT fk_options_question
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE,
    CONSTRAINT uq_options_order
        UNIQUE (question_id, order_index),
    -- Enables the composite FK used in attempt_answers (see below)
    CONSTRAINT uq_options_question_id
        UNIQUE (question_id, id)
);

-- ------------------------------------------------------------
-- 6. ATTEMPTS  (one sitting of one exam by one student)
-- ------------------------------------------------------------
CREATE TABLE attempts (
    id            BIGSERIAL    PRIMARY KEY,
    exam_id       BIGINT       NOT NULL,
    student_id    BIGINT       NOT NULL,
    attempt_token UUID         NOT NULL UNIQUE,      -- secure token
    status        VARCHAR(20)  NOT NULL DEFAULT 'IN_PROGRESS'
                  CHECK (status IN ('IN_PROGRESS','SUBMITTED','EXPIRED','GRADED')),
    started_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ  NOT NULL,             -- server-side timing
    submitted_at  TIMESTAMPTZ,
    score         NUMERIC(6,2),
    total_marks   NUMERIC(6,2),
    percentage    NUMERIC(5,2),
    ip_address    INET,

    CONSTRAINT fk_attempts_exam
        FOREIGN KEY (exam_id) REFERENCES exams(id) ON DELETE RESTRICT,
    CONSTRAINT fk_attempts_student
        FOREIGN KEY (student_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT chk_attempts_window
        CHECK (expires_at > started_at),
    CONSTRAINT chk_attempts_submitted_after_start
        CHECK (submitted_at IS NULL OR submitted_at >= started_at),
    CONSTRAINT chk_attempts_score_range
        CHECK (percentage IS NULL OR percentage BETWEEN 0 AND 100)
);

-- Business rule: at most ONE active attempt per student per exam
CREATE UNIQUE INDEX uq_one_active_attempt_per_exam
    ON attempts (exam_id, student_id)
    WHERE status = 'IN_PROGRESS';

-- Speeds up leaderboard queries
CREATE INDEX idx_attempts_exam_status_score
    ON attempts (exam_id, status, score DESC);

-- ------------------------------------------------------------
-- 7. ATTEMPT_ANSWERS  (one answer inside an attempt)
-- ------------------------------------------------------------
CREATE TABLE attempt_answers (
    id                 BIGSERIAL    PRIMARY KEY,
    attempt_id         BIGINT       NOT NULL,
    question_id        BIGINT       NOT NULL,
    selected_option_id BIGINT,
    is_correct         BOOLEAN      NOT NULL DEFAULT FALSE,
    marks_awarded      NUMERIC(5,2) NOT NULL DEFAULT 0,
    answered_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_answers_attempt
        FOREIGN KEY (attempt_id) REFERENCES attempts(id) ON DELETE CASCADE,
    CONSTRAINT fk_answers_question
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE RESTRICT,

    -- 🔒 DOUBLE-SUBMIT PROTECTION: one answer per question per attempt
    CONSTRAINT uq_answers_attempt_question
        UNIQUE (attempt_id, question_id),

    -- 🔒 ADVANCED: guarantees the selected option actually belongs
    --    to the question being answered (cross-table integrity)
    CONSTRAINT fk_answers_option_belongs_to_question
        FOREIGN KEY (question_id, selected_option_id)
        REFERENCES options (question_id, id)
);

-- ------------------------------------------------------------
-- 8. VIEW: Leaderboard per exam
-- ------------------------------------------------------------
CREATE VIEW v_exam_leaderboard AS
WITH best_per_student AS (
    SELECT
        a.exam_id,
        a.student_id,
        MAX(a.score)        AS best_score,
        MIN(a.submitted_at) AS first_submitted_at   -- tie-breaker
    FROM attempts a
    WHERE a.status = 'GRADED'
    GROUP BY a.exam_id, a.student_id
)
SELECT
    b.exam_id,
    e.title                                AS exam_title,
    b.student_id,
    u.full_name                            AS student_name,
    b.best_score,
    b.first_submitted_at,
    RANK() OVER (
        PARTITION BY b.exam_id
        ORDER BY b.best_score DESC, b.first_submitted_at ASC
    )                                      AS rank
FROM best_per_student b
JOIN exams e ON e.id = b.exam_id
JOIN users u ON u.id = b.student_id;

-- ------------------------------------------------------------
-- 9. VIEW: Per-topic performance analytics
-- ------------------------------------------------------------
CREATE VIEW v_topic_performance AS
SELECT
    a.exam_id,
    a.student_id,
    q.topic_id,
    COALESCE(t.name, 'Unclassified')                       AS topic_name,
    COUNT(*)                                               AS questions_answered,
    COUNT(*) FILTER (WHERE aa.is_correct)                  AS correct_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE aa.is_correct) / COUNT(*),
        2
    )                                                      AS accuracy_pct
FROM attempt_answers aa
JOIN attempts  a ON a.id = aa.attempt_id
JOIN questions q ON q.id = aa.question_id
LEFT JOIN topics t ON t.id = q.topic_id
GROUP BY a.exam_id, a.student_id, q.topic_id, t.name;
