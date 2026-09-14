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
create table exercises (
  exercise_id   serial primary key,
  module_id     int not null references modules(module_id),
  exercise_key  text not null unique,
  title         text not null,
  order_index   int not null
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
create table chat_logs (
  chat_id      bigserial primary key,
  student_id   uuid not null references students(student_id),
  exercise_id  int not null references exercises(exercise_id),
  role         text not null check (role in ('student', 'tutor')),
  message      text not null,
  created_at   timestamptz not null default now()
);

-- Indexes to keep dashboard queries fast as data grows.
create index idx_attempts_student on exercise_attempts(student_id);
create index idx_attempts_exercise on exercise_attempts(exercise_id);
create index idx_chat_student on chat_logs(student_id);
create index idx_chat_exercise on chat_logs(exercise_id);

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
