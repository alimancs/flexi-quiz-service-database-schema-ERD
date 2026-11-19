# Flexi Quiz Service Database Schema & ERD

## Domain
Quiz/Exam Service (question bank, attempts, leaderboard, topic analytics).

## Artifacts
- `erd/quiz-service-erd.pdf` – Entity Relationship Diagram (PDF)
- `sql/schema.sql` – Full PostgreSQL DDL
- `erd/quiz-service-erd.dbml` – dbdiagram.io source

## Entities
| Entity | Type | Purpose |
|--------|------|---------|
| users | Strong | Students, lecturers, admins |
| topics | Strong | Subject areas for analytics |
| exams | Strong | Assessments created by lecturers |
| questions | Weak (owned by exam) | MCQ items |
| options | Weak (owned by question) | Answer choices |
| attempts | Associative | One student's sitting of one exam |
| attempt_answers | Associative | One answer within an attempt |

## Relationships
- users 1—N exams (lecturer creates)
- users 1—N attempts (student takes)
- exams 1—N questions
- questions 1—N options
- topics 1—N questions
- attempts 1—N attempt_answers
- **users N—M exams** resolved via `attempts`
- **attempts N—M questions** resolved via `attempt_answers`

## Keys & Constraints
See `sql/schema.sql`. Highlights:
- `attempts.attempt_token` UUID UNIQUE (secure token)
- Partial unique index: one active attempt per student per exam
- `UNIQUE (attempt_id, question_id)` → double-submit protection
- Composite FK ensures selected option belongs to the answered question
- CHECK constraints on role, status, score ranges, and timing windows

## Views
- `v_exam_leaderboard` – ranked results per exam (best score, tie-break by time)
- `v_topic_performance` – per-topic accuracy per attempt

## ERD Diagram
```mermaid
erDiagram
    USERS ||--o{ EXAMS : "creates"
    USERS ||--o{ ATTEMPTS : "takes"
    EXAMS ||--o{ QUESTIONS : "contains"
    EXAMS ||--o{ ATTEMPTS : "is_taken_in"
    TOPICS ||--o{ QUESTIONS : "classifies"
    QUESTIONS ||--o{ OPTIONS : "has"
    ATTEMPTS ||--o{ ATTEMPT_ANSWERS : "records"
    QUESTIONS ||--o{ ATTEMPT_ANSWERS : "answered_in"
    OPTIONS ||--o{ ATTEMPT_ANSWERS : "selected_as"

    USERS {
        bigint id PK
        varchar email UK
        varchar password_hash
        varchar full_name
        varchar role
        boolean is_active
        timestamptz created_at
    }

    TOPICS {
        serial id PK
        varchar name UK
        text description
    }

    EXAMS {
        bigint id PK
        varchar title
        text description
        bigint lecturer_id FK
        int duration_minutes
        numeric pass_mark
        smallint max_attempts
        varchar status
        timestamptz opens_at
        timestamptz closes_at
        timestamptz created_at
    }

    QUESTIONS {
        bigint id PK
        bigint exam_id FK
        int topic_id FK
        text question_text
        numeric marks
        numeric negative_marks
        int order_index
    }

    OPTIONS {
        bigint id PK
        bigint question_id FK
        text option_text
        boolean is_correct
        smallint order_index
    }

    ATTEMPTS {
        bigint id PK
        bigint exam_id FK
        bigint student_id FK
        uuid attempt_token UK
        varchar status
        timestamptz started_at
        timestamptz expires_at
        timestamptz submitted_at
        numeric score
        numeric total_marks
        numeric percentage
        inet ip_address
    }

    ATTEMPT_ANSWERS {
        bigint id PK
        bigint attempt_id FK
        bigint question_id FK
        bigint selected_option_id FK
        boolean is_correct
        numeric marks_awarded
        timestamptz answered_at
    }
