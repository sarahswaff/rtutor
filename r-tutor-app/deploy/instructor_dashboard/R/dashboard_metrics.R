# R/dashboard_metrics.R
# Every number the instructor dashboard shows, computed from the raw-table
# list returned by load_dashboard_data() (R/db_utils.R) or
# make_demo_dashboard_data() (R/dashboard_demo_data.R). Pure functions: no
# database, no Shiny -- so each one can be checked directly in a console.
#
# Two deliberately different notions of "passed" are used, matching how the
# rest of the app already thinks about them:
#   - mastery (`latest_passed`): the student's MOST RECENT attempt passed --
#     same rule as the exercise_mastery view, used for completion/progress.
#   - ever passed (`ever_passed`): any attempt passed -- used for difficulty,
#     since a student who passed and then kept experimenting still solved it.

library(dplyr)

#' A student with no activity of any kind for this many days counts as
#' "stalled" (and, if they're stuck on an exercise, as having given up on it).
STALLED_AFTER_DAYS <- 7

minutes_between <- function(later, earlier) as.numeric(difftime(later, earlier, units = "mins"))

safe_median <- function(x) if (length(x) == 0 || all(is.na(x))) NA_real_ else stats::median(x, na.rm = TRUE)

pct <- function(num, den) {
  out <- 100 * num / den
  out[!is.finite(out)] <- NA_real_
  out
}

#' One row per (student, exercise) the student has submitted at least once.
#' The backbone of most other views.
student_exercise_summary <- function(d) {
  d$attempts |>
    arrange(created_at) |>
    group_by(student_id, exercise_id) |>
    summarize(
      n_attempts = n(),
      n_failures = sum(!passed),
      first_attempt_at = first(created_at),
      first_fail_at = created_at[which(!passed)[1]],
      first_try_passed = first(passed),
      ever_passed = any(passed),
      attempts_to_pass = which(passed)[1],
      first_pass_at = created_at[which(passed)[1]],
      latest_passed = last(passed),
      last_attempt_at = last(created_at),
      .groups = "drop"
    )
}

#' When each student last did anything at all -- login, submission, quiz,
#' chat, or tracked active time.
student_last_seen <- function(d) {
  events <- bind_rows(
    transmute(d$students, student_id, at = last_active_at),
    transmute(d$attempts, student_id, at = created_at),
    transmute(d$quiz, student_id, at = created_at),
    transmute(d$chats, student_id, at = created_at),
    transmute(d$activity, student_id, at = window_end)
  ) |> filter(!is.na(at))
  events |> group_by(student_id) |> summarize(last_seen = max(at), .groups = "drop")
}

#' Active minutes per student per module (topics outside a module, e.g. an
#' unparseable topic id, are dropped here but still count in totals).
active_minutes_by_student_module <- function(d) {
  d$activity |>
    filter(!is.na(module_number)) |>
    group_by(student_id, module_number) |>
    summarize(active_minutes = sum(active_seconds) / 60, .groups = "drop")
}

#' One row per student, for the Students tab (and the Overview's stat cards).
student_overview <- function(d, now = Sys.time()) {
  n_exercises <- nrow(d$exercises)
  se <- student_exercise_summary(d)

  mastered <- se |> group_by(student_id) |>
    summarize(exercises_passed = sum(latest_passed), exercises_attempted = n(), .groups = "drop")

  # First module (in course order) the student hasn't fully mastered.
  current_module <- d$students |>
    select(student_id) |>
    cross_join(distinct(d$exercises, exercise_id, module_number)) |>
    left_join(select(se, student_id, exercise_id, latest_passed), by = c("student_id", "exercise_id")) |>
    group_by(student_id, module_number) |>
    summarize(done = all(latest_passed %in% TRUE), .groups = "drop") |>
    filter(!done) |>
    group_by(student_id) |>
    summarize(current_module = min(module_number), .groups = "drop")

  time <- d$activity |> group_by(student_id) |>
    summarize(active_minutes = sum(active_seconds) / 60, .groups = "drop")

  quiz_first <- first_quiz_answers(d) |> group_by(student_id) |>
    summarize(quizzes_answered = n(), quiz_first_try_pct = pct(sum(correct), n()), .groups = "drop")

  chats <- d$chats |> filter(role == "student") |> group_by(student_id) |>
    summarize(tutor_messages = n(), .groups = "drop")

  d$students |>
    select(student_id, display_name, first_login_at) |>
    left_join(student_last_seen(d), by = "student_id") |>
    left_join(mastered, by = "student_id") |>
    left_join(current_module, by = "student_id") |>
    left_join(time, by = "student_id") |>
    left_join(quiz_first, by = "student_id") |>
    left_join(chats, by = "student_id") |>
    mutate(
      exercises_passed = coalesce(exercises_passed, 0L),
      exercises_attempted = coalesce(exercises_attempted, 0L),
      active_minutes = coalesce(active_minutes, 0),
      quizzes_answered = coalesce(quizzes_answered, 0L),
      tutor_messages = coalesce(tutor_messages, 0L),
      n_exercises = n_exercises,
      days_inactive = as.numeric(difftime(now, last_seen, units = "days")),
      status = case_when(
        n_exercises > 0 & exercises_passed >= n_exercises ~ "Completed",
        is.na(last_seen) | days_inactive >= STALLED_AFTER_DAYS ~ "Stalled",
        TRUE ~ "Active"
      )
    ) |>
    arrange(desc(last_seen))
}

#' Each student's FIRST answer to each quiz. First answers are what measure
#' understanding -- later answers can be process of elimination, since quizzes
#' allow unlimited retries.
first_quiz_answers <- function(d) {
  d$quiz |>
    arrange(created_at) |>
    group_by(student_id, quiz_key) |>
    summarize(
      module_number = first(module_number),
      first_choice = first(choice_id),
      correct = first(correct),
      n_submissions = n(),
      .groups = "drop"
    )
}

#' One row per module, for the Overview.
module_summary <- function(d) {
  n_students <- nrow(d$students)
  se <- student_exercise_summary(d) |> left_join(select(d$exercises, exercise_id, module_number), by = "exercise_id")
  ex_per_module <- d$exercises |> count(module_number, module_title, name = "n_exercises")

  completed <- se |> filter(latest_passed) |>
    count(student_id, module_number, name = "n_mastered") |>
    inner_join(ex_per_module, by = "module_number") |>
    filter(n_mastered >= n_exercises) |>
    count(module_number, name = "students_completed")

  first_try <- se |> group_by(module_number) |>
    summarize(exercise_first_try_pct = pct(sum(first_try_passed), n()), .groups = "drop")

  time <- active_minutes_by_student_module(d) |> group_by(module_number) |>
    summarize(students_with_time = n(), median_active_minutes = safe_median(active_minutes), .groups = "drop")

  quiz <- first_quiz_answers(d) |> filter(!is.na(module_number)) |> group_by(module_number) |>
    summarize(quiz_first_try_pct = pct(sum(correct), n()), .groups = "drop")

  ex_per_module |>
    left_join(completed, by = "module_number") |>
    left_join(first_try, by = "module_number") |>
    left_join(time, by = "module_number") |>
    left_join(quiz, by = "module_number") |>
    mutate(
      students_completed = coalesce(students_completed, 0L),
      pct_of_class = pct(students_completed, n_students)
    ) |>
    arrange(module_number)
}

#' One row per exercise: how hard it is, for the Exercises tab.
exercise_difficulty <- function(d, now = Sys.time()) {
  se <- student_exercise_summary(d)
  stalled_ids <- student_overview(d, now) |> filter(status == "Stalled") |> pull(student_id)
  chatted <- d$chats |> filter(role == "student") |> distinct(student_id, exercise_id) |> mutate(chatted = TRUE)

  stats <- se |>
    left_join(chatted, by = c("student_id", "exercise_id")) |>
    group_by(exercise_id) |>
    summarize(
      students_attempted = n(),
      students_passed = sum(ever_passed),
      first_try_pass_pct = pct(sum(first_try_passed), n()),
      median_attempts_to_pass = safe_median(attempts_to_pass[ever_passed]),
      # Only students who failed first -- first-try passers would all be 0.
      median_minutes_to_recover = safe_median(minutes_between(first_pass_at, first_attempt_at)[ever_passed & !first_try_passed]),
      students_stuck = sum(!ever_passed),
      students_gave_up = sum(!ever_passed & student_id %in% stalled_ids),
      pct_used_tutor = pct(sum(chatted %in% TRUE), n()),
      .groups = "drop"
    )

  d$exercises |>
    left_join(stats, by = "exercise_id") |>
    mutate(
      students_attempted = coalesce(students_attempted, 0L),
      students_passed = coalesce(students_passed, 0L),
      students_stuck = coalesce(students_stuck, 0L),
      students_gave_up = coalesce(students_gave_up, 0L),
      pass_pct = pct(students_passed, students_attempted)
    ) |>
    arrange(module_number, order_index)
}

#' The grader feedback messages failed attempts on one exercise received,
#' most common first. Each message corresponds to a specific mistake the
#' grading logic recognizes, so this is effectively "most common mistakes".
#' `example_code` is the most recent submission that got that message.
exercise_failure_messages <- function(d, exercise_id) {
  failed <- d$attempts[d$attempts$exercise_id == exercise_id & !d$attempts$passed, ]
  if (nrow(failed) == 0) {
    return(data.frame(gradethis_message = character(0), times = integer(0), students = integer(0),
                      pct_of_failures = numeric(0), example_code = character(0)))
  }
  failed |>
    mutate(gradethis_message = coalesce(gradethis_message, "(no message)")) |>
    arrange(desc(created_at)) |>
    group_by(gradethis_message) |>
    summarize(times = n(), students = n_distinct(student_id), example_code = first(submitted_code), .groups = "drop") |>
    mutate(pct_of_failures = 100 * times / sum(times)) |>
    arrange(desc(times))
}

#' How far students get: for each exercise in course order, how many students
#' attempted it and how many passed it -- plus, among stalled students who
#' haven't finished, which exercise they touched last ("where they stopped").
course_funnel <- function(d, now = Sys.time()) {
  se <- student_exercise_summary(d)
  ov <- student_overview(d, now)
  stalled <- ov |> filter(status == "Stalled") |> pull(student_id)

  stopped_at <- se |>
    filter(student_id %in% stalled) |>
    group_by(student_id) |>
    slice_max(last_attempt_at, n = 1, with_ties = FALSE) |>
    ungroup() |>
    count(exercise_id, name = "stalled_here")

  d$exercises |>
    left_join(
      se |> group_by(exercise_id) |> summarize(attempted = n(), passed = sum(ever_passed), .groups = "drop"),
      by = "exercise_id"
    ) |>
    left_join(stopped_at, by = "exercise_id") |>
    mutate(across(c(attempted, passed, stalled_here), ~ coalesce(.x, 0L)), position = row_number()) |>
    select(position, exercise_id, module_number, title, attempted, passed, stalled_here)
}

#' Stalled, unfinished students who never submitted any exercise at all
#' (their stopping point is "before the first exercise").
stalled_before_first_exercise <- function(d, now = Sys.time()) {
  student_overview(d, now) |> filter(status == "Stalled", exercises_attempted == 0) |> nrow()
}

#' Time per topic, in course order. `topic_catalog` (instructor_dashboard/
#' topic_catalog.csv, from R/build_course_catalog.R) supplies titles and
#' order; topics missing from it still appear, titled by their raw id.
topic_time <- function(d, topic_catalog = NULL) {
  per_student <- d$activity |> group_by(topic_id, student_id) |>
    summarize(minutes = sum(active_seconds) / 60, module_number = first(module_number), .groups = "drop")
  out <- per_student |> group_by(topic_id) |>
    summarize(
      module_number = first(module_number),
      students = n(),
      median_minutes = safe_median(minutes),
      total_hours = sum(minutes) / 60,
      .groups = "drop"
    )
  if (!is.null(topic_catalog)) {
    out <- out |>
      left_join(select(topic_catalog, topic_id, topic_title, topic_order), by = "topic_id") |>
      mutate(topic_title = coalesce(topic_title, topic_id))
  } else {
    out <- out |> mutate(topic_title = topic_id, topic_order = NA_integer_)
  }
  out |> arrange(topic_order, module_number, topic_id)
}

#' One row per quiz: first-try accuracy and the most popular wrong first answer.
quiz_summary <- function(d, quiz_catalog = NULL) {
  fa <- first_quiz_answers(d)
  top_wrong <- fa |> filter(!correct) |>
    count(quiz_key, first_choice, name = "n") |>
    group_by(quiz_key) |> slice_max(n, n = 1, with_ties = FALSE) |> ungroup() |>
    select(quiz_key, top_wrong_choice = first_choice, top_wrong_n = n)

  out <- fa |> group_by(quiz_key) |>
    summarize(
      module_number = first(module_number),
      students_answered = n(),
      first_try_pct = pct(sum(correct), n()),
      avg_submissions = mean(n_submissions),
      .groups = "drop"
    ) |>
    left_join(top_wrong, by = "quiz_key") |>
    mutate(top_wrong_pct = pct(coalesce(top_wrong_n, 0L), students_answered))

  if (!is.null(quiz_catalog)) {
    questions <- distinct(quiz_catalog, quiz_key, question, quiz_order)
    labels <- select(quiz_catalog, quiz_key, choice_id, choice_label)
    out <- out |>
      left_join(questions, by = "quiz_key") |>
      left_join(labels, by = c("quiz_key", "top_wrong_choice" = "choice_id")) |>
      mutate(question = coalesce(question, quiz_key), top_wrong_label = coalesce(choice_label, top_wrong_choice)) |>
      select(-choice_label) |>
      arrange(quiz_order)
  } else {
    out <- out |> mutate(question = quiz_key, top_wrong_label = top_wrong_choice) |> arrange(module_number, quiz_key)
  }
  out
}

#' How students' FIRST answers to one quiz split across its choices
#' (including choices nobody picked, when the catalog is available).
quiz_choice_distribution <- function(d, quiz_key, quiz_catalog = NULL) {
  fa <- first_quiz_answers(d)
  picked <- fa[fa$quiz_key == quiz_key, ] |> count(choice_id = first_choice, name = "students")
  if (!is.null(quiz_catalog) && quiz_key %in% quiz_catalog$quiz_key) {
    choices <- quiz_catalog[quiz_catalog$quiz_key == quiz_key, c("choice_id", "choice_label")]
    out <- choices |> left_join(picked, by = "choice_id") |> mutate(students = coalesce(students, 0L))
  } else {
    out <- picked |> mutate(choice_label = choice_id)
  }
  out |> mutate(is_correct = choice_id == "correct", pct = pct(students, sum(students)))
}

#' Course-wide tutor usage headline numbers.
tutor_overview <- function(d) {
  student_msgs <- d$chats |> filter(role == "student")
  per_student <- student_msgs |> count(student_id, name = "messages")
  ever_active <- unique(c(d$attempts$student_id, d$quiz$student_id, d$activity$student_id, d$chats$student_id))
  list(
    students_active = length(ever_active),
    students_chatted = nrow(per_student),
    pct_chatted = pct(nrow(per_student), length(ever_active)),
    student_messages = nrow(student_msgs),
    median_messages_per_chatter = safe_median(per_student$messages)
  )
}

#' Did talking to the tutor after failing go with getting unstuck? Compares
#' every (student, exercise) pair with at least one failed attempt, split by
#' whether the student messaged the tutor after their first failure (and
#' before passing, if they passed). This is an association, not proof the
#' chat helped -- students who reach for the tutor may be the more stuck ones.
tutor_after_failure <- function(d) {
  se <- student_exercise_summary(d) |> filter(n_failures > 0)
  msgs <- d$chats |> filter(role == "student") |> select(student_id, exercise_id, msg_at = created_at)
  chatted <- se |>
    inner_join(msgs, by = c("student_id", "exercise_id"), relationship = "many-to-many") |>
    filter(msg_at > first_fail_at, is.na(first_pass_at) | msg_at < first_pass_at) |>
    distinct(student_id, exercise_id) |>
    mutate(chatted_after_fail = TRUE)

  # Attempts made after the first failure, up to and including the pass.
  fail_index <- d$attempts |>
    arrange(created_at) |>
    group_by(student_id, exercise_id) |>
    summarize(first_fail_n = which(!passed)[1], .groups = "drop")

  se |>
    left_join(chatted, by = c("student_id", "exercise_id")) |>
    left_join(fail_index, by = c("student_id", "exercise_id")) |>
    mutate(
      group = if_else(chatted_after_fail %in% TRUE, "Asked the tutor after failing", "Didn't ask the tutor"),
      further_attempts = attempts_to_pass - first_fail_n
    ) |>
    group_by(group) |>
    summarize(
      student_exercise_pairs = n(),
      pct_eventually_passed = pct(sum(ever_passed), n()),
      median_further_attempts_to_pass = safe_median(further_attempts[ever_passed]),
      .groups = "drop"
    )
}

#' Tutor usage per exercise.
tutor_by_exercise <- function(d) {
  attempters <- d$attempts |> distinct(student_id, exercise_id) |> count(exercise_id, name = "students_attempted")
  msgs <- d$chats |> filter(role == "student")
  top_cat <- msgs |> filter(!is.na(help_category)) |>
    count(exercise_id, help_category) |>
    group_by(exercise_id) |> slice_max(n, n = 1, with_ties = FALSE) |> ungroup() |>
    select(exercise_id, top_category = help_category)
  d$exercises |>
    left_join(attempters, by = "exercise_id") |>
    left_join(
      msgs |> group_by(exercise_id) |> summarize(students_chatted = n_distinct(student_id), student_messages = n(), .groups = "drop"),
      by = "exercise_id"
    ) |>
    left_join(top_cat, by = "exercise_id") |>
    mutate(
      across(c(students_attempted, students_chatted, student_messages), ~ coalesce(.x, 0L)),
      pct_of_attempters_chatted = pct(students_chatted, students_attempted)
    ) |>
    arrange(module_number, order_index)
}

#' Tutor usage per student (students who never chatted are omitted).
tutor_by_student <- function(d) {
  d$chats |>
    filter(role == "student") |>
    group_by(student_id) |>
    summarize(
      messages = n(),
      exercises = n_distinct(exercise_id),
      wants_answer = sum(help_category %in% "wants_answer"),
      # suppressWarnings: dplyr evaluates this once on zero rows to infer
      # its type when there are no chats at all.
      last_message_at = suppressWarnings(max(created_at)),
      .groups = "drop"
    ) |>
    mutate(pct_wants_answer = pct(wants_answer, messages)) |>
    left_join(select(d$students, student_id, display_name), by = "student_id") |>
    arrange(desc(messages))
}

#' Student messages per help category (NULL = not yet run through
#' R/classify_chat_messages.R, shown as its own "uncategorized" bucket).
help_category_breakdown <- function(d) {
  d$chats |>
    filter(role == "student") |>
    mutate(help_category = coalesce(help_category, "uncategorized")) |>
    count(help_category, name = "n") |>
    arrange(desc(n))
}

#' Needs attention: an exercise with 3+ attempts whose latest attempt still
#' fails (same rule the dashboard has always used).
stuck_students <- function(d, min_attempts = 3) {
  student_exercise_summary(d) |>
    filter(n_attempts >= min_attempts, !latest_passed) |>
    left_join(select(d$students, student_id, display_name), by = "student_id") |>
    left_join(select(d$exercises, exercise_id, title, module_number), by = "exercise_id") |>
    arrange(desc(n_attempts), desc(last_attempt_at))
}

#' Needs attention: students who've repeatedly asked the tutor for the answer.
answer_seekers <- function(d, min_messages = 3) {
  tutor_by_student(d) |> filter(wants_answer >= min_messages)
}

#' Per-module breakdown for one student (Students tab detail view).
student_module_detail <- function(d, student_id) {
  sd <- filter_to_student(d, student_id)
  se <- student_exercise_summary(sd)
  d$exercises |>
    left_join(select(se, exercise_id, latest_passed, n_attempts), by = "exercise_id") |>
    group_by(module_number, module_title) |>
    summarize(
      exercises = n(),
      passed = sum(latest_passed %in% TRUE),
      attempts = sum(coalesce(n_attempts, 0L)),
      .groups = "drop"
    ) |>
    left_join(active_minutes_by_student_module(sd) |> select(module_number, active_minutes), by = "module_number") |>
    left_join(
      first_quiz_answers(sd) |> group_by(module_number) |>
        summarize(quizzes_answered = n(), quizzes_first_try_correct = sum(correct), .groups = "drop"),
      by = "module_number"
    ) |>
    left_join(
      sd$chats |> filter(role == "student") |>
        left_join(select(d$exercises, exercise_id, module_number), by = "exercise_id") |>
        count(module_number, name = "tutor_messages"),
      by = "module_number"
    ) |>
    mutate(across(c(active_minutes), ~ coalesce(.x, 0)),
           across(c(quizzes_answered, quizzes_first_try_correct, tutor_messages), ~ coalesce(.x, 0L))) |>
    arrange(module_number)
}

#' Everything one student did, newest first: submissions, quiz answers, and
#' messages to the tutor.
student_timeline <- function(d, student_id, quiz_catalog = NULL) {
  sd <- filter_to_student(d, student_id)
  ex <- select(d$exercises, exercise_id, title, module_number)

  attempts <- sd$attempts |> left_join(ex, by = "exercise_id") |>
    transmute(at = created_at, module_number, kind = "Exercise",
              item = title, result = if_else(passed, "Passed", "Failed"),
              detail = if_else(passed, "", coalesce(gradethis_message, "")))

  quiz <- sd$quiz
  if (!is.null(quiz_catalog)) {
    quiz <- quiz |>
      left_join(distinct(quiz_catalog, quiz_key, question), by = "quiz_key") |>
      left_join(select(quiz_catalog, quiz_key, choice_id, choice_label), by = c("quiz_key", "choice_id"))
  } else {
    quiz <- quiz |> mutate(question = quiz_key, choice_label = choice_id)
  }
  quiz <- quiz |> transmute(at = created_at, module_number, kind = "Quiz",
                            item = coalesce(question, quiz_key),
                            result = if_else(correct, "Correct", "Incorrect"),
                            detail = paste("Answered:", coalesce(choice_label, choice_id)))

  chats <- sd$chats |> filter(role == "student") |> left_join(ex, by = "exercise_id") |>
    transmute(at = created_at, module_number, kind = "Tutor chat",
              item = title, result = coalesce(help_category, ""), detail = message)

  bind_rows(attempts, quiz, chats) |> arrange(desc(at))
}

filter_to_student <- function(d, student_id) {
  lapply(d, function(tbl) if ("student_id" %in% names(tbl)) tbl[tbl$student_id %in% student_id, , drop = FALSE] else tbl)
}
