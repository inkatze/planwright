#!/bin/sh
# check-sidedness.sh — the advisory sidedness check (operator-dialogue REQ-M1.3,
# REQ-I1.4, D-19).
#
# `interaction-style` requires every emit mandate to declare its destination
# side: an instruction whose object is content delivered somewhere says whether
# that somewhere is the attended turn or an artifact. A mandate that says only
# "present the four tables" is how a full audit record kept landing on the
# operator: nothing said which side it belonged to, so the turn got it.
#
# This check flags such mandates in skill and doctrine prose. It is a
# heuristic over natural phrasing, never a marker grammar, and it has false
# positives, so it INFORMS and never gates: it always exits zero on a scan,
# whatever it finds. Its reader is the person repairing the flagged surface;
# the finding is drained by that repair's review, not by a red build. A wrong
# gate teaches gate-dodging.
#
# What counts as an emit mandate: a sentence that opens with an emit verb in
# the imperative ("Present the counts", "Show the record") or carries one
# after a modal ("the skill must emit ..."). The verbs are present, emit,
# print, render, show, display, paste, surface, output, and report. The
# imperative is recognized by a determiner or count after the verb ("the",
# "each", "42"), so a bare-plural object ("Surface implicit terms") goes
# unreported: the price of not reading "Output is" or "Report format" as
# mandates. A sentence opening with "never" or "do not" is a prohibition, not
# a mandate.
#
# What counts as a declared side: a phrase naming the turn ("to the operator",
# "turn-side", "in the turn", "in the terminal", "stdout") or naming an artifact ("artifact-side",
# "the PR body", "the brief", "recorded in", "tasks.md", a `.md` file name).
# Headings, table rows, frontmatter, and code-fence bodies are not prose and
# are skipped.
#
# The corpus is skills/**/*.md and doctrine/*.md under the root. tests/ is
# outside it on purpose: the planted side-less fixture the unit test uses lives
# there, and the live pass must never report it.
#
# Usage: check-sidedness.sh [--root <dir>] [<file>...]
#   --root <dir>  repository root whose corpus is scanned (default: this repo)
#   <file>...     scan exactly these files instead of the corpus
#
# Exit: 0 after any scan, findings or not; 2 on a usage error only.
#
# Portable POSIX sh + awk (mawk-safe: no three-argument match). File content
# is matched as data, never executed; reported excerpts pass the canonical
# sanitizer before reaching the terminal.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/echo-safety.sh
. "$SELF_DIR/echo-safety.sh"

prog="check-sidedness"
root="$(cd "$SELF_DIR/.." && pwd)"

usage() {
  printf '%s\n' "$prog: $(sanitize_printable "$1")" >&2
  printf '%s\n' "usage: check-sidedness.sh [--root <dir>] [<file>...]" >&2
  exit 2
}

files=""
explicit=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || usage "--root needs a value"
      root="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,/^[^#]/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) usage "unknown option: $1" ;;
    *)
      files="$files$1
"
      explicit=1
      shift
      ;;
  esac
done

if [ "$explicit" -eq 0 ]; then
  if [ ! -d "$root" ]; then
    printf '%s\n' "$prog: root '$(sanitize_printable "$root")' is not a directory; nothing scanned (advisory, never gates)"
    exit 0
  fi
  files="$(cd "$root" && {
    find -L skills -type f -name '*.md' 2>/dev/null
    find -L doctrine -maxdepth 1 -type f -name '*.md' 2>/dev/null
  } | sort)"
fi

# scan <display-name> <path> — print one "<name>:<line>: <excerpt>" line per
# side-less mandate.
scan() {
  awk -v name="$1" '
    function flush(   s, l, lead) {
      if (cur == "") return
      s = cur
      cur = ""
      l = tolower(s)
      gsub(/[*_`]/, "", l)
      sub(/^ +/, "", l)
      sub(/^([-+] |[0-9]+\. )/, "", l)
      sub(/^ +/, "", l)
      if (l ~ /^(never|do not|don.t) /) return
      verbs = "(present|emit|print|render|show|display|paste|surface|output|report)"
      dets = "(the|a|an|it|them|this|that|these|those|each|every|any|all|one|both|its|their|what|which|whether|only|no|[0-9]+)"
      lead = "^((then|and|also|always|finally|first|next|instead|otherwise),? )?" verbs "( " dets " |:)"
      if (l !~ lead && l !~ ("(must|shall|should|always) ((also|then|first|instead|only) )?" verbs "( |$)")) return
      if (l ~ /(turn-side|turn side|in the turn|into the turn|to the operator|at the operator|for the operator|the operator.s turn|to the user|in-band|in band|to the terminal|in the terminal|on the terminal|stdout|stderr|in chat|in the reply|in the selector|option preview)/) return
      if (l ~ /(artifact-side|artifact side|in the artifact|to the artifact|into the artifact|pr body|pr-body|pull request body|pr description|in the brief|to the brief|into the brief|tasks\.md|awaiting.input|in the log|to the log|into the log|decision log|in a file|to a file|in the file|to the file|into the file|recorded in|recorded to|record it in|written to|write it to|appended to|commit message|as a comment|in a comment|observation fragment|\.md|changelog|ledger|risk register|in the spec|to the spec)/) return
      gsub(/[^ -~]+/, "-", s)
      if (length(s) > 100) s = substr(s, 1, 97) "..."
      printf "%s:%d: %s\n", name, start, s
    }
    function take(line,   p) {
      gsub(/\*/, "", line)
      sub(/^[ \t]+/, "", line)
      if (cur == "") start = NR
      cur = (cur == "" ? line : cur " " line)
      while (match(cur, /[.!?]( |$)/)) {
        p = RSTART
        rest = substr(cur, p + 2)
        cur = substr(cur, 1, p)
        flush()
        sub(/^ +/, "", rest)
        cur = rest
        if (cur != "") start = NR
      }
    }
    NR == 1 && /^---[ \t]*$/ { front = 1; next }
    front { if ($0 ~ /^---[ \t]*$/) front = 0; next }
    /^[ \t]*(```|~~~)/ {
      flush()
      t = $0
      sub(/^[ \t]*/, "", t)
      if (fence == "") fence = substr(t, 1, 3)
      else if (substr(t, 1, 3) == fence) fence = ""
      next
    }
    fence != "" { next }
    /^[ \t]*$/ || /^#/ || /^[ \t]*\|/ || /^[ \t]*</ { flush(); next }
    /^[ \t]*([-+*]|[0-9]+\.) / { flush() }
    { take($0) }
    END { flush() }
  ' "$2"
}

findings=0
scanned=0
report=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ "$explicit" -eq 1 ]; then
    path="$f"
  else
    path="$root/$f"
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf '%s\n' "$prog: cannot read '$(sanitize_printable "$f")' as a file; skipped" >&2
    continue
  fi
  scanned=$((scanned + 1))
  out="$(scan "$f" "$path")"
  [ -n "$out" ] || continue
  report="$report$out
"
done <<EOF
$files
EOF

if [ -n "$report" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    findings=$((findings + 1))
    printf '%s\n' "$prog: $(sanitize_printable "$line")"
  done <<EOF
$report
EOF
fi

printf '%s\n' "$prog: $findings emit mandate(s) with no declared destination side in $scanned file(s) (advisory, never gates)"
exit 0
