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
(sarahswaff/rtutor) -- each module is deployed as its own separate "content" item, pointed
at its own self-contained folder under `deploy/` (see "Current status" below for why a
separate, flattened `deploy/` copy exists per module rather than deploying `tutorials/`
directly). Each deployment needs its own copy of the four `.Renviron` variables
(`SUPABASE_DB_HOST`, `SUPABASE_DB_USER`, `SUPABASE_DB_PASSWORD`, `ANTHROPIC_API_KEY`) set in
its own Connect Cloud dashboard settings.
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
│   ├── module_1.Rmd    -- DONE, tested end-to-end
│   ├── module_2.Rmd    -- DONE, tested end-to-end
│   └── module_3.Rmd    -- DONE, tested end-to-end (see "Current status" below)
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
1. **Introduction** -- install R/RStudio, panes, working directory. DONE, but see "Current
   status" below -- the install section was substantively rewritten from a passive fact-list
   into an actual guided step-by-step walkthrough and hasn't been re-verified live in a
   browser yet (module_1.Rmd).
2. **Basic Code** -- packages, console, comments, run provided code, error messages, help().
   DONE (module_2.Rmd).
3. **Data** -- hello world, data types, naming conventions, vectors, assignment, basic
   functions/comparisons, data structures, import. DONE (module_3.Rmd).
4. **Clean up** -- inspect, rename columns, index/subset, pipe, dplyr verbs
   (filter/select/mutate/arrange/group_by/summarize), handling NAs.
5. **Actual Work** -- ggplot basics, markdown awareness (NOT authoring -- students just need
   to know it exists, it'll likely be provided to them), script save/import, file naming
   conventions (light touch on version control -- awareness only, not real git usage).

A capstone pipeline assessment exists but is explicitly OUT of scope for the tutorial itself.

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
- No password auth. Students identified by name + email only; roster-CSV matching is planned
  but NOT YET BUILT (deferred on purpose -- the identity table is designed to make this a
  drop-in addition later).
- No Canvas LTI integration yet. A lightweight roster-CSV approach is planned instead; full
  LTI SSO/gradebook integration is deferred to a later phase pending institutional approval.
- Instructor dashboard not started -- deliberately deferred until real attempt data exists
  from testing, so it can be built against real shapes of data rather than guesses.
- Every exercise attempt is logged as its own row (explicitly chosen over update-in-place).


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

A real back-and-forth tutor conversation has been verified for all three modules (both
directions confirmed in `chat_logs`) -- responses correctly reference the student's actual
submission, give guiding next steps without leaking answers, and build on the student's own
follow-ups, consistent with the system prompt's escalation/non-leaking design. The tutor
chat greeting (`TUTOR_CHAT_GREETING`, pushed via `chat_set_greeting()` after every
`chat_clear()` in `wire_tutor_chat()`'s `refresh_chat()`) is confirmed working on every
module.

Module 1's "Installing R and RStudio" section is a real guided walkthrough (three `###`
steps -- install R, install RStudio, verify via `2 + 2` in the Console -- each with its own
checkpoint quiz), not a passive fact list.

**Next actions, in order:**
1. Modules 4-5 follow the same established pattern -- source `R/tutor_utils.R`, call
   `bs5_theme_dependencies()` + `wire_tutor_chat()` for any exercise,
   `quiz_question_ui()`/`quiz_question_server()` for quizzes, `exercise_ui()`/
   `exercise_server()` for graded exercises (NOT `learnr::question()`/`exercise=TRUE`/
   gradethis -- see the note at the top of "Key conventions" above), write only the
   exercise-specific `evaluate_<exercise>()` grading function per module, and size the
   exercise count/complexity per the scaling convention above rather than Module 1/2's
   original (pre-rewrite) count.
2. When each new module is ready, add a matching self-contained copy under `deploy/` with
   its own `manifest.json`, following the Modules 1-3 pattern, and deploy it to Connect
   Cloud the same way.
3. Instructor dashboard, once there's real attempt/chat data to build it against.
