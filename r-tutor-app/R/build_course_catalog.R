# R/build_course_catalog.R
# Builds two small lookup tables the instructor dashboard uses to turn the
# raw IDs it logs into something readable:
#   - instructor_dashboard/topic_catalog.csv: every `##` topic's anchor id
#     (exactly what activity_time.topic_id stores), module, title, and
#     position in the course -- so time-on-topic can be shown in course
#     order with real titles.
#   - instructor_dashboard/quiz_catalog.csv: every quiz's question text and
#     each choice's label, keyed by quiz_key/choice_id (exactly what
#     quiz_responses stores) -- so "which wrong answer do students pick"
#     shows the actual answer text, not 'wrong_compare'.
#
# Reads the RENDERED tutorials/course.html, not the .Rmd: topic anchors come
# from pandoc's own slug rules (e.g. "R-squared -- how much..." becomes
# 'r-squared-how-much-...'), which are easy to get subtly wrong by
# reimplementing them. course.html is produced by any local run
# (Rscript R/run_tutorial.R) -- rerun this script after a run whenever
# topics or quizzes change, then regenerate deploy/instructor_dashboard/.
#
# Usage: Rscript R/build_course_catalog.R

library(xml2)

PROJECT_ROOT <- "C:/Users/sarah/OneDrive/Documents/R_tutor/r-tutor-app"
html <- read_html(file.path(PROJECT_ROOT, "tutorials", "course.html"))

topic_nodes <- xml_find_all(html, "//div[contains(@class, 'section') and contains(@class, 'level2')]")
topic_ids <- sub("^section-", "", xml_attr(topic_nodes, "id"))
topic_titles <- vapply(topic_nodes, function(n) xml_text(xml_find_first(n, "./h2")), character(1))
topics <- data.frame(
  topic_id = topic_ids,
  module_number = suppressWarnings(as.integer(sub("^module-([0-9]+)-.*$", "\\1", topic_ids))),
  topic_title = sub("^Module [0-9]+: ", "", trimws(topic_titles)),
  topic_order = seq_along(topic_ids)
)
write.csv(topics, file.path(PROJECT_ROOT, "instructor_dashboard", "topic_catalog.csv"), row.names = FALSE)

# quiz_question_ui() renders a plain shiny::radioButtons() group whose
# question text is the group's <label> and whose choices are radio inputs
# (value = choice_id) each followed by a <span> holding the label text.
quiz_nodes <- xml_find_all(html, "//div[contains(@class, 'shiny-input-radiogroup')]")
quizzes <- do.call(rbind, lapply(quiz_nodes, function(n) {
  quiz_key <- xml_attr(n, "id")
  topic <- xml_find_first(n, "./ancestor::div[contains(@class, 'level2')]")
  inputs <- xml_find_all(n, ".//input[@type='radio']")
  data.frame(
    quiz_key = quiz_key,
    topic_id = sub("^section-", "", xml_attr(topic, "id")),
    question = trimws(xml_text(xml_find_first(n, ".//label[contains(@class, 'control-label')]"))),
    choice_id = xml_attr(inputs, "value"),
    choice_label = trimws(vapply(inputs, function(i) xml_text(xml_find_first(i, "./following-sibling::span")), character(1)))
  )
}))
# Module 7's practice module picker is also a radio group, but not a quiz.
quizzes <- quizzes[grepl("_quiz$", quizzes$quiz_key), ]
quizzes$module_number <- topics$module_number[match(quizzes$topic_id, topics$topic_id)]
quizzes$quiz_order <- match(quizzes$quiz_key, unique(quizzes$quiz_key))
write.csv(quizzes, file.path(PROJECT_ROOT, "instructor_dashboard", "quiz_catalog.csv"), row.names = FALSE)

cat(sprintf("Wrote %d topics and %d quizzes (%d choices).\n", nrow(topics), length(unique(quizzes$quiz_key)), nrow(quizzes)))
