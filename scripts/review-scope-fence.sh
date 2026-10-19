#!/bin/sh
# review-scope-fence.sh — the reviewer-basics scope fence: report every file
# the change touches outside the unit's deliverables, each one a finding for
# the gate to disposition (review-effectiveness REQ-A1.7, D-2).
#
# THE CHANGED FILES are one repo path per line: --changed <file>, or a handoff
# bundle's changed-files.txt (scripts/review-handoff.sh), which holds both
# sides of a rename.
#
# THE DELIVERABLES are entries of three shapes: one holding `*`, `?`, or `[`
# is a shell pattern, `*` crossing `/`; a path ending in `/` admits everything
# under it (under every match, for a pattern); anything else admits that exact
# path. A leading `./` is dropped. They come from
# --deliverables <file> (one entry per line), or are read from a task
# contract (--contract, or the bundle's contract-base.md, the contract as the
# base revision holds it, so a branch cannot widen its own fence by editing
# its tasks file): every backticked token
# in a `Deliverables:` field that holds a `/` or a `.`, has no whitespace or
# `<`, and does not start with `-`. The field is read with the shared task
# grammar (scripts/spec-parse.sh): it runs over its indented continuation
# lines and ends at a blank line, prose, another bullet, or a heading, and a
# column-0 code fence admits nothing. Prose naming a file without backticks
# admits nothing, so the fence errs toward reporting; --allow <entry> adds an
# entry, repeatable.
#
# Prints `outside <path>` per file outside the fence, the path stripped of
# non-printable bytes. With --bundle, every
# path the builder refused to carry (its skipped-files.txt) is reported
# outside too, whatever the deliverables say. A contract that yields no entry
# is refused rather than fencing everything out.
#
# --bundle needs a bundle built from the repository's current HEAD (its
# MANIFEST head) by a builder that records its build id, which must not change
# while the fence reads it, and that holds contract-base.md; when the builder
# recorded why that file is absent, the refusal names the reason, and
# --changed <bundle>/changed-files.txt with a trusted --contract is the
# fallback.
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
# printable — the input without its non-printable bytes, tabs and newlines kept.
printable() { tr -d '\000-\010\013-\037\177\200-\237'; }
readable() {
  [ -f "$2" ] && [ -r "$2" ] || die 2 "$1 is not a readable file: $2"
}
# manifest_value <key> — the bundle MANIFEST's first value for a key.
manifest_value() {
  awk -F '\t' -v k="$1" '$1 == k { print $2; exit }' "$bundle/MANIFEST"
}
# dot_slash <entry> — the entry without its leading `./` runs.
dot_slash() {
  e=$1
  while :; do
    case $e in ./*) e=${e#./} ;; *) break ;; esac
  done
  printf '%s\n' "$e"
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
          allow=$allow$(dot_slash "$2")$NL
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
  build=$(manifest_value build)
  [ -n "$build" ] || die 2 "the bundle records no build id; rebuild it with scripts/review-handoff.sh"
  current=$(git -C "$bundle" rev-parse --verify --quiet 'HEAD^{commit}') \
    || die 2 "cannot read the HEAD of the repository holding the bundle"
  [ "$(manifest_value head)" = "$current" ] || die 2 "the bundle is stale: it was built from another head; rebuild it"
  contract=$bundle/contract-base.md
  if [ ! -f "$contract" ]; then
    why=$(manifest_value contract_base_absent)
    die 2 "the bundle holds no contract-base.md (${why:-no reason recorded}): build it with --tasks-file and --task against a base whose tasks file holds every task, or pass --changed $bundle/changed-files.txt with a trusted --contract"
  fi
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
entries=$(printf '%s\n' "$entries" | while IFS= read -r e || [ -n "$e" ]; do dot_slash "$e"; done)
entries=$entries$NL$allow

status=0
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  inside=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    # shellcheck disable=SC2254 # the entry is a pattern by contract
    case $e in
      *[*?[]*/)
        case $path in $e*) inside=1 ;; esac
        ;;
      *[*?[]*)
        case $path in $e) inside=1 ;; esac
        ;;
      */)
        case $path in "$e"*) inside=1 ;; esac
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
    printf 'outside\t%s\n' "$path" | printable
    status=1
  fi
done <"$changed"
if [ -n "$skipped" ]; then
  while IFS= read -r path || [ -n "$path" ]; do
    [ -n "$path" ] || continue
    printf 'outside\t%s\n' "$path" | printable
    status=1
  done <"$skipped"
  # A build that swapped in while the fence read could have mixed two bundles.
  [ "$(manifest_value build)" = "$build" ] || die 2 "the bundle was rebuilt while the fence read it; run the fence again"
fi
exit "$status"
