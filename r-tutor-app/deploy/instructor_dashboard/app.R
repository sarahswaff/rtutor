library(shiny)
library(bslib)
library(DT)
library(ggplot2)
library(DBI)

source("R/db_utils.R")

TOTAL_EXERCISES <- 18L # keep in sync with schema.sql / tutorials

check_password <- function(attempt) {
  expected <- Sys.getenv("DASHBOARD_PASSWORD")
  nzchar(expected) && identical(attempt, expected)
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
    nav_panel(
      "Overview",
      layout_column_wrap(
        width = 1 / 4,
        value_box("Students", textOutput("n_students", inline = TRUE)),
        value_box("Active in last 7 days", textOutput("n_active_week", inline = TRUE)),
        value_box("Avg. exercises passed", textOutput("avg_passed", inline = TRUE)),
        value_box("Overall pass rate", textOutput("overall_pass_rate", inline = TRUE))
      ),
      card(
        card_header("Pass rate by exercise"),
        plotOutput("exercise_pass_plot", height = "420px")
      ),
      card(
        card_header("Module completion (students who passed every exercise in the module)"),
        DTOutput("module_completion_table")
      )
    ),
    nav_panel(
      "Roster",
      card(
        card_header("All students"),
        DTOutput("roster_table")
      )
    ),
    nav_panel(
      "Needs attention",
      card(
        card_header("Students stuck on an exercise (3+ attempts, not yet passed)"),
        DTOutput("struggling_table")
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

  # Re-query the DB on load and whenever "Refresh data" is clicked.
  refresh_tick <- reactiveVal(0)
  observeEvent(input$refresh_btn, refresh_tick(refresh_tick() + 1))

  roster <- reactive({
    refresh_tick()
    con <- get_con()
    on.exit(dbDisconnect(con))
    get_roster_summary(con)
  })

  module_completion_raw <- reactive({
    refresh_tick()
    con <- get_con()
    on.exit(dbDisconnect(con))
    get_module_completion(con)
  })

  exercise_stats <- reactive({
    refresh_tick()
    con <- get_con()
    on.exit(dbDisconnect(con))
    get_exercise_stats(con)
  })

  struggling <- reactive({
    refresh_tick()
    con <- get_con()
    on.exit(dbDisconnect(con))
    get_struggling_students(con)
  })

  # ---- Overview tab ----

  output$n_students <- renderText({
    nrow(roster())
  })

  output$n_active_week <- renderText({
    r <- roster()
    cutoff <- Sys.time() - as.difftime(7, units = "days")
    sum(r$last_active_at >= cutoff, na.rm = TRUE)
  })

  output$avg_passed <- renderText({
    r <- roster()
    if (nrow(r) == 0) return("--")
    sprintf("%.1f / %d", mean(r$exercises_passed), TOTAL_EXERCISES)
  })

  output$overall_pass_rate <- renderText({
    es <- exercise_stats()
    total_attempted <- sum(es$n_students_attempted)
    if (total_attempted == 0) return("--")
    sprintf("%.0f%%", 100 * sum(es$n_students_passed) / total_attempted)
  })

  output$exercise_pass_plot <- renderPlot({
    es <- exercise_stats()
    req(nrow(es) > 0)
    es$pass_rate <- ifelse(es$n_students_attempted > 0,
      es$n_students_passed / es$n_students_attempted, NA)
    es$exercise_title <- factor(es$exercise_title, levels = es$exercise_title)

    ggplot(es, aes(x = exercise_title, y = pass_rate, fill = factor(module_number))) +
      geom_col() +
      scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
      labs(x = NULL, y = "Pass rate", fill = "Module") +
      coord_flip() +
      theme_minimal(base_size = 13)
  })

  output$module_completion_table <- renderDT({
    mc <- module_completion_raw()
    req(nrow(mc) > 0)
    mc$completed <- mc$n_passed >= mc$n_exercises & mc$n_exercises > 0

    summary_tbl <- aggregate(
      completed ~ module_number + module_title,
      data = mc, FUN = sum
    )
    n_students <- length(unique(mc$student_id))
    summary_tbl <- summary_tbl[order(summary_tbl$module_number), ]
    names(summary_tbl) <- c("Module #", "Module", "Students who completed it")
    summary_tbl[["% of class"]] <- sprintf(
      "%.0f%%", 100 * summary_tbl[["Students who completed it"]] / n_students
    )

    datatable(summary_tbl, rownames = FALSE, options = list(paging = FALSE, dom = "t"))
  })

  # ---- Roster tab ----

  output$roster_table <- renderDT({
    r <- roster()
    r$exercises_passed <- sprintf("%d / %d", r$exercises_passed, TOTAL_EXERCISES)
    display <- r[, c("display_name", "first_login_at", "last_active_at",
                      "exercises_passed", "exercises_attempted")]
    names(display) <- c("Student", "First login", "Last active", "Passed", "Attempted")
    datatable(display, rownames = FALSE, options = list(pageLength = 25))
  })

  # ---- Needs attention tab ----

  output$struggling_table <- renderDT({
    s <- struggling()
    if (nrow(s) == 0) {
      return(datatable(
        data.frame(Message = "No students currently stuck on an exercise."),
        rownames = FALSE, options = list(dom = "t")
      ))
    }
    names(s) <- c("Student", "Exercise", "Module #", "Attempts", "Last attempt")
    datatable(s, rownames = FALSE, options = list(pageLength = 25))
  })
}

shinyApp(ui, server)
