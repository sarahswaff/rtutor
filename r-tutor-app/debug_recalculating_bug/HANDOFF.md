# Bug handoff: learnr exercises/quizzes permanently stuck "recalculating"

## STATUS: UNRESOLVED, but now precisely characterized. Read this section
## first, then "Alternatives worth investigating in parallel" near the
## end — the app's owner wants alternative approaches considered alongside
## continued root-causing after this much investigation.

**The bug is a client-side interaction-binding failure, not a rendering
failure.** This is now conclusively established, not inferred:

1. A wire-level trace (`options(shiny.trace = "send")`, see "Wire-level
   trace test" below) captured directly from the app owner's own real
   browser (raw output saved in `trace_output_from_app_owner.txt`) shows
   the server correctly completing the full render cycle for the quiz
   outputs — `recalculating` → `recalculated` → a `values` message
   containing the real question HTML (actual `<input type="radio">`
   elements, real answer text) → a `progress`/`binding` message (Shiny's
   own protocol signal telling the client to bind interactivity for that
   content).
2. The app owner confirmed directly: **"the question shows up. the
   buttons are visible."** The server-sent content is reached and
   displayed in the DOM. This rules out both a server-side scheduling
   failure and a client-side DOM-rendering failure.
3. But: **"the buttons are not clickable."** Visible, correctly-rendered
   quiz radio buttons and/or the Submit Answer button do not respond to
   clicks at all.

Put together: the server renders and sends everything correctly, the
browser displays it correctly, and then **the interactive/input-binding
step that's supposed to make that displayed content clickable never
takes effect**, specifically in the app owner's real browser (Chrome and
Edge both) and never in the automation harness. This is a materially
different, and much narrower, bug than anything chased earlier in this
document (the original theories about `session$clientData` hidden flags,
`outputOptions()`/`suspendWhenHidden`, MathJax, and the mystery
`startTime` JS error are all now superseded by this finding — kept below
for context/history, but none of them explain a working data-flow with a
broken interaction layer). See "Current leading hypothesis" immediately
below for what this actually points at, and "Not yet tried" for the
concrete next diagnostic.

## Current leading hypothesis: `Shiny.bindAll()` / dynamic input binding

Shiny's client-side JS does not automatically make freshly-inserted HTML
interactive. When an output like `install-quiz-answer_container` is
updated with new HTML (e.g. real radio buttons replacing a loading
placeholder), Shiny's protocol sends a `{"progress":{"type":"binding",...}}`
message specifically so the client knows to run its binding step
(`Shiny.bindAll()` or equivalent) over the new DOM subtree — this is
exactly what enables `input$wd-quiz-answer`-style reactivity for a radio
group that didn't exist in the DOM a moment earlier, and what wires up the
Submit Answer button's click handler. If that client-side binding step
does not execute (or errors, or is skipped) after the content is inserted,
the exact symptom reported would result: real, visible, correctly-rendered
HTML that simply never responds to interaction, because nothing ever
attached event listeners / registered the new inputs with Shiny's
reactive system. **This is the current leading hypothesis** and is
directly testable — see "Not yet tried" below. It is well-precedented:
Shiny has had various historical bugs and edge cases around re-binding
dynamically-inserted content (distinct from `renderUI`'s own visibility
suspension issue investigated earlier in this document), and this would
be consistent with something that reproduces in some browser
configurations but not others.

## Original investigation history (superseded by the above, kept for context)

The rest of this document, below "The central open question", is the
history of how the investigation arrived at the finding above. It
includes some conclusions that no longer hold (e.g. the fix
`unstick_hidden_outputs()` was originally verified extensively on the
automation harness and believed to be a complete server-side fix — it
does appear to genuinely fix what it targets, since the wire trace now
confirms the server-side render/send cycle completes correctly even in
the app owner's environment; it just turned out not to be sufficient,
because the actual remaining bug is client-side, one layer further down
the pipeline than anything `unstick_hidden_outputs()` touches). The
MathJax and `startTime`-JS-error investigation is very likely irrelevant
now given the finding above, but is left in place in case it turns out to
be connected to the binding failure after all (e.g. if whatever throws
that JS error also happens to interrupt Shiny's own binding call in the
same execution context — not yet checked either way).

## The central open question

| Launch method | Browser | Extensions | Result |
|---|---|---|---|
| `Rscript R/run_tutorial.R` | automation harness (Chromium-based, not a normal user browser) | none | **works** |
| RStudio "Run Document" | app owner's real Chrome | normal | **fails** |
| `Rscript R/run_tutorial.R` | app owner's real Chrome, incognito | none allowed in incognito (confirmed via `chrome://extensions`) | **fails** |
| (same server, `repro_no_mathjax.Rmd` on :7413) | app owner's real Chrome, incognito | none | **fails** (same JS error, MathJax ruled out) |
| (same test) | app owner's real Edge | — | **fails** (rules out Chrome-specific) |

It is not about the launch method (RStudio vs. `Rscript`) — confirmed by
row 3. It is not about MathJax, and not Chrome specifically — confirmed by
rows 4-5: Edge, a different browser built on the same Chromium engine
family, fails exactly the same way. **Every real, user-installed browser
tried on this machine fails; the automation harness has never failed.**
The remaining honest description of the divide is "automation harness vs.
a real browser on this specific machine" — which could mean browser-vendor
behavior that both Chrome and Edge happen to share (plausible, since they
share the Chromium rendering engine — Firefox has not yet been tried and
would be the next real test of "is it Chromium-family-specific"), or it
could mean something about the *machine* rather than the browser at all
(see item 1 under "Not yet tried").

Also newly confirmed: the server-side fix (`unstick_hidden_outputs()`) is
running correctly and identically regardless of which row above is being
tested. Debug logging was added (`message()` calls, see `repro.Rmd`'s
comments for the exact diff) and, when the app owner ran the RStudio
"Run Document" case with it in place, the R console showed:

```
UNSTICK STARTED | pid=23356 | shiny=1.14.0 | learnr=0.11.6
PATCHED: install-quiz-answer_container | hidden=TRUE
PATCHED: install-r-quiz-answer_container | hidden=TRUE
PATCHED: install-rstudio-quiz-answer_container | hidden=TRUE
PATCHED: first-check-quiz-answer_container | hidden=TRUE
PATCHED: panes-quiz-answer_container | hidden=TRUE
PATCHED: wd-quiz-answer_container | hidden=TRUE
PATCHED: tutorial-exercise-name-exercise-output | hidden=TRUE
PATCHED: install-quiz-message_container | hidden=TRUE
PATCHED: install-quiz-action_button_container | hidden=TRUE
PATCHED: install-r-quiz-message_container | hidden=TRUE
PATCHED: install-r-quiz-action_button_container | hidden=TRUE
PATCHED: install-rstudio-quiz-message_container | hidden=TRUE
PATCHED: install-rstudio-quiz-action_button_container | hidden=TRUE
PATCHED: first-check-quiz-message_container | hidden=TRUE
PATCHED: first-check-quiz-action_button_container | hidden=TRUE
PATCHED: panes-quiz-message_container | hidden=TRUE
PATCHED: panes-quiz-action_button_container | hidden=TRUE
PATCHED: wd-quiz-message_container | hidden=TRUE
PATCHED: wd-quiz-action_button_container | hidden=TRUE

Execution halted
```

Package versions match what's expected (`shiny=1.14.0`, `learnr=0.11.6` —
no stale-namespace issue), and every single output the fix is supposed to
patch shows up and gets patched, in the same order seen on the working
automated-harness runs.

**Correction to an earlier version of this document:** that was previously
described as "server-side confirmation that the fix's own mechanism is not
the problem." That claim was too strong and has been corrected. The
`PATCHED` log only proves `outputOptions(..., suspendWhenHidden = FALSE)`
was *called* and didn't error — i.e. the output existed and the option was
recorded. It does **not** prove the output's underlying observer actually
went on to re-execute and produce/send a value afterward. Shiny 1.14.0's
own source (`ShinySession$outputOptions()`, confirmed by reading it
directly) does call `manageHiddenOutputs()` immediately after recording
the option, which does call `resume()` on the right observer when
`shouldSuspend()` is now `FALSE` — but whether that `resume()` actually
results in a completed render, on the app owner's specific setup, had not
been directly observed. See "Wire-level trace test" immediately below for
the real answer to this, now confirmed on the automation harness (where it
works) as the reference case for the app owner to compare against.

## Wire-level trace test (confirms/rules out each layer separately)

`ShinySession$write()` (the function that actually sends any message to
the browser) checks `getOption("shiny.trace", FALSE)` and, if it's
`"send"`, prints every outgoing message via `message("SEND ", json)`
before handing it to the websocket — confirmed by reading Shiny 1.14.0's
installed source directly. This lets the three layers (R observer →
outgoing websocket value → DOM binding) be checked independently instead
of inferred from the `.recalculating` CSS class alone.

**Run `debug_recalculating_bug/run_repro_trace.R`** (new file in this
folder — sets `options(shiny.trace = "send")` and launches `repro.Rmd` on
port 7414). Open the printed URL in the real browser where the bug
happens. No clicking needed — just get through the identity modal and
navigate to "Installing R and RStudio" (the first quiz topic), then search
the R console output for `install-quiz-answer_container`.

**Reference trace, captured from the automation harness (i.e. this is
what "working" looks like):**

```
PATCHED: install-quiz-answer_container | hidden=TRUE
SEND {"recalculating":{"name":"install-quiz-answer_container","status":"recalculating"}}
SEND {"recalculating":{"name":"install-quiz-answer_container","status":"recalculated"}}
SEND {...,"values":{...,"install-quiz-answer_container":{"html":"<div class=\"loading placeholder-glow\">...</div>","deps":[]},...}}
SEND {"progress":{"type":"binding","message":{"id":"install-quiz-answer_container","persistent":false}}}
```

...followed shortly after by a second `values` message for the same ID,
this time containing the real question HTML
(`"<div id=\"install-quiz-answer\" class=\"form-group shiny-input-radiogroup...`)
instead of the loading-placeholder skeleton — this is learnr's own
two-stage render (a placeholder while the question module initializes,
then the real content).

**What to compare against, in the app owner's failing environment:**

| What the R console shows | Meaning |
|---|---|
| `PATCHED`, but no `SEND recalculating`/`recalculated`/`values` for that ID ever | The observer isn't actually executing after `resume()` — still a server/reactive-scheduling issue, and the earlier server-side theory needs revisiting. |
| Server sends `recalculating`, `recalculated`, and a `values` message containing the quiz HTML (matching the reference trace above) | Server side is genuinely fine — the bug is in the browser (DOM binding) or the transport layer. Check DevTools Network → WS → Messages (see below) to see whether the browser *receives* this same message. |
| Server sends the value (per the R console), but DevTools' WS Messages tab never shows a matching incoming frame | Transport/WebSocket layer is the target — investigate proxying, buffering, or connection-handling differences specific to the app owner's setup. |
| Server sends it, DevTools WS Messages shows the browser receiving it, but the `<div id="install-quiz-answer">` stays empty in the actual page | Client-side Shiny output-binding bug specifically — the browser has the data but isn't applying it to the DOM. |

This fork is a much stronger test than the `PATCHED` log alone, and should
be done before spending more time on the `startTime` JS error, trying
Firefox, testing another machine, or any of the "Alternatives" below —
it will likely determine which of those is actually worth pursuing.

You don't need to click Submit Answer to also check the WebSocket
directly: in DevTools → Network → filter **WS** → select the Shiny
connection → **Messages** tab → search for `install-quiz-answer_container`.
Per the reference trace above, this should appear automatically once the
quiz topic is reached, without any click — `learnr` registers and renders
the question module's initial UI on its own.

The `Execution halted` line's cause is not yet confirmed — it may simply
mark RStudio's background job for the tutorial being stopped/closed
(a normal side effect of ending the "Run Document" session) rather than a
crash; this wasn't isolated before the app owner moved on to the
incognito/real-browser test, which is the more informative result anyway
since it used a stable, independently-launched server rather than a
job that gets torn down. Worth a quick confirmation later (does
`Execution halted` appear even if the tutorial tab is left open and
untouched?) but it is not the current priority.

## New finding: an uncaught client-side JS error, only in the app owner's real browser

While testing directly in Chrome (not incognito, regular window), DevTools
console showed:

```
Uncaught TypeError: Cannot read properties of undefined (reading 'startTime')
    at et.reportAllChanges (<anonymous>:2:19429)
    at <anonymous>:2:13070
    at <anonymous>:2:331
    at d (<anonymous>:2:6141)
    at u (<anonymous>:2:6153)
    at <anonymous>:2:6321
    at <anonymous>:2:2895
    at n.timeout (<anonymous>:2:5652)
```

The line the error links to (i.e. the actual source line inside the
anonymous/minified script) is:

```js
startTime: t.entries[0].startTime,
```

— i.e. `t.entries` is an empty array (or undefined) and the code assumes
it has at least one item. This specific pattern (an object literal field
named `startTime` pulled from a `PerformanceEntry`, inside a function
literally named `reportAllChanges`) matches Google's `web-vitals` JS
library's internal metric-reporting code (`reportAllChanges` is a
documented option/pattern in that library's own public API for `onCLS`,
`onLCP`, etc.) — not anything in learnr's, Shiny's, or bslib's own known
JS.

**What's confirmed about this error:**
- It occurs in the app owner's real Chrome, both in a normal window and in
  incognito.
- It is NOT from a browser extension — confirmed via `chrome://extensions`,
  no extensions are allowed to run in incognito, and the error still
  appears there.
- **Not a system-level proxy or antivirus "Web Shield"-style script
  injector either** — checked directly on the app owner's machine:
  `netsh winhttp show proxy` reports direct access (no proxy), the
  `HKCU\...\Internet Settings\ProxyEnable` registry value is `0`, and a
  process scan found no Avast/AVG/Norton/McAfee/Malwarebytes/Kaspersky/
  Bitdefender/etc. — only Windows Defender's standard `MsMpEng.exe`
  (which does not do web-page script injection) plus a large amount of
  ordinary Acer OEM bloatware/services, none of which are known
  web-injection tools. This weakens (doesn't fully rule out, since not
  every product was checked) the "something on this machine injects a
  script into all pages, including localhost" theory.
- The stack trace shows only `<anonymous>` frames (Chrome's "VM" /
  anonymous-script labeling) — this typically means either an inline
  `<script>` block with no `src=` attribute, or `eval()`'d/dynamically
  `document.write()`'d code. With extensions and system-level injection
  both weakened as explanations, this increasingly points at something the
  **page's own served HTML pulls in**, most likely a script that MathJax
  itself (or a service in front of it, e.g. a CDN's injected analytics
  beacon) loads dynamically after its own initial `<script src=...>` tag
  runs — dynamically-inserted scripts commonly show as anonymous/VM in
  Chrome DevTools even though they didn't come from an extension.
- It has never been observed in the automation harness's browser — checked
  directly: `read_console_messages` shows zero messages, and MathJax was
  independently confirmed to load successfully there (`window.MathJax` is
  defined with `.Hub` present after page load, no errors).
- **Confirmed present in the page's own HTML:** the rendered page includes
  exactly one external (non-`127.0.0.1`) script tag:
  `<script src="https://mathjax.rstudio.com/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML">`.
  This is the only network dependency in the whole page that isn't served
  from the local Shiny process itself.

**MathJax/its CDN is now RULED OUT as the cause**, tested directly: the
app owner opened `repro_no_mathjax.Rmd` (running at
`http://127.0.0.1:7413`, `mathjax: null`, confirmed via the rendered HTML
that the `mathjax.rstudio.com` script tag is actually gone) in the same
real Chrome, including incognito — **same error, same broken buttons.**
The error is not dependent on MathJax being present at all.

**The anonymous script's origin is also now ruled out as anything the app
itself serves**: every `.js` file across all installed R packages
(learnr, shiny, bslib, shinychat, gradethis, htmltools, rmarkdown, and
everything else under the R library — 304 files) was searched for the
literal string `reportAllChanges`. **Zero matches.** The rendered page's
static HTML also references no external domain besides the
now-ruled-out MathJax CDN (`grep`'d directly for every `https?://` URL in
the output). So this error is not part of learnr/shiny/bslib/shinychat's
own code, and it's not coming from any script the page's own HTML asks the
browser to load.

**This substantially weakens the JS-error-as-root-cause hypothesis.**
Combined with the above, plausible remaining explanations for the error
itself: (a) it's a genuinely Chrome-internal mechanism (Chrome ships its
own Web Vitals / Core Web Vitals instrumentation for internal telemetry
purposes on some channels/flags, which would explain "anonymous", present
regardless of page content, and completely disconnected from anything the
app can control), in which case it is most likely **coincidental and
unrelated** to the actual bug; or (b) it's still something injected below
the page level that hasn't been identified yet (a security/monitoring tool
not in the process list check done so far, a router/ISP-level script
injection that somehow reaches `127.0.0.1` — unusual but not impossible
depending on how the machine's virtual network adapters are configured).
Given (a) is more likely based on current evidence, **this error should
probably no longer be treated as the leading hypothesis** — see "Not yet
tried" for where to look next.

- Whether this error is the actual cause of the button-unresponsiveness,
  or a coincidental, unrelated error, remains open — but see above, the
  balance of evidence now leans toward "unrelated."
- Whether a WebSocket message is actually sent to the server when the
  button is clicked (would distinguish "JS never attached a click handler"
  from "click handler ran but something else failed"). Not yet checked —
  the app owner was unable to complete this check ("there's no possibility
  to check this, i cannot click submit answer" — the button itself does
  not respond to clicks at all, so this may not even be checkable via a
  click; watching the Network/WS tab while attempting other interactions,
  e.g. a quiz radio button, might still be informative).

## TL;DR of the underlying bug (background, for context)

In a `learnr::tutorial` with `progressive: true`, quiz `question()` answer
choices and the exercise Run Code/Submit Answer output get bound
(`shiny:bound` fires) but **never complete a single reactive cycle** after
that — no `shiny:recalculating`, `shiny:recalculated`, or `shiny:value`
event ever fires, indefinitely (this was the original diagnostic finding,
from the automation harness — server-side, the output really does appear
stuck this way). The client applies a `.recalculating` CSS class at bind
time (documented Shiny >=1.9.0 behavior) and it's never cleared, which
also leaves the exercise's Run Code/Submit Answer buttons permanently
disabled. In the app owner's real browser, the buttons are reported as not
clickable at all, which is at least consistent with (though not provably
identical to) this same visual symptom.

## The attempted fix (server-side confirmed running correctly on both paths; does not resolve the app owner's symptom)

Full code is in `repro.Rmd`'s setup chunk (`unstick_hidden_outputs()`),
copied verbatim from the real project's `R/tutor_utils.R`. Short version:

Shiny's `session$clientData$output_<id>_hidden` flag was observed, via the
automation harness, to never flip back to `FALSE` for an output bound
while its containing `##` topic was hidden by learnr's `progressive: true`
topic switching — confirmed via a `clientData` dump observer (stuck at
`hidden = TRUE` even while that topic was the one actively on screen) and
a `shiny:bound`/`shiny:recalculating`/`shiny:recalculated`/`shiny:value`
lifecycle listener (`shiny:bound` fires once, nothing else, ever). Since
`shouldSuspend()` reads that flag, it permanently blocks the output's
first real render. `outputOptions(..., suspendWhenHidden = FALSE)` is the
documented override — but it requires the target output to already be
registered, and learnr registers most quiz/exercise sub-outputs *lazily*
(well after session start), so calling it too early throws and crashes the
session. `unstick_hidden_outputs()` works around this by watching
`session$clientData`'s `output_*_hidden` keys on a 200ms timer (they
appear the instant each dynamic output binds) and patching each newly-seen
output exactly once.

This is confirmed (via the debug logging above) to run correctly and patch
every relevant output, in both the working automation-harness environment
and the app owner's failing RStudio/real-browser environment. **Since the
server-side behavior is now confirmed identical in both environments, and
only the app owner's environment fails, the remaining discrepancy is very
likely client-side** — see "New finding" above.

## Reproduction

```r
# Install (versions below; CRAN except gradethis/shinychat which need pak/remotes from GitHub)
rmarkdown::run("repro.Rmd")
```

1. Open the tutorial (any browser).
2. Type any name in the "Welcome!" modal, click "Start Tutorial".
3. Click through to "Installing R and RStudio" (or any topic beyond the
   first) — the quiz question's answer choices should render as real radio
   buttons. If they never appear (empty box, permanently spinning/stuck
   look), the bug is present.
4. Click through to "Wrapping up" — the one graded exercise's **Run Code**
   and **Submit Answer** buttons. Try clicking Submit Answer. If nothing
   ever happens (no feedback message appears, ever, no matter how long you
   wait), the bug is present.

`repro.Rmd` already has `unstick_hidden_outputs()` wired in, with the
debug `message()` logging described above still active (see its setup
chunk) — this is the current best-attempted fix plus its diagnostic
instrumentation, included so a fresh reviewer can see exactly what's been
tried and verify the server-side console output for themselves.

**If you can reproduce this**, the most valuable next things to check, in
order:
1. Open DevTools Console on a fresh page load, and see whether the same
   `TypeError: Cannot read properties of undefined (reading 'startTime')`
   (or any other error) appears.
2. Try the `mathjax: null` YAML test described under "New finding" above.
3. Check the Sources panel / right-click the stack trace to identify where
   the anonymous script actually comes from.

## Environment

- R 4.5.2, Windows 11
- `shiny` 1.14.0
- `learnr` 0.11.6
- `gradethis` 0.2.14 (GitHub: rstudio/gradethis)
- `bslib` 0.12.0
- `shinychat` 0.5.0 (GitHub: posit-dev/shinychat) — **hard-requires
  `shiny >= 1.10.0`** (`loadNamespace()` refuses to load below that,
  confirmed by actually trying, not just reading `DESCRIPTION`)
- `rmarkdown` 2.30, `htmltools` 0.5.9
- `tutorial.storage` is set to `"none"` via `.Rprofile`
- App owner's failing browser: Chrome (recent, exact version not yet
  captured), personal (non-managed) machine, no extensions allowed in
  incognito
- Automation harness's working browser: a Chromium-based automation tool,
  not the app owner's regular browser — exact engine/version not
  characterized in detail

## Diagnostic evidence already gathered

### 1. Lifecycle event log (automation harness)

Instrumented the live app with:

```js
$(document).on(
  'shiny:outputinvalidated shiny:recalculating shiny:recalculated shiny:value shiny:bound shiny:unbound',
  function(e) {
    console.log(e.type, e.target && e.target.id);
  }
);
```

Every stuck output (in the pre-fix state) logs exactly one event, ever:
`shiny:bound`. Waited 30+ seconds past page load with nothing else
happening — no further events for any of them.

### 2. `session$clientData$output_<id>_hidden` never updates to `FALSE` (automation harness, pre-fix)

Added a 1-second `observe()` dumping every `output_*_hidden` value from
`session$clientData` to the R console. For any output on a topic that had
been navigated to and was the currently-active, on-screen topic, the
`hidden` value for that output's clientData entry was still `TRUE`,
indefinitely. This is what motivated `outputOptions(..., suspendWhenHidden
= FALSE)` as the fix.

### 3. Server-side fix confirmed running identically on both the working and failing environments

See the `PATCHED: ...` console log under "The central open question"
above — captured from the app owner's own RStudio session, matches the
automation harness's logs exactly (same output IDs, same order, same
`hidden=TRUE` readings at patch time).

### 4. Client-side JS error, only in the app owner's real browser

See "New finding" above.

### 5. Ruled out

- [rstudio/shiny#4406](https://github.com/rstudio/shiny/issues/4406)
  (`IntersectionObserver` stopping at a boxless ancestor) — the stuck
  output's own `hidden` clientData value was directly observed, ruling
  this out as the specific server-side mechanism.
- `tutorial.storage` setting ("none" vs "auto" vs "client" vs a custom
  per-process `filesystem_storage()`) — tested exhaustively, no storage
  backend changed the automation-harness outcome, and `tutorial.storage`
  is confirmed present in `.Rprofile`.
- Downgrading `shiny` below 1.9.0 fixes the underlying `.recalculating`
  CSS timing but `shinychat` hard-requires `shiny >= 1.10.0`, so no
  version satisfies both.
- RStudio's "Run Document" as the sole differentiator — ruled out by the
  incognito + `Rscript`-launch test (see table above): same failure with
  or without RStudio in the loop.
- A typical browser extension — ruled out via incognito with zero
  extensions allowed, same failure.
- Stale/mismatched package namespaces in a long-running RStudio session —
  ruled out by the debug logging showing `shiny=1.14.0`/`learnr=0.11.6`,
  matching what's installed.

## Not yet tried

The wire-level trace test has been done and its result is known (see
"STATUS" above) — data flow is confirmed working end-to-end through the
DOM; only interactivity is broken. Priorities now:

1. **Directly test whether ANY click is registering at all**, at the most
   basic possible level, in the app owner's failing browser. In DevTools
   Console, run:
   ```js
   document.addEventListener('click', e => console.log('CLICK', e.target), true)
   ```
   then click a quiz radio button (or attempt to). If nothing logs, clicks
   aren't reaching the DOM element at all (something is intercepting or
   blocking them entirely — worth checking `pointer-events` CSS, an
   invisible overlapping element, or a `z-index` issue via the Elements
   panel). If it DOES log, the click reaches the element fine, and the
   problem is specifically that Shiny's own input-binding JS never
   attached its own handler / never registered the input with Shiny's
   reactive system — pointing squarely at the `Shiny.bindAll()` hypothesis
   above.
2. **Check whether `Shiny.bindAll()` (or the specific binding call) is
   being invoked at all**, and whether it throws. In DevTools Console,
   before navigating to the quiz, run `Shiny.unbindAll = ((orig) =>
   function(...args) { console.log('unbindAll', args); return
   orig.apply(this, args); })(Shiny.unbindAll)` and similarly wrap
   `Shiny.bindAll` (exact method names may differ by Shiny version — check
   `Object.keys(Shiny)` first) to log every call and catch any thrown
   error. Compare against the same instrumentation in the automation
   harness (or just check whether it's called at all there) to see if the
   call happens in both places but fails silently in one, or simply never
   happens in the failing one.
3. **Check the `progress`/`binding` message's actual handling client-side.**
   The wire trace confirms the server sends
   `{"progress":{"type":"binding","message":{"id":"install-quiz-answer_container",...}}}`
   — find where Shiny's client JS (`shiny.min.js`, minified but the
   `progress`/`binding` message TYPE string should still be greppable) handles that
   message type, and check via a `debugger;` statement or a wrapped
   console log whether it's reached and completes without error in the
   failing browser.
4. **Try Firefox and/or a genuinely different machine** to separate
   "Chromium-family binding bug" from "machine-specific" — still valuable,
   now specifically in the context of testing whether the binding step
   itself behaves differently, not just whether the bug reproduces at all.
5. **Revisit the `startTime` JS error with this new lens**: does it fire
   at the same moment `Shiny.bindAll()` would be expected to run (i.e. is
   it possible it's thrown *from inside* Shiny's own binding call chain,
   despite not matching any known function name in Shiny's source — worth
   checking Shiny's actual bundled/minified `shiny.min.js` specifically,
   not just the unminified source used for the earlier search, in case
   minification renamed something into what looked like an unrelated
   function)? If the error's stack trace timing lines up with a binding
   attempt, that would tie the two findings together directly.

## Alternatives worth investigating in parallel

After this much investigation without a working fix, it's reasonable to
hedge with alternative approaches alongside continued root-causing, rather
than treating this as a single must-solve blocker. None of these have been
tried yet. Roughly in order of how much they'd salvage of the existing
work:

1. **Test against a real deployment, not just localhost.** The app has
   never actually been deployed anywhere (see `CLAUDE.md` — "Deployment
   target: Not finalized yet"). Every single test of this bug, on both the
   working and failing sides, has been against `127.0.0.1`. It's possible
   this entire bug class is a localhost/dev-server artifact (e.g. tied to
   `learnr`'s `client_storage` vs. `local_storage` split, which is itself
   keyed off `is_localhost()` — see the `tutorial_storage()` gotcha in
   `CLAUDE.md`) that simply would not occur once the app is served from a
   real HTTPS origin (shinyapps.io has a free tier and would be a fast way
   to test this — deploy `module_1.Rmd` there and see if the exact same
   real browser that fails on localhost also fails against the deployed
   URL). If it works once deployed, this whole investigation may be moot
   for real students, who were always going to use a deployed URL, not
   localhost.
2. **Try without `progressive: true` gating**, or with a different gating
   mechanism entirely (e.g. gate topic navigation with a plain `observeEvent`-driven
   custom UI instead of relying on learnr's built-in topic show/hide).
   Every diagnostic finding in this document traces back to learnr's
   `progressive`-driven topic hiding/showing interacting badly with
   Shiny's output-suspension machinery. If the pedagogical requirement
   (must complete a section before moving on) can be met a different way,
   it may be possible to sidestep the entire bug class rather than fix it.
3. **Try a plain, learnr-free Shiny app for the exercises/quizzes**,
   writing the question/exercise UI by hand (a `radioButtons()` +
   `actionButton()` + `renderUI()` for feedback, driven entirely by
   ordinary, fully-controlled Shiny code) instead of relying on `learnr::question()`
   and `exercise=TRUE` chunks. More work upfront (loses learnr's
   built-in exercise sandboxing, gradethis integration point would need
   rebuilding), but removes the entire layer of learnr internals
   (`question_module_server`, `exercise_server_chunk`,
   `shouldSuspend()`/`outputOptions()` interactions) that this whole
   investigation has been chasing.
4. **Consider Posit's `webr`-based in-browser R** (R compiled to
   WebAssembly, running entirely client-side, no Shiny server round-trip
   at all) for the exercise-running piece specifically. This is a newer,
   actively-developed approach specifically aimed at exactly this kind of
   interactive-R-teaching use case, and would eliminate the entire
   category of server/client reactive-synchronization bugs this
   investigation has been dealing with, at the cost of a bigger rewrite
   and losing server-side features that currently depend on a live R
   session (the Postgres logging, the ellmer/shinychat tutor bot as
   currently built).
5. Check whether this exact bug (or something matching its symptoms) is
   already a known, tracked issue against `rstudio/learnr` or
   `rstudio/shiny` — a search wasn't done in this round of the
   investigation. If a maintainer has already diagnosed something matching
   "progressive topic switching + Shiny 1.9+ recalculating-forever," there
   may already be a known fix, workaround, or version pin.

## Files in this folder

- `repro.Rmd` — the standalone reproduction, including the current
  best-attempted fix and its debug logging. Needs `learnr`, `gradethis`,
  `shiny`, `bslib`, `shinychat` installed; no database, no API keys, no
  other project files.
- `repro_no_mathjax.Rmd` — identical to `repro.Rmd` except `mathjax: null`
  in the YAML, to test the MathJax/external-CDN hypothesis (see "New
  finding" above). Already running at http://127.0.0.1:7413 as of this
  writing; re-launch with
  `rmarkdown::run("repro_no_mathjax.Rmd", shiny_args = list(port = 7413))`
  if that process has since been stopped.
- `diagnose_session.R` — package-version/session diagnostic script (used
  to rule out stale namespaces; can be re-run any time to double check).
- `run_repro_trace.R` — launches `repro.Rmd` on port 7414 with
  `options(shiny.trace = "send")` set, so every outgoing server→browser
  message prints to the R console. Already run once by the app owner in
  their failing environment — see `trace_output_from_app_owner.txt` for
  the captured result.
- `trace_output_from_app_owner.txt` — the actual wire-trace output
  captured from the app owner's own failing browser via
  `run_repro_trace.R`. This is the evidence behind the "STATUS" section's
  conclusion at the top of this document — confirms the server-side
  render/send cycle completes correctly (including real quiz HTML with
  radio inputs, not just placeholders) even in the failing environment.
