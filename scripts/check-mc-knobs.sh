#!/usr/bin/env bash
# check-mc-knobs.sh — mission control's knob inventory check: every
# behaviour that admits a preference is a documented, default-preserving
# mission_control_* knob.
#
# Reads, under the core root:
#   config/defaults.yml               the shipped knobs
#   config/mission-control-knobs.tsv  behaviour<TAB>knob<TAB>consumer rows
#   docs/options-reference.md         one row per knob
#   scripts/mc-*.sh and every inventoried consumer
#
# Fails on:
#   - an inventoried behaviour with no knob (`-` or empty), a knob outside
#     the mission_control_* namespace or absent from the defaults, a consumer
#     that does not exist, resolves outside the core root or never names
#     its knob, or a behaviour listed twice;
#   - a mission_control_* key in the defaults that does not resolve to a
#     non-empty default through scripts/config-get.sh, or that no behaviour
#     claims;
#   - a mission_control_* key a scanned file names that the defaults lack
#     (a reader of a preference nobody declared);
#   - a knob with no options-reference row, or a row that does not carry
#     `Evidence:`.
#
# Usage: check-mc-knobs.sh [--core <dir>]
#   --core <dir>  the core root (default: the checkout holding this script)
#
# Exit codes: 0 clean; 1 a finding; 2 usage, or an input the check cannot
# read.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=check-mc-knobs
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$prog: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2

die() {
  printf '%s\n' "$prog: $1" >&2
  exit 2
}

core=$(cd "$script_dir/.." && pwd) || exit 2
while [ $# -gt 0 ]; do
  case $1 in
    --core)
      [ $# -ge 2 ] || die "--core needs a value"
      core=$2
      shift 2
      ;;
    *) die "unknown argument: $(sanitize_printable "$1")" ;;
  esac
done

core_real=$(cd "$core" 2>/dev/null && pwd -P) || die "cannot read the core root: $(sanitize_printable "$core")"
defaults="$core/config/defaults.yml"
inventory="$core/config/mission-control-knobs.tsv"
reference="$core/docs/options-reference.md"
for f in "$defaults" "$inventory" "$reference"; do
  [ -f "$f" ] && [ -r "$f" ] || die "missing or unreadable: $(sanitize_printable "$f")"
done

scratch=$(mktemp -d) || die "mktemp -d failed"
[ -n "$scratch" ] && [ -d "$scratch" ] || die "mktemp -d produced no directory"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/adopter" "$scratch/claude" || die "cannot populate the scratch directory"

findings=0
finding() {
  printf '%s\n' "$prog: $(sanitize_printable "$1")" >&2
  findings=$((findings + 1))
}

# resolve <key>: the key through the config resolver, the core defaults the
# only layer.
resolve() {
  env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_ROOT \
    -u PLANWRIGHT_REPO_ROOT_CHECKED -u PLANWRIGHT_CONFIG_STRICT_OVERLAYS \
    PLANWRIGHT_CONFIG_DEFAULTS="$defaults" \
    PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_ADOPTER_OVERLAY="$scratch/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="$scratch/absent.yml" \
    CLAUDE_DIR="$scratch/claude" \
    /bin/sh "$script_dir/config-get.sh" "$1" 2>"$scratch/err"
}

keys=$(sed -n 's/^\(mission_control_[a-z0-9_]*\):.*/\1/p' "$defaults")

for k in $keys; do
  value=$(resolve "$k") || value=""
  if [ -z "$value" ]; then
    why=$(head -n 1 "$scratch/err")
    finding "$k does not resolve to a default through scripts/config-get.sh${why:+ ($why)}"
  fi
  row=$(grep -F "| \`$k\` |" "$reference" | head -n 1)
  if [ -z "$row" ]; then
    finding "$k has no row in docs/options-reference.md"
  else
    case $row in
      *"Evidence:"*) ;;
      *) finding "$k's docs/options-reference.md row names no evidence (Evidence:)" ;;
    esac
  fi
done

claimed=" "
seen=" "
consumers=""
# Rows are split by awk, on every tab: read's IFS would merge an empty
# column into its neighbour and drop a last line with no newline. The unit
# separator then carries the columns, empty ones included.
rows=$(awk -F '\t' '!/^#/ && NF { printf "%s\037%s\037%s\n", $1, $2, $3 }' "$inventory")
while IFS=$(printf '\037') read -r behaviour knob consumer; do
  [ -n "$behaviour" ] || continue
  case $seen in
    *" $behaviour "*) finding "behaviour '$behaviour' is inventoried twice" ;;
  esac
  seen="$seen$behaviour "
  case $knob in
    "" | -)
      finding "behaviour '$behaviour' has no knob"
      ;;
    mission_control_*)
      case "
$keys
" in
        *"
$knob
"*) claimed="$claimed$knob " ;;
        *) finding "behaviour '$behaviour' names $knob, which config/defaults.yml lacks" ;;
      esac
      ;;
    *) finding "behaviour '$behaviour' names '$knob', outside the mission_control_* namespace" ;;
  esac
  case $consumer in
    "" | /* | *..*) finding "behaviour '$behaviour' names no consumer inside the core root" ;;
    *)
      consumer_dir=$(cd "$core/$(dirname "$consumer")" 2>/dev/null && pwd -P) || consumer_dir=""
      if [ ! -f "$core/$consumer" ]; then
        finding "behaviour '$behaviour' names consumer $consumer, which does not exist"
      elif [ -L "$core/$consumer" ] || [ -z "$consumer_dir" ] \
        || case $consumer_dir/ in "$core_real"/*) false ;; *) true ;; esac; then
        # A link could point the scan at a file outside the core root.
        finding "behaviour '$behaviour' names consumer $consumer, which resolves outside the core root"
      else
        consumers="$consumers$consumer
"
        [ ! -r "$core/$consumer" ] || grep -qF -- "$knob" "$core/$consumer" \
          || finding "behaviour '$behaviour': $consumer does not read $knob"
      fi
      ;;
  esac
done <<EOF
$rows
EOF

for k in $keys; do
  case $claimed in
    *" $k "*) ;;
    *) finding "$k is claimed by no behaviour in config/mission-control-knobs.tsv" ;;
  esac
done

scanned=$(
  {
    (set +f && cd "$core" && for f in scripts/mc-*.sh; do [ -f "$f" ] && printf '%s\n' "$f"; done)
    printf '%s' "$consumers"
  } | sort -u
)
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -r "$core/$f" ] || die "cannot read $(sanitize_printable "$f")"
  tokens=$(grep -o 'mission_control_[a-z0-9][a-z0-9_]*' "$core/$f" | sort -u)
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    case "
$keys
" in
      *"
$token
"*) ;;
      *) finding "$f names $token, which config/defaults.yml lacks" ;;
    esac
  done <<EOT
$tokens
EOT
done <<EOF
$scanned
EOF

if [ "$findings" -ne 0 ]; then
  printf '%s\n' "$prog: $findings finding(s)" >&2
  exit 1
fi
printf '%s\n' "$prog: mission_control_* knobs inventoried, defaulted and documented"
