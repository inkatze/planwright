#!/usr/bin/env bash
# mc-adapter-forge.sh — the shipped snapshot adapter for the forge (GitHub
# through the gh CLI and its own authentication; nothing is stored).
#
# Implements the adapter contract scripts/mc-snapshot.sh's header states:
#   mc-adapter-forge.sh refresh --program <p> --out <file> [--previous <file>]
# For each of the program's repositories, one GraphQL read lists the tracked
# pull requests (mission_control_forge_tracked: every open one, or only those
# the gh account authored; the newest 50 by update time, threads counted over
# the first 100) and writes one line per pull request:
#   pr<TAB><owner/name><TAB><number><TAB><head sha><TAB><draft true|false>
#     <TAB><mergeable><TAB><review decision|NONE><TAB><open threads>
#     <TAB><checks state|NONE><TAB><reviews><TAB><comments><TAB><patch id|->
# The patch id (git patch-id --stable over the pull request's diff) is carried
# forward from --previous while the head is unchanged, so an unchanged patch
# costs no read; a changed head costs one diff read.
#
# Prints `ratelimit<TAB><remaining><TAB><reset-epoch>` from the GraphQL rate
# limit, the lowest seen across the repositories. Exit 0 the snapshot is
# written; 75 the forge refused a read for its rate limit; 1 any other failed
# read or an unexpected field; 2 usage.
#
# Portable bash 3.2 / BSD tooling; gh's built-in --jq does the JSON.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-adapter-forge
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

usage() { mc_usage_fail "usage: mc-adapter-forge.sh refresh --program <p> --out <file> [--previous <file>]"; }

[ $# -ge 1 ] && [ "$1" = refresh ] || usage
shift
program=""
out=""
previous=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --out | --previous)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --out) out=$2 ;;
        --previous) previous=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] && [ -n "$out" ] || usage
mc_valid_program "$program" || mc_usage_fail "invalid program name '$(sanitize_printable "$program")'"
command -v gh >/dev/null 2>&1 || mc_fail "gh is not installed"

# shellcheck disable=SC2329 # called by name through mc_knob
is_tracked() {
  case $1 in
    open | authored) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}
tracked=$(mc_knob mission_control_forge_tracked is_tracked) || exit 1
repos=$(/bin/bash "$script_dir/mc-program.sh" get "$program" repositories) || exit 1

errf=$(mktemp) || mc_fail "mktemp failed"
body=$(mktemp) || mc_fail "mktemp failed"
trap 'rm -f "$errf" "$body"' EXIT

# gh_read <args...>: run gh, stdout to the caller; exit 75 on a rate-limit
# refusal, 1 on any other failure.
gh_read() {
  if gh "$@" 2>"$errf"; then
    return 0
  fi
  if grep -qi 'rate limit' "$errf"; then
    printf '%s\n' "$prog: the forge refused a read for its rate limit" >&2
    exit 75
  fi
  printf '%s\n' "$prog: gh $1 failed: $(head -n 1 "$errf" | mc_clean)" >&2
  exit 1
}

# shellcheck disable=SC2016 # GraphQL variables, not shell ones
QUERY='query($owner:String!,$name:String!){ rateLimit{ remaining resetAt } viewer{ login } repository(owner:$owner,name:$name){ pullRequests(states:OPEN,first:50,orderBy:{field:UPDATED_AT,direction:DESC}){ nodes{ number headRefOid isDraft mergeable reviewDecision author{ login } reviewThreads(first:100){ nodes{ isResolved } } commits(last:1){ nodes{ commit{ statusCheckRollup{ state } } } } reviews{ totalCount } comments{ totalCount } } } } }'
# The first line is the rate limit; then one row per tracked pull request.
# shellcheck disable=SC2016 # jq, not shell
JQ='"ratelimit\t\(.data.rateLimit.remaining)\t\(.data.rateLimit.resetAt | fromdateiso8601)",
  (.data.viewer.login as $me | .data.repository.pullRequests.nodes[]
   | select($tracked == "open" or .author.login == $me)
   | [.number, .headRefOid, .isDraft, .mergeable, (.reviewDecision // "NONE"),
      ([.reviewThreads.nodes[] | select(.isResolved | not)] | length),
      (.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
      .reviews.totalCount, .comments.totalCount] | @tsv)'
JQ="def tracked: \"$tracked\"; ${JQ//\$tracked/tracked}"

low_remaining=""
low_reset=""
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  slug=$(cd "$repo" && gh_read repo view --json nameWithOwner --jq .nameWithOwner) || exit $?
  case $slug in
    */*) ;;
    *) mc_fail "unexpected repository name for $(sanitize_printable "$repo")" ;;
  esac
  case $slug in
    *[!A-Za-z0-9._/-]* | */*/*) mc_fail "unexpected repository name '$(sanitize_printable "$slug")'" ;;
  esac
  rows=$(gh_read api graphql -f owner="${slug%%/*}" -f name="${slug#*/}" -f query="$QUERY" --jq "$JQ") || exit $?
  first=1
  while IFS='	' read -r a b c d e f g h i; do
    if [ "$first" -eq 1 ]; then
      first=0
      if [ "$a" != ratelimit ] || ! mc_valid_uint "$b" || ! mc_valid_uint "$c"; then
        mc_fail "unexpected rate-limit line from the forge"
      fi
      if [ -z "$low_remaining" ] || [ "$b" -lt "$low_remaining" ]; then
        low_remaining=$b
        low_reset=$c
      fi
      continue
    fi
    mc_valid_uint "$a" || mc_fail "unexpected pull request number from the forge"
    case $b in
      *[!0-9a-f]* | "") mc_fail "unexpected head for #$a" ;;
    esac
    case $c in true | false) ;; *) mc_fail "unexpected draft state for #$a" ;; esac
    for v in "$d" "$e" "$g"; do
      case $v in
        "" | *[!A-Z_]*) mc_fail "unexpected state field for #$a" ;;
      esac
    done
    for v in "$f" "$h" "$i"; do
      mc_valid_uint "$v" || mc_fail "unexpected count for #$a"
    done
    patch=""
    if [ -n "$previous" ] && [ -f "$previous" ]; then
      patch=$(awk -F '\t' -v s="$slug" -v n="$a" -v h="$b" \
        '$1 == "pr" && $2 == s && $3 == n && $4 == h && $12 ~ /^[0-9a-f]+$/ { print $12; exit }' "$previous")
    fi
    if [ -z "$patch" ]; then
      diff=$(gh_read pr diff "$a" -R "$slug") || exit $?
      patch=$(printf '%s\n' "$diff" | git patch-id --stable 2>/dev/null | awk 'NR == 1 { print $1 }')
      case $patch in
        "" | *[!0-9a-f]*) patch=- ;;
      esac
    fi
    printf 'pr\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$slug" "$a" "$b" "$c" "$d" "$e" "$f" "$g" "$h" "$i" "$patch" >>"$body"
  done <<EOF
$rows
EOF
done <<EOF
$repos
EOF

cat "$body" >"$out" || mc_fail "cannot write the snapshot body"
[ -z "$low_remaining" ] || printf 'ratelimit\t%s\t%s\n' "$low_remaining" "$low_reset"
exit 0
