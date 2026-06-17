#!/bin/sh
# spec-translate.sh — the plain-language translation layer for /spec-walkthrough.
#
# Task 3 of specs/spec-comprehension (D-2; REQ-C1.1, REQ-C1.7, REQ-D1.3): the
# lossless layered view over the bundle reader model (scripts/spec-model.sh).
# It reads the model's tagged, tab-separated record stream, passes every model
# record through unchanged (the substrate stays intact and computable — D-2
# losslessness), and appends, per text-bearing element, a translated record:
#
#   TEXT  <ref>  <kind>  <plain>  <source>
#   NORM  <ref>  <ordinal>  <token>
#
# <plain> is the default audience-neutral rendering: planwright's internal
# vocabulary — the requirement/decision/task identifier schemes and the
# four-file names — is scrubbed so a cross-functional reader sees no IDs by
# default (REQ-C1.1). <source> is the element's text verbatim, the reveal seam
# (D-3/REQ-D1.3): the identifiers the plain view hid and any non-normative
# phrasing it rephrased are restorable from it. <ref> is the element's
# back-pointer — the requirement/decision/task identifier (with a `#field`
# suffix for a decision/task sub-field) — so every plain sentence resolves back
# to its exact source element (REQ-D1.3, Done-when #3).
#
# The translation is conservative by construction: it removes identifier tokens
# and maps file names, and otherwise carries the text verbatim. It never
# paraphrases or softens a normative token — MUST/SHALL/SHALL NOT, a comparator
# threshold — so each survives verbatim in <plain> (REQ-C1.7); a NORM record
# marks each one toggle-anchored for the reveal toggle (REQ-D1.3). The HTML
# escaping/sanitization of all rendered content is Task 6's artifact-assembly
# job (REQ-E1.7), downstream of this layer; escaping here would corrupt the
# lossless text the reveal view restores.
#
# Usage:
#   spec-translate.sh <spec-dir>     # run the model->translate chain
#   spec-model.sh <spec-dir> | spec-translate.sh   # translate a model stream
#
# With a <spec-dir> argument it runs scripts/spec-model.sh (a sibling) over the
# directory and translates the result; with no argument it reads a model stream
# on stdin (the composable pipe). It is strictly read-only (REQ-A1.3): it writes
# nothing but its stdout stream.
#
# Exit codes:
#   0  the translated stream was emitted (an empty model stream emits nothing).
#   2  usage or environment error in <spec-dir> mode: the model script could not
#      be found, or the model itself failed (e.g. an absent spec directory —
#      fail closed, propagated from scripts/spec-model.sh).
#
# Portable: /bin/sh + awk as shipped on macOS (bash 3.2, BSD userland) and
# Linux (the REQ-K1.5 envelope). No gawk-only constructs, no eval; input is
# treated as data only.
set -eu

# Pin the C locale: the [[:cntrl:]]-free byte handling and the multibyte ≤/≥
# threshold match below rely on C-locale (byte-wise) classification, matching
# the upstream model. Range and class behavior must not vary by host locale.
LC_ALL=C
export LC_ALL
unset CDPATH

# The translator: reads a model record stream on stdin, emits the pass-through
# plus the TEXT/NORM layer. Held in a variable so both invocation modes feed the
# same program.
# shellcheck disable=SC2016 # $1/$2/$0 are awk fields, not shell expansions
awk_prog='
  BEGIN { FS = "\t"; OFS = "\t" }

  # strip_tok(re, s) — remove every *standalone* occurrence of an identifier
  # pattern from s. awk POSIX ERE has no word-boundary anchor, so a bare
  # gsub(/D-[0-9]+/, "", s) also eats the pattern inside ordinary words
  # (UUID-123 -> UUI, FREQ-A -> F, STANDARD-7 -> STANDAR), corrupting content
  # that carries no back-pointer. We walk matches with match() and drop one only
  # when neither flank is alphanumeric — the same boundary discipline emit_norm
  # uses for modals. A pattern embedded in a larger word is content, left
  # verbatim (D-2 losslessness).
  function strip_tok(re, s,   out, before, after) {
    out = ""
    while (match(s, re)) {
      before = (RSTART > 1) ? substr(s, RSTART - 1, 1) \
                            : (out == "" ? "" : substr(out, length(out), 1))
      after = substr(s, RSTART + RLENGTH, 1)
      if ((before == "" || before !~ /[A-Za-z0-9]/) && (after == "" || after !~ /[A-Za-z0-9]/)) {
        out = out substr(s, 1, RSTART - 1)
      } else {
        out = out substr(s, 1, RSTART + RLENGTH - 1)
      }
      s = substr(s, RSTART + RLENGTH)
    }
    return out s
  }

  # scrub(s) — the default-view rendering of a source text: strip planwright
  # internal vocabulary (REQ-C1.1) while leaving everything else (notably the
  # normative tokens, REQ-C1.7) verbatim.
  function scrub(s,   t) {
    t = s
    # Four-file names -> plain audience-neutral phrases.
    gsub(/requirements\.md/, "the requirements", t)
    gsub(/design\.md/, "the design", t)
    gsub(/test-spec\.md/, "the test plan", t)
    gsub(/tasks\.md/, "the task list", t)
    # Remove the identifier tokens themselves, each a back-pointer carried in the
    # ref/source columns: full REQ ids first, then D ids, then leftover REQ group
    # refs, then task-id-scheme tokens. Removing the tokens directly (rather than
    # matching whole parentheticals by shape) means a parenthetical carrying
    # non-identifier content — "(UTF-8)", "(SHA-256)", "(MUST-HAVE)" — keeps its
    # content; only the ids inside it go, and the tidy below collapses what is
    # left empty. The text the plain view drops always survives in <source>
    # (D-2 losslessness): the scrub never deletes content that has no back-pointer.
    # strip_tok anchors each removal to token boundaries so an id pattern living
    # inside an ordinary word (UUID-123, FREQ-A) is kept as content.
    t = strip_tok("REQ-[A-Z][0-9]+\\.[0-9]+", t)
    t = strip_tok("D-[0-9]+", t)
    t = strip_tok("REQ-[A-Z]", t)
    t = strip_tok("Task [0-9]+(\\.[0-9]+)?", t)
    # Tidy: parentheses the id removal emptied to only spaces/separators
    # ("()", "( / )", "( , )"), spaces before punctuation, and collapsed
    # whitespace. A parenthetical with surviving content is left intact.
    gsub(/\([ \t]*[\/,;.&-]*[ \t]*\)/, "", t)
    gsub(/ +,/, ",", t)
    gsub(/ +\./, ".", t)
    gsub(/ +;/, ";", t)
    gsub(/ +:/, ":", t)
    gsub(/  +/, " ", t)
    sub(/^ +/, "", t)
    sub(/ +$/, "", t)
    return t
  }

  # emit_norm(ref, s) — one NORM record per normative token in s, marking it
  # toggle-anchored (REQ-C1.7). Two classes scanned in two passes: first the
  # RFC-2119 uppercase modals (extended to "... NOT" when it follows) in source
  # order, then the comparator thresholds (a comparator governing a number) in
  # source order. Ordinals therefore run modals-before-thresholds, not strict
  # whole-string source order, when both classes co-occur; the per-class order is
  # stable and deterministic, and consumers key off the (ref, token) pair. The
  # token-boundary guard treats digits as word characters (MUST1 / SHALL2 are not
  # normative tokens), the same alphanumeric flank rule strip_tok uses.
  function emit_norm(ref, s,   rest, tok, before, after, ord, adv) {
    ord = 0
    rest = s
    while (match(rest, /(MUST|SHALL|SHOULD|MAY|REQUIRED|RECOMMENDED|OPTIONAL)/)) {
      tok = substr(rest, RSTART, RLENGTH)
      before = (RSTART == 1) ? "" : substr(rest, RSTART - 1, 1)
      after = substr(rest, RSTART + RLENGTH, 1)
      adv = RSTART + RLENGTH
      if ((before == "" || before !~ /[A-Za-z0-9]/) && (after == "" || after !~ /[A-Za-z0-9]/)) {
        # Extend a bare modal to "<modal> NOT" so the negation is one verbatim
        # token, regardless of the regex engine longest-match behavior.
        if (tok ~ /^(MUST|SHALL|SHOULD)$/ && substr(rest, adv, 5) ~ /^ NOT([^A-Za-z0-9]|$)/) {
          tok = tok " NOT"
          adv = adv + 4
        }
        ord++
        printf "NORM\t%s\t%d\t%s\n", ref, ord, tok
      }
      rest = substr(rest, adv)
    }
    rest = s
    while (match(rest, /(<=|>=|≤|≥|<|>)[ ]*[0-9]+(\.[0-9]+)?/)) {
      ord++
      printf "NORM\t%s\t%d\t%s\n", ref, ord, substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
    }
  }

  # translate(ref, kind, src) — emit a TEXT record and its NORM marks. An empty
  # source emits nothing (no text to render or restore).
  function translate(ref, kind, src) {
    if (src == "") return
    printf "TEXT\t%s\t%s\t%s\t%s\n", ref, kind, scrub(src), src
    emit_norm(ref, src)
  }

  # Every model record passes through unchanged (lossless substrate); the
  # text-bearing ones additionally get a translated record.
  { print $0 }

  $1 == "REQ" { translate($2, "requirement", $5); next }
  $1 == "DEC" { translate($2, "decision-title", $4); next }
  $1 == "DECFIELD" { translate($2 "#" $3, "decision-" $3, $4); next }
  $1 == "TASK" { translate("task-" $2, "task-title", $4); next }
  $1 == "TASKFIELD" { translate("task-" $2 "#" $3, "task-" $3, $4); next }
'

spec_dir="${1:-}"
if [ -n "$spec_dir" ] && [ "$spec_dir" != "-" ]; then
  # <spec-dir> mode: run the sibling model and translate its stream. Resolve the
  # model script next to this one (the sibling-script convention).
  here=$(cd "$(dirname "$0")" && pwd)
  model="$here/spec-model.sh"
  if [ ! -x "$model" ]; then
    echo "spec-translate: cannot find an executable spec-model.sh at $model" >&2
    exit 2
  fi
  # Capture the model first so its exit code propagates (fail closed on an
  # absent/unreadable spec directory); /bin/sh has no portable pipefail.
  model_stream=$("$model" "$spec_dir") || exit $?
  printf '%s\n' "$model_stream" | awk "$awk_prog"
else
  awk "$awk_prog"
fi
