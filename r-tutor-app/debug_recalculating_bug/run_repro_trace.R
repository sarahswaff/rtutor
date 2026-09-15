# Wire-level trace test -- see HANDOFF.md, "Wire-level trace test" section.
#
# Prints every outgoing (server -> browser) Shiny message to the R console.
# Run this, then open the printed URL in your REAL BROWSER (the one where
# the bug happens) -- not RStudio's Viewer. You do NOT need to click
# anything. Just get through the identity modal and navigate to the
# "Installing R and RStudio" topic (the first quiz), then watch/search the
# R console for "install-quiz-answer_container".
#
# What to look for, in the R console output:
#   - A line starting "SEND" containing "install-quiz-answer_container"
#     with real HTML content (the quiz's answer choices) => server sent it.
#   - No such line at all, ever => the server-side observer never actually
#     ran/produced a value, despite the earlier "PATCHED" log. This is the
#     key fork HANDOFF.md describes.
#
# This will print A LOT of console output (every message, not just this
# one output) -- that's expected. Search/scroll for the ID above.

setwd("C:/Users/sarah/OneDrive/Documents/R_tutor/r-tutor-app/debug_recalculating_bug")
Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
options(shiny.launch.browser = FALSE)
options(shiny.trace = "send")
rmarkdown::run(
  "repro.Rmd",
  shiny_args = list(host = "127.0.0.1", port = 7414, launch.browser = FALSE)
)
