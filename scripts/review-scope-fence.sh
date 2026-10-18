#!/bin/sh
# review-scope-fence.sh — the reviewer-basics scope fence: report every file
# the change touches outside the unit's deliverables, each one a finding for
# the gate to disposition (review-effectiveness REQ-A1.7, D-2).
#
# THE CHANGED FILES are one repo path per line: --changed <file>, or a handoff
# bundle's changed-files.txt (scripts/review-handoff.sh), which holds both
# sides of a rename.
#
# THE DELIVERABLES are entries of three shapes: a path ending in `/` admits
# everything under it; one holding `*`, `?`, or `[` is a shell pattern, `*`
# crossing `/`; anything else admits that exact path. They come from
# --deliverables <file> (one entry per line), or are read from a task
# contract (--contract, or the bundle's contract.md): every backticked token
# in a `Deliverables:` field that holds a `/` or a `.`, has no whitespace or
# `<`, and does not start with `-`. The field is read with the shared task
# grammar (scripts/spec-parse.sh): it runs over its indented continuation
# lines and ends at a blank line, prose, another bullet, or a heading, and a
# column-0 code fence admits nothing. Prose naming a file without backticks
# admits nothing, so the fence errs toward reporting; --allow <entry> adds an
# entry, repeatable.
#
# Prints `outside <path>` per file outside the fence. With --bundle, every
# path the builder refused to carry (its skipped-files.txt) is reported
# outside too, whatever the deliverables say. A contract that yields no entry
# is refused rather than fencing everything out.
#
# Usage:
#   review-scope-fence.sh (--bundle <dir> | --changed <file>
#       (--contract <file> | --deliverables <file>)) [--allow <entry> ...]
#
# Exit codes: 0 every file is inside; 1 one or more are outside; 2 usage or a
#   refused input.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-scope-fence
NL='
'
here=$(cd "$(dirname "$0")" && pwd)
spec_parse_sh="$here/spec-parse.sh"
if [ ! -f "$spec_parse_sh" ] || [ ! -r "$spec_parse_sh" ]; then
  printf '%s\n' "$prog: spec-parse.sh missing or unreadable: $spec_parse_sh" >&2
  exit 2
fi
# shellcheck source=scripts/spec-parse.sh
. "$spec_parse_sh" || exit 2

usage() {
  cat >&2 <<EOF
usage: $prog (--bundle <dir> | --changed <file> (--contract <file> | --deliverables <file>))
         [--allow <entry> ...]
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" >&2
  exit "$1"
}
readable() {
  [ -f "$2" ] && [ -r "$2" ] || die 2 "$1 is not a readable file: $2"
}

bundle=
changed=
skipped=
contract=
deliverables=
allow=
while [ $# -gt 0 ]; do
  case $1 in
    --bundle | --changed | --contract | --deliverables | --allow)
      [ $# -ge 2 ] || usage
      case $1 in
        --bundle) bundle=$2 ;;
        --changed) changed=$2 ;;
        --contract) contract=$2 ;;
        --deliverables) deliverables=$2 ;;
        --allow)
          case $2 in *"$NL"* | '') die 2 "--allow takes one non-empty entry" ;; esac
          allow=$allow$2$NL
          ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ -n "$bundle" ]; then
  [ -z "$changed$contract$deliverables" ] || usage
  [ -f "$bundle/MANIFEST" ] && [ "$(sed -n 1p "$bundle/MANIFEST")" = "$(printf 'review-handoff\t1')" ] \
    || die 2 "not a handoff bundle: $bundle"
  changed=$bundle/changed-files.txt
  skipped=$bundle/skipped-files.txt
  [ -f "$skipped" ] || die 2 "the bundle holds no skipped-files.txt; rebuild it with scripts/review-handoff.sh"
  contract=$bundle/contract.md
  [ -f "$contract" ] || die 2 "the bundle holds no contract.md; build it with --tasks-file and --task"
fi
[ -n "$changed" ] || usage
[ -n "$contract" ] || [ -n "$deliverables" ] || usage
[ -z "$contract" ] || [ -z "$deliverables" ] || usage
readable "the changed-files list" "$changed"

if [ -n "$contract" ]; then
  readable "--contract" "$contract"
  entries=$(awk "$spec_parse_awk_fence$spec_parse_awk_grammar"'
    /^#/ { on = 0; next }
    /^- / { on = (spec_parse_task_field($0) == "deliverables"); if (on) text = text " " $0; next }
    /^[ \t]+[^ \t]/ { if (on) text = text " " $0; next }
    { on = 0 }
    END {
      while (match(text, /`[^`]*`/)) {
        tok = substr(text, RSTART + 1, RLENGTH - 2)
        text = substr(text, RSTART + RLENGTH)
        if (tok ~ /^-/ || tok ~ /[[:space:]<]/ || tok !~ /[\/.]/) continue
        print tok
      }
    }' "$contract")
  [ -n "$entries" ] || die 2 "the contract names no deliverable path in backticks; pass --deliverables instead"
else
  readable "--deliverables" "$deliverables"
  entries=$(grep -v '^[[:space:]]*$' "$deliverables" || true)
fi
entries=$entries$NL$allow

status=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  inside=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    case $e in
      */)
        case $path in "$e"*) inside=1 ;; esac
        ;;
      *[*?[]*)
        # shellcheck disable=SC2254 # the entry is a pattern by contract
        case $path in $e) inside=1 ;; esac
        ;;
      *)
        [ "$path" != "$e" ] || inside=1
        ;;
    esac
    [ "$inside" -eq 0 ] || break
  done <<EOF
$entries
EOF
  if [ "$inside" -eq 0 ]; then
    printf 'outside\t%s\n' "$path"
    status=1
  fi
done <"$changed"
if [ -n "$skipped" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf 'outside\t%s\n' "$path"
    status=1
  done <"$skipped"
fi
exit "$status"
