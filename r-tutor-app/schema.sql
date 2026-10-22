-- =====================================================
-- R Tutor App: Initial Database Schema
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New query)
-- =====================================================

-- students: one row per learner.
-- Identity is generic for now (no roster/Canvas matching yet) --
-- first_login_at being NULL is the "has not started" signal for the dashboard.
create table students (
  student_id      uuid primary key default gen_random_uuid(),
  display_name    text not null,
  email           text unique,
  first_login_at  timestamptz,
  last_active_at  timestamptz,
  created_at      timestamptz not null default now()
);

-- modules: the 5 curriculum modules (Introduction, Basic Code, Data, Clean up, Actual Work)
create table modules (
  module_id     serial primary key,
  module_number int not null unique,
  title         text not null
);

-- exercises: individual learnr exercises within a module.
-- exercise_key must match the label used inside the learnr .Rmd exercise chunk.
-- learning_objective is plain-language and given to the LLM tutor for context --
-- it must never describe or hint at the actual correct answer.
create table exercises (
  exercise_id         serial primary key,
  module_id           int not null references modules(module_id),
  exercise_key        text not null unique,
  title               text not null,
  order_index         int not null,
  learning_objective  text
);

-- exercise_attempts: one row per submission (every attempt kept, per your call).
create table exercise_attempts (
  attempt_id        bigserial primary key,
  student_id        uuid not null references students(student_id),
  exercise_id       int not null references exercises(exercise_id),
  submitted_code    text,
  passed            boolean not null,
  gradethis_message text,
  created_at        timestamptz not null default now()
);

-- chat_logs: every tutor conversation message, tied to student + exercise context.
-- help_category is filled in later, offline, by R/classify_chat_messages.R --
-- NULL means "not yet classified" (or, for role='tutor' rows, "not applicable";
-- only student messages are ever classified). Never set by the live tutorial
-- or dashboard apps directly.
create table chat_logs (
  chat_id       bigserial primary key,
  student_id    uuid not null references students(student_id),
  exercise_id   int not null references exercises(exercise_id),
  role          text not null check (role in ('student', 'tutor')),
  message       text not null,
  help_category text check (help_category in (
    'syntax_error', 'conceptual_confusion', 'how_do_i_start',
    'wants_answer', 'environment_setup', 'other'
  )),
  created_at    timestamptz not null default now()
);

-- activity_time: how long a student was ACTIVELY on each learnr `##` topic.
-- Written by activity_tracker_server() (R/tutor_utils.R), which accumulates
-- client-reported active seconds per topic and flushes one row per topic
-- every couple of minutes and at session end -- so a single visit to a topic
-- can span several rows; always SUM(active_seconds), never read one row as
-- "the visit". "Active" = tab visible AND a mouse/keyboard/scroll event in
-- the last 90 seconds, so a tab left open overnight doesn't count.
-- topic_id is learnr's own topic anchor (e.g. 'module-4-indexing-and-subsetting');
-- module_number is parsed from it at write time (NULL if it doesn't parse).
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

-- quiz_responses: one row per quiz submission (every retry kept, same
-- philosophy as exercise_attempts). quiz_key is the quiz's input_id in
-- course.Rmd (e.g. 'indexing_quiz'); choice_id is the internal ID of the
-- option picked (e.g. 'wrong_compare') -- distractor IDs are deliberately
-- descriptive, so which wrong answer gets picked is itself useful signal.
create table quiz_responses (
  response_id    bigserial primary key,
  student_id     uuid not null references students(student_id),
  quiz_key       text not null,
  module_number  int,
  choice_id      text not null,
  correct        boolean not null,
  created_at     timestamptz not null default now()
);

-- Indexes to keep dashboard queries fast as data grows.
create index idx_attempts_student on exercise_attempts(student_id);
create index idx_attempts_exercise on exercise_attempts(exercise_id);
create index idx_chat_student on chat_logs(student_id);
create index idx_chat_exercise on chat_logs(exercise_id);
create index idx_activity_student on activity_time(student_id);
create index idx_quiz_student on quiz_responses(student_id);
create index idx_quiz_key on quiz_responses(quiz_key);

-- exercise_mastery: a VIEW (not a table) giving each student's most recent
-- pass/fail status per exercise, computed live from exercise_attempts.
-- This is what dashboard "mastery achieved" queries should read from.
create view exercise_mastery as
select distinct on (student_id, exercise_id)
  student_id,
  exercise_id,
  passed,
  created_at as last_attempt_at
from exercise_attempts
order by student_id, exercise_id, created_at desc;
