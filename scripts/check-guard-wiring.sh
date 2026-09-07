#!/bin/sh
# check-guard-wiring.sh — every guard this repo ships must be REACHED by the
# gate that is supposed to run it.
#
# A guard nobody invokes is indistinguishable from a guard that always passes.
# The repo has shipped both: two check scripts sat in scripts/ for months,
# fully written and fully tested, wired into nothing. Their tests passed, so
# every signal said the guard existed; the only thing missing was anyone
# running it. That is the same failure shape as an assertion that cannot fail,
# one level up — the check is vacuous because it is never evaluated at all.
#
# WHAT THIS CHECKS. Each scripts/check-*.sh must be named either
#   (a) in the RUN BODY of a mise task reachable from the `check` aggregate,
#   (b) inside a .github/workflows/*.yml or *.yaml file, or
#   (c) in the tracked allowlist, which must say who runs it instead.
#
# REACHABILITY, NOT MERE PRESENCE. Searching the whole task file would accept a
# guard wired into a task nothing depends on — which is precisely the state
# being guarded against, so the guard would be vacuous in its own terms. The
# `check` aggregate's dependency closure is walked instead, and a run body's
# own `mise run <task>` feeds that closure as an edge.
#
# THE RUN BODY, NOT THE WHOLE TASK. A task's description is prose, not
# execution: a guard merely NAMED in one is not run by it. Reading the task
# graph structurally is what keeps those apart — an earlier revision of this
# script matched task text as a blob and accepted a script mentioned only in a
# description, which is the exact hole this file exists to close.
#
# THE GRAPH COMES FROM MISE, NOT FROM PARSING ITS FILE. `mise tasks --json`
# renders the task runner's own resolved view: quoting, multi-line arrays,
# aliases and wildcard expansion are its business, not this script's. A
# hand-rolled parser of someone else's file format drifts from it silently and
# is wrong in ways nobody can predict; this asks the owner instead.
#
# PARSE BOUNDARY, ENFORCED RATHER THAN DOCUMENTED. Only tasks defined in the
# repo's own mise.toml count. mise layers mise.local.toml and file tasks on
# top, and a machine-local task is not wiring any other checkout has, so a
# guard reachable only through one must not read as wired here. Tasks are
# filtered on their reported source.
#
# FAILS CLOSED on anything that would narrow the scan to nothing: no mise, no
# task graph, a graph with zero tasks, no `check` task, a closure of zero
# tasks, no workflows directory, or zero check-*.sh found. Each of those would
# otherwise make this script exit 0 having proven nothing.
#
# Usage: check-guard-wiring.sh [--repo-root <dir>]
# Exit codes: 0 every guard is reached; 1 one or more are not (or the allowlist
# is stale); 2 usage error; 5 fail-closed (an input that would make the scan
# vacuous).
#
# POSIX sh on the macOS + Linux support bar. All input is data.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=check-guard-wiring
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

repo_root=$(cd "$script_dir/.." && pwd) || exit 2
while [ "$#" -gt 0 ]; do
  case $1 in
    --repo-root)
      [ "$#" -ge 2 ] || {
        echo "$me: --repo-root needs a directory" >&2
        exit 2
      }
      repo_root=$2
      shift 2
      ;;
    -h | --help)
      echo "usage: check-guard-wiring.sh [--repo-root <dir>]" >&2
      exit 0
      ;;
    *)
      echo "$me: unknown argument" >&2
      exit 2
      ;;
  esac
done

repo_root=$(cd "$repo_root" 2>/dev/null && pwd) || {
  echo "$me: repo root is not a readable directory" >&2
  exit 5
}

misefile="$repo_root/mise.toml"
workflow_dir="$repo_root/.github/workflows"
allowfile="$repo_root/scripts/guard-wiring-allow.txt"

[ -r "$misefile" ] || {
  echo "$me: $misefile is missing or unreadable — the closure would prove nothing" >&2
  exit 5
}
[ -d "$workflow_dir" ] && [ -r "$workflow_dir" ] || {
  echo "$me: $workflow_dir is missing or unreadable — half the wiring surface would go unread" >&2
  exit 5
}

for tool in jq mise; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "$me: '$tool' is not on PATH — cannot read the task graph, refusing to guess" >&2
    exit 5
  }
done

# The task graph, as mise itself resolves it. MISE_TRUSTED_CONFIG_PATHS keeps a
# fixture checkout (and a fresh clone) from stopping on the trust prompt; this
# only ever LISTS tasks, never runs one.
graph=$(cd "$repo_root" && MISE_TRUSTED_CONFIG_PATHS="$repo_root" mise tasks --json 2>/dev/null) || graph=''
[ -n "$graph" ] || {
  echo "$me: 'mise tasks --json' produced nothing in $repo_root — failing closed rather than reporting a clean scan" >&2
  exit 5
}

# One jq pass: filter to this repo's own mise.toml, union the three edge kinds
# with the `mise run <task>` calls a run body makes, walk the closure from
# `check`, and emit the reached run bodies plus the diagnostics. A dangling
# edge (naming no task in this file) is reported, never silently dropped: an
# edge the walk cannot follow is exactly how a guard appears reachable without
# being reachable.
report=$(printf '%s' "$graph" | jq -r --arg src "$misefile" '
  [ .[] | select(.source == $src)
    | { name: .name,
        run: ((.run // []) | join("\n")),
        deps: ((.depends // []) + (.depends_post // []) + (.wait_for // [])) } ]
  | map(. + { deps: (.deps + ([ .run
        | match("mise[[:space:]]+run[[:space:]]+((?:-[^[:space:]]+[[:space:]]+)*)([A-Za-z0-9:_.*-]+)"; "g")
        | .captures[1].string ]))
    })                                                              as $tasks
  | ($tasks | map({key: .name, value: .}) | from_entries)           as $by
  | def grow($seen):
      ($seen + ($seen | map($by[.].deps // []) | add // []) | unique) as $next
      | if ($next | length) == ($seen | length) then $seen else grow($next) end;
    (if ($by | has("check")) then grow(["check"]) else null end)     as $reached
  | if $tasks == [] then "PARSE\tthe task graph holds no task from this repo mise.toml"
    elif $reached == null then "PARSE\tno `check` task in the graph, so there is no gate to walk"
    else
      ([ $reached[] | . as $n | select($by | has($n)) ]) as $known
      | if ($known | length) == 0 then "PARSE\tthe closure from check reached zero known tasks"
        else
          ( "COUNT\t\($known | length)" ),
          ( [ $reached[] | . as $n | select(($by | has($n)) | not) ] | unique | .[] | "DANGLING\t\(.)" ),
          ( [ $reached[] | select(test("\\*")) ] | unique | .[] | "WILDCARD\t\(.)" ),
          ( "BODIES" ),
          ( $known[] | $by[.].run )
        end
    end
') || {
  echo "$me: could not read the task graph — failing closed" >&2
  exit 5
}

case $report in
  PARSE*)
    echo "$me: ${report#PARSE?} — failing closed rather than reporting a clean scan" >&2
    exit 5
    ;;
esac

# Split the report at the BODIES marker. No sed \t anywhere: BSD sed reads \t
# as a literal `t`, so a tab-delimited pattern silently matches nothing on
# macOS and the haystack would lose every task body.
meta=$(printf '%s\n' "$report" | awk '/^BODIES$/ { exit } { print }')
bodies=$(printf '%s\n' "$report" | awk 'f { print } /^BODIES$/ { f = 1 }')

reached_count=$(printf '%s\n' "$meta" | awk -F'\t' '$1 == "COUNT" { print $2; exit }')
case ${reached_count:-0} in
  '' | *[!0-9]* | 0)
    echo "$me: the task-graph walk reported no reached tasks — failing closed" >&2
    exit 5
    ;;
esac

# The membership haystack: reached run bodies plus every workflow file. Both
# YAML spellings — GitHub accepts .yaml, so matching only .yml would report a
# genuinely wired guard as unwired.
haystack=$(
  printf '%s\n' "$bodies"
  find "$workflow_dir" -type f \( -name '*.yml' -o -name '*.yaml' \) -exec cat {} + 2>/dev/null
)
[ -n "$haystack" ] || {
  echo "$me: the wiring text came back empty — failing closed" >&2
  exit 5
}

guards=$(find "$repo_root/scripts" -maxdepth 1 -type f -name 'check-*.sh' 2>/dev/null | sort)
[ -n "$guards" ] || {
  echo "$me: found no scripts/check-*.sh at all — the scan would prove nothing" >&2
  exit 5
}

# The allowlist's first field. Leading whitespace is stripped BEFORE the field
# split, so an indented entry is read rather than silently blanked into
# nothing — a dropped exemption reads as an unwired guard and sends whoever
# hits it looking in the wrong place.
allowed=''
if [ -r "$allowfile" ]; then
  allowed=$(awk '{ sub(/#.*/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]].*$/, ""); if ($0 != "") print }' "$allowfile")
fi

rc=0
unwired=''
# Read the guard list a line at a time: a path containing a space would be
# split into fragments by a `for` over the unquoted list, and every fragment
# would then read as an unwired guard.
while IFS= read -r g; do
  [ -n "$g" ] || continue
  b=${g##*/}
  if printf '%s\n' "$haystack" | grep -qF -- "$b"; then
    case " $allowed " in
      *" $b "*)
        echo "$me: $b is in the allowlist but IS wired — remove the stale entry" >&2
        rc=1
        ;;
    esac
    continue
  fi
  case " $allowed " in
    *" $b "*) continue ;;
  esac
  unwired="$unwired $b"
  rc=1
done <<EOF
$guards
EOF

for a in $allowed; do
  [ -f "$repo_root/scripts/$a" ] || {
    echo "$me: the allowlist names '$a', which does not exist — remove the stale entry" >&2
    rc=1
  }
done

if [ -n "$unwired" ]; then
  for b in $unwired; do
    echo "$me: scripts/$b is run by no task in the \`check\` closure and by no workflow" >&2
  done
  echo "$me: a guard nothing runs cannot fail. Wire it into \`check\`, or add it to scripts/guard-wiring-allow.txt naming who runs it instead." >&2
fi

printf '%s\n' "$meta" | awk -F'\t' -v me="$me" '
  $1 == "DANGLING" { print me ": note: dependency on `" $2 "` names no task in this repo mise.toml — outside the parse boundary" > "/dev/stderr" }
  $1 == "WILDCARD" { print me ": note: wildcard dependency not expanded: " $2 > "/dev/stderr" }
'

if [ "$rc" = 0 ]; then
  echo "$me: ok, every scripts/check-*.sh is run ($reached_count tasks in the check closure)"
fi
exit $rc
