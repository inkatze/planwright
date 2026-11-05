#!/usr/bin/env bash
# check-mc-verbs.sh — config/mission-control-verbs.txt, the script verbs the
# command guard's mission-control mode approves, must equal what the
# mission-control skill and config/duties.yaml invoke. `--help` holds the
# derivation rules, options and exit codes.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

help_text() {
  cat <<'HELP'
usage: check-mc-verbs.sh [--print] [--root <dir>] [--skill <file>]
                         [--duties <file>] [--list <file>]

Derives the verbs mission control invokes and fails on any difference from
config/mission-control-verbs.txt, in either direction.

The skill (skills/mission-control/SKILL.md), section by section (heading to
heading), its code spans in order:
  `scripts/<s>.sh`'s `<verb> ...`   names <verb> of <s>
  `scripts/<s>.sh <word> ...`       names <word>; a `<...>` placeholder is any
                                    argument (`*`); a leading flag names
                                    nothing (another session's command)
  any other span                    its first word, when a script referenced
                                    earlier in the section dispatches it (a
                                    top-level `<verb>)` case arm, indented at
                                    most two spaces), names that verb of the
                                    nearest such script
The duty catalog: each `scripts/<s>.sh@...` watcher is <s> run with no
argument (`-`).

Only top-level scripts/<name>.sh paths count, as in the guard tier.
fleet-streamjson.sh answer (the raw prompt-answer verb) is never listed, nor
a `*` entry for that script. The list is core-only: the guard reads it from
its own root and no overlay adds to it.

  --print   print the derived list, one `<script> <verb>` per line
  --root    the core root (default: the checkout holding this script); the
            other paths default under it, scripts read from <root>/scripts

Exit codes: 0 the list matches; 1 a difference, each named on stderr;
2 usage, or an input the check cannot read.
HELP
}

me=check-mc-verbs
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
root=$(cd "$script_dir/.." && pwd -P) || exit 2
skill='' duties='' list='' print=0

die() {
  printf '%s\n' "$me: $1" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case $1 in
    --print)
      print=1
      shift
      ;;
    --root | --skill | --duties | --list)
      [ "$#" -ge 2 ] || die "$1 needs a value"
      case $1 in
        --root) root=$2 ;;
        --skill) skill=$2 ;;
        --duties) duties=$2 ;;
        --list) list=$2 ;;
      esac
      shift 2
      ;;
    -h | --help)
      help_text
      exit 0
      ;;
    *)
      help_text >&2
      exit 2
      ;;
  esac
done
: "${skill:=$root/skills/mission-control/SKILL.md}"
: "${duties:=$root/config/duties.yaml}"
: "${list:=$root/config/mission-control-verbs.txt}"
for f in "$skill" "$duties"; do
  [ -f "$f" ] && [ -r "$f" ] || die "cannot read $f"
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/check-mc-verbs.XXXXXX") || die "cannot create a scratch directory"
trap 'rm -rf "$tmp"' EXIT

# Pass 1 over the skill, one section at a time, its code spans in order:
# the scripts referenced (`R <script>`), explicit pairs (`P <script>
# <verb>`), and each other span's first word with the scripts referenced
# before it in its section, nearest first (`C <word> <script>,...`).
awk '
  function flush(   s, w, sc, rest, after, refs, skip) {
    s = buf
    refs = ""
    skip = 0
    while (match(s, /`[^`]+`/)) {
      w = substr(s, RSTART + 1, RLENGTH - 2)
      s = substr(s, RSTART + RLENGTH)
      if (skip) {
        skip = 0
        continue
      }
      if (match(w, /^scripts\/[a-z0-9][a-z0-9-]*\.sh/)) {
        sc = substr(w, 9, RLENGTH - 8)
        rest = substr(w, RLENGTH + 1)
        print "R", sc
        refs = sc (refs == "" ? "" : "," refs)
        if (rest == "") {
          if (substr(s, 1, 2) == "'"'"'s") {
            after = substr(s, 3)
            sub(/^[ ]+/, "", after)
            if (match(after, /^`[a-z][a-z0-9-]*/)) {
              print "P", sc, substr(after, 2, RLENGTH - 1)
              skip = 1
            }
          }
        } else if (substr(rest, 1, 2) == " <") {
          print "P", sc, "*"
        } else if (match(rest, /^ [a-z][a-z0-9-]*/)) {
          print "P", sc, substr(rest, 2, RLENGTH - 1)
        }
        continue
      }
      if (refs != "" && match(w, /^[a-z][a-z0-9-]*/) && (RLENGTH == length(w) || substr(w, RLENGTH + 1, 1) == " "))
        print "C", substr(w, 1, RLENGTH), refs
    }
    buf = ""
  }
  /^#/ { flush(); next }
  { buf = buf " " $0 }
  END { flush() }
' "$skill" >"$tmp/pass1" || die "cannot read $skill"

# The verbs each referenced script dispatches: its case-arm words.
: >"$tmp/arms"
awk '$1 == "R" { print $2 }' "$tmp/pass1" | sort -u >"$tmp/refs"
while IFS= read -r s; do
  f=$root/scripts/$s
  [ -f "$f" ] || continue
  awk -v s="$s" '
    match($0, /^ ?( )?[a-z][a-z0-9-]*([ \t]*\|[ \t]*[a-z][a-z0-9-]*)*\)/) {
      a = substr($0, RSTART, RLENGTH - 1)
      gsub(/[ \t]/, "", a)
      n = split(a, w, "|")
      for (i = 1; i <= n; i++) print s, w[i]
    }
  ' "$f" >>"$tmp/arms"
done <"$tmp/refs"

{
  awk '$1 == "P" { print $2, $3 }' "$tmp/pass1"
  awk '
    FILENAME == ARGV[1] { arm[$1 " " $2] = 1; next }
    $1 == "C" {
      n = split($3, r, ",")
      for (i = 1; i <= n; i++) if ((r[i] " " $2) in arm) { print r[i], $2; break }
    }
  ' "$tmp/arms" "$tmp/pass1"
  awk '
    /^[ \t]*watchers:/ {
      s = $0
      while (match(s, /scripts\/[a-z0-9][a-z0-9-]*\.sh@/)) {
        print substr(s, RSTART + 8, RLENGTH - 9), "-"
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$duties"
} | awk '!($1 == "fleet-streamjson.sh" && ($2 == "answer" || $2 == "*"))' | sort -u >"$tmp/derived"

if [ "$print" = 1 ]; then
  cat "$tmp/derived"
  exit 0
fi

[ -f "$list" ] && [ -r "$list" ] || die "cannot read $list"
awk 'NF && $1 !~ /^#/ { print $1, $2 }' "$list" | sort -u >"$tmp/listed"

status=0
while read -r s v; do
  printf '%s\n' "$me: $s $v is invoked by mission control but not in ${list#"$root"/}" >&2
  status=1
done < <(comm -23 "$tmp/derived" "$tmp/listed")
while read -r s v; do
  printf '%s\n' "$me: $s $v is in ${list#"$root"/} but nothing mission control runs invokes it" >&2
  status=1
done < <(comm -13 "$tmp/derived" "$tmp/listed")
if awk '$1 == "fleet-streamjson.sh" && ($2 == "answer" || $2 == "*") { found = 1 } END { exit !found }' "$tmp/listed"; then
  printf '%s\n' "$me: ${list#"$root"/} must never pre-approve fleet-streamjson.sh answer" >&2
  status=1
fi
[ "$status" = 0 ] && printf '%s\n' "$me: ok ($(wc -l <"$tmp/derived" | tr -d ' ') verbs)"
exit "$status"
