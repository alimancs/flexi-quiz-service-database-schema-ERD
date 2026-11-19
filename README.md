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
    ...
