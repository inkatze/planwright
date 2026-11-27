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

# The sign-off read enters the program's repository with its scratch paths in
# hand, so a TMPDIR relative to the caller's directory would point elsewhere.
case ${TMPDIR:-} in
  '' | /*) ;;
  *)
    if abs_tmp=$(cd -P -- "$TMPDIR" 2>/dev/null && pwd -P); then
      TMPDIR=$abs_tmp
      export TMPDIR
    fi
    ;;
esac
mc_usable_tmpdir

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
  path<TAB><file><TAB><change>[<TAB><source>]
                                      one per changed path, with the
                                      forge's change type; a RENAMED or
                                      COPIED path carries the path it came
                                      from when the forge's file list
                                      named one
  check<TAB><name><TAB><state>        one per individual check context,
                                      its latest run only (a re-run
                                      supersedes the runs before it), but
                                      not a check ready_base_state_checks
                                      names (it describes the base);
                                      SUCCESS, NEUTRAL and SKIPPED pass
  bypass<TAB><name><TAB><state>       a ready_base_state_checks check whose
                                      latest finished run did not pass: no
                                      condition, but named by a ready or
                                      request-review walk as the check
                                      the operator bypasses at merge
  require<TAB>macos                   the repository's CI has macOS jobs, which
                                      run only on a ready or ci-macos
                                      labelled pull request; both must be
                                      SUCCESS, a skip or absence is unmet
  require<TAB>pr-agent                the repository runs PR-Agent, the bot
                                      review: once per head, on the draft
                                      when a review is requested, and the
                                      ready flip waits for it
  state<TAB>draft|ready               whether the pull request is a draft
  flip<TAB><time>                     when the pull request was last marked
                                      ready (its ready_for_review event)
  born<TAB><name><TAB><time>          when the workflow run of a check was
                                      created, which a queued check cannot
                                      say itself
  botmark<TAB><login><TAB><run>.<attempt><TAB><head><TAB><status><TAB><time>
                                      one per PR-Agent run marker comment
                                      (`<!-- pr-agent-run: ... -->`) on the
                                      pull request: its author, the
                                      run attempt, the head it reviewed,
                                      its status and when it was last edited
  botattempt<TAB><run>.<attempt><TAB><workflow><TAB><started><TAB><conclusion>
                                      the run attempt behind a marker the
                                      workflow (github-actions[bot]) posted
                                      at the head
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
                                      (kind unaudited: a record the step-record
                                      truth check refuses; reads as not audited),
                                      except that a post-pr stale whose every
                                      post-pr completion lies outside the pull
                                      request's history (neither behind nor
                                      ahead of its head, or held by its base)
                                      is kind foreign, which collect derives
  cadence<TAB>covered<TAB><point>     one per point it found complete
  cadence<TAB>unaudited<TAB><why>     the audit could not run
  scope<TAB>spec-only<TAB><head>      every changed path lies under the
                                      program's spec root
  signoff<TAB><bundle><TAB>signed|unsigned<TAB><detail>
                                      an edited spec bundle's kickoff
                                      sign-off at the head; a signed row's
                                      detail is `-`, or `legacy, no kickoff
                                      brief` for a legacy bundle (collect)
  drift<TAB><path><TAB><spec>/<task>...
                                      a changed file a spec lists as a task
                                      deliverable that no spec edit, Not
                                      covered reason or task trailer covers
  drift<TAB>*<TAB><reason>            the spec-drift check could not run
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
  - no individual check (a check ready_base_state_checks names is left
    out of the evidence, so a pull request whose only check is that one
    has none), or any check outside SUCCESS, NEUTRAL and
    SKIPPED, whatever the rollup says;
  - where PR-Agent is required, a pull request with no PR-Agent run at its
    head. The review runs on the draft, fired by a review request once the
    other checks are green, and the flip waits for it, so a ready pull
    request can merge at once: a draft with none is told to request it
    (request-review, below), a ready one with none is refused. The run, like
    any check, must be green, and its findings answered; one still running
    holds the draft, and one still running at the flip is a too-early flip. A
    code change on a finding is a new head and needs one more run. A skipped
    run (the skip-pr-agent label, a dependabot head) is the opt-out. A re-run
    after a fix round reviews the head while its check stays on the commit the
    run first fired at, so a run marker stands in for the check: the latest
    one github-actions[bot] posted for a run attempt, naming the full head
    with status success, whose attempt is a PR-Agent one with a start time
    that finished green. Any other marker is named and not counted;
  - a pending check on a ready pull request, told by its run's creation time:
    created at or after the flip, it is the flip's own run and only has to
    finish; created before the flip and still running at it, the flip came
    too early (`fail flip`). A run whose creation time, or a flip time, is
    unknown reads as plainly pending;
  - where macOS is required, a macos-suite or macos-smoke check that never
    ran, was skipped with no run of it at that head (a draft head) or is
    not SUCCESS, named with the ci-macos label that starts it, so the flip
    never rests on a draft run;
  - an open thread, an unanswered finding, a failed guard, a truncated
    read, a renamed or copied path whose source the forge's file list did
    not name;
  - any screenshot whose judgment is not ok, or recorded at another head;
  - each required step (ready steps) with no passed or applied record
    ending on the head;
  - a cadence not audited at the head, and each gap the audit named: the
    configured cadence binds whatever the gate data names, except on a
    spec-only pull request (a spec-only scope at the head), which is held
    for its sign-off instead of the cadence and the required steps. The
    exception is a post-pr gap (no completion, one only on heads outside the
    pull request's history such as another unit's in a reused worktree, or a
    step never recorded) on a draft whose bot review is due: that point waits
    on the run a review request fires, so it is pending the request, not a
    gap. When the due review and such gaps are all the walk holds, the
    verdict is request-review (below); with any other refusal the verdict
    stays not-ready and names that refusal. Once the run exists, and on a
    ready pull request, the post-pr gap is a gap again;
  - each edited spec bundle not signed off, on any pull request;
  - each drift row: a changed deliverable no spec edit covers, or a drift
    check that could not run (scripts/spec-drift-check.sh);
  - each required evidence kind (ready evidence) with no ok record at the
    head;
  - each required body text (ready body) absent from the body.
The conditions come from scripts/mc-gates.sh resolve, for the evidence's
repo, labels and paths, a renamed or copied path's source among them.

Usage:
  mc-readiness.sh walk --evidence <file> (--program <p> | --conditions <file>)
      ready<TAB><head> (then bypass<TAB><name><TAB><state> per check
      the operator bypasses at merge), or not-ready<TAB><head|-> then
      fail<TAB><what><TAB><detail> per failure, or, for a draft whose only
      gap is its due bot review and the post-pr point that waits on it,
      request-review<TAB><head> then pending<TAB>bot-review<TAB><detail>,
      pending<TAB>post-pr<TAB><detail> per such gap (and any bypass lines):
      request a review on the draft (scripts/request-reviewer.sh), wait for
      the run it fires, answer its findings and record post-pr against it,
      then walk again; the flip follows a ready walk. request-review exits 4
      like not-ready, so a caller that only checks for exit 0 never reads it
      as flip- or merge-ready; a caller that parses the first field names the
      request
  mc-readiness.sh collect --program <p> --repo <owner/name> --pr <n>
                          [--worktree <dir>] --out <file>
      write the evidence at the pull request's current head: one gh read
      for the head, labels, paths, check contexts and body, one GraphQL
      read for the first 100 review threads (a thread opened by a bot is a
      finding, answered once resolved or replied to by a person other than
      the pull request's author, with a login), the spec-only scope (every
      path a `.md` file under the program's spec root inside the
      repository whose origin is --repo, added, modified or deleted, or
      renamed or copied from such a file, its source read from the REST
      file list and never guessed when unread, a rename also touching the
      bundle it leaves; a head that repository lacks is a spec-only scope
      with one unsigned `*` sign-off naming the fetch; then each touched
      bundle, a
      directory under the root not opening with `_`, is signed off when,
      read from that repository's objects at the head with no fetch, its
      requirements.md status is Ready, Active or Done and its
      kickoff-brief.md's latest anchor recomputes over the bundle (a
      requirements.md missing, unreadable or with no Status line, as a
      pre-pipeline bundle has, is unsigned, each named apart with its path;
      a Done bundle with no kickoff-brief.md at the head is a legacy one,
      finished before kickoff existed, and signed with the detail `legacy,
      no kickoff brief`, when the base branch's remote-tracking ref already
      holds the bundle as Done or with no Status line and holds no brief for
      it, and the pull request deletes none (so a pre-pipeline bundle the
      pull request marks Done is legacy); a bundle the base lacks or holds
      at another status, a pull request naming no base, and a base that
      cannot be read all refuse, and a brief that is present never makes a
      bundle legacy); a pull
      request touching only `_` accumulators or files directly under the
      root has no bundle to sign off), for any other pull request the same
      sign-off for each bundle it edits, a rename's source bundle among
      them (a bundle absent at the head aside), and the
      spec-drift check (scripts/spec-drift-check.sh, from the base branch's
      remote-tracking ref to the head, the body its statement), the step
      records of --worktree (scripts/step-record.sh list) and the cadence
      audit there, --worktree defaulting to the one worktree of the
      program's repositories that has the pull request's branch checked
      out (neither read for a spec-only pull request; a worktree ahead of
      the pull request's head is audited at that head, one behind or beside
      it is unaudited), the recorded
      evidence for that head, and the ready-flip guard
      (scripts/ready-guard.sh, given the flip it would refuse) run from the
      program's first repository, then the head read once more, a head that
      moved meanwhile failing the guard; nothing is written to any
      repository
  mc-readiness.sh not-red --evidence <file>
      the notice verdict over a collected evidence file: not-red<TAB><head>
      (exit 0) when no check finished red, pending ones included; otherwise
      red<TAB><head>, then fail<TAB>check<TAB><name> is <state> and
      diagnose<TAB><name> per red check (exit 4). The ready flip never uses it:
      walk refuses a pending or red check
  mc-readiness.sh unfinished --evidence <file>
      the finished-checks verdict over a collected evidence file, for a pull
      request already marked ready: finished<TAB><head> (exit 0) when no check
      is queued, pending or in progress; otherwise unfinished<TAB><head>, then
      fail<TAB>check<TAB><name> is <state> per unfinished check, saying a run
      the flip itself started is that (exit 4); a run created before the flip
      and still running at it is fail<TAB>flip<TAB>... a too-early flip. A
      check that finished red is not unfinished here: a red window-lock is the
      operator's to bypass
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
the program is not configured; 4 not ready (request-review included).

Portable bash 3.2 / BSD tooling; gh's built-in --jq does the JSON.
HELP
}

usage() {
  mc_usage_fail "usage: mc-readiness.sh walk|not-red|unfinished|collect|check|record|watch ...; mc-readiness.sh --help for each verb"
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

# not_red_awk <evidence>: the notice verdict. A check still pending passes; only
# a check that finished red holds, and each one is named and routed to log
# diagnosis. The ready flip judges every check by walk, never by this.
not_red_awk() {
  awk -F '\t' '
function pass_check(s) { return s == "SUCCESS" || s == "NEUTRAL" || s == "SKIPPED" }
function pending_check(s) { return s == "PENDING" || s == "IN_PROGRESS" || s == "QUEUED" || s == "EXPECTED" || s == "WAITING" || s == "REQUESTED" }
FNR == 1 { if ($0 != "# format: 1") { badfmt = 1; exit 4 } ; next }
$1 == "head" { head = $2 }
$1 == "check" && !pass_check($3) && !pending_check($3) { red[++nr] = $2 "\t" $3 }
END {
  if (badfmt) { print "red\t-"; print "fail\tformat\tthe evidence file lacks \"# format: 1\""; exit 4 }
  if (head == "") { print "red\t-"; print "fail\thead\tno evidence at a head was collected"; exit 4 }
  if (!nr) { print "not-red\t" head; exit 0 }
  print "red\t" head
  for (i = 1; i <= nr; i++) {
    split(red[i], r, "\t")
    print "fail\tcheck\t" r[1] " is " r[2]
    print "diagnose\t" r[1]
  }
  exit 4
}' "$1"
}

# The awk both verdicts share. A check named PR-Agent is the bot review: it
# runs on the draft, on a review request, and the flip waits for it, so it is
# judged like any check. On a ready pull request a pending run is told apart
# by when it was created: one created before the flip that was still running
# at it means the flip came too early; one created at or after the flip is the
# flip's own and only has to finish. Without a state, a flip time or a run's
# creation time, a pending check reads as plainly pending.
CHECK_FUNCS='
function pass_check(s) { return s == "SUCCESS" || s == "NEUTRAL" || s == "SKIPPED" }
function pending_check(s) { return s == "PENDING" || s == "IN_PROGRESS" || s == "QUEUED" || s == "EXPECTED" || s == "WAITING" || s == "REQUESTED" }
function bot_check(n) { return n ~ /^PR-Agent( |$)/ }
# stage(pending_only): from the collected check rows, count the checks that
# count (nc), note a PR-Agent one (botseen) and queue each failing one, or each
# pending one when pending_only, in ck[]. It runs once, at the END, so row
# order in the evidence never matters.
function stage(pending_only,    i) {
  for (i = 1; i <= nraw; i++) {
    nc++
    if (bot_check(rn[i])) botseen = 1
    if (pending_only ? pending_check(rs[i]) : !pass_check(rs[i])) ck[++nck] = rn[i] "\t" rs[i]
  }
}
function describe(n, s,    b) {
  b = born[n]
  if (pending_check(s) && state == "ready" && flip != "" && b != "") {
    if (b >= flip) return "check\t" n " is " s " (run created " b ", after the flip at " flip ": the run the flip started, wait for it)"
    return "flip\t" n " was still running at the flip (run created " b ", before the flip at " flip "): a too-early flip"
  }
  return "check\t" n " is " s
}
'
# shellcheck disable=SC2016 # an awk program
CHECK_ROWS='
$1 == "state" { state = $2 }
$1 == "flip" { flip = $2 }
$1 == "born" { born[$2] = $3 }
$1 == "check" { rn[++nraw] = $2; rs[nraw] = $3 }
'

# unfinished_awk <evidence>: the finished-checks verdict. Only a check still
# queued, pending or running holds; one that finished red does not.
unfinished_awk() {
  awk -F '\t' "$CHECK_FUNCS$CHECK_ROWS"'
FNR == 1 { if ($0 != "# format: 1") { badfmt = 1; exit 4 } ; next }
$1 == "head" { head = $2 }
# The flip statuses are no check to wait for: drop the row CHECK_ROWS just kept.
$1 == "check" && ($2 == "planwright/pre-ready-flip" || $2 == "planwright/pre-spec-ready-flip") { nraw-- }
END {
  stage(1)
  if (badfmt) { print "unfinished\t-"; print "fail\tformat\tthe evidence file lacks \"# format: 1\""; exit 4 }
  if (head == "") { print "unfinished\t-"; print "fail\thead\tno evidence at a head was collected"; exit 4 }
  if (!nck) { print "finished\t" head; exit 0 }
  print "unfinished\t" head
  for (i = 1; i <= nck; i++) { split(ck[i], c, "\t"); print "fail\t" describe(c[1], c[2]) }
  exit 4
}' "$1"
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
  awk -F '\t' "$CHECK_FUNCS"'
function fail(what, detail) { fails[++nf] = "fail\t" what "\t" detail }
# bot_marker(): 1 when a run marker the PR-Agent workflow posted proves one of
# its run attempts reviewed the head and finished green, before the flip or
# after it. A re-run keeps the check on the commit the run first fired at, so
# only the marker names the head. Only the latest marker of each author and
# attempt counts; each refused one is named in mwhy.
function bot_marker(    i, m, a, k, at, latest, order, n, r) {
  for (i = 1; i <= nmk; i++) {
    split(mk[i], m, "\t")
    k = m[1] "\t" m[2]
    if (!(k in at)) order[++n] = k
    if (!(k in at) || m[5] >= at[k]) { at[k] = m[5]; latest[k] = mk[i] }
  }
  for (i = 1; i <= n; i++) {
    split(latest[order[i]], m, "\t")
    r = ""
    if (m[1] != "github-actions[bot]") r = "marker " m[2] " was posted by " m[1] ", not the PR-Agent workflow"
    else if (m[3] != head) r = "marker " m[2] " names " (m[3] == "" ? "no commit" : substr(m[3], 1, 12)) ", not the head"
    else if (m[4] != "success") r = "marker " m[2] " reports " m[4]
    else if (!(m[2] in att)) r = "attempt " m[2] " was not read"
    else {
      split(att[m[2]], a, "\t")
      if (!bot_check(a[1])) r = "attempt " m[2] " belongs to " a[1] ", not PR-Agent"
      else if (a[2] == "") r = "attempt " m[2] " has no start time read"
      else if (!pass_check(a[3])) r = "attempt " m[2] " is " a[3]
      else return 1
    }
    mwhy = mwhy "; run " r
  }
  return 0
}
FILENAME == ARGV[1] {
  if ($1 == "ready" && ($2 == "steps" || $2 == "evidence" || $2 == "body")) need[$2, ++nn[$2]] = $3
  next
}
'"$CHECK_ROWS"'
FNR == 1 { if ($0 != "# format: 1") { badfmt = 1; exit } ; next }
$1 == "head" { head = $2 }
$1 == "require" && $2 == "pr-agent" { needbot = 1 }
$1 == "botmark" { mk[++nmk] = $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }
$1 == "botattempt" { att[$2] = $3 "\t" $4 "\t" $5 }
$1 == "bypass" { byp[++nb] = $2 "\t" $3 }
$1 == "check" && ($2 == "macos-suite" || $2 == "macos-smoke" || $2 ~ /^macos-(suite|smoke) /) {
  j = ($2 ~ /^macos-suite/) ? "macos-suite" : "macos-smoke"
  macn[j]++
  if ($3 == "SUCCESS") macok[j]++
  else if ($3 == "SKIPPED") macskip[j] = 1
  else if ($3 == "NEUTRAL") macneutral[j] = $2
}
$1 == "require" && $2 == "macos" { needmac = 1 }
$1 == "thread" && $3 != "resolved" { fail("thread", $2 " is open") }
$1 == "finding" && $4 != "answered" { fail("finding", $2 " " $3 " is unanswered") }
$1 == "guard" && $3 != "pass" { fail("guard", $2 ": " $4) }
$1 == "truncated" { fail("truncated", "the " $2 " read hit its cap; what lies past it is unread") }
$1 == "path" && ($3 == "RENAMED" || $3 == "COPIED") && $4 == "" { fail("path", $2 " is " tolower($3) " from a path the file list of the forge did not name, so the gates and sign-off its source brings cannot be read; collect again") }
$1 == "step" { steps[++ns] = $2 "\t" $3 "\t" $4 }
$1 == "cadence" && $2 == "audited" { audited = $3 }
$1 == "cadence" && $2 == "gap" {
  d = $5 " is " $4
  if ($4 == "incomplete") d = "no completion record"
  else if ($4 == "stale") d = "completed only at " substr($5, 1, 12)
  else if ($4 == "foreign") d = "completed only outside the history of this pull request, newest at " substr($5, 1, 12)
  else if ($4 == "mismatch") d = "a record does not match its branch (" $5 ")"
  else if ($4 == "failed") { i = index($5, ":"); d = substr($5, 1, i - 1) " recorded " substr($5, i + 1) }
  else if ($4 == "fault") d = $5
  if ($4 == "unaudited") { d = $5 " fails the step-record truth check (if only its start or end is wrong, step-record.sh supersede corrects it)"; cad[++ncad] = "not audited: " $3 ": " d; unaud = 1 }
  else {
    cad[++ncad] = $3 ": " d
    # A post-pr step may wait on the bot review a review request fires.
    if ($3 == "post-pr" && ($4 == "incomplete" || $4 == "missing" || $4 == "foreign")) cadpf[ncad] = d
  }
}
$1 == "cadence" && $2 == "unaudited" { cad[++ncad] = "not audited: " $3; unaud = 1 }
$1 == "scope" && $2 == "spec-only" { speconly_head = $3 }
$1 == "signoff" && $3 != "signed" { fail("signoff", $2 ": " ($4 == "" ? "not signed off" : $4)) }
$1 == "drift" {
  if ($2 == "*") fail("drift", "the spec-drift check could not run: " $3)
  else fail("drift", $2 " is a deliverable of " $3 " and no spec edit, Not covered reason or task trailer covers it")
}
$1 == "evidence" { ev[++ne] = $2 "\t" $3 "\t" $4 "\t" $5 }
$1 == "bodyline" { body = body substr($0, 10) "\n" }
END {
  if (badfmt) { print "not-ready\t-"; print "fail\tformat\tthe evidence file lacks \"# format: 1\""; exit 4 }
  if (head == "") { print "not-ready\t-"; print "fail\thead\tno evidence at a head was collected; a session report alone never passes"; exit 4 }
  stage(0)
  # The check refusals lead, as they did when each was read in file order: a
  # caller that takes the first refusal as the reason sees the check first.
  for (i = 1; i <= nck; i++) { split(ck[i], c, "\t"); r = describe(c[1], c[2]); k = index(r, "\t"); lead[++nlead] = "fail\t" substr(r, 1, k - 1) "\t" substr(r, k + 1) }
  if (!nc) fail("check", "no individual check context at the head")
  # The bot review runs on the draft, on a review request, and the flip waits
  # for it: a draft with no run at its head is due a request, and a ready pull
  # request with none is refused. A run before the flip is the one wanted; one
  # still running at the flip is a too-early flip, which describe() names.
  # No apostrophe here: this is a shell string.
  marked = needbot ? bot_marker() : 0
  unreviewed = needbot && !botseen && !marked
  due = unreviewed && state == "draft"
  if (unreviewed && !due) fail("bot-review", "no PR-Agent run at " substr(head, 1, 12) "; request a review (scripts/request-reviewer.sh) and wait for its run" mwhy)
  speconly = (speconly_head == head)
  if (needmac && !speconly) {
    hint = "; add the ci-macos label so CI runs it on the draft"
    nm = split("macos-suite macos-smoke", mj, " ")
    for (i = 1; i <= nm; i++) {
      j = mj[i]
      if (!macn[j]) fail("macos", j " never ran at " substr(head, 1, 12) hint)
      else if (macskip[j] && !macok[j]) fail("macos", j " was skipped at " substr(head, 1, 12) hint)
      else if (macneutral[j] != "") fail("macos", macneutral[j] " is NEUTRAL; the macOS jobs must be green")
    }
  }
  if (!speconly) {
    for (i = 1; i <= ncad; i++) {
      # Until the draft review runs, a post-pr gap that may wait on it is
      # pending the review request, not a gap.
      if ((i in cadpf) && due) pend[++np] = cadpf[i]
      else fail("cadence", cad[i])
    }
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
  if (nf || nlead) {
    print "not-ready\t" head
    for (i = 1; i <= nlead; i++) print lead[i]
    for (i = 1; i <= nf; i++) print fails[i]
    exit 4
  }
  if (due) {
    print "request-review\t" head
    print "pending\tbot-review\tno PR-Agent run at " substr(head, 1, 12) "; request a review (scripts/request-reviewer.sh) on the draft, then wait for the run it fires" mwhy
    for (i = 1; i <= np; i++) print "pending\tpost-pr\t" pend[i] "; pending the bot review (PR-Agent) a review request fires, which a post-pr step may wait on"
    for (i = 1; i <= nb; i++) print "bypass\t" byp[i]
    exit 4
  }
  print "ready\t" head
  for (i = 1; i <= nb; i++) print "bypass\t" byp[i]
}' "$(operand "$2")" "$(operand "$1")"
}

# conditions_for <program> <evidence> <out>: the gate conditions for the
# evidence's repo, labels and paths, a rename's or copy's source among them,
# so moving a file out of a gated path keeps that path's gate.
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
$(awk -F '\t' '
  ($1 == "label" || $1 == "path") && NF >= 2 { print $1 "\t" $2 }
  $1 == "path" && ($3 == "RENAMED" || $3 == "COPIED") && $4 != "" { print "path\t" $4 }' "$cf_ev")
EOF
  /bin/bash "$script_dir/mc-gates.sh" resolve --program "$1" ${cf_args[@]+"${cf_args[@]}"} >"$3"
}

# post_pr_foreign <worktree> <head> <base commit or empty> <records>: succeed
# only when the records hold a post-pr completion and every one is on a head
# outside the pull request's own history: on neither side of <head>'s line,
# or behind it but already held by the base it branched from. Such a
# completion is another unit's, left in a reused worktree, so it is no
# completion at <head>. One behind <head> and not in the base, one ahead of
# it (work not yet pushed), or a head git cannot place keeps the point stale,
# and so does a shallow repository, whose cut history hides ancestry.
post_pr_foreign() {
  local wt=$1 head=$2 base=$3 heads h rc n=0
  [ "$(mc_untrusted_git -C "$wt" rev-parse --is-shallow-repository 2>/dev/null)" = false ] || return 1
  # A record that ends without a newline runs into the next one, so each
  # record line closes the one before it, as the audit reads them.
  heads=$(awk -F '\t' '
    function close_rec() { if (t == "completion" && p == "post-pr" && !seen[h]++) print h; t = p = h = "" }
    $1 == "record" { close_rec(); next }
    $1 == "type" { t = $2 } $1 == "point" { p = $2 } $1 == "head" { h = $2 }
    /^$/ { close_rec() }
    END { close_rec() }' "$4") || return 1
  while IFS= read -r h; do
    [[ $h =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || return 1
    n=$((n + 1))
    mc_untrusted_git -C "$wt" merge-base --is-ancestor "$h" "$head" 2>/dev/null
    rc=$?
    case $rc in
      0)
        [ -n "$base" ] || return 1
        mc_untrusted_git -C "$wt" merge-base --is-ancestor "$h" "$base" 2>/dev/null || return 1
        ;;
      1)
        mc_untrusted_git -C "$wt" merge-base --is-ancestor "$head" "$h" 2>/dev/null
        [ $? -eq 1 ] || return 1
        ;;
      *) return 1 ;;
    esac
  done <<EOF
$heads
EOF
  [ "$n" -gt 0 ]
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
  repos=$(mc_slug_repos "$1" "$2") || {
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

# spec_home <program> <slug>: print `<repository><TAB><spec root relative to
# it>` for the program's repository of <slug> that holds the spec root, or
# fail when none does.
spec_home() {
  local root r top
  root=$(/bin/bash "$script_dir/mc-program.sh" get "$1" spec_root 2>/dev/null) || return 1
  # Logical paths, so a symbolic link in a checkout cannot move the root; the
  # head must then hold the root as a directory.
  root=$(cd -L "$root" 2>/dev/null && pwd -L) || return 1
  while IFS= read -r r; do
    top=$(cd -L "$r" 2>/dev/null && pwd -L) || continue
    case $root in
      "$top"/?*)
        printf '%s\t%s\n' "$r" "${root#"$top"/}"
        return 0
        ;;
    esac
  done < <(mc_slug_repos "$1" "$2" 2>/dev/null)
  return 1
}

# drift_scope <program> <slug> <head> <base ref> <pr read> <scratch dir>: for
# a pull request that is not spec-only, print a `signoff` line for each spec
# bundle it edits and a `drift` line for each changed file the spec-drift
# check flags (path and the tasks listing it), or one `drift<TAB>*` line
# giving the reason the check could not run. Nothing for a program whose spec
# root lies outside the repository.
drift_scope() {
  local home rel repo b why rc=0 rows
  home=$(spec_home "$1" "$2") || return 0
  rel=${home#*	} repo=${home%%	*}
  [ -n "$4" ] || {
    printf 'drift\t*\tthe pull request names no base branch\n'
    return 0
  }
  # A bundle is any directory directly under the root that does not open with
  # `_`, edited by any file under it. A rename edits the bundle it leaves as
  # well; a copy leaves its source unchanged, so it touches only its
  # destination, as in spec_scope.
  SPEC_REL=$rel awk -F '\t' '
    function touch(p,    n, b) {
      n = length(ENVIRON["SPEC_REL"])
      if (substr(p, 1, n + 1) != ENVIRON["SPEC_REL"] "/") return
      p = substr(p, n + 2)
      if (index(p, "/") && substr(p, 1, 1) != "_") { b = substr(p, 1, index(p, "/") - 1); if (!(b in seen)) { seen[b] = 1; print b } }
    }
    $1 == "path" { touch($2); if ($3 == "RENAMED" && $4 != "") touch($4) }' "$5" >"$6/touched" || return 0
  if mc_untrusted_git -C "$repo" cat-file -e "$3^{commit}" 2>/dev/null; then
    while IFS= read -r b; do
      # A bundle the pull request removes or moves has no sign-off to read.
      [[ $b =~ ^[a-z0-9][a-z0-9-]*$ ]] && [ "$(mc_untrusted_git -C "$repo" cat-file -t "$3:$rel/$b" 2>/dev/null)" != tree ] && continue
      signoff_row "$repo" "$3" "$rel" "$b" "$6/touched-$b" "refs/remotes/origin/$4" "$5" || exit
    done <"$6/touched"
  fi
  awk -F '\t' '$1 == "bodyline" { print substr($0, 10) }' "$5" >"$6/body"
  /bin/bash "$script_dir/spec-drift-check.sh" --repo "$repo" --base "refs/remotes/origin/$4" --head "$3" \
    --body-file "$6/body" --spec-root "$rel" >"$6/drift-out" 2>"$6/drift-err" || rc=$?
  case $rc in
    0) ;;
    4)
      rows=$(awk -F '\t' '$1 == "flagged" { print "drift\t" $2 "\t" $3 }' "$6/drift-out")
      if [ -n "$rows" ]; then
        printf '%s\n' "$rows"
      else
        printf 'drift\t*\tthe check reported drift but named no file\n'
      fi
      ;;
    *)
      why=$(sed 's/^spec-drift-check: //' "$6/drift-err" | head -n 1)
      printf 'drift\t*\t%s\n' "${why:-the check exited $rc with no reason given}"
      ;;
  esac
}

# spec_scope <program> <slug> <head> <pr read> <scratch dir> <base branch>:
# when every changed path lies under the program's spec root inside the
# repository for <slug>, print `scope<TAB>spec-only<TAB><head>` and one
# `signoff` line per bundle touched; otherwise nothing. Sign-offs are read
# from the repository's own objects at the head, since collect writes nothing
# (no fetch) to any repository.
spec_scope() {
  local home rel repo files b base=''
  files=$(awk -F '\t' '$1 == "count" && $2 == "files" { print $3 + 0; exit }' "$4")
  [ "${files:-0}" -gt 0 ] && [ "$files" -lt "$CAP" ] || return 0
  home=$(spec_home "$1" "$2") || return 0
  rel=${home#*	} repo=${home%%	*}
  # Each path must sit strictly under the root, with no `.`, `..` or empty
  # component, be prose (`.md`), and be added, modified or deleted, or
  # renamed or copied from a path that passes the same test. A rename or copy
  # with no source named is refused, never guessed. The bundles are the
  # directories directly under the root, those opening with `_` (the reserved
  # accumulators) aside; a rename edits the bundle it leaves as well.
  SPEC_REL=$rel awk -F '\t' '
    function under(p,    n) {
      n = length(ENVIRON["SPEC_REL"])
      if (substr(p, 1, n + 1) != ENVIRON["SPEC_REL"] "/" || p !~ /\.md$/) return ""
      p = substr(p, n + 2)
      if (p == "" || ("/" p "/") ~ /\/(\.|\.\.)?\//) return ""
      return p
    }
    function touch(p,    b) {
      if (index(p, "/") && substr(p, 1, 1) != "_") { b = substr(p, 1, index(p, "/") - 1); if (!(b in seen)) { seen[b] = 1; bs[++nb] = b } }
    }
    $1 != "path" { next }
    {
      if ($3 == "RENAMED" || $3 == "COPIED") {
        if (NF < 4 || (s = under($4)) == "") { out = 1; exit }
      } else if ($3 != "ADDED" && $3 != "MODIFIED" && $3 != "DELETED") { out = 1; exit }
      if ((p = under($2)) == "") { out = 1; exit }
      touch(p)
      if ($3 == "RENAMED") touch(s)
    }
    END { if (out) exit 1; for (i = 1; i <= nb; i++) print bs[i] }' "$4" >"$5/bundles" || return 0
  if ! mc_untrusted_git -C "$repo" cat-file -e "$3^{commit}" 2>/dev/null; then
    printf 'scope\tspec-only\t%s\nsignoff\t*\tunsigned\tthe head is not in %s; fetch it\n' "$3" "$(sanitize_printable "$repo")"
    return 0
  fi
  [ "$(mc_untrusted_git -C "$repo" cat-file -t "$3:$rel" 2>/dev/null)" = tree ] || return 0
  printf 'scope\tspec-only\t%s\n' "$3"
  [ -z "$6" ] || base=refs/remotes/origin/$6
  while IFS= read -r b; do
    signoff_row "$repo" "$3" "$rel" "$b" "$5/bundle-$b" "$base" "$4" || exit
  done <"$5/bundles"
}

# signoff_row <repo> <head> <root rel> <bundle> <scratch dir> <base ref> <pr
# read>: the bundle's `signoff` row at <head>.
signoff_row() {
  local why rc=0
  why=$(bundle_signoff "$@") || rc=$?
  case $rc in
    0) ;;
    5)
      printf 'signoff\t%s\tsigned\tlegacy, no kickoff brief\n' "$4"
      return 0
      ;;
    *) return "$rc" ;;
  esac
  if [ -n "$why" ]; then
    printf 'signoff\t%s\tunsigned\t%s\n' "$4" "$why"
  else
    printf 'signoff\t%s\tsigned\t-\n' "$4"
  fi
}

# bundle_signoff <repo> <head> <root rel> <bundle> <scratch dir> <base ref>
# <pr read>: print why <bundle> is not signed off at <head>, read from
# <repo>'s objects, or nothing when it is; return 5, printing nothing, for a
# legacy bundle (legacy_bundle).
bundle_signoff() {
  local repo=$1 head=$2 rel=$3 b=$4 d=$5 st f entry rc got gd req mode kb
  if ! [[ $b =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    printf 'not a spec identifier'
    return 0
  fi
  mkdir -p "$d" || mc_fail "cannot create a scratch directory"
  req=$(sanitize_printable "$rel/$b/requirements.md")
  # A path git does not hold, one that is no regular file, a file git cannot
  # hand over, and a file with no Status line each need a different fix.
  if ! mode=$(mc_untrusted_git -C "$repo" --literal-pathspecs ls-tree "$head" -- "$rel/$b/requirements.md" 2>/dev/null); then
    printf 'its requirements.md cannot be read at the head (git could not list %s)' "$req"
    return 0
  fi
  mode=${mode%% *}
  case $mode in
    '')
      printf 'it has no requirements.md at the head (%s)' "$req"
      return 0
      ;;
    100644 | 100755) ;;
    *)
      printf 'its requirements.md cannot be read at the head (%s is not a file)' "$req"
      return 0
      ;;
  esac
  if ! mc_untrusted_git -C "$repo" cat-file blob "$head:$rel/$b/requirements.md" >"$d/requirements.md" 2>/dev/null; then
    printf 'its requirements.md cannot be read at the head (git could not read %s)' "$req"
    return 0
  fi
  rc=0
  st=$(spec_parse_header_value "$d/requirements.md" Status 2>/dev/null) || rc=$?
  case $rc in
    0) ;;
    1)
      printf 'its requirements.md cannot be read at the head (%s holds a NUL byte or cannot be read)' "$req"
      return 0
      ;;
    3)
      printf 'its requirements.md declares **Status:** more than once at the head (%s)' "$req"
      return 0
      ;;
    *)
      printf 'its requirements.md cannot be read at the head (%s does not parse)' "$req"
      return 0
      ;;
  esac
  if [ -z "$st" ]; then
    # Never a pass: a bundle from before the pipeline carries no sign-off.
    printf 'its requirements.md has no **Status:** value in its header at the head, as a pre-pipeline bundle has: add **Status:** Draft to the header of %s and sign the bundle off with /spec-kickoff, or leave the bundle out of this pull request' "$req"
    return 0
  fi
  case $st in
    Ready | Active | Done) ;;
    *)
      printf 'its status at the head is %s' "$(sanitize_printable "$st")"
      return 0
      ;;
  esac
  kb=$(sanitize_printable "$rel/$b/kickoff-brief.md")
  # An absent brief is told from one git cannot hand over, since only an
  # absent one can make a Done bundle legacy.
  if ! mode=$(mc_untrusted_git -C "$repo" --literal-pathspecs ls-tree "$head" -- "$rel/$b/kickoff-brief.md" 2>/dev/null); then
    printf 'its kickoff-brief.md cannot be read at the head (git could not list %s)' "$kb"
    return 0
  fi
  mode=${mode%% *}
  case $mode in
    '')
      if [ "$st" = Done ]; then
        legacy_bundle "$repo" "$rel" "$b" "$6" "$7" "$d"
        return
      fi
      printf 'it has no kickoff brief at the head'
      return 0
      ;;
    100644 | 100755) ;;
    *)
      printf 'its kickoff-brief.md cannot be read at the head (%s is not a file)' "$kb"
      return 0
      ;;
  esac
  for f in design.md tasks.md test-spec.md kickoff-brief.md; do
    mc_untrusted_git -C "$repo" cat-file blob "$head:$rel/$b/$f" >"$d/$f" 2>/dev/null || rm -f "$d/$f"
  done
  if ! [ -f "$d/kickoff-brief.md" ]; then
    printf 'its kickoff-brief.md cannot be read at the head (git could not read %s)' "$kb"
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
    "scripts/spec-anchor.sh $rel/$b" | "spec-anchor.sh $rel/$b")
      # Both script forms run only the shipped spec-anchor.sh, never the path
      # the brief names.
      got=$(cd "$repo" && mc_untrusted_git_env && /bin/sh "$script_dir/spec-anchor.sh" "$d" 2>/dev/null) || got=''
      ;;
    'git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin')
      gd=$(mc_untrusted_git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null) || gd=''
      [ -z "$gd" ] || got=$(cd "$d" && mc_untrusted_git_env "$repo" && export GIT_DIR="$gd" \
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

# legacy_bundle <repo> <root rel> <bundle> <base ref> <pr read> <scratch dir>:
# for a Done bundle with no kickoff brief at the head, return 5 when it
# finished before kickoff existed, or print why that cannot be told: the pull
# request deletes its brief, the base holds one, the base cannot be read, or
# the base does not hold the bundle as Done or from before the pipeline (no
# Status line). Deleting a brief, adding a bundle, or marking a Draft, Ready
# or Active one Done in the pull request must never make it legacy.
legacy_bundle() {
  local p="$2/$3/kickoff-brief.md" req="$2/$3/requirements.md" kb name mode st rc=0
  kb=$(sanitize_printable "$p")
  P=$p awk -F '\t' '$1 == "path" && $2 == ENVIRON["P"] && $3 == "DELETED" { found = 1; exit } END { exit !found }' "$5" || rc=$?
  case $rc in
    0)
      printf 'it has no kickoff brief at the head, and the pull request deletes %s' "$kb"
      return 0
      ;;
    1) ;;
    *)
      printf "it has no kickoff brief at the head, and the pull request's file list cannot be read to rule out a deleted one"
      return 0
      ;;
  esac
  if [ -z "$4" ]; then
    printf 'it has no kickoff brief at the head, and the pull request names no base branch to rule out a deleted one'
    return 0
  fi
  name=$(sanitize_printable "${4#refs/remotes/}")
  if ! mc_untrusted_git -C "$1" rev-parse --verify -q "$4^{commit}" >/dev/null 2>&1; then
    printf "it has no kickoff brief at the head, and the pull request's base %s is not in this repository to rule out a deleted one; fetch it" "$name"
    return 0
  fi
  if ! mode=$(mc_untrusted_git -C "$1" --literal-pathspecs ls-tree "$4" -- "$p" 2>/dev/null); then
    printf "it has no kickoff brief at the head, and git could not list %s at the pull request's base %s" "$kb" "$name"
    return 0
  fi
  if [ -n "$mode" ]; then
    printf "it has no kickoff brief at the head, but the pull request's base %s holds one (%s)" "$name" "$kb"
    return 0
  fi
  if ! mode=$(mc_untrusted_git -C "$1" --literal-pathspecs ls-tree "$4" -- "$req" 2>/dev/null); then
    printf "it has no kickoff brief at the head, and git could not list %s at the pull request's base %s" "$(sanitize_printable "$req")" "$name"
    return 0
  fi
  case ${mode%% *} in
    '')
      printf "it has no kickoff brief at the head, and the pull request's base %s does not hold the bundle, so it cannot have finished before kickoff" "$name"
      return 0
      ;;
    100644 | 100755) ;;
    *)
      printf "it has no kickoff brief at the head, and its requirements.md at the pull request's base %s cannot be read for its status" "$name"
      return 0
      ;;
  esac
  rc=0
  mc_untrusted_git -C "$1" cat-file blob "$4:$req" >"$6/base-requirements.md" 2>/dev/null \
    && st=$(spec_parse_header_value "$6/base-requirements.md" Status 2>/dev/null) || rc=1
  if [ "$rc" != 0 ]; then
    printf "it has no kickoff brief at the head, and its requirements.md at the pull request's base %s cannot be read for its status" "$name"
    return 0
  fi
  case $st in
    '' | Done) return 5 ;;
  esac
  printf "it has no kickoff brief at the head, and the pull request's base %s holds it at status %s, so it did not finish before kickoff" "$name" "$(sanitize_printable "$st")"
}

# collect <program> <slug> <pr> <worktree> <out>
collect() {
  cl_tmp=$(mktemp -d "${TMPDIR:-/tmp}/mc-readiness.XXXXXX") || mc_fail "cannot create a scratch directory"
  trap 'rm -rf "$cl_tmp"' EXIT
  cl_owner=${2%%/*}
  cl_name=${2#*/}
  cl_runs=$(cat -- "$script_dir/check-runs.jq") || mc_fail "check-runs.jq is missing or unreadable (broken install)"
  # gh --jq takes no variables, so the list the shared module reads is bound inline.
  cl_base=$(/bin/sh "$script_dir/base-state-checks.sh") || cl_base='[]'
  cl_runs="${cl_base:-[]} as \$base_state | $cl_runs"
  # shellcheck disable=SC2016 # a jq program
  gh pr view "$3" --repo "$2" --json headRefOid,headRefName,baseRefName,isDraft,labels,files,body,statusCheckRollup --jq "$cl_runs"'
    def clean: tostring | gsub("[\t\r\n]"; " ");
    "head\t" + .headRefOid,
    "state\t" + (if .isDraft == true then "draft" else "ready" end),
    "branch\t" + ((.headRefName // "") | clean),
    "base\t" + ((.baseRefName // "") | clean),
    "count\tfiles\t" + ((.files // []) | length | tostring),
    "count\tchecks\t" + ((.statusCheckRollup // []) | length | tostring),
    "count\tlabels\t" + ((.labels // []) | length | tostring),
    (.labels[]? | "label\t" + (.name | clean)),
    ((.statusCheckRollup // []) | bypassed_check_runs[]
      | "bypass\t" + ((.name // "-") | clean) + "\t" + ((.conclusion // "") | if . == "" then "UNKNOWN" else . end | clean)),
    (.files[]? | "path\t" + (.path | clean) + "\t" + ((.changeType // "-") | clean)),
    ((.statusCheckRollup // []) | latest_check_runs[]
      | "check\t" + ((.name // .context // "-") | clean) + "\t"
      + (if (.conclusion // "") != "" then .conclusion else (.state // "PENDING") end | clean)),
    ((.statusCheckRollup // []) | latest_check_runs[]
      | ((.detailsUrl // "") | capture("/actions/runs/(?<id>[0-9]+)")? // empty) as $r
      | "runref\t" + ((.name // .context // "-") | clean) + "\t" + $r.id),
    ((.body // "") | split("\n")[] | "bodyline\t" + (gsub("[\t\r]"; " ")))' >"$cl_tmp/pr" 2>"$cl_tmp/err" \
    || mc_fail "the pull request read failed: $(sanitize_printable "$(head -c 300 "$cl_tmp/err")")"
  cl_head=$(awk -F '\t' '$1 == "head" { print $2; exit }' "$cl_tmp/pr")
  mc_valid_sha "$cl_head" || mc_fail "the pull request read returned no head"
  # The GraphQL file list names no source for a rename or copy; the REST one
  # does. Advisory: a failed read leaves the path with no source,
  # which no spec-only scope accepts and the walk refuses.
  if awk -F '\t' '$1 == "path" && ($3 == "RENAMED" || $3 == "COPIED") { f = 1 } END { exit !f }' "$cl_tmp/pr" \
    && gh api --paginate "repos/$2/pulls/$3/files?per_page=100" --jq '.[] | select((.previous_filename // "") != "")
      | "from\t" + (.filename | tostring | gsub("[\t\r\n]"; " ")) + "\t" + (.previous_filename | tostring | gsub("[\t\r\n]"; " "))' \
      >"$cl_tmp/from" 2>"$cl_tmp/err"; then
    if ! awk -F '\t' '
      FILENAME == ARGV[1] { if ($1 == "from") src[$2] = $3; next }
      $1 == "path" && ($3 == "RENAMED" || $3 == "COPIED") && NF == 3 && ($2 in src) { print $0 "\t" src[$2]; next }
      { print }' "$cl_tmp/from" "$cl_tmp/pr" >"$cl_tmp/pr.from" || ! mv "$cl_tmp/pr.from" "$cl_tmp/pr"; then
      mc_fail "the pull request's rename sources cannot be joined"
    fi
  fi
  # A finding is answered once its thread is resolved, or a person other
  # than the pull request's author replied: the author's sessions post as
  # the author, and their own word is never evidence.
  # shellcheck disable=SC2016 # a GraphQL query and a jq program
  gh api graphql -f owner="$cl_owner" -f name="$cl_name" -F number="$3" -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        author { login }
        timelineItems(last: 1, itemTypes: [READY_FOR_REVIEW_EVENT]) { nodes { ... on ReadyForReviewEvent { createdAt } } }
        reviewThreads(first: 100) { pageInfo { hasNextPage } nodes { id isResolved
          comments(first: 50) { nodes { author { __typename login } } } } } } } }' --jq '
    def bot: ((.author.__typename // "") == "Bot") or ((.author.login // "") | endswith("[bot]"));
    .data.repository.pullRequest as $p | ($p.author.login // "") as $me
    | ($p.timelineItems.nodes[0].createdAt // empty | "flip\t" + .),
      (if $p.reviewThreads.pageInfo.hasNextPage then "truncated\treview threads" else empty end),
      ($p.reviewThreads.nodes[] | . as $t
      | "thread\t" + $t.id + "\t" + (if $t.isResolved then "resolved" else "open" end),
        (if ($t.comments.nodes[0] // {} | bot) then
          "finding\t" + ($t.comments.nodes[0].author.login // "-") + "\t" + $t.id + "\t"
          + (if $t.isResolved or ([$t.comments.nodes[1:][] | select((bot | not) and ((.author.login // "") != "") and ((.author.login // "") != $me))] | length > 0)
             then "answered" else "unanswered" end)
         else empty end))' >"$cl_tmp/threads" 2>"$cl_tmp/err" \
    || mc_fail "the review thread read failed: $(sanitize_printable "$(head -c 300 "$cl_tmp/err")")"
  # When each check's workflow run was created, which a queued check run
  # cannot say (gh reports its start as the zero time). Advisory: a failed read
  # leaves a pending check reading as plainly pending. A draft is never judged
  # by it, so its read is skipped.
  : >"$cl_tmp/born"
  if ! grep -qx "state$(printf '\t')draft" "$cl_tmp/pr" && gh api "repos/$2/actions/runs?head_sha=$cl_head&per_page=100" --jq '.workflow_runs[] | "runat\t" + (.id | tostring) + "\t" + (.created_at // "")' >"$cl_tmp/runs" 2>"$cl_tmp/err"; then
    awk -F '\t' '
      FILENAME == ARGV[1] { if ($1 == "runat" && $3 != "") at[$2] = $3; next }
      $1 == "runref" && ($3 in at) { print "born\t" $2 "\t" at[$3] }' "$cl_tmp/runs" "$cl_tmp/pr" >"$cl_tmp/born" || : >"$cl_tmp/born"
  fi
  # A PR-Agent re-run keeps its check on the commit the run first fired at,
  # though it reviews the current head; the run marker comment the workflow
  # posts names the head it reviewed. Every marker is collected with its
  # author, for the walk to judge, and the attempt behind each of the
  # workflow's markers at the head is read for its start and conclusion.
  # Advisory like the run read: a failed read leaves no row, which the walk
  # never counts as a review. A draft is read too: its review runs before the
  # flip. The marker line is the one .github/workflows/pr-agent.yml writes;
  # change the two together.
  # shellcheck disable=SC2016 # a jq program
  if gh api --paginate "repos/$2/issues/$3/comments?per_page=100" --jq '
    def clean: tostring | gsub("[\t\r\n]"; " ");
    .[] | ((.body // "") | split("\n")[0]
      | capture("^<!-- pr-agent-run: id=(?<id>[0-9]+\\.[0-9]+) head=(?<head>[0-9a-f]*) status=(?<status>[a-z_]+) -->$")?) as $m
    | "botmark\t" + ((.user.login // "-") | clean) + "\t" + $m.id + "\t" + $m.head + "\t" + $m.status + "\t" + ((.updated_at // "") | clean)' \
    >"$cl_tmp/marks" 2>"$cl_tmp/err"; then
    while IFS= read -r cl_att; do
      [ -n "$cl_att" ] || continue
      cl_row=$(gh api "repos/$2/actions/runs/${cl_att%.*}/attempts/${cl_att#*.}" --jq '
        def clean: tostring | gsub("[\t\r\n]"; " ");
        ((.name // "-") | clean) + "\t" + ((.run_started_at // "") | clean) + "\t"
        + (if (.conclusion // "") != "" then .conclusion else (.status // "pending") end | ascii_upcase | clean)' 2>"$cl_tmp/err") \
        && printf 'botattempt\t%s\t%s\n' "$cl_att" "$cl_row" >>"$cl_tmp/marks"
    done <<EOF
$(awk -F '\t' -v H="$cl_head" '$1 == "botmark" && $2 == "github-actions[bot]" && $4 == H && $3 ~ /^[0-9]+\.[0-9]+$/ && !seen[$3]++ { print $3 }' "$cl_tmp/marks")
EOF
  else
    # A failed read, whose partial output must not stand.
    : >"$cl_tmp/marks"
  fi
  : >"$cl_tmp/steps"
  cl_wt=$4
  cl_branch=$(awk -F '\t' '$1 == "branch" { print $2; exit }' "$cl_tmp/pr")
  cl_baseref=$(awk -F '\t' '$1 == "base" { print $2; exit }' "$cl_tmp/pr")
  cl_unaud=''
  : >"$cl_tmp/cadence"
  spec_scope "$1" "$2" "$cl_head" "$cl_tmp/pr" "$cl_tmp" "$cl_baseref" >"$cl_tmp/scope"
  : >"$cl_tmp/drift"
  [ -s "$cl_tmp/scope" ] || drift_scope "$1" "$2" "$cl_head" "$cl_baseref" "$cl_tmp/pr" "$cl_tmp" >"$cl_tmp/drift"
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
  cl_ciwt=$cl_wt
  if [ -n "$cl_wt" ]; then
    # The audit judges the forge's head, never the worktree's: records carry
    # their own heads, and the audit counts one only when its completion is
    # at or behind that head. A worktree ahead of the head (a session still
    # at work past what was pushed) holds the head, so it is audited at the
    # head; one behind or off to the side cannot speak for it.
    cl_wthead=$(mc_untrusted_git -C "$cl_wt" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null) || cl_wthead=''
    if [ "$cl_wthead" != "$cl_head" ] \
      && { [ -z "$cl_wthead" ] || ! mc_untrusted_git -C "$cl_wt" merge-base --is-ancestor "$cl_head" "$cl_wthead" 2>/dev/null; }; then
      cl_unaud="the worktree $(sanitize_printable "$cl_wt") is at ${cl_wthead:-no commit}, not the pull request's head $cl_head and not ahead of it; the session using it may be mid-change, so retry once it has pushed or finished"
      cl_wt=''
    fi
  fi
  if [ -n "$cl_wt" ]; then
    # The audit resolves the cadence as the worktree's own session would; a
    # merge after the last point counts only when the base already holds it.
    # A base the worktree does not hold would let any clean merge pass.
    # Resolved once, so the audit and the foreign check judge the same base
    # even if a fetch in the worktree moves it in between.
    cl_base=()
    cl_basesha=''
    if [ -n "$cl_baseref" ]; then
      cl_basesha=$(mc_untrusted_git -C "$cl_wt" rev-parse --verify -q "refs/remotes/origin/$cl_baseref^{commit}" 2>/dev/null) || cl_basesha=''
      if [[ $cl_basesha =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
        cl_base=(--base "$cl_basesha")
      else
        cl_basesha=''
        cl_unaud="the worktree $(sanitize_printable "$cl_wt") does not hold the base origin/$cl_baseref; fetch it"
        cl_wt=''
      fi
    fi
  fi
  if [ -n "$cl_wt" ]; then
    (mc_untrusted_git_env "$cl_wt" && unset PLANWRIGHT_REPO_ROOT PLANWRIGHT_REPO_ROOT_CHECKED \
      && /bin/bash "$script_dir/step-run.sh" --worktree "$cl_wt" audit --through post-pr --head "$cl_head" ${cl_base[@]+"${cl_base[@]}"}) \
      >"$cl_tmp/audit" 2>"$cl_tmp/err"
    case $? in
      0 | 1) awk -F '\t' -v H="$cl_head" '
          $1 == "gap" { print "cadence\tgap\t" $2 "\t" $3 "\t" $4 }
          $1 == "covered" { print "cadence\tcovered\t" $2 }
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
    if ! (mc_untrusted_git_env "$cl_wt" && /bin/bash "$script_dir/step-record.sh" --worktree "$cl_wt" list) >"$cl_tmp/records" 2>"$cl_tmp/err"; then
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
    if awk -F '\t' '$2 == "gap" && $3 == "post-pr" && $4 == "stale" { f = 1 } END { exit !f }' "$cl_tmp/cadence" \
      && post_pr_foreign "$cl_wt" "$cl_head" "$cl_basesha" "$cl_tmp/records"; then
      if ! awk -F '\t' 'BEGIN { OFS = FS } $2 == "gap" && $3 == "post-pr" && $4 == "stale" { $4 = "foreign" } { print }' \
        "$cl_tmp/cadence" >"$cl_tmp/cadence.new" || ! mv "$cl_tmp/cadence.new" "$cl_tmp/cadence"; then
        mc_fail "the cadence evidence cannot be rewritten"
      fi
    fi
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
  # Where CI has macOS jobs they only run once a pull request is ready (or
  # labelled), so the walk must be told to want them green, not skipped.
  : >"$cl_tmp/require"
  cl_ci=${cl_ciwt:-$cl_first}
  # find, not grep -r --include (busybox grep has no --include) and not a
  # glob (this script runs with globbing off).
  if [ -n "$(find "$cl_ci/.github/workflows" -name '*.yml' -exec grep -lE '^  macos-(suite|smoke):' {} + 2>/dev/null)" ]; then
    printf 'require\tmacos\n' >"$cl_tmp/require"
  fi
  # The bot review is wanted where the repository runs PR-Agent: on the draft,
  # before the flip, and on a ready pull request.
  if [ -n "$(find "$cl_ci/.github/workflows" -name '*.yml' -exec grep -lE '^[^#]*pragent/pr-agent' {} + 2>/dev/null)" ]; then
    printf 'require\tpr-agent\n' >>"$cl_tmp/require"
  fi
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
    awk -F '\t' -v cap="$CAP" '$1 == "count" { if ($3 + 0 >= cap) print "truncated\t" $2; next } $1 == "branch" || $1 == "base" || $1 == "runref" { next } { print }' "$cl_tmp/pr"
    cat "$cl_tmp/born" "$cl_tmp/marks" "$cl_tmp/require" "$cl_tmp/threads" "$cl_tmp/steps" "$cl_tmp/cadence" "$cl_tmp/scope" "$cl_tmp/drift" "$cl_tmp/evidence"
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
  not-red)
    [ -n "$evidence" ] || usage
    [ -r "$evidence" ] || mc_fail "the evidence file is unreadable: $(sanitize_printable "$evidence")"
    not_red_awk "$evidence"
    ;;
  unfinished)
    [ -n "$evidence" ] || usage
    [ -r "$evidence" ] || mc_fail "the evidence file is unreadable: $(sanitize_printable "$evidence")"
    unfinished_awk "$evidence"
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
    # A program whose code state is not snapshotted, or not freshly enough,
    # has nothing to watch yet.
    mc_code_state "$program"
    case $? in
      0) ;;
      1) mc_fail "the source map of program $program does not resolve" ;;
      2) mc_fail "the $MC_CS_SOURCE snapshot cannot be read" ;;
      *) exit 0 ;;
    esac
    snap=$MC_CS_ROWS
    runtime=$(mc_runtime "$program") || mc_fail "cannot resolve the runtime directory"
    seen="$runtime/readiness-announced"
    due=$(printf '%s\n' "$snap" | awk -F '\t' '$1 == "pr" && $5 == "true" && $8 == "0" && $9 == "SUCCESS" { print $2 "\t" $3 "\t" $4 }')
    rc=0
    live=""
    while IFS='	' read -r w_slug w_n w_head; do
      [ -n "$w_slug" ] || continue
      live="$live$w_slug#$w_n	$w_head
"
      w_subject=$(mc_pr_subject "$w_slug" "$w_n")
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
