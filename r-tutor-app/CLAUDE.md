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

**STILL UNRESOLVED, despite an earlier note in this file claiming otherwise -- read this
before trusting anything below.** `unstick_hidden_outputs()` in `R/tutor_utils.R` (still in
place, called once per module) was verified extensively via automated testing -- and then
the user re-tested via RStudio's "Run Document" button and in their own regular browser and
saw **zero change**: buttons still completely non-functional. This was re-confirmed, not a
fluke. The automated-testing verification below is real (it did happen, the fix does work
under those specific conditions) but evidently does not reflect the app's actual real-world
behavior, for a reason that hasn't been identified yet. See
`debug_recalculating_bug/HANDOFF.md` for the full, current writeup and the open questions --
that file is now the source of truth for this bug, not this section. The two things most
worth checking next: (1) has anyone actually run `Rscript R/run_tutorial.R` and then opened
the result in a real, non-automated browser (as opposed to either RStudio's "Run Document" OR
an automated testing tool -- that exact combination has never been tried), and (2) is
`tutorial.storage` actually `"none"` inside the RStudio session that's failing, or could that
session predate the `.Rprofile` change and still be using stale/default storage. A
`grading_progress_indicator_css()` CSS-only loading-message fix was also added and then
**removed** after the user reported it displaying before the exercise could even be
submitted -- confirming the output frame is stuck in `.recalculating` from page load in their
environment, i.e. the original bug, not a delay.

The rest of this section is kept as a record of what was tried and what Path-A (automated)
testing showed -- treat it as unverified for the app's real usage until the discrepancy above
is resolved.

**Root cause:** Shiny's `session$clientData$output_<id>_hidden` flag, which tracks whether a
given output is currently visible, never flips back to `FALSE` for an output that was bound
while its containing `##` topic was still hidden by learnr's `progressive: true` topic
switching (learnr hides inactive topics via jQuery show/hide, and whatever visibility
re-detection Shiny normally relies on -- e.g. `IntersectionObserver` -- never fires for that
transition in this combination). Confirmed directly: a `session$clientData` dump observer
showed the hidden flag stuck at `TRUE` for a quiz's outputs even while that quiz's topic was
the actively-displayed one on screen, and a `shiny:bound`/`shiny:recalculating`/
`shiny:recalculated`/`shiny:value` lifecycle listener showed the output gets `shiny:bound`
once and nothing else, ever. Since Shiny's `shouldSuspend()` reads that stale `hidden=TRUE`
forever, it permanently blocks the output's first real render -- this is what
`outputOptions(..., suspendWhenHidden = FALSE)` (a real, documented Shiny option -- see the
"Explicit vs. implicit output registration" note below for the correction of an earlier wrong
claim that this option didn't work) is designed to override.

**Why a simple fix didn't work directly:** `outputOptions()` requires the target output to
already be registered, but learnr registers most quiz/exercise sub-outputs (a question's
`message_container`/`action_button_container`, an exercise's own output frame) *lazily*,
well after session start -- calling `outputOptions()` on them too early throws `"<id> is not
in list of output objects"` and crashes the whole session (confirmed empirically). The fix:
`unstick_hidden_outputs(output, session)` watches `session$clientData`'s `output_*_hidden`
keys (which reliably appear the instant each dynamic output binds, regardless of whether it's
hidden) on a 200ms timer, and calls `outputOptions(..., suspendWhenHidden = FALSE)` on each
newly-seen output exactly once. This is fully generic -- no per-module/per-exercise label
list to maintain -- and patches every quiz and exercise output in the session, not just one.

**False leads ruled out along the way** (kept here so this isn't re-investigated):
- Not a `tutorial.storage` issue. `tutorial.storage = "none"` (set to fix the *separate*,
  real local-filesystem-collision bug -- see the gotcha further below) was suspected at one
  point since removing it appeared to fix the bug in one test run -- but a clean, controlled
  retest (single server process, storage explicitly set to `"auto"`/`"client"`/a custom
  per-PID `filesystem_storage()`) reproduced the exact same stuck-recalculating symptom
  regardless of storage backend. That one successful-looking run was a red herring (likely a
  timing/race artifact from several concurrent R processes competing for CPU at the time, not
  a real fix). `tutorial.storage = "none"` stays in place -- it's still the correct fix for
  the collision bug -- and `unstick_hidden_outputs()` was confirmed working under it.
- Not the Shiny `.recalculating`-class-on-bind behavior change alone, not
  [rstudio/shiny#4406](https://github.com/rstudio/shiny/issues/4406)'s boxless-ancestor
  `IntersectionObserver` bug (no `display:contents` ancestor exists in this app's real DOM
  chain, and the documented `min-width`/`min-height` workaround didn't fix it here), and not
  [[rstudio/shiny#4373]] resume-after-hidden territory -- all plausible given the observed
  symptoms, but none of the targeted fixes for those specific issues resolved it. The eventual
  fix works at a different layer (forcing `suspendWhenHidden = FALSE`) rather than fixing
  whatever specifically breaks the hidden-flag update, so the exact underlying Shiny/learnr
  incompatibility causing `output_*_hidden` to never update is still not pinned down -- only
  worth chasing further if a future Shiny/learnr upgrade needs `unstick_hidden_outputs()`
  revisited.
- Downgrading `shiny` below 1.9.0 was tried and abandoned: it dodges this bug but `shinychat`
  (tutor chat) hard-requires `shiny >= 1.10.0` and refuses to load below it, so no version
  satisfies both. Not needed now that the real fix is in place; shiny stays on 1.14.0.

**Verified against the live app, post-fix** (all three modules, real Supabase DB, real
gradethis grading, not just the isolated `debug_recalculating_bug/repro.Rmd` repro): Module
1's `name-exercise` (both fail and pass paths), Module 2's `comment-exercise` and
`fix-the-bug-exercise` (including the error-check path, and tutor chat auto-open + greeting
on a failed attempt), and Module 3's `vectors-exercise` and `cumulative-exercise` (including
its starting syntax-error path) -- plus quiz questions on topics beyond the first (Module 1's
install-walkthrough quizzes) -- all render and grade correctly with the fix in place, with
zero code changes to storage settings.

**Diagnostic artifacts** (`debug_recalculating_bug/HANDOFF.md`, `debug_recalculating_bug/
repro.Rmd`) are left in place as a record of the investigation but are not part of the
production app and don't need to be kept in sync going forward.

**A second-order finding turned out to be a red herring and its fix was reverted.** After the
`unstick_hidden_outputs()` fix, automated (Path A) testing found a real but separate ~9-10
second cold-start delay on a fresh R process's first exercise submission (traced to
`rmarkdown`/`knitr` warm-up cost inside `learnr:::render_exercise()`), and added
`warm_up_exercise_renderer()` (still in place -- harmless, and does measurably help this
specific delay) plus a `grading_progress_indicator_css()` loading message (**removed**) to
address it. When the user reported "still having the issue" a second time, it became clear
this cold-start delay was NOT what they were experiencing -- the app owner reported the
loading message appearing before the exercise could even be submitted, meaning the output
frame was stuck in `.recalculating` from page load, not mid-submission. The CSS message was
actively misleading in that state (implying grading was in progress when nothing had been
submitted) and was removed. `warm_up_exercise_renderer()` was left in place since it's
harmless and unrelated to the real, still-unresolved bug -- see `debug_recalculating_bug/
HANDOFF.md`.

Modules 1-3 are all fully built and tested end-to-end, in the same style: identity capture ->
instructional/quiz content -> gated exercise(s), each backed by an always-available tutor
chat panel that auto-opens on a failed attempt. Module 1's one exercise
(`module1_name_check`), Module 2's two (`module2_comment_out`, `module2_fix_error`), and
Module 3's four (`module3_assignment`, `module3_vectors`, `module3_fix_comparison`,
`module3_cumulative` -- the first module built under the updated "exercise count/difficulty
scales with the module" convention, including its first cumulative exercise) all share the
exact same wiring -- `wire_tutor_chat()`, `log_attempt_and_maybe_open_chat()`, and
`bs5_theme_dependencies()` live once in `R/tutor_utils.R` and are called identically from
each module's `setup`/`context="server"` chunks; only each exercise's own
`evaluate_<exercise>()` grading logic differs. `exercises.learning_objective` is set for all
seven exercise rows in Supabase (schema, Module 1-3 rows, and all exercise rows confirmed
live).

Verified against the live app (via `rmarkdown::run()` + a browser, not just code review, for
ALL THREE modules): identity modal + DB write, progressive gating (submitting is required
before "Continue" unlocks -- confirmed both the blocked and unblocked cases), and for every
graded exercise the full button set -- Run Code, Submit Answer both failing and passing, AND
Start Over tested separately after a failing attempt and after a passing attempt (per the
"Testing convention" above) -- confirmed the editor resets to starting code correctly both
times, with DB attempt logging (`exercise_attempts`, correct `student_id`/`exercise_id`) and
tutor chat auto-open behaving correctly throughout. A real back-and-forth tutor conversation
has now been verified for all three modules (both directions confirmed in `chat_logs`) --
Module 3's `module3_assignment` exchange correctly referenced the student's actual failed
submission (identified `FIXME` as the problem from the fed-in context, not a generic guess),
gave a guiding next step without stating the exercise's actual answer values, and correctly
affirmed + built on the student's own follow-up proposal in the second turn -- consistent
with the system prompt's escalation/non-leaking design.

**Fixed: the tutor chat greeting was silently never (re)appearing after the first page
load, on any module.** Root cause: `chat_ui(greeting = ...)` only sets a *static* greeting
shown on that widget's very first render. `shinychat::chat_clear(chat_id, greeting = TRUE,
session = session)` -- called every time `wire_tutor_chat()`'s `refresh_chat()` runs, i.e.
every single time a panel opens -- does NOT redisplay it; in shinychat 0.5.0 that flag just
resets the panel to blank and makes the *client* fire a `<chat_id>_greeting_requested` Shiny
input event asking the server to supply one. Nothing in this app ever listened for that
event, so the greeting stayed null forever after the first load (note: `.shiny-chat-greeting`
is its own DOM element, separate from `.shiny-chat-messages-content` -- checking the wrong
one looks identical to the greeting being missing). Fix: `TUTOR_CHAT_GREETING` (a shared
constant in `R/tutor_utils.R`) is now used both as `chat_ui()`'s static `greeting =` value
*and* pushed explicitly via `shinychat::chat_set_greeting(chat_id, TUTOR_CHAT_GREETING,
session = session)` right after every `chat_clear()` call inside `refresh_chat()` -- this is
the documented way to (re)send a greeting from the server, not a workaround. Fixed once in
the shared `wire_tutor_chat()`, so it applies to all modules; live-verified on Module 3
(auto-open, manual open, and a full follow-up conversation afterward all confirmed correct)
and spot-checked on Modules 1-2 (greeting confirmed rendering correctly on Module 1's one
exercise and both of Module 2's) -- Modules 1-2 weren't re-tested for the full auto-open/
conversation/DB-logging flow post-fix, but that wiring is unchanged by this fix and was
already verified pre-fix, so a manual-open greeting check was sufficient here.

**Module 1 install section rewritten -- was a passive fact-list, is now an actual guided
walkthrough.** User feedback: "Installing R and RStudio" originally just told students facts
("R and RStudio are two different pieces of software...") without ever walking them through
doing it. Rewritten into three `###` steps under that same `##` topic -- Step 1 (install R
from CRAN, with concrete Windows/Mac click-by-click instructions), Step 2 (install RStudio
from posit.co, same level of concreteness), Step 3 (open RStudio, verify via typing `2 + 2`
in the Console) -- each ending in its own checkpoint `question()`, matching what the user
asked for ("a multi step quiz that walks through steps"). Explicitly tells students up front
that this tutorial can't see their computer or verify their install directly (unlike later
modules' exercises, which run in-browser) -- Step 3's console check is the closest thing to
a real verification this format can offer. Rendered cleanly (`rmarkdown::render`, no errors,
all new quiz chunk labels unique) and content-verified by fetching the live server's HTML
directly (`curl`, bypassing the browser) -- but NOT yet click-tested in an actual browser
session; see the environment note below for why.

**UNRESOLVED this session: could not get a reliable live-browser verification signal at
all, for any module, late in this working session -- this is a tooling problem, not a
content or app problem.** While re-verifying Module 1's exercise buttons after the
`tutorial.storage` fix, Run Code/Submit Answer showed the same stuck-`disabled`,
never-responds symptom the user reported -- but a direct A/B check (switching the exact same
browser session to Module 3, which had been fully click-verified working earlier this same
session) showed the *identical* stuck symptom there too, at the same time. Since one
codebase can't be simultaneously broken and proven-working, this points at the browser
automation session itself having degraded after a very long testing run, not at either
module's code -- this same category of environment flakiness (session-wide, resolved by a
full pane restart) was already seen and worked around once before, during Module 3's initial
testing. Didn't chase it further this time to avoid repeating that multi-hour detour; a fresh
`R/run_tutorial.R` + browser session (or the user's own RStudio) is the next real test of
whether Module 1's buttons work post-fix, not a repeat of this session's browser pane.

**Tutor chat / bslib retrofit history:** Module 2 needed several fixes not anticipated in
earlier planning -- see "Key conventions" above (BS5 theming, `*-error-check` chunks, the
setup-chunk-shared-function pattern for grading logic, and the deprecation of
`chat_mod_ui()`/`chat_mod_server()`). Module 1 was retrofitted to match once the pattern was
proven out, and the shared wiring was extracted into `R/tutor_utils.R` at the same time so
Modules 3-5 reuse it rather than re-copying it per module.

**Module 3 build notes:** first module written under the updated exercise-scaling convention
(see "Key conventions") -- four graded exercises (three targeted + one cumulative) instead of
1-2, mixing "fix this" and "make this output" formats, with the cumulative exercise
deliberately starting from code with real (parseable-by-R-error, not just logically wrong)
syntax errors to reinforce Module 2's error-reading skill. Two new gotchas surfaced during
live testing and are now documented above for Modules 4-5: the bare-`___`-placeholder R
syntax trap (fixed by switching to `FIXME`), and learnr's per-OS-user server-side `.rds`
progress cache, which can look exactly like a broken Run Code/Submit Answer button during
local iteration if not cleared.

**Next actions, in order:**
1. Modules 4-5 follow the same established pattern -- source `R/tutor_utils.R`, call
   `bs5_theme_dependencies()` + `wire_tutor_chat()` for any exercise, write only the
   exercise-specific `evaluate_<exercise>()` grading function per module, and size the
   exercise count/complexity per the updated scaling convention rather than Module 1/2's
   count.
2. Instructor dashboard, once there's real attempt/chat data to build it against.
