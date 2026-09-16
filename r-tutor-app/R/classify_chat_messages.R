# Offline classifier: labels every not-yet-categorized student chat message
# with a help_category (see HELP_CATEGORIES in R/db_utils.R), so the
# instructor dashboard's "Chats" tab can show what kind of help students are
# actually asking for, in aggregate.
#
# Deliberately NOT part of either live app (course.Rmd or
# instructor_dashboard/app.R) -- run this by hand (or on a schedule) whenever
# you want fresh categories before checking the dashboard. New messages sit
# as "uncategorized" until the next run; nothing breaks in the meantime.
#
# Usage: Rscript R/classify_chat_messages.R

PROJECT_ROOT <- "C:/Users/sarah/OneDrive/Documents/R_tutor/r-tutor-app"
readRenviron(file.path(PROJECT_ROOT, ".Renviron"))
setwd(PROJECT_ROOT)

source("R/db_utils.R")
library(ellmer)

BATCH_SIZE <- 20

CLASSIFIER_SYSTEM_PROMPT <- paste0(
  "You are classifying messages a student sent to an R tutoring chatbot, ",
  "in an introductory R course. For EACH message, assign exactly one ",
  "category from this fixed list:\n\n",
  "- syntax_error: a specific error message, or code that won't run\n",
  "- conceptual_confusion: doesn't understand a concept/why something works\n",
  "- how_do_i_start: doesn't know where to begin an exercise\n",
  "- wants_answer: is asking to just be given the solution/correct code\n",
  "- environment_setup: R/RStudio installation, packages, or general setup\n",
  "- other: doesn't clearly fit any category above\n\n",
  "Respond with ONLY a JSON array of strings, one category per input ",
  "message, in the same order as the input. No other text."
)

classify_batch <- function(client, messages) {
  numbered <- paste0(seq_along(messages), ". ", messages, collapse = "\n")
  reply <- client$chat(paste0(
    "Classify these ", length(messages), " messages:\n\n", numbered
  ))
  # Strip a markdown code fence (```json ... ``` or ``` ... ```) if the
  # model wrapped its answer in one, despite being asked for JSON only.
  reply_clean <- trimws(gsub("^```(json)?|```$", "", trimws(reply)))
  categories <- tryCatch(
    jsonlite::fromJSON(reply_clean),
    error = function(e) NULL
  )
  if (is.null(categories) || length(categories) != length(messages) ||
      !all(categories %in% HELP_CATEGORIES)) {
    message("Batch classification failed to parse cleanly, skipping this batch: ", reply)
    return(NULL)
  }
  categories
}

con <- get_con()
total_classified <- 0

repeat {
  batch <- get_uncategorized_chat_messages(con, limit = BATCH_SIZE)
  if (nrow(batch) == 0) break

  client <- ellmer::chat_anthropic(
    model = "claude-haiku-4-5-20251001",
    system_prompt = CLASSIFIER_SYSTEM_PROMPT
  )
  categories <- classify_batch(client, batch$message)

  if (is.null(categories)) break # avoid an infinite loop on a bad batch

  for (i in seq_len(nrow(batch))) {
    set_chat_message_category(con, batch$chat_id[i], categories[i])
  }
  total_classified <- total_classified + nrow(batch)
  cat("Classified", nrow(batch), "messages (", total_classified, "so far)\n")
}

dbDisconnect(con)
cat("Done. Total newly classified:", total_classified, "\n")
