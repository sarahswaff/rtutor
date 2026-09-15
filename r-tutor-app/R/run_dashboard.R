# Launches the instructor dashboard standalone, for local testing.
#
# Usage: Rscript R/run_dashboard.R
# Then open http://127.0.0.1:7413 in a browser.

PROJECT_ROOT <- "C:/Users/sarah/OneDrive/Documents/R_tutor/r-tutor-app"

readRenviron(file.path(PROJECT_ROOT, ".Renviron"))
setwd(file.path(PROJECT_ROOT, "instructor_dashboard"))

options(shiny.launch.browser = FALSE)
shiny::runApp(".", host = "127.0.0.1", port = 7413)
