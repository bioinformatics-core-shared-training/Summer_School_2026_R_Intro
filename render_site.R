#!/usr/bin/env Rscript

# The session 8 exercise report is a Quarto document, so it is not rendered by
# rmarkdown::render_site(). Render it first: render_site() then copies the
# resulting session8_exercise.html (and its _files directory) into docs/ along
# with the other non-Rmd resources.
if (nzchar(Sys.which("quarto"))) {
    system2("quarto", c("render", "session8_exercise.qmd"))
} else {
    warning("quarto not found on PATH - session8_exercise.html will not be ",
            "rebuilt. See https://quarto.org/docs/get-started/")
}

rmarkdown::render_site()
