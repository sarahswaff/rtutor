library(shiny)
library(bslib)
library(DT)
library(ggplot2)
library(DBI)

source("../R/db_utils.R")
source("../R/dashboard_metrics.R")
source("../R/dashboard_demo_data.R")

# DASHBOARD_DEMO=true swaps in a synthetic class (R/dashboard_demo_data.R) so
# the dashboard can be previewed before real data exists. Never set it on the
# deployed content item.
DEMO_MODE <- identical(tolower(Sys.getenv("DASHBOARD_DEMO")), "true")

# Readable titles for topics and quiz questions/answers -- see
# R/build_course_catalog.R. Optional: without them the dashboard shows raw ids.
read_catalog <- function(file) if (file.exists(file)) read.csv(file, stringsAsFactors = FALSE) else NULL
TOPIC_CATALOG <- read_catalog("topic_catalog.csv")
QUIZ_CATALOG <- read_catalog("quiz_catalog.csv")

# Two steps of the theme's blue: light for "attempted"/background marks,
# dark for "passed"/foreground marks.
COLOR_LIGHT <- "#a9d4f5"
COLOR_DARK <- "#1f6fb2"

check_password <- function(attempt) {
  expected <- Sys.getenv("DASHBOARD_PASSWORD")
  nzchar(expected) && identical(attempt, expected)
}

fmt_pct <- function(x) ifelse(is.na(x), "--", sprintf("%.0f%%", x))
fmt_num <- function(x, digits = 1) ifelse(is.na(x), "--", formatC(x, format = "f", digits = digits))
fmt_minutes <- function(x) {
  ifelse(is.na(x), "--", ifelse(x >= 60, sprintf("%dh %02dm", as.integer(x %/% 60), as.integer(round(x %% 60))), sprintf("%.0fm", x)))
}
fmt_time <- function(x) ifelse(is.na(x), "--", format(x, "%b %d, %H:%M"))
pretty_category <- function(x) gsub("_", " ", x)

simple_table <- function(df, page_length = 25, selection = "none", ...) {
  datatable(df, rownames = FALSE, selection = selection, escape = TRUE,
            options = list(pageLength = page_length, autoWidth = FALSE, ...))
}

login_ui <- function(failed = FALSE) {
  div(
    class = "d-flex justify-content-center align-items-center",
    style = "height: 80vh;",
    card(
      style = "width: 360px;",
      card_header("Instructor Dashboard Login"),
      card_body(
        passwordInput("password", "Password", width = "100%"),
        actionButton("login_btn", "Log in", class = "btn-primary w-100"),
        if (failed) div(class = "text-danger mt-2", "Incorrect password.")
      )
    )
  )
}

dashboard_ui <- function() {
  page_navbar(
    title = "R Tutor -- Instructor Dashboard",
    theme = bs_theme(version = 5, bootswatch = "cerulean"),
    header = if (DEMO_MODE) div(class = "alert alert-warning m-2 py-2", strong("Demo mode: "), "everything shown is synthetic data, not real students."),

    nav_panel(
      "Overview",
      layout_column_wrap(
        width = 1 / 4,
        value_box("Students", textOutput("n_students", inline = TRUE)),
        value_box("Active in last 7 days", textOutput("n_active_week", inline = TRUE)),
        value_box("Median active time per student", textOutput("median_time", inline = TRUE)),
        value_box("Avg. exercises passed", textOutput("avg_passed", inline = TRUE))
      ),
      card(
        card_header("How far students get"),
        p(class = "text-muted small mb-0",
          "Each exercise in course order: how many students attempted it (light) and passed it (dark). ",
          "\"stopped here\" counts students inactive for ", STALLED_AFTER_DAYS, "+ days whose last submission was on that exercise."),
        plotOutput("funnel_plot", height = "560px"),
        textOutput("stalled_before_first")
      ),
      card(
        card_header("By module"),
        DTOutput("module_table")
      )
    ),

    nav_panel(
      "Students",
      card(
        card_header("All students -- click a row for details"),
        DTOutput("student_table")
      ),
      uiOutput("student_detail")
    ),

    nav_panel(
      "Exercises",
      card(
        card_header("Difficulty by exercise -- click a row to see the most common mistakes"),
        p(class = "text-muted small mb-0",
          "First-try pass rate is the cleanest difficulty signal. \"Minutes to recover\" is time from first submission to passing, ",
          "for students who failed first. \"Gave up\" = never passed and inactive ", STALLED_AFTER_DAYS, "+ days."),
        DTOutput("exercise_table")
      ),
      uiOutput("exercise_detail")
    ),

    nav_panel(
      "Quizzes",
      card(
        card_header("Quiz questions -- click a row to see how answers split"),
        p(class = "text-muted small mb-0",
          "Based on each student's FIRST answer -- quizzes allow unlimited retries, so later answers mostly reflect elimination."),
        DTOutput("quiz_table")
      ),
      uiOutput("quiz_detail")
    ),

    nav_panel(
      "Time",
      p(class = "text-muted small mt-2",
        "Active time only counts while the course tab is visible and the student has moused, typed, or scrolled in the last 90 seconds."),
      layout_column_wrap(
        width = 1 / 2,
        card(card_header("Active minutes per module (each dot is a student)"), plotOutput("time_module_plot", height = "320px")),
        card(card_header("Time vs. progress"), plotOutput("time_progress_plot", height = "320px"))
      ),
      card(card_header("Time per topic, in course order"), DTOutput("topic_table"))
    ),

    nav_panel(
      "Tutor",
      layout_column_wrap(
        width = 1 / 3,
        value_box("Students who used the tutor", textOutput("tutor_pct", inline = TRUE)),
        value_box("Messages from students", textOutput("tutor_messages", inline = TRUE)),
        value_box("Median messages per tutor user", textOutput("tutor_median", inline = TRUE))
      ),
      card(
        card_header("After a failed attempt: asked the tutor vs. didn't"),
        p(class = "text-muted small mb-0",
          "Every student/exercise pair with at least one failure. This shows association, not cause -- ",
          "students who reach for the tutor may simply be the more stuck ones."),
        tableOutput("tutor_effect_table")
      ),
      layout_column_wrap(
        width = 1 / 2,
        card(card_header("What students ask about"), plotOutput("help_category_plot", height = "300px")),
        card(card_header("Tutor use by student"), DTOutput("tutor_student_table"))
      ),
      card(card_header("Tutor use by exercise"), DTOutput("tutor_exercise_table")),
      card(
        card_header("Browse a conversation"),
        layout_column_wrap(
          width = 1 / 2,
          selectInput("chat_student", "Student", choices = c("Select a student..." = ""), selectize = FALSE),
          selectInput("chat_exercise", "Exercise", choices = c("Select a student first..." = ""), selectize = FALSE)
        ),
        uiOutput("chat_transcript")
      )
    ),

    nav_panel(
      "Needs attention",
      card(
        card_header("Stuck on an exercise (3+ attempts, latest still failing)"),
        DTOutput("stuck_table")
      ),
      card(
        card_header(paste0("Stalled (no activity for ", STALLED_AFTER_DAYS, "+ days, course not finished)")),
        DTOutput("stalled_table")
      ),
      card(
        card_header("Repeatedly asking the tutor for the answer (3+ messages)"),
        DTOutput("answer_seeker_table")
      )
    ),

    nav_spacer(),
    nav_item(actionButton("refresh_btn", "Refresh data", class = "btn-sm btn-outline-secondary"))
  )
}

ui <- uiOutput("app_root")

server <- function(input, output, session) {
  authenticated <- reactiveVal(FALSE)
  login_failed <- reactiveVal(FALSE)

  observeEvent(input$login_btn, {
    if (check_password(input$password)) {
      authenticated(TRUE)
    } else {
      login_failed(TRUE)
    }
  })

  output$app_root <- renderUI({
    if (authenticated()) dashboard_ui() else login_ui(failed = login_failed())
  })

  # Re-query the DB on load and whenever "Refresh data" is clicked. Every
  # view below is computed from this one snapshot (see R/dashboard_metrics.R).
  refresh_tick <- reactiveVal(0)
  observeEvent(input$refresh_btn, refresh_tick(refresh_tick() + 1))

  dash <- reactive({
    req(authenticated())
    refresh_tick()
    con <- get_con()
    on.exit(dbDisconnect(con))
    if (DEMO_MODE) {
      # Real exercise list, synthetic everything else.
      exercises <- load_dashboard_data(con)$exercises
      make_demo_dashboard_data(exercises, TOPIC_CATALOG, QUIZ_CATALOG)
    } else {
      load_dashboard_data(con)
    }
  })

  students <- reactive(student_overview(dash()))
  exercises <- reactive(exercise_difficulty(dash()))
  quizzes <- reactive(quiz_summary(dash(), QUIZ_CATALOG))
  tutor_students <- reactive(tutor_by_student(dash()))

  exercise_label <- function(ex) sprintf("M%d: %s", ex$module_number, ex$title)

  # ---- Overview ----

  output$n_students <- renderText(nrow(students()))
  output$n_active_week <- renderText(sum(students()$days_inactive < 7, na.rm = TRUE))
  output$median_time <- renderText({
    s <- students()
    if (nrow(s) == 0) "--" else fmt_minutes(safe_median(s$active_minutes))
  })
  output$avg_passed <- renderText({
    s <- students()
    if (nrow(s) == 0) return("--")
    sprintf("%.1f / %d", mean(s$exercises_passed), nrow(dash()$exercises))
  })

  output$funnel_plot <- renderPlot({
    f <- course_funnel(dash())
    req(nrow(f) > 0)
    f$label <- factor(exercise_label(f), levels = rev(exercise_label(f)))
    ggplot(f, aes(y = label)) +
      geom_col(aes(x = attempted, fill = "Attempted"), width = 0.7) +
      geom_col(aes(x = passed, fill = "Passed"), width = 0.45) +
      geom_text(
        data = f[f$stalled_here > 0, ],
        aes(x = attempted, label = paste0("  ", stalled_here, " stopped here")),
        hjust = 0, size = 3.5, color = "grey30"
      ) +
      scale_fill_manual(values = c(Attempted = COLOR_LIGHT, Passed = COLOR_DARK), name = NULL) +
      scale_x_continuous(expand = expansion(mult = c(0, 0.4))) +
      labs(x = "Students", y = NULL) +
      theme_minimal(base_size = 13) +
      theme(legend.position = "top", panel.grid.major.y = element_blank(), panel.grid.minor = element_blank())
  })

  output$stalled_before_first <- renderText({
    n <- stalled_before_first_exercise(dash())
    if (n > 0) sprintf("%d stalled student(s) never submitted any exercise.", n) else ""
  })

  output$module_table <- renderDT({
    m <- module_summary(dash())
    req(nrow(m) > 0)
    simple_table(data.frame(
      Module = sprintf("%d: %s", m$module_number, m$module_title),
      Exercises = m$n_exercises,
      `Students completed` = sprintf("%d (%s)", m$students_completed, fmt_pct(m$pct_of_class)),
      `Exercise first-try pass` = fmt_pct(m$exercise_first_try_pct),
      `Quiz first-try correct` = fmt_pct(m$quiz_first_try_pct),
      `Median active time` = fmt_minutes(m$median_active_minutes),
      check.names = FALSE
    ), dom = "t", paging = FALSE, ordering = FALSE)
  })

  # ---- Students ----

  output$student_table <- renderDT({
    s <- students()
    simple_table(data.frame(
      Student = s$display_name,
      Status = s$status,
      `Last active` = fmt_time(s$last_seen),
      `Active time` = fmt_minutes(s$active_minutes),
      Passed = sprintf("%d / %d", s$exercises_passed, s$n_exercises),
      `Current module` = ifelse(is.na(s$current_module), "--", s$current_module),
      `Quiz first-try` = fmt_pct(s$quiz_first_try_pct),
      `Tutor messages` = s$tutor_messages,
      check.names = FALSE
    ), selection = "single")
  })

  selected_student <- reactive({
    i <- input$student_table_rows_selected
    req(length(i) == 1)
    students()[i, ]
  })

  output$student_detail <- renderUI({
    s <- selected_student()
    card(
      card_header(sprintf("%s -- %s, first seen %s", s$display_name, s$status, fmt_time(s$first_login_at))),
      h6("By module"),
      tableOutput("student_module_table"),
      h6("Currently stuck on"),
      uiOutput("student_stuck"),
      h6("Activity, newest first"),
      DTOutput("student_timeline_table")
    )
  })

  output$student_module_table <- renderTable({
    m <- student_module_detail(dash(), selected_student()$student_id)
    data.frame(
      Module = sprintf("%d: %s", m$module_number, m$module_title),
      `Exercises passed` = sprintf("%d / %d", m$passed, m$exercises),
      Submissions = m$attempts,
      `Active time` = fmt_minutes(m$active_minutes),
      `Quizzes right first try` = sprintf("%d / %d", m$quizzes_first_try_correct, m$quizzes_answered),
      `Tutor messages` = m$tutor_messages,
      check.names = FALSE
    )
  }, striped = TRUE, spacing = "s")

  output$student_stuck <- renderUI({
    st <- stuck_students(dash(), min_attempts = 1)
    st <- st[st$student_id == selected_student()$student_id, ]
    if (nrow(st) == 0) return(p(class = "text-muted", "Nothing -- no exercise with a failing latest attempt."))
    tags$ul(lapply(seq_len(nrow(st)), function(i) {
      tags$li(sprintf("Module %d: %s (%d attempts, last %s)", st$module_number[i], st$title[i], st$n_attempts[i], fmt_time(st$last_attempt_at[i])))
    }))
  })

  output$student_timeline_table <- renderDT({
    t <- student_timeline(dash(), selected_student()$student_id, QUIZ_CATALOG)
    simple_table(data.frame(
      When = fmt_time(t$at),
      Module = t$module_number,
      Type = t$kind,
      Item = t$item,
      Result = pretty_category(t$result),
      Detail = t$detail,
      check.names = FALSE
    ), page_length = 15, ordering = FALSE)
  })

  # ---- Exercises ----

  output$exercise_table <- renderDT({
    e <- exercises()
    simple_table(data.frame(
      Exercise = exercise_label(e),
      Attempted = e$students_attempted,
      `Pass rate` = fmt_pct(e$pass_pct),
      `First-try pass` = fmt_pct(e$first_try_pass_pct),
      `Median attempts to pass` = fmt_num(e$median_attempts_to_pass),
      `Median minutes to recover` = fmt_num(e$median_minutes_to_recover),
      Stuck = e$students_stuck,
      `Gave up` = e$students_gave_up,
      `Used tutor` = fmt_pct(e$pct_used_tutor),
      check.names = FALSE
    ), selection = "single", ordering = TRUE)
  })

  output$exercise_detail <- renderUI({
    i <- input$exercise_table_rows_selected
    req(length(i) == 1)
    e <- exercises()[i, ]
    card(
      card_header(sprintf("Most common mistakes: %s", exercise_label(e))),
      p(class = "text-muted small mb-0", "Grouped by the feedback message the grader gave -- each message corresponds to one specific mistake the grading code recognizes."),
      DTOutput("failure_table")
    )
  })

  output$failure_table <- renderDT({
    i <- input$exercise_table_rows_selected
    req(length(i) == 1)
    fm <- exercise_failure_messages(dash(), exercises()$exercise_id[i])
    if (nrow(fm) == 0) return(simple_table(data.frame(Message = "No failed attempts yet."), dom = "t"))
    simple_table(data.frame(
      `Grader feedback` = fm$gradethis_message,
      Times = fm$times,
      Students = fm$students,
      `% of failures` = fmt_pct(fm$pct_of_failures),
      `Most recent example` = fm$example_code,
      check.names = FALSE
    ), page_length = 10, dom = "tp")
  })

  # ---- Quizzes ----

  output$quiz_table <- renderDT({
    q <- quizzes()
    simple_table(data.frame(
      Module = q$module_number,
      Question = q$question,
      Answered = q$students_answered,
      `First-try correct` = fmt_pct(q$first_try_pct),
      `Most-picked wrong answer` = ifelse(is.na(q$top_wrong_label), "--", sprintf("%s (%s of students)", q$top_wrong_label, fmt_pct(q$top_wrong_pct))),
      check.names = FALSE
    ), selection = "single")
  })

  output$quiz_detail <- renderUI({
    i <- input$quiz_table_rows_selected
    req(length(i) == 1)
    card(card_header(quizzes()$question[i]), plotOutput("quiz_choice_plot", height = "240px"))
  })

  output$quiz_choice_plot <- renderPlot({
    i <- input$quiz_table_rows_selected
    req(length(i) == 1)
    qd <- quiz_choice_distribution(dash(), quizzes()$quiz_key[i], QUIZ_CATALOG)
    qd$label <- paste0(ifelse(qd$is_correct, "(correct) ", ""), wrap_label(qd$choice_label, 60))
    qd$label <- factor(qd$label, levels = rev(qd$label))
    ggplot(qd, aes(x = students, y = label, fill = is_correct)) +
      geom_col(width = 0.6) +
      geom_text(aes(label = sprintf("  %d (%s)", students, fmt_pct(pct))), hjust = 0, size = 3.8, color = "grey20") +
      scale_fill_manual(values = c(`TRUE` = COLOR_DARK, `FALSE` = "grey70"), guide = "none") +
      scale_x_continuous(expand = expansion(mult = c(0, 0.3))) +
      labs(x = "Students (first answer)", y = NULL) +
      theme_minimal(base_size = 13) +
      theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank())
  })

  # ---- Time ----

  output$time_module_plot <- renderPlot({
    tm <- active_minutes_by_student_module(dash())
    req(nrow(tm) > 0)
    tm$module <- factor(paste("Module", tm$module_number), levels = paste("Module", sort(unique(tm$module_number))))
    ggplot(tm, aes(x = module, y = active_minutes)) +
      geom_boxplot(outlier.shape = NA, fill = COLOR_LIGHT, color = COLOR_DARK, width = 0.55) +
      geom_jitter(width = 0.15, height = 0, size = 1.6, alpha = 0.5, color = COLOR_DARK) +
      labs(x = NULL, y = "Active minutes") +
      theme_minimal(base_size = 13) +
      theme(panel.grid.major.x = element_blank(), panel.grid.minor = element_blank())
  })

  output$time_progress_plot <- renderPlot({
    s <- students()
    req(nrow(s) > 0)
    ggplot(s, aes(x = active_minutes, y = exercises_passed)) +
      geom_point(size = 2.6, alpha = 0.7, color = COLOR_DARK) +
      labs(x = "Total active minutes", y = "Exercises passed") +
      theme_minimal(base_size = 13) +
      theme(panel.grid.minor = element_blank())
  })

  output$topic_table <- renderDT({
    t <- topic_time(dash(), TOPIC_CATALOG)
    if (nrow(t) == 0) return(simple_table(data.frame(Message = "No active-time data yet."), dom = "t"))
    simple_table(data.frame(
      Module = t$module_number,
      Topic = t$topic_title,
      Students = t$students,
      `Median time` = fmt_minutes(t$median_minutes),
      `Total time` = fmt_minutes(t$total_hours * 60),
      check.names = FALSE
    ), page_length = 60, ordering = FALSE)
  })

  # ---- Tutor ----

  tutor_stats <- reactive(tutor_overview(dash()))
  output$tutor_pct <- renderText({
    t <- tutor_stats()
    sprintf("%d of %d (%s)", t$students_chatted, t$students_active, fmt_pct(t$pct_chatted))
  })
  output$tutor_messages <- renderText(tutor_stats()$student_messages)
  output$tutor_median <- renderText(fmt_num(tutor_stats()$median_messages_per_chatter))

  output$tutor_effect_table <- renderTable({
    te <- tutor_after_failure(dash())
    if (nrow(te) == 0) return(data.frame(Note = "No failed attempts yet."))
    data.frame(
      ` ` = te$group,
      `Student/exercise pairs` = te$student_exercise_pairs,
      `Eventually passed` = fmt_pct(te$pct_eventually_passed),
      `Median further attempts to pass` = fmt_num(te$median_further_attempts_to_pass),
      check.names = FALSE
    )
  }, striped = TRUE, spacing = "s")

  output$help_category_plot <- renderPlot({
    cb <- help_category_breakdown(dash())
    req(nrow(cb) > 0)
    cb$help_category <- factor(pretty_category(cb$help_category), levels = rev(pretty_category(cb$help_category)))
    ggplot(cb, aes(x = n, y = help_category)) +
      geom_col(fill = COLOR_DARK, width = 0.6) +
      labs(x = "Student messages", y = NULL) +
      theme_minimal(base_size = 13) +
      theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank())
  })

  output$tutor_student_table <- renderDT({
    ts <- tutor_students()
    simple_table(data.frame(
      Student = ts$display_name,
      Messages = ts$messages,
      Exercises = ts$exercises,
      `Asked for answer` = sprintf("%d (%s)", ts$wants_answer, fmt_pct(ts$pct_wants_answer)),
      `Last message` = fmt_time(ts$last_message_at),
      check.names = FALSE
    ), page_length = 8, dom = "tp")
  })

  output$tutor_exercise_table <- renderDT({
    te <- tutor_by_exercise(dash())
    simple_table(data.frame(
      Exercise = exercise_label(te),
      `Students who chatted` = sprintf("%d of %d attempters (%s)", te$students_chatted, te$students_attempted, fmt_pct(te$pct_of_attempters_chatted)),
      `Student messages` = te$student_messages,
      `Most common question type` = ifelse(is.na(te$top_category), "--", pretty_category(te$top_category)),
      check.names = FALSE
    ))
  })

  # Transcript browser. Reads from the same snapshot as everything else, so
  # it also works in demo mode.
  observe({
    ts <- tutor_students()
    s <- ts[order(ts$display_name), ]
    # Preserve the current selection across a "Refresh data" click --
    # without `selected`, updateSelectInput() resets to the placeholder.
    updateSelectInput(
      session, "chat_student",
      choices = c("Select a student..." = "", setNames(s$student_id, s$display_name)),
      selected = isolate(input$chat_student)
    )
  })

  observeEvent(input$chat_student, {
    if (!nzchar(input$chat_student)) {
      updateSelectInput(session, "chat_exercise", choices = c("Select a student first..." = ""))
      return()
    }
    d <- dash()
    ids <- unique(d$chats$exercise_id[d$chats$student_id == input$chat_student])
    ex <- d$exercises[d$exercises$exercise_id %in% ids, ]
    updateSelectInput(session, "chat_exercise",
                      choices = c("Select an exercise..." = "", setNames(ex$exercise_id, sprintf("Module %d: %s", ex$module_number, ex$title))))
  })

  output$chat_transcript <- renderUI({
    req(input$chat_student, input$chat_exercise)
    chats <- dash()$chats
    transcript <- chats[chats$student_id == input$chat_student & chats$exercise_id == as.integer(input$chat_exercise), ]
    transcript <- transcript[order(transcript$created_at), ]

    if (nrow(transcript) == 0) {
      return(div(class = "text-muted mt-3", "No messages for this exercise."))
    }

    tagList(lapply(seq_len(nrow(transcript)), function(i) {
      row <- transcript[i, ]
      is_student <- row$role == "student"
      div(
        class = paste("mt-2 p-2 rounded", if (is_student) "bg-light" else "bg-white border"),
        strong(if (is_student) "Student" else "Tutor"),
        span(class = "text-muted small ms-2", fmt_time(row$created_at)),
        if (is_student && !is.na(row$help_category)) {
          span(class = "badge bg-secondary ms-2", pretty_category(row$help_category))
        },
        div(class = "mt-1", row$message)
      )
    }))
  })

  # ---- Needs attention ----

  output$stuck_table <- renderDT({
    s <- stuck_students(dash())
    if (nrow(s) == 0) return(simple_table(data.frame(Message = "No students currently stuck on an exercise."), dom = "t"))
    simple_table(data.frame(
      Student = s$display_name,
      Exercise = sprintf("M%d: %s", s$module_number, s$title),
      Attempts = s$n_attempts,
      `Last attempt` = fmt_time(s$last_attempt_at),
      check.names = FALSE
    ))
  })

  output$stalled_table <- renderDT({
    s <- students()
    s <- s[s$status == "Stalled", ]
    if (nrow(s) == 0) return(simple_table(data.frame(Message = "No stalled students."), dom = "t"))
    s <- s[order(s$days_inactive), ]
    simple_table(data.frame(
      Student = s$display_name,
      `Last active` = fmt_time(s$last_seen),
      `Days inactive` = fmt_num(s$days_inactive, 0),
      Passed = sprintf("%d / %d", s$exercises_passed, s$n_exercises),
      `Stopped in module` = ifelse(is.na(s$current_module), "--", s$current_module),
      check.names = FALSE
    ))
  })

  output$answer_seeker_table <- renderDT({
    a <- answer_seekers(dash())
    if (nrow(a) == 0) return(simple_table(data.frame(Message = "Nobody yet."), dom = "t"))
    simple_table(data.frame(
      Student = a$display_name,
      `Asked for the answer` = a$wants_answer,
      `All messages` = a$messages,
      `Last message` = fmt_time(a$last_message_at),
      check.names = FALSE
    ))
  })
}

#' Wrap long quiz answer labels for the choice-split chart's y-axis.
wrap_label <- function(x, width) vapply(x, function(s) paste(strwrap(s, width), collapse = "\n"), character(1))

shinyApp(ui, server)
