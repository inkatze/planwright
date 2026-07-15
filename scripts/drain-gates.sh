#!/bin/sh
# drain-gates.sh — the shared gate parser/evaluator behind /drain and
# /orchestrate --bookkeeping (Task 10, REQ-H1.3, REQ-H1.4, D-17, D-31).
#
# Sweeps every spec bundle's tasks.md under the given specs root for
# `**Gate:**` entries, parses structured `GATE(when: ...)` conditions
# against the closed declarative grammar defined in
# doctrine/accumulator-taxonomy.md (the normative home for the productions),
# evaluates them, and prints a drain report. The sweep is read-only: it
# never resolves, drops, or rewrites a gate (REQ-H1.4) — re-surfacing means
# reporting; acting on the report is the caller's (human's) move.
#
# Lanes (normative detail in the doctrine doc):
#   SATISFIED  condition gate (task/status atoms only), every atom true
#   PENDING    condition gate with at least one unmet or unresolved atom (an
#              UNRESOLVED atom — v2 completion evidence unavailable, see below
#              — blocks satisfaction and is named in the row's own
#              `unresolved (completion evidence unavailable):` clause; DORMANT
#              rows carry the same clause when a date gate holds one)
#   SURFACED   date gate (contains a date atom), every atom true/reached
#   DORMANT    date gate with any atom not yet true/reached — date gates
#              only surface, never satisfy and never hard-fail
#   FREE-TEXT  gate text not in GATE(when: ...) form — surfaced verbatim,
#              never evaluated
#   MALFORMED  structured gate failing the grammar, or a gate line outside
#              any deferral bullet — a drain-report-level error: reported,
#              never evaluated, never silently skipped; the pass completes
#
# Fenced code blocks (column-0 ``` fences) are illustration: their content
# defines no task ids and produces no gate rows.
#
# Task-completion atoms are version-keyed (invariant-tasks Task 5; D-8,
# REQ-C1.3, REQ-C1.8): a bundle's `Format-version:` line (read from tasks.md,
# the file whose shape the version keys) selects the completion source. v1
# resolves `task <id> completed` from `## Completed` section membership as
# before. v2 has no placement sections: completion resolves through the
# derivation engine (scripts/orchestrate-state.sh — git + trailer + gh
# evidence), with reference-bullet authority applied (REQ-B1.4, D-3): a task
# named by a live `- **Task <id>**` bullet in a human-payload section never
# resolves completed, whatever its git evidence says; bullet task ids are
# grammar-validated before use and a violating id is rejected with a note
# (REQ-C1.9). A missing or unparseable `Format-version:` fails closed as a
# per-spec report error — the spec's gates are not evaluated under guessed
# rules (REQ-C1.8). On a transient evidence failure (the engine's `degraded`
# record: remote configured but the fetch failed) or an engine failure, v2
# task atoms resolve as UNRESOLVED (REQ-B1.5): never satisfied from partial
# evidence, surfaced and counted as a report error, the sweep still completes.
#
# Confidence (REQ-H1.5): a bullet's `Confidence: <low|medium|high>` field
# (matched as a whole token in the entry text before the gate marker)
# orders the report within each lane of each spec's section, low first, so
# low-confidence deferrals resurface first.
#
# Also surfaces the observations log's unmined count and oldest-entry age
# (REQ-H1.4, surface only; age clamps at zero for future-dated entries).
#
# Usage: drain-gates.sh [--today YYYY-MM-DD] <specs-root>
#   --today pins the evaluation date (tests); defaults to the system date.
#
# Exit codes: 0 sweep completed (malformed gates and unreadable, NUL-laden,
# or mid-sweep-changed swept files are report content, not failures),
# 1 unusable specs root (missing, unreadable, or non-searchable), 2 usage
# error or a broken install (the script's own directory unresolvable, so the
# sibling derivation engine cannot be located); any other status means the
# sweep aborted mid-run (internal failure) without emitting a report.
#
# Security (REQ-H1.3): gate content is data only. The parse is pattern
# match; nothing is passed to eval, a subshell, or arithmetic expansion;
# gate text is never used as a pattern, format string, or unquoted
# argument; control characters (C0 minus newline, DEL, and the C1 range
# 0x80-0x9F) are stripped from the echoed report; status values read from
# requirements.md are whitelisted before crossing into awk.
# Portable: POSIX sh + awk (bash 3.2 / BSD compatible, mawk-safe — no
# regex interval expressions).
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8
# locales (house pattern, see sibling scripts).
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo its destination into the script-dir command
# substitution below, corrupting the derived engine path (house pattern, see
# sibling scripts).
unset CDPATH

TAB=$(printf '\t')

# Resolve this script's directory so the sibling derivation engine
# (orchestrate-state.sh, the v2 completion source) is found regardless of the
# caller's working directory.
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
state_engine="$script_dir/orchestrate-state.sh"

usage() {
  echo "usage: drain-gates.sh [--today YYYY-MM-DD] <specs-root>" >&2
  exit 2
}

# --- observation-fragment helpers (mirrors obs-record.sh / check-obs.sh) --
# The observations surfacing (the `== observations ==` section below) derives
# the unmined count and oldest-entry age from the fragment store (entries/ glob)
# plus the frozen legacy file's unconsumed lines (REQ-C1.3, D-4). These helpers
# validate a fragment name and name-embedded date the same way the recording
# helper and the CI guard do, so drain, render, record, and the guard agree on
# what a valid fragment is.

# obs_safe <string> — strip C0 control bytes, DEL, and the C1 range (newline
# included) so an untrusted fragment name embedded in a finding cannot forge a
# report row or smuggle a terminal escape (echo discipline, D-7). The final
# report strip keeps newlines for structure, so a name is scrubbed of them here.
obs_safe() {
  printf '%s' "$1" | tr -d '\000-\037\177\200-\237'
}

# strip0 <digits> — drop leading zeros so arithmetic never reads 08/09 as octal.
strip0() {
  _n=$1
  while [ "$_n" != "${_n#0}" ] && [ "${#_n}" -gt 1 ]; do
    _n=${_n#0}
  done
  printf '%s' "$_n"
}

# valid_calendar_date <YYYY-MM-DD> — 0 if the shape-checked date is real
# (month 1-12, day within the month, leap Feb), else 1.
valid_calendar_date() {
  _y=$(strip0 "${1%%-*}")
  _rest=${1#*-}
  _mo=$(strip0 "${_rest%%-*}")
  _da=$(strip0 "${_rest#*-}")
  [ "$_mo" -ge 1 ] && [ "$_mo" -le 12 ] || return 1
  case "$_mo" in
    1 | 3 | 5 | 7 | 8 | 10 | 12) _max=31 ;;
    4 | 6 | 9 | 11) _max=30 ;;
    2)
      if { [ $((_y % 4)) -eq 0 ] && [ $((_y % 100)) -ne 0 ]; } \
        || [ $((_y % 400)) -eq 0 ]; then
        _max=29
      else
        _max=28
      fi
      ;;
    *) return 1 ;;
  esac
  [ "$_da" -ge 1 ] && [ "$_da" -le "$_max" ]
}

# valid_name <basename> — 0 if the filename matches `<date>-<slug>-<uid>.md`
# with a real calendar date, a kebab-case slug of 1..40 chars, and an
# 8-lowercase-hex UID, else 1. Pure string parsing; the `_v`-prefixed locals
# keep a private namespace from valid_calendar_date's globals (POSIX sh has no
# function-local scope). Mirror of check-obs.sh.
valid_name() {
  _vb=$1
  case "$_vb" in
    *.md) : ;;
    *) return 1 ;;
  esac
  _vstem=${_vb%.md}
  case "$_vstem" in
    *-*) : ;;
    *) return 1 ;;
  esac
  _vuid=${_vstem##*-}
  case "$_vuid" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
    *) return 1 ;;
  esac
  _vrest=${_vstem%-*}
  case "$_vrest" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-?*) : ;;
    *) return 1 ;;
  esac
  _vslug=${_vrest#??????????-}
  _vdate=${_vrest%"-$_vslug"}
  [ -n "$_vslug" ] || return 1
  [ "${#_vslug}" -le 40 ] || return 1
  case "$_vslug" in
    -* | *-) return 1 ;;
    *--*) return 1 ;;
    *[!a-z0-9-]*) return 1 ;;
  esac
  valid_calendar_date "$_vdate" || return 1
  return 0
}

today=""
if [ $# -ge 1 ] && [ "$1" = "--today" ]; then
  [ $# -ge 2 ] || usage
  today=$2
  shift 2
fi
[ $# -eq 1 ] || usage
root=$1

if [ -z "$today" ]; then
  today=$(date +%Y-%m-%d)
fi
# Calendar-validate --today with the same leap-aware rule gate date atoms
# get, so the comparison anchor can never be a date that does not exist.
case $today in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    ok=$(awk -v d="$today" 'BEGIN {
      y = substr(d, 1, 4) + 0
      m = substr(d, 6, 2) + 0
      dd = substr(d, 9, 2) + 0
      dim = 31
      if (m == 4 || m == 6 || m == 9 || m == 11) dim = 30
      if (m == 2)
        dim = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28
      print (m >= 1 && m <= 12 && dd >= 1 && dd <= dim) ? 1 : 0
    }')
    if [ "$ok" != 1 ]; then
      echo "drain-gates: invalid --today date: $today" >&2
      exit 2
    fi
    ;;
  *)
    echo "drain-gates: invalid --today date: $today" >&2
    exit 2
    ;;
esac

case $root in
  ?*/) root=${root%/} ;;
esac
if [ ! -d "$root" ] || [ ! -r "$root" ] || [ ! -x "$root" ]; then
  echo "drain-gates: specs root missing, unreadable, or non-searchable: $1" >&2
  exit 1
fi

# Enumerate spec bundles: directories whose name passes the REQ-A1.8
# identifier discipline. Underscore-prefixed accumulators are not bundles
# and are never swept for gates; other non-conforming names are noted so
# the skip is visible, never silent.
specs=""
notes=""
for dir in "$root"/*/; do
  [ -d "$dir" ] || continue
  name=${dir%/}
  name=${name##*/}
  case $name in
    _*) continue ;;
    *[!a-z0-9-]* | -* | "")
      notes="${notes}note: skipped directory with non-conforming spec identifier
"
      continue
      ;;
  esac
  if [ ${#name} -gt 64 ]; then
    notes="${notes}note: skipped directory with over-length spec identifier
"
    continue
  fi
  specs="$specs $name"
done

# Spec status map for status atoms: "name=status" pairs, lowercased. An
# unreadable requirements.md is noted: its status atoms will not evaluate.
# Status values are whitelisted against the five lifecycle statuses BEFORE
# they reach awk -v: -v performs C-escape processing, so an unvalidated
# value containing a literal backslash escape could smuggle whitespace into
# the map and forge another spec's status (REQ-H1.3 data-only discipline).
statuses=""
for name in $specs; do
  req="$root/$name/requirements.md"
  if [ ! -f "$req" ]; then
    notes="${notes}note: spec $name: requirements.md missing; status atoms referencing it will not evaluate
"
  elif [ ! -r "$req" ]; then
    notes="${notes}note: spec $name: requirements.md unreadable; status atoms referencing it will not evaluate
"
  else
    st=$(awk '/^\*\*Status:\*\*/ { print tolower($2); exit }' "$req") || st=""
    case $st in
      draft | active | done | retired | superseded)
        statuses="$statuses $name=$st"
        ;;
      "") ;;
      *)
        notes="${notes}note: spec $name: unrecognized status; status atoms referencing it will not evaluate
"
        ;;
    esac
  fi
done

# --- the sweep, emitted to stdout and control-stripped at the end ---------

report() {
  printf 'drain report - root: %s - today: %s\n' "$root" "$today"
  [ -n "$notes" ] && printf '%s' "$notes"

  total=0
  n_sat=0
  n_sur=0
  n_pen=0
  n_dor=0
  n_free=0
  n_mal=0
  n_err=0

  for name in $specs; do
    tasks="$root/$name/tasks.md"
    printf '\n== spec: %s ==\n' "$name"
    if [ ! -f "$tasks" ]; then
      printf '(no tasks.md)\n'
      continue
    fi
    if [ ! -r "$tasks" ]; then
      printf 'error: tasks.md unreadable - its gates are unknown\n'
      n_err=$((n_err + 1))
      continue
    fi

    # awk truncates records at NUL, which could silently hide a gate
    # marker (never-silently-skipped, REQ-H1.3); flag the file instead of
    # trusting a truncated parse.
    if [ "$(wc -c <"$tasks")" -ne "$(tr -d '\000' <"$tasks" | wc -c)" ]; then
      printf 'error: tasks.md contains NUL bytes - gates may be hidden; treat as malformed\n'
      n_err=$((n_err + 1))
      continue
    fi

    # Digest bracket, opened HERE (before every read that feeds gate
    # evaluation): the Format-version line, the v2 parked map and task/gate
    # counts, the engine's own read of the file, and the main gate parse all
    # read within the pre/post pair, so a concurrent rewrite landing between
    # ANY of them and the gate parse is flagged as torn instead of silently
    # mixing two file versions (e.g. a v1 map against v2 bytes, or a stale
    # parked map against fresh evidence). A rewrite restoring identical bytes
    # within the window is below the check's resolution. The NUL screen above
    # stays a separate, cheaper open; it feeds no evaluation.
    if ! pre_digest=$(cksum <"$tasks" 2>/dev/null); then
      printf 'error: tasks.md vanished during the sweep\n'
      n_err=$((n_err + 1))
      continue
    fi

    # Format-version (REQ-C1.8): task-completion atoms are version-keyed
    # (v1 section membership vs v2 derivation, see the header), so the version
    # must parse before the spec's gates are evaluated. Missing or unparseable
    # fails closed as a per-spec report error — never a guess, never a silent
    # skip; the sweep completes. Trailing trim: a Markdown hard-break or CRLF
    # checkout must not make a valid value unrecognizable. Column-0 fences are
    # illustration: a fenced example header line must not shadow the real
    # declaration (the trim mirrors spec-status.sh; its fence-awareness
    # alignment is tracked as an observation). A read failure is reported as
    # its own error, not misattributed to the format.
    if ! fv=$(awk '
      /^```/ { fence = !fence; next }
      fence { next }
      /^\*\*Format-version:\*\*/ { sub(/^\*\*Format-version:\*\*[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }
    ' "$tasks" 2>/dev/null); then
      printf 'error: tasks.md became unreadable during the sweep\n'
      n_err=$((n_err + 1))
      continue
    fi
    case "$fv" in
      1 | 2) ;;
      *)
        printf 'error: tasks.md has a missing or unparseable Format-version: line - gates not evaluated (fail closed)\n'
        n_err=$((n_err + 1))
        continue
        ;;
    esac

    # v2 completion evidence (REQ-C1.3, REQ-B1.4, REQ-B1.5): the completed set
    # comes from the derivation engine, minus every bullet-parked task (a live
    # reference bullet outranks git evidence). On an engine failure or a
    # transient evidence failure (`degraded`), task atoms resolve as unresolved
    # instead of evaluating against partial evidence.
    v2comp=" "
    v2evfail=0
    if [ "$fv" = 2 ]; then
      # One pre-parse pass: the parked map (live reference bullets under the
      # three human-payload sections), the unfenced task count, and whether any
      # unfenced gate marker exists. Column-0 fences are illustration here as
      # in the gate parse. Bullet task ids are grammar-validated; a violating
      # id is rejected with a note and never used (REQ-C1.9; the final report
      # strip sanitizes it), while a lead with inner whitespace is a plain
      # prose bullet the format allows in Deferred / Out of scope — silently
      # skipped, matching the validator's rule. A sibling of the
      # spec-status.sh (Task 3) parked-map parse; its fence/prose alignment is
      # tracked as an observation. A failed pre-parse fails CLOSED (the parked
      # map is the input that vetoes evidence; an empty default would silently
      # un-park tasks).
      if ! v2pre=$(awk '
        function classof(sec) {
          if (sec == "Awaiting input") return "awaiting-input"
          if (sec == "Deferred") return "deferred"
          if (sec == "Out of scope") return "out-of-scope"
          return ""
        }
        { sub(/\r$/, "") }
        /^```/ { fence = !fence; next }
        fence { next }
        /^## / { sec = substr($0, 4); sub(/[ \t]+$/, "", sec); next }
        /^### Task / { if ($3 ~ /^[0-9]+(\.[0-9]+)?$/) ntasks++ }
        index($0, "**Gate:**") > 0 { hasgate = 1 }
        /^- \*\*Task / && classof(sec) != "" {
          line = $0
          sub(/^- \*\*Task /, "", line)
          i = index(line, "**")
          if (i == 0) next # no closing bold: not a reference bullet
          id = substr(line, 1, i - 1)
          if (id ~ /[ \t]/) {
            # Inner whitespace is usually a plain prose bullet (validator
            # parity) — but a NEAR-MISS reference (whitespace-trimmed
            # remainder is a valid id, or only digits/dots/whitespace) is a
            # failed park a human meant, rejected loudly below.
            probe = id
            sub(/^[ \t]+/, "", probe)
            sub(/[ \t]+$/, "", probe)
            if (probe !~ /^[0-9]+(\.[0-9]+)?$/ && id !~ /^[0-9. \t]+$/) next
          }
          if (id !~ /^[0-9]+(\.[0-9]+)?$/) {
            gsub(/\t/, " ", id) # tabs would corrupt the record split
            print "rejected\t" id
            next
          }
          if (id in seen) next
          seen[id] = 1
          print "parked\t" id
          next
        }
        END { print "meta\t" ntasks + 0 "\t" hasgate + 0 }
      ' "$tasks" 2>/dev/null); then
        printf 'error: could not read the v2 parked map - gates not evaluated (fail closed)\n'
        n_err=$((n_err + 1))
        continue
      fi
      # Pre-parse record shapes: `rejected<TAB><raw-id>`, `parked<TAB><id>`,
      # and exactly one `meta<TAB><ntasks><TAB><hasgate>` (from END).
      v2parked=" "
      v2ntasks=0
      v2hasgate=0
      while IFS="$TAB" read -r pm_tag pm_a pm_b; do
        [ -n "$pm_tag" ] || continue
        case "$pm_tag" in
          rejected)
            printf 'note: reference bullet rejected - task id %s violates the task-id grammar\n' "'$pm_a'"
            ;;
          parked)
            v2parked="$v2parked$pm_a "
            ;;
          meta)
            v2ntasks=$pm_a
            v2hasgate=$pm_b
            ;;
        esac
      done <<EOF
$v2pre
EOF
      # The engine is consulted only when its output can be consumed: a bundle
      # with no unfenced task blocks has nothing to derive (every task atom is
      # already an unknown-id MALFORMED), and a bundle with no unfenced gate
      # marker has no atoms to resolve — either way a needless derivation
      # (git subprocesses, potentially a gh network call) would only inflate
      # the error tally on unrelated failures.
      if [ "$v2ntasks" -gt 0 ] && [ "$v2hasgate" -eq 1 ]; then
        if [ ! -x "$state_engine" ]; then
          printf 'error: derivation engine unavailable - task-completion atoms resolve as unresolved (fail closed)\n'
          n_err=$((n_err + 1))
          v2evfail=1
        else
          eng_rc=0
          eng_out=$("$state_engine" "$root/$name" 2>/dev/null) || eng_rc=$?
          if [ "$eng_rc" -ne 0 ]; then
            printf 'error: derivation failed - task-completion atoms resolve as unresolved (fail closed)\n'
            n_err=$((n_err + 1))
            v2evfail=1
          elif printf '%s\n' "$eng_out" \
            | awk -F"$TAB" '$1 == "degraded" { f = 1 } END { exit !f }'; then
            # Detected by tag (the engine's documented consumption model),
            # never by message text (REQ-B1.5).
            printf 'error: transient evidence failure - task-completion atoms resolve as unresolved (REQ-B1.5)\n'
            n_err=$((n_err + 1))
            v2evfail=1
          else
            for cid in $(printf '%s\n' "$eng_out" \
              | awk -F"$TAB" '$1 == "task" && $3 == "completed" { print $2 }'); do
              case "$v2parked" in
                *" $cid "*) ;; # bullet authority: parked outranks evidence
                *) v2comp="$v2comp$cid " ;;
              esac
            done
          fi
        fi
      fi
    fi

    # Single parse pass: the awk program reads the file once, buffering
    # it and collecting the task-id universe (ids defined anywhere
    # outside fenced code blocks; the v1 Completed subset) while reading,
    # then evaluates gates over the buffered lines in END. Two separate
    # parse reads could see different versions of a file being rewritten
    # concurrently and fabricate MALFORMED rows for valid gates; one
    # parse open confines any race to a torn single read. Every read that
    # feeds gate evaluation — this parse plus the fv / parked-map / engine
    # pre-reads above — sits inside the digest bracket opened before the fv
    # read, so a rewrite anywhere in that window is flagged as torn. Each
    # read is guarded so a file vanishing mid-sweep degrades to a
    # report-level error for this spec instead of aborting the whole report.
    if ! lines=$(awk -v fname="$tasks" -v today="$today" -v statuses="$statuses" \
      -v fv="$fv" -v comp="$v2comp" -v evfail="$v2evfail" '
      BEGIN {
        n = split(statuses, a, " ")
        for (i = 1; i <= n; i++) {
          eq = index(a[i], "=")
          if (eq > 1) STATUS[substr(a[i], 1, eq - 1)] = substr(a[i], eq + 1)
        }
        VALID["draft"] = VALID["active"] = VALID["done"] = 1
        VALID["retired"] = VALID["superseded"] = 1
        CAT["MALFORMED"] = 0; CAT["SATISFIED"] = 1; CAT["SURFACED"] = 2
        CAT["PENDING"] = 3; CAT["DORMANT"] = 4; CAT["FREE-TEXT"] = 5
        CONFR["low"] = 0; CONFR["medium"] = 1; CONFR["high"] = 2; CONFR["-"] = 3
        buf = ""; inb = 0; rdfence = 0
      }

      # Read phase: strip a trailing CR so CRLF files parse like LF ones
      # (interior CRs stay data and are control-stripped at output), then
      # buffer the line. Column-0 code fences toggle illustration mode:
      # fenced lines never define task ids.
      { sub(/\r$/, ""); L[NR] = $0 }
      /^```/ { rdfence = !rdfence }
      /^## / { if (!rdfence) sec = $0 }
      /^### Task / {
        if (!rdfence) {
          ALL[$3] = 1
          if (sec ~ /^## Completed/) COMP[$3] = 1
        }
      }
      END {
        for (i = 1; i <= NR; i++) scan(L[i], i)
        flush_bullet()
        emit()
      }

      function trim(s) {
        sub(/^[ \t]+/, "", s)
        sub(/[ \t]+$/, "", s)
        return s
      }

      # Buffer one top-level bullet (with its indented continuations) and
      # process it as a unit; gate text may wrap lines. Blank lines never
      # end a bullet (loose markdown list items stay whole); a gate line
      # outside any bullet is malformed, never dropped. Column-0 fences
      # open/close illustration blocks: fenced content is never parsed as
      # gates (an example gate is not a deferral), and a fence ends any
      # open bullet.
      function scan(line, nr) {
        if (line ~ /^```/) {
          flush_bullet()
          FENCE = !FENCE
          return
        }
        if (FENCE) return
        if (line ~ /^- /) {
          flush_bullet()
          buf = line
          bline = nr
          inb = 1
          return
        }
        if (line ~ /^[ \t]*$/) return
        if (line ~ /^[ \t]/) {
          if (inb) { buf = buf " " line; return }
          orphan(line, nr)
          return
        }
        flush_bullet()
        orphan(line, nr)
      }

      function orphan(line, nr,  g, k) {
        if (index(line, "**Gate:**") == 0) return
        bline = nr
        g = substr(line, index(line, "**Gate:**") + 9)
        k = index(g, " Citations:")
        if (k) g = substr(g, 1, k - 1)
        add("MALFORMED", "-", "(untitled)", \
          "gate outside a deferral bullet - gate: " trim(g))
      }

      function flush_bullet(  text, title, conf, g, k) {
        if (!inb) return
        inb = 0
        text = buf
        buf = ""
        gsub(/[ \t]+/, " ", text)
        if (index(text, "**Gate:**") == 0) return

        title = bullet_title(text)
        conf = bullet_conf(substr(text, 1, index(text, "**Gate:**") - 1))

        g = substr(text, index(text, "**Gate:**") + 9)
        k = index(g, " Citations:")
        if (k) g = substr(g, 1, k - 1)
        g = trim(g)

        if (substr(g, 1, 10) == "GATE(when:")
          structured(g, title, conf)
        else
          add("FREE-TEXT", conf, title, "gate: " g)
      }

      function bullet_title(text,  i, rest, j) {
        i = index(text, "**")
        if (!i || i == index(text, "**Gate:**")) return "(untitled)"
        rest = substr(text, i + 2)
        j = index(rest, "**")
        if (!j) return "(untitled)"
        rest = substr(rest, 1, j - 1)
        sub(/\.$/, "", rest)
        return rest
      }

      # The Confidence field is matched as a whole token in the entry text
      # before the gate marker, so gate-text mentions and longer words
      # ("Confidence: lowest") never count.
      function bullet_conf(pre) {
        if (pre ~ /Confidence: low($|[^a-z])/) return "low"
        if (pre ~ /Confidence: medium($|[^a-z])/) return "medium"
        if (pre ~ /Confidence: high($|[^a-z])/) return "high"
        return "-"
      }

      # Closed-grammar parse of a structured gate: pattern match only, the
      # condition is never executed or expanded (REQ-H1.3). The grammar
      # ends at the closing parenthesis; anything but a final period after
      # it is malformed.
      function structured(g, title, conf,  cond, p, rest, n, atoms, i, \
        atom, verdict, hasdate, allmet, unmet, unres, det, why) {
        cond = trim(substr(g, 11))
        p = index(cond, ")")
        if (!p) {
          add("MALFORMED", conf, title, "unterminated GATE(when: ...) - gate: " g)
          return
        }
        rest = trim(substr(cond, p + 1))
        if (rest != "" && rest != ".") {
          add("MALFORMED", conf, title, \
            "trailing content after the closing parenthesis - gate: " g)
          return
        }
        cond = trim(substr(cond, 1, p - 1))
        if (cond == "") {
          add("MALFORMED", conf, title, "empty condition - gate: " g)
          return
        }
        n = split(cond, atoms, / and /)
        hasdate = 0
        allmet = 1
        unmet = ""
        why = ""
        for (i = 1; i <= n; i++) {
          atom = trim(atoms[i])
          verdict = eval_atom(atom)
          if (verdict ~ /^bad/) {
            why = why (why == "" ? "" : "; ") atom_error(verdict, atom)
            continue
          }
          # A v2 task atom whose completion evidence is unavailable (engine
          # failure or transient remote failure, REQ-B1.5): unresolved — it
          # blocks satisfaction (never satisfied from partial evidence) and is
          # accumulated separately so every affected row, PENDING or DORMANT,
          # names it distinctly from a genuinely unmet atom.
          if (verdict == "unresolved") {
            allmet = 0
            unres = unres (unres == "" ? "" : "; ") atom
            continue
          }
          if (verdict == "date-met" || verdict == "date-unmet") hasdate = 1
          if (verdict ~ /unmet$/) {
            allmet = 0
            unmet = unmet (unmet == "" ? "" : "; ") atom
          }
        }
        if (why != "") {
          add("MALFORMED", conf, title, why " - gate: " g)
        } else if (hasdate) {
          if (allmet)
            add("SURFACED", conf, title, "(date reached) when: " cond)
          else {
            det = "when: " cond
            if (unres != "")
              det = det " - unresolved (completion evidence unavailable): " unres
            add("DORMANT", conf, title, det)
          }
        } else {
          if (allmet)
            add("SATISFIED", conf, title, "when: " cond)
          else {
            det = "when: " cond
            if (unmet != "") det = det " - unmet: " unmet
            if (unres != "")
              det = det " - unresolved (completion evidence unavailable): " unres
            add("PENDING", conf, title, det)
          }
        }
      }

      # One atom -> met / unmet / unresolved / date-met / date-unmet / bad-*.
      function eval_atom(atom,  nt, tk) {
        if (atom == "") return "bad-atom"
        nt = split(atom, tk, " ")
        if (nt == 3 && tk[1] == "task" && tk[3] == "completed" \
          && tk[2] ~ /^[0-9]+(\.[0-9]+)?$/) {
          if (!(tk[2] in ALL)) return "bad-task"
          # Version-keyed completion source (REQ-C1.3): v1 reads `## Completed`
          # membership; v2 reads the derivation-engine completed set (bullet
          # authority already applied), unresolved when evidence is unavailable.
          if (fv == 2) {
            if (evfail) return "unresolved"
            return (index(comp, " " tk[2] " ") > 0) ? "met" : "unmet"
          }
          return (tk[2] in COMP) ? "met" : "unmet"
        }
        if (nt == 3 && tk[1] == "spec" && (tk[3] in VALID) \
          && tk[2] ~ /^[a-z0-9][a-z0-9-]*$/ && length(tk[2]) <= 64) {
          if (!(tk[2] in STATUS)) return "bad-spec"
          return (STATUS[tk[2]] == tk[3]) ? "met" : "unmet"
        }
        if (nt == 2 && tk[1] == "after" \
          && tk[2] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
          if (!valid_date(tk[2])) return "bad-date"
          # A date is reached on or after the named day (inclusive).
          return (tk[2] <= today) ? "date-met" : "date-unmet"
        }
        return "bad-atom"
      }

      # Calendar validity: real month, real day-of-month, leap-aware.
      function valid_date(d,  y, m, dd, dim) {
        y = substr(d, 1, 4) + 0
        m = substr(d, 6, 2) + 0
        dd = substr(d, 9, 2) + 0
        if (m < 1 || m > 12 || dd < 1) return 0
        dim = 31
        if (m == 4 || m == 6 || m == 9 || m == 11) dim = 30
        if (m == 2)
          dim = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28
        return dd <= dim
      }

      function atom_error(verdict, atom) {
        if (verdict == "bad-task") return "unknown task in atom: " atom
        if (verdict == "bad-spec") return "unknown spec in atom: " atom
        if (verdict == "bad-date") return "invalid date in atom: " atom
        return "unrecognized atom: " atom
      }

      function add(cat, conf, title, detail,  key) {
        key = CAT[cat] "," CONFR[conf]
        CNT[key]++
        ROW[key, CNT[key]] = cat " [" conf "] " fname ":" bline " - " title " - " detail
      }

      function emit(  c, k, s, key) {
        for (c = 0; c <= 5; c++)
          for (k = 0; k <= 3; k++) {
            key = c "," k
            for (s = 1; s <= CNT[key]; s++) print ROW[key, s]
          }
      }
    ' "$tasks" 2>/dev/null); then
      printf 'error: tasks.md vanished during the sweep\n'
      n_err=$((n_err + 1))
      continue
    fi

    post_digest=$(cksum <"$tasks" 2>/dev/null) || post_digest="(vanished)"
    if [ "$pre_digest" != "$post_digest" ]; then
      printf 'error: tasks.md changed during the sweep - rows below may be torn; re-run\n'
      n_err=$((n_err + 1))
    fi

    if [ -n "$lines" ]; then
      printf '%s\n' "$lines"
      total=$((total + $(printf '%s\n' "$lines" | grep -c .)))
      n_sat=$((n_sat + $(printf '%s\n' "$lines" | grep -c '^SATISFIED' || true)))
      n_sur=$((n_sur + $(printf '%s\n' "$lines" | grep -c '^SURFACED' || true)))
      n_pen=$((n_pen + $(printf '%s\n' "$lines" | grep -c '^PENDING' || true)))
      n_dor=$((n_dor + $(printf '%s\n' "$lines" | grep -c '^DORMANT' || true)))
      n_free=$((n_free + $(printf '%s\n' "$lines" | grep -c '^FREE-TEXT' || true)))
      n_mal=$((n_mal + $(printf '%s\n' "$lines" | grep -c '^MALFORMED' || true)))
    else
      printf '(no gates)\n'
    fi
  done

  printf '\n== observations ==\n'
  # The unmined observation count and oldest-entry age are derived from the
  # fragment store (entries/ glob) plus the frozen legacy file's unconsumed
  # lines, naming both surfaces while the legacy file still holds entries
  # (REQ-C1.3, D-4). Nothing here is a committed compiled view (REQ-B1.3): this
  # is the same derived read scripts/obs-render.sh performs for the human view.
  obsroot="$root/_observations"
  entries="$obsroot/entries"
  legacy="$obsroot/opportunities.md"

  # A symlinked observations root would resolve the whole store outside the
  # tree; do not traverse through it (D-7, the root-level guard obs-record.sh
  # and check-obs.sh hold). The per-dir/per-file symlink checks below cover
  # entries/ and the legacy file, but not the root itself. Surfaced as a note,
  # not a hard error, so one odd directory never aborts the sweep.
  obsroot_ok=1
  if [ -L "$obsroot" ]; then
    printf 'note: observations root is a symlink; not traversed (D-7)\n'
    obsroot_ok=0
  fi

  # Live fragments: entries/*.md that pass the filename grammar and open with
  # the entry form and carry no `Consumed-by:` line. A grammar- or shape-invalid
  # file is excluded from the count and named (skip-and-warn, D-4); a
  # consumed-but-unmoved fragment is excluded and surfaced as a stuck consume
  # (REQ-C1.2). Fragment names/content are data only (D-7). Null-safe over an
  # absent or symlinked entries/ directory.
  frag_live=0
  frag_dates=""
  stuck=""
  invalid=""
  unreadable=""
  # A symlinked entries/ is surfaced as a note and not traversed (D-7), the
  # same posture obs-render.sh holds on a symlinked fragment directory and drain
  # holds on a symlinked root; otherwise a misconfigured store hides behind
  # unmined: 0 with no signal.
  if [ "$obsroot_ok" -eq 1 ] && [ -L "$entries" ]; then
    printf 'note: observations entries/ is a symlink; not traversed (D-7)\n'
  fi
  if [ "$obsroot_ok" -eq 1 ] && [ -d "$entries" ] && [ ! -L "$entries" ]; then
    for _f in "$entries"/*.md; do
      # `-e` is false for the literal unmatched glob and for a dangling symlink;
      # `|| -L` keeps a broken symlink in play so it is named as invalid below
      # rather than silently skipped, matching check-obs.sh and obs-render.sh
      # (D-7).
      [ -e "$_f" ] || [ -L "$_f" ] || continue
      _name=${_f##*/}
      if [ -L "$_f" ] || [ ! -f "$_f" ]; then
        invalid="$invalid$(obs_safe "$_name")
"
        continue
      fi
      if ! valid_name "$_name"; then
        invalid="$invalid$(obs_safe "$_name")
"
        continue
      fi
      # An unreadable fragment is named and excluded, never read. Without this
      # guard the `done <"$_f"` open below fails, and under a strict-POSIX
      # /bin/sh (dash, the CI shell) that redirect failure aborts the whole
      # sweep under set -e - no report emitted at all. Mirrors the legacy-file
      # -r guard below and scripts/obs-render.sh.
      if [ ! -r "$_f" ]; then
        unreadable="$unreadable$(obs_safe "$_name")
"
        continue
      fi
      # One pure-shell pass over the (tiny) fragment: first content line and
      # whether any `Consumed-by:` metadata line is present. No subprocess per
      # fragment, so the O(N) sweep stays cheap at scale.
      _first=""
      _gotfirst=0
      _consumed=0
      while IFS= read -r _ln || [ -n "$_ln" ]; do
        if [ "$_gotfirst" -eq 0 ]; then
          _first=$_ln
          _gotfirst=1
        fi
        case "$_ln" in
          Consumed-by:*) _consumed=1 ;;
        esac
      done <"$_f"
      case "$_first" in
        "- "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" ["*"] "*) : ;;
        *)
          invalid="$invalid$(obs_safe "$_name")
"
          continue
          ;;
      esac
      if [ "$_consumed" -eq 1 ]; then
        stuck="$stuck$(obs_safe "$_name")
"
        continue
      fi
      frag_live=$((frag_live + 1))
      _ftail=${_name#??????????}
      _fdate=${_name%"$_ftail"}
      frag_dates="$frag_dates$_fdate
"
    done
  fi

  # Unconsumed legacy lines: entry-form lines (`- <date> [<scope>] …`) in the
  # frozen file with no in-place `— consumed-by:` annotation. The freeze header
  # and non-entry prose are never counted. Calendar-invalid entry dates still
  # count as unmined (never a silent drop) but never become the oldest entry.
  leg_count=0
  leg_oldest=""
  if [ "$obsroot_ok" -eq 1 ] && [ -f "$legacy" ] && [ ! -L "$legacy" ]; then
    if [ ! -r "$legacy" ]; then
      printf 'error: observations log unreadable\n'
      n_err=$((n_err + 1))
    else
      # Single-read digest bracket: the frozen log is still appended by every
      # skill until the migration freeze lands, so it races the same way the
      # tasks.md sweep does. The fragment reads above need no such guard — each
      # fragment is published atomically (obs-record.sh's exclusive hard-link),
      # so a fragment is never seen half-written.
      _lpre=$(cksum <"$legacy" 2>/dev/null) || _lpre="(vanished)"
      _leg=$(awk '
        function valid_date(d,  y, m, dd, dim) {
          y = substr(d, 1, 4) + 0
          m = substr(d, 6, 2) + 0
          dd = substr(d, 9, 2) + 0
          if (m < 1 || m > 12 || dd < 1) return 0
          dim = 31
          if (m == 4 || m == 6 || m == 9 || m == 11) dim = 30
          if (m == 2)
            dim = (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28
          return dd <= dim
        }
        # Entry form `- <date> [<scope>] <text>`: require the closing `] `,
        # so this reader agrees with obs-render.sh is_entry_form on exactly
        # which legacy lines are entries (a bare `- <date> [scope` with no
        # close is not an entry to either surface). Calendar-invalid dates
        # still count as unmined (never silently dropped) but never become the
        # oldest — the deliberate render/drain asymmetry: render skips them,
        # drain keeps them counted (REQ-C1.3 vs D-4).
        /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] \[.*\] / {
          if (index($0, "consumed-by:") > 0) next
          n++
          d = substr($0, 3, 10)
          if (valid_date(d) && (oldest == "" || d < oldest)) oldest = d
        }
        END { printf "%d %s", n + 0, (oldest == "" ? "-" : oldest) }
      ' "$legacy" 2>/dev/null) || _leg="0 -"
      _lpost=$(cksum <"$legacy" 2>/dev/null) || _lpost="(vanished)"
      if [ "$_lpre" != "$_lpost" ]; then
        printf 'error: observations log changed during the sweep - counts may be torn; re-run\n'
        n_err=$((n_err + 1))
      fi
      leg_count=${_leg%% *}
      leg_oldest=${_leg#* }
      [ "$leg_oldest" = "-" ] && leg_oldest=""
    fi
  fi

  # Oldest across both surfaces (string min over YYYY-MM-DD; fragment names are
  # grammar-validated so their dates are always real).
  frag_oldest=$(printf '%s' "$frag_dates" | grep . | sort | head -n1)
  overall_oldest=""
  for _cand in "$frag_oldest" "$leg_oldest"; do
    [ -n "$_cand" ] || continue
    if [ -z "$overall_oldest" ]; then
      overall_oldest=$_cand
    else
      overall_oldest=$(printf '%s\n%s\n' "$overall_oldest" "$_cand" | sort | head -n1)
    fi
  done

  total_unmined=$((frag_live + leg_count))
  if [ "$total_unmined" -eq 0 ]; then
    # Zero unmined: state the zero count and omit the age line (REQ-C1.3).
    printf 'unmined: 0\n'
  else
    _surfaces=""
    [ "$frag_live" -gt 0 ] && _surfaces="fragments: $frag_live"
    if [ "$leg_count" -gt 0 ]; then
      if [ -n "$_surfaces" ]; then
        _surfaces="$_surfaces, legacy: $leg_count"
      else
        _surfaces="legacy: $leg_count"
      fi
    fi
    if [ -n "$overall_oldest" ]; then
      _age=$(awk -v o="$overall_oldest" -v t="$today" '
        function jdn(y, m, d,  a, yy, mm) {
          a = int((14 - m) / 12)
          yy = y + 4800 - a
          mm = m + 12 * a - 3
          return d + int((153 * mm + 2) / 5) + 365 * yy + int(yy / 4) \
            - int(yy / 100) + int(yy / 400) - 32045
        }
        BEGIN {
          split(o, p, "-")
          split(t, q, "-")
          age = jdn(q[1] + 0, q[2] + 0, q[3] + 0) - jdn(p[1] + 0, p[2] + 0, p[3] + 0)
          if (age < 0) age = 0
          print age
        }')
      printf 'unmined: %d (%s) - oldest: %s (%d days)\n' \
        "$total_unmined" "$_surfaces" "$overall_oldest" "$_age"
    else
      printf 'unmined: %d (%s) - oldest: (no valid entry date)\n' \
        "$total_unmined" "$_surfaces"
    fi
  fi

  # Name the excluded fragments so an invalid or stuck one is never a silently
  # lost observation (IFS=newline so a name carrying a space stays one row).
  if [ -n "$stuck" ]; then
    _oifs=$IFS
    IFS='
'
    for _s in $stuck; do
      printf 'stuck consume (annotated, not archived): entries/%s\n' "$_s"
    done
    IFS=$_oifs
  fi
  if [ -n "$invalid" ]; then
    _oifs=$IFS
    IFS='
'
    for _iv in $invalid; do
      printf 'skipped invalid fragment (excluded from count): entries/%s\n' "$_iv"
    done
    IFS=$_oifs
  fi
  if [ -n "$unreadable" ]; then
    _oifs=$IFS
    IFS='
'
    for _ur in $unreadable; do
      printf 'unreadable fragment (excluded from count): entries/%s\n' "$_ur"
    done
    IFS=$_oifs
  fi

  printf '\n== summary ==\n'
  printf 'gates: %d - satisfied: %d - surfaced: %d - pending: %d - dormant: %d - free-text: %d - malformed: %d - errors: %d\n' \
    "$total" "$n_sat" "$n_sur" "$n_pen" "$n_dor" "$n_free" "$n_mal" "$n_err"
}

# Capture the report before stripping: a failure inside report() then
# fails this assignment and aborts with the real status under set -e,
# instead of a pipeline emitting a truncated report with tr's exit 0. A
# complete report always ends with the "== summary ==" section.
out=$(report)

# Strip control characters from the echoed report (REQ-H1.3): C0 minus
# newline, DEL, and the C1 range 0x80-0x9F (8-bit CSI and friends; a
# multibyte character using C1 continuation bytes degrades rather than
# reaching the terminal as a control sequence).
printf '%s\n' "$out" | tr -d '\000-\011\013-\037\177\200-\237'
