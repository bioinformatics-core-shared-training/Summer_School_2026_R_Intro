#!/usr/bin/env Rscript

# Generate the instructor notes: pared-back versions of the session pages for
# the instructor to keep on a second screen while live coding. Headings, code,
# output, and a terse reminder of the critical teaching points.
#
#     Rscript _MakeInstructorNotes.R [--full] [session1 session2 ...]
#
# Each page is written by handing the student page to the claude CLI with the
# editorial brief in _instructor_prompt.md. That brief is the thing to edit when
# the output is not what you wanted; this script only decides WHAT to ask for
# and then checks the answer.
#
# An earlier deterministic implementation was replaced by this one. It could
# keep headings and code faithfully but could not judge prose, so every long
# paragraph needed a summary written by hand - 325 of them across sessions 2-8.
#
# HOW IT RUNS
#
#   * NOT a Quarto pre-render step. Output is non-deterministic and costs money,
#     so it must never re-run on `quarto render` or `quarto preview`. Run it by
#     hand when a session page or the prompt changes.
#   * Its output IS committed, which is what lets a clean checkout render, and
#     what makes a prompt iteration reviewable - `git diff` on the generated
#     page shows exactly what the prompt change did.
#   * The agent gets NO TOOLS and writes no files. The source goes into the
#     prompt inline and its stdout is captured. Fewer moving parts than letting
#     it Read/Write, no permission prompts, no nested agent loose in the repo,
#     and cheaper - no tool round-trips.
#
# THREE MODES, chosen per page from the provenance stamp in the existing file
#
#   full      No existing page, or --full, or the fallbacks below.
#             Sends the whole source. One API call.
#   refresh   The source's md5 matches the stamp: nothing has changed. The
#             agent's body is kept BYTE FOR BYTE and only the wrapper is
#             rewritten - front matter, setup chunk, nav strip, stamp. NO API
#             call, so a change to any of those costs nothing across all eight
#             pages.
#   update    The source has changed. Recovers the old source from the stamped
#             commit, diffs it, and sends the agent its own previous body plus
#             that diff (_instructor_prompt_update.md).
#
#             Falls back to `full` when the old source cannot be trusted: the
#             commit is unknown (rebased, shallow clone), or the tree was dirty
#             when the page was generated - in which case the committed file is
#             not what was actually used and the diff would be a lie - or the
#             diff is so large that a rewrite is the honest answer.
#
# What `update` buys is mostly STABILITY, not tokens: the agent still emits a
# whole body, but seeded with its own previous output it keeps its existing
# wording everywhere the source did not change. That is what stops a one-line
# edit to a session page from churning the whole generated file, and it is what
# makes a committed generated file worth reviewing. The token saving is in
# `refresh`, where untouched pages cost nothing at all.
#
# The FILE LAYOUT this depends on:
#
#     ---
#     front matter          <- written here, never by the agent
#     ---
#     <!-- GENERATED ... -->
#     <!-- instructor-notes: source=... md5=... commit=... -->
#     ```{r} instructor-setup ... ```
#     ::: {.instructor-nav} ... :::
#     <!-- BODY -->
#     ... the agent's body ...
#
# Everything above the BODY sentinel is ours and is regenerated every run;
# everything below it is the agent's and is only touched when the source has
# changed. The sentinel is also why the setup chunk cannot trip the
# chunk-fidelity check, which only ever sees the body.

NOTES_FILE   <- "_instructor_notes.yml"
PROMPT_FULL  <- "_instructor_prompt.md"
PROMPT_UPDATE <- "_instructor_prompt_update.md"

MODEL  <- Sys.getenv("INSTRUCTOR_MODEL",  "opus")
EFFORT <- Sys.getenv("INSTRUCTOR_EFFORT", "high")

# Everything above this marker in a prompt file is documentation for whoever
# edits it, and is not sent.
PROMPT_MARKER <- "<!-- PROMPT BEGINS -->"

# Above this share of the source changing, an update is a rewrite in all but
# name, and seeding the agent with a stale body helps nobody.
REWRITE_THRESHOLD <- 0.5

# The file layout of a generated page, and how to take it apart again, are
# shared with _MakeInstructorPDF.R.
source("_instructor_common.R")

for (pkg in c("yaml", "jsonlite"))
    stopifnot("required package missing" = requireNamespace(pkg, quietly = TRUE))
stopifnot("claude is not on PATH" = nzchar(Sys.which("claude")),
          "run from the project root" = file.exists(PROMPT_FULL) &&
                                        file.exists(NOTES_FILE))

argv <- commandArgs(trailingOnly = TRUE)
FORCE_FULL <- "--full" %in% argv
# Migration aid, for pages generated before the provenance stamp existed:
# accept the body that is there as current and stamp it against the source as
# it stands, with no API call. Only correct when you know the source has not
# moved since the page was written - which is why it is not the default.
ADOPT <- "--adopt" %in% argv
pages <- setdiff(argv, c("--full", "--adopt"))

cfg <- yaml::read_yaml(NOTES_FILE)
if (!length(pages)) pages <- cfg$pages

# ==========================================================================
#    PROVENANCE
#
#    The stamp is what makes the three modes possible. md5 answers "has the
#    source changed?" without needing git at all; commit is what makes the
#    change recoverable as a diff.
# ==========================================================================

git <- function(...) {
    out <- suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = FALSE))
    if (!is.null(attr(out, "status")) && attr(out, "status") != 0L) NULL else out
}

source_md5 <- function(path) unname(tools::md5sum(path))

head_commit <- function() {
    sha <- git("rev-parse", "HEAD")
    if (is.null(sha)) NA_character_ else sha[[1]]
}

# Dirty specifically for THIS file: a stamp saying dirty=no must mean that the
# stamped commit really does hold the bytes the agent was shown.
is_dirty <- function(path) {
    out <- git("status", "--porcelain", "--", path)
    is.null(out) || any(nzchar(out))
}

stamp_line <- function(page) {
    src <- paste0(page, ".qmd")
    paste0("<!-- instructor-notes: source=", src,
           " md5=", source_md5(src),
           " commit=", head_commit(),
           " dirty=", if (is_dirty(src)) "yes" else "no",
           " model=", MODEL, " effort=", EFFORT, " -->")
}


# ==========================================================================
#    THE PROMPT
# ==========================================================================

# Whether an image is cued or dropped is a decision, not a judgement, so it is
# stated as fact in _instructor_notes.yml and interpolated here rather than
# left to the agent. The PDF build reads the same map.
image_rules <- function(page) {
    src <- readLines(paste0(page, ".qmd"), warn = FALSE)
    used <- unique(unlist(regmatches(
        src, gregexpr("assets/imgs/[^\"')} ]+\\.(png|svg|jpg|jpeg|gif)", src))))
    if (!length(used))
        return("This page contains no images.")

    names <- cfg$images
    lines <- vapply(used, function(p) {
        label <- names[[p]]
        if (is.null(label))
            paste0("* `", p, "` -- give it a cue, naming it sensibly.")
        else if (identical(label, "drop"))
            paste0("* `", p, "` -- **drop it**. Shown live, not on the page.")
        else
            paste0("* `", p, "` -- cue it, named \"", label, "\".")
    }, character(1), USE.NAMES = FALSE)

    paste(c("Each image on this page is handled as follows. These are decisions",
            "already taken; do not second-guess them.",
            "", lines), collapse = "\n")
}

read_prompt <- function(path) {
    tmpl <- paste(readLines(path, warn = FALSE), collapse = "\n")
    at <- regexpr(PROMPT_MARKER, tmpl, fixed = TRUE)
    if (at > 0) substring(tmpl, at + nchar(PROMPT_MARKER)) else tmpl
}

# sub() with fixed = TRUE throughout, never gsub with a regex: the source is
# full of backslashes and braces that would be read as backreferences.
fill <- function(tmpl, key, value) sub(key, value, tmpl, fixed = TRUE)

build_prompt_full <- function(page) {
    tmpl <- read_prompt(PROMPT_FULL)
    tmpl <- fill(tmpl, "{{IMAGE_RULES}}", image_rules(page))
    tmpl <- fill(tmpl, "{{SOURCE_PATH}}", paste0(page, ".qmd"))
    fill(tmpl, "{{SOURCE}}",
         paste(readLines(paste0(page, ".qmd"), warn = FALSE), collapse = "\n"))
}

build_prompt_update <- function(page, previous, diff) {
    tmpl <- read_prompt(PROMPT_UPDATE)
    tmpl <- fill(tmpl, "{{IMAGE_RULES}}", image_rules(page))
    tmpl <- fill(tmpl, "{{SOURCE_PATH}}", paste0(page, ".qmd"))
    tmpl <- fill(tmpl, "{{DIFF}}", diff)
    fill(tmpl, "{{PREVIOUS}}", previous)
}

# The diff of a student page between the stamped commit and now, plus how much
# of the file it touches. NULL means "cannot be trusted" - see the fallbacks in
# the header.
source_diff <- function(page, stamp) {
    src <- paste0(page, ".qmd")
    if (is.null(stamp) || is.null(stamp$commit) || is.na(stamp$commit) ||
        identical(stamp$commit, "NA"))
        return(NULL)
    if (identical(stamp$dirty, "yes"))
        return(NULL)                       # stamped commit != what was shown
    if (is.null(git("cat-file", "-e", paste0(stamp$commit, ":", src))))
        return(NULL)                       # rebased away, or shallow clone
    d <- git("diff", "--unified=6", stamp$commit, "--", src)
    if (is.null(d) || !length(d)) return(NULL)
    changed <- sum(grepl("^[+-][^+-]", d))
    list(text = paste(d, collapse = "\n"),
         changed = changed,
         share = changed / max(1L, length(readLines(src, warn = FALSE))))
}

# ==========================================================================
#    THE CALL
# ==========================================================================

ask_claude <- function(prompt) {
    pf <- tempfile(fileext = ".txt")
    on.exit(unlink(pf))
    writeLines(prompt, pf)

    started <- Sys.time()
    out <- system2("claude",
                   c("-p", "--model", MODEL, "--effort", EFFORT,
                     "--tools", shQuote(""), "--output-format", "json"),
                   stdin = pf, stdout = TRUE, stderr = "")
    took <- as.numeric(difftime(Sys.time(), started, units = "secs"))

    if (!length(out))
        stop("claude returned nothing")
    res <- jsonlite::fromJSON(paste(out, collapse = "\n"))
    if (!is.null(res$is_error) && isTRUE(res$is_error))
        stop("claude reported an error: ", res$result)
    list(body = res$result,
         cost = res$total_cost_usd,
         secs = took)
}

# ==========================================================================
#    VERIFICATION
#
#    The comparison is only worth anything if the output can be trusted, so
#    the two things that would quietly ruin a teaching crib sheet - altered R
#    code and altered headings - are checked mechanically and are fatal.
# ==========================================================================

# Everything before the closing "---" of the YAML header. session8's header
# carries a long authoring note whose lines start with "# ", and counting those
# as headings inflated the source count and reported every one of them as a
# dropped heading.
drop_yaml <- function(lines) {
    if (!length(lines) || !grepl("^---\\s*$", lines[[1]])) return(lines)
    ends <- which(grepl("^---\\s*$", lines))
    if (length(ends) < 2L) return(lines)
    lines[-seq_len(ends[[2]])]
}

# Pull out every fenced block, and separately every heading, ignoring anything
# inside a fence (R comments start with "#" too).
scan_doc <- function(lines) {
    lines <- drop_yaml(lines)
    chunks <- list(); headings <- character()
    i <- 1L; n <- length(lines)
    while (i <= n) {
        open <- regmatches(lines[[i]], regexpr("^\\s*(`{3,}|~{3,})", lines[[i]]))
        if (length(open) && nzchar(open)) {
            marker <- trimws(open)
            close_re <- paste0("^\\s*\\", substr(marker, 1L, 1L),
                               "{", nchar(marker), ",}\\s*$")
            j <- i + 1L
            while (j <= n && !grepl(close_re, lines[[j]])) j <- j + 1L
            j <- min(j, n)
            if (grepl("^\\s*`{3,}\\{r[}, ]", lines[[i]]))
                chunks[[length(chunks) + 1L]] <-
                    paste(lines[i:j], collapse = "\n")
            i <- j + 1L
            next
        }
        if (grepl("^#{1,6}\\s", lines[[i]]))
            headings <- c(headings, lines[[i]])
        i <- i + 1L
    }
    list(chunks = chunks, headings = headings)
}

chunk_label <- function(text) {
    hit <- regmatches(text, regexpr("(?<=#\\| label:)[^\n]+", text, perl = TRUE))
    if (length(hit)) trimws(hit) else "(unlabelled)"
}

# Prose blocks of more than two lines - not fatal, but the whole brief was
# "bullets, not paragraphs", so it is worth knowing when that slipped.
long_prose <- function(lines) {
    out <- character(); i <- 1L; n <- length(lines)
    # Not prose: headings, divs, images, list items (numbered, bulleted OR
    # lettered - session8 uses "a." sublists), block quotes, fences, rules,
    # markdown table rows, and indented continuation lines.
    special <- paste0("^(#{1,6}\\s|:{3,}|!\\[|<img\\b",
                      "|\\s*([*+-]|[0-9]+[.)]|[a-z][.)])\\s",
                      "|\\s*>|\\s*(`{3,}|~{3,})|-{3,}\\s*$",
                      "|\\s*\\||\\s+\\S)")
    while (i <= n) {
        open <- regmatches(lines[[i]], regexpr("^\\s*(`{3,}|~{3,})", lines[[i]]))
        if (length(open) && nzchar(open)) {
            marker <- trimws(open)
            close_re <- paste0("^\\s*\\", substr(marker, 1L, 1L),
                               "{", nchar(marker), ",}\\s*$")
            i <- i + 1L
            while (i <= n && !grepl(close_re, lines[[i]])) i <- i + 1L
            i <- i + 1L
            next
        }
        if (nzchar(trimws(lines[[i]])) && !grepl(special, lines[[i]])) {
            j <- i
            while (j + 1L <= n && nzchar(trimws(lines[[j + 1L]])) &&
                   !grepl(special, lines[[j + 1L]])) j <- j + 1L
            if (j - i + 1L > 2L)
                out <- c(out, paste0("[", j - i + 1L, " lines] ",
                                     substr(trimws(lines[[i]]), 1L, 70L)))
            i <- j + 1L
            next
        }
        i <- i + 1L
    }
    out
}

verify <- function(page, body) {
    src <- scan_doc(readLines(paste0(page, ".qmd"), warn = FALSE))
    got <- scan_doc(strsplit(body, "\n", fixed = TRUE)[[1]])
    fatal <- character()

    # -- preamble ---------------------------------------------------------
    first <- head(Filter(nzchar, trimws(strsplit(body, "\n", fixed = TRUE)[[1]])), 1L)
    if (!length(first) || !grepl("^(#{1,6}\\s|:{3,})", first))
        fatal <- c(fatal, paste0("output does not start with a heading or div: ",
                                 substr(first, 1L, 60L)))

    # -- chunks ------------------------------------------------------------
    src_txt <- vapply(src$chunks, identity, character(1))
    altered <- Filter(function(k) !(got$chunks[[k]] %in% src_txt),
                      seq_along(got$chunks))
    if (length(altered))
        fatal <- c(fatal, paste0(length(altered), " chunk(s) not verbatim: ",
                                 paste(vapply(altered, function(k)
                                     chunk_label(got$chunks[[k]]),
                                     character(1)), collapse = ", ")))

    # -- headings ----------------------------------------------------------
    invented <- setdiff(got$headings, src$headings)
    if (length(invented))
        fatal <- c(fatal, paste0(length(invented), " heading(s) not in the source: ",
                                 paste(trimws(invented), collapse = " | ")))
    pos <- match(got$headings, src$headings)
    if (length(pos) > 1L && any(diff(pos[!is.na(pos)]) < 0))
        fatal <- c(fatal, "headings are out of source order")

    list(fatal = fatal,
         chunks_kept = length(got$chunks), chunks_src = length(src$chunks),
         chunks_dropped = vapply(setdiff(src_txt,
                                         vapply(got$chunks, identity,
                                                character(1))),
                                 chunk_label, character(1), USE.NAMES = FALSE),
         headings_kept = length(got$headings), headings_src = length(src$headings),
         headings_dropped = trimws(setdiff(src$headings, got$headings)),
         prose = long_prose(strsplit(body, "\n", fixed = TRUE)[[1]]))
}

# ==========================================================================
#    OUTPUT
# ==========================================================================

# Deliberately identical to _MakeInstructorNotes.R's front matter: the two
# variants must look the same so that only their content is being judged. See
# that script for why each key is here (in short: `grid: body-width` is the
# only thing that actually widens a page with a left TOC, and the small figure
# device beats scaling a 7-inch figure down in CSS).
front_matter <- function(title) {
    c("---",
      paste0('title: "', title, '"'),
      'subtitle: "Instructor notes"',
      "# Wider body. grid is deep-merged with the project block in _quarto.yml,",
      "# so sidebar-width, margin-width and gutter-width are inherited.",
      "# page-layout: full would NOT widen this page: with toc-location: left",
      "# the TOC is #quarto-sidebar, so Quarto picks the column-page-right",
      "# layout, whose body is still capped at $grid-body-width.",
      "grid:",
      "  body-width: 1400px",
      "toc-depth: 4",
      "toc-expand: true",
      "# Appended to the project css rather than replacing it, so fonts.css",
      "# still loads (Quarto treats css as a mergeable list at every level).",
      "css: assets/css/instructor.css",
      "include-in-header: _includes/instructor-head.html",
      "# Keeps these pages out of docs/search.json. `navbar: search: false`",
      "# only hides the search box - the index is written regardless.",
      "search: false",
      "# Rendered at 480x307 and displayed at half that by instructor.css; see",
      "# the Figures block there for which way that trade goes and why.",
      "fig-format: png",
      "fig-width: 5",
      "fig-height: 3.2",
      "---",
      "",
      "<!-- GENERATED by _MakeInstructorNotes.R from _instructor_prompt.md.",
      "     Committed, but do not hand-edit below the BODY marker: the next run",
      "     that sees a changed source page overwrites it. To change the prose,",
      "     edit the prompt; to change the layout, edit this script. -->")
}

# Injected by us, never by the agent, and deliberately above the BODY marker so
# the chunk-fidelity check never sees it.
#
# Printed tables are the single biggest consumer of vertical space on these
# pages - session 3 alone spent 361 lines on 22 tibble prints, a median of 18
# lines each. Two data rows is all a crib sheet needs.
setup_chunk <- function() {
    c("```{r}",
      "#| label: instructor-setup",
      "#| include: false",
      "# width/cli.width are set project-wide in _quarto.yml and are restated",
      "# here so that this one chunk is the whole story for a generated page -",
      "# otherwise a later edit here silently drops them.",
      "options(width = 80, cli.width = 80,",
      "        tibble.print_min = 2, tibble.print_max = 2,",
      "        # A 32-column tibble spends six lines listing the columns it",
      "        # could not fit. One line saying how many is enough here - the",
      "        # \"1,904 x 32\" header already gives the shape.",
      "        tibble.max_extra_cols = 1)",
      "",
      "# Base data frames have no equivalent of the tibble options, so they need",
      "# a method. It MUST let tibbles through: they are data frames too, so S3",
      "# dispatch would land them here, and head() would throw away the real",
      "# row count that the tibble footer reports. kable/kableExtra/DT all",
      "# return their own classes, so none of them come through this.",
      "registerS3method(\"knit_print\", \"data.frame\", function(x, ...) {",
      "    if (inherits(x, \"tbl_df\")) return(knitr::normal_print(x))",
      "    knitr::normal_print(utils::head(x, 2L))",
      "}, envir = asNamespace(\"knitr\"))",
      "```")
}

nav_strip <- function(page) {
    links <- vapply(cfg$pages, function(p) {
        n <- sub("^session", "", p)
        if (identical(p, page)) paste0("**", n, "**")
        else paste0("[", n, "](instructor_", p, ".html)")
    }, character(1))
    c("::: {.instructor-nav}",
      paste0("[Contents](instructor_index.html) &nbsp;·&nbsp; ",
             paste(links, collapse = " &nbsp;·&nbsp; "),
             " &nbsp;·&nbsp; [Student page](", page, ".html)"),
      ":::")
}


write_page <- function(page, body) {
    out <- paste0("instructor_", page, ".qmd")
    writeLines(c(front_matter(page_title(page)),
                 stamp_line(page),
                 "",
                 setup_chunk(),
                 "",
                 nav_strip(page),
                 "",
                 BODY_MARKER,
                 body),
               out)
    out
}

# A whole-document code fence is the one bit of chatter worth forgiving, since
# it changes nothing about the content.
clean_body <- function(text) {
    body <- sub("\\s+$", "", text)
    if (grepl("^```", body)) {
        body <- sub("^```[a-z]*\n", "", body)
        body <- sub("\n```$", "", body)
        message("  (stripped a wrapping code fence)")
    }
    body
}

report <- function(v) {
    message(sprintf("  chunks   %d/%d kept", v$chunks_kept, v$chunks_src))
    message(sprintf("  headings %d/%d kept", v$headings_kept, v$headings_src))
    if (length(v$chunks_dropped))
        message("  chunks dropped: ", paste(v$chunks_dropped, collapse = ", "))
    if (length(v$headings_dropped))
        message("  headings dropped: ",
                paste(v$headings_dropped, collapse = " | "))
    if (length(v$prose)) {
        message("  ", length(v$prose), " prose block(s) over 2 lines:")
        for (p in v$prose) message("      ", p)
    }
}

# ==========================================================================
#    MAIN
# ==========================================================================

spent <- 0

for (page in pages) {
    src <- paste0(page, ".qmd")
    if (!file.exists(src)) {
        warning("no such page: ", src, call. = FALSE, immediate. = TRUE)
        next
    }
    out <- paste0("instructor_", page, ".qmd")
    existing <- if (file.exists(out) && !FORCE_FULL) split_page(out) else NULL

    # ---- refresh: source unchanged, so the body stands and costs nothing ---
    unstamped_adopt <- ADOPT && !is.null(existing) && is.null(existing$stamp)
    if (unstamped_adopt)
        message(page, ": adopting an unstamped page (--adopt)")
    if (!is.null(existing) &&
        (unstamped_adopt ||
         (!is.null(existing$stamp) &&
          identical(existing$stamp$md5, source_md5(src))))) {
        before <- existing$body
        write_page(page, before)
        after <- split_page(out)$body
        if (!identical(before, after))
            stop("refresh altered the body of ", out, " - that is a bug")
        message(page, ": source unchanged, wrapper refreshed, body untouched")
        next
    }

    # ---- update: seed the agent with its own previous body plus the diff ---
    mode <- "full"
    d <- if (!is.null(existing)) source_diff(page, existing$stamp)
    if (!is.null(d) && d$share <= REWRITE_THRESHOLD) {
        mode <- "update"
    } else if (!is.null(existing)) {
        why <- if (is.null(d)) "no trustworthy diff against the stamped commit"
               else sprintf("diff touches %.0f%% of the source", 100 * d$share)
        message(page, ": full rewrite (", why, ")")
    }

    message(page, ": asking ", MODEL, " (effort ", EFFORT, ", ", mode, ") ...")
    ans <- ask_claude(if (identical(mode, "update"))
                          build_prompt_update(page, existing$body, d$text)
                      else build_prompt_full(page))
    body <- clean_body(ans$body)
    spent <- spent + (ans$cost %||% 0)

    v <- verify(page, body)
    message(sprintf("  %.0fs, $%.3f", ans$secs, ans$cost %||% NA_real_))
    report(v)

    # Drift is the failure mode of update mode: a body that churns far more
    # than its source did means the agent rewrote things it was told to leave.
    if (identical(mode, "update")) {
        old_l <- strsplit(existing$body, "\n", fixed = TRUE)[[1]]
        new_l <- strsplit(body, "\n", fixed = TRUE)[[1]]
        churn <- length(setdiff(new_l, old_l)) + length(setdiff(old_l, new_l))
        message(sprintf("  body lines changed %d, source diff touched %d",
                        churn, d$changed))
        if (churn > 4L * d$changed)
            message("  NOTE: body churned much more than the source - check ",
                    "`git diff ", out, "`")
    }

    if (length(v$fatal)) {
        writeLines(body, paste0(out, ".rejected"))
        for (f in v$fatal) message("  FAILED: ", f)
        stop("verification failed; output kept at ", out, ".rejected")
    }

    write_page(page, body)
    message("wrote ", out)
}

# ==========================================================================
#    THE CONTENTS PAGE
#
#    Deliberately plain: it exists so there is one URL to bookmark.
# ==========================================================================

index_rows <- vapply(cfg$pages, function(p) {
    doc <- paste0(p, ".qmd")
    title <- if (file.exists(doc)) page_title(p) else p
    paste0("* [", title, "](instructor_", p, ".html)",
           " &nbsp;·&nbsp; [student page](", p, ".html)")
}, character(1))

writeLines(c(front_matter("Instructor notes"),
             "",
             paste("Pared-back versions of the session pages -- headings, code and",
                   "output, with the prose stripped to the teaching points. Meant",
                   "to be kept open on a second screen while live coding, so that",
                   "a glance says what comes next."),
             "",
             index_rows,
             "",
             "---",
             "",
             "[Back to the course &rarr;](index.html)"),
           "instructor_index.qmd")
message("wrote instructor_index.qmd")

if (spent > 0) message(sprintf("total spend: $%.2f", spent))
