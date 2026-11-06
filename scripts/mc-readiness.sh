#!/usr/bin/env bash
# mc-readiness.sh — the readiness-check duty: walk the primary evidence at a
# pull request's current head against the program's gate conditions before a
# flip is offered or requested. A session's own report is never evidence.
#
# `mc-readiness.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-readiness
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh spec-parse.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/spec-parse.sh
. "$script_dir/spec-parse.sh" || exit 2

help_text() {
  cat <<'HELP'
mc-readiness.sh — the readiness-check duty: walk the primary evidence at a
pull request's current head against the program's gate conditions before a
flip is offered or requested. A session's own report is never evidence.

THE EVIDENCE file (collect writes it; a fixture may stand in) opens with
"# format: 1"; every other line is tab-separated, its first field the kind:
  head<TAB><sha>                      the pull request's current head
  repo<TAB><owner/name>
  label<TAB><name>                    one per label
  path<TAB><file><TAB><change>        one per changed path, with the
                                      forge's change type (RENAMED and
                                      COPIED name no source path)
  check<TAB><name><TAB><state>        one per individual check context,
                                      its latest run only (a re-run
                                      supersedes the runs before it);
                                      SUCCESS, NEUTRAL and SKIPPED pass
  thread<TAB><id><TAB>open|resolved   one per review thread
  finding<TAB><reviewer><TAB><id><TAB>answered|unanswered
                                      an automated reviewer's thread
  step<TAB><id><TAB><outcome><TAB><end head>
                                      a recorded cadence step
  cadence<TAB>audited<TAB><head>      the configured cadence was audited
                                      at the head (scripts/step-run.sh
                                      audit --through post-pr)
  cadence<TAB>gap<TAB><point><TAB><kind><TAB><detail>
                                      one per gap that audit printed
  cadence<TAB>unaudited<TAB><why>     the audit could not run
  scope<TAB>spec-only<TAB><head>      every changed path lies under the
                                      program's spec root
  signoff<TAB><bundle><TAB>signed|unsigned<TAB><detail>
                                      a touched spec bundle's kickoff
                                      sign-off at the head
  evidence<TAB><kind><TAB><ref><TAB><head><TAB><judgment>
                                      smoke, walk or screenshot evidence;
                                      judgment ok, error or missing
  guard<TAB><name><TAB>pass|fail<TAB><detail>
                                      a ready-flip guard's verdict
  truncated<TAB><what>                a forge list that came back at its
                                      cap of 100 (files, checks, labels,
                                      review threads), so it may have been
                                      cut
  bodyline<TAB><text>                 one per line of the pull request body
  report<TAB><text>                   a session's own claim: read, never
                                      counted
Unknown kinds are ignored.

THE WALK refuses, each failure one line:
  - no head: nothing at a head was collected, so a report alone never
    passes;
  - no individual check, or any check outside SUCCESS, NEUTRAL and
    SKIPPED, whatever the rollup says;
  - an open thread, an unanswered finding, a failed guard, a truncated
    read;
  - any screenshot whose judgment is not ok, or recorded at another head;
  - each required step (ready steps) with no passed or applied record
    ending on the head;
  - a cadence not audited at the head, and each gap the audit named: the
    configured cadence binds whatever the gate data names, except on a
    spec-only pull request (a spec-only scope at the head), which is held
    for its sign-off instead of the cadence and the required steps;
  - each touched spec bundle not signed off;
  - each required evidence kind (ready evidence) with no ok record at the
    head;
  - each required body text (ready body) absent from the body.
The conditions come from scripts/mc-gates.sh resolve, for the evidence's
repo, labels and paths.

Usage:
  mc-readiness.sh walk --evidence <file> (--program <p> | --conditions <file>)
      ready<TAB><head>, or not-ready<TAB><head|-> then
      fail<TAB><what><TAB><detail> per failure
  mc-readiness.sh collect --program <p> --repo <owner/name> --pr <n>
                          [--worktree <dir>] --out <file>
      write the evidence at the pull request's current head: one gh read
      for the head, labels, paths, check contexts and body, one GraphQL
      read for the first 100 review threads (a thread opened by a bot is a
      finding, answered once resolved or replied to by a person other than
      the pull request's author, with a login), the spec-only scope (every
      path a `.md` file under the program's spec root inside the
      repository whose origin is --repo, added, modified or deleted, never
      renamed or copied; a head that repository lacks is a spec-only scope
      with one unsigned `*` sign-off naming the fetch; then each touched
      bundle, a
      directory under the root not opening with `_`, is signed off when,
      read from that repository's objects at the head with no fetch, its
      requirements.md status is Ready, Active or Done and its
      kickoff-brief.md's latest anchor recomputes over the bundle; a pull
      request touching only `_` accumulators or files directly under the
      root has no bundle to sign off), the step
      records of --worktree (scripts/step-record.sh list) and the cadence
      audit there, --worktree defaulting to the one worktree of the
      program's repositories that has the pull request's branch checked
      out (neither read for a spec-only pull request), the recorded
      evidence for that head, and the ready-flip guard
      (scripts/ready-guard.sh, given the flip it would refuse) run from the
      program's first repository, then the head read once more, a head that
      moved meanwhile failing the guard; nothing is written to any
      repository
  mc-readiness.sh check --program <p> --repo <owner/name> --pr <n>
                        [--worktree <dir>]
      collect, then walk, printing the walk
  mc-readiness.sh record --program <p> --repo <owner/name> --pr <n>
                         --head <sha> --kind smoke|walk|screenshot
                         --ref <ref> --judgment ok|error|missing
      record evidence the session opened and judged, in the program home's
      kb/readiness-check/evidence.tsv ("# format: 1", then
      <owner/name><TAB><pr><TAB><head><TAB><kind><TAB><ref><TAB><judgment>);
      the latest record of a kind and ref at a head is the one collected
  mc-readiness.sh watch [--program <p>]
      the duty's watcher (also what a run with no arguments does under the
      runner): for each draft pull request in the code-state snapshot whose
      checks are green and whose threads are resolved, one readiness-due
      event per new head (announced again once a head clears and returns),
      printing
        announced<TAB>readiness-due<TAB><subject>
      the program from PLANWRIGHT_MC_PROGRAM when --program is absent;
      a program with no code-state snapshot, none taken yet, or one past
      twice its cadence (the most a budget rung stretches a refresh)
      raises nothing. Each event is emitted to the program's event store,
      subject <owner>:<name>:<n>, and a head counts as announced only once
      the store holds its event. A subject outside the event grammar (over 128
      characters, say) falls back to pr-<checksum>, the slug in the text.

Exit codes: 0 ready, or done; 1 a failed read, store or event; 2 usage; 3
the program is not configured; 4 not ready.

Portable bash 3.2 / BSD tooling; gh's built-in --jq does the JSON.
HELP
}

usage() {
  mc_usage_fail "usage: mc-readiness.sh walk|collect|check|record|watch ...; mc-readiness.sh --help for each verb"
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
if [ $# -eq 0 ] && [ -n "${PLANWRIGHT_MC_PROGRAM:-}" ]; then
  set -- watch
fi
[ $# -ge 1 ] || usage
verb=$1
shift
program=""
evidence=""
conditions=""
slug=""
pr=""
worktree=""
out=""
head=""
kind=""
ref=""
judgment=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --evidence | --conditions | --repo | --pr | --worktree | --out | --head | --kind | --ref | --judgment)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --evidence) evidence=$2 ;;
        --conditions) conditions=$2 ;;
        --repo) slug=$2 ;;
        --pr) pr=$2 ;;
        --worktree) worktree=$2 ;;
        --out) out=$2 ;;
        --head) head=$2 ;;
        --kind) kind=$2 ;;
        --ref) ref=$2 ;;
        --judgment) judgment=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

need_pr() {
  mc_valid_slug "$slug" || mc_usage_fail "--repo takes owner/name"
  mc_valid_uint "$pr" && [ "$pr" -gt 0 ] || mc_usage_fail "--pr takes a pull request number"
}

# operand <path>: the path as an awk file operand, never read as an
# assignment (awk takes a `name=value` operand for one).
operand() {
  case $1 in
    /*) printf '%s\n' "$1" ;;
    *) printf './%s\n' "$1" ;;
  esac
}

evidence_store() { # evidence_store <program>: the store's path, its directory created
  es_home=$(mc_program_home "$1") || exit 1
  es_dir="$es_home/kb/readiness-check"
  mkdir -p "$es_dir" || mc_fail "cannot create $es_dir"
  printf '%s\n' "$es_dir/evidence.tsv"
}

# walk <evidence> <conditions>: the verdict; returns 4 when not ready, 1
# when the walk itself fails.
walk() {
  walk_awk "$@"
  wk_rc=$?
  case $wk_rc in
    0 | 4) return "$wk_rc" ;;
  esac
  printf '%s\n' "$prog: the walk failed (awk exit $wk_rc)" >&2
  return 1
}
walk_awk() {
  awk -F '\t' '
function fail(what, detail) { fails[++nf] = "fail\t" what "\t" detail }
function pass_check(s) { return s == "SUCCESS" || s == "NEUTRAL" || s == "SKIPPED" }
FILENAME == ARGV[1] {
  if ($1 == "ready" && ($2 == "steps" || $2 == "evidence" || $2 == "body")) need[$2, ++nn[$2]] = $3
  next
}
FNR == 1 { if ($0 != "# format: 1") { badfmt = 1; exit } ; next }
$1 == "head" { head = $2 }
$1 == "check" { nc++; if (!pass_check($3)) fail("check", $2 " is " $3) }
$1 == "thread" && $3 != "resolved" { fail("thread", $2 " is open") }
$1 == "finding" && $4 != "answered" { fail("finding", $2 " " $3 " is unanswered") }
$1 == "guard" && $3 != "pass" { fail("guard", $2 ": " $4) }
$1 == "truncated" { fail("truncated", "the " $2 " read hit its cap; what lies past it is unread") }
$1 == "step" { steps[++ns] = $2 "\t" $3 "\t" $4 }
$1 == "cadence" && $2 == "audited" { audited = $3 }
$1 == "cadence" && $2 == "gap" {
  d = $5 " is " $4
  if ($4 == "incomplete") d = "no completion record"
  else if ($4 == "stale") d = "completed only at " substr($5, 1, 12)
  else if ($4 == "failed") { i = index($5, ":"); d = substr($5, 1, i - 1) " recorded " substr($5, i + 1) }
  cad[++ncad] = $3 ": " d
}
$1 == "cadence" && $2 == "unaudited" { cad[++ncad] = "not audited: " $3; unaud = 1 }
$1 == "scope" && $2 == "spec-only" { speconly_head = $3 }
$1 == "signoff" && $3 != "signed" { fail("signoff", $2 ": " ($4 == "" ? "not signed off" : $4)) }
$1 == "evidence" { ev[++ne] = $2 "\t" $3 "\t" $4 "\t" $5 }
$1 == "bodyline" { body = body substr($0, 10) "\n" }
END {
  if (badfmt) { print "not-ready\t-"; print "fail\tformat\tthe evidence file lacks \"# format: 1\""; exit 4 }
  if (head == "") { print "not-ready\t-"; print "fail\thead\tno evidence at a head was collected; a session report alone never passes"; exit 4 }
  if (!nc) fail("check", "no individual check context at the head")
  speconly = (speconly_head == head)
  if (!speconly) {
    for (i = 1; i <= ncad; i++) fail("cadence", cad[i])
    if (!unaud && audited != head) fail("cadence", "the configured cadence was not audited at " substr(head, 1, 12))
  }
  for (i = 1; i <= ne; i++) {
    split(ev[i], e, "\t")
    if (e[1] == "screenshot" && e[4] != "ok") fail("screenshot", e[2] " judged " (e[4] == "" ? "missing" : e[4]))
    else if (e[1] == "screenshot" && e[3] != head) fail("screenshot", e[2] " was judged at another head")
  }
  if (!speconly) for (i = 1; i <= nn["steps"]; i++) {
    s = need["steps", i]; got = 0
    for (j = 1; j <= ns; j++) { split(steps[j], t, "\t"); if (t[1] == s && (t[2] == "passed" || t[2] == "applied") && t[3] == head) got = 1 }
    if (!got) fail("step", s " is not recorded passed or applied at " substr(head, 1, 12))
  }
  for (i = 1; i <= nn["evidence"]; i++) {
    k = need["evidence", i]; got = 0
    for (j = 1; j <= ne; j++) { split(ev[j], e, "\t"); if (e[1] == k && e[3] == head && e[4] == "ok") got = 1 }
    if (!got) fail("evidence", k " is not recorded ok at " substr(head, 1, 12))
  }
  for (i = 1; i <= nn["body"]; i++) if (!index(body, need["body", i])) fail("body", "the body lacks \"" need["body", i] "\"")
  if (nf) {
    print "not-ready\t" head
    for (i = 1; i <= nf; i++) print fails[i]
    exit 4
  }
  print "ready\t" head
}' "$(operand "$2")" "$(operand "$1")"
}

# conditions_for <program> <evidence> <out>: the gate conditions for the
# evidence's repo, labels and paths.
conditions_for() {
  cf_args=()
  cf_ev=$(operand "$2")
  cf_repo=$(awk -F '\t' '$1 == "repo" { print $2; exit }' "$cf_ev")
  [ -z "$cf_repo" ] || cf_args+=(--repo "$cf_repo")
  while IFS='	' read -r cf_k cf_v; do
    case $cf_k in
      label) cf_args+=(--label "$cf_v") ;;
      path) cf_args+=(--path "$cf_v") ;;
    esac
  done <<EOF
$(awk -F '\t' '($1 == "label" || $1 == "path") && NF >= 2 { print $1 "\t" $2 }' "$cf_ev")
EOF
  /bin/bash "$script_dir/mc-gates.sh" resolve --program "$1" ${cf_args[@]+"${cf_args[@]}"} >"$3"
}

# slug_repos <program> <slug>: the program's repositories whose origin remote
# is <slug>, one per line; returns 1 when the repositories do not resolve.
slug_repos() {
  local repos r url sl
  repos=$(/bin/bash "$script_dir/mc-program.sh" get "$1" repositories) || return 1
  sl=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r r; do
    [ -n "$r" ] && [ -d "$r" ] || continue
    url=$(mc_untrusted_git -C "$r" remote get-url origin 2>/dev/null | tr '[:upper:]' '[:lower:]') || continue
    url=${url%.git}
    case $url in */"$sl" | *:"$sl") printf '%s\n' "$r" ;; esac
  done <<<"$repos"
}

# branch_worktree <program> <slug> <branch> <head>: find the worktree of the
# program's repository for <slug> (its origin remote) that has <branch>
# checked out and holds <head>, printing `one<TAB><path>`, `none`, `several`
# or `unreadable`. Paths are read NUL-separated, since a path may carry a
# newline.
branch_worktree() {
  local repos r w br pr f n=0 hit='' seen=$'\n'
  [ -n "$3" ] || {
    printf 'none\n'
    return 0
  }
  repos=$(slug_repos "$1" "$2") || {
    printf 'unreadable\n'
    return 0
  }
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    w='' br='' pr=0
    while IFS= read -r -d '' f; do
      case $f in
        'worktree '*) w=${f#worktree } br='' pr=0 ;;
        'branch '*) br=${f#branch } ;;
        prunable | 'prunable '*) pr=1 ;;
        '')
          if [ -n "$w" ] && [ "$br" = "refs/heads/$3" ] && [ "$pr" = 0 ] && [ -d "$w" ] \
            && [ "$(mc_untrusted_git -C "$w" symbolic-ref -q HEAD 2>/dev/null)" = "refs/heads/$3" ] \
            && [ "$(mc_untrusted_git -C "$w" rev-parse --show-toplevel 2>/dev/null)" = "$w" ] \
            && mc_untrusted_git -C "$w" cat-file -e "$4^{commit}" 2>/dev/null; then
            # A repository listed twice, or with a listed worktree, names the same path again.
            case $seen in *$'\n'"$w"$'\n'*) ;; *) n=$((n + 1)) hit=$w seen="$seen$w"$'\n' ;; esac
          fi
          w=''
          ;;
      esac
    done < <(mc_untrusted_git -C "$r" worktree list --porcelain -z 2>/dev/null)
  done <<<"$repos"
  case $n in
    0) printf 'none\n' ;;
    1) printf 'one\t%s\n' "$hit" ;;
    *) printf 'several\n' ;;
  esac
}

# The forge reads cap a list at 100; a list that comes back full may have
# been cut, and the walk refuses on a `truncated` line rather than pass.
CAP=100

# spec_scope <program> <slug> <head> <pr read> <scratch dir>: when every
# changed path lies under the program's spec root inside the repository for
# <slug>, print `scope<TAB>spec-only<TAB><head>` and one `signoff` line per
# bundle touched; otherwise nothing. Sign-offs are read from the repository's
# own objects at the head, since collect writes nothing (no fetch) to any
# repository.
spec_scope() {
  local root r top rel='' repo='' files b why
  files=$(awk -F '\t' '$1 == "count" && $2 == "files" { print $3 + 0; exit }' "$4")
  [ "${files:-0}" -gt 0 ] && [ "$files" -lt "$CAP" ] || return 0
  root=$(/bin/bash "$script_dir/mc-program.sh" get "$1" spec_root 2>/dev/null) || return 0
  # Logical paths, so a symbolic link in a checkout cannot move the root; the
  # head must then hold the root as a directory.
  root=$(cd -L "$root" 2>/dev/null && pwd -L) || return 0
  while IFS= read -r r; do
    top=$(cd -L "$r" 2>/dev/null && pwd -L) || continue
    case $root in
      "$top"/?*)
        rel=${root#"$top"/} repo=$r
        break
        ;;
    esac
  done < <(slug_repos "$1" "$2" 2>/dev/null)
  [ -n "$rel" ] || return 0
  # Each path must sit strictly under the root, with no `.`, `..` or empty
  # component, be prose (`.md`), and be added, modified or deleted: a rename
  # or copy names no source path. The bundles are the directories directly
  # under the root, those opening with `_` (the reserved accumulators) aside.
  SPEC_REL=$rel awk -F '\t' '
    $1 != "path" { next }
    {
      if ($3 != "ADDED" && $3 != "MODIFIED" && $3 != "DELETED") { out = 1; exit }
      p = $2; n = length(ENVIRON["SPEC_REL"])
      if (substr(p, 1, n + 1) != ENVIRON["SPEC_REL"] "/" || p !~ /\.md$/) { out = 1; exit }
      p = substr(p, n + 2)
      if (p == "" || ("/" p "/") ~ /\/(\.|\.\.)?\//) { out = 1; exit }
      if (index(p, "/") && substr(p, 1, 1) != "_") { b = substr(p, 1, index(p, "/") - 1); if (!(b in seen)) { seen[b] = 1; bs[++nb] = b } }
    }
    END { if (out) exit 1; for (i = 1; i <= nb; i++) print bs[i] }' "$4" >"$5/bundles" || return 0
  if ! mc_untrusted_git -C "$repo" cat-file -e "$3^{commit}" 2>/dev/null; then
    printf 'scope\tspec-only\t%s\nsignoff\t*\tunsigned\tthe head is not in %s; fetch it\n' "$3" "$(sanitize_printable "$repo")"
    return 0
  fi
  [ "$(mc_untrusted_git -C "$repo" cat-file -t "$3:$rel" 2>/dev/null)" = tree ] || return 0
  printf 'scope\tspec-only\t%s\n' "$3"
  while IFS= read -r b; do
    why=$(bundle_signoff "$repo" "$3" "$rel" "$b" "$5/bundle-$b") || exit
    if [ -n "$why" ]; then
      printf 'signoff\t%s\tunsigned\t%s\n' "$b" "$why"
    else
      printf 'signoff\t%s\tsigned\t-\n' "$b"
    fi
  done <"$5/bundles"
}

# bundle_signoff <repo> <head> <root rel> <bundle> <scratch dir>: print why
# <bundle> is not signed off at <head>, read from <repo>'s objects, or
# nothing when it is.
bundle_signoff() {
  local repo=$1 head=$2 rel=$3 b=$4 d=$5 st f entry rc got gd
  if ! [[ $b =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    printf 'not a spec identifier'
    return 0
  fi
  mkdir -p "$d" || mc_fail "cannot create a scratch directory"
  # cat-file blob refuses a tree or a missing path, so a partial file is removed.
  mc_untrusted_git -C "$repo" cat-file blob "$head:$rel/$b/requirements.md" >"$d/requirements.md" 2>/dev/null || rm -f "$d/requirements.md"
  if ! st=$(spec_parse_header_value "$d/requirements.md" Status 2>/dev/null) || [ -z "$st" ]; then
    printf 'its requirements.md status cannot be read at the head'
    return 0
  fi
  case $st in
    Ready | Active | Done) ;;
    *)
      printf 'its status at the head is %s' "$(sanitize_printable "$st")"
      return 0
      ;;
  esac
  for f in design.md tasks.md test-spec.md kickoff-brief.md; do
    mc_untrusted_git -C "$repo" cat-file blob "$head:$rel/$b/$f" >"$d/$f" 2>/dev/null || rm -f "$d/$f"
  done
  if ! [ -f "$d/kickoff-brief.md" ]; then
    printf 'it has no kickoff brief at the head'
    return 0
  fi
  # The sign-off stands only for the content it anchored: the brief's latest
  # anchor must recompute, by the sanctioned form it records, over the bundle
  # at the head, hashed in the bundle's own repository.
  rc=0
  entry=$(spec_parse_latest_anchor_entry "$d/kickoff-brief.md" 2>/dev/null) || rc=$?
  if [ "$rc" = 2 ]; then
    printf "its kickoff brief's latest anchor entry does not parse"
    return 0
  fi
  [ "$rc" = 0 ] || entry=''
  if [ -z "$entry" ]; then
    printf 'its kickoff brief records no anchor'
    return 0
  fi
  got=''
  case ${entry#*	} in
    "scripts/spec-anchor.sh $rel/$b")
      got=$(cd "$repo" && mc_untrusted_git_env && /bin/sh "$script_dir/spec-anchor.sh" "$d" 2>/dev/null) || got=''
      ;;
    'git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin')
      gd=$(mc_untrusted_git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null) || gd=''
      [ -z "$gd" ] || got=$(cd "$d" && mc_untrusted_git_env && export GIT_DIR="$gd" \
        && git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin) 2>/dev/null || got=''
      ;;
    *)
      printf "its kickoff brief's anchor uses a form this check does not recompute"
      return 0
      ;;
  esac
  if [ -z "$got" ]; then
    printf 'its anchor cannot be recomputed at the head'
  elif [ "${entry%%	*}" != "$got" ]; then
    printf 'its content at the head is not what the kickoff signed off (the anchor differs)'
  fi
}

# collect <program> <slug> <pr> <worktree> <out>
collect() {
  cl_tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-readiness.XXXXXX") || mc_fail "cannot create a scratch directory"
  trap 'rm -rf "$cl_tmp"' EXIT
  cl_owner=${2%%/*}
  cl_name=${2#*/}
  cl_runs=$(cat -- "$script_dir/check-runs.jq") || mc_fail "check-runs.jq is missing or unreadable (broken install)"
  # shellcheck disable=SC2016 # a jq program
  gh pr view "$3" --repo "$2" --json headRefOid,headRefName,baseRefName,labels,files,body,statusCheckRollup --jq "$cl_runs"'
    def clean: tostring | gsub("[\t\r\n]"; " ");
    "head\t" + .headRefOid,
    "branch\t" + ((.headRefName // "") | clean),
    "base\t" + ((.baseRefName // "") | clean),
    "count\tfiles\t" + ((.files // []) | length | tostring),
    "count\tchecks\t" + ((.statusCheckRollup // []) | length | tostring),
    "count\tlabels\t" + ((.labels // []) | length | tostring),
    (.labels[]? | "label\t" + (.name | clean)),
    (.files[]? | "path\t" + (.path | clean) + "\t" + ((.changeType // "-") | clean)),
    ((.statusCheckRollup // []) | latest_check_runs[]
      | "check\t" + ((.name // .context // "-") | clean) + "\t"
      + (if (.conclusion // "") != "" then .conclusion else (.state // "PENDING") end | clean)),
    ((.body // "") | split("\n")[] | "bodyline\t" + (gsub("[\t\r]"; " ")))' >"$cl_tmp/pr" 2>"$cl_tmp/err" \
    || mc_fail "the pull request read failed: $(sanitize_printable "$(head -c 300 "$cl_tmp/err")")"
  cl_head=$(awk -F '\t' '$1 == "head" { print $2; exit }' "$cl_tmp/pr")
  mc_valid_sha "$cl_head" || mc_fail "the pull request read returned no head"
  # A finding is answered once its thread is resolved, or a person other
  # than the pull request's author replied: the author's sessions post as
  # the author, and their own word is never evidence.
  # shellcheck disable=SC2016 # a GraphQL query and a jq program
  gh api graphql -f owner="$cl_owner" -f name="$cl_name" -F number="$3" -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        author { login }
        reviewThreads(first: 100) { pageInfo { hasNextPage } nodes { id isResolved
          comments(first: 50) { nodes { author { __typename login } } } } } } } }' --jq '
    def bot: ((.author.__typename // "") == "Bot") or ((.author.login // "") | endswith("[bot]"));
    .data.repository.pullRequest as $p | ($p.author.login // "") as $me
    | (if $p.reviewThreads.pageInfo.hasNextPage then "truncated\treview threads" else empty end),
      ($p.reviewThreads.nodes[] | . as $t
      | "thread\t" + $t.id + "\t" + (if $t.isResolved then "resolved" else "open" end),
        (if ($t.comments.nodes[0] // {} | bot) then
          "finding\t" + ($t.comments.nodes[0].author.login // "-") + "\t" + $t.id + "\t"
          + (if $t.isResolved or ([$t.comments.nodes[1:][] | select((bot | not) and ((.author.login // "") != "") and ((.author.login // "") != $me))] | length > 0)
             then "answered" else "unanswered" end)
         else empty end))' >"$cl_tmp/threads" 2>"$cl_tmp/err" \
    || mc_fail "the review thread read failed: $(sanitize_printable "$(head -c 300 "$cl_tmp/err")")"
  : >"$cl_tmp/steps"
  cl_wt=$4
  cl_branch=$(awk -F '\t' '$1 == "branch" { print $2; exit }' "$cl_tmp/pr")
  cl_baseref=$(awk -F '\t' '$1 == "base" { print $2; exit }' "$cl_tmp/pr")
  cl_unaud=''
  : >"$cl_tmp/cadence"
  spec_scope "$1" "$2" "$cl_head" "$cl_tmp/pr" "$cl_tmp" >"$cl_tmp/scope"
  if [ -s "$cl_tmp/scope" ]; then
    # A spec-only pull request is held for its sign-off, not the cadence, so
    # no worktree is needed and none is audited.
    cl_wt=''
  elif [ -z "$cl_wt" ]; then
    cl_found=$(branch_worktree "$1" "$2" "$cl_branch" "$cl_head")
    case $cl_found in
      one"	"*) cl_wt=${cl_found#*	} ;;
      several) cl_unaud="several worktrees of $2 have branch ${cl_branch:--} checked out; pass --worktree" ;;
      unreadable) cl_unaud="the repositories of program $1 do not resolve" ;;
      *) cl_unaud="no worktree of $2 has branch ${cl_branch:--} checked out in a repository holding the head; pass --worktree" ;;
    esac
  fi
  if [ -n "$cl_wt" ]; then
    # Records speak for the worktree's own head, so it must be the forge's.
    cl_wthead=$(mc_untrusted_git -C "$cl_wt" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null) || cl_wthead=''
    if [ "$cl_wthead" != "$cl_head" ]; then
      cl_unaud="the worktree $(sanitize_printable "$cl_wt") is at ${cl_wthead:-no commit}, not the pull request's head $cl_head"
      cl_wt=''
    fi
  fi
  if [ -n "$cl_wt" ]; then
    # The audit resolves the cadence as the worktree's own session would; a
    # merge after the last point counts only when the base already holds it.
    # A base the worktree does not hold would let any clean merge pass.
    cl_base=()
    if [ -n "$cl_baseref" ]; then
      if mc_untrusted_git -C "$cl_wt" rev-parse --verify -q "refs/remotes/origin/$cl_baseref^{commit}" >/dev/null 2>&1; then
        cl_base=(--base "refs/remotes/origin/$cl_baseref")
      else
        cl_unaud="the worktree $(sanitize_printable "$cl_wt") does not hold the base origin/$cl_baseref; fetch it"
        cl_wt=''
      fi
    fi
  fi
  if [ -n "$cl_wt" ]; then
    (mc_untrusted_git_env && unset PLANWRIGHT_REPO_ROOT PLANWRIGHT_REPO_ROOT_CHECKED \
      && /bin/bash "$script_dir/step-run.sh" --worktree "$cl_wt" audit --through post-pr --head "$cl_head" ${cl_base[@]+"${cl_base[@]}"}) \
      >"$cl_tmp/audit" 2>"$cl_tmp/err"
    case $? in
      0 | 1) awk -F '\t' -v H="$cl_head" '
          $1 == "gap" { print "cadence\tgap\t" $2 "\t" $3 "\t" $4 }
          $1 == "audit" && $3 == H { print "cadence\taudited\t" H }' "$cl_tmp/audit" >"$cl_tmp/cadence" ;;
      *)
        cl_err=$(grep '^step-run: ' "$cl_tmp/err" | tail -n 1)
        [ -n "$cl_err" ] || cl_err=$(tail -n 1 "$cl_tmp/err")
        cl_unaud="the audit in $(sanitize_printable "$cl_wt") failed: $(sanitize_printable "$(printf '%s' "$cl_err" | head -c 200)")"
        ;;
    esac
  fi
  [ -z "$cl_unaud" ] || printf 'cadence\tunaudited\t%s\n' "$cl_unaud" >"$cl_tmp/cadence"
  if [ -n "$cl_wt" ]; then
    # The worktree is a worker's, so its git configuration runs nothing here.
    if ! (mc_untrusted_git_env && /bin/bash "$script_dir/step-record.sh" --worktree "$cl_wt" list) >"$cl_tmp/records" 2>"$cl_tmp/err"; then
      [ -z "$4" ] || mc_fail "the step records of $(sanitize_printable "$cl_wt") cannot be read"
      # A discovered worktree that cannot be read is a gap, never a crash.
      : >"$cl_tmp/records"
      printf 'cadence\tunaudited\tthe step records of %s cannot be read\n' "$(sanitize_printable "$cl_wt")" >"$cl_tmp/cadence"
    fi
    awk -F '\t' '
      $1 == "record" { t = s = o = h = "" }
      $1 == "type" { t = $2 } $1 == "step" { s = $2 } $1 == "outcome" { o = $2 } $1 == "end-head" { h = $2 }
      /^$/ { if (t == "step" && s != "") print "step\t" s "\t" o "\t" h; t = "" }
      END { if (t == "step" && s != "") print "step\t" s "\t" o "\t" h }' "$cl_tmp/records" >"$cl_tmp/steps" \
      || mc_fail "the step records cannot be parsed"
  fi
  cl_store=$(evidence_store "$1") || exit 1
  : >"$cl_tmp/evidence"
  if [ -f "$cl_store" ]; then
    mc_store_ok "$cl_store" || mc_fail "the evidence store has a missing or unknown format: $cl_store"
    # The latest record of each piece of evidence at the head stands, so a
    # judgment corrected at the same head replaces the earlier one.
    R=$2 P=$3 H=$cl_head awk -F '\t' '
      NR > 1 && $1 == ENVIRON["R"] && $2 == ENVIRON["P"] && $3 == ENVIRON["H"] {
        k = $4 "\t" $5; if (!(k in j)) o[++n] = k; j[k] = $6
      }
      END { for (i = 1; i <= n; i++) { split(o[i], f, "\t"); print "evidence\t" f[1] "\t" f[2] "\t" ENVIRON["H"] "\t" j[o[i]] } }' \
      "$cl_store" >"$cl_tmp/evidence" || mc_fail "the evidence store cannot be read: $cl_store"
  fi
  cl_repos=$(/bin/bash "$script_dir/mc-program.sh" get "$1" repositories) || mc_fail "the repositories of program $1 do not resolve"
  cl_first=$(printf '%s\n' "$cl_repos" | head -n 1)
  [ -n "$cl_first" ] && [ -d "$cl_first" ] || mc_fail "the program's first repository is not a directory here"
  printf '{"tool_name":"Bash","tool_input":{"command":"gh pr ready %s --repo %s"}}' "$3" "$2" >"$cl_tmp/payload"
  if cl_verdict=$(cd "$cl_first" && /bin/bash "$script_dir/ready-guard.sh" <"$cl_tmp/payload" 2>/dev/null); then
    case $cl_verdict in
      *'"permissionDecision":"deny"'*)
        cl_why=$(printf '%s' "$cl_verdict" | sed -n 's/.*"permissionDecisionReason":"\([^"]*\)".*/\1/p' | head -c 200)
        cl_guard="guard	ready-guard	fail	${cl_why:-denied}"
        ;;
      *) cl_guard="guard	ready-guard	pass	-" ;;
    esac
  else
    cl_guard="guard	ready-guard	fail	the guard did not run"
  fi
  # The guard read the pull request after the evidence did; a head that moved
  # in between leaves evidence for a head no longer current.
  cl_now=$(gh pr view "$3" --repo "$2" --json headRefOid --jq .headRefOid 2>/dev/null) || cl_now=""
  if [ -z "$cl_now" ]; then
    cl_guard="guard	head	fail	the head could not be re-read after the guard"
  elif [ "$cl_now" != "$cl_head" ]; then
    cl_guard="guard	head	fail	the head moved to $cl_now while the evidence was collected"
  fi
  {
    printf '# format: 1\nrepo\t%s\n' "$2"
    awk -F '\t' -v cap="$CAP" '$1 == "count" { if ($3 + 0 >= cap) print "truncated\t" $2; next } $1 == "branch" || $1 == "base" { next } { print }' "$cl_tmp/pr"
    cat "$cl_tmp/threads" "$cl_tmp/steps" "$cl_tmp/cadence" "$cl_tmp/scope" "$cl_tmp/evidence"
    printf '%s\n' "$cl_guard"
  } | mc_clean_text | mc_write "$5" || mc_fail "cannot write $(sanitize_printable "$5")"
}

case $verb in
  walk)
    [ -n "$evidence" ] || usage
    [ -r "$evidence" ] || mc_fail "the evidence file is unreadable: $(sanitize_printable "$evidence")"
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/mc-readiness.XXXXXX") || mc_fail "cannot create a scratch directory"
    trap 'rm -rf "$scratch"' EXIT
    if [ -n "$program" ]; then
      [ -z "$conditions" ] || usage
      mc_require_program "$program"
      conditions_for "$program" "$evidence" "$scratch/conditions" || exit 1
      conditions=$scratch/conditions
    fi
    [ -n "$conditions" ] && [ -r "$conditions" ] || usage
    walk "$evidence" "$conditions"
    ;;
  collect | check)
    [ -n "$program" ] || usage
    need_pr
    mc_require_program "$program"
    [ -z "$worktree" ] || [ -d "$worktree" ] || mc_fail "no worktree at $(sanitize_printable "$worktree")"
    command -v gh >/dev/null 2>&1 || mc_fail "gh is not on PATH"
    if [ "$verb" = collect ]; then
      [ -n "$out" ] || usage
      collect "$program" "$slug" "$pr" "$worktree" "$out"
      exit 0
    fi
    [ -z "$out" ] || usage
    work=$(mktemp -d "${TMPDIR:-/tmp}/mc-readiness.XXXXXX") || mc_fail "cannot create a scratch directory"
    (collect "$program" "$slug" "$pr" "$worktree" "$work/evidence") || {
      rm -rf "$work"
      exit 1
    }
    rc=0
    conditions_for "$program" "$work/evidence" "$work/conditions" || rc=1
    [ "$rc" -ne 0 ] || {
      walk "$work/evidence" "$work/conditions"
      rc=$?
    }
    rm -rf "$work"
    exit "$rc"
    ;;
  record)
    [ -n "$program" ] || usage
    need_pr
    mc_valid_sha "$head" || mc_usage_fail "--head takes a full 40-hex sha"
    case $kind in smoke | walk | screenshot) ;; *) mc_usage_fail "--kind takes smoke, walk or screenshot" ;; esac
    case $judgment in ok | error | missing) ;; *) mc_usage_fail "--judgment takes ok, error or missing" ;; esac
    [ -n "$ref" ] || mc_usage_fail "--ref takes the evidence's path or link"
    mc_require_program "$program"
    store=$(evidence_store "$program") || exit 1
    trap mc_kb_unlock EXIT
    mc_kb_lock "$program" readiness-check/evidence.tsv
    mc_store_init "$store"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$slug" "$pr" "$head" "$kind" "$ref" "$judgment" >>"$store" || mc_fail "cannot append to $store"
    printf 'recorded\t%s#%s\t%s\t%s\n' "$slug" "$pr" "$kind" "$judgment"
    ;;
  watch)
    [ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
    [ -n "$program" ] || usage
    mc_require_program "$program"
    sources=$(/bin/bash "$script_dir/mc-program.sh" get "$program" sources) || mc_fail "the source map of program $program does not resolve"
    source=$(printf '%s\n' "$sources" | awk -F '\t' '$1 == "code-state" && $3 == "snapshot" { print $2 }')
    # A program whose code state is not snapshotted has nothing to watch.
    [ -n "$source" ] || exit 0
    snap=$(/bin/bash "$script_dir/mc-snapshot.sh" read --program "$program" "$source")
    case $? in
      0) ;;
      3) exit 0 ;;
      *) mc_fail "the $source snapshot cannot be read" ;;
    esac
    # A snapshot past twice its cadence (the most any budget rung stretches
    # a refresh) may show a head long gone; wait for a fresh one.
    if ! printf '%s\n' "$snap" | head -n 1 | awk -F '\t' '$5 == "age" && $7 == "cadence" { ok = ($6 + 0 <= 2 * ($8 + 0)) } END { exit !ok }'; then
      exit 0
    fi
    runtime=$(mc_runtime "$program") || mc_fail "cannot resolve the runtime directory"
    seen="$runtime/readiness-announced"
    due=$(printf '%s\n' "$snap" | awk -F '\t' '$1 == "pr" && $5 == "true" && $8 == "0" && $9 == "SUCCESS" { print $2 "\t" $3 "\t" $4 }')
    rc=0
    live=""
    while IFS='	' read -r w_slug w_n w_head; do
      [ -n "$w_slug" ] || continue
      live="$live$w_slug#$w_n	$w_head
"
      w_subject="${w_slug%%/*}:${w_slug#*/}:$w_n"
      mc_valid_handle "$w_subject" || w_subject=$(mc_subject pr "$w_slug#$w_n")
      mc_announce "$program" "$seen" "$w_slug#$w_n	$w_head" readiness-due "$w_subject" \
        "$w_slug#$w_n head $(printf '%s' "$w_head" | cut -c1-12)" || rc=1
    done <<EOF
$due
EOF
    mc_announce_prune "$seen" "$live" || rc=1
    exit "$rc"
    ;;
  *) usage ;;
esac
