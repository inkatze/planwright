#!/usr/bin/env bash
# mc-gates.sh — a mission-control program's gate conditions: ready-when and
# merge-recommendation conditions as data, per program, repository, label or
# path, checked at load against the human-gates floors.
#
# `mc-gates.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-gates
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
mc-gates.sh — a mission-control program's gate conditions: ready-when and
merge-recommendation conditions as data, per program, repository, label or
path, checked at load against the human-gates floors.

THE FILE is <home>/gates.tsv in the program home (scripts/mc-program.sh get
<p> home); absent, every condition takes its default. Its first line is
"# format: 1"; blank lines and lines opening with `#` are skipped; every
other line is five tab-separated fields:
  <gate> <scope> <match> <key> <value>
  gate    ready | merge
  scope   program (match `*`), repo (match a forge slug, owner/name),
          label (a label name) or path (a glob over changed paths, `*`
          crossing `/`); a slug or a label matches whatever its case, as
          the forge treats them
  ready keys, each row adding one member to a set:
    steps     a step id that must be recorded passed or applied at the head
    evidence  smoke, walk or screenshot: evidence that must be recorded,
              judged ok, at the head
    body      text the pull request body must carry
  ready key, a single value:
    flip      offer (mission control offers the flip to the operator,
              the default) or request (a session requests it itself,
              admitted only while ready_flip_policy is unit-owner)
  merge keys, a single value each; mission control only recommends:
    recommend ready (the default) or approved: when a merge is recommended
    order     graph (the default): the order the whole dependency graph
              gives (scripts/mc-radar.sh order)
    method    merge, squash or rebase: the one method to name
    conflicts operator (the default) or session: who resolves a conflict
A single value set at several scopes takes the most specific: path over
label over repo over program, and a later line over an earlier one at the
same scope. Sets take the union of every matching line.

THE FLOORS. No condition places a flip or a merge below the human-gates
floors: a merge key or value that would authorize or enable a merge (any
key other than the four above, or a value such as auto) is refused at
load, and so is `flip request` while ready_flip_policy is not unit-owner
(read through scripts/resolve-policy-knob.sh from the program's first
repository, or from the current directory under --file). Since no condition can authorize a merge, every merge_policy
bounds them.
A load with any refused line refuses the whole file; nothing is evaluated
from it.

Usage:
  mc-gates.sh check (--program <p> | --file <f>)
      load the file and report each refused line on stderr as
      <file>:<line>: <reason>
  mc-gates.sh resolve (--program <p> | --file <f>) [--repo <slug>]
                      [--label <l>]... [--path <p>]...
      the conditions in force for a pull request, one per line:
        <gate><TAB><key><TAB><value>
      sets first (one line per member), then flip, recommend, order,
      method (`-` when none is named) and conflicts

Exit codes: 0 loaded; 1 a refused line, an unknown format or an unreadable
file or policy; 2 usage; 3 the program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-gates.sh check (--program <p> | --file <f>) | resolve (--program <p> | --file <f>) [--repo <slug>] [--label <l>]... [--path <p>]..."
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
case $verb in
  check | resolve) ;;
  *) usage ;;
esac
program=""
file=""
repo=""
labels=""
paths=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --file | --repo | --label | --path)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --file) file=$2 ;;
        --repo) repo=$2 ;;
        --label) labels="$labels$2
" ;;
        --path) paths="$paths$2
" ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
if [ "$verb" = check ]; then
  [ -z "$repo$labels$paths" ] || usage
fi
if [ -n "$program" ]; then
  [ -z "$file" ] || usage
  mc_require_program "$program"
  home=$(mc_program_home "$program") || exit 1
  file="$home/gates.tsv"
  [ -e "$file" ] || file=""
else
  [ -n "$file" ] || usage
  [ -e "$file" ] || mc_fail "no gate-condition file at $(sanitize_printable "$file")"
fi

# The policy is read the way the flip helpers read it, from the program's
# first repository when a program is named, so its repo-tracked layer counts.
policy_dir=.
if [ -n "$program" ]; then
  policy_dir=$(/bin/bash "$script_dir/mc-program.sh" get "$program" repositories | head -n 1)
  [ -n "$policy_dir" ] && [ -d "$policy_dir" ] || mc_fail "the program's first repository is not a directory here"
fi
policy=$(cd "$policy_dir" && /bin/sh "$script_dir/resolve-policy-knob.sh" ready_flip_policy 2>/dev/null) || mc_fail "ready_flip_policy cannot be read"
[ -n "$policy" ] || mc_fail "ready_flip_policy cannot be read"

# The loader: every line checked, then the resolution for the pull request
# described by REPO, LABELS and PATHS (newline-separated). Refusals go to
# stderr and fail the load.
if [ -n "$file" ]; then
  [ -r "$file" ] || mc_fail "the gate-condition file is unreadable: $(sanitize_printable "$file")"
  # A relative operand of the form name=value would be an awk assignment.
  case $file in
    /*) src=$file ;;
    *) src=./$file ;;
  esac
else
  src=/dev/null
fi
FILE=${file:-none} POLICY=$policy REPO=$repo LABELS=$labels PATHS=$paths VERB=$verb awk -F '\t' '
function refuse(why) { printf "%s:%d: %s\n", ENVIRON["FILE"], NR, why > "/dev/stderr"; bad = 1 }
function glob(s, g,   r, i, c) {
  r = "^"
  for (i = 1; i <= length(g); i++) {
    c = substr(g, i, 1)
    if (c == "*") r = r ".*"
    else if (c == "?") r = r "."
    else if (c ~ /[][\\.^$+(){}|]/) r = r "\\" c
    else r = r c
  }
  return s ~ (r "$")
}
function inlist(v, list,   n, a, i) {
  n = split(list, a, "\n")
  for (i = 1; i <= n; i++) if (a[i] != "" && tolower(a[i]) == tolower(v)) return 1
  return 0
}
function anypath(g,   n, a, i) {
  n = split(ENVIRON["PATHS"], a, "\n")
  for (i = 1; i <= n; i++) if (a[i] != "" && glob(a[i], g)) return 1
  return 0
}
BEGIN {
  rank["program"] = 1; rank["repo"] = 2; rank["label"] = 3; rank["path"] = 4
  setk["steps"] = 1; setk["evidence"] = 1; setk["body"] = 1
  one["ready", "flip"] = "offer"
  one["merge", "recommend"] = "ready"; one["merge", "order"] = "graph"
  one["merge", "method"] = "-"; one["merge", "conflicts"] = "operator"
}
NR == 1 {
  if ($0 != "# format: 1") { refuse("unknown format (want \"# format: 1\" on the first line)"); exit }
  next
}
/^[ ]*$/ || /^#/ { next }
{
  if (NF != 5) { refuse("want five tab-separated fields, got " NF); next }
  g = $1; s = $2; m = $3; k = $4; v = $5
  if (g != "ready" && g != "merge") { refuse("unknown gate \"" g "\" (ready or merge)"); next }
  if (!(s in rank)) { refuse("unknown scope \"" s "\" (program, repo, label or path)"); next }
  if (s == "program" && m != "*") { refuse("a program line matches \"*\""); next }
  if (m == "") { refuse("an empty match"); next }
  if (v == "") { refuse("an empty value"); next }
  if (g == "merge") {
    if (!((g, k) in one)) { refuse("merge key \"" k "\" would authorize a merge; mission control only recommends (recommend, order, method, conflicts)"); next }
    if (k == "recommend" && v != "ready" && v != "approved") { refuse("merge recommend \"" v "\" would authorize a merge; want ready or approved"); next }
    if (k == "order" && v != "graph") { refuse("merge order \"" v "\": want graph"); next }
    if (k == "method" && v != "merge" && v != "squash" && v != "rebase") { refuse("merge method \"" v "\": want merge, squash or rebase"); next }
    if (k == "conflicts" && v != "operator" && v != "session") { refuse("merge conflicts \"" v "\": want operator or session"); next }
  } else if (k in setk) {
    if (k == "steps" && v !~ /^[a-z0-9][a-z0-9-]*$/) { refuse("ready steps \"" v "\": want a step id"); next }
    if (k == "evidence" && v != "smoke" && v != "walk" && v != "screenshot") { refuse("ready evidence \"" v "\": want smoke, walk or screenshot"); next }
  } else if (k == "flip") {
    if (v != "offer" && v != "request") { refuse("ready flip \"" v "\" would place a flip below ready_flip_policy (" ENVIRON["POLICY"] "); want offer or request"); next }
    if (v == "request" && ENVIRON["POLICY"] != "unit-owner") { refuse("ready flip request would place a flip below ready_flip_policy (" ENVIRON["POLICY"] ")"); next }
  } else { refuse("unknown ready key \"" k "\" (steps, evidence, body, flip)"); next }
  if (ENVIRON["VERB"] != "resolve") next
  hit = (s == "program") || (s == "repo" && ENVIRON["REPO"] != "" && tolower(m) == tolower(ENVIRON["REPO"])) || (s == "label" && inlist(m, ENVIRON["LABELS"])) || (s == "path" && anypath(m))
  if (!hit) next
  if (k in setk) {
    if (!((g, k, v) in seen)) { seen[g, k, v] = 1; order[++n] = g "\t" k "\t" v }
  } else if (!((g, k) in at) || rank[s] >= at[g, k]) { at[g, k] = rank[s]; one[g, k] = v }
}
END {
  if (NR == 0 && ENVIRON["FILE"] != "none") { printf "%s: empty, with no format line\n", ENVIRON["FILE"] > "/dev/stderr"; exit 1 }
  if (bad) exit 1
  if (ENVIRON["VERB"] != "resolve") exit 0
  for (i = 1; i <= n; i++) print order[i]
  print "ready\tflip\t" one["ready", "flip"]
  print "merge\trecommend\t" one["merge", "recommend"]
  print "merge\torder\t" one["merge", "order"]
  print "merge\tmethod\t" one["merge", "method"]
  print "merge\tconflicts\t" one["merge", "conflicts"]
}' "$src"
