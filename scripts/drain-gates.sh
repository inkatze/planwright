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
#   PENDING    condition gate with at least one unmet atom
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
# error; any other status means the sweep aborted mid-run (internal
# failure) without emitting a report.
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

    # Single parse pass: the awk program reads the file once, buffering
    # it and collecting the task-id universe (ids defined anywhere
    # outside fenced code blocks; the Completed subset) while reading,
    # then evaluates gates over the buffered lines in END. Two separate
    # parse reads could see different versions of a file being rewritten
    # concurrently and fabricate MALFORMED rows for valid gates; one
    # parse open confines any race to a torn single read, which the
    # digest bracket around this invocation bounds (a rewrite restoring
    # identical bytes within the window is below the check's resolution).
    # The NUL screen above and the digest pair are separate, cheaper
    # opens; only the parse feeds gate evaluation. Each read is guarded
    # so a file vanishing mid-sweep degrades to a report-level error for
    # this spec instead of aborting the whole report.
    if ! pre_digest=$(cksum <"$tasks" 2>/dev/null); then
      printf 'error: tasks.md vanished during the sweep\n'
      n_err=$((n_err + 1))
      continue
    fi
    if ! lines=$(awk -v fname="$tasks" -v today="$today" -v statuses="$statuses" '
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
        atom, verdict, hasdate, allmet, unmet, why) {
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
          else
            add("DORMANT", conf, title, "when: " cond)
        } else {
          if (allmet)
            add("SATISFIED", conf, title, "when: " cond)
          else
            add("PENDING", conf, title, "when: " cond " - unmet: " unmet)
        }
      }

      # One atom -> met / unmet / date-met / date-unmet / bad-*.
      function eval_atom(atom,  nt, tk) {
        if (atom == "") return "bad-atom"
        nt = split(atom, tk, " ")
        if (nt == 3 && tk[1] == "task" && tk[3] == "completed" \
          && tk[2] ~ /^[0-9]+(\.[0-9]+)?$/) {
          if (!(tk[2] in ALL)) return "bad-task"
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
  if [ "$obsroot_ok" -eq 1 ] && [ -d "$entries" ] && [ ! -L "$entries" ]; then
    for _f in "$entries"/*.md; do
      [ -e "$_f" ] || continue
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
