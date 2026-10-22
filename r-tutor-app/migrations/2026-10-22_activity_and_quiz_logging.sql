-- Adds active-time and quiz-response logging (see activity_time /
-- quiz_responses in schema.sql for what each column means). Additive only --
-- no existing table or row is modified. Paste into the Supabase SQL Editor
-- (Dashboard > SQL Editor > New query) and run.

create table activity_time (
  activity_id     bigserial primary key,
  student_id      uuid not null references students(student_id),
  topic_id        text not null,
  module_number   int,
  active_seconds  int not null check (active_seconds > 0),
  window_start    timestamptz not null,
  window_end      timestamptz not null,
  created_at      timestamptz not null default now()
);

create table quiz_responses (
  response_id    bigserial primary key,
  student_id     uuid not null references students(student_id),
  quiz_key       text not null,
  module_number  int,
  choice_id      text not null,
  correct        boolean not null,
  created_at     timestamptz not null default now()
);

create index idx_activity_student on activity_time(student_id);
create index idx_quiz_student on quiz_responses(student_id);
create index idx_quiz_key on quiz_responses(quiz_key);
