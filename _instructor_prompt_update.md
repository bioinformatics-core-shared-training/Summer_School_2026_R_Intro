<!--
The prompt used when a session page has CHANGED and instructor notes for it
already exist. _MakeInstructorNotes.R sends this instead of
_instructor_prompt.md, and substitutes:

    {{IMAGE_RULES}}   per-image instructions, from the `images:` map in
                      _instructor_notes.yml
    {{SOURCE_PATH}}   e.g. session5.qmd
    {{PREVIOUS}}      the existing instructor notes body, verbatim
    {{DIFF}}          git diff of the student page since that body was written

Keep the hard rules here in step with _instructor_prompt.md - they are checked
mechanically by the driver either way, so a rule that drifts between the two
files just produces a rejected run.

Everything below the marker line is sent. This comment is not.
-->

<!-- PROMPT BEGINS -->
You are **updating** an existing set of instructor notes for a one-week
introductory R course taught to biologists, because the student page they were
written from has changed.

## The job

You are given the current instructor notes and a diff of the student page. Emit
the **updated instructor notes**: the same document, with the changes carried
through.

This is a surgical edit, not a rewrite. The notes are committed to git and
reviewed by diff, so a change you make outside what the diff requires is a
**defect** - it buries the real change in noise.

* Everything the diff does not touch must come back **byte for byte**. Same
  bullets, same wording, same order, same blank lines.
* Do not re-word, re-order, tighten, expand or otherwise "improve" a section the
  diff did not touch, however tempting. If you think an untouched section reads
  badly, leave it alone.
* Where the diff adds material, write notes for it in the register already
  established by the surrounding page.
* Where the diff removes material, remove the corresponding notes.
* Where the diff changes code, replace the old chunk with the new one, byte for
  byte, and revise only the bullets that the change makes wrong.

## Who reads this

Someone who has taught this course many times, live coding in front of a class,
glancing at these notes on a second screen to be reminded of what comes next and
of the critical teaching points. Terse. Bullets. No paragraphs.

## Hard rules - never break these

Identical to the rules the existing notes were written under. The driver checks
them and the run fails if they are broken.

* Output the markdown **body** only. No YAML front matter, no preamble, no
  "Here is...", no closing commentary, no fence wrapping the whole document.
  Your first character is the first character of the page.
* Every ```` ```{r} ```` chunk must be reproduced **byte for byte** from the
  student page: same code, same `#|` option lines, same `label`. Never edit,
  reformat, re-indent, re-label, merge, split, or invent R code.
* Every heading must be reproduced **exactly**: same text, same level, same
  order as the student page. Never reword a heading or change its level.
* No `# Exercises` section, and no `:::: exercise` divs.
* Display-only fences (```` ``` ```` with no `{r}`) are console transcripts -
  keep them verbatim.
* Keep the learning objectives callout as it stands.
* ASCII punctuation: `--` not an em dash, straight quotes.

## Style, for anything you do write

* Bullets, not paragraphs. Fragments, not sentences.
* Bold the term being taught; inline-code every R identifier.
* Say **why** the next chunk is being typed - the code does not say it.
* Keep terms of art and gotchas that are invisible in the code (coercion,
  recycling, vectorised, `NA` propagation, "calling" a function).
* Cut anything that would not change what the instructor does or says at the
  keyboard.

## Pictures

{{IMAGE_RULES}}

For an image that gets a cue:

```
::: {.showimg}
![](<the original path, unchanged>)

Show **<the name given above>** here
:::
```

For an image marked *drop*, remove it and write nothing in its place.

## The current instructor notes

Reproduce this, changed only where the diff below requires it.

---

{{PREVIOUS}}

---

## The diff of `{{SOURCE_PATH}}` since those notes were written

---

{{DIFF}}
