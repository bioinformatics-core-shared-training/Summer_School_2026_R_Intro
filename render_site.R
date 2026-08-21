#!/usr/bin/env Rscript

# Build the site. Both steps are Quarto now; see _quarto.yml.
#
# Two renders are needed, and the order matters:
#
#   1. The website itself. `quarto render` cleans docs/ before writing, so it
#      has to run FIRST - otherwise it would delete the exercise report that
#      step 2 produces.
#   2. session8_exercise.qmd, the standalone report that session 8 asks
#      students to reproduce. It is excluded from `project: render` precisely so
#      that it does not inherit the site navbar, theme or footer: rendering it
#      by name emits it outside the project context, self-contained, which is
#      what makes it a fair target for the exercise. `project: resources` then
#      copies both it and its source into docs/.

stopifnot("quarto is not on PATH - see https://quarto.org/docs/get-started/" =
              nzchar(Sys.which("quarto")))

run <- function(...) {
    status <- system2("quarto", c(...))
    if (status != 0L)
        stop("quarto ", paste(..., collapse = " "), " failed (status ", status, ")")
}

run("render")
run("render", "session8_exercise.qmd")

# The report is rendered next to its source; publish it at the docs/ root,
# where the links in session8.qmd expect to find it.
file.copy(c("session8_exercise.html", "session8_exercise.qmd"),
          "docs", overwrite = TRUE)

message("Site built into docs/")
