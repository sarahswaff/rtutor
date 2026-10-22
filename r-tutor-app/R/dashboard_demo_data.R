# R/dashboard_demo_data.R
# Synthetic class data in exactly the shape load_dashboard_data() returns, so
# the instructor dashboard can be developed, tested, and previewed without a
# populated database (the live DB is deliberately reset before each pilot).
# Used only when the dashboard runs with DASHBOARD_DEMO=true -- never set
# that on the deployed Connect Cloud content item.
#
# The simulation is intentionally simple but has the shape real data should
# have: students differ in ability and persistence, later modules are harder,
# some students drop out partway, struggling students lean on the tutor
# more, and quiz wrong answers cluster on particular distractors.

make_demo_dashboard_data <- function(exercises, topic_catalog, quiz_catalog,
                                     n_students = 60, now = Sys.time(), seed = 42) {
  set.seed(seed)
  exercises <- exercises[order(exercises$module_number, exercises$order_index), ]
  ex_difficulty <- stats::setNames(
    0.3 * exercises$module_number + stats::rnorm(nrow(exercises), 0, 0.6) - 0.6,
    exercises$exercise_id
  )
  fail_messages <- c(
    "Close -- check which column you're working with.",
    "That code doesn't run as-is -- look for a missing quote or parenthesis.",
    "Your result has the right shape, but the values aren't right yet.",
    "Looks like the FIXME placeholder is still there.",
    "Make sure your answer is computed from the data, not typed in by hand."
  )
  student_questions <- list(
    syntax_error = c("I keep getting an unexpected symbol error, what does that mean?", "why does it say object not found"),
    conceptual_confusion = c("what's the difference between filter and select?", "I don't get what the comma does here"),
    how_do_i_start = c("where do I even begin with this one?", "what should my first line be?"),
    wants_answer = c("can you just tell me the answer", "what's the code for this"),
    environment_setup = c("it says the package isn't installed"),
    other = c("thanks!", "is this going to be on the exam?")
  )
  quiz_keys <- unique(quiz_catalog$quiz_key)
  quiz_difficulty <- stats::setNames(stats::rnorm(length(quiz_keys), 0, 0.8), quiz_keys)
  module_numbers <- sort(unique(exercises$module_number))

  students <- data.frame(
    student_id = sprintf("demo-%03d", seq_len(n_students)),
    display_name = sprintf("Demo Student %02d", seq_len(n_students))
  )
  attempts <- list(); chats <- list(); activity <- list(); quiz <- list()
  first_login <- last_active <- rep(now, n_students)

  for (s in seq_len(n_students)) {
    sid <- students$student_id[s]
    ability <- stats::rnorm(1)
    chattiness <- stats::runif(1, 0, 0.8)
    dropout_per_module <- stats::runif(1, 0, 0.35)
    # At most ~6 modules x 20h gaps plus work time, so starting 8+ days ago
    # keeps every simulated event in the past.
    clock <- now - as.difftime(stats::runif(1, 8, 30), units = "days")
    first_login[s] <- clock
    advance <- function(secs) clock <<- clock + secs

    for (m in module_numbers) {
      if (m > 1 && stats::runif(1) < dropout_per_module) break
      # A new sitting for each module, a few hours to a day apart.
      advance(stats::runif(1, 2, 20) * 3600)

      for (i in which(topic_catalog$module_number %in% m)) {
        secs <- round(stats::rlnorm(1, log(150), 0.6) * exp(-0.2 * ability))
        activity[[length(activity) + 1]] <- data.frame(
          student_id = sid, topic_id = topic_catalog$topic_id[i], module_number = m,
          active_seconds = secs, window_start = clock, window_end = clock + secs
        )
        advance(secs * stats::runif(1, 1, 1.4))
      }

      for (qk in unique(quiz_catalog$quiz_key[quiz_catalog$module_number %in% m])) {
        choices <- quiz_catalog$choice_id[quiz_catalog$quiz_key == qk]
        wrong <- setdiff(choices, "correct")
        # Wrong answers cluster on the first distractor, like real misconceptions.
        wrong_weights <- rev(seq_along(wrong))^2
        repeat {
          ok <- stats::runif(1) < stats::plogis(ability + 1.2 - quiz_difficulty[[qk]])
          pick <- if (ok || length(wrong) == 0) "correct" else sample(wrong, 1, prob = wrong_weights)
          quiz[[length(quiz) + 1]] <- data.frame(student_id = sid, quiz_key = qk, module_number = m,
                                                 choice_id = pick, correct = pick == "correct", created_at = clock)
          advance(stats::runif(1, 5, 30))
          if (pick == "correct") break
          wrong <- setdiff(wrong, pick)
          wrong_weights <- rev(seq_along(wrong))^2
        }
      }

      for (j in which(exercises$module_number == m)) {
        eid <- exercises$exercise_id[j]
        msg_weights <- stats::runif(length(fail_messages))^3
        boost <- 0
        for (k in 1:8) {
          advance(stats::runif(1, 30, 240))
          passed <- stats::runif(1) < stats::plogis(ability - ex_difficulty[[as.character(eid)]] + 0.5 * (k - 1) + boost)
          attempts[[length(attempts) + 1]] <- data.frame(
            student_id = sid, exercise_id = eid, submitted_code = if (passed) "# a correct answer" else "# an attempt",
            passed = passed, gradethis_message = if (passed) "Nice work!" else sample(fail_messages, 1, prob = msg_weights),
            created_at = clock
          )
          if (passed) break
          if (k >= 3 && stats::runif(1) < 0.25) break # gives up on this one
          if (stats::runif(1) < chattiness) {
            for (turn in seq_len(sample(1:3, 1))) {
              cat <- sample(names(student_questions), 1, prob = c(0.25, 0.3, 0.15, 0.15 + 0.2 * (k > 2), 0.05, 0.1))
              advance(stats::runif(1, 20, 90))
              chats[[length(chats) + 1]] <- data.frame(
                student_id = sid, exercise_id = eid, role = c("student", "tutor"),
                message = c(sample(student_questions[[cat]], 1), "(demo tutor reply)"),
                help_category = c(if (stats::runif(1) < 0.85) cat else NA_character_, NA_character_),
                created_at = c(clock, clock + 5)
              )
            }
            boost <- boost + 0.6
          }
        }
      }
    }
    last_active[s] <- min(clock, now)
  }

  bind <- function(x, template) if (length(x) == 0) template else do.call(rbind, x)
  attempts <- bind(attempts, NULL); chats <- bind(chats, NULL); activity <- bind(activity, NULL); quiz <- bind(quiz, NULL)
  attempts$attempt_id <- seq_len(nrow(attempts))
  chats$chat_id <- seq_len(nrow(chats))
  # Simulated clocks can run past "now" for the most recent students; clamp.
  clamp <- function(x) { x[x > now] <- now; x }
  attempts$created_at <- clamp(attempts$created_at)
  chats$created_at <- clamp(chats$created_at)
  quiz$created_at <- clamp(quiz$created_at)
  activity$window_end <- clamp(activity$window_end)
  activity$window_start <- pmin(activity$window_start, activity$window_end - 1)

  students$first_login_at <- first_login
  students$last_active_at <- last_active

  list(
    students = students,
    exercises = exercises,
    attempts = attempts,
    chats = chats,
    activity = activity,
    quiz = quiz
  )
}
