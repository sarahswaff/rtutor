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

#' Record one block of active time on a learnr topic (see activity_time in
#' schema.sql), and bump students.last_active_at -- which otherwise only
#' moves at login, making "last active" really mean "last logged in".
#' module_number is parsed from learnr's topic anchor ('module-4-...').
log_activity <- function(con, student_id, topic_id, active_seconds, window_start, window_end) {
  module_number <- suppressWarnings(as.integer(sub("^module-([0-9]+)-.*$", "\\1", topic_id)))
  dbExecute(
    con,
    "INSERT INTO activity_time
       (student_id, topic_id, module_number, active_seconds, window_start, window_end)
     VALUES ($1, $2, $3, $4, $5, $6)",
    params = list(student_id, topic_id, module_number, as.integer(round(active_seconds)), window_start, window_end)
  )
  dbExecute(
    con,
    "UPDATE students SET last_active_at = now() WHERE student_id = $1",
    params = list(student_id)
  )
}

#' Record one quiz submission (every retry is its own row).
log_quiz_response <- function(con, student_id, quiz_key, module_number, choice_id, correct) {
  dbExecute(
    con,
    "INSERT INTO quiz_responses (student_id, quiz_key, module_number, choice_id, correct)
     VALUES ($1, $2, $3, $4, $5)",
    params = list(student_id, quiz_key, as.integer(module_number), choice_id, correct)
  )
}

# ---------------------------------------------------------------------------
# Instructor dashboard queries.
# The dashboard reads raw tables once via load_dashboard_data() and computes
# everything else in R (R/dashboard_metrics.R). Kept here (not in the
# dashboard app itself) for the same reason as everything else in this
# file: one shared place for SQL against this schema.
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

#' Every raw table the instructor dashboard needs, in one round trip. All
#' dashboard numbers are computed in R from this list (R/dashboard_metrics.R)
#' rather than in per-chart SQL -- at a single course's scale (hundreds of
#' students, thousands of rows) pulling the raw rows is cheap, and it means
#' the metrics are plain functions that can be tested against synthetic data
#' (R/dashboard_demo_data.R) without a populated database. Returns a named
#' list of data frames; see make_demo_dashboard_data() for the exact columns.
load_dashboard_data <- function(con) {
  q <- function(sql) fix_int64_cols(dbGetQuery(con, sql))
  list(
    students = q("SELECT student_id, display_name, first_login_at, last_active_at FROM students"),
    exercises = q("
      SELECT e.exercise_id, e.exercise_key, e.title, e.order_index,
             m.module_number, m.title AS module_title
      FROM exercises e JOIN modules m ON m.module_id = e.module_id
      ORDER BY m.module_number, e.order_index
    "),
    attempts = q("
      SELECT attempt_id, student_id, exercise_id, submitted_code, passed,
             gradethis_message, created_at
      FROM exercise_attempts
    "),
    chats = q("
      SELECT chat_id, student_id, exercise_id, role, message, help_category, created_at
      FROM chat_logs
    "),
    activity = q("
      SELECT student_id, topic_id, module_number, active_seconds, window_start, window_end
      FROM activity_time
    "),
    quiz = q("
      SELECT student_id, quiz_key, module_number, choice_id, correct, created_at
      FROM quiz_responses
    ")
  )
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
# Help-category queries, used by R/classify_chat_messages.R (the offline
# classifier). Categorization is lazy/offline by design -- these functions never touch
# the live course.Rmd tutorial app, only chat_logs.help_category, which
# R/classify_chat_messages.R fills in after the fact. See that file and
# CLAUDE.md's "Chat categorization" section for why.
# ---------------------------------------------------------------------------

#' The recognized help_category values (must match the DB CHECK constraint
#' in schema.sql exactly). Kept here so the classifier and the schema's
#' CHECK constraint have one place to stay in sync.
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
