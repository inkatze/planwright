#!/bin/sh
# spec-teachback.sh — the teach-back challenge view for /spec-walkthrough.
#
# Task 5 of specs/spec-comprehension (D-3, D-9; REQ-C1.5, REQ-D1.1, REQ-D1.4):
# the claim set a human teaches back to confirm their own understanding. It
# reads the plain-language translation stream (scripts/spec-translate.sh) and
# extracts the bundle's own assertions — every live requirement and every
# decision — into a section-by-section challenge that both the in-artifact
# checklist (assembled by Task 6) and the optional in-session walk (the skill)
# render from this one source, so the two paths cover the same claims by
# construction (Done-when #4).
#
# The independence firewall (D-3, REQ-D1.1) is structural here: the view offers
# a neutral agree / disagree / unsure response model and the claims themselves,
# and *nothing else*. There is no column where a verdict, score, or "right
# answer" could live — the human marks each claim and adjudicates any divergence
# themselves (REQ-D1.4); the tool presents and records, it never judges.
#
# Record vocabulary (tag in column 1, tab-separated):
#   RESPONSE  <option>                              (agree | disagree | unsure)
#   SECTION   <section-id>  <order>  <label>
#   CLAIM     <ref>  <section-id>  <ordinal>  <plain>  <source>
#
# A claim's <plain> is the audience-neutral assertion the reader restates
# (inherited verbatim from the translation layer's scrub, so no internal
# vocabulary leaks — REQ-C1.1); <source> is the element's verbatim text, the
# reveal seam (D-2 / REQ-D1.3) restoring the identifiers and exact wording the
# plain view hid; <ref> is the back-pointer (a requirement or decision id) so
# every claim resolves to its source element. Claims are grouped into sections —
# one per requirement group, then the decisions — and presented section by
# section (REQ-C1.5, the chunk-and-check teach-back evidence base behind D-3).
# Superseded requirements and tasks are not claims: a superseded requirement is
# history, and a task is the plan, not an assertion to agree or disagree with.
#
# Usage:
#   spec-teachback.sh <spec-dir>     # run the model->translate->teachback chain
#   spec-translate.sh <spec-dir> | spec-teachback.sh   # view a translation stream
#
# With a <spec-dir> argument it runs scripts/spec-translate.sh (a sibling) over
# the directory and reads the bundle's requirement-group headings for plain
# section labels; with no argument it reads a translation stream on stdin (the
# composable pipe), where section labels fall back to a generic plain phrase
# (the group headings are not in the stream). The claim set — the load-bearing
# contract — is identical in both modes. Strictly read-only (REQ-A1.3): it
# writes nothing but its stdout stream.
#
# Exit codes:
#   0  the teach-back view was emitted (a stream with no claims emits nothing).
#   2  usage or environment error in <spec-dir> mode: the translate script could
#      not be found, or the chain itself failed (e.g. an absent spec directory —
#      fail closed, propagated from scripts/spec-translate.sh).
#
# Portable: /bin/sh + awk as shipped on macOS (bash 3.2, BSD userland) and
# Linux (the REQ-K1.5 envelope). No gawk-only constructs, no eval; input is
# treated as data only.
set -eu

# Pin the C locale: the byte-wise leading-separator strip in the group-title
# extraction (the multibyte em-dash in "## REQ-A — Title") and the awk class
# matching below rely on C-locale classification, matching the upstream layers.
LC_ALL=C
export LC_ALL
unset CDPATH

# The teach-back view: reads a translation record stream (optionally prefixed
# with GROUPTITLE records carrying the plain section labels), and emits the
# neutral response model, the sections, and one claim per assertion. Held in a
# variable so both invocation modes feed the same program.
# shellcheck disable=SC2016 # $1..$5/$0 are awk fields, not shell expansions
awk_prog='
  BEGIN { FS = "\t"; OFS = "\t"; nc = 0; secn = 0 }

  # Plain section labels (dir mode prefixes these, one per requirement group).
  $1 == "GROUPTITLE" { title[$2] = $3; next }

  # The model pass-through carries each requirement group and its live/superseded
  # state; only live requirements are current claims.
  $1 == "REQ" { grp[$2] = $3; live[$2] = ($4 == "live") ? 1 : 0; next }

  # A translated requirement is one claim, filed under its requirement group.
  $1 == "TEXT" && $3 == "requirement" {
    ref = $2
    if (live[ref] != 1) next
    sec = "req-" grp[ref]
    register(sec, label_for(grp[ref]))
    add_claim(ref, sec, $4, $5)
    next
  }

  # A decision is one claim: its plain decision statement is the assertion, filed
  # under the decisions section. The structured ref (D-N#decision) collapses to
  # the decision id (D-N), the back-pointer the reveal seam resolves.
  $1 == "TEXT" && $3 == "decision-decision" {
    ref = $2
    sub(/#.*/, "", ref)
    register("decisions", "Key decisions")
    add_claim(ref, "decisions", $4, $5)
    next
  }

  function label_for(g) {
    return (g in title && title[g] != "") ? title[g] : "Requirements"
  }

  # Register a section the first time a claim files under it, preserving
  # first-seen order (requirement groups in file order, then decisions).
  function register(sec, label) {
    if (sec in secorder) return
    secorder[sec] = ++secn
    order2sec[secn] = sec
    seclabel[sec] = label
  }

  function add_claim(ref, sec, plain, src) {
    nc++
    cref[nc] = ref
    csec[nc] = sec
    cplain[nc] = plain
    csrc[nc] = src
  }

  # Emit section by section: the neutral response model once, the section list in
  # reading order, then the claims grouped under their section with per-section
  # ordinals. A stream with no claims emits nothing (empty in, empty out).
  END {
    if (nc == 0) exit 0
    print "RESPONSE", "agree"
    print "RESPONSE", "disagree"
    print "RESPONSE", "unsure"
    for (o = 1; o <= secn; o++) {
      sec = order2sec[o]
      print "SECTION", sec, o, seclabel[sec]
    }
    for (o = 1; o <= secn; o++) {
      sec = order2sec[o]
      ord = 0
      for (i = 1; i <= nc; i++) {
        if (csec[i] != sec) continue
        ord++
        print "CLAIM", cref[i], sec, ord, cplain[i], csrc[i]
      }
    }
  }
'

# extract_group_titles <requirements.md> — emit one `GROUPTITLE <letter> <title>`
# per requirement-group heading (`## REQ-<letter> — <title>`). The title is the
# plain, audience-neutral heading text after the separator; the leading run of
# non-alphanumeric bytes (the " — " with its multibyte em-dash) is stripped
# byte-wise under the pinned C locale. The id prefix never reaches the label.
extract_group_titles() {
  awk '
    /^## REQ-[A-Z]/ {
      match($0, /^## REQ-[A-Z]+/)
      grp = substr($0, 8, RLENGTH - 7)
      title = $0
      sub(/^## REQ-[A-Z]+/, "", title)
      sub(/^[^A-Za-z0-9]+/, "", title)
      gsub(/[[:cntrl:]]/, " ", title)
      gsub(/  +/, " ", title)
      sub(/ +$/, "", title)
      if (title != "") printf "GROUPTITLE\t%s\t%s\n", grp, title
    }
  ' "$1"
}

spec_dir="${1:-}"
if [ -n "$spec_dir" ] && [ "$spec_dir" != "-" ]; then
  # <spec-dir> mode: run the sibling translate chain and read the group headings
  # for plain section labels. Resolve the translate script next to this one.
  here=$(cd "$(dirname "$0")" && pwd)
  translate="$here/spec-translate.sh"
  if [ ! -x "$translate" ]; then
    echo "spec-teachback: cannot find an executable spec-translate.sh at $translate" >&2
    exit 2
  fi
  # Strip trailing slashes for the requirements.md read (mirror the model).
  d=$spec_dir
  while [ "$d" != "${d%/}" ]; do d=${d%/}; done
  # Capture the chain first so its exit code propagates (fail closed on an
  # absent/unreadable spec directory); /bin/sh has no portable pipefail.
  stream=$("$translate" "$spec_dir") || exit $?
  titles=
  if [ -f "$d/requirements.md" ] && [ -r "$d/requirements.md" ]; then
    titles=$(extract_group_titles "$d/requirements.md")
  fi
  # Prefix the titles (if any), then the translation stream. printf '%s' on the
  # stream (no trailing newline) keeps the "empty in, empty out" contract: an
  # empty stream stays empty rather than gaining a phantom blank record.
  {
    [ -n "$titles" ] && printf '%s\n' "$titles"
    printf '%s' "$stream"
  } | awk "$awk_prog"
else
  awk "$awk_prog"
fi
