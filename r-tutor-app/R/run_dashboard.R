# Launches the instructor dashboard standalone, for local testing.
#
# Usage: Rscript R/run_dashboard.R          (real data)
#        Rscript R/run_dashboard.R demo     (synthetic class -- see R/dashboard_demo_data.R)
# Then open http://127.0.0.1:7413 in a browser.
# Demo mode logs in with the password "demo" (it shows no real student data,
# so there's no reason to reuse the real DASHBOARD_PASSWORD for it).

PROJECT_ROOT <- "C:/Users/sarah/OneDrive/Documents/R_tutor/r-tutor-app"

readRenviron(file.path(PROJECT_ROOT, ".Renviron"))
if ("demo" %in% commandArgs(trailingOnly = TRUE)) {
  Sys.setenv(DASHBOARD_DEMO = "true", DASHBOARD_PASSWORD = "demo")
}
setwd(file.path(PROJECT_ROOT, "instructor_dashboard"))

options(shiny.launch.browser = FALSE)
shiny::runApp(".", host = "127.0.0.1", port = 7413)
