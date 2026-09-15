# Run this in the RStudio console that produces the broken app (i.e. the
# same console you'd click "Run Document" from), BEFORE clicking Run
# Document. See debug_recalculating_bug/HANDOFF.md for context.

pkgs <- c(
  "shiny", "learnr", "bslib",
  "shinychat", "rmarkdown", "htmltools"
)

data.frame(
  package = pkgs,
  installed = vapply(
    pkgs,
    function(x) as.character(packageVersion(x)),
    character(1)
  ),
  loaded = vapply(
    pkgs,
    function(x) {
      if (isNamespaceLoaded(x))
        as.character(getNamespaceVersion(x))
      else
        "<not loaded>"
    },
    character(1)
  )
)

cat("\nPID:", Sys.getpid())
cat("\nWD:", getwd())
cat("\ntutorial.storage:", getOption("tutorial.storage"))
cat("\nRStudio:", Sys.getenv("RSTUDIO"))
cat("\n\n.libPaths():\n")
print(.libPaths())
