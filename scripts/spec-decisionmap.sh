#!/bin/sh
# spec-decisionmap.sh — the ADR-shaped decision-map view for /spec-walkthrough.
#
# Task 8 of specs/spec-comprehension (D-2; REQ-C1.4): the four-beat decision view
# over the plain-language translation layer (scripts/spec-translate.sh). It reads
# the translate record stream, passes every upstream record through unchanged
# (the lossless substrate — D-2), and appends a decision-map layer that renders
# each decision in the ADR shape Context -> Decision -> Alternative-rejected ->
# Consequence, surfacing the rejected alternative and its cost, not only the
# chosen path:
#
#   DECMAPFRAME  <spec>  <status>  <decs>
#   DECMAP       <ordinal>  <ref>  <beat>  <plain>  <source>
#
# The frame is the orientation header a renderer opens the decision map with: the
# bundle, its status, and how many decisions it holds. Each decision then emits
# exactly four DECMAP records, in the canonical beat order, sharing the
# decision's ordinal (its document position, 1..decs) and ref (its identifier):
#   <beat>    context | decision | alternative | consequence
#   <ref>     the decision's identifier — the back-pointer, carried in its own
#             column so the default render stays audience-neutral (REQ-C1.1) and
#             the reveal toggle (REQ-D1.3) can surface it on demand.
#   <plain>   the default audience-neutral rendering of the beat (from the
#             translation layer; internal vocabulary scrubbed, REQ-C1.1).
#   <source>  the beat's verbatim text — the reveal seam (D-2).
#
# The four beats map onto the bundle's three decision fields plus the decision's
# framing, per the kickoff brief's REQ-C1.4 four-beat sourcing resolution (§3):
# the three-field D-ID substrate (Decision / Alternatives considered / Chosen
# because) has no dedicated Context or Consequence field, so the four-beat shape
# is a presentation mapping over it —
#   context      <- the decision's framing: its title (the decision-title TEXT).
#   decision     <- the Decision field.
#   alternative  <- the Alternatives-considered field, which carries both the
#                   rejected option and its "Rejected because" cost verbatim
#                   (REQ-C1.4: surface the rejected alternative and the cost).
#   consequence  <- the Chosen-because field.
# A decision missing a source field still emits the full four-beat shape with
# that beat's plain/source columns empty: the shape is preserved and the gap is
# visible rather than a silently dropped beat (graceful degradation, REQ-A1.5).
#
# The view supplies no verdict, score, or assessment of any decision — it
# presents the bundle's own four-beat content and structures it; the human judges
# (the independence firewall, REQ-D1.1). The plain rendering is the translation
# layer's audience-neutral text; this view does not soften a normative token
# (REQ-C1.7) — it carries whatever the upstream layers carried. HTML/SVG escaping
# of the rendered content is Task 6's artifact-assembly job (REQ-E1.7),
# downstream of this layer; escaping here would corrupt the lossless verbatim
# source the reveal view restores (D-2).
#
# Usage:
#   spec-decisionmap.sh <spec-dir>     # run the model->translate->map chain
#   spec-translate.sh <spec-dir> | spec-decisionmap.sh   # render a translate stream
#
# With a <spec-dir> argument it runs scripts/spec-translate.sh (a sibling, which
# runs the model itself) over the directory and renders the result; with no
# argument it reads a translate stream on stdin (the composable pipe). It is
# strictly read-only (REQ-A1.3): it writes nothing but its stdout stream.
#
# Exit codes:
#   0  the decision-map stream was emitted (an empty input emits nothing).
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

# The renderer: reads a translate record stream on stdin, passes it through
# unchanged, and appends the decision-map frame and four-beat records computed in
# END. Held in a variable so both invocation modes feed the same program.
# shellcheck disable=SC2016 # $1/$2/$0 are awk fields, not shell expansions
awk_prog='
  BEGIN { FS = "\t"; OFS = "\t" }

  # Pass every upstream record through unchanged (lossless substrate, D-2). $0 is
  # never reassigned on these lines, so the record is reprinted verbatim.
  { print $0 }

  $1 == "BUNDLE" { spec = $2; status = $3; next }

  # Decisions in document order. The DEC record fixes the order and the ordinal;
  # the beats come from the translate TEXT records below.
  $1 == "DEC" { decn++; decorder[decn] = $2; next }

  # The translation layer emits one TEXT record per text-bearing element. For a
  # decision it emits a decision-title record (ref = the decision id) and one
  # record per field (ref = "<id>#<field>", kind = "decision-<field>"). Key each
  # beat by the decision id so the END block can assemble the four-beat shape.
  # Field 4 is the plain (audience-neutral) rendering; field 5 the verbatim
  # source (the reveal seam).
  $1 == "TEXT" && $3 == "decision-title" {
    ctx_plain[$2] = $4; ctx_src[$2] = $5; next
  }
  $1 == "TEXT" && $3 == "decision-decision" {
    id = $2; sub(/#decision$/, "", id)
    dec_plain[id] = $4; dec_src[id] = $5; next
  }
  $1 == "TEXT" && $3 == "decision-alternatives" {
    id = $2; sub(/#alternatives$/, "", id)
    alt_plain[id] = $4; alt_src[id] = $5; next
  }
  $1 == "TEXT" && $3 == "decision-chosen" {
    id = $2; sub(/#chosen$/, "", id)
    cons_plain[id] = $4; cons_src[id] = $5; next
  }

  END {
    # Nothing parsed (empty input): emit nothing, matching the upstream chain.
    if (spec == "" && decn == 0) exit 0

    # The orientation frame first (the decision map opens on it).
    printf "DECMAPFRAME\t%s\t%s\t%d\n", spec, status, decn

    # Each decision in document order emits exactly four beats, in canonical
    # order. A beat whose source field is absent emits empty plain/source columns
    # — the four-beat shape is always present (graceful degradation, REQ-A1.5).
    for (i = 1; i <= decn; i++) {
      id = decorder[i]
      printf "DECMAP\t%d\t%s\t%s\t%s\t%s\n", i, id, "context",     ctx_plain[id],  ctx_src[id]
      printf "DECMAP\t%d\t%s\t%s\t%s\t%s\n", i, id, "decision",    dec_plain[id],  dec_src[id]
      printf "DECMAP\t%d\t%s\t%s\t%s\t%s\n", i, id, "alternative", alt_plain[id],  alt_src[id]
      printf "DECMAP\t%d\t%s\t%s\t%s\t%s\n", i, id, "consequence", cons_plain[id], cons_src[id]
    }
  }
'

spec_dir="${1:-}"
if [ -n "$spec_dir" ] && [ "$spec_dir" != "-" ]; then
  # <spec-dir> mode: run the sibling translate chain and render its stream.
  # Resolve the translate script next to this one (the sibling-script convention,
  # mirroring scripts/spec-onepager.sh's resolution of the translate layer).
  here=$(cd "$(dirname "$0")" && pwd)
  translate="$here/spec-translate.sh"
  if [ ! -x "$translate" ]; then
    echo "spec-decisionmap: cannot find an executable spec-translate.sh at $translate" >&2
    exit 2
  fi
  # Capture the upstream stream first so its exit code propagates (fail closed on
  # an absent/unreadable spec directory); /bin/sh has no portable pipefail.
  upstream=$("$translate" "$spec_dir") || exit $?
  # printf '%s' (no trailing newline): command substitution already stripped the
  # upstream trailing newline, and awk reads a final unterminated record fine. A
  # '%s\n' would inject a phantom blank record if the stream were ever empty,
  # breaking the "empty in, empty out" contract.
  printf '%s' "$upstream" | awk "$awk_prog"
else
  awk "$awk_prog"
fi
