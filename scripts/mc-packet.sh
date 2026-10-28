#!/usr/bin/env bash
# mc-packet.sh — the prepared-moments duty: the packet the operator gets
# before a human gate, the readiness result first, and the record of what
# they last looked at.
#
# `mc-packet.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-packet
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

help_text() {
  cat <<'HELP'
mc-packet.sh — the prepared-moments duty: the packet the operator gets
before a human gate, the readiness result first, and the record of what
they last looked at.

THE LOOKS store is the program home's kb/prepared-moments/looks.tsv
("# format: 1", then unit<TAB>head<TAB>epoch), the head each unit stood at
when the operator last looked.

Usage:
  mc-packet.sh look --program <p> --unit <unit> --head <sha>
      record that the operator looked at the unit at <head>
  mc-packet.sh assemble --program <p> --unit <unit> --readiness <file>
                        [--look <file>] [--repo <dir> --head <sha>]
                        [--risks <file>] [--order <file>]
      the packet, its sections always in this order:
        Readiness             the walk (scripts/mc-readiness.sh walk), whole
        What to look at       --look's lines
        Changed since you last looked
                              the commits between the recorded look and
                              --head in --repo (`first look` with none
                              recorded, `nothing` at the same head)
        Risks                 --risks' lines
        Order                 --order's lines (scripts/mc-radar.sh order)
      a section with no input reads `- none`; a readiness file that does
      not open with ready or not-ready is refused, so no packet goes out
      without its readiness result

Exit codes: 0 done; 1 a refused input or a store that cannot be read or
written; 2 usage; 3 the program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-packet.sh look --program <p> --unit <unit> --head <sha> | assemble --program <p> --unit <unit> --readiness <file> [--look <file>] [--repo <dir> --head <sha>] [--risks <file>] [--order <file>]"
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
[ $# -ge 1 ] || usage
verb=$1
shift
program=""
unit=""
head=""
readiness=""
look=""
repo=""
risks=""
order=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --unit | --head | --readiness | --look | --repo | --risks | --order)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --unit) unit=$2 ;;
        --head) head=$2 ;;
        --readiness) readiness=$2 ;;
        --look) look=$2 ;;
        --repo) repo=$2 ;;
        --risks) risks=$2 ;;
        --order) order=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] && [ -n "$unit" ] || usage
case $unit in *'	'*) mc_usage_fail "--unit takes no tab" ;; esac
valid_sha() {
  case $1 in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 40 ]
}
mc_require_program "$program"
home=$(/bin/bash "$script_dir/mc-program.sh" get "$program" home) || mc_fail "the home of program $program does not resolve"
store="$home/kb/prepared-moments/looks.tsv"
if [ -e "$store" ]; then
  awk 'NR == 1 { exit ($0 != "# format: 1") } END { if (NR == 0) exit 1 }' "$store" || mc_fail "the looks store has a missing or unknown format: $store"
fi

section() { # section <title> <file|"">
  printf '\n%s\n' "$1"
  if [ -n "$2" ] && [ -s "$2" ]; then
    mc_clean_text <"$2"
  else
    printf -- '- none\n'
  fi
}

case $verb in
  look)
    valid_sha "$head" || mc_usage_fail "--head takes a full 40-hex sha"
    [ -z "$readiness$look$repo$risks$order" ] || usage
    mkdir -p "${store%/*}" || mc_fail "cannot create ${store%/*}"
    trap mc_kb_unlock EXIT
    mc_kb_lock "$program" prepared-moments/looks.tsv
    {
      printf '# format: 1\n'
      [ ! -e "$store" ] || U=$unit awk -F '\t' 'NR > 1 && $1 != ENVIRON["U"]' "$store"
      printf '%s\t%s\t%s\n' "$unit" "$head" "$(mc_now)"
    } | mc_write "$store" || mc_fail "cannot write $store"
    printf 'looked\t%s\t%s\n' "$unit" "$head"
    ;;
  assemble)
    [ -n "$readiness" ] || usage
    [ -r "$readiness" ] || mc_fail "the readiness result is unreadable: $(sanitize_printable "$readiness")"
    case $(head -n 1 "$readiness" | cut -f1) in
      ready | not-ready) ;;
      *) mc_fail "the readiness result does not open with ready or not-ready; no packet without it" ;;
    esac
    for f in "$look" "$risks" "$order"; do
      [ -z "$f" ] || [ -r "$f" ] || mc_fail "unreadable: $(sanitize_printable "$f")"
    done
    if [ -n "$repo$head" ]; then
      [ -n "$repo" ] && [ -d "$repo" ] || mc_usage_fail "--head takes --repo, a directory"
      valid_sha "$head" || mc_usage_fail "--head takes a full 40-hex sha"
    fi
    scratch=$(mktemp -d) || mc_fail "cannot create a scratch directory"
    # shellcheck disable=SC2064 # the path is fixed now
    trap "rm -rf '$scratch'" EXIT
    changed=$scratch/changed
    if [ -n "$head" ]; then
      last=""
      [ ! -e "$store" ] || last=$(U=$unit awk -F '\t' 'NR > 1 && $1 == ENVIRON["U"] { print $2 }' "$store" | tail -n 1)
      if [ -z "$last" ]; then
        printf -- '- first look\n' >"$changed"
      elif [ "$last" = "$head" ]; then
        printf -- '- nothing\n' >"$changed"
      else
        git -C "$repo" log --no-color --format='- %h %s' "$last..$head" -- >"$changed" 2>/dev/null \
          || mc_fail "the commits since the last look cannot be read"
        [ -s "$changed" ] || printf -- '- nothing\n' >"$changed"
      fi
    else
      : >"$changed"
    fi
    printf 'Packet: %s\n' "$unit" | mc_clean_text
    section Readiness "$readiness"
    section "What to look at" "$look"
    section "Changed since you last looked" "$changed"
    section Risks "$risks"
    section Order "$order"
    ;;
  *) usage ;;
esac
