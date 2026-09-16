# R/db_utils.R
# Shared database helper functions for the R Tutor app.
# Both the student-facing tutorial app and the instructor dashboard
# source this file so database logic never has to be duplicated.

library(DBI)
library(RPostgres)

#' Open a connection to the Supabase Postgres database.
#' Reads connection details from environment variables set in .Renviron.
#' connect_timeout caps how long a hung/unreachable connection attempt can
#' block the single-threaded Shiny process -- without it, a stalled network
#' connection (a flaky wifi hiccup, a VPN, a Supabase blip) freezes the
#' entire app indefinitely with no error and no spinner, since every
#' identity/exercise/chat action opens a fresh connection synchronously.
get_con <- function() {
  dbConnect(
    RPostgres::Postgres(),
    dbname          = "postgres",
    host            = Sys.getenv("SUPABASE_DB_HOST"),
    port            = 5432,
    user            = Sys.getenv("SUPABASE_DB_USER"),
    password        = Sys.getenv("SUPABASE_DB_PASSWORD"),
    connect_timeout = 10
  )
}

#' Look up a student by display name (temporary identity scheme --
#' no roster/Canvas matching yet). Creates a new student row if one
#' doesn't already exist, and stamps first_login_at / last_active_at.
get_or_create_student <- function(con, display_name) {
  existing <- dbGetQuery(
    con,
    "SELECT student_id FROM students WHERE display_name = $1",
    params = list(display_name)
  )
  
  if (nrow(existing) > 0) {
    student_id <- existing$student_id[1]
    dbExecute(
      con,
      "UPDATE students SET last_active_at = now() WHERE student_id = $1",
      params = list(student_id)
    )
  } else {
    result <- dbGetQuery(
      con,
      "INSERT INTO students (display_name, first_login_at, last_active_at)
       VALUES ($1, now(), now())
       RETURNING student_id",
      params = list(display_name)
    )
    student_id <- result$student_id[1]
  }
  
  student_id
}

#' Look up an exercise's internal ID from its exercise_key
#' (the label used inside the learnr .Rmd exercise chunk).
get_exercise_id <- function(con, exercise_key) {
  result <- dbGetQuery(
    con,
    "SELECT exercise_id FROM exercises WHERE exercise_key = $1",
    params = list(exercise_key)
  )
  if (nrow(result) == 0) {
    stop(paste0(
      "No exercise found with key: ", exercise_key,
      " -- has it been added to the exercises table yet?"
    ))
  }
  result$exercise_id[1]
}

#' Record one exercise attempt. Called every time a student submits
#' an exercise, whether it passes gradethis's check or not.
log_attempt <- function(con, student_id, exercise_id, submitted_code, passed, gradethis_message) {
  dbExecute(
    con,
    "INSERT INTO exercise_attempts
       (student_id, exercise_id, submitted_code, passed, gradethis_message)
     VALUES ($1, $2, $3, $4, $5)",
    params = list(student_id, exercise_id, submitted_code, passed, gradethis_message)
  )
}

#' Record one chat message -- either the student's message to the tutor
#' or the tutor's (ellmer-generated) reply.
log_chat <- function(con, student_id, exercise_id, role, message) {
  stopifnot(role %in% c("student", "tutor"))
  dbExecute(
    con,
    "INSERT INTO chat_logs (student_id, exercise_id, role, message)
     VALUES ($1, $2, $3, $4)",
    params = list(student_id, exercise_id, role, message)
  )
}

# ---------------------------------------------------------------------------
# Instructor dashboard queries.
# Read-only aggregate queries used only by instructor_dashboard/app.R.
# Kept here (not in the dashboard app itself) for the same reason as
# everything else in this file: one shared place for SQL against this schema.
# ---------------------------------------------------------------------------

#' RPostgres returns Postgres bigint (e.g. every COUNT(*)) as bit64::integer64,
#' which silently breaks ordinary arithmetic like mean() (no error -- just a
#' wrong answer). None of these dashboard counts can realistically exceed
#' ordinary integer range, so convert every integer64 column back to a plain
#' R integer immediately after querying.
fix_int64_cols <- function(df) {
  for (col in names(df)) {
    if (inherits(df[[col]], "integer64")) {
      df[[col]] <- as.integer(df[[col]])
    }
  }
  df
}

#' One row per student: activity timestamps + exercises passed/attempted.
#' "Exercises passed" counts distinct exercises with a passing row in
#' exercise_mastery (most recent attempt only, per that view's definition).
get_roster_summary <- function(con) {
  fix_int64_cols(dbGetQuery(con, "
    SELECT
      s.student_id,
      s.display_name,
      s.first_login_at,
      s.last_active_at,
      COALESCE(p.n_passed, 0)    AS exercises_passed,
      COALESCE(a.n_attempted, 0) AS exercises_attempted
    FROM students s
    LEFT JOIN (
      SELECT student_id, COUNT(DISTINCT exercise_id) AS n_passed
      FROM exercise_mastery
      WHERE passed = true
      GROUP BY student_id
    ) p ON p.student_id = s.student_id
    LEFT JOIN (
      SELECT student_id, COUNT(DISTINCT exercise_id) AS n_attempted
      FROM exercise_attempts
      GROUP BY student_id
    ) a ON a.student_id = s.student_id
    ORDER BY s.last_active_at DESC NULLS LAST
  "))
}

#' Per student, per module: how many of that module's exercises are passed
#' vs. how many exist. Used to derive "modules completed" on the dashboard.
get_module_completion <- function(con) {
  fix_int64_cols(dbGetQuery(con, "
    SELECT
      s.student_id,
      s.display_name,
      m.module_id,
      m.module_number,
      m.title AS module_title,
      COUNT(DISTINCT e.exercise_id)                                   AS n_exercises,
      COUNT(DISTINCT em.exercise_id) FILTER (WHERE em.passed)         AS n_passed
    FROM students s
    CROSS JOIN modules m
    JOIN exercises e ON e.module_id = m.module_id
    LEFT JOIN exercise_mastery em
      ON em.exercise_id = e.exercise_id AND em.student_id = s.student_id
    GROUP BY s.student_id, s.display_name, m.module_id, m.module_number, m.title
    ORDER BY s.display_name, m.module_number
  "))
}

#' Per exercise: attempt counts and how many distinct students have
#' attempted / passed it. Basis for the pass-rate chart and table.
get_exercise_stats <- function(con) {
  fix_int64_cols(dbGetQuery(con, "
    SELECT
      e.exercise_id,
      m.module_number,
      m.title AS module_title,
      e.order_index,
      e.title AS exercise_title,
      COUNT(a.attempt_id)                                     AS n_attempts,
      COUNT(DISTINCT a.student_id)                             AS n_students_attempted,
      COUNT(DISTINCT a.student_id) FILTER (WHERE a.passed)     AS n_students_passed
    FROM exercises e
    JOIN modules m ON m.module_id = e.module_id
    LEFT JOIN exercise_attempts a ON a.exercise_id = e.exercise_id
    GROUP BY e.exercise_id, m.module_number, m.title, e.order_index, e.title
    ORDER BY m.module_number, e.order_index
  "))
}

#' Students currently stuck: an exercise with 3+ attempts that is still
#' not passed as of the most recent attempt (per exercise_mastery).
get_struggling_students <- function(con, min_attempts = 3) {
  fix_int64_cols(dbGetQuery(con, "
    SELECT
      s.display_name,
      e.title AS exercise_title,
      m.module_number,
      COUNT(a.attempt_id) AS n_attempts,
      MAX(a.created_at) AS last_attempt_at
    FROM exercise_attempts a
    JOIN students s ON s.student_id = a.student_id
    JOIN exercises e ON e.exercise_id = a.exercise_id
    JOIN modules m ON m.module_id = e.module_id
    JOIN exercise_mastery em
      ON em.student_id = a.student_id AND em.exercise_id = a.exercise_id
    WHERE em.passed = false
    GROUP BY s.display_name, e.title, m.module_number, a.student_id, a.exercise_id
    HAVING COUNT(a.attempt_id) >= $1
    ORDER BY n_attempts DESC, last_attempt_at DESC
  ", params = list(min_attempts)))
}

# ---------------------------------------------------------------------------
# Student-facing progress query, used by the merged course tutorial's
# "welcome back" banner (tutorials/course.Rmd). Kept here for the same
# reason as the instructor-dashboard queries above -- one shared place for
# SQL against this schema, even though this one is read by the student app
# rather than the dashboard.
# ---------------------------------------------------------------------------

#' A single student's overall progress: how many exercises (of the whole
#' course) they've passed, and the first module (in module/exercise order)
#' that isn't fully passed yet. `next_module_title` is NA when every
#' exercise is already passed. Returns a plain list, not a data frame --
#' this is always a single-student, single-record read.
get_student_progress <- function(con, student_id) {
  totals <- fix_int64_cols(dbGetQuery(con, "SELECT COUNT(*) AS total_exercises FROM exercises"))
  passed <- fix_int64_cols(dbGetQuery(con, "
    SELECT COUNT(DISTINCT exercise_id) AS exercises_passed
    FROM exercise_mastery
    WHERE student_id = $1 AND passed = true
  ", params = list(student_id)))

  next_module <- dbGetQuery(con, "
    SELECT m.module_number, m.title
    FROM exercises e
    JOIN modules m ON m.module_id = e.module_id
    LEFT JOIN exercise_mastery em
      ON em.exercise_id = e.exercise_id AND em.student_id = $1 AND em.passed = true
    WHERE em.exercise_id IS NULL
    ORDER BY m.module_number, e.order_index
    LIMIT 1
  ", params = list(student_id))

  list(
    exercises_passed = passed$exercises_passed[1],
    total_exercises = totals$total_exercises[1],
    next_module_title = if (nrow(next_module) > 0) {
      sprintf("Module %d: %s", next_module$module_number[1], next_module$title[1])
    } else {
      NA_character_
    }
  )
}

# ---------------------------------------------------------------------------
# Chat transcript + help-category queries, used by the instructor dashboard's
# "Chats" tab and by R/classify_chat_messages.R (the offline classifier).
# Categorization is lazy/offline by design -- these functions never touch
# the live course.Rmd tutorial app, only chat_logs.help_category, which
# R/classify_chat_messages.R fills in after the fact. See that file and
# CLAUDE.md's "Chat categorization" section for why.
# ---------------------------------------------------------------------------

#' The recognized help_category values (must match the DB CHECK constraint
#' in schema.sql exactly). Exported here so both the classifier and the
#' dashboard render the same fixed list/order rather than each hardcoding
#' their own copy.
HELP_CATEGORIES <- c(
  "syntax_error", "conceptual_confusion", "how_do_i_start",
  "wants_answer", "environment_setup", "other"
)

#' Student messages that haven't been classified yet (help_category IS
#' NULL). `limit` caps how many the classifier pulls in one batch.
get_uncategorized_chat_messages <- function(con, limit = 20) {
  dbGetQuery(con, "
    SELECT chat_id, message
    FROM chat_logs
    WHERE role = 'student' AND help_category IS NULL
    ORDER BY created_at
    LIMIT $1
  ", params = list(limit))
}

#' Write a classified category back onto one chat_logs row.
set_chat_message_category <- function(con, chat_id, category) {
  stopifnot(category %in% HELP_CATEGORIES)
  dbExecute(
    con,
    "UPDATE chat_logs SET help_category = $1 WHERE chat_id = $2",
    params = list(category, chat_id)
  )
}

#' Count of student messages per help_category, across the whole course.
#' Uncategorized messages (help_category IS NULL -- not yet run through the
#' classifier) are grouped under the literal label "uncategorized" rather
#' than dropped, so the dashboard can show that a backlog exists.
get_help_category_breakdown <- function(con) {
  fix_int64_cols(dbGetQuery(con, "
    SELECT COALESCE(help_category, 'uncategorized') AS help_category, COUNT(*) AS n
    FROM chat_logs
    WHERE role = 'student'
    GROUP BY COALESCE(help_category, 'uncategorized')
    ORDER BY n DESC
  "))
}

#' Every student who has at least one logged chat message -- populates the
#' dashboard's student picker for the transcript viewer.
get_students_with_chats <- function(con) {
  dbGetQuery(con, "
    SELECT DISTINCT s.student_id, s.display_name
    FROM chat_logs c
    JOIN students s ON s.student_id = c.student_id
    ORDER BY s.display_name
  ")
}

#' Every exercise a given student has chat history for -- populates the
#' dashboard's exercise picker once a student is selected.
get_chatted_exercises_for_student <- function(con, student_id) {
  dbGetQuery(con, "
    SELECT DISTINCT e.exercise_id, e.title, m.module_number, e.order_index
    FROM chat_logs c
    JOIN exercises e ON e.exercise_id = c.exercise_id
    JOIN modules m ON m.module_id = e.module_id
    WHERE c.student_id = $1
    ORDER BY m.module_number, e.order_index
  ", params = list(student_id))
}

#' Full transcript (in order) for one student/exercise pair.
get_chat_transcript <- function(con, student_id, exercise_id) {
  dbGetQuery(con, "
    SELECT role, message, help_category, created_at
    FROM chat_logs
    WHERE student_id = $1 AND exercise_id = $2
    ORDER BY created_at
  ", params = list(student_id, exercise_id))
}