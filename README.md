# Quiz/Exam Service Database Schema & ERD

📌 1. Entity List
Entity	Purpose	Type
users	Students, lecturers, admins	Strong entity
topics	Subject areas for per-topic analytics	Strong entity
exams	An assessment created by a lecturer	Strong entity
questions	MCQ belonging to one exam	Weak (owned by exam)
options	Answer choices for a question	Weak (owned by question)
attempts	One student's sitting of one exam	Associative entity (resolves student ↔ exam)
attempt_answers	One answer within an attempt	Associative entity (resolves attempt ↔ question)
v_exam_leaderboard	Ranked results per exam	View (derived)

```erDiagram
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
```


