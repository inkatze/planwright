#!/bin/sh
# spec-validate.sh — the planwright status-aware spec validator.
#
# Enforces doctrine/spec-format.md's validator-enforceable invariants
# (REQ-A2.1, REQ-A2.2, REQ-A1.8, REQ-A3.2; D-25, D-34), keyed off the
# bundle's declared format-version (this implementation: format-versions
# 1 and 2):
#
#   1. Four-file presence.
#   2. Header block: Status declared (missing warns, defaults to Draft);
#      one of the six statuses (Draft, Ready, Active, Done, Retired,
#      Superseded); Superseded requires `Superseded-by:`; Format-version
#      declared; Status mirrors kept in sync.
#   3. Spec-identifier charset and length; underscore-accumulator name
#      screening (accumulators are skipped, not validated as bundles).
#   4. REQ-ID convention: ID-bearing bullets, citation per live REQ
#      (superseded records exempt), no duplicate IDs.
#   5. D-ID structure: Decision / Alternatives considered / Chosen because.
#   6. Task structure: well-formed stable ID plus the five definition fields.
#   7. REQ↔test-spec coverage (exact-id matching, never substring).
#   8. Stable-ID discipline: duplicates rejected; against the baseline ref,
#      a vanished (renumbered/removed) ID is flagged; a supersede passes,
#      and a supersede newly introduced since the baseline must carry a
#      dated Changelog entry naming the superseded ID (REQ-A3.3). A removed
#      TASK block has the mirror-image escape: a dated Changelog entry
#      naming `Task <id>` authorizes the removal, and nothing else does
#      (REQ-D1.6, D-12).
#   9. Terminal-state discipline: no transition out of Retired/Superseded
#      relative to the baseline ref.
#  10. Fence balance: an unclosed column-0 code fence is flagged per file
#      (REQ-D1.11). Every content parse above reads through the shared
#      grammar lib's fence lexer, so fenced illustration is documentation
#      rather than content in both directions — it neither raises findings
#      of its own nor satisfies a check a real record would (REQ-C1.2).
#
# Format-version 2 (the invariant ledger; invariant-tasks REQ-C1.5,
# REQ-C1.8, REQ-C1.9, REQ-D1.1 · D-3, D-5, D-7) adds, for v2 bundles only:
#
#   11. No placement sections: `## Forward plan`, `## In progress`, and
#       `## Completed` do not exist (task blocks live in `## Tasks`).
#   12. No state annotation bullets: `Status`, `Last activity`, and
#       `Dispatch` bullets do not exist in task blocks (the three
#       state-annotation tokens the format defines; other bullets are not
#       this check's concern).
#   13. Stored `Status:` restricted to the human-gated set — Draft, Ready,
#       Retired, Superseded; Active and Done are derived, never stored.
#   14. The static pointer line `**Execution:** derived — see the status
#       render` present in every file's header, in its fixed vocabulary.
#   15. Reference-bullet integrity in the human-payload sections: every
#       `**Task <id>**` bullet names an existing task id, ids pass the
#       task-id grammar before any use, and a task is parked by at most
#       one bullet across all three sections.
#
# Version keying is fail-closed (REQ-C1.8): a missing or unparseable
# `Format-version:` is an error at every status — the rules to apply cannot
# be known without a parsed version — and neither version's extra rules are
# applied. Unparseable includes a DUPLICATE in-header `Format-version:` or
# `Status:` declaration (REQ-A1.2, REQ-D1.9), which has no honest positional
# winner; so does a header block or reference-bullet parse the shared grammar
# lib refused (a NUL byte, or end-of-file inside an open column-0 fence). The declaration is read from requirements.md; when that file is
# absent it falls back to the sibling mirrors (agreeing siblings resolve,
# disagreeing siblings are a hard error). v1 bundles keep the v1 rules
# unchanged (REQ-D1.1).
#
# Severity (status-aware, D-25): findings are warnings on Draft, errors on
# Ready, Active, and Done (signed-off live content — Ready is signed off and
# executable), warnings on Retired/Superseded (frozen records do not block
# CI). Integrity violations are errors regardless of status: an unknown
# status, a missing/unparseable/unsupported format-version,
# Superseded without its pointer, duplicate IDs, identifier-charset
# violations, and a transition out of a terminal state.
#
# Usage:
#   spec-validate.sh [--baseline <ref>] <specs-root | spec-dir>
#   spec-validate.sh --check-id <identifier>
#
# A path containing any of the four spec files is validated as a single
# bundle; any other directory is treated as a specs root and its direct
# children are screened and validated. A symlinked directory in the root is
# a hard error (a silent skip would be a bundle CI never checks); plain
# files, symlinks to files, and hidden entries (tooling artifacts) are
# ignored. The baseline for stable-ID and
# terminal-state checks defaults to origin/main when it resolves (it is
# skipped quietly otherwise: a brand-new repo with no remote degrades
# gracefully per REQ-K1.7); --baseline makes it explicit and fatal when
# unresolvable. --check-id validates a proposed spec identifier string,
# full-string, for skills to call before any path or command is formed
# (REQ-A1.8); the hostile input is never echoed back.
#
# Exit codes: 0 no errors (warnings allowed), 1 errors found (or an invalid
# --check-id identifier), 2 usage or environment error.
#
# Portable: /bin/sh + awk + grep + git as shipped on macOS (bash 3.2, BSD
# userland) and Linux (GNU userland) — the REQ-K1.5 envelope. Two utilities
# used here sit outside strict POSIX but ship on every targeted platform:
# mktemp(1) and grep -o. No eval; input treated as data only.
set -eu

# Pin the C locale: charset checks and awk/grep ranges must not vary by
# host locale collation.
LC_ALL=C
export LC_ALL

unset CDPATH
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Canonical echo-discipline sanitizer (doctrine/security-posture.md): strip
# non-printables off repo-controlled input before it reaches the terminal.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

# The shared spec-parse grammar lib (format-grammar D-3, D-4; REQ-B1.3,
# REQ-B1.4): the header-block declaration parse behind hb_load/hb_get and the v2
# parked-map parse below come from it, so this validator cannot re-diverge from
# its three sibling v2 parsers. Sourced, never executed; fail closed when it is
# missing or unreadable (REQ-B1.6a).
spec_parse_sh="$script_dir/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  printf '%s\n' "spec-validate: required helper $(sanitize_printable "$spec_parse_sh") missing or not readable" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

usage() {
  echo "usage: spec-validate.sh [--baseline <ref>] <specs-root-or-spec-dir>" >&2
  echo "       spec-validate.sh --check-id <identifier>" >&2
  exit 2
}

# Full-string spec-identifier check (REQ-A1.8): ^[a-z0-9][a-z0-9-]*$, max 64.
check_spec_id() {
  cid=$1
  [ -n "$cid" ] || return 1
  [ "${#cid}" -le 64 ] || return 1
  case $cid in
    [a-z0-9]*) ;;
    *) return 1 ;;
  esac
  case $cid in
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# Accumulator-name screen (REQ-A1.8): ^_[a-z0-9][a-z0-9-]*$, max 64.
check_accumulator_name() {
  anm=$1
  [ "${#anm}" -le 64 ] || return 1
  case $anm in
    _*) ;;
    *) return 1 ;;
  esac
  check_spec_id "${anm#_}"
}

baseline=origin/main
explicit_baseline=0
target=
while [ $# -gt 0 ]; do
  case $1 in
    --check-id)
      [ $# -eq 2 ] || usage
      if check_spec_id "$2"; then
        exit 0
      fi
      # Never echo the candidate back: a hostile identifier must not reach
      # any output a caller might interpolate.
      echo "spec-validate: invalid spec identifier (must match ^[a-z0-9][a-z0-9-]*\$, max length 64)" >&2
      exit 1
      ;;
    --baseline)
      [ $# -ge 2 ] || usage
      baseline=$2
      explicit_baseline=1
      shift 2
      ;;
    -*)
      usage
      ;;
    *)
      [ -z "$target" ] || usage
      target=$1
      shift
      ;;
  esac
done

[ -n "$target" ] || usage
while [ "$target" != "${target%/}" ]; do target=${target%/}; done
if [ ! -d "$target" ]; then
  echo "spec-validate: not a directory: $target" >&2
  exit 2
fi

gtmp=$(mktemp -d)
trap 'rm -rf "$gtmp"' EXIT

err=0
warn=0
tab=$(printf '\t')

# emit_error <name> <msg> — report a root-level screening error and count
# it. The name is repo-controlled input that failed (or never reached) the
# charset screen, so non-printables are stripped before echoing (REQ-H1.3
# echo discipline), with a placeholder when nothing printable remains.
emit_error() {
  en=$(sanitize_printable "$1" "(unprintable name)")
  printf 'spec-validate: ERROR %s: %s\n' "$en" "$2"
  err=$((err + 1))
}

# hb_load <file> <label> — capture <file>'s whole header block into $hb_stream
# with ONE lib invocation, so the three-to-four declarations this validator reads
# per file cost one call rather than one each (the lib's batched entry point,
# D-3's batchability clause). An unreadable or NUL-bearing file lands a `hard`
# finding — an error at EVERY status per D-9's fail-closed exception to the D-25
# severity model — and leaves an empty stream, so the bundle then follows the
# existing missing-declaration path instead of a guessed one.
#
# $hb_path memoizes the last loaded path, so the two-to-three declarations a
# single visit reads really do cost one lib call. It is a single slot on purpose:
# validate_bundle walks the sibling files in two separate loops (Status /
# Format-version mirrors, then the **Execution:** pointer), so a per-file cache
# would buy one avoided call per file at the cost of carrying four streams.
#
# The FAILURE report is memoized separately, by path, because that interleaving
# does defeat the single slot: a file whose header block cannot be read is
# revisited by the second loop and would otherwise land the SAME `hard` finding
# twice, reporting one root cause as two errors and inflating the bundle's error
# total. validate_bundle resets both memos per bundle.
#
# The lib's own stderr is captured and folded into the finding rather than left to
# print raw, matching how the parked-map call site below handles its diagnostic
# and how the other consumers (drain-gates.sh, check-ledger.sh, tasks-pr-sync.sh)
# keep their report the single output surface.
hb_path=
hb_stream=
hb_failed=
hb_load() {
  if [ "$hb_path" = "$1" ]; then
    return 0
  fi
  hb_path=$1
  if hb_stream=$(spec_parse_header_block "$1" 2>"$gtmp/hb.err"); then
    return 0
  fi
  hb_stream=
  if set_in "$1" "$hb_failed"; then
    return 0
  fi
  hb_failed="$hb_failed$1
"
  printf 'hard\t%s: could not read the header block (unreadable or NUL-bearing file; fail closed): %s\n' \
    "$2" "$(sanitize_printable "$(cat "$gtmp/hb.err" 2>/dev/null)" "(no diagnostic)")" >>"$fnd"
  return 0
}

# hb_get <key> <label> — the value of <key> from the $hb_stream hb_load
# captured. A `hdrdup` record means the declaration is unparseable (more than
# one in-header `Format-version:`/`Status:`, REQ-A1.2, REQ-D1.9, D-6): it lands a
# `hard` finding and resolves to empty, never to a positional winner. Callable
# inside a command substitution — the finding is appended to the $fnd file,
# which survives the subshell.
#
# The lookup and the echo-discipline strip are done WITHOUT spawning a process on
# the common path: the lib emits raw bytes (REQ-B1.6c) and this is the caller's
# output-site boundary, but a value whose every byte is printable ASCII is
# already what the strip would produce, and the lib already trimmed its trailing
# whitespace. Only a value carrying a byte outside 0x20-0x7E (a control byte, or
# the UTF-8 lead bytes of the em-dash in the `Execution:` pointer) pays the awk
# call — which strips high bytes exactly as the pre-lib in-awk form did.
hb_get() {
  hbg_key=$1
  hbg_label=$2
  hbg_val=
  hbg_dup=0
  while IFS="$tab" read -r hbg_tag hbg_k hbg_v; do
    [ "$hbg_k" = "$hbg_key" ] || continue
    case $hbg_tag in
      hdrdup) hbg_dup=1 ;;
      hdr) hbg_val=$hbg_v ;;
    esac
  done <<EOF
$hb_stream
EOF
  if [ "$hbg_dup" -eq 1 ]; then
    printf 'hard\t%s: unparseable %s: declaration (more than one in-header declaration has no honest positional winner; fail closed)\n' \
      "$hbg_label" "$hbg_key" >>"$fnd"
    return 0
  fi
  case $hbg_val in
    *[!\ -~]*)
      hbg_val=$(printf '%s' "$hbg_val" \
        | awk '{ gsub(/[^[:print:]]/, ""); sub(/[ \t]+$/, ""); print }')
      ;;
  esac
  printf '%s' "$hbg_val"
}

# defence <file|-> — emit the source with fenced illustration removed, for the
# grep-shaped checks below (format-grammar Task 6; REQ-C1.2 · D-5). The awk
# parses prepend $spec_parse_awk_fence directly instead, which keeps NR the
# source line number for findings that cite one; a grep has no line number to
# preserve, so a filter is the simpler form there.
#
# An UNCLOSED fence leaves this emitting only the lines before it. That is the
# lexer's defined behavior and it is safe here because the imbalance carries its
# own finding (REQ-D1.11) — a reader is told the file is malformed rather than
# left to wonder why a later check went quiet.
defence() {
  if [ "$1" = - ]; then
    LC_ALL=C awk "$spec_parse_awk_fence"'{ print }'
  else
    LC_ALL=C awk "$spec_parse_awk_fence"'{ print }' <"$1"
  fi
}

# debaseline <blob> <file-label> — the BASELINE half of a stable-ID diff, fence
# -stripped to match the current half (REQ-C1.2) without inheriting defence's
# truncation as a fail-open.
#
# The safety the comment above rests on is the REQ-D1.11 flag, and that flag
# reads the working tree — never the git object a baseline comes from. So a
# baseline whose fence is unbalanced would be stripped down to whatever sat
# above the fence, silently, and every id below it would read as "never defined
# at the baseline" rather than as removed. On a guard whose entire job is
# catching removals that is the fail-open direction, and it is invisible: the
# current file can be perfectly well-formed while the comparison quietly runs on
# a fraction of the baseline.
#
# So the baseline is balance-checked in its own right, and on imbalance the
# comparison falls back to the RAW blob. Over-reporting (a fenced mock id read
# as removed) is the fail-closed error and the accompanying finding names the
# revision that is actually malformed, so the author is never left guessing
# which side of the diff to fix.
#
# The probe's status is read for what it says rather than for truthiness: 3 is
# the imbalance, and anything else non-zero means the fence state could not be
# established at all. Both fall back to the raw blob, so the posture does not
# turn on the distinction — the message does, and a confident "unclosed fence"
# printed against a file that has none would send the author to the wrong file.
debaseline() {
  dbl_rc=0
  printf '%s\n' "$1" | spec_parse_fence_balance - >/dev/null 2>&1 || dbl_rc=$?
  case $dbl_rc in
    0)
      printf '%s\n' "$1" | defence -
      return 0
      ;;
    3)
      printf 'gap\t%s: unclosed column-0 code fence in the %s baseline (its ids are compared unstripped, so a fenced mock id there may read as removed)\n' \
        "$2" "$baseline" >>"$fnd"
      ;;
    *)
      printf 'gap\t%s: could not establish the fence state of the %s baseline (probe exit %s; its ids are compared unstripped)\n' \
        "$2" "$baseline" "$dbl_rc" >>"$fnd"
      ;;
  esac
  printf '%s\n' "$1"
}

# Parse requirements.md REQ blocks. Tagged tab-separated output:
#   F <tab> gap|hard <tab> message     — a finding
#   ALL <tab> id                       — every defined REQ-ID
#   LIVE <tab> id                      — REQ-IDs not marked Superseded-by
#
# Fence-aware via the shared lexer (REQ-C1.2): a bundle that documents the REQ
# bullet form inside a fence is showing an example, not declaring a second REQ
# with the id it illustrates — the false duplicate-REQ error this landing fixes.
#
# The bullet grammar itself is the shared lib's (format-grammar Task 8;
# REQ-B1.5): the validator, the selector, and the bundle reader now read one
# definition of what a requirement bullet is.
parse_requirements() {
  awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
    function flush() {
      if (cur == "") return
      if (sup) {
        printf "SUP\t%s\n", cur
      } else {
        printf "LIVE\t%s\n", cur
        if (!cites)
          printf "F\tgap\t%s has no citation annotation (*(Cites: ...)*)\n", cur
      }
      cur = ""
    }
    /^## / { flush(); ingroup = ($0 ~ /^## REQ-/); next }
    !ingroup { next }
    /^- / {
      flush()
      id = spec_parse_req_bullet_id($0)
      if (id != "") {
        printf "ALL\t%s\n", id
        if (id in seen) printf "F\thard\tduplicate REQ-ID %s\n", id
        seen[id] = 1
        cur = id
        cites = ($0 ~ /\(Cites:/)
        sup = ($0 ~ /\*\*Superseded-by: REQ-/)
      } else {
        printf "F\tgap\tprose-only bullet or non-conforming REQ-ID at requirements.md:%d (expected REQ-<letter><n>.<m>)\n", NR
      }
      next
    }
    cur != "" {
      if ($0 ~ /\(Cites:/) cites = 1
      if ($0 ~ /\*\*Superseded-by: REQ-/) sup = 1
    }
    END { flush() }
  ' "$1"
}

# Parse design.md D-ID sections. Same tagged tab-separated format as
# parse_requirements: F findings, plus every D-ID tagged ALLD. Fence-aware
# via the shared lexer (REQ-C1.2), with the heading grammar itself from the
# shared lib (Task 8; REQ-B1.5).
parse_design() {
  awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
    function flush() {
      if (cur == "") return
      if (!hd) printf "F\tgap\t%s missing field: Decision\n", cur
      if (!ha) printf "F\tgap\t%s missing field: Alternatives considered\n", cur
      if (!hc) printf "F\tgap\t%s missing field: Chosen because\n", cur
      cur = ""
    }
    spec_parse_dec_attempt($0) {
      flush()
      id = spec_parse_dec_id($0)
      if (id == "") {
        # D- prefix without the <n>: shape: surface it rather than silently
        # treating a typo as ordinary prose (mirror of the malformed-task rule).
        printf "F\tgap\tmalformed decision heading at design.md:%d (expected ### D-<n>: <title>)\n", NR
        next
      }
      printf "ALLD\t%s\n", id
      if (id in seen) printf "F\thard\tduplicate D-ID %s\n", id
      seen[id] = 1
      cur = id
      hd = ha = hc = 0
      next
    }
    /^## / || /^### / { flush(); next }
    cur != "" {
      if ($0 ~ /^\*\*Decision:\*\*/) hd = 1
      if ($0 ~ /^\*\*Alternatives considered:\*\*/) ha = 1
      if ($0 ~ /^\*\*Chosen because:\*\*/) hc = 1
    }
    END { flush() }
  ' "$1"
}

# Parse tasks.md task blocks. Same tagged tab-separated format as
# parse_requirements: F findings, plus every well-formed task id tagged ALLT.
# Fence-aware via the shared lexer (REQ-C1.2): a fenced mock block neither
# duplicates the id it illustrates nor reports the definition fields it omits.
# The heading and definition-field grammars are the shared lib's (Task 8;
# REQ-B1.5), so "which five bullets are a task definition" has one answer here,
# in the canonical extraction, and in the bundle reader.
parse_tasks() {
  awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
    function flush() {
      if (cur == "") return
      if (!fdel) printf "F\tgap\tTask %s missing field: Deliverables\n", cur
      if (!fdw) printf "F\tgap\tTask %s missing field: Done when\n", cur
      if (!fdep) printf "F\tgap\tTask %s missing field: Dependencies\n", cur
      if (!fcit) printf "F\tgap\tTask %s missing field: Citations\n", cur
      if (!feff) printf "F\tgap\tTask %s missing field: Estimated effort\n", cur
      cur = ""
    }
    /^## / { flush(); next }
    spec_parse_is_task_heading($0) {
      flush()
      id = spec_parse_task_id($0)
      if (id == "") {
        printf "F\tgap\tmalformed task id at tasks.md:%d (expected <n> or <n>.<m>)\n", NR
        next
      }
      printf "ALLT\t%s\n", id
      if (id in seen) printf "F\thard\tduplicate task id: Task %s\n", id
      seen[id] = 1
      cur = id
      fdel = fdw = fdep = fcit = feff = 0
      next
    }
    /^### / { flush(); next }
    cur == "" { next }
    {
      fld = spec_parse_task_field($0)
      if (fld == "deliverables") fdel = 1
      else if (fld == "donewhen") fdw = 1
      else if (fld == "dependencies") fdep = 1
      else if (fld == "citations") fcit = 1
      else if (fld == "effort") feff = 1
    }
    END { flush() }
  ' "$1"
}

# Parse a format-version 2 tasks.md for the invariant-ledger rules
# (REQ-C1.5, D-3): banned placement sections, banned state-annotation
# bullets, and reference-bullet integrity in the human-payload sections.
# Tagged tab-separated output:
#   F <tab> gap <tab> message   — a finding (embedded values are either
#                                 fixed vocabulary or grammar-validated ids)
#   TID <tab> id                — every well-formed task id defined in the file,
#                                 for the reference-bullet cross-check below
#
# Reference-bullet classification is NOT here: it comes from the shared lib's
# parked-map parse (scripts/spec-parse.sh, REQ-B1.4), so this validator applies
# the same single v2 posture as its three sibling parsers — fences as
# illustration, CRLF-tolerant section headings, prose tolerance, near-miss
# rejection. reference_bullet_findings() below consumes those records. The
# banned-heading and banned-annotation scan here takes the same fence lexer, so
# a fenced example of a version-1 tasks.md is documentation rather than a ban
# violation (REQ-C1.2).
parse_tasks_v2() {
  awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
    # Normalize a trailing CR first: the heading arms below are
    # EOL-anchored, and a CRLF-saved file must not slip a banned heading
    # past the ban (or hide a payload section) on line endings alone.
    { sub(/\r$/, "") }
    # Headings are matched with trailing-whitespace tolerance: an exact
    # `==` would let a hand-edited "## Completed " escape the placement
    # ban (fail-open) or hide a payload section from the integrity checks.
    # Suffixed variants ("## Completed (legacy)") stay ordinary headings:
    # canonical heading form belongs to the ledger guard, not this parser.
    function banned(nm, ln) {
      printf "F\tgap\tplacement section \"## %s\" at tasks.md:%d does not exist in format-version 2 (task blocks live in \"## Tasks\"; execution state is derived)\n", nm, ln
    }
    /^## Forward plan[ \t]*$/  { section = ""; in_task = 0; banned("Forward plan", NR); next }
    /^## In progress[ \t]*$/   { section = ""; in_task = 0; banned("In progress", NR); next }
    /^## Completed[ \t]*$/     { section = ""; in_task = 0; banned("Completed", NR); next }
    /^## Awaiting input[ \t]*$/ { section = "Awaiting input"; in_task = 0; next }
    /^## Deferred[ \t]*$/       { section = "Deferred"; in_task = 0; next }
    /^## Out of scope[ \t]*$/   { section = "Out of scope"; in_task = 0; next }
    /^## / { section = ""; in_task = 0; next }
    spec_parse_is_task_heading($0) {
      in_task = 1
      curid = spec_parse_task_id($0)
      if (curid != "") printf "TID\t%s\n", curid
      next
    }
    /^### / { in_task = 0; next }
    in_task && /^- \*\*(Status|Last activity|Dispatch):\*\*/ {
      tok = substr($0, 5)
      sub(/:\*\*.*$/, "", tok)
      if (curid != "") loc = "Task " curid; else loc = "tasks.md:" NR
      printf "F\tgap\tstate annotation bullet \"%s\" on %s does not exist in format-version 2 (the Status, Last activity, and Dispatch state annotations are derived state, never stored)\n", tok, loc
      next
    }
  ' "$1"
}

# reference_bullet_findings <TID-stream> <parked-map-stream> — the v2
# reference-bullet integrity checks, over the shared lib's parked-map records
# (REQ-B1.4): every reference names an existing task id, and a task is parked by
# at most one bullet across all three sections. Tagged output, same shapes the
# callers already consume:
#   F  <tab> gap <tab> message   — a finding
#   RB <tab> line <tab> raw-id   — a grammar-violating reference-bullet token,
#                                  raw (whitespace-free of tabs and newlines by
#                                  the lib's framing); the caller routes it
#                                  through sanitize_printable before echoing
#                                  (REQ-C1.9)
# The lib emits class atoms; the section NAMES are restored here so the finding
# text is unchanged.
reference_bullet_findings() {
  # The id file is discriminated by FILENAME, not the FNR == NR idiom: a v2
  # bundle can legitimately define zero task blocks, and with an EMPTY first
  # file FNR == NR is true for the second file's first record, silently eating
  # the first reference bullet (the classic empty-first-file gotcha).
  #
  # Compared against ARGV[1] rather than a `-v idsfile=` copy of the same path:
  # awk escape-processes a -v assignment's VALUE, so a $gtmp path carrying a
  # backslash escape (GNU mktemp -d honours TMPDIR) would reach the program with
  # `\t` rewritten to a tab, never match FILENAME, leave ids[] empty, and report
  # every reference bullet as naming an unknown task id. ARGV holds the operand
  # verbatim. The sibling multi-file readers avoid -v for this too
  # (fleet-status.sh matches FILENAME against a suffix pattern).
  awk -F"$tab" '
    function label(c) {
      if (c == "awaiting-input") return "Awaiting input"
      if (c == "deferred") return "Deferred"
      if (c == "out-of-scope") return "Out of scope"
      return c
    }
    FILENAME == ARGV[1] { if ($1 == "TID") ids[$2] = 1; next }
    $1 == "refbad" { printf "RB\t%s\t%s\n", $4, $2; next }
    $1 == "ref" {
      rid = $2
      sec = label($3)
      nr = $4
      if (!(rid in ids))
        printf "F\tgap\treference bullet at tasks.md:%s names unknown task id %s (%s)\n", nr, rid, sec
      if (rid in seensec) {
        if (seensec[rid] == sec)
          printf "F\tgap\tTask %s is named by more than one reference bullet (twice in %s; a task is parked in one section at a time)\n", rid, sec
        else
          printf "F\tgap\tTask %s is named by more than one reference bullet (%s and %s; a task is parked in one section at a time)\n", rid, seensec[rid], sec
      } else
        seensec[rid] = sec
    }
  ' "$1" "$2"
}

# set_in <needle> <newline-list> — exact-membership test.
set_in() {
  printf '%s\n' "$2" | grep -qxF "$1"
}

# task_retirement_named <task-id> — the REQ-D1.6 / D-12 retirement escape:
# does $clog carry a DATED entry naming this task id? Where a task block
# genuinely must leave the file, that entry authorizes the removal — the escape
# REQ supersession already has, and the only one the stable-ID check accepts.
#
# The recognized form is the meta-spec's own task-reference citation, `Task
# <id>`, and a bare number does not count. That qualifier is doing real work
# rather than ceremony: a task id is digits and dots, so an unqualified token
# cannot be told apart from a date component (any entry dated the 7th would
# authorize retiring Task 7), an issue number, or any other number in the
# prose. The REQ-supersede sibling needs no such qualifier because a REQ id
# carries a letter.
#
# The extracted token is validated against the task-id grammar before the
# comparison (REQ-D1.6), a gate kept distinct from the equality test so a
# grammar-violating "Task 7a" cannot authorize anything even by accident.
#
# The tokenizer mirrors the REQ-supersede matcher: awk tracks whether the line
# is part of a dated `- <YYYY-MM-DD> …` bullet (entries span lines and the id
# often sits on a continuation), tokenizes on non-id characters, and compares
# exactly, so a sentence-final "Task 7." matches while "Task 70" does not.
#
# Where it must NOT mirror the sibling: this citation is two tokens, and the
# sibling's is one. A REQ id survives any wrap because it is a single word, but
# `Task <id>` straddles one whenever the wrap lands between them — and changelog
# prose here is hand-wrapped, so that is a matter of time, not of malice. So the
# scan runs over the whole dated entry joined into one buffer rather than over
# each line, and the accumulation stops at the next bullet: joining across
# entries would let a trailing "Task" in one and a leading id in the next invent
# an authorization neither records.
task_retirement_named() {
  printf '%s\n' "$clog" | awk -v id="$1" '
    function names_id(buf,   n, t, i, tok) {
      gsub(/[^A-Za-z0-9.]/, " ", buf)
      n = split(buf, t, " ")
      for (i = 1; i < n; i++) {
        if (t[i] != "Task") continue
        tok = t[i + 1]
        sub(/\.$/, "", tok)
        if (tok !~ /^[0-9]+(\.[0-9]+)?$/) continue
        if (tok == id) return 1
      }
      return 0
    }
    /^- / {
      if (dated && names_id(entry)) { found = 1; exit }
      dated = ($0 ~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
      entry = dated ? $0 : ""
      next
    }
    dated { entry = entry " " $0 }
    END {
      if (!found && dated && names_id(entry)) found = 1
      exit(found ? 0 : 1)
    }
  '
}

# Baseline checks for one bundle: terminal-state discipline and the
# stable-ID never-reused rule, against $baseline. Appends to $fnd. Skipped
# quietly when the bundle is not in a git work tree or the default baseline
# does not resolve; an explicit --baseline that cannot be used is fatal.
baseline_checks() {
  bdir=$1
  if ! git -C "$bdir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ "$explicit_baseline" -eq 1 ]; then
      echo "spec-validate: --baseline given but $bdir is not in a git work tree" >&2
      exit 2
    fi
    return 0
  fi
  # 2>/dev/null as well as --quiet: --quiet silences the missing-ref case
  # but a failed ^{commit} peel (ref exists, wrong object type) still prints
  # "error: ..." — the probe is a yes/no check and must stay quiet on the
  # default-baseline skip path.
  if ! git -C "$bdir" rev-parse --verify --quiet "$baseline^{commit}" >/dev/null 2>&1; then
    if [ "$explicit_baseline" -eq 1 ]; then
      echo "spec-validate: baseline ref does not resolve: $baseline" >&2
      exit 2
    fi
    return 0
  fi

  old_req=$(git -C "$bdir" show "$baseline:./requirements.md" 2>/dev/null) || old_req=
  old_des=$(git -C "$bdir" show "$baseline:./design.md" 2>/dev/null) || old_des=
  old_tsk=$(git -C "$bdir" show "$baseline:./tasks.md" 2>/dev/null) || old_tsk=

  # The current bundle's `## Changelog` body, loaded once for both escapes that
  # read it: REQ-A3.3's changelog-on-supersede and REQ-D1.6's task retirement.
  # Fence-aware (REQ-C1.2) at both ends — a fenced changelog example is
  # illustration, and a fenced `## ` heading does not close the section early.
  # Empty when requirements.md is absent, which leaves both escapes inactive;
  # the missing-file gap already carries that case (REQ-K1.7).
  clog=
  if [ -f "$bdir/requirements.md" ]; then
    clog=$(defence "$bdir/requirements.md" | awk '
      tolower($0) ~ /^## changelog/ { f = 1; next }
      /^## / { f = 0 }
      f
    ') || clog=
  fi

  if [ -n "$old_req" ]; then
    # The baseline blob's stored status, through the shared lib's
    # header-block-scoped parse (REQ-B1.3) fed from stdin — the blob has no path
    # to hand it. An unparseable baseline declaration (a duplicate in-header
    # `Status:`, REQ-A1.2) leaves the terminal-transition check with nothing
    # trustworthy to compare against, so it is surfaced rather than silently
    # skipped; the CURRENT file's own duplicate carries its own hard finding.
    if old_status=$(printf '%s\n' "$old_req" | spec_parse_header_value - Status); then
      old_status=$(printf '%s' "$old_status" \
        | awk '{ gsub(/[^[:print:]]/, ""); sub(/[ \t]+$/, ""); print }')
    else
      printf 'gap\tunparseable Status: declaration in requirements.md at %s; the terminal-state transition check could not run\n' \
        "$baseline" >>"$fnd"
      old_status=
    fi
    case $old_status in
      Retired | Superseded)
        if [ "$declared_status" != "$old_status" ]; then
          printf 'hard\ttransition out of terminal status (was %s at %s, now %s)\n' \
            "$old_status" "$baseline" "${declared_status:-Draft}" >>"$fnd"
        fi
        ;;
    esac
    # Fence-stripped before the id sweep (REQ-C1.2): both halves of the
    # stable-ID diff have to parse the same grammar, or a fenced mock id
    # present in BOTH revisions reads as an id that vanished.
    old_ids=$(debaseline "$old_req" requirements.md \
      | awk "$spec_parse_awk_grammar"'
        { id = spec_parse_req_bullet_id($0); if (id != "") print id }
      ') || old_ids=
    printf '%s\n' "$old_ids" | while read -r oid; do
      [ -n "$oid" ] || continue
      set_in "$oid" "$all_req_ids" \
        || printf 'gap\t%s renumbered or removed since %s (stable IDs are never reused; supersede instead)\n' \
          "$oid" "$baseline" >>"$fnd"
    done

    # Changelog-on-supersede (REQ-A3.3, D-20): a REQ newly marked
    # `Superseded-by` since the baseline must be named in a dated Changelog
    # entry — the supersede pointer records the lineage, the changelog records
    # the why-it-changed. The current superseded set is diffed against the
    # baseline's so a supersede already recorded upstream is not re-flagged.
    # Status-scoped like the other stable-ID findings (warn on Draft, error on
    # Ready/Active/Done). REQ supersedes only: that is the parseable, marked case.
    # Guarded on the current file existing: a bundle that deletes
    # requirements.md still has a non-empty baseline `$old_req`, and parsing a
    # now-missing file would leak raw awk errors and abort under set -eu — the
    # missing-file gap already covers that case (REQ-K1.7 graceful degradation).
    if [ -f "$bdir/requirements.md" ]; then
      printf '%s\n' "$old_req" >"$gtmp/old_req"
      old_sup=$(parse_requirements "$gtmp/old_req" | awk -F"$tab" '$1 == "SUP" { print $2 }')
      cur_sup=$(parse_requirements "$bdir/requirements.md" | awk -F"$tab" '$1 == "SUP" { print $2 }')
      printf '%s\n' "$cur_sup" | while read -r sid; do
        [ -n "$sid" ] || continue
        if set_in "$sid" "$old_sup"; then continue; fi
        # Name the bare id (REQ- stripped) as a whole token, inside a dated
        # Changelog entry (REQ-A3.3). awk tracks whether the current line is
        # part of a dated bullet entry — a `- <YYYY-MM-DD> …` bullet, or one of
        # its continuation lines, since entries span multiple lines and the id
        # often sits on a continuation (e.g. "REQ-B2.4 supersedes REQ-B2.1") —
        # and only scans those, so an undated bullet that names the id does not
        # satisfy the check. On a dated line it tokenizes on non-id characters
        # and compares exactly: the bare "X1.2", a prefixed "REQ-X1.2", and a
        # sentence-final "X1.2." match, while a longer id it only prefixes
        # ("X1.20", "X1.2.alpha") does not. awk, not grep -E, because anchors
        # inside an alternation (`(^|…)` / `($|…)`) match unreliably on BSD
        # grep; exact compare, so the id needs no regex-escaping.
        if printf '%s\n' "$clog" | awk -v id="${sid#REQ-}" '
          /^- / { dated = ($0 ~ /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) }
          dated {
            line = $0
            gsub(/[^A-Za-z0-9.]/, " ", line)
            n = split(line, t, " ")
            for (i = 1; i <= n; i++) {
              tok = t[i]
              sub(/\.$/, "", tok)
              if (tok == id) { found = 1; exit }
            }
          }
          END { exit(found ? 0 : 1) }
        '; then
          :
        else
          printf 'gap\t%s newly superseded since %s without a matching Changelog entry (REQ-A3.3: a supersede needs a dated Changelog entry naming it)\n' \
            "$sid" "$baseline" >>"$fnd"
        fi
      done
    fi
  fi
  if [ -n "$old_des" ]; then
    old_ids=$(debaseline "$old_des" design.md \
      | awk "$spec_parse_awk_grammar"'
        { id = spec_parse_dec_id($0); if (id != "") print id }
      ') || old_ids=
    printf '%s\n' "$old_ids" | while read -r oid; do
      [ -n "$oid" ] || continue
      set_in "$oid" "$all_d_ids" \
        || printf 'gap\t%s renumbered or removed since %s (stable IDs are never reused; supersede instead)\n' \
          "$oid" "$baseline" >>"$fnd"
    done
  fi
  if [ -n "$old_tsk" ]; then
    old_ids=$(debaseline "$old_tsk" tasks.md \
      | awk "$spec_parse_awk_grammar"'
        { id = spec_parse_task_id($0); if (id != "") print id }
      ') || old_ids=
    printf '%s\n' "$old_ids" | while read -r oid; do
      [ -n "$oid" ] || continue
      if set_in "$oid" "$all_t_ids"; then
        continue
      fi
      # REQ-D1.6 / D-12: the changelog-named retirement escape, mirroring the
      # REQ supersession path above. Without it the validator carries the
      # asymmetry that forced a hand workaround the last time a task had to
      # leave a bundle: REQs could retire via the changelog and tasks could not.
      if task_retirement_named "$oid"; then
        continue
      fi
      printf 'gap\tTask %s renumbered or removed since %s (stable IDs are never reused; retire it with a dated Changelog entry naming "Task %s")\n' \
        "$oid" "$baseline" "$oid" >>"$fnd"
    done
  fi
}

# validate_bundle <dir> <name> — run every bundle check, print the
# severity-mapped findings, and update the global err/warn counters. Sets
# the globals declared_status / live_req_ids / all_req_ids / all_d_ids /
# all_t_ids (reset here on every call; baseline_checks reads them).
validate_bundle() {
  bdir=$1
  bname=$2
  fnd="$gtmp/findings"
  : >"$fnd"
  # The hb_load memos are per bundle: $fnd is truncated here, so a failure
  # report suppressed across bundles would go missing rather than de-duplicate.
  hb_path=
  hb_failed=

  for bf in requirements.md design.md tasks.md test-spec.md; do
    [ -f "$bdir/$bf" ] || printf 'gap\tmissing file: %s\n' "$bf" >>"$fnd"
  done

  # Unbalanced column-0 fence (REQ-D1.11, D-5). Checked before anything reads
  # the file's content, because this is the finding that explains every other
  # check's silence: under the fence grammar an unterminated fence turns the
  # rest of the file into illustration, dropping content from every parser at
  # once. Status-scoped per the D-9 severity model; the fence-aware parses below
  # still run, so whatever is visible above the fence is still reported.
  for bf in requirements.md design.md tasks.md test-spec.md; do
    [ -f "$bdir/$bf" ] || continue
    fbrc=0
    fbline=$(spec_parse_fence_balance "$bdir/$bf" 2>"$gtmp/fence.err") || fbrc=$?
    case $fbrc in
      0) ;;
      3)
        # $fbline is an awk NR: a bare integer, never parsed content.
        printf 'gap\t%s: unclosed column-0 code fence opened at line %s (an unbalanced fence silently parses the rest of the file as illustration)\n' \
          "$bf" "$fbline" >>"$fnd"
        ;;
      *)
        # Carry the lib's own reason (a NUL byte reads very differently from a
        # permission problem), sanitized at this output site like every other
        # echoed diagnostic — the sibling parked-map refusal does the same.
        printf 'hard\t%s: the fence-balance probe refused the file, so fenced illustration cannot be told from content (fail closed): %s\n' \
          "$bf" "$(sanitize_printable "$(cat "$gtmp/fence.err" 2>/dev/null)" "(no diagnostic)")" >>"$fnd"
        ;;
    esac
  done

  declared_status=
  live_req_ids=
  all_req_ids=
  all_d_ids=
  all_t_ids=
  fver=
  fver_conflict=
  bundle_ver=

  if [ ! -f "$bdir/requirements.md" ]; then
    # The authoritative Status home is absent: derive the severity status
    # from the first sibling mirror that declares one, so deleting
    # requirements.md cannot downgrade a Ready/Active bundle's errors to
    # warnings (same evasion class as an implicit-Draft mirror).
    for bf in design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      hb_load "$bdir/$bf" "$bf"
      declared_status=$(hb_get Status "$bf")
      [ -n "$declared_status" ] && break
    done
    # The format-version follows the same fallback (REQ-C1.8): deleting
    # requirements.md must not skip version keying, or a v2 bundle's
    # invariants would silently fail open while the file is absent. With
    # no authoritative file to arbitrate, disagreeing siblings fail
    # closed rather than resolving to whichever file comes first (a
    # drifted lower value would skip the v2 invariants silently).
    for bf in design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      hb_load "$bdir/$bf" "$bf"
      sfv=$(hb_get Format-version "$bf")
      [ -n "$sfv" ] || continue
      if [ -z "$fver" ]; then
        fver=$sfv
      elif [ "$sfv" != "$fver" ]; then
        fver_conflict=1
      fi
    done
    if [ -n "$fver_conflict" ]; then
      printf 'hard\tconflicting Format-version declarations across sibling files (fail-closed: no authoritative requirements.md to arbitrate)\n' >>"$fnd"
    fi
  fi

  if [ -f "$bdir/requirements.md" ]; then
    hb_load "$bdir/requirements.md" requirements.md
    declared_status=$(hb_get Status requirements.md)
    if [ -z "$declared_status" ]; then
      printf 'gap\tmissing Status: header (defaulting to Draft)\n' >>"$fnd"
      # The default participates in everything downstream (mirrors, severity,
      # baseline): an explicit Ready/Active mirror must not hide behind an absent
      # authoritative header.
      declared_status=Draft
    fi

    fver=$(hb_get Format-version requirements.md)

    if [ "$declared_status" = "Superseded" ]; then
      defence "$bdir/requirements.md" | grep -q '^\*\*Superseded-by:\*\*' \
        || printf 'hard\tSuperseded status requires a **Superseded-by:** pointer\n' >>"$fnd"
    fi

    parse_requirements "$bdir/requirements.md" >"$gtmp/tagged"
    awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged" >>"$fnd"
    live_req_ids=$(awk -F'\t' '$1 == "LIVE" { print $2 }' "$gtmp/tagged")
    all_req_ids=$(awk -F'\t' '$1 == "ALL" { print $2 }' "$gtmp/tagged")

    # Status mirrors, compared against the declared-or-defaulted status.
    # Format-version mirrors likewise (meta-spec: all four files carry the
    # same header block), compared only when requirements.md declares one —
    # unlike Status it has no specified default to mirror against.
    for bf in design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      hb_load "$bdir/$bf" "$bf"
      mst=$(hb_get Status "$bf")
      if [ -z "$mst" ]; then
        printf 'gap\t%s: missing Status: header (mirror of requirements.md)\n' "$bf" >>"$fnd"
      elif [ "$mst" != "$declared_status" ]; then
        printf 'gap\t%s: Status mirror mismatch: %s (requirements.md resolves %s)\n' \
          "$bf" "$mst" "$declared_status" >>"$fnd"
      fi
      if [ -n "$fver" ]; then
        mfv=$(hb_get Format-version "$bf")
        if [ -z "$mfv" ]; then
          printf 'gap\t%s: missing Format-version: header (mirror of requirements.md)\n' "$bf" >>"$fnd"
        elif [ "$mfv" != "$fver" ]; then
          printf 'gap\t%s: Format-version mirror mismatch: %s (requirements.md declares %s)\n' \
            "$bf" "$mfv" "$fver" >>"$fnd"
        fi
      fi
    done
  fi

  # Version keying is fail-closed (REQ-C1.8, D-7): a missing, empty, or
  # unparseable declaration is a hard error at every status — the rules to
  # apply cannot be known without a parsed version — and neither version's
  # extra rules run ($bundle_ver stays empty; the shared structural checks
  # still do). An undeclared numeric version is the REQ-A1.7 unsupported
  # error, equally hard. $fver comes from requirements.md (the
  # authoritative home) or, only when that file is absent, from the
  # agreeing sibling mirrors; a sibling conflict already carries its own
  # hard finding and skips keying entirely.
  [ -n "$fver_conflict" ] || case $fver in
    1 | 2)
      bundle_ver=$fver
      ;;
    '')
      printf 'hard\tmissing or empty Format-version: declaration (fail-closed: validation rules cannot be selected without a declared version)\n' >>"$fnd"
      ;;
    *[!0-9]*)
      printf 'hard\tunparseable format-version: %s (fail-closed: validation rules cannot be selected without a parsed version)\n' \
        "$(sanitize_printable "$fver" "(unprintable)")" >>"$fnd"
      ;;
    *)
      printf 'hard\tunsupported format-version: %s (this validator implements format-versions 1 and 2)\n' \
        "$(sanitize_printable "$fver" "(unprintable)")" >>"$fnd"
      ;;
  esac

  if [ "$bundle_ver" = "2" ]; then
    # v2 stored status is restricted to the human-gated set (D-4 via
    # REQ-C1.5): Active and Done are derived on demand, never stored. They
    # are gap-class findings, but a bundle declaring them maps to the
    # errors-block severity anyway, so they always block.
    case $declared_status in
      Draft | Ready | Retired | Superseded | '') ;;
      Active | Done)
        printf 'gap\tstored status %s is derived in format-version 2 (stored header restricted to Draft, Ready, Retired, Superseded)\n' \
          "$declared_status" >>"$fnd"
        ;;
      *)
        printf 'hard\tunknown status: %s (format-version 2 stores Draft, Ready, Retired, or Superseded)\n' \
          "$(sanitize_printable "$declared_status" "(unprintable)")" >>"$fnd"
        ;;
    esac
  else
    case $declared_status in
      Draft | Ready | Active | Done | Retired | Superseded | '') ;;
      *)
        printf 'hard\tunknown status: %s (expected Draft, Ready, Active, Done, Retired, or Superseded)\n' \
          "$declared_status" >>"$fnd"
        ;;
    esac
  fi

  # v2 pointer line (D-5 via REQ-C1.5): the constant
  # `**Execution:** derived — see the status render` line in every file's
  # header, in its fixed vocabulary. Matched as an exact full line
  # (grep -xF); the non-canonical echo goes through hb_get's non-printable
  # strip plus sanitize_printable (REQ-C1.9).
  if [ "$bundle_ver" = "2" ]; then
    exec_canon='**Execution:** derived — see the status render'
    for bf in requirements.md design.md tasks.md test-spec.md; do
      [ -f "$bdir/$bf" ] || continue
      # Fence-stripped both ways (REQ-C1.2): a fenced copy of the pointer line
      # is an example of the header block, so it must neither satisfy the check
      # nor be reported as a non-canonical one.
      defence "$bdir/$bf" >"$gtmp/exec.scan"
      if grep -qxF "$exec_canon" "$gtmp/exec.scan"; then
        :
      elif grep -q '^\*\*Execution:\*\*' "$gtmp/exec.scan"; then
        hb_load "$bdir/$bf" "$bf"
        pv=$(hb_get Execution "$bf")
        printf 'gap\t%s: non-canonical **Execution:** pointer line: %s (fixed vocabulary: derived — see the status render)\n' \
          "$bf" "$(sanitize_printable "$pv" "(unprintable)")" >>"$fnd"
      else
        printf 'gap\t%s: missing **Execution:** pointer line (format-version 2 header)\n' \
          "$bf" >>"$fnd"
      fi
    done
  fi

  if [ -f "$bdir/design.md" ]; then
    parse_design "$bdir/design.md" >"$gtmp/tagged"
    awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged" >>"$fnd"
    all_d_ids=$(awk -F'\t' '$1 == "ALLD" { print $2 }' "$gtmp/tagged")
  fi

  if [ -f "$bdir/tasks.md" ]; then
    parse_tasks "$bdir/tasks.md" >"$gtmp/tagged"
    awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged" >>"$fnd"
    all_t_ids=$(awk -F'\t' '$1 == "ALLT" { print $2 }' "$gtmp/tagged")

    # v2 invariant-ledger rules (REQ-C1.5): the shared task-structure
    # checks above still apply; these are the additional v2-only bans. A
    # grammar-violating reference-bullet id is untrusted content: it is
    # rejected and echoed only through sanitize_printable (REQ-C1.9).
    if [ "$bundle_ver" = "2" ]; then
      parse_tasks_v2 "$bdir/tasks.md" >"$gtmp/tagged2"
      awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/tagged2" >>"$fnd"
      # The parked map comes from the shared lib (REQ-B1.4). Its exit status is
      # checked (REQ-B1.6f): an unreadable, NUL-bearing, or unbalanced-fence
      # tasks.md must become a fail-closed hard finding, never a validated
      # empty parked map.
      if spec_parse_parked_map "$bdir/tasks.md" >"$gtmp/parked2" 2>"$gtmp/parked2.err"; then
        reference_bullet_findings "$gtmp/tagged2" "$gtmp/parked2" >"$gtmp/refs2"
        awk -F'\t' '$1 == "F" { print $2 "\t" $3 }' "$gtmp/refs2" >>"$fnd"
        while IFS="$tab" read -r rtag rline rid; do
          [ "$rtag" = "RB" ] || continue
          printf 'gap\treference bullet task id at tasks.md:%s fails the task-id grammar and is rejected: %s\n' \
            "$rline" "$(sanitize_printable "$rid" "(empty or unprintable)")" >>"$fnd"
        done <"$gtmp/refs2"
      else
        printf 'hard\ttasks.md: the reference-bullet parse failed, so parked state cannot be validated (fail closed): %s\n' \
          "$(sanitize_printable "$(cat "$gtmp/parked2.err" 2>/dev/null)" "(no diagnostic)")" >>"$fnd"
      fi
    fi
  fi

  # REQ↔test-spec coverage: every live REQ appears in an H3 entry heading,
  # matched as an exact id (REQ-F1.1 is not covered by REQ-F1.10).
  if [ -f "$bdir/test-spec.md" ] && [ -n "$live_req_ids" ]; then
    # Fence-stripped (REQ-C1.2): a fenced entry heading is an example of the
    # test-spec form, and must not be able to satisfy coverage for a REQ that
    # has no real entry — the fail-OPEN half of fence-awareness.
    # Every id on an entry heading, not just the first: one heading may name
    # more than one REQ, and each of those is covered (Task 8; REQ-B1.5).
    heads=$(defence "$bdir/test-spec.md" \
      | awk "$spec_parse_awk_grammar"'
        /^### / {
          n = split(spec_parse_req_tokens($0), t, " ")
          for (i = 1; i <= n; i++) print t[i]
        }
      ') || heads=
    printf '%s\n' "$live_req_ids" | while read -r rid; do
      [ -n "$rid" ] || continue
      set_in "$rid" "$heads" \
        || printf 'gap\t%s has no test-spec entry\n' "$rid" >>"$fnd"
    done
  fi

  baseline_checks "$bdir"

  # Severity mapping (D-25): warnings on Draft and on the frozen terminal
  # records; errors on the signed-off live statuses (Ready, Active, Done —
  # Ready is signed off and executable, kickoff-lifecycle D-1/REQ-B1.2); hard
  # findings always error. An unknown status already carries its own hard
  # finding.
  case $declared_status in
    Ready | Active | Done) gapsev=ERROR ;;
    *) gapsev=WARN ;;
  esac
  while IFS="$tab" read -r class msg; do
    [ -n "$class" ] || continue
    if [ "$class" = "hard" ]; then
      sev=ERROR
    else
      sev=$gapsev
    fi
    printf 'spec-validate: %s %s: %s\n' "$sev" "$bname" "$msg"
    if [ "$sev" = "ERROR" ]; then
      err=$((err + 1))
    else
      warn=$((warn + 1))
    fi
  done <"$fnd"
}

# screen_and_validate <dir> — name-screen a direct child of the specs root
# and validate it as a bundle when the screen passes.
screen_and_validate() {
  sdir=$1
  snm=$(basename "$sdir")
  case $snm in
    _*)
      # Reserved non-spec accumulator: never validated as a bundle, but the
      # name is still screened (REQ-A1.8).
      check_accumulator_name "$snm" \
        || emit_error "$snm" "accumulator directory name fails ^_[a-z0-9][a-z0-9-]*\$ (max 64)"
      ;;
    *)
      if check_spec_id "$snm"; then
        validate_bundle "$sdir" "$snm"
      else
        emit_error "$snm" "spec identifier fails ^[a-z0-9][a-z0-9-]*\$ (max 64); not validated as a bundle"
      fi
      ;;
  esac
}

if [ -f "$target/requirements.md" ] || [ -f "$target/design.md" ] \
  || [ -f "$target/tasks.md" ] || [ -f "$target/test-spec.md" ]; then
  screen_and_validate "$target"
else
  # Glob iteration, not `find | split`: pathname-expansion results arrive
  # one entry per word, so names containing newlines (or any other
  # splittable byte) cannot fragment into charset-valid phantom entries,
  # and expansion results are never re-expanded, so glob-metacharacter
  # names (e.g. "[g]") are screened literally. Hidden entries are skipped
  # as tooling artifacts (the root's own dotfiles set the precedent).
  # Symlinked directories are a hard error, not a silent skip: an accepted
  # symlink would be a bundle CI never checks (fail closed, REQ-A2.1);
  # symlinks to non-directories stay ignored like any other plain file.
  for d in "$target"/*; do
    { [ -e "$d" ] || [ -L "$d" ]; } || continue # unmatched-glob literal
    if [ -L "$d" ]; then
      if [ -d "$d" ]; then
        emit_error "$(basename "$d")" \
          "symlinked directory under the specs root; bundles must be real directories"
      fi
      continue
    fi
    [ -d "$d" ] || continue
    screen_and_validate "$d"
  done
fi

printf 'spec-validate: %d error(s), %d warning(s)\n' "$err" "$warn"
[ "$err" -eq 0 ]
