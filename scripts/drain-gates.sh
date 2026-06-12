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
#   DORMANT    date gate not yet reached — date gates only surface, never
#              satisfy and never hard-fail
#   FREE-TEXT  gate text not in GATE(when: ...) form — surfaced verbatim,
#              never evaluated
#   MALFORMED  structured gate failing the grammar — a drain-report-level
#              error: reported, never evaluated, never silently skipped;
#              the pass completes
#
# Confidence (REQ-H1.5): a bullet's `Confidence: <low|medium|high>` orders
# the report within each lane, low first, so low-confidence deferrals
# resurface first.
#
# Also surfaces the observations log's unmined count and oldest-entry age
# (REQ-H1.4, surface only).
#
# Usage: drain-gates.sh [--today YYYY-MM-DD] <specs-root>
#   --today pins the evaluation date (tests); defaults to the system date.
#
# Exit codes: 0 sweep completed (malformed gates are report content, not
# failures), 1 unusable specs root, 2 usage error.
#
# Security (REQ-H1.3): gate content is data only. The parse is pattern
# match; nothing is passed to eval, a subshell, or arithmetic expansion;
# gate text is never used as a pattern, format string, or unquoted
# argument; control characters are stripped from the echoed report.
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
case $today in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *)
    echo "drain-gates: invalid --today date: $today" >&2
    exit 2
    ;;
esac

case $root in
  */) root=${root%/} ;;
esac
if [ -z "$root" ] || [ ! -d "$root" ] || [ ! -r "$root" ]; then
  echo "drain-gates: specs root missing or unreadable: $1" >&2
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

# Spec status map for status atoms: "name=status" pairs, lowercased.
statuses=""
for name in $specs; do
  req="$root/$name/requirements.md"
  if [ -f "$req" ] && [ -r "$req" ]; then
    st=$(awk '/^\*\*Status:\*\*/ { print tolower($2); exit }' "$req")
    [ -n "$st" ] && statuses="$statuses $name=$st"
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

  for name in $specs; do
    tasks="$root/$name/tasks.md"
    printf '\n== spec: %s ==\n' "$name"
    if [ ! -f "$tasks" ] || [ ! -r "$tasks" ]; then
      printf '(no tasks.md)\n'
      continue
    fi

    # Task-id universe for task atoms: ids defined anywhere in the file,
    # and the subset whose block sits in the Completed section.
    ids=$(awk '
      /^## / { sec = $0 }
      /^### Task / {
        id = $3
        all = all id " "
        if (sec ~ /^## Completed/) comp = comp id " "
      }
      END {
        print "ALL " all
        print "COMP " comp
      }' "$tasks")
    allids=$(printf '%s\n' "$ids" | awk '/^ALL / { sub(/^ALL /, ""); print }')
    compids=$(printf '%s\n' "$ids" | awk '/^COMP / { sub(/^COMP /, ""); print }')

    lines=$(awk -v fname="$tasks" -v today="$today" \
      -v allids="$allids" -v compids="$compids" -v statuses="$statuses" '
      BEGIN {
        n = split(allids, a, " ")
        for (i = 1; i <= n; i++) if (a[i] != "") ALL[a[i]] = 1
        n = split(compids, a, " ")
        for (i = 1; i <= n; i++) if (a[i] != "") COMP[a[i]] = 1
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
        buf = ""; inb = 0
      }

      function trim(s) {
        sub(/^[ \t]+/, "", s)
        sub(/[ \t]+$/, "", s)
        return s
      }

      # Buffer one top-level bullet (with its indented continuations) and
      # process it as a unit; gate text may wrap lines.
      /^- / { flush_bullet(); buf = $0; bline = NR; inb = 1; next }
      /^[ \t]/ { if (inb) { buf = buf " " $0; next } }
      { flush_bullet() }
      END { flush_bullet(); emit() }

      function flush_bullet(  text, title, conf, g, k) {
        if (!inb) return
        inb = 0
        text = buf
        buf = ""
        gsub(/[ \t]+/, " ", text)
        if (index(text, "**Gate:**") == 0) return

        title = bullet_title(text)
        conf = bullet_conf(text)

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
        if (!i) return "(untitled)"
        rest = substr(text, i + 2)
        j = index(rest, "**")
        if (!j) return "(untitled)"
        rest = substr(rest, 1, j - 1)
        sub(/\.$/, "", rest)
        return rest
      }

      function bullet_conf(text) {
        if (index(text, "Confidence: low")) return "low"
        if (index(text, "Confidence: medium")) return "medium"
        if (index(text, "Confidence: high")) return "high"
        return "-"
      }

      # Closed-grammar parse of a structured gate: pattern match only, the
      # condition is never executed or expanded (REQ-H1.3).
      function structured(g, title, conf,  cond, p, n, atoms, i, atom, \
        verdict, hasdate, allmet, unmet, why) {
        cond = trim(substr(g, 11))
        p = index(cond, ")")
        if (!p) {
          add("MALFORMED", conf, title, "unterminated GATE(when: ...) - gate: " g)
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
          if (verdict == "bad-date") hasdate = 1
          if (verdict ~ /^bad/) {
            why = atom_error(verdict, atom)
            break
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
          if (substr(tk[2], 6, 2) < "01" || substr(tk[2], 6, 2) > "12" \
            || substr(tk[2], 9, 2) < "01" || substr(tk[2], 9, 2) > "31")
            return "bad-date"
          return (tk[2] <= today) ? "date-met" : "date-unmet"
        }
        return "bad-atom"
      }

      function atom_error(verdict, atom) {
        if (verdict == "bad-task") return "unknown task in atom: " atom
        if (verdict == "bad-spec") return "unknown spec in atom: " atom
        if (verdict == "bad-date") return "invalid date in atom: " atom
        return "unrecognized atom: " atom
      }

      function add(cat, conf, title, detail,  key) {
        key = CAT[cat] "," CONFR[conf]
        cnt[key]++
        line[key, cnt[key]] = cat " [" conf "] " fname ":" bline " - " title " - " detail
      }

      function emit(  c, k, s, key) {
        for (c = 0; c <= 5; c++)
          for (k = 0; k <= 3; k++) {
            key = c "," k
            for (s = 1; s <= cnt[key]; s++) print line[key, s]
          }
      }
    ' "$tasks")

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
  obs="$root/_observations/opportunities.md"
  if [ -f "$obs" ] && [ -r "$obs" ]; then
    awk -v today="$today" '
      function jdn(y, m, d,  a, yy, mm) {
        a = int((14 - m) / 12)
        yy = y + 4800 - a
        mm = m + 12 * a - 3
        return d + int((153 * mm + 2) / 5) + 365 * yy + int(yy / 4) \
          - int(yy / 100) + int(yy / 400) - 32045
      }
      /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / {
        n++
        d = substr($0, 3, 10)
        if (oldest == "" || d < oldest) oldest = d
      }
      END {
        if (n == 0) {
          print "unmined: 0"
          exit
        }
        split(oldest, p, "-")
        split(today, q, "-")
        age = jdn(q[1] + 0, q[2] + 0, q[3] + 0) - jdn(p[1] + 0, p[2] + 0, p[3] + 0)
        printf "unmined: %d - oldest: %s (%d days)\n", n, oldest, age
      }' "$obs"
  else
    printf 'no observations log\n'
  fi

  printf '\n== summary ==\n'
  printf 'gates: %d - satisfied: %d - surfaced: %d - pending: %d - dormant: %d - free-text: %d - malformed: %d\n' \
    "$total" "$n_sat" "$n_sur" "$n_pen" "$n_dor" "$n_free" "$n_mal"
}

# Strip control characters from the echoed report (REQ-H1.3); newlines are
# the only control bytes that belong in it.
report | tr -d '\000-\011\013-\037\177'
