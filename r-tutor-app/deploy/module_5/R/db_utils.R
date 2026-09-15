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