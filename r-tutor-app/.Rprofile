# Disables learnr's local-filesystem exercise/progress cache for ANY
# localhost session of this project -- both RStudio's "Run Document" button
# and R/run_tutorial.R go through this.
#
# Why: learnr's default `tutorial.storage = "auto"` persists exercise
# submissions and section-viewed state to disk, keyed by OS username +
# tutorial path (see AppData/Local/R/learnr/tutorial/storage/<username>/),
# whenever the tutorial is served on localhost -- which every local dev/test
# session is. That means every local session (yours, Claude's, an old one
# from days ago) shares the exact same on-disk state for a given module,
# regardless of browser, browser tab, or which R process is running it. A
# submission or reset from one session can silently "restore" into another,
# which looks exactly like a broken/unresponsive Run Code, Submit Answer, or
# Start Over button (the editor shows stale code/output and nothing you
# click seems to do anything) even though the app itself is working fine.
#
# This is purely a local-dev-convenience feature to begin with -- once
# actually deployed (not on localhost), learnr automatically switches to
# client_storage (per-browser, not per-OS-user) instead, so real students
# are unaffected by this either way; disabling the local filesystem variant
# here costs nothing except "R remembers where you left off between R
# restarts on your own machine" during local testing, which was actively
# causing the underlying bug it was meant to be a nicety for.
#
# If local testing ever needs a clean slate for a reason unrelated to this
# option (e.g. seeing what a brand-new student sees), the same cache lives
# at AppData/Local/R/learnr/tutorial/storage/<username>/ and can be deleted
# directly.
options(tutorial.storage = "none")
