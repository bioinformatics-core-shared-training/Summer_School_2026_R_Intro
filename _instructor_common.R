# Shared by the two instructor-notes scripts:
#
#   _MakeInstructorNotes.R   writes instructor_sessionN.qmd (the web version)
#   _MakeInstructorPDF.R     turns those into a printable PDF
#
# Only the things both genuinely need live here - the file layout of a
# generated page, and how to take it apart again. Everything else stays in
# whichever script owns it.

# Separates the wrapper _MakeInstructorNotes.R writes (front matter, setup
# chunk, nav strip, provenance stamp) from the body the agent wrote. Everything
# above it is regenerated on every run; everything below it is the agent's.
BODY_MARKER <- "<!-- BODY -->"

parse_stamp <- function(lines) {
    hit <- grep("^<!-- instructor-notes:", lines)
    if (!length(hit)) return(NULL)
    kv <- regmatches(lines[[hit[[1]]]],
                     gregexpr("[a-z0-9]+=[^ ]+", lines[[hit[[1]]]]))[[1]]
    out <- as.list(sub("^[a-z0-9]+=", "", kv))
    names(out) <- sub("=.*$", "", kv)
    out
}

# Split a generated page into our wrapper and the agent's body.
#
# Pages written before the BODY marker existed are still readable: their body
# starts after the closing ":::" of the nav strip, which is the last thing the
# old wrapper emitted. Those have no stamp either, so on their own they force a
# full regeneration - see --adopt in _MakeInstructorNotes.R.
split_page <- function(path) {
    lines <- readLines(path, warn = FALSE)
    at <- grep(BODY_MARKER, lines, fixed = TRUE)
    if (!length(at)) {
        nav <- grep("^:::+ *\\{\\.instructor-nav\\}", lines)
        if (!length(nav)) return(NULL)
        close <- grep("^:::+ *$", lines)
        close <- close[close > nav[[1]]]
        if (!length(close)) return(NULL)
        at <- close[[1]]
        legacy <- TRUE
    } else {
        legacy <- FALSE
    }
    body <- lines[-seq_len(at[[1]])]
    while (length(body) && !nzchar(trimws(body[[1]]))) body <- body[-1]
    list(stamp = parse_stamp(lines), legacy = legacy,
         body = paste(body, collapse = "\n"))
}

# The title a student page declares, used for both the web page and the PDF.
page_title <- function(page) {
    lines <- readLines(paste0(page, ".qmd"), warn = FALSE)
    hit <- grep("^title:", lines)
    if (!length(hit)) return(page)
    trimws(gsub('^"|"$', "", trimws(sub("^title:", "", lines[[hit[[1]]]]))))
}
