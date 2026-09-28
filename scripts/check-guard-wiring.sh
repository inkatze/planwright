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
# renders the task runner's own view of each task: TOML quoting and multi-line
# arrays are its business, not this script's. It does NOT resolve edges, so
# the walk does: a task alias resolves to its task, and a glob edge expands to
# every task name or alias it matches. A run body contributes the task each
# `mise run` / `mise r` call names (`default` when it names none), each `:::`
# segment included. A call whose leading flags keep the target or its
# dependencies from running (`--dry-run`, `--skip-deps`, ...) or run it from
# another directory's config (`--cd`) contributes nothing; a stop flag in a
# later `:::` segment drops that segment alone. Global flags placed before
# `run` (`mise -q run x`) are not read, so such a call contributes nothing.
#
# WHOLE-LINE COMMENTS ARE NOT EXECUTION. They are dropped from a run body
# before either edges or guard names are read from it, so a commented-out call
# wires nothing. Known limit: a guard or edge named in a live line that does
# not run it, such as an `echo` or a trailing `# ...` comment, still counts;
# telling those apart needs a shell parser.
#
# PARSE BOUNDARY, ENFORCED RATHER THAN DOCUMENTED. Only tasks defined in the
# repo's own mise.toml count. mise layers mise.local.toml and file tasks on
# top, and a machine-local task is not wiring any other checkout has, so a
# guard reachable only through one must not read as wired here. Tasks are
# filtered on their reported source.
#
# FAILS CLOSED on anything that would narrow the scan to nothing: no mise or
# jq, no mise.toml, no task graph, a graph with zero tasks, no `check` task, a
# walk that reports no reached tasks, no workflows directory, or zero
# check-*.sh found. Each of those would
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

# The task list, as mise itself renders it. MISE_TRUSTED_CONFIG_PATHS keeps a
# fixture checkout (and a fresh clone) from stopping on the trust prompt; this
# only ever LISTS tasks, never runs one.
graph=$(cd "$repo_root" && MISE_TRUSTED_CONFIG_PATHS="$repo_root" mise tasks --json --hidden 2>/dev/null) || graph=''
[ -n "$graph" ] || {
  echo "$me: 'mise tasks --json --hidden' produced nothing in $repo_root — failing closed rather than reporting a clean scan" >&2
  exit 5
}

# One jq pass: filter to this repo's own mise.toml, union `depends`,
# `depends_post`, structured `{ task = ... }` run entries, and the tasks a run
# body's `mise run` calls name, resolve each against names, aliases and globs,
# walk the closure from `check`, and emit the reached run bodies plus the
# diagnostics. `wait_for` is deliberately not an edge: it only orders a task
# that something else already scheduled and never causes its target to run,
# so following it would pass a guard nothing runs. A dangling edge (resolving
# to no task in this file) is reported, never silently dropped: an edge the
# walk cannot follow is exactly how a guard appears reachable without being
# reachable. Its newlines are escaped, so no task name can forge a report line.
report=$(printf '%s' "$graph" | jq -r --arg src "$misefile" '
  def uncommented: split("\n") | map(select(test("^[[:space:]]*#") | not)) | join("\n");
  # The task one `:::` segment names, given its words. A flag that stops the
  # target from running (or its dependencies, or runs it from another
  # directory) yields the stop mark, so no edge is claimed; a flag taking a
  # separate value skips that value too.
  def seg_task:
    if length == 0 then empty
    else .[0] as $w
      | if ($w | test("^--(dry-run|help|skip-deps|no-deps|cd)(=|$)|^-[A-Za-z]*[nhC][A-Za-z]*$")) then "\u0000stop"
        elif ($w | test("^--(jobs|output|shell|tool|timeout|allow-env|allow-net|allow-read|allow-write)$|^-[A-Za-z]*[jost]$")) then (.[2:] | seg_task)
        elif ($w | startswith("-")) then (.[1:] | seg_task)
        else $w | gsub("^[\"\u0027`]+|[\"\u0027`);]+$"; "")
        end
    end;
  # The first segment carries the flags of the call, so a stop there drops the
  # whole call; a first segment naming no task runs `default`.
  def run_edges:
    [ match("(?:^|[^A-Za-z0-9_-])mise[ \t]+(?:run|r)(?=[ \t;&|\n]|$)[ \t]*([^;&|\n]*)"; "g")
      | [ .captures[0].string | splits("[ \t]*:::[ \t]*")
          | [ splits("[ \t]+") | select(. != "") ] | [ seg_task ] ]
      | if .[0] == ["\u0000stop"] then empty
        else ((if .[0] == [] then ["default"] else .[0] end)[]),
             (.[1:][][] | select(. != "\u0000stop"))
        end ];
  # A depends entry carrying arguments or env names its task in `.task` or in
  # its first word.
  def edge_name:
    if type == "array" then .[0]
    elif type == "object" then (.task // tostring)
    elif type == "string" then (split(" ") | .[0])
    else tostring end;
  # mise task-name globs, as measured against mise itself: a trailing `*` (or
  # `**`) spans the `:` separator, an inner one and `?` do not, and `[...]`
  # classes and `{a,b}` alternation are honoured.
  def glob_re:
    split("") as $cs
    | reduce range(0; $cs | length) as $i ({re: "", br: 0, cls: false};
      $cs[$i] as $c
      | if .cls then
        (if $c == "]" then .cls = false else . end)
        | .re += (if $c == "!" and (.re | endswith("[")) then "^"
                  elif $c == "\\" then "\\\\" else $c end)
      elif $c == "*" then
        .re += (if $i > 0 and $cs[$i - 1] == "*" then ""
                elif ($cs[$i + 1:] | all(. == "*")) then ".*"
                else "[^:]*" end)
      elif $c == "?" then .re += "[^:]"
      elif $c == "[" then .cls = true | .re += "["
      elif $c == "{" then .br += 1 | .re += "(?:"
      elif $c == "}" and .br > 0 then .br -= 1 | .re += ")"
      elif $c == "," and .br > 0 then .re += "|"
      elif ($c | test("[.+^$()|{}\\]\\\\]")) then .re += "\\" + $c
      else .re += $c end)
    | "^" + .re + "$";
  [ .[] | select(.source == $src) ]                                 as $raw
  | [ $raw[].name ]                                                 as $names
  | ([ $raw[] | .name as $n | (.aliases // [])[] | {key: ., value: $n} ]
     | from_entries)                                                as $alias
  | def resolve:
      . as $e
      | if ($names | index([$e])) then [$e]
        elif ($alias | has($e)) then [$alias[$e]]
        elif test("[*?\\[{]") then (glob_re) as $re
          | [ ($names[] | select(test($re))),
              ($alias | to_entries[] | select(.key | test($re)) | .value) ] | unique
        else [] end;
    [ $raw[]
      | (.run // [])                                                as $run
      | ($run | map(select(type == "string")) | join("\n") | uncommented) as $body
      | ([ (.depends // [])[], (.depends_post // [])[],
           ($run[] | objects | (.task // empty), (.tasks // [])[]) ]
         | map(edge_name) + ($body | run_edges)
         | map(select(. != "") | gsub("\n"; "\\n")))                as $edges
      | { name: .name,
          body: $body,
          next: ([ $edges[] | resolve[] ] | unique),
          dangling: [ $edges[] | select((resolve | length) == 0) ] } ] as $tasks
  | ($tasks | map({key: .name, value: .}) | from_entries)           as $by
  | def grow($seen):
      ($seen + ($seen | map($by[.].next) | add // []) | unique) as $next
      | if ($next | length) == ($seen | length) then $seen else grow($next) end;
    (if ($by | has("check")) then grow(["check"]) else null end)     as $reached
  | if $tasks == [] then "PARSE\tthe task graph holds no task from this repo mise.toml"
    elif $reached == null then "PARSE\tno `check` task in the graph, so there is no gate to walk"
    else
      ( "COUNT\t\($reached | length)" ),
      ( [ $reached[] | $by[.].dangling[] ] | unique | .[] | "DANGLING\t\(.)" ),
      ( "BODIES" ),
      ( $reached[] | $by[.].body )
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

# The one membership test over that list. It is newline-separated and a
# basename may contain a space, so neither a space-delimited `case` pattern
# (which would match only the final entry) nor word-splitting is safe here;
# every reader of $allowed goes through this.
is_allowed() {
  [ -n "$allowed" ] || return 1
  printf '%s\n' "$allowed" | grep -qxF -- "$1"
}

rc=0
unwired=''
# Read the guard list a line at a time: a path containing a space would be
# split into fragments by a `for` over the unquoted list, and every fragment
# would then read as an unwired guard.
while IFS= read -r g; do
  [ -n "$g" ] || continue
  b=${g##*/}
  if printf '%s\n' "$haystack" | grep -qF -- "$b"; then
    if is_allowed "$b"; then
      echo "$me: $b is in the allowlist but IS wired — remove the stale entry" >&2
      rc=1
    fi
    continue
  fi
  is_allowed "$b" && continue
  unwired="$unwired $b"
  rc=1
done <<EOF
$guards
EOF

while IFS= read -r a; do
  [ -n "$a" ] || continue
  [ -f "$repo_root/scripts/$a" ] || {
    echo "$me: the allowlist names '$a', which does not exist — remove the stale entry" >&2
    rc=1
  }
done <<EOF
$allowed
EOF

if [ -n "$unwired" ]; then
  for b in $unwired; do
    echo "$me: scripts/$b is run by no task in the \`check\` closure and by no workflow" >&2
  done
  echo "$me: a guard nothing runs cannot fail. Wire it into \`check\`, or add it to scripts/guard-wiring-allow.txt naming who runs it instead." >&2
fi

printf '%s\n' "$meta" | awk -F'\t' -v me="$me" '
  $1 == "DANGLING" { print me ": note: edge to `" $2 "` names or matches no task in this repo mise.toml — outside the parse boundary" > "/dev/stderr" }
'

if [ "$rc" = 0 ]; then
  echo "$me: ok, every scripts/check-*.sh is run ($reached_count tasks in the check closure)"
fi
exit $rc
