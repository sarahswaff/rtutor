# Launches a tutorial module standalone (outside RStudio's "Run Document"
# button), for testing in a browser. Edit MODULE_FILE below to switch modules.
#
# Usage: Rscript R/run_tutorial.R
# Then open http://127.0.0.1:7412 in a browser.

MODULE_FILE <- "module_2.Rmd"
PROJECT_ROOT <- "C:/Users/sarah/OneDrive/Documents/R_tutor/r-tutor-app"

readRenviron(file.path(PROJECT_ROOT, ".Renviron"))
setwd(file.path(PROJECT_ROOT, "tutorials"))

# Outside RStudio, R doesn't know where RStudio's bundled pandoc lives.
# Adjust this path if RStudio is installed somewhere other than the default.
Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")

options(shiny.launch.browser = FALSE)
rmarkdown::run(
  MODULE_FILE,
  shiny_args = list(host = "127.0.0.1", port = 7412, launch.browser = FALSE)
)
