#!/bin/sh
# spec-onepager.sh — the spec-at-a-glance one-pager view for /spec-walkthrough.
#
# Task 4 of specs/spec-comprehension (D-2; REQ-C1.2): the length-bounded
# narrative view over the plain-language translation layer
# (scripts/spec-translate.sh). It reads the translate record stream, passes
# every upstream record through unchanged (the lossless substrate — D-2), and
# appends a bounded, ranked one-pager layer:
#
#   ONEPAGERFRAME  <spec>  <status>  <reqs>  <decs>  <tasks>  <shown>  <live>
#   ONEPAGER       <ordinal>  <prominence>  <ref>  <score>  <plain>  <source>
#
# The frame is the orientation header a narrative renderer opens with: the
# bundle, its status, the element counts, how many claims the one-pager surfaces
# (<shown>) and out of how many live requirements (<live>). Surfacing the
# shown-of-live bound is deliberate — the at-a-glance view omits the long tail,
# and saying so keeps the omission honest rather than silent.
#
# Each ONEPAGER record is one load-bearing claim, in one-pager order (the
# foregrounded "killer items" first, then routine content; within each, highest
# load-bearing score first, document order breaking ties):
#   <prominence>  killer | routine — killer items are the small foregrounded set
#                 (REQ-C1.2); a renderer (Task 6) draws them visually distinct.
#   <ref>         the claim's back-pointer — the requirement identifier — so
#                 every plain sentence resolves to its exact source element
#                 (REQ-C1.2, REQ-D1.3 reveal seam).
#   <score>       the load-bearing score: how many of the bundle's own citation
#                 / dependency edges point at this requirement (TASKCITE +
#                 REQCITE inbound). The more the rest of the bundle leans on a
#                 requirement, the more load-bearing it is.
#   <plain>       the default audience-neutral rendering (from the translation
#                 layer; internal vocabulary scrubbed, REQ-C1.1).
#   <source>      the requirement's verbatim text — the reveal seam (D-2).
#
# Claims are the bundle's *live* requirements (its normative "what must be true"
# assertions); superseded requirements are not current claims, and decisions and
# tasks have their own dedicated views (the decision-map and graph tasks).
#
# Killer-item selection is a heuristic — inbound-reference count as the
# load-bearing proxy — declared as a within-task scoping call (proportionality):
# the *quality* of the selection is the [manual] half of REQ-C1.2's verification,
# and a richer killer-item signal is logged as a drain-loop observation. The
# at-a-glance length bound (SHOWN_MAX / KILLER_MAX below) is the "deliberately
# unquantified, manual-judged" bound the kickoff brief (§2) records: a sensible
# default, not a contract number.
#
# Usage:
#   spec-onepager.sh <spec-dir>     # run the model->translate->one-pager chain
#   spec-translate.sh <spec-dir> | spec-onepager.sh   # render a translate stream
#
# With a <spec-dir> argument it runs scripts/spec-translate.sh (a sibling, which
# runs the model itself) over the directory and renders the result; with no
# argument it reads a translate stream on stdin (the composable pipe). It is
# strictly read-only (REQ-A1.3): it writes nothing but its stdout stream.
#
# Exit codes:
#   0  the one-pager stream was emitted (an empty input emits nothing).
#   2  usage or environment error in <spec-dir> mode: the translate script could
#      not be found, or the upstream chain failed (e.g. an absent spec directory
#      — fail closed, propagated from scripts/spec-translate.sh).
#
# Portable: /bin/sh + awk as shipped on macOS (bash 3.2, BSD userland) and Linux
# (the REQ-K1.5 envelope). No gawk-only constructs (asort, gensub), no eval;
# input is treated as data only.
set -eu

# Pin the C locale: range patterns and the tab-field handling below rely on
# C-locale (byte-wise) classification, matching the upstream model/translate.
LC_ALL=C
export LC_ALL
unset CDPATH

# The at-a-glance bound. KILLER_MAX is the small foregrounded set (the aviation
# "killer items" — few by construction); SHOWN_MAX caps the whole one-pager so a
# large bundle renders an at-a-glance subset, not a dump of every requirement.
# Defaults, not a contract: REQ-C1.2's length bound is "deliberately
# unquantified, manual-judged" (kickoff brief §2).
KILLER_MAX=3
SHOWN_MAX=9

# The renderer: reads a translate record stream on stdin, passes it through
# unchanged, and appends the one-pager frame and claim records computed in END.
# Held in a variable so both invocation modes feed the same program.
# shellcheck disable=SC2016 # $1/$2/$0 are awk fields, not shell expansions
awk_prog='
  BEGIN { FS = "\t"; OFS = "\t" }

  # Pass every upstream record through unchanged (lossless substrate, D-2). $0
  # is never reassigned on these lines, so the record is reprinted verbatim.
  { print $0 }

  $1 == "BUNDLE" { spec = $2; status = $3; next }

  # Requirements: remember each in document order, its live/superseded state, and
  # its verbatim source text. reqs counts all requirement records; live counts
  # the current ones (the claim universe).
  $1 == "REQ" {
    reqs++
    if ($4 == "live") {
      live++
      liveid[live] = $2
      rsrc[$2] = $5
      seen_live[$2] = 1
    }
    next
  }

  # Plain audience-neutral rendering of each requirement (REQ-C1.1), keyed by the
  # requirement id (the translation layer emits a requirement TEXT record whose
  # ref is the requirement id).
  $1 == "TEXT" && $3 == "requirement" { rplain[$2] = $4; next }

  $1 == "DEC"  { decs++; next }
  $1 == "TASK" { tasks++; next }

  # Load-bearing score: every citation / dependency edge pointing at an element
  # (its third field is the cited id). A requirement cited by many tasks (and
  # any requirement that cites it) is structurally load-bearing.
  $1 == "REQCITE"  { score[$3]++; next }
  $1 == "TASKCITE" { score[$3]++; next }

  END {
    # Nothing parsed (empty input): emit nothing, matching the upstream chain.
    if (spec == "" && live == 0 && reqs == 0) exit 0

    # Rank live requirements by score descending, document order breaking ties.
    # A stable insertion sort over an index array: only a strictly-greater score
    # displaces, so equal scores keep their original (document) order.
    for (i = 1; i <= live; i++) { order[i] = i; sc[i] = score[liveid[i]] + 0 }
    for (i = 2; i <= live; i++) {
      key = order[i]; j = i - 1
      while (j >= 1 && sc[order[j]] < sc[key]) { order[j + 1] = order[j]; j-- }
      order[j + 1] = key
    }

    shown = (live < SHOWN_MAX) ? live : SHOWN_MAX

    # Emit the orientation frame first (the narrative opens on it).
    printf "ONEPAGERFRAME\t%s\t%s\t%d\t%d\t%d\t%d\t%d\n", \
      spec, status, reqs, decs, tasks, shown, live

    # Emit the shown claims in ranked order. The first KILLER_MAX claims that
    # carry any load-bearing signal (score >= 1) are the foregrounded killer
    # set; everything else is routine. A bundle whose requirements carry no
    # citation signal at all surfaces no killer items rather than foregrounding
    # an arbitrary pick.
    killers = 0
    for (p = 1; p <= shown; p++) {
      id = liveid[order[p]]
      s = sc[order[p]]
      if (killers < KILLER_MAX && s >= 1) {
        prominence = "killer"
        killers++
      } else {
        prominence = "routine"
      }
      plain = (id in rplain) ? rplain[id] : rsrc[id]
      printf "ONEPAGER\t%d\t%s\t%s\t%d\t%s\t%s\n", \
        p, prominence, id, s, plain, rsrc[id]
    }
  }
'

spec_dir="${1:-}"
if [ -n "$spec_dir" ] && [ "$spec_dir" != "-" ]; then
  # <spec-dir> mode: run the sibling translate chain and render its stream.
  # Resolve the translate script next to this one (the sibling-script
  # convention, mirroring scripts/spec-translate.sh's resolution of the model).
  here=$(cd "$(dirname "$0")" && pwd)
  translate="$here/spec-translate.sh"
  if [ ! -x "$translate" ]; then
    echo "spec-onepager: cannot find an executable spec-translate.sh at $translate" >&2
    exit 2
  fi
  # Capture the upstream stream first so its exit code propagates (fail closed on
  # an absent/unreadable spec directory); /bin/sh has no portable pipefail.
  upstream=$("$translate" "$spec_dir") || exit $?
  # printf '%s' (no trailing newline): command substitution already stripped the
  # upstream trailing newline, and awk reads a final unterminated record fine. A
  # '%s\n' would inject a phantom blank record if the stream were ever empty,
  # breaking the "empty in, empty out" contract.
  printf '%s' "$upstream" | awk -v KILLER_MAX="$KILLER_MAX" -v SHOWN_MAX="$SHOWN_MAX" "$awk_prog"
else
  awk -v KILLER_MAX="$KILLER_MAX" -v SHOWN_MAX="$SHOWN_MAX" "$awk_prog"
fi
