# Launches a tutorial standalone (outside RStudio's "Run Document" button),
# for testing in a browser. Edit MODULE_FILE below to switch which .Rmd it
# serves -- "course.Rmd" (the merged, currently-deployed all-5-modules
# tutorial) is the default; the original per-module files
# (module_1.Rmd..module_5.Rmd) are kept for reference and still work here
# too.
#
# Usage: Rscript R/run_tutorial.R
# Then open http://127.0.0.1:7412 in a browser.

MODULE_FILE <- "course.Rmd"
PROJECT_ROOT <- "C:/Users/sarah/OneDrive/Documents/R_tutor/r-tutor-app"

readRenviron(file.path(PROJECT_ROOT, ".Renviron"))
setwd(file.path(PROJECT_ROOT, "tutorials"))

# Outside RStudio, R doesn't know where RStudio's bundled pandoc lives.
# Adjust this path if RStudio is installed somewhere other than the default.
Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")

options(shiny.launch.browser = FALSE)
# Belt-and-suspenders alongside the project's .Rprofile (which only takes
# effect if R started with this project's root as its working directory) --
# see .Rprofile for why local-filesystem tutorial progress caching needs to
# stay off for local testing.
options(tutorial.storage = "none")
rmarkdown::run(
  MODULE_FILE,
  shiny_args = list(host = "127.0.0.1", port = 7412, launch.browser = FALSE)
)
