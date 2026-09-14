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

**Tutor chat trigger design (built and tested in Module 2 -- follow this pattern):** the
chat must be ALWAYS accessible, not gated behind failure -- passing a gradethis check
doesn't guarantee real understanding, and the student should be actively encouraged to use
it any time, including after passing. On a FAILED attempt specifically, the chat auto-opens
via `bslib::accordion_panel_open(id = <accordion_id>, values = "Ask the Tutor", session =
session)`, called from inside the exercise's check code, targeting an
`accordion(id = ..., open = FALSE, accordion_panel(title = "Ask the Tutor", chat_ui(...)))`
that houses the chat.

`chat_mod_ui()`/`chat_mod_server()` are DEPRECATED as of shinychat 0.5.0 (the version
installed in this project) -- do not use them despite older references to them in this
file's history. Instead wire the chat manually with `shinychat::chat_ui()` in the UI plus,
in a `context="server"` chunk, `observeEvent(input[[paste0(chat_id, "_user_input")]], ...)`
that calls `client$stream_async(user_text)` and `shinychat::chat_append(chat_id, stream,
session = session)`. This manual form (not the higher-level `chat_server()`) is what makes
it possible to log both directions of every message via `log_chat()`, since neither
`chat_mod_server()` nor `chat_server()` expose a per-message callback hook.

A fresh `start_tutor_chat()` client (plus `shinychat::chat_clear(chat_id, greeting = TRUE,
session = session)` to visually reset the panel) is created every time the accordion panel
transitions from closed to open -- detected via `observeEvent(input[[accordion_id]], ...)`,
since `accordion(id = ...)` exposes the set of currently-open panel values as that Shiny
input. This covers both a manual open and the failure-triggered
`accordion_panel_open()` call, since both update the same input.

**bslib/shinychat require Bootstrap 5, but learnr's tutorial template defaults to Bootstrap
3.** Any module using `bslib::accordion()`, `shinychat::chat_ui()`, or any other BS5-only
component MUST do both of the following, or the components silently fail to render (browser
console: "requires Bootstrap version 5 but this page is using version 3") with no error
surfaced to the student:
1. Add `theme: !expr bslib::bs_theme(version = 5, bootswatch = "cerulean")` under
   `learnr::tutorial:` in the YAML header (this affects pandoc's static template only).
2. Also emit `htmltools::tagList(bslib::bs_theme_dependencies(bslib::bs_theme(version = 5,
   bootswatch = "cerulean")))` as the return value of a plain (non-`context="server"`) chunk
   placed inside the first `##` topic (NOT before the first heading -- content before any
   `##` heading renders in the wrong place in learnr's layout). This actually injects the
   BS5 JS/CSS dependencies into the live Shiny page; step 1 alone is not sufficient. Do NOT
   use `shiny::bootstrapLib()` for this -- printed directly in a chunk it dumps its own
   function source as literal text onto the page; `bs_theme_dependencies()` wrapped in
   `tagList()` is the version that actually works.
Module 1 has no bslib components and was left alone, but ANY module (existing or new) that
adds a tutor chat panel needs both of the steps above.

**gradethis check chunks MUST have a matching `*-error-check` chunk, or errors are graded
by gradethis's generic default instead of your code.** If a student's exercise code throws
a real R error (a very likely outcome for "fix the error"-style exercises, and possible by
accident in any exercise), learnr routes grading to `<label>-error-check` -- and if that
chunk doesn't exist, it falls back entirely to `gradethis_error_checker()`'s generic
message, silently skipping your `log_attempt()` call and your `accordion_panel_open()` auto-open.
Define both `<label>-check` and `<label>-error-check` for every graded exercise. Do NOT
name the exercise chunk itself with "error" as a standalone word in the label (e.g. don't
use `fix-error-exercise`) -- learnr's suffix-stripping to recover the base exercise label
from `<label>-error-check` gets confused by an extra "error" already in the label and the
tutorial fails to even start. Use something like `fix-the-bug-exercise` instead.

Also note: a `grade_this({...})` result CANNOT be assigned to a variable in `setup` and
then referenced by name from multiple `*-check`/`*-error-check` chunks -- gradethis rewires
the enclosing environment per call site and reusing the same object across chunks throws
"Can't change the parent of a locked environment". Instead, put the actual grading
*logic* in a plain function (not a `grade_this()` object) in `setup`, and call `grade_this({...})`
fresh, inline, in each `*-check`/`*-error-check` chunk, delegating to that shared plain
function. See `evaluate_comment_exercise()` / `evaluate_fix_the_bug_exercise()` and
`log_attempt_and_maybe_open_chat()` in module_2.Rmd's setup chunk for the working pattern.

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
- Outside RStudio, `rmarkdown::run()` doesn't know where RStudio's bundled pandoc lives --
  set `Sys.setenv(RSTUDIO_PANDOC = ...)` first (see `R/run_tutorial.R`, which has the actual
  path on this machine).
- **Reported (not reproduced): "Run Document" in RStudio's Viewer pane, clicking a module's
  "Start Over" link, then the whole tutorial stops responding to clicks -- no error, no
  spinner.** Tested extensively via `R/run_tutorial.R` in an external browser (repeatedly,
  clean sessions) and could not reproduce it there -- Start Over, navigation, Run Code, and
  Submit Answer all kept working. Since every DB-backed action (identity capture, attempt
  logging, chat) opens a fresh Postgres connection synchronously with no timeout, a stalled
  connection would freeze the whole single-threaded Shiny process exactly like this, with no
  visible error -- `connect_timeout = 10` was added to `get_con()` in `db_utils.R` as a
  hardening measure regardless of whether that's the actual cause. If this resurfaces, the
  first diagnostic step is testing with the tutorial forced into an external browser instead
  of the Viewer pane (Global Options, or just call `rmarkdown::run()` from the console
  yourself) to isolate a Viewer-pane-specific issue from a real app bug.

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
progressive gating. It has no tutor chat panel (predates that feature) and was left alone --
see "Tutor chat / bslib retrofit" below.

Module 2 is fully built and tested end-to-end: identity capture -> packages/console/comments/
running-code/errors/help content -> two gated exercises (`module2_comment_out`,
`module2_fix_error`), each with its own always-available tutor chat panel that auto-opens on
a failed attempt. Schema additions (the `learning_objective` column, the Module 2 row, and
its two exercise rows) have been run against the real Supabase database. Verified against the
live app (via `rmarkdown::run()` + a browser, not just code review): identity modal + DB
write, progressive gating (submitting is required before "Continue" unlocks -- confirmed both
the blocked and unblocked cases), both exercises' pass/fail/error-in-submitted-code paths,
DB attempt logging with correct student_id/exercise_id, tutor chat auto-open on failure, and a
real back-and-forth tutor conversation (both directions confirmed in `chat_logs`) after
Anthropic credits were added -- the reply correctly asked a clarifying question rather than
guessing or leaking the answer, consistent with the system prompt's design.

**Tutor chat / bslib retrofit:** Module 2 needed several fixes not anticipated in earlier
planning -- see "Key conventions" above (BS5 theming, `*-error-check` chunks, the
setup-chunk-shared-function pattern for grading logic, and the deprecation of
`chat_mod_ui()`/`chat_mod_server()`). These apply to every future module that adds a tutor
chat panel or any other bslib component. Module 1 does not currently have a tutor chat panel,
so it isn't broken by any of this -- but if Module 1 later gets one retrofitted, it needs the
same BS5 setup.

**Next actions, in order:**
1. Confirm the "Start Over" freeze reported from RStudio's Viewer pane is resolved (or isolate
   it) -- see the gotcha above. Try an external browser first.
2. Modules 3-5 follow the same established pattern -- including the bslib/BS5 conventions
   above for any module that adds a tutor chat panel.
3. Instructor dashboard, once there's real attempt/chat data to build it against.
