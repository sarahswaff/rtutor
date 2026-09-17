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
Posit Connect Cloud (connect.posit.cloud), deploying directly from the GitHub repo
(sarahswaff/rtutor). The Free plan caps published apps at 5 (Basic is $19/mo for 25,
confirmed on the plans page) -- each piece of content is deployed as its own separate
"content" item, pointed at its own self-contained folder under `deploy/` (see "Current
status" below for why a separate, flattened `deploy/` copy exists per app rather than
deploying `tutorials/`/`instructor_dashboard/` directly). The student tutorial is
`deploy/course/` (Modules 1-5 merged into one app -- see "Merged course tutorial" below;
the original `deploy/module_1`...`module_5` still exist and still work but are slated for
retirement once `deploy/course/` is verified in production), and the instructor dashboard
is `deploy/instructor_dashboard/`. Each deployment needs its own copy of the relevant
`.Renviron` variables (`SUPABASE_DB_HOST`, `SUPABASE_DB_USER`, `SUPABASE_DB_PASSWORD`,
`ANTHROPIC_API_KEY` -- the dashboard doesn't need the last one) set in its own Connect
Cloud dashboard settings.
IMPORTANT: persistence lives in the external Postgres DB, never in local files -- this
matters even more on a redeployed/restarted Connect Cloud instance than it did during local
dev, since that filesystem is also ephemeral.

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
│   ├── course.Rmd      -- CURRENT deployment target: Modules 1-5 merged into one app
│   │                       (see "Merged course tutorial" below)
│   ├── module_1.Rmd    -- superseded by course.Rmd; kept for reference/rollback
│   ├── module_2.Rmd    -- superseded by course.Rmd; kept for reference/rollback
│   ├── module_3.Rmd    -- superseded by course.Rmd; kept for reference/rollback
│   ├── module_4.Rmd    -- superseded by course.Rmd; kept for reference/rollback
│   ├── module_5.Rmd    -- superseded by course.Rmd; kept for reference/rollback
│   └── media/           -- prepped, empty (see "Screenshots and screen recordings" below)
│       ├── images/
│       └── videos/
├── student_app/         -- not yet built
└── instructor_dashboard/ -- app.R, built and tested locally (see "Instructor dashboard")
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

## Curriculum (7 modules, finalized -- do not reorganize without reason)
1. **Introduction** -- install R/RStudio, panes, working directory. DONE, but see "Current
   status" below -- the install section was substantively rewritten from a passive fact-list
   into an actual guided step-by-step walkthrough and hasn't been re-verified live in a
   browser yet (module_1.Rmd).
2. **Basic Code** -- packages, console, comments, run provided code, error messages, help().
   DONE (module_2.Rmd).
3. **Data** -- hello world, data types, naming conventions, vectors, assignment, basic
   functions/comparisons, data structures, import, **turning a formula into code** (added
   later -- see "Current status" below for why). DONE (module_3.Rmd).
4. **Clean up** -- inspect, rename columns, index/subset, pipe, dplyr verbs
   (filter/select/mutate/arrange/group_by/summarize), handling NAs. DONE (module_4.Rmd) --
   built around a synthetic 10-row fish survey data set (`fish_survey`/`fish_clean`, two
   lakes, three species, deliberately messy column names and real NAs), 7 graded exercises.
5. **Actual Work** -- ggplot basics, markdown awareness (NOT authoring -- students just need
   to know it exists, it'll likely be provided to them), script save/import, file naming
   conventions (light touch on version control -- awareness only, not real git usage). DONE
   (module_5.Rmd) -- reuses the same `fish_clean` data from Module 4 for continuity, 4 graded
   ggplot exercises (scatter, bar from a dplyr summary, histogram, filtered+titled
   cumulative) plus quiz-only awareness content for everything else, since none of the
   file-naming/Markdown/version-control content involves writing new code.
6. **Interpreting Model Output** -- recognizing linear vs. curved relationships, reading
   R^2^ and RMSE, comparing two models' predictions. Added after Modules 1-5 (see "Current
   status" below). Deliberately does NOT involve building a model -- that's still out of
   scope for the tutorial itself (see below). DONE -- 2 graded exercises (compute RMSE;
   decide which of two models wins), each with its own tutor chat.
7. **Extra Practice** -- ungraded, endlessly-repeatable practice questions (see "Current
   status" below for the mechanism). NOT part of the graded curriculum sequence -- no
   `exercises` rows, no `exercise_attempts`/`chat_logs` logging, and deliberately not gated
   behind `progressive`/`allow_skip` (see the gotcha noted where it's built, in
   `tutorials/course.Rmd` just above `## Module 7: Extra Practice`). One shared, always-on
   tutor chat for the whole module (not per-question).

A capstone pipeline assessment exists but is explicitly OUT of scope for the tutorial itself
-- Module 6 teaches the vocabulary to interpret one's output, not how to build one. A
`pilot_testing/` folder (see "Current status" below) previews that capstone as a standalone
script run outside the app, for pilot-testing purposes only.

## Key conventions (established through real trial and error -- follow these)

**SUPERSEDED, read this before anything else in this section: Modules 1-3 no longer use
`learnr::question()` or `exercise=TRUE`/gradethis at all.** They were replaced with plain
Shiny (`quiz_question_ui()`/`quiz_question_server()` and `exercise_ui()`/`exercise_server()`
in `R/tutor_utils.R`) due to a serious, confirmed bug in learnr's own quiz/exercise
rendering -- see "Current status" below for the full story. Any guidance further down in
this section that references `question()`, `exercise=TRUE`, `grade_this()`, or gradethis
(the "*-error-check chunks", the bare-`___`-placeholder note, etc.) describes the OLD
pattern -- kept for historical/reference value, but do **not** follow it for Modules 4-5.
Use the same plain-Shiny pattern Modules 1-3 now use instead; see "Current status" for
exactly how.

**Exercise count and difficulty scale with the module, not a fixed count or fixed
minimalism.** Modules 1-2 landed on 1-2 exercises each because their content was mostly
conceptual (install steps, reading errors). That was right for those modules, not a target
to hold every later module to. As the curriculum gets more hands-on (Module 3 onward),
follow instead:
- A module introducing an actual code skill the student must produce or manipulate
  (not just a concept to recognize) generally earns its own graded exercise -- don't
  default that content to quiz-only just to keep the exercise count low.
- "Fix this" (given broken/incorrect code) and "make this output" (produce correct
  output from a near-blank starting point) are equally valid exercise formats -- pick
  whichever fits the skill, neither is the fallback/lesser option.
- Later exercises should grow more complex over time, including in raw lines of code
  (not necessarily linearly module-to-module) and by requiring previously-taught skills,
  not just the current module's new one -- code isn't standalone in practice, so
  exercises composing earlier skills (e.g. a Module 4 exercise also relying on Module 3's
  vector/assignment skills) are good design, not scope creep.
- Each module should include one **cumulative exercise** -- multi-step, requiring more
  than a single fix or single line of output, pulling together skills from that module
  (and ideally prior modules). This is in addition to, not instead of, the module's other
  more targeted per-skill exercises.

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

**This entire wiring is shared, not per-module.** `wire_tutor_chat(exercise_key, chat_id,
accordion_id, panel_value, input, output, session)` and
`log_attempt_and_maybe_open_chat(exercise_key, student_id, user_code, passed, message,
accordion_id, session)` live in `R/tutor_utils.R` and are used identically by every module
(Module 1's one exercise and both of Module 2's). Call `wire_tutor_chat()` once per exercise
from a `context="server"` chunk, passing that chunk's own `input`/`output`/`session` (it's a
plain function, not itself in the server closure, so it needs them explicitly). Only the
per-exercise *grading logic* (the `evaluate_<exercise>()` functions) is module-specific and
belongs in each module's own `setup` chunk -- see "gradethis check chunks" below.

**bslib/shinychat require Bootstrap 5, but learnr's tutorial template defaults to Bootstrap
3.** Any module using `bslib::accordion()`, `shinychat::chat_ui()`, or any other BS5-only
component MUST do both of the following, or the components silently fail to render (browser
console: "requires Bootstrap version 5 but this page is using version 3") with no error
surfaced to the student:
1. Add `theme: !expr bslib::bs_theme(version = 5, bootswatch = "cerulean")` under
   `learnr::tutorial:` in the YAML header (this affects pandoc's static template only).
2. Also call `` `r bs5_theme_dependencies()` `` (defined in `R/tutor_utils.R`) as the return
   value of a plain (non-`context="server"`) chunk placed inside the first `##` topic (NOT
   before the first heading -- content before any `##` heading renders in the wrong place in
   learnr's layout). This actually injects the BS5 JS/CSS dependencies into the live Shiny
   page; step 1 alone is not sufficient. Do NOT use `shiny::bootstrapLib()` for this --
   printed directly in a chunk it dumps its own function source as literal text onto the
   page; `bs_theme_dependencies()` wrapped in `tagList()` (what `bs5_theme_dependencies()`
   does) is the version that actually works.
Both Module 1 and Module 2 already do this -- any new module needs both steps too.

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

**Never use a bare `___` (or any run of underscores) as a fill-in-the-blank placeholder in
exercise starter code -- it is a genuine R syntax error, not just an undefined name.** As of
R 4.2, `_` is a reserved token (the native pipe placeholder, e.g. `x |> f(_)`), and an
identifier cannot start with `_` at all -- `parse(text = "x <- ___")` fails with `unexpected
input`, which routes the *untouched* exercise straight to the `*-error-check` chunk before a
student has done anything. Module 1's `"___"` placeholder is fine because it's inside string
quotes (plain text, not parsed as an identifier); a bare/unquoted blank in numeric or
identifier position needs a real placeholder token instead -- this project uses `FIXME`
(e.g. `apples <- FIXME`, `scores <- c(FIXME)`) starting in Module 3. Always sanity-check a
new placeholder with `parse(text = "...")` before assuming it's just "undefined until
filled in."

**ROOT-CAUSED and FIXED: learnr's local-filesystem progress cache was the real cause of
"Run Code/Submit Answer/Start Over stop responding" -- for BOTH Claude's testing sessions
AND the user's own local "Run Document" sessions, since they share the same machine/OS
user.** learnr's `tutorial.storage` option defaults to `"auto"`, which -- per
`learnr:::tutorial_storage()` -- checks whether the tutorial is being served on localhost;
if so (true for EVERY local dev/test session: `R/run_tutorial.R`, and RStudio's own "Run
Document" button, both bind to `127.0.0.1`), it persists every exercise submission and
section-viewed flag to disk in `.rds` files under
`<AppData>/R/learnr/tutorial/storage/<os-username>/<url-encoded-Rmd-directory-path>/
<tutorial-version>/`, keyed by OS username + Rmd folder path + exercise/section label --
NOT by browser, browser tab, cookies, localStorage, or IndexedDB (clearing any of those does
nothing). Consequences this caused, now understood: (1) any two local sessions for the same
module -- Claude testing module_3 while the user has module_3 open in RStudio, or even just
the user's own session from an hour ago -- read and write the *exact same* on-disk state,
so one session's submission, reset, or mid-edit state can silently "restore" into a totally
different session, which looks exactly like Run Code/Submit Answer/Start Over doing nothing
(the editor shows stale code/output no matter what you click) even though the app itself is
fine; (2) this is a **purely local artifact** -- learnr automatically switches to
`client_storage` (per-browser, not per-OS-user) for any non-localhost deployment, so real
students on the deployed app were never at risk from this, only local dev/testing was; (3)
the fix, now in place: `options(tutorial.storage = "none")` in the project's `.Rprofile`
(covers RStudio's "Run Document") and redundantly in `R/run_tutorial.R` (covers direct
`Rscript` invocation regardless of starting directory) -- this disables the local-filesystem
cache for every local session going forward, at the cost of nothing that matters locally
("resume where I left off across an R restart" during dev testing, which was actively
causing the bug it was a nicety for). If a *genuinely* fresh state is ever needed for some
other reason, the same cache still lives at
`AppData/Local/R/learnr/tutorial/storage/<username>/` and can be deleted directly.

Also note: a `grade_this({...})` result CANNOT be assigned to a variable in `setup` and
then referenced by name from multiple `*-check`/`*-error-check` chunks -- gradethis rewires
the enclosing environment per call site and reusing the same object across chunks throws
"Can't change the parent of a locked environment". Instead, put the actual grading
*logic* in a plain function (not a `grade_this()` object) in `setup`, and call `grade_this({...})`
fresh, inline, in each `*-check`/`*-error-check` chunk, delegating to that shared plain
function. See `evaluate_name_exercise()` in module_1.Rmd and `evaluate_comment_exercise()` /
`evaluate_fix_the_bug_exercise()` in module_2.Rmd for the per-module half of this pattern;
`log_attempt_and_maybe_open_chat()` itself is shared (see above).

**Tutor context assembly** (see `tutor_utils.R`): query the attempt count + most recent
attempt (code, pass/fail, gradethis message) + the exercise's `learning_objective`, and
build a dynamic context block. The LLM is NEVER given the actual correct solution/answer
key.

**REAL BUG, found via a real student conversation, now fixed: context used to only refresh
when the accordion opened, not on every message.** `start_tutor_chat()` bakes this context
block into the ellmer client's system prompt once, when `wire_tutor_chat()`'s
`refresh_chat()` runs -- which only happens when `input[[accordion_id]]` actually changes
(accordion closed->open). This chat is deliberately meant to stay usable while a student
keeps submitting without closing it ("before you submit, after a failed attempt, or even
after you've already passed" -- every module says this) -- so a student who submitted a
NEW attempt in an already-open chat got a tutor that kept describing their OLD attempt,
confusingly insisting a since-fixed, since-passed submission still had the original
problem. Confirmed as a real occurrence, not a hypothetical, from an actual student
transcript. **Fixed** by re-fetching `build_context_message()` immediately before EVERY
message (not just at chat-open) in `wire_tutor_chat()`'s user-input `observeEvent`, spliced
in as an extra content part of that turn (clearly labeled "SYSTEM CONTEXT UPDATE -- not
written by the student"), rather than rebuilding the whole client -- rebuilding the client
would silently discard the conversation history the system prompt explicitly asks the
model to reason over cumulatively, which would be a worse regression than the one being
fixed. Verified directly against the database (logged a failing attempt, captured the
context a chat-open would have baked in, then logged a passing attempt and confirmed the
next `build_context_message()` call -- what the fix now sends on the very next
message -- correctly reflects the new attempt count and PASSED state).

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

**Testing convention (as of Module 3 and onward): exercise "Start Over" must be tested at
every attempt stage, not just once.** Every learnr exercise chunk renders its own
Run Code / Submit Answer / Start Over button trio, and manual test passes must click all
three -- not just Submit Answer -- for every graded exercise in a module. Test Start Over
specifically in both of these states, not just from a fresh/untouched exercise: (1) after a
*failing* submitted attempt, and (2) after a *passing* submitted attempt. Confirm in each
case that it actually resets the code editor to the exercise's starting code, and that
`exercise_attempts` logging and tutor-chat auto-open state behave sanely afterward (e.g. a
new attempt post-reset still logs correctly and doesn't double-open or break the chat
accordion). Buttons silently not responding was previously reported as unreproduced and is
now root-caused and fixed (see the `tutorial.storage` gotcha above, and the environment
gotcha below) -- so it's not purely a UX nicety.

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
- **RESOLVED: "Run Document" (or any local session) going unresponsive on Run Code/Submit
  Answer/Start Over, with no error.** Originally reported as unreproduced; later genuinely
  hit again and properly root-caused -- see the `tutorial.storage` gotcha under "Key
  conventions" above for the full mechanism (learnr's local-filesystem progress cache, shared
  by every localhost session under the same OS user, including two different sessions -- e.g.
  Claude testing a module while the user has "Run Document" open on the same one -- silently
  stepping on each other's state). Fixed via `options(tutorial.storage = "none")` in both
  `.Rprofile` (covers "Run Document") and `R/run_tutorial.R` (covers direct `Rscript`
  invocation). The earlier `connect_timeout = 10` hardening in `get_con()` (guarding against a
  hung Postgres connection freezing the single-threaded Shiny process) is unrelated to this
  specific bug but remains in place as legitimate hardening regardless.

## Deliberate scope decisions -- don't relitigate without a real reason
- No password auth for students. Identified by name + email only; roster-CSV matching is
  planned but NOT YET BUILT (deferred on purpose -- the identity table is designed to make
  this a drop-in addition later). The instructor dashboard is different -- see below -- it
  DOES have a password gate, because it exposes every student's real data.
- No Canvas LTI integration yet. A lightweight roster-CSV approach is planned instead; full
  LTI SSO/gradebook integration is deferred to a later phase pending institutional approval.
- Every exercise attempt is logged as its own row (explicitly chosen over update-in-place).

## Instructor dashboard (`instructor_dashboard/app.R`)
Built once Modules 1-5 had real attempt data in Supabase to build against (85 students, all
5 modules represented, at build time). A plain Shiny app (not learnr) -- three tabs:
- **Overview** -- class-wide stat cards (student count, active-in-7-days, avg. exercises
  passed, overall pass rate), a pass-rate-by-exercise bar chart (`ggplot2`, colored by
  module), and a module-completion summary table (how many students passed every exercise
  in each module).
- **Roster** -- one row per student: first login, last active, exercises passed/attempted
  (sortable/searchable `DT` table).
- **Needs attention** -- students with 3+ attempts on some exercise who still haven't passed
  it, per `exercise_mastery`. Threshold is a function argument
  (`get_struggling_students(con, min_attempts = 3)`), not hardcoded in the query.

All four query functions (`get_roster_summary()`, `get_module_completion()`,
`get_exercise_stats()`, `get_struggling_students()`) live in `R/db_utils.R`, not the app
itself -- same "one shared place for SQL" rationale as everything else in that file.

**Gotcha that cost real debugging time and will resurface in any future dashboard query:**
`RPostgres` returns every Postgres `bigint` (i.e. the result of any `COUNT(...)`) as
`bit64::integer64`, not a plain R integer. `mean()` and other ordinary arithmetic on an
`integer64` column silently produce a wrong answer with no error or warning (observed:
`mean()` of a real, correct `integer64` column returning `0` instead of ~0.4) -- this is
NOT the same failure mode as a normal type error, so it's easy to ship without noticing.
Every one of the four query functions above pipes its result through `fix_int64_cols()`
(also in `db_utils.R`), which converts every `integer64` column back to plain `integer`
right after the query. **Any new dashboard query added later must do the same** -- wrap the
`dbGetQuery()` call in `fix_int64_cols()` before returning.

**Auth:** a hand-rolled password gate (`check_password()` in `app.R`), not a package
(`shinymanager` was considered and rejected -- unnecessary dependency for a single shared
password, and inconsistent with this project's existing preference for plain Shiny over
extra UI-framework packages, per the `learnr::question()`/gradethis rewrite above). Reads
the expected password from a new `.Renviron`/Connect-Cloud-dashboard variable,
`DASHBOARD_PASSWORD` -- this is a FIFTH env var beyond the four listed under "Deployment
target" above, needed only by the dashboard's own Connect Cloud content item (not the
tutorial modules). Not real per-instructor auth (no accounts, no audit log of who viewed
what) -- acceptable for a single-instructor course; would need real auth before handing
dashboard access to multiple people.

**Local testing:** `Rscript R/run_dashboard.R` (mirrors `R/run_tutorial.R` -- calls
`readRenviron()` on the project-root `.Renviron` before `setwd()`-ing into
`instructor_dashboard/`, since R only auto-loads `.Renviron` from the process's original
working directory). Serves on `http://127.0.0.1:7413`.

**Verified locally against real production data** (85 students, all 5 modules): login
gate (correct password succeeds, wrong password shows an inline error and does not log in),
all three tabs render with correct values cross-checked against direct SQL, and the
"Refresh data" button re-queries. DT tables can render visually blank on the FIRST paint of
a `bslib::nav_panel` tab that starts hidden (a live Bootstrap-tab/DT initial-width quirk --
the data is present in the DOM, just not laid out yet); it self-corrects on the next redraw
and was not treated as a bug to fix, since normal user interaction (scrolling, resizing,
switching tabs again) is enough to trigger it. Not yet deployed to Connect Cloud, and not
yet confirmed against a real instructor's actual workflow/questions in practice.

**Deployment infrastructure added, following the exact Modules 1-5 pattern:**
`deploy/instructor_dashboard/` is a flattened, self-contained copy (`app.R` at the folder
root, `R/db_utils.R` alongside it, `source("R/db_utils.R")` instead of
`source("../R/db_utils.R")`) with a generated `manifest.json`
(`rsconnect::writeManifest(appDir = "deploy/instructor_dashboard", appPrimaryDoc = "app.R")`,
confirmed `appmode: "shiny"`). Regenerate the same way any time `instructor_dashboard/app.R`
or `R/db_utils.R` changes. Still needed: create the Connect Cloud content item and set its
env vars in its own dashboard settings -- the three `SUPABASE_DB_*` vars (the dashboard
only reads the DB, never writes) plus the new `DASHBOARD_PASSWORD`. `ANTHROPIC_API_KEY` is
not needed here; the dashboard never calls `tutor_utils.R`.

### Chat categorization + transcript viewer (added later, a 4th "Chats" tab)
The instructor wanted visibility into *what students are actually asking the tutor*, not
just pass/fail stats -- this adds that as a 4th dashboard tab, with two parts: a bar chart
of student messages grouped by help-type, and a browsable per-student/per-exercise
transcript viewer.

**Categorization is lazy and offline by design, chosen explicitly over real-time
classification when asked.** `chat_logs` got one new nullable column,
`help_category` (see `schema.sql` -- a `CHECK` constraint restricts it to the fixed list in
`HELP_CATEGORIES`, `R/db_utils.R`: `syntax_error`, `conceptual_confusion`, `how_do_i_start`,
`wants_answer`, `environment_setup`, `other`). NULL means "not yet classified." A brand new
standalone script, **`R/classify_chat_messages.R`**, is the only thing that ever writes to
that column -- it is NOT part of either live app (`course.Rmd` or
`instructor_dashboard/app.R`), so this feature required zero changes and zero redeploy risk
to the live student-facing tutorial. Run it by hand (`Rscript R/classify_chat_messages.R`)
whenever you want fresh categories before checking the dashboard; new messages just sit as
"uncategorized" in the meantime, which the dashboard's chart shows as its own bucket rather
than hiding. It batches up to 20 uncategorized student messages per Anthropic call (cheap at
this project's scale, and avoids one API call per message as chat volume grows), asks for a
JSON array of categories back, and strips a markdown code fence if the model wraps its
answer in one (it did, every time, despite being told "JSON only, no other text" -- don't
assume a plain `jsonlite::fromJSON()` call on the raw reply will work without that strip).

Four new query functions in `R/db_utils.R`, same "one shared place for SQL" rationale as
everything else there: `get_help_category_breakdown()`, `get_students_with_chats()`,
`get_chatted_exercises_for_student()`, `get_chat_transcript()`.

**Real bug caught during testing**: `get_chatted_exercises_for_student()`'s original query
used `SELECT DISTINCT ... ORDER BY e.order_index` without `e.order_index` in the `SELECT`
list -- Postgres rejects this outright (`ORDER BY expressions must appear in select list`
for `SELECT DISTINCT`), a real, immediate query error, not a subtle logic bug. Fixed by
adding `e.order_index` to the `SELECT DISTINCT` list.

**The two new `selectInput()`s (student picker, exercise picker) explicitly pass
`selectize = FALSE`.** Shiny's default selectize.js-enhanced dropdown didn't respond to
scripted interaction the same way the project's existing plain inputs (radio buttons, text
areas, buttons) always have -- consistent with this project's now-repeated experience
(the whole `learnr::question()` rewrite, and `shinychat`'s chat input) that JS-enhanced
widgets are harder to drive reliably than plain native form elements. Plain `<select>`
elements are simpler, more accessible, and were the deliberate choice here for the same
reason plain Shiny inputs replaced learnr's dynamic quiz/exercise UI -- not just a testing
convenience.

**Also fixed**: the student-picker's populating `observe()` block didn't pass `selected =`
to `updateSelectInput()`, so clicking "Refresh data" silently reset the currently-selected
student/exercise back to the placeholder every time. Now passes
`selected = input$chat_student` to preserve the instructor's place across a refresh.

**Verified locally**: all four new query functions directly against real production data
(one transcript in particular showed a genuine 3-turn exchange where the tutor correctly
guided a student through a `rename()` mistake without ever giving the column-name answer
outright -- a nice incidental confirmation the system prompt design still holds up); the
"Chats" tab's category chart, student picker, exercise picker (correctly narrows to only
that student's actual chat history), and full transcript render, all against real data, in
a real browser. Same `bslib::nav_panel` first-paint-blank quirk noted above applies to this
tab's chart/transcript on first load -- self-corrects the same way, not a new bug.
**Not yet deployed to Connect Cloud** -- needs `deploy/instructor_dashboard/` regenerated
and redeployed (schema migration already applied directly to the live Supabase DB, so no
DB-side work is needed on deploy, just the app code).

## Merged course tutorial (`tutorials/course.Rmd`)
Posit Connect Cloud's Free plan caps published apps at 5 -- confirmed live on the plans
page (connect.posit.cloud/plans): Free = 5 applications, Basic ($19/mo) = 25, Enhanced
($59/mo) = unlimited. Modules 1-5, each deployed as its own content item, already used all
5 free slots, which is what blocked deploying the instructor dashboard as a 6th app. Rather
than pay for Basic, Modules 1-5 were merged into a single learnr document,
`tutorials/course.Rmd`, deployed as ONE Connect Cloud app -- freeing 4 slots permanently (1
course + 1 dashboard = 2 used, 3 spare). The original `tutorials/module_1.Rmd`...
`module_5.Rmd` and their `deploy/module_1`...`module_5` folders are kept as-is (rollback
safety / historical reference), not deleted.

**This was a mechanical merge of already-tested content, not a rewrite** -- every quiz's
choices/feedback, every exercise's starting code and `evaluate_*()` grading logic, and the
tutor chat system prompt are byte-for-byte unchanged from the per-module originals. What
had to change, and why:
- **Every `##` Topic heading is prefixed with its module** (`## Module 3: Vectors`, etc.).
  Needed for two reasons: modules 2-5 all originally titled their first topic literally
  `## Welcome back` (4 identical heading strings, which pandoc would auto-suffix but still
  read confusingly in one combined sidebar), and a ~44-topic single sidebar with no module
  labels would be very hard for a student to navigate. `###` sub-headings are untouched.
- **`tutor_chat_N`/`tutor_accordion_N` are renumbered per module** as
  `tutor_chat_m{module}_{i}` / `tutor_accordion_m{module}_{i}` (e.g. module 4's third
  exercise: `tutor_chat_m4_3`/`tutor_accordion_m4_3`). Every module used to restart this
  numbering at `_1`, which is harmless across 5 separate deployments but is a real Shiny
  ID collision (up to 5-way) once concatenated into one page/session.
- **The two `cumulative_exercise` collisions are renamed to be module-specific**:
  module_3's exercise UI ID and its `evaluate_cumulative_exercise()` function became
  `module3_cumulative_exercise` / `evaluate_module3_cumulative_exercise`; module_4's became
  `module4_cumulative_exercise` / `evaluate_module4_cumulative_exercise`. These were the
  only exercise/quiz ID and only `evaluate_*()` function name that collided across all 5
  modules -- everything else was already unique.
- **Only ONE identity-capture modal remains** (module 1's "Welcome!" wording, at the very
  top), not 5 near-identical copies -- they all used the same unnamespaced
  `student_name`/`submit_name` input IDs, so 5 concatenated copies would have multi-fired
  one button click. `bs5_theme_dependencies()` is likewise called exactly once (module 1's
  call; the other 4 were deleted), since it's a document-wide dependency injection, not a
  per-module one.
- **`fish_survey`/`fish_clean` are now built once, in module 4's setup chunk, and reused
  by module 5** (which used to rebuild its own separate copy of `fish_clean` from scratch,
  back when each module was an independent deployment with no way to share module 4's
  actual object). Both `assign(..., envir = globalenv())`'d; module 5's redundant
  reconstruction was deleted outright, not merely deduplicated -- it's the same data,
  constructed identically, so there was nothing left to preserve.
- **Each module's `setup`-labeled chunk was renamed to a unique label** (`setup-module1`
  ... `setup-module5`, since knitr errors on duplicate chunk labels in one document) **and
  given an explicit `context="setup"` attribute.** This is the one non-obvious gotcha that
  actually broke the first working version of this merge, silently: shiny_prerendered's
  special "runs once per session, before every other server chunk, and stays in scope for
  all of them" behavior is tied to the chunk being named *exactly* `setup` -- renaming it to
  `setup-module2` etc. without ALSO adding `context="setup"` explicitly causes that chunk to
  fall back to the default `context="render"` (knit-time only), so every function it defines
  (`evaluate_*()`, `mapping_label()`) and every object it creates (`fish_survey`,
  `fish_clean`) silently vanishes by the time a live session's exercise-submit code tries to
  call it -- caught locally as `Error in evaluate_name_exercise: could not find function
  "evaluate_name_exercise"` the first time an exercise was submitted, not at render/knit
  time, which is what made it non-obvious. Confirmed fixed by checking the rendered HTML's
  `data-context` attributes (`context="setup"` chunks show up as `data-context="server-start"`
  -- the correct, once-per-session-before-other-server-chunks semantic). **Any future chunk
  that needs to behave like a `setup` chunk but can't literally be named `setup` (i.e., any
  chunk after the first in a multi-module document like this one) needs `context="setup"`
  stated explicitly -- the bare name is not enough.**

**New feature added as part of this merge: a "welcome back" progress banner**, since one
continuous course makes "where do I pick back up" a real question in a way 5 separate
per-module links never were. `get_student_progress(con, student_id)` (`R/db_utils.R`,
same file/rationale as the dashboard queries) returns exercises passed + the title of the
first module (in module/exercise order) that isn't fully passed yet. Rendered as a plain
`uiOutput("welcome_back_banner")` in Module 1's Welcome topic, computed inside the single
identity-capture `observeEvent`, right after `get_or_create_student()` succeeds and before
`dbDisconnect()`. A brand-new student (0 exercises passed) sees no banner -- identical to
today's experience. **Deliberately NOT an automatic jump/scroll to that module** -- the
banner just names it in plain text ("Pick up in Module 3: Data using the sidebar on the
left") and the student clicks the real, unmodified sidebar themselves. This was a
considered choice, not a shortcut: `learnr`'s Topic sidebar is a hand-rolled JS closure with
no exported/internal R-level navigation API and no `receiveMessage` hook on its one Shiny
input binding (confirmed by reading the installed `learnr` package's own JS and R
namespace) -- the only way to auto-navigate would be injecting JS to synthetically click a
sidebar link, which is the same class of undocumented-client-internals dependency that
caused the original `learnr::question()`/`exercise=TRUE` rewrite (see "Current status"
below). `options(tutorial.storage = ...)` was also considered and rejected for the same
underlying reason: that setting only restores learnr's own native question/exercise state,
which this project abandoned project-wide already, and it's browser-bound rather than
identity-bound, which fights this project's actual DB-backed, name-based identity model.

**A real, deliberate behavior change from merging:** students can now freely navigate to
any module's Topics from the sidebar, including ones "ahead" of where they've actually
gotten to -- previously, a student could only reach module N by having that module's own
separate URL. Building a real hard gate across modules would require the same
undocumented-sidebar-manipulation approach just ruled out for navigation above, so this was
accepted rather than worked around: this is a self-paced pre-course-prep tool (per this
file's stated Purpose), not a certification path, and a curious/ahead student previewing or
revisiting content isn't a real problem worth that risk.

**Verified locally end-to-end after the fix above** (`Rscript R/run_tutorial.R`, pointed at
`course.Rmd`): identity modal appears exactly once; a brand-new student sees no welcome-back
banner while a student with prior `exercise_mastery` rows sees the correct passed-count and
correct next-module name; Module 1's exercise (fail -> tutor chat auto-open -> pass ->
Start Over all confirmed), Module 2's `fix_the_bug_exercise`, Module 3's renamed cumulative
exercise (error path, fail path, and pass path, confirming
`evaluate_module3_cumulative_exercise` resolves correctly), Module 4's renamed cumulative
exercise (confirming `fish_clean`/`dplyr` both resolve correctly via the session-start
context), and Module 5's ggplot quiz + scatter exercise (confirming `fish_clean` correctly
carries over from Module 4's setup chunk with no module-5-local reconstruction, and
`has_plot_output` plot rendering still works). Cross-checked directly against
`exercise_attempts` in Supabase afterward -- every test attempt logged against the correct
`exercise_key`, in the correct pass/fail state, in the correct order.

**Deployed to Connect Cloud and confirmed working in production**: `deploy/course/` and
`deploy/instructor_dashboard/` are both live content items. A real session against the
deployed `course.Rmd` app logged a failed then a passing `module1_name_check` attempt to
Supabase, checked directly against `exercise_attempts`. The 5 old per-module Connect Cloud
deployments have been retired (removed from Connect Cloud only -- their source files,
`tutorials/module_1.Rmd`...`module_5.Rmd` and `deploy/module_1`...`module_5`, are
deliberately kept in the repo as reference/rollback, not deleted).

`deploy/course/` is a flattened, self-contained copy (`course.Rmd` at the folder root,
`R/db_utils.R` and `R/tutor_utils.R` alongside it, `source("R/...")` not `source("../R/...")`)
with a generated `manifest.json`
(`rsconnect::writeManifest(appDir = "deploy/course", appPrimaryDoc = "course.Rmd")`,
confirmed `appmode: "rmd-shiny"`, primary doc `course.Rmd`). **Regenerate the same way any
time `tutorials/course.Rmd`, `R/db_utils.R`, or `R/tutor_utils.R` changes, and redeploy on
Connect Cloud** -- a git push alone does not update the live app.

### Install-section tutor chat (added after the merge)
Module 1's "Installing R and RStudio" topic (and its three `###` sub-steps) originally had
no tutor chat at all -- only the very last topic in Module 1 ("Quick system check") had
one. Since installation is the one part of this course that genuinely depends on the
student's own computer (OS, chip architecture, permission prompts) and the tutorial
explicitly can't see any of that, a chat panel was added there too.

It intentionally does NOT reuse `wire_tutor_chat()` -- every existing tutor chat is tied to
a real row in the `exercises` table (used for both `chat_logs`' `NOT NULL` FK and for
building the AI's context: title, learning objective, attempt history), and installation
isn't a graded exercise. Rather than add a schema flag to mark a non-graded "exercise" row
(considered, and the more "correct" long-term design, but more invasive), this uses a new,
simpler function: **`wire_standalone_chat()`** (`R/tutor_utils.R`) -- same refresh-on-open
mechanism as `wire_tutor_chat()` (a fresh `ellmer` client per accordion open), but with NO
`student_id`, NO `exercise_key`, and NO `chat_logs`/`exercise_attempts` writes at all.
**Consequence: these conversations are NOT logged anywhere and will NOT show up in the
instructor dashboard's future chat-transcript feature** -- a deliberate tradeoff (this was
explicitly the option chosen over the schema-flag approach when asked), not an oversight.
Also has its own short, narrower system prompt (`INSTALL_HELP_SYSTEM_PROMPT`) instead of
`TUTOR_SYSTEM_PROMPT`, since the latter is written entirely around "stuck on a graded
exercise" framing (attempt-count escalation, not leaking an answer, grader feedback) that
doesn't apply to install troubleshooting.

**Verification note:** confirmed locally that the panel renders in the right place, opens
on click, and shows its distinct greeting, with no server-side errors. Actually sending a
message and getting an AI reply could NOT be confirmed through automated browser testing --
attempting the same interaction against an already-proven, pre-existing tutor chat (Module
1's "Quick system check") showed the identical symptom (no message appears, no reply),
which points to a browser-automation limitation with `shinychat`'s custom chat input widget
rather than a defect in this code (this project's own history already notes that real
tutor conversations were originally confirmed by a human typing in an actual browser, not
via automated testing). **A human should confirm this one manually in a real browser**
before considering it fully done.

## Screenshots and screen recordings (planned, not started)
**Deliberately sequenced AFTER the pilot, not before or during it** -- see "Current status"
below. Rather than deciding up front whether this is worth the effort, or assuming it's only
relevant to Module 1, `pilot_testing/checkpoints_and_feedback.md` directly asks real testers
whether a screenshot, clip, or any other visual would have helped **anywhere in the
course**, plus an open-ended "anything else visual that would have helped" -- so the
decision (and its scope) is based on actual signal, not a guess about where it matters.

Idea: add real screenshots and short screen recordings to `course.Rmd` for the one part of
the course that has no live code output to speak for itself -- Module 1's "Installing R and
RStudio" and "The RStudio panes" -- plus later, wherever seeing code actually run (not just
reading about it) would help more than text alone.

**Sourcing must be the user's own screen captures, not third-party images.** Pulling an
existing screenshot from someone else's site was explored and abandoned: Claude's browser
tool can *view* a live page but has no way to save that view as a file (confirmed by
testing -- nothing appears on disk after a screenshot action), and the one plausible
freely-licensed alternative found on Wikimedia Commons ("RStudio IDE screenshot.png", CC
BY-SA 4.0) turned out to be flagged by Commons itself as having disputed copyright status
(RStudio's own AGPLv3 licensing may mean a screenshot of its UI isn't the uploader's to
freely relicense) -- filed under Commons' own "Items with disputed copyright information."
Self-captured screenshots/recordings of the user's own RStudio session sidestep this
entirely: that's the user's own original capture, not a reproduction of someone else's
published work, regardless of RStudio the application being copyrighted.

**Prepped so far:**
- `tutorials/media/images/` and `tutorials/media/videos/` -- empty, ready for real files.
- Suggested formats: PNG for static screenshots (CRAN/RStudio download pages, pane
  layout); GIF for short silent clips (embeds directly via plain Markdown image syntax,
  no video player/HTML needed -- ideal for something like "here's how you run a line of
  code"); MP4 only if a clip genuinely needs to be longer than a GIF comfortably allows.
- Software (all free/open-source or already installed -- no paid tools needed for this):
  - **ShareX** (Windows, free/open-source) -- screenshots with annotation (arrows,
    highlighting, blur) plus short GIF/video capture, covers most of this in one tool.
  - **ScreenToGif** (Windows, free/open-source) -- dedicated short animated-GIF recorder,
    good specifically for brief "watch this run" clips.
  - **OBS Studio** (free/open-source, cross-platform) -- for a longer/full-quality video
    recording if a GIF isn't enough.
  - **Xbox Game Bar** (`Win+G`, already built into Windows) -- zero-install MP4 screen
    recording, the simplest option if nothing fancier is needed.
  - Windows' built-in Snipping Tool / Snip & Sketch is fine for plain screenshots; ShareX
    only adds value once arrows/highlighting/blur are wanted.

**Still to do when this is picked back up:**
- Actually capture the images/clips (user's own screen, their call on OS/theme/setup shown).
- Embed them in `tutorials/course.Rmd` at the relevant spots (Markdown image syntax for
  PNG/GIF; an HTML5 `<video>` tag for MP4).
- Sync `tutorials/media/` into `deploy/course/media/` (the existing flattened-deploy-copy
  step doesn't currently include it, since there was nothing to copy yet) and confirm
  `rsconnect::writeManifest()` picks up the new files before the next deploy.
- Be ready to pull anything back out if it doesn't actually help teaching/learning -- this
  was an explicit condition going in, not just a nice-to-have.


## Current status / immediate next step

**RESOLVED: the "quiz questions and exercise buttons don't work" bug that dominated most of
this project's debugging history is fixed, via a rewrite, not a patch.** Root cause: a
client-side interaction-binding bug in `learnr`'s own dynamic quiz/exercise UI
(`learnr::question()` and `exercise=TRUE`/gradethis) -- confirmed, via a wire-level Shiny
trace against a real deployed server (see `debug_recalculating_bug/HANDOFF.md` for the full
investigation), that the server always renders and sends the right content correctly, the
browser displays it correctly, but the client-side step that's supposed to make freshly
inserted content clickable never takes effect, in every real user browser tested (Chrome,
Edge; both localhost and a real Posit Connect Cloud deployment) -- and never in the
automated testing harness used throughout most of this investigation, which is why it went
undiagnosed for so long. Multiple attempted server-side patches (`unstick_hidden_outputs()`
and others) genuinely fixed what they targeted but did not fix this, because the real bug is
one layer further down the pipeline (client-side input binding), not anything server-side.

**The fix:** Modules 1-3 no longer use `learnr::question()` or `exercise=TRUE`/gradethis at
all. Both were replaced with plain, statically-declared Shiny inputs
(`radioButtons()`/`actionButton()`/`textAreaInput()`), which only need Shiny's normal
one-time page-load binding -- the same mechanism the identity modal's `textInput`/
`actionButton` had relied on the entire time without ever failing, which was the concrete
clue that motivated this approach. Shared helpers live in `R/tutor_utils.R`:
- `quiz_question_ui()`/`quiz_question_server()` -- replaces `question()`. Takes a named
  `choices` vector (label -> internal ID) and a `feedback` list (ID -> `list(correct=,
  message=)`).
- `exercise_ui()`/`exercise_server()` -- replaces an `exercise=TRUE` chunk plus its
  `*-check`/`*-error-check` gradethis chunks. A plain `textAreaInput()` stands in for
  learnr's ace.js code editor (a deliberate simplification, not a general-purpose editor
  replacement -- fine for this course's short exercises). Evaluates the submitted code via
  `eval(parse(text = user_code), envir = new.env())` in a fresh environment, so grading
  logic can inspect intermediate variables the student created (not just the final printed
  value -- needed for Module 3's cumulative exercise, which checks that `prices`/`tax_rate`
  exist) and so genuine syntax errors are caught the same way a real R console would show
  them. `evaluate_fn` is always called as `(user_code, result, envir, stage)`; each module's
  existing `evaluate_*()` grading functions are unchanged, just wrapped in a small inline
  closure matching that fixed signature (they each had a different, narrower signature
  before). DB logging (`log_attempt_and_maybe_open_chat()`) and tutor chat wiring
  (`wire_tutor_chat()`) are completely unchanged -- only how the UI is declared and grading
  is invoked changed, not the grading logic, DB schema, or tutor chat behavior itself.

`unstick_hidden_outputs()` is kept in every module (harmless, still relevant: the quiz/
exercise *feedback* messages are still ordinary `renderUI()` outputs, which remain subject
to the separate suspend-while-hidden mechanism this function works around).
`warm_up_exercise_renderer()` was removed from Modules 1-3 along with gradethis, since
nothing left in those modules uses `learnr:::render_exercise()` anymore.

**Verified end-to-end for all three modules**, both locally and on a real deployment
(Posit Connect Cloud -- see "Deployment target" below, now updated): identity capture (incl.
a real DB-connection-failure error path, see below), every quiz question, every exercise's
fail/error/pass/Start-Over paths (including Module 3's cumulative exercise, which
deliberately starts from genuinely malformed R syntax), tutor chat auto-open-on-fail, and
real Postgres attempt logging with no errors in the server console. Confirmed by the app
owner directly, in their own real browser, on the deployed module 1 app, before modules 2-3
were rewritten the same way.

**Also fixed along the way: the identity-capture `observeEvent` had no error handling**,
so any DB connection failure (bad/missing env vars, network issue) threw uncaught and
crashed the entire Shiny session -- surfaced to the student as a bare "disconnected from
server" with zero indication of the actual cause. This is exactly what happened on the
first Connect Cloud deploy attempt (env vars hadn't propagated yet). Now wrapped in
`tryCatch()`, showing the real error message in a modal with a "Try again" button instead.

**Deployment infrastructure added:** `deploy/module_1/`, `deploy/module_2/`,
`deploy/module_3/` are self-contained, flattened copies of each module (`.Rmd` at the
folder root, `R/` subfolder alongside it, `source("R/...")` instead of `source("../R/...")`)
with a generated `manifest.json` each, specifically for Posit Connect Cloud deployment.
**Why the flattening was necessary:** `rsconnect::writeManifest()`'s app-type
auto-detection (`inferAppMode()`) only scans files at the app directory's *root* -- an
`.Rmd` nested in a `tutorials/` subfolder (matching this project's normal layout) is
invisible to it and falls through to `appmode: "static"`, which Connect Cloud will not even
offer as a primary-file candidate. **These `deploy/` copies must be regenerated any time the
corresponding `tutorials/*.Rmd` or `R/*.R` file changes** -- they are not symlinks, they're
plain copies with one line difference (`source()` path). Regenerate via
`rsconnect::writeManifest(appDir = "deploy/module_N", appPrimaryDoc = "module_N.Rmd")`
after copying the updated files in (see recent commit history for the exact copy+sed
pattern used). Each Connect Cloud deployment needs its own copies of the four `.Renviron`
variables (`SUPABASE_DB_HOST`, `SUPABASE_DB_USER`, `SUPABASE_DB_PASSWORD`,
`ANTHROPIC_API_KEY`) set in its own dashboard settings -- they are deliberately not in git
and don't propagate from `.Renviron` automatically.

**Diagnostic artifacts** (`debug_recalculating_bug/`) are kept as a full record of the
investigation (the false leads, the wire-trace methodology, the eventual root-cause finding)
but are no longer relevant to ongoing work -- the bug they document is fixed by the
architectural change above, not by anything in that folder.

Modules 1-3 are all fully built and tested end-to-end, in the same content style: identity
capture -> instructional/quiz content -> gated exercise(s), each backed by an
always-available tutor chat panel that auto-opens on a failed attempt. Module 1's one
exercise (`module1_name_check`), Module 2's two (`module2_comment_out`, `module2_fix_error`),
and Module 3's four (`module3_assignment`, `module3_vectors`, `module3_fix_comparison`,
`module3_cumulative` -- the first module built under the exercise-scaling convention below,
including its first cumulative exercise) all share the same wiring --
`wire_tutor_chat()`, `log_attempt_and_maybe_open_chat()`, `bs5_theme_dependencies()`,
`quiz_question_ui()`/`quiz_question_server()`, `exercise_ui()`/`exercise_server()` all live
once in `R/tutor_utils.R`; only each exercise's own `evaluate_<exercise>()` grading logic
and each quiz's own choices/feedback text differ per module. `exercises.learning_objective`
is set for all seven exercise rows in Supabase.

A real back-and-forth tutor conversation has been verified for all five modules (both
directions confirmed in `chat_logs`) -- responses correctly reference the student's actual
submission, give guiding next steps without leaking answers, and build on the student's own
follow-ups, consistent with the system prompt's escalation/non-leaking design. The tutor
chat greeting (`TUTOR_CHAT_GREETING`, pushed via `chat_set_greeting()` after every
`chat_clear()` in `wire_tutor_chat()`'s `refresh_chat()`) is confirmed working on every
module.

Module 1's "Installing R and RStudio" section is a real guided walkthrough (three `###`
steps -- install R, install RStudio, verify via `2 + 2` in the Console -- each with its own
checkpoint quiz), not a passive fact list.

**Modules 4-5 are built and tested end-to-end** (locally: identity capture, every quiz,
every exercise's fail/error/pass/Start-Over paths, tutor chat auto-open-on-fail, a real
tutor conversation confirmed in both directions via `chat_logs`, and `exercise_attempts`
logging). Two things came up building them that are now established conventions for any
future module:

- **A module's exercises can't just reference a data object defined in the `setup` chunk --
  it has to be explicitly placed in `.GlobalEnv`.** `exercise_server()` evaluates submitted
  code via `eval(parse(text = user_code), envir = new.env())`; that environment's parent
  chain resolves through wherever `exercise_server()` itself was `source()`'d (which is
  `.GlobalEnv`, since `source()` defaults to `local = FALSE`), NOT through the `setup`
  chunk's own local execution environment. Modules 1-3 never hit this because their
  exercises only ever built self-contained vectors from scratch; Module 4 is the first to
  need a shared reference data set (`fish_survey`/`fish_clean`), so its `setup` chunk ends
  with `assign("fish_clean", fish_clean, envir = globalenv())` (and the same for
  `fish_survey`). Safe to do for static, read-only reference data that's the same for every
  session. Module 5 recreates its own copy of `fish_clean` the same way (each module is a
  separate deployment -- no state is shared across modules in production).
- **`exercise_ui()`/`exercise_server()` gained an opt-in `has_plot_output` argument** (see
  `R/tutor_utils.R`) for exercises whose result is a `ggplot` object. The normal feedback
  path (`capture.output(print(result))`) is fine for the vectors/data frames every other
  module's exercises return, but `print.ggplot()`'s real job is drawing to a graphics
  device, not producing useful text -- so a plotting exercise needs `has_plot_output = TRUE`
  (both in the `exercise_ui()` call in the document body and the matching `exercise_server()`
  call), which adds a `plotOutput()`/`renderPlot()` area instead. Defaults to `FALSE`, so
  every existing module's calls are completely unaffected -- confirmed via a parse/formals
  smoke test after the change (a full manual re-test of Modules 1-3 was not run, but the
  change is purely additive and low-risk).

**Next actions, in order:**
1. DONE: Modules 4 and 5 are deployed to Connect Cloud.
2. DONE: Instructor dashboard built and tested locally (see "Instructor dashboard" above).
3. DONE: Modules 1-5 merged into one tutorial, `tutorials/course.Rmd` (see "Merged course
   tutorial" above), to free up Connect Cloud app slots for the dashboard. Verified locally
   end-to-end. `R/run_tutorial.R`'s `MODULE_FILE` now defaults to `"course.Rmd"`.
4. DONE: `deploy/course/` and `deploy/instructor_dashboard/` are both published to Connect
   Cloud as their own content items. Confirmed genuinely working in production, not just
   loading -- a real session against the deployed `course.Rmd` app logged a failed then a
   passing `module1_name_check` attempt to Supabase (checked directly against
   `exercise_attempts`).
5. DONE: the 5 old per-module Connect Cloud deployments have been retired -- `course.Rmd`
   is the only student-facing app now live. (Their source files are still in the repo on
   purpose, per "Merged course tutorial" above.)
6. DONE: added a standalone tutor chat to Module 1's "Installing R and RStudio" section
   (see "Install-section tutor chat" above), and `course.Rmd` has been redeployed to
   Connect Cloud with it. Still needs one manual check: a real human sending it a message
   and confirming the AI actually replies -- this could not be confirmed via automated
   testing (see that section for why).
7. DONE: chat transcript viewer + help-type categorization added as a 4th dashboard tab,
   "Chats" (see "Chat categorization" above). Built, tested locally against real production
   data, migration already applied to the live Supabase DB. **Not yet deployed** -- needs
   `deploy/instructor_dashboard/` (already regenerated) pushed to Connect Cloud. Note the
   install-section chat (item 6) will NOT appear here even once deployed, since it isn't
   logged to `chat_logs` at all -- deliberate, see that section.
8. DONE: added Module 6, "Interpreting Model Output" -- linear-vs-curved recognition,
   R^2^/RMSE (shown as both a formula and plain language, deliberately -- see below), and
   comparing two models, with no actual model-building. Two graded exercises (compute RMSE;
   decide which of two models wins), each with its own tutor chat. Also added a new Module 3
   exercise, "Turning a formula into code" (Pythagorean theorem -> `sqrt(a^2 + b^2)`),
   specifically so students hit "translate a formula into R" once on something simple before
   Module 6 needs the same skill for RMSE. Both built and tested locally end-to-end
   (quizzes, exercise fail/pass/error paths, tutor chat auto-open, `exercise_attempts`
   logging all confirmed against Supabase); `deploy/course/` regenerated to match.
   **R^2^/RMSE are shown as real math notation (MathJax, already wired into this course via
   `--mathjax` in the pandoc build) alongside the plain-language walkthrough, not
   prose-only** -- added after the app owner pointed out that English-only explanations of a
   formula are less accessible than showing the actual notation, especially for
   international students; formula notation reads the same regardless of English fluency.
   **Still needs one manual check**, same caveat as item 6: an actual tutor-chat reply for
   Module 6's exercises could not be confirmed via automated browser testing (typed message
   didn't register, 0 rows in `chat_logs` afterward) -- consistent with the same shinychat/
   browser-automation limitation already noted for the install-section chat, not a new bug.
   **Every module's "Wrapping up" section was also rewritten** -- they'd all converged on
   the same weak pattern (one sentence just re-listing that module's topic nouns, e.g.
   "You've now covered X, Y, Z"), flagged by the app owner as not actually useful. Now each
   one keeps a short recap but adds a "If you remember only a few things from this module"
   list of 2-3 concrete, conceptual takeaways instead of a topic-name recap. Module 1 was
   deliberately left alone -- its "Wrapping up" centers on a real check exercise, not a
   prose recap, so it was never the pattern being complained about.
9. DONE: built a `pilot_testing/` folder (message to send guinea-pig testers, checkpoints to
   inject at specific points in the course, the data/scripts those checkpoints need,
   including a capstone script comparing a linear model vs. a random forest on fish data --
   restructured so testers write a few lines themselves, filtering results by species with
   the Module 4 `filter()` skill, rather than just clicking Run). Not yet sent to any real
   tester.
10. **Screenshots and screen recordings (see that section above) are deliberately sequenced
    AFTER the pilot, not before or during it** -- explicitly reprioritized when this came up
    again after Module 6 was built. `pilot_testing/checkpoints_and_feedback.md` now directly
    asks testers whether a screenshot/clip (or any other visual -- a diagram, example
    output, etc.) would have helped **anywhere in the course, not just Module 1** -- the
    question was deliberately widened after being flagged as too narrowly scoped, since
    visuals could plausibly help in more places than just the install section. Also added,
    same round: a question on whether testers sought help outside the course at all (Google,
    another AI tool, a friend) and where/why -- signal on whether the in-course tutor chat is
    actually sufficient or people route around it.
11. DONE: added Module 7, "Extra Practice" -- ungraded, endlessly repeatable practice
    questions, added because the app owner wanted a low-stakes way to get more reps on a
    skill without waiting for a new module. Two question generators to start (vector
    indexing; formula translation, picking randomly among 3 formula templates each time),
    each producing genuinely different random values/wording every time via a
    `generate_fn()` contract -- see `random_exercise_ui()`/`random_exercise_server()` in
    `R/tutor_utils.R`. Deliberately ungraded and unlogged (no `exercises` row, no
    `exercise_attempts`/`chat_logs` writes) -- same rationale as the install-help chat's
    `wire_standalone_chat()`, which this reuses (generalized to take its own
    `system_prompt`/`greeting` instead of a hardcoded one, so the same function now serves
    both the install-help chat and this module's practice chat).
    **Two real bugs caught and fixed while building this:**
    - `random_exercise_server()`'s first version called `question()` (a `reactiveVal`) from
      a plain helper function invoked both at setup and inside `observeEvent()` -- reading a
      reactiveVal only works from inside an actual reactive consumer (`render*()`/
      `observe()`/`reactive()`), so this threw "Operation not allowed without an active
      reactive context" every time, confirmed in the server console. Fixed by moving the
      read inside `renderUI({...})` itself, which is a valid reactive context and means
      Shiny auto-reruns it whenever `question()` changes -- no manual re-render call needed.
    - Stacking the two practice panels as separate `###` sub-sections under one `##` topic
      broke learnr's `progressive`/`allow_skip` "Continue" gate between them -- it never
      unlocked, confirmed via the DOM (`display: none`, class `section level3 hide`) no
      matter what was submitted. Root cause, as best determined: `random_exercise_ui()`'s
      panels are entirely dynamic (a bare `uiOutput()` filled in later by `renderUI()`),
      unlike every other exercise/quiz in this app which emit fully static HTML at knit
      time -- the progressive gate appears to depend on markup present in the static HTML to
      recognize a section's exercise as completed, which a bare placeholder can't provide
      regardless of what's later rendered into it. Since this module is ungraded anyway
      (no reason to force sequential completion), fixed by not using `###` subheadings for
      these panels at all (bold text instead) rather than solving progressive-gating for a
      mechanism it was never designed for. **Any future dynamic-`uiOutput()` content stacked
      under one `##` topic should do the same** -- see the comment in `course.Rmd` right
      above `## Module 7: Extra Practice` for the full writeup.
    Tested locally: both panels render together (no gate), "New Question" regenerates
    different values/templates each click, fail and pass paths confirmed for both question
    types, and the shared practice chat panel opens with its distinct greeting. Same caveat
    as items 6/8: an actual AI reply in that chat could not be confirmed via automated
    browser testing.
12. **REVISED (superseding item 11's two-fixed-panel layout) into a BETA module-picker
    design**, after the app owner clarified what they actually wanted: not two separate
    fixed boxes, but pick a module (2-6) and get a random question drawn from what THAT
    module taught -- including question types not tied to any of that module's actual
    graded exercises, once more variety is added (explicitly deferred to a later pass; this
    beta has exactly one generator per module, chosen to mirror content that module already
    teaches, to keep the beta itself simple to reason about and test).
    - `random_exercise_ui()`/`random_exercise_server()` were replaced outright (not kept
      alongside) with `module_practice_ui()`/`module_practice_server()` in
      `R/tutor_utils.R` -- a `radioButtons()` module picker plus ONE dynamic panel, backed
      by `generators_by_module` (a named list keyed by module number as a string, e.g.
      `"3"`, each value `list(generate_fn = ..., has_plot_output = TRUE/FALSE)`). Switching
      modules or clicking "New Question" both regenerate via the currently-selected
      module's `generate_fn()`. Also added `has_plot_output` support (mirroring
      `exercise_ui()`/`exercise_server()`'s same argument) since Module 5's practice
      question needed it -- the first random-practice question to produce a plot.
    - Five generators, one per module: Module 2 = comment out a random line (mirrors its
      `module2_comment_out` exercise); Module 3 = vector indexing (unchanged from item 11,
      just renamed `generate_module3_practice`); Module 4 = `filter()` + `summarize(sum(...))`
      on a small randomly-generated fruit/count table; Module 5 = scatter plot of a random
      `practice_df` (`geom_point()`, checked the same structural way Module 5's own
      `scatter_exercise` is); Module 6 = compute RMSE from random `practice_actual`/
      `practice_predicted` vectors. The old `generate_formula_practice()` (3 formula
      templates) was deleted rather than kept dangling unused -- formula-style practice can
      return under Module 3 or 6's pool once the "add types beyond what each module already
      grades" pass happens.
    - Tested locally end-to-end: all five modules produce a correct, on-topic question;
      fail and pass paths confirmed for Module 2 (comment-out), Module 4 (dplyr), and
      Module 6 (RMSE); Module 5's plot renders and its structural check passes; switching
      modules and clicking "New Question" both regenerate fresh values every time. Practice
      chat re-verified opening correctly (same automated-reply-testing caveat as before).
13. Remaining:
   - Actually run the pilot (send `pilot_testing/` materials to real testers).
   - Get real instructor usage on the dashboard's tabs to see if they actually answer the
     day-to-day questions, or need adjusting.
   - Run `Rscript R/classify_chat_messages.R` periodically (by hand, or set up on a
     schedule) so the "Chats" tab's categories stay fresh as new conversations happen.
   - After beta feedback: add more question generators per module, INCLUDING types not
     tied to that module's own graded exercises (explicit direction from the app owner --
     practice should draw on everything a module taught, not just repeat its exercise
     shapes). Also add a sentence at the end of each module (its "Wrapping up," most
     likely) pointing to Module 7 and noting that its practice includes code-practice types
     beyond what that module's own graded exercises covered -- deliberately deferred until
     after the beta/that expansion, so the sentence describes what's actually there.
   - Get real pilot feedback on the beta itself before expanding it -- do the 5 module
     choices and one-question-per-module scope feel right, or does it need adjusting first?
