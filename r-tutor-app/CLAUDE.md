# R Tutor App — Project Context

## Purpose
Interactive R/RStudio tutorial app for a split-level university course, built with learnr.
Goal: bring students to baseline R/RStudio literacy before real coursework begins.
Students are NOT expected to become programmers -- they'll eventually run instructor- or
LLM-provided scripts, not write substantial code from scratch.

## Tech stack
- learnr (interactive tutorials, .Rmd + `runtime: shiny_prerendered`)
- gradethis (exercise grading) -- install via `pak::pak("rstudio/gradethis")`, NOT on CRAN
- ellmer (LLM calls) -- may need `pak::pak("tidyverse/ellmer")` if not on CRAN
- shinychat (chat UI) -- uses `chat_mod_ui()` / `chat_mod_server()`; each user session needs
  its own ellmer client (never share one client across sessions)
- Shiny app framework
- DBI + RPostgres for database access
- Supabase (hosted Postgres). Use the **Session pooler** connection (port 5432, host ending
  in `pooler.supabase.com`) -- NOT Transaction pooler (serverless-oriented) or Direct
  connection (IPv6-only, usually unreachable)
- Anthropic API, model `claude-haiku-4-5-20251001`, for the tutor chat. Spending cap is set
  in the Anthropic console.

## Deployment target
Not finalized yet (shinyapps.io vs Posit Connect vs self-hosted, still undecided).
IMPORTANT: whatever the target, persistence must live in the external Postgres DB, never
in local files -- shinyapps.io's filesystem is ephemeral and will silently lose local data.

## Folder structure
```
r-tutor-app/
├── .Renviron (gitignored)  -- SUPABASE_DB_HOST, SUPABASE_DB_USER, SUPABASE_DB_PASSWORD, ANTHROPIC_API_KEY
├── .gitignore
├── schema.sql
├── R/
│   ├── db_utils.R      -- shared DB functions
│   └── tutor_utils.R   -- ellmer tutor chat functions + system prompt
├── tutorials/
│   ├── module_1.Rmd    -- DONE, tested end-to-end
│   └── module_2.Rmd    -- IN PROGRESS (see "Current status" below)
├── student_app/         -- not yet built
└── instructor_dashboard/ -- not yet built
```

## Database schema (full DDL in schema.sql)
- `students(student_id uuid PK, display_name, email, first_login_at, last_active_at, created_at)`
  -- generic identity for now, NO Canvas/roster matching yet. This is deliberate: identity
  is designed as a swappable layer, so every other table refers only to `student_id`, never
  to how that identity was established. Roster-matching gets added in FRONT of this later
  without touching anything downstream.
- `modules(module_id, module_number, title)`
- `exercises(exercise_id, module_id FK, exercise_key unique, title, order_index, learning_objective)`
  -- `exercise_key` must exactly match the learnr exercise chunk label used in the .Rmd.
  `learning_objective` is plain-language, used to give the LLM tutor context WITHOUT ever
  giving it the actual answer.
- `exercise_attempts(attempt_id, student_id FK, exercise_id FK, submitted_code, passed bool, gradethis_message, created_at)`
  -- every attempt is its own row, by deliberate choice (never overwrite/update in place).
- `chat_logs(chat_id, student_id FK, exercise_id FK, role 'student'|'tutor', message, created_at)`
- `exercise_mastery` -- a VIEW (not a table), most recent pass/fail per student per exercise,
  computed live from exercise_attempts. Dashboard mastery queries should read from this view,
  never a hand-maintained status column.

## Curriculum (5 modules, finalized -- do not reorganize without reason)
1. **Introduction** -- install R/RStudio, panes, working directory. DONE (module_1.Rmd).
2. **Basic Code** -- packages, console, comments, run provided code, error messages, help().
   IN PROGRESS (module_2.Rmd).
3. **Data** -- hello world, data types, naming conventions, vectors, assignment, basic
   functions/comparisons, data structures, import.
4. **Clean up** -- inspect, rename columns, index/subset, pipe, dplyr verbs
   (filter/select/mutate/arrange/group_by/summarize), handling NAs.
5. **Actual Work** -- ggplot basics, markdown awareness (NOT authoring -- students just need
   to know it exists, it'll likely be provided to them), script save/import, file naming
   conventions (light touch on version control -- awareness only, not real git usage).

A capstone pipeline assessment exists but is explicitly OUT of scope for the tutorial itself.

## Key conventions (established through real trial and error -- follow these)

**Exercises should be minimal and deliberate, not one per subtopic.** Most content is
instructional/quiz-only; only add a graded exercise where it earns its place.

**YAML header for every tutorial module:**
```yaml
---
title: "..."
output:
  learnr::tutorial:
    progressive: true
    allow_skip: false
runtime: shiny_prerendered
---
```
This forces at least one submission on graded exercises before a student can move on.
It does NOT gate quiz questions -- that's a known learnr limitation, and it's fine, not a bug.

**CRITICAL learnr gotcha:** `progressive`/`allow_skip` only gates movement between `###`
sub-sections WITHIN a `##` Topic. It does NOT gate movement between separate `##` Topics.
Any exercise that needs to be gated MUST live in a `###` sub-section sharing its `##` Topic
with whatever content should be locked behind it. (This cost significant debugging time in
Module 1 -- don't repeat the mistake.)

**Identity capture pattern** (see module_1.Rmd for the working reference implementation):
a `context="server"` chunk shows a modal on tutorial start asking for a name, calls
`get_or_create_student()`, and stores the result on `session$userData$student_id` --
NOT a global `options()` call, which is unsafe across concurrent sessions. Exercise check
code (which runs semi-isolated from the main server chunk) reaches it via
`shiny::getDefaultReactiveDomain()$userData$student_id`.

**Tutor chat trigger design (agreed, not yet built):** the chat must be ALWAYS accessible,
not gated behind failure -- passing a gradethis check doesn't guarantee real understanding,
and the student should be actively encouraged to use it any time, including after passing.
On a FAILED attempt specifically, the chat should auto-open. Planned approach:
`bslib::accordion_panel_open()` targeting an accordion (collapsed by default, so it's a
manual toggle the rest of the time) that houses `chat_mod_ui()`. NOT YET TESTED.

**Tutor context assembly** (see `tutor_utils.R`): before starting each new chat, query the
attempt count + most recent attempt (code, pass/fail, gradethis message) + the exercise's
`learning_objective`, and build a dynamic context block appended to the static system
prompt. The LLM is NEVER given the actual correct solution/answer key.

**The system prompt went through many rounds of deliberate critique** -- see
`TUTOR_SYSTEM_PROMPT` in `tutor_utils.R` for the current version. Do not casually rewrite it
without understanding why each part exists:
- Escalating help across attempts (question-only -> name concept -> analogous example),
  but attempt count is a *starting point*, not a strict gate -- read actual conversational
  signal too (e.g., a student who's clearly close but hit a typo can get more help sooner)
- Awareness of cumulative leakage across a whole conversation, not just per-message
- Grader skepticism (gradethis can be wrong) WITHOUT the LLM overclaiming certainty, since
  it cannot execute code either
- Never inventing execution results/output it wasn't given
- An escape hatch for clearly-environmental (not conceptual) problems
- Responses end in a concrete next step, but not forced onto every single turn of an
  ongoing back-and-forth
- All tiering/escalation logic is internal reasoning -- never exposed to the student

## Known environment gotchas (this machine, Windows)
- The Rtools warning on every `install.packages()` call is normal/harmless unless installing
  something that needs compilation from source.
- gradethis, ellmer, and shinychat are not reliably on CRAN -- install from GitHub via `pak`.
- This machine had a persistent SSL download error from CRAN. What actually fixed it:
  disabling "Use secure download method for HTTP" in RStudio's
  **Tools > Global Options > Packages** -- NOT `options(download.file.method = ...)`,
  which didn't reliably persist across sessions/`.Rprofile` for reasons never fully
  resolved. If this resurfaces on a different machine, try the Global Options route first.
- A corrupted `.RData` previously caused RStudio to hang indefinitely on startup. Workspace
  save/restore is now disabled in **Global Options > General**. If this resurfaces, delete
  `~/.RData` and confirm that setting is still off.

## Deliberate scope decisions -- don't relitigate without a real reason
- No password auth. Students identified by name + email only; roster-CSV matching is planned
  but NOT YET BUILT (deferred on purpose -- the identity table is designed to make this a
  drop-in addition later).
- No Canvas LTI integration yet. A lightweight roster-CSV approach is planned instead; full
  LTI SSO/gradebook integration is deferred to a later phase pending institutional approval.
- Instructor dashboard not started -- deliberately deferred until real attempt data exists
  from testing, so it can be built against real shapes of data rather than guesses.
- Every exercise attempt is logged as its own row (explicitly chosen over update-in-place).

## Current status / immediate next step
Module 1 is fully built and tested end-to-end: identity capture -> quiz content -> gated
exercise -> logged attempt with correct student_id, including the ### restructuring fix for
progressive gating.

Module 2 is in progress:
- Schema additions written (not yet confirmed run): `learning_objective` column added to
  `exercises`; Module 2 + two exercise rows (`module2_comment_out`, `module2_fix_error`)
  -- see schema.sql and the ALTER/INSERT statements from recent conversation history.
- `R/tutor_utils.R` is written (system prompt + context-assembly functions +
  `start_tutor_chat()`) but **NOT YET TESTED** -- this is the immediate next step.

**Next actions, in order:**
1. Run the schema additions against Supabase if not already done.
2. Test `start_tutor_chat()` standalone (source db_utils.R + tutor_utils.R, create a test
   student, log a fake failed attempt, call `start_tutor_chat()`, send a message, confirm
   the response actually follows the system prompt's escalation/question-based behavior).
3. Build the shinychat UI into `module_2.Rmd`: `chat_mod_ui()`/`chat_mod_server()`, wired to
   auto-open via `bslib::accordion_panel_open()` on a failed attempt, with both directions
   of every conversation logged via `log_chat()`.
4. Write Module 2's instructional/quiz content for the remaining topics (packages, console,
   comments, running code, error messages, help()).
5. Test Module 2 end-to-end, same rigor as Module 1.
6. Modules 3-5 follow the same established pattern.
7. Instructor dashboard, once there's real attempt/chat data to build it against.
