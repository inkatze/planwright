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
#   (a) inside the run body of a mise task REACHABLE from the `check`
#       aggregate, or
#   (b) inside a .github/workflows/*.yml file, or
#   (c) in the tracked allowlist, which must say who runs it instead.
#
# REACHABILITY, NOT MERE PRESENCE. Grepping the whole of mise.toml would accept
# a guard wired into a task that nothing depends on — which is precisely the
# state being guarded against, so the guard would be vacuous in its own terms.
# The `check` aggregate's `depends` closure is walked instead, and a run body's
# own `mise run <task>` feeds that closure as an edge.
#
# PARSE BOUNDARY. mise.toml only. Tasks defined in mise.local.toml or in file
# tasks are invisible here, and a `depends` entry naming one reads as a
# dangling edge. A dangling edge is REPORTED, never silently dropped: an edge
# this parse cannot follow is exactly how a guard would appear reachable
# without being reachable.
#
# FAILS CLOSED on anything that would narrow the scan to nothing: no mise.toml,
# a mise.toml parsing to zero tasks, no `check` task, a closure of zero tasks,
# no workflows directory, or zero check-*.sh scripts found. Each of those would
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

[ -d "$repo_root" ] || {
  echo "$me: repo root '$repo_root' is not a directory" >&2
  exit 5
}

misefile="$repo_root/mise.toml"
workflow_dir="$repo_root/.github/workflows"
allowfile="$repo_root/scripts/guard-wiring-allow.txt"

[ -r "$misefile" ] || {
  echo "$me: $misefile is missing or unreadable — the closure would prove nothing" >&2
  exit 5
}
[ -d "$workflow_dir" ] || {
  echo "$me: $workflow_dir is missing — half the wiring surface would go unread" >&2
  exit 5
}

# The reached wiring text: the run bodies of every mise task reachable from
# `check`, walked over depends/depends_post/wait_for and over `mise run <task>`
# appearing inside a reached body. Emitted as plain text for the membership
# scan below; diagnostics go to stderr and are surfaced verbatim.
reached=$(
  awk -v root=check '
    function bail(why) { parse_error = why; exit }
    # A task block runs from its header to the next top-level table header.
    /^\[/ {
      if ($0 ~ /^\[tasks\./) {
        name = $0
        sub(/^\[tasks\./, "", name)
        sub(/\]$/, "", name)
        gsub(/^"|"$/, "", name)
        if (name == "") bail("a [tasks.*] header with an empty name")
        cur = name
        seen[cur] = 1
        ntasks++
      } else {
        cur = ""
      }
      next
    }
    cur != "" { body[cur] = body[cur] "\n" $0 }
    END {
      if (parse_error != "") {
        print "PARSE\t" parse_error
        exit
      }
      if (ntasks == 0) {
        print "PARSE\tmise.toml parsed to zero tasks"
        exit
      }
      if (!(root in seen)) {
        print "PARSE\tno [tasks." root "] block, so there is no gate to walk"
        exit
      }
      # Breadth-first over the edges each reached body declares.
      queue[1] = root
      inq[root] = 1
      head = 1
      tail = 1
      while (head <= tail) {
        t = queue[head++]
        b = body[t]
        # depends / depends_post / wait_for operands, and run-body mise calls.
        # Both are quoted or bare task names; take every quoted token on a
        # depends-ish line and every operand of a `mise run`.
        n = split(b, lines, "\n")
        indep = 0
        for (i = 1; i <= n; i++) {
          l = lines[i]
          if (l ~ /^[[:space:]]*(depends|depends_post|wait_for)[[:space:]]*=/) indep = 1
          if (indep) {
            m = l
            while (match(m, /"[^"]+"/)) {
              tok = substr(m, RSTART + 1, RLENGTH - 2)
              m = substr(m, RSTART + RLENGTH)
              edge[t, ++nedge[t]] = tok
              if (tok ~ /\*/) { wild[tok] = 1; continue }
              if (!(tok in inq)) { inq[tok] = 1; queue[++tail] = tok }
              if (!(tok in seen)) dangling[tok] = dangling[tok] " " t
            }
            if (l ~ /\]/) indep = 0
          }
          if (l ~ /mise[[:space:]]+run[[:space:]]/) {
            m = l
            if (match(m, /mise[[:space:]]+run[[:space:]]+[A-Za-z0-9:_.-]+/)) {
              tok = substr(m, RSTART, RLENGTH)
              sub(/^mise[[:space:]]+run[[:space:]]+/, "", tok)
              if (tok !~ /\*/) {
                if (!(tok in inq)) { inq[tok] = 1; queue[++tail] = tok }
                if (!(tok in seen)) dangling[tok] = dangling[tok] " " t
              } else wild[tok] = 1
            }
          }
        }
      }
      nreached = 0
      for (t in inq) if (t in seen) nreached++
      if (nreached == 0) {
        print "PARSE\tthe closure from " root " reached zero known tasks"
        exit
      }
      for (t in dangling) print "DANGLING\t" t "\t" dangling[t]
      for (w in wild) print "WILDCARD\t" w
      print "COUNT\t" nreached
      for (t in inq) if (t in seen) print "BODY\t" t body[t]
    }
  ' "$misefile"
)

parse_err=$(printf '%s\n' "$reached" | sed -n 's/^PARSE\t//p')
if [ -n "$parse_err" ]; then
  echo "$me: $parse_err — failing closed rather than reporting a clean scan" >&2
  exit 5
fi

reached_count=$(printf '%s\n' "$reached" | sed -n 's/^COUNT\t//p')
case ${reached_count:-0} in
  '' | *[!0-9]* | 0)
    echo "$me: the task-graph walk reported no reached tasks — failing closed" >&2
    exit 5
    ;;
esac

# The membership haystack: reached run bodies plus every workflow file.
haystack=$(
  printf '%s\n' "$reached" | sed -n '/^BODY\t/,$p'
  find "$workflow_dir" -type f -name '*.yml' -exec cat {} + 2>/dev/null
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

allowed=''
if [ -r "$allowfile" ]; then
  allowed=$(sed -e 's/#.*//' -e 's/[[:space:]].*$//' "$allowfile" | grep -v '^$' || true)
fi

rc=0
unwired=''
for g in $guards; do
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
done

for a in $allowed; do
  [ -f "$repo_root/scripts/$a" ] || {
    echo "$me: the allowlist names '$a', which does not exist — remove the stale entry" >&2
    rc=1
  }
done

if [ -n "$unwired" ]; then
  for b in $unwired; do
    echo "$me: scripts/$b is reached by no task in the \`check\` closure and by no workflow" >&2
  done
  echo "$me: a guard nothing runs cannot fail. Wire it into \`check\`, or add it to scripts/guard-wiring-allow.txt naming who runs it instead." >&2
fi

printf '%s\n' "$reached" | sed -n 's/^DANGLING\t\([^\t]*\)\t\(.*\)/'"$me"': note: depends edge on \1 (from\2) names no task in mise.toml — outside the parse boundary/p' >&2
printf '%s\n' "$reached" | sed -n 's/^WILDCARD\t/'"$me"': note: wildcard edge not expanded: /p' >&2

if [ "$rc" = 0 ]; then
  echo "$me: ok, every scripts/check-*.sh is reached ($reached_count tasks in the check closure)"
fi
exit $rc
