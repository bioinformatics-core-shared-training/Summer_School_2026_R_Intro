#!/usr/bin/env Rscript

# Build a PRINTABLE version of the instructor notes.
#
#     Rscript _MakeInstructorPDF.R [session1 session2 ...]
#
# The web instructor notes assume a second screen. This produces the fallback
# for when there isn't one: a two-column A4 booklet at 10pt, one PDF per
# session plus a combined instructor_notes.pdf to print in one go.
#
# It does NOT re-ask the agent anything. It reuses the body of each committed
# instructor_sessionN.qmd verbatim, so the print and screen versions can never
# say different things about the material. What differs is what is shown:
#
#   1. NO CHUNK OUTPUT EXCEPT PLOTS. The web version prints tibbles and console
#      output; the printed one shows the code and the plots and nothing else.
#      This is by far the biggest saving - printed output was over a third of
#      the page count - and it is a reasonable trade for paper, where you are
#      reading the notes to remember what to type, not to check a value.
#
#      Note the casualty: a chunk with `echo: false` exists only for its
#      output, so with output hidden it renders nothing at all. Six chunks are
#      in that position, including session 1's comparison-operator and
#      logical-operator reference tables.
#
#      Display-only fences in the body - the `> 23 + 45` transcripts in session
#      1 - are not chunk output and are unaffected.
#   2. FIGURE SIZE. Drawn to fit one column, then displayed at half that. See
#      FIG_DISPLAY.
#   3. HTML-ONLY OUTPUT. An htmlwidget cannot be printed. knitr's fallback is
#      to screenshot it with webshot2, which is not installed here - so those
#      chunks are shown but not run, with a note saying so. Session 8's `DT`
#      and `kableExtra` sections are the ones affected, and both are about
#      styling web output, so there is nothing to lose on paper.
#
# PRINT_WIDTH still re-runs the code at a narrower console than the web build's
# 80 columns. That is inert while output is hidden, and kept because
# re-enabling output is a one-word change.
#
# WHY TYPST, not LaTeX. Quarto ships Typst, so this needs nothing installed -
# which matters, because this machine's TeX has no usable base fonts and both
# pdflatex and lualatex fail on a bare two-column document. Typst also takes
# the mixed Unicode in this material (the tibble footer's arrows and times
# signs, the middots in the nav strip) without a font dance, and it wraps long
# code lines instead of running them off the page.

# Console columns. A tibble header that overruns by even one character wraps
# and takes its column alignment with it - which is most of what makes a
# printed tibble readable - so this wants a couple of characters of headroom.
#
# Measured at CODE_SIZE and PAGE_MARGIN with a ruler page appended to a real
# build (see --keep): 56 characters fit in one column, 58 wrap. At the previous
# 12mm margin it was about 53, so the extra 14mm of page width buys four
# characters.
#
# THE TRAP, if you re-measure after changing CODE_SIZE or PAGE_MARGIN: the
# ruler lines must contain SPACES. A line of unbroken characters has no break
# opportunity, so Typst lets it overflow the column silently instead of
# wrapping - it looks like it fits, and a first attempt at this measurement
# read 68 characters for a column that actually holds 56.
PRINT_WIDTH <- 54
CODE_SIZE   <- "7.4pt"

# 5mm, taken from the Summer School certificate build, which pinned it after
# checking what office printers can actually image: HP and Canon lasers stop
# at about 4.23mm from the A4 edge, Brother at about 4mm, inkjets vary more.
# See PRINT_MARGIN in Cambridge_UCI_Summer_School_2026/certificate/certdesign.py.
# Worth knowing what this costs: at 5mm there is nowhere to hold the sheet
# without a thumb over the text, and nowhere to staple. Widen it if these are
# going to be bound.
PAGE_MARGIN  <- "5mm"
FOLIO_MARGIN <- "9mm"
BODY_SIZE   <- "9pt"
# Plots are DRAWN at FIG_WIDTH x FIG_HEIGHT and DISPLAYED at FIG_DISPLAY, half
# that width. Drawing at full size and scaling down on the page, rather than
# drawing small, is what keeps a faceted plot's panels from collapsing and its
# labels from colliding - and a 2x image stays sharp in print. The cost is that
# all the plot text is set at half size, which is legible on paper but not
# something to read values off.
FIG_WIDTH   <- 3.3  # inches, a little under one column
FIG_HEIGHT  <- 2.0
FIG_DISPLAY <- FIG_WIDTH / 2
COMBINED    <- "instructor_notes.pdf"

source("_instructor_common.R")

stopifnot("quarto is not on PATH" = nzchar(Sys.which("quarto")),
          "run from the project root" = file.exists("_instructor_notes.yml"))

argv <- commandArgs(trailingOnly = TRUE)
# --keep leaves the generated _print_<page>.qmd in place after a SUCCESSFUL
# render. Failures keep it regardless. Useful for measuring the real column
# fit: append a page of lines of known length and re-render by hand.
KEEP  <- "--keep" %in% argv
cfg   <- yaml::read_yaml("_instructor_notes.yml")
pages <- setdiff(argv, "--keep")
if (!length(pages)) pages <- cfg$pages

# The print .qmd is written into the PROJECT ROOT, not a scratch directory,
# under a leading-underscore name. That is not laziness:
#
#   * Chunks must resolve read_csv("data/...") and assets/imgs/... exactly as
#     the web build does. Quarto executes with the working directory set to
#     the input file's own directory, so rendering from anywhere else breaks
#     every data path.
#   * A leading underscore is the same convention that keeps _Brief_Recap.qmd
#     unpublished: Quarto's project input discovery ignores "**/_*", so these
#     never become website inputs, while `quarto render` on an explicit path
#     still works.
#
# They are removed on success and LEFT BEHIND on failure, which is the whole
# reason this is not in tempdir() - the first version put them there, R
# deleted the directory on exit, and the render error went with it.
OUT_DIR <- "print"
dir.create(OUT_DIR, showWarnings = FALSE)

# ==========================================================================
#    PRINT PRESENTATION
# ==========================================================================

# Typst styling, and it matters WHERE each half goes.
#
# Quarto's typst template hardcodes `set par(justify: true)` inside the
# function that wraps the document body, so anything in include-in-header is
# overridden by it. Justified monospace is not a cosmetic problem: a code line
# too long for the column wraps, and the wrapped fragment is then stretched to
# both margins, so `options(width = 54,` arrives as
# `options(width    =    54,`. Putting the paragraph settings in
# include-before-body instead lands them INSIDE that scope, where they win.
# Text sizes are not affected by this and stay in the header.
typst_header <- function() {
    c(paste0("#show raw: set text(size: ", CODE_SIZE, ")"),
      "#show heading: set text(fill: rgb(\"#00007e\"))",
      "#show heading.where(level: 1): set text(size: 11.5pt)",
      "#show heading.where(level: 2): set text(size: 10.5pt)",
      "#show heading.where(level: 3): set text(size: 10pt)")
}

# Unjustified throughout, not only in code: in a 55-character column
# justification opens rivers of whitespace in the prose too.
typst_before_body <- function() {
    c("#set par(justify: false, leading: 0.55em)",
      "#set block(spacing: 0.62em)")
}

front_matter <- function(page) {
    c("---",
      paste0('title: "', page_title(page), '"'),
      'subtitle: "Instructor notes"',
      "format:",
      "  typst:",
      "    columns: 2",
      "    papersize: a4",
      "    margin:",
      paste0("      left: ", PAGE_MARGIN),
      paste0("      right: ", PAGE_MARGIN),
      paste0("      top: ", PAGE_MARGIN),
      # The folio lives in the bottom margin, so that one cannot go to 5mm
      # without the page number landing outside the printable area.
      paste0("      bottom: ", FOLIO_MARGIN),
      paste0("    fontsize: ", BODY_SIZE),
      "    # Backstop. HTML_ONLY below neutralises the chunks we know about so",
      "    # that each gets a visible note in its place. This stops an",
      "    # unrecognised one from failing the whole build instead: its output",
      "    # is silently omitted, which is worse than a note but far better",
      "    # than no PDF at all.",
      "    prefer-html: true",
      "    include-in-header:",
      "      text: |",
      paste0("        ", typst_header()),
      "    include-before-body:",
      "      text: |",
      paste0("        ", typst_before_body()),
      "---")
}

# The print counterpart of the web setup chunk. Same two-row truncation, but a
# narrower console and no Unicode: cli's arrows and times signs are fine in
# Typst, yet plain ASCII survives any printer and any photocopier.
setup_chunk <- function() {
    c("```{r}",
      "#| label: print-setup",
      "#| include: false",
      "# These four are INERT while results = \"hide\" below suppresses printed",
      "# output. They are kept because re-enabling output is a one-word change,",
      "# and without them a printed tibble is 20 lines instead of 6.",
      paste0("options(width = ", PRINT_WIDTH, ", cli.width = ", PRINT_WIDTH, ","),
      "        tibble.print_min = 2, tibble.print_max = 2,",
      "        tibble.max_extra_cols = 1, cli.unicode = FALSE)",
      "# NOT inert: this one fixes the reference tables restored below.",
      "# kable's default pipe format makes pandoc derive relative column",
      "# widths from the source table, so session 1's logical-operator table -",
      "# one cell of which is a 180-character sentence - came out as",
      "# columns: (4.5%, 4%, 91.5%). Typst does not shrink text to fit a track,",
      "# so the \"Operator\" and \"Meaning\" headers overprinted their",
      "# neighbours and the table was unreadable. The simple format emits",
      "# columns: 3 instead, and Typst lays it out automatically.",
      "options(knitr.table.format = \"simple\")",
      "# Inert for the same reason as the block above, and kept for the same",
      "# reason.",
      "registerS3method(\"knit_print\", \"data.frame\", function(x, ...) {",
      "    if (inherits(x, \"tbl_df\")) return(knitr::normal_print(x))",
      "    knitr::normal_print(utils::head(x, 2L))",
      "}, envir = asNamespace(\"knitr\"))",
      paste0("knitr::opts_chunk$set(fig.width = ", FIG_WIDTH,
             ", fig.height = ", FIG_HEIGHT, ","),
      paste0("                      out.width = \"", FIG_DISPLAY, "in\","),
      "                      # Everything except plots is suppressed. results",
      "                      # hides printed values, message/warning the rest;",
      "                      # fig.show is untouched, so plots still appear.",
      "                      results = \"hide\", message = FALSE,",
      "                      warning = FALSE)",
      "```")
}

# ==========================================================================
#    BODY TRANSFORMS
#
#    The body is the agent's and is not rewritten - but three constructs in it
#    mean something only on a web page.
# ==========================================================================

# The strip of links to the other pages. Meaningless on paper.
drop_nav <- function(lines) {
    nav <- grep("^:::+ *\\{\\.instructor-nav\\}", lines)
    if (!length(nav)) return(lines)
    close <- grep("^:::+ *$", lines)
    close <- close[close > nav[[1]]]
    if (!length(close)) return(lines)
    lines[-(nav[[1]]:close[[1]])]
}

# ::: {.showimg} is a flex row on the web - thumbnail left, cue right. On paper
# it becomes the thumbnail at a fixed width with the cue under it. The cue is
# the point: it says which diagram to put on the projector.
convert_showimg <- function(lines) {
    out <- character()
    i <- 1L
    while (i <= length(lines)) {
        if (grepl("^:::+ *\\{\\.showimg\\}", lines[[i]])) {
            j <- i + 1L
            while (j <= length(lines) && !grepl("^:::+ *$", lines[[j]])) j <- j + 1L
            inner <- lines[(i + 1L):(j - 1L)]
            img <- grep("^!\\[", inner, value = TRUE)
            cue <- grep("^Show ", inner, value = TRUE)
            if (length(img))
                out <- c(out, sub("\\)\\s*$", "){width=1.1in}", img[[1]]), "")
            if (length(cue)) out <- c(out, paste0("**", cue[[1]], "**"), "")
            i <- j + 1L
            next
        }
        out <- c(out, lines[[i]])
        i <- i + 1L
    }
    out
}

# Output that exists only as HTML. Running these aborts a Typst render outright
# ("Functions that produce HTML output found in document targeting typst
# output") unless webshot2 is installed to screenshot them, and it is not.
#
# Two families, both from session 8, and both are ABOUT styling web output - so
# showing the code with a note is the honest result rather than a loss:
#   * DT::datatable  an interactive table; there is nothing to print
#   * kableExtra     kbl() piped into kable_styling(bootstrap_options = ...)
#                    is HTML by construction
HTML_ONLY <- "datatable\\(|DT::|kable_styling|kbl\\("

neutralise_html_only <- function(lines) {
    fence <- grep("^```\\{r\\}", lines)
    for (f in rev(fence)) {
        close <- grep("^```\\s*$", lines)
        close <- close[close > f]
        if (!length(close)) next
        body <- lines[(f + 1L):(close[[1]] - 1L)]
        if (!any(grepl(HTML_ONLY, body))) next
        lines <- append(lines, "#| eval: false", after = f)
        lines <- append(lines,
                        c("", "*(HTML-only output -- see the web version)*"),
                        after = close[[1]] + 1L)
    }
    lines
}

# Chunks whose whole purpose is to render a static reference table. Suppressing
# every output turns these into nothing at all - they are `echo: false`, so with
# the output gone there is no code shown either, and session 1 silently lost its
# comparison-operator and logical-operator tables.
#
# Identified by what they DO, not by `echo: false`. A blanket "echo: false keeps
# its output" rule would also restore session 8's sessionInfo chunk, whose long
# dump of the R environment is exactly what does not belong on paper. Session
# 8's other two `echo: false` chunks draw plots, which were never suppressed.
#
# `kable(` is safe against the neighbouring kableExtra calls: `kbl(` and
# `kable_styling(` do not contain it, so the HTML-only chunks stay neutralised.
TABLE_OUTPUT <- "kable\\("

restore_table_output <- function(lines) {
    for (f in rev(grep("^```\\{r\\}", lines))) {
        close <- grep("^```\\s*$", lines)
        close <- close[close > f]
        if (!length(close)) next
        blk <- lines[(f + 1L):(close[[1]] - 1L)]
        if (!any(grepl(TABLE_OUTPUT, blk))) next
        # Nothing to restore if the chunk is not being run anyway.
        if (any(grepl("^#\\|\\s*eval:\\s*false", blk))) next
        lines <- append(lines, "#| results: markup", after = f)
    }
    lines
}

# Drop columns from a generated reference table, per print_table_drop in
# _instructor_notes.yml.
#
# This is the ONE place the driver touches chunk code rather than chunk options,
# and it is deliberately fenced in: it acts only on chunks that are
# `echo: false`, whose code is never shown. So the printed page differs from the
# web page in what its table contains, but no code is ever displayed that
# differs from the student page. A visible chunk gets a warning and is left
# alone.
#
# The line is injected immediately before the kable() call, subsetting whatever
# object kable was given.
drop_table_columns <- function(lines, page) {
    spec <- cfg$print_table_drop
    if (is.null(spec)) return(lines)

    for (f in rev(grep("^```\\{r\\}", lines))) {
        close <- grep("^```\\s*$", lines)
        close <- close[close > f]
        if (!length(close)) next
        close <- close[[1]]
        blk <- lines[(f + 1L):(close - 1L)]

        lab <- grep("^#\\|\\s*label:", blk, value = TRUE)
        if (!length(lab)) next
        lab <- trimws(sub("^#\\|\\s*label:", "", lab[[1]]))
        cols <- spec[[lab]]
        if (is.null(cols)) next

        if (!any(grepl("^#\\|\\s*echo:\\s*false", blk))) {
            warning(page, ": ", lab, " is not echo: false, so dropping a column",
                    " would show code that differs from the student page.",
                    " Left alone.", call. = FALSE, immediate. = TRUE)
            next
        }

        at <- grep("kable\\(", blk)
        if (!length(at)) next
        obj <- sub(".*kable\\(\\s*", "", blk[[at[[length(at)]]]])
        obj <- trimws(sub("[,)].*$", "", obj))
        if (!grepl("^[A-Za-z.][A-Za-z0-9._]*$", obj)) {
            warning(page, ": cannot tell what object ", lab, " passes to kable",
                    " (got \"", obj, "\"). Left alone.",
                    call. = FALSE, immediate. = TRUE)
            next
        }

        inject <- paste0(obj, " <- ", obj, "[, setdiff(names(", obj, "), c(",
                         paste0("\"", cols, "\"", collapse = ", "),
                         ")), drop = FALSE]")
        lines <- append(lines, inject, after = f + at[[length(at)]] - 1L)
        message("  dropped ", paste(cols, collapse = ", "), " from ", lab)
    }
    lines
}

# ==========================================================================
#    BUILD
# ==========================================================================

built <- character()

pdf_pages <- function(f) {
    info <- system2("pdfinfo", c(shQuote(f)), stdout = TRUE, stderr = FALSE)
    hit <- grep("^Pages:", info)
    if (!length(hit)) return(NA_integer_)
    as.integer(trimws(sub("^Pages:", "", info[[hit[[1]]]])))
}

for (page in pages) {
    qmd <- paste0("instructor_", page, ".qmd")
    if (!file.exists(qmd)) {
        warning("no instructor notes for ", page,
                " - run _MakeInstructorNotes.R first",
                call. = FALSE, immediate. = TRUE)
        next
    }
    parts <- split_page(qmd)
    if (is.null(parts)) {
        warning("cannot find the body of ", qmd, call. = FALSE,
                immediate. = TRUE)
        next
    }

    body <- strsplit(parts$body, "\n", fixed = TRUE)[[1]]
    body <- drop_table_columns(
                restore_table_output(
                    neutralise_html_only(convert_showimg(drop_nav(body)))),
                page)

    stem <- paste0("_print_", page)
    src  <- paste0(stem, ".qmd")
    writeLines(c(front_matter(page), "", setup_chunk(), "", body), src)

    message("rendering ", page, " ...")
    status <- system2("quarto", c("render", shQuote(src), "--to", "typst"),
                      stdout = FALSE, stderr = FALSE)
    pdf <- paste0(stem, ".pdf")

    if (status != 0L || !file.exists(pdf)) {
        warning(page, ": render failed. The generated source has been left at ",
                src, " - render it by hand to see the error.",
                call. = FALSE, immediate. = TRUE)
        next
    }

    dest <- file.path(OUT_DIR, paste0("instructor_", page, ".pdf"))
    file.rename(pdf, dest)
    built <- c(built, dest)
    message("  ", dest, " (", pdf_pages(dest), " pages)")

    # Clean up on success only. The _files directory holds this build's
    # figures, which are already embedded in the PDF.
    if (!KEEP) unlink(c(src, paste0(stem, ".typ")))
    unlink(paste0(stem, "_files"), recursive = TRUE)
}

if (!length(built)) {
    message("nothing built")
} else {
    total <- sum(vapply(built, pdf_pages, integer(1)), na.rm = TRUE)
    if (length(built) > 1L && nzchar(Sys.which("pdfunite"))) {
        combined <- file.path(OUT_DIR, COMBINED)
        system2("pdfunite", c(shQuote(built), shQuote(combined)))
        message("\n", combined, " - the one to print (", pdf_pages(combined),
                " pages)")
    }
    message(length(built), " session(s), ", total, " pages")
}
