#!/usr/bin/env bash
# check-workflow-posture.sh — the workflow posture guard: the fork-PR posture
# (guard-coverage D-6; REQ-C1.1, REQ-C1.2, REQ-H1.3), and the platform
# matrix under --matrix (below).
#
# D-6's working posture: PR-authored code MAY execute under `pull_request`, but
# only ever with a read-only token and zero stored secrets. That posture was
# audited once (the REQ-C1.1 record in specs/guard-coverage/kickoff-brief.md);
# this guard is what keeps it true, so a workflow edit that breaks it fails CI
# instead of relying on reviewer vigilance.
#
# The four assertions (REQ-C1.2):
#   1. No workflow uses `pull_request_target` — it runs PR-authored code in the
#      base repo's context, with secrets and a write token.
#   2. Every job reachable from `pull_request` has read-only EFFECTIVE
#      permissions: the job's own `permissions:` when present, else the
#      top-level one. Top-level-only checking is the classic evasion — a
#      job-level override silently escalates under a read-only top level.
#   3. No stored secret is reachable from `pull_request`: no `secrets.NAME`,
#      no `secrets['NAME']`/`secrets["NAME"]` index spelling, and no
#      `secrets: inherit`. Matching is case-INSENSITIVE, because GitHub's
#      expression contexts and secret names are (`${{ SECRETS.foo }}` and
#      `${{ SeCRetS.Baz }}` both resolve), so a case-sensitive scan would be
#      evadable by casing alone. The workflow's own `secrets.GITHUB_TOKEN` is
#      exempt in any casing — it is not a stored secret, GitHub reserves the
#      `GITHUB_` prefix so none can impersonate it, and its privilege is
#      governed by assertion 2. Reachability follows local reusable-workflow
#      `uses:` edges.
#   4. Any `workflow_run` workflow holding write permissions or secrets keeps a
#      base-branch filter, pins the ORIGINATING repository, and consumes no
#      PR-produced artifact. A `workflow_run` fired by a fork PR's workflow runs
#      with the base repo's secrets and write token, so an unfiltered one — or
#      one that unpacks an artifact the PR produced — is the documented
#      cache/artifact-poisoning path. The branch filter alone does not scope the
#      trigger to this repository: `branches:` matches the TRIGGERING run's head
#      branch, and a fork PR's head branch is the fork's ref, so a fork PR from a
#      branch named like the base branch satisfies it. Only a
#      `head_repository.full_name == github.repository` clause says who produced
#      the run, which is what decides whether an outsider can choose when the
#      privileged job fires and whose CI verdict it acts on.
#
# Cache and artifact posture beyond assertion 4 carries no standing check: an
# accepted residual recorded in D-6, covered by the REQ-C1.1 audit only.
#
# FAIL-CLOSED (REQ-H1.3). The guard fails, never passes, when it cannot prove
# the posture: a missing or empty workflow directory, a workflow declaring no
# jobs or no triggers, a file using YAML the parser below does not model, a
# `pull_request`-reachable job with no permissions declaration anywhere (the
# effective token then comes from repo/org settings, which the file cannot
# prove read-only), a local `uses:` target absent from the scanned set, and —
# for assertion 4 — a `workflow_run` workflow whose permissions are undeclared
# or unrecognized, which is treated as privileged.
#
# PARSE BOUNDARY (deliberate, in the spirit of D-7's). A strict block-style
# subset is modeled: 2-or-more-space indentation, `key: value` mappings, `- `
# sequence items, block scalars (`|`, `>`), and flow scalars/sequences as leaf
# VALUES. Tabs in indentation, multiple documents, anchors, aliases, merge
# keys, and flow mappings as the value of `on:` or `jobs:` are NOT modeled and
# are reported as parse failures rather than half-read. A flow mapping under
# `permissions:` is read rather than rejected, in both its top-level and
# job-level spellings: `{}` reads as read-only (GitHub's documented spelling
# for "no permissions at all"), and any other flow mapping reads as an
# unrecognized level, which the driver treats exactly like `write`. Both are
# verdicts rather than half-reads, and stopping short of a parse failure keeps
# the guard from failing a push-only workflow over a `permissions:` shape it
# never judges. Job-level keys are read only at the job's own body indent, so a
# step's `uses:` is never mistaken for a reusable-workflow call. Block-scalar
# bodies are skipped for STRUCTURE (a `- run: |` script is text, and a line
# reading `name: &anchor` in it is shell) but still scanned as TEXT for secret
# and artifact references. Full-line comments are skipped by both; a trailing
# comment is scanned, so a comment mentioning `secrets.FOO` over-blocks — the
# fail-loud direction, and cheaper than deciding whether a `#` sits inside a
# quoted string. Physical lines are joined on a trailing backslash before
# scanning, so a shell command split across lines is read as the one command it
# is.
#
# That text scan is a heuristic, and assertion 4's artifact half is where that
# matters: it recognizes `download-artifact` and `gh run download`, which covers
# how an artifact is fetched in practice and any honest formatting of it, but
# not every way one could be. The artifacts REST API reached by `curl`, an
# action name assembled from a matrix variable, or a renamed `gh` all pass it.
# Closing that class needs expression evaluation this parser deliberately does
# not do, so it is an accepted residual on the same footing as the cache
# posture above — assertion 4 raises the cost of the artifact-poisoning path
# rather than proving it shut.
#
# The originating-repository half is a text scan for the same reason: the
# clause lives in a job `if:`, whose ordinary `>-` spelling is a block scalar
# this parser reads as leaf content. What it looks for is the EQUALITY against
# `github.repository`, in either operand order, and not merely the field —
# `repository: ${{ …head_repository.full_name }}` on a checkout step is the
# fork's code being cloned into the privileged job, so a bare substring test
# would take the attack for the defense; requiring `==` also means an inverted
# `!=` cannot satisfy it. Two consequences of matching the canonical spelling:
# an equivalent gate written another way (`== 'owner/repo'`, or the comparison
# split across two physical lines) does not satisfy the assertion, which fails
# loud and is corrected by spelling it the canonical way.
#
# Its residual runs the other way from the artifact half's: a match proves the
# clause is PRESENT in the file, not that it gates the privileged job, because
# whether an expression is a gate is exactly the evaluation this parser does
# not do. So the check catches the regression that happens (the clause is
# deleted, or the workflow never had one) and not the one that has to be
# written on purpose (a real equality parked in an `env:` value, or one job
# carrying it while a second privileged job in the same file does not). What it
# does refuse is the clause surviving only as narration: full-line comments
# never reach the scan and everything from the first `#` on is stripped before
# it, so a paragraph outliving the clause it explains fails.
#
# Two ways that strip costs a false failure, both loud and both fixed by
# reformatting: a `#` that is literal content earlier on the line (inside a
# quoted string, or in a block-scalar body) truncates the scanned text before
# the clause, and a TRAILING comment whose last character is a backslash joins
# the line after it into the same logical line and takes that line's clause
# with it. A third shape needs no strip to bite: the `privileged` verdict this
# assertion hangs off is set by the secret scan, which reads comments on
# purpose, so a read-only `workflow_run` workflow carrying `secrets.NAME` in a
# TRAILING comment is judged privileged and asked for the clause too. Both
# shapes need the trailing position — a full-line comment is dropped before
# either the join or any scan — which is also why a paragraph explaining a
# deleted clause, the usual narration shape, is never mistaken for the clause.
#
# The negation disqualifier reads one physical line, so an `!(` opening on its
# own line above the clause is not seen; that is the same written-on-purpose
# class as the residuals above, not a shape anyone reaches by accident.
#
# Remote reusable workflows (`owner/repo/.github/workflows/x.yml@ref`) are not
# fetched, and do not need to be: GitHub scopes a called workflow's
# GITHUB_TOKEN to at most the caller job's permissions (maintained or reduced,
# never elevated), and secrets reach a callee only via `secrets: inherit` or an
# explicit `secrets:` block — all three of which assertions 2 and 3 already
# check on the CALLING job.
#
# Untrusted input: workflow files are PR-controllable. They are read as text by
# awk and never executed, sourced, or eval'd; the only glob is the fixed
# `*.yml`/`*.yaml` pattern under the scanned directory, so no file CONTENT is
# ever subject to expansion.
#
# THE PLATFORM MATRIX (--matrix, universal-binary REQ-B1.4, D-13). Given a
# workflow file name, a further assertion holds that file to the CI platform
# matrix, failing closed when it is absent:
#   - it carries an Ubuntu job (runs-on ubuntu-*, no container), a macOS job
#     (runs-on macos-*), and exactly one Alpine job (a container image whose
#     last path component is alpine); a runs-on this parser cannot read as a
#     scalar, a matrix expression included, places a job on no platform;
#   - every step blocks: no `continue-on-error` other than `false`, and no
#     flow mapping or sequence naming it at all; no content line swallowing a
#     failure (`||` onto `true`, `:`, `/bin/true`, `exit 0`, or `{ true; }`,
#     on the same line or the next, and `set +e` or `set +o errexit`), in a
#     `run:` body or a shell comment alike, which over-blocks the loud way;
#     and no `shell:` other than `bash`, `sh`, or a command line
#     carrying `-e`, since a custom shell without it lets every line but the
#     last fail silently;
#   - no `if:`, job- or step-level and on every line of a multi-line value,
#     names a platform (runner.os, runner.arch, matrix.os, or a platform
#     word); the macOS and Alpine jobs carry no job-level `if:` at all, since
#     a matrix job runs on every pull request; and a step the scope names
#     (`install smoke`, `shell suite`, `bake-off harness`) carries no `if:`
#     beyond always(), !cancelled(), or success();
#   - the Ubuntu and macOS sides each carry an `install smoke` step in a job
#     with no job-level `if:` beyond those three;
#   - every Alpine step is named, each name either `setup: <what>` or one of
#     the scope REQ-B1.4 gives the job, with exactly one `shell suite`,
#     exactly one `install smoke`, and at most one `bake-off harness`.
# The scope is held by step name, so a step doing other work under a
# `setup: ` name passes; the name is what a reviewer reads, and the guard
# holds the list of names, not what each command does. The swallowing forms
# are the spellings in use, not every one: `|| echo skipped`, an early
# `exit 0`, or a platform job made to `needs:` a gated job all pass. A
# flow-style step (`- {run: x}`) and a job id outside GitHub's grammar fail
# closed. Workflow text reaches stderr with non-printable bytes dropped.
#
# Usage: check-workflow-posture.sh [--matrix <workflow-file>] [<workflows-dir>]
#   Default: <repo-root>/.github/workflows (the repo root is derived from this
#   script's location, so a bare invocation works from any directory).
#   --matrix names a file directly under the scanned directory.
# Exit: 0 posture holds; 1 a violation or a fail-closed condition (offending
#   file:line on stderr); 2 usage error.
#
# Portable bash 3.2 / BSD tooling; POSIX awk. No fish/mise dependency
# (REQ-K1.5).
set -u

# Pin the C locale so the bracket expressions below mean exactly their ASCII
# range on every host (mirrors check-options-reference.sh).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below and
# corrupt the repo-root derivation.
unset CDPATH

usage() {
  echo "usage: check-workflow-posture.sh [--matrix <workflow-file>] [<workflows-dir>]" >&2
  exit 2
}
matrix=""
if [ "${1:-}" = "--matrix" ]; then
  [ $# -ge 2 ] || usage
  matrix="$2"
  shift 2
  case "$matrix" in
    "" | */* | .*) usage ;;
    *.yml | *.yaml) ;;
    *) usage ;;
  esac
fi
[ $# -le 1 ] || usage

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)" || exit 2
dir="${1:-$repo_root/.github/workflows}"

if [ ! -d "$dir" ]; then
  echo "check-workflow-posture: no workflow directory at '$dir' — the fork-PR" \
    "posture cannot be verified (failing closed, not skipping)." >&2
  exit 1
fi

# Enumerate the workflow files. A non-matching glob stays literal, so each
# candidate is existence-checked. Indexed by a counter rather than expanded as
# "${files[@]}", which bash 3.2 rejects under `set -u` when the array is empty.
nfiles=0
files=()
for f in "$dir"/*.yml "$dir"/*.yaml; do
  [ -f "$f" ] || continue
  files[nfiles]="$f"
  nfiles=$((nfiles + 1))
done

if [ "$nfiles" -eq 0 ]; then
  echo "check-workflow-posture: no workflow files under '$dir' — nothing was" \
    "proven about the fork-PR posture (failing closed, not passing vacuously)." >&2
  exit 1
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

# --- the parser ------------------------------------------------------------
#
# One pass per file, emitting a tab-separated fact stream the driver below
# evaluates. Facts:
#   E <line> <message>              a parse failure (fail closed)
#   T <trigger>                     a trigger name from `on:`
#   W branches                      the workflow_run trigger has a base-branch filter
#   P <read|write|unknown|absent>   top-level permissions verdict
#   J <job> <read|write|unknown|absent>   a job and its OWN permissions verdict
#   U <job> <local|remote> <target>       a job-level reusable-workflow call
#   S <job> inherit                 a job-level `secrets: inherit`
#   R <line> <name>                 a stored-secret reference (GITHUB_TOKEN excluded)
#   A <line>                        an artifact-download reference
#   H <line>                        a head_repository == github.repository clause
read -r -d '' awk_parser <<'AWK_PARSER' || true
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function unquote(s) { sub(/^["']/, "", s); sub(/["']$/, "", s); return s }
function err(msg) { printf "E\t%d\t%s\n", NR, msg; errs++ }
# read-all / write-all / {} are the three scalar permission spellings; anything
# else (including a bare `permissions:` with no entries) is unknown, and the
# driver treats unknown exactly like write.
function scalar_perm(v) {
  v = unquote(v)
  if (v == "read-all") return "read"
  if (v == "write-all") return "write"
  if (v == "{}") return "read"
  return "unknown"
}
function level_perm(v) {
  if (v == "read" || v == "none") return "read"
  if (v == "write") return "write"
  return "unknown"
}
# Merge a newly seen level into a running verdict: write and unknown are both
# disqualifying, and write is reported in preference to unknown.
function merge_perm(cur, add) {
  if (cur == "write" || add == "write") return "write"
  if (cur == "unknown" || add == "unknown") return "unknown"
  return "read"
}
# Whether the key on the current line is one the parser derives a verdict
# from, rather than leaf content. Mirrors the section dispatch below, and is
# read BEFORE that dispatch updates the level variables, so a `*_child` still
# at -1 means this line is about to become that level and counts as structural.
function structural_key() {
  if (indent == 0) return (key == "on" || key == "permissions" || key == "jobs")
  if (section == "on") return (on_child < 0 || indent == on_child)
  if (section == "permissions") return (perm_child < 0 || indent == perm_child)
  if (section == "jobs") {
    if (jobs_child < 0 || indent == jobs_child) return 1
    if (job_body < 0 || indent == job_body) return (key == "permissions" || key == "uses" || key == "secrets")
    if (in_jperm && (jperm_child < 0 || indent == jperm_child)) return 1
  }
  return 0
}
function record_trigger(t) {
  t = unquote(trim(t))
  sub(/:$/, "", t)
  if (t == "") return
  printf "T\t%s\n", t
  ntrig++
  cur_trigger = t
}
# `on: push`, `on: [push, pull_request]`. A flow MAPPING is not modeled, and
# neither is a flow SEQUENCE that opens here without closing on the same line:
# both must fail closed rather than fall through to record_trigger, which would
# file the raw `[` as the trigger name and lose every real trigger with it. A
# lost `pull_request` is the worst direction to be wrong in — it reads as "not
# reachable" and switches off assertions 2 and 3 for the whole file.
function inline_triggers(v,   inner, n, parts, i) {
  if (v ~ /^\{/) { err("flow-mapping `on:` value is outside the parsed subset"); return }
  if (v ~ /^\[/) {
    if (v !~ /\]$/) { err("multi-line flow-sequence `on:` value is outside the parsed subset"); return }
    inner = substr(v, 2, length(v) - 2)
    n = split(inner, parts, ",")
    for (i = 1; i <= n; i++) record_trigger(parts[i])
    return
  }
  record_trigger(v)
}
# The secret and artifact scans, run over one LOGICAL line (see the joining
# below) and reporting at the line it starts on. Matched against a lower-cased
# copy because GitHub expression contexts AND secret names are case-insensitive
# — `${{ SECRETS.foo }}` and `${{ SeCRetS.Baz }}` both resolve — so a
# case-sensitive scan would be evadable by casing alone. The exemption is
# case-insensitive for the same reason, which is safe: GitHub reserves the
# `GITHUB_` prefix, so no stored secret can be named `github_token` in any
# casing. Names are reported upper-cased, the form GitHub stores them in.
function scan_refs(t, nr,   low, s, tok) {
  low = tolower(t)
  s = low
  while (match(s, /secrets[ \t]*(\.[a-z_][a-z0-9_]*|\[[ \t]*["'][a-z_][a-z0-9_]*["'][ \t]*\])/)) {
    tok = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    sub(/^secrets[ \t]*/, "", tok)
    gsub(/[^a-z0-9_]/, "", tok)
    if (tok != "github_token") printf "R\t%d\t%s\n", nr, toupper(tok)
  }
  if (low ~ /download-artifact/ || low ~ /gh[ \t]+run[ \t]+download/) printf "A\t%d\n", nr
  # Everything from the first `#` on is dropped before the match below, so the
  # clause must be live content rather than narration — including a `;#` shell
  # comment inside a `run:` body, which no whitespace-anchored strip would see.
  # This is the opposite treatment from the secret scan above, and deliberately:
  # reading a comment there over-blocks (loud), reading one here would let a
  # paragraph outlive the clause it explains (silent). A `#` that is literal
  # content rather than a comment truncates the line early and the assertion
  # then fails, which is the direction to be wrong in.
  #
  # The trailing space lets one `[^a-z0-9_]` guard cover the end of the line as
  # well as the middle of it.
  sub(/#.*$/, "", low)
  low = low " "
  # The EQUALITY, in either operand order — not any use of the field. The
  # difference is the whole assertion: `repository: ${{ …head_repository…}}` on
  # a checkout step is the fork's code being cloned into the write-token job,
  # and a bare substring test would read that as evidence of hardening. The
  # right operand is guarded against `github.repository_owner` and
  # `github.repository_id`, which merely start the same way and, compared with
  # an `owner/repo` string, can never be true — a dead gate, not a live one.
  # `!=` cannot match at all, and an `!(` opening directly onto the clause
  # disqualifies it, so neither spelling of an inverted clause counts. The
  # disqualifier names the clause on BOTH sides of that `!(` — including the
  # reversed operand order in full — so it reads the clause's own polarity
  # rather than the line's: a second, unrelated negated condition beside a live
  # clause is ordinary expression-writing, and that stays true when the
  # unrelated condition happens to negate an equality on `github.repository`.
  if ((low ~ /github\.event\.workflow_run\.head_repository\.full_name[ \t]*==[ \t]*github\.repository[^a-z0-9_]/ ||
       low ~ /github\.repository[ \t]*==[ \t]*github\.event\.workflow_run\.head_repository\.full_name/) &&
      low !~ /![ \t]*\([ \t]*github\.(event\.workflow_run\.head_repository|repository[ \t]*==[ \t]*github\.event\.workflow_run\.head_repository)/)
    printf "H\t%d\n", nr
}
BEGIN {
  section = ""; on_child = -1; perm_child = -1; jobs_child = -1
  job_body = -1; jperm_child = -1; in_jperm = 0
  top_perm = "absent"; top_perm_n = 0
  cur_job = ""; njobs = 0; ntrig = 0; errs = 0; fatal = 0
  bs = 0; bs_indent = -1; ndocs = 0; seen_content = 0
  cont = 0; logical = ""; logical_nr = 0
}
{
  if (fatal) next
  line = $0
  sub(/\r$/, "", line)
  if (line ~ /^[ \t]*$/) next

  match(line, /^[ \t]*/)
  indent = RLENGTH
  ws = substr(line, 1, indent)
  if (ws ~ /\t/) {
    err("tab in indentation is outside the parsed subset")
    fatal = 1
    next
  }
  rest = substr(line, indent + 1)
  if (rest ~ /^#/) next

  # Text scans run on every content line, block-scalar bodies included: a
  # `run: |` script can reference a secret or download an artifact just as a
  # structured value can. Physical lines are first joined into LOGICAL ones on
  # a trailing backslash, because a `run:` body may split one shell command
  # across several lines — ordinary formatting for a long command, not only an
  # evasion — and a physical-line-at-a-time scan would read `gh run \` and
  # `download …` as two commands and match neither. Only the scans see the
  # joined text; the structural parsing below stays line-at-a-time.
  # Concatenated with NO separator, which is what both spellings that reach
  # here mean. YAML's double-quoted escaped line break removes the break
  # entirely, so `"${{ sec\` + `rets.FOO }}"` IS `${{ secrets.FOO }}` to GitHub
  # and a space inserted here would hide it. A shell continuation keeps the
  # space that precedes its backslash, so `gh run \` + `download …` still joins
  # to a matchable `gh run download …`.
  if (cont) {
    logical = logical rest
  } else {
    logical = rest
    logical_nr = NR
  }
  if (logical ~ /\\[ \t]*$/) {
    sub(/\\[ \t]*$/, "", logical)
    cont = 1
  } else {
    cont = 0
    scan_refs(logical, logical_nr)
  }

  # Block-scalar bodies carry no structure for this parser.
  if (bs) {
    if (indent > bs_indent) next
    bs = 0
  }

  if (rest ~ /^---([ \t]|$)/) {
    ndocs++
    if (ndocs > 1 || seen_content) { err("multiple YAML documents are outside the parsed subset"); fatal = 1 }
    next
  }
  if (rest ~ /^\.\.\.([ \t]|$)/) { err("document-end marker is outside the parsed subset"); fatal = 1; next }
  if (rest ~ /^<<[ \t]*:/) { err("YAML merge key is outside the parsed subset"); fatal = 1; next }
  if (rest ~ /:[ \t]+&[A-Za-z_]/ || rest ~ /^-[ \t]+&[A-Za-z_]/) { err("YAML anchor is outside the parsed subset"); fatal = 1; next }
  if (rest ~ /:[ \t]+\*[A-Za-z_]/ || rest ~ /^-[ \t]+\*[A-Za-z_]/) { err("YAML alias is outside the parsed subset"); fatal = 1; next }
  seen_content = 1

  isseq = (rest ~ /^-([ \t]|$)/)
  haskey = 0; key = ""; val = ""
  if (!isseq && match(rest, /^("[^"]*"|'[^']*'|[A-Za-z_][A-Za-z0-9_.-]*)[ \t]*:([ \t]|$)/)) {
    haskey = 1
    # The match spans the key, its colon, and (unless the key ends the line)
    # the one separating space, so the key is what is left after trimming that
    # space and the colon, and the value is everything past the match.
    kraw = trim(substr(rest, 1, RLENGTH))
    sub(/:$/, "", kraw)
    key = unquote(trim(kraw))
    val = trim(substr(rest, RLENGTH + 1))
    sub(/[ \t]+#.*$/, "", val)
    val = trim(val)
  }
  # A value that opens a block scalar (`|`, `>`, `|-`, `>2`, …). The sequence
  # forms (`- run: |`, `- |`) matter as much as the mapping form: a step script
  # is TEXT, and a body line reading `name: &anchor` or `<<: merge` is shell,
  # not YAML structure. Without this the body would reach the structural
  # screening below and be rejected as an anchor or a merge key.
  # …but only where the value really is leaf content. On a key the parser
  # derives a verdict from, skipping the body drops the key itself, and YAML
  # resolves each of these to exactly the plain string GitHub's schema accepts:
  # `permissions: |-` over `write-all` runs write-all, `uses: |-` over a path
  # calls that workflow. Silently dropping either reads as the safe verdict, so
  # a structural key opening a block scalar fails closed instead.
  if (haskey && val ~ /^[|>][0-9]*[+-]?$/) {
    if (structural_key()) {
      err("block scalar as the value of the structural key `" key ":` is outside the parsed subset")
      fatal = 1
      next
    }
    bs = 1; bs_indent = indent; next
  }
  if ((isseq && rest ~ /:[ \t]*[|>][0-9]*[+-]?[ \t]*$/) ||
      (isseq && rest ~ /^-[ \t]+[|>][0-9]*[+-]?[ \t]*$/)) {
    bs = 1; bs_indent = indent; next
  }

  if (indent == 0) {
    if (!haskey) { err("unparsed top-level line"); fatal = 1; next }
    in_jperm = 0
    if (key == "on") {
      section = "on"; on_child = -1; cur_trigger = ""
      if (val != "") { inline_triggers(val); section = "" }
    } else if (key == "permissions") {
      section = "permissions"; perm_child = -1
      if (val != "") { top_perm = scalar_perm(val); top_perm_n = 1; section = "" } else { top_perm = "read"; top_perm_n = 0 }
    } else if (key == "jobs") {
      section = "jobs"; jobs_child = -1; job_body = -1; cur_job = ""
      if (val != "") { err("flow-style `jobs:` value is outside the parsed subset"); fatal = 1 }
    } else {
      section = ""
    }
    next
  }

  if (section == "on") {
    if (on_child < 0) on_child = indent
    if (indent < on_child) { err("inconsistent indentation under `on:`"); fatal = 1; next }
    if (indent == on_child) {
      if (isseq) record_trigger(substr(rest, 2))
      else if (haskey) record_trigger(key)
      else { err("unparsed line under `on:`"); fatal = 1 }
    } else if (cur_trigger == "workflow_run" && haskey && key == "branches") {
      print "W\tbranches"
    }
    next
  }

  if (section == "permissions") {
    if (perm_child < 0) perm_child = indent
    if (indent != perm_child) { err("unexpected nesting under `permissions:`"); fatal = 1; next }
    if (!haskey) { err("unparsed line under `permissions:`"); fatal = 1; next }
    top_perm = merge_perm(top_perm, level_perm(val))
    top_perm_n++
    next
  }

  if (section == "jobs") {
    if (jobs_child < 0) jobs_child = indent
    if (indent < jobs_child) { err("inconsistent indentation under `jobs:`"); fatal = 1; next }
    if (indent == jobs_child) {
      if (!haskey) { err("unparsed job entry under `jobs:`"); fatal = 1; next }
      if (val != "") { err("flow-style job body is outside the parsed subset"); fatal = 1; next }
      cur_job = key; njobs++
      jobperm[cur_job] = "absent"; jobperm_n[cur_job] = 0
      joborder[njobs] = cur_job
      job_body = -1; in_jperm = 0
      next
    }
    if (job_body < 0) job_body = indent
    if (indent < job_body) { err("inconsistent job-body indentation"); fatal = 1; next }
    if (indent == job_body) {
      in_jperm = 0
      if (!haskey) next
      if (key == "permissions") {
        if (val != "") { jobperm[cur_job] = scalar_perm(val); jobperm_n[cur_job] = 1 } else { jobperm[cur_job] = "read"; jobperm_n[cur_job] = 0; in_jperm = 1; jperm_child = -1 }
      } else if (key == "uses") {
        u = unquote(val)
        printf "U\t%s\t%s\t%s\n", cur_job, (u ~ /^\.\//) ? "local" : "remote", u
      } else if (key == "secrets" && tolower(unquote(val)) == "inherit") {
        printf "S\t%s\tinherit\n", cur_job
      }
      next
    }
    if (in_jperm) {
      if (jperm_child < 0) jperm_child = indent
      if (indent != jperm_child) { err("unexpected nesting under a job's `permissions:`"); fatal = 1; next }
      if (!haskey) { err("unparsed line under a job's `permissions:`"); fatal = 1; next }
      jobperm[cur_job] = merge_perm(jobperm[cur_job], level_perm(val))
      jobperm_n[cur_job]++
    }
    next
  }
}
END {
  # A backslash left dangling at EOF never reached the join's else branch.
  if (cont) scan_refs(logical, logical_nr)
  if (errs > 0) exit 0
  if (ntrig == 0) { printf "E\t0\t%s\n", "workflow declares no triggers"; exit 0 }
  if (njobs == 0) { printf "E\t0\t%s\n", "workflow declares no jobs"; exit 0 }
  # A declared-but-empty permissions map proves nothing.
  if (top_perm != "absent" && top_perm_n == 0) top_perm = "unknown"
  printf "P\t%s\n", top_perm
  for (i = 1; i <= njobs; i++) {
    j = joborder[i]
    v = jobperm[j]
    if (v != "absent" && jobperm_n[j] == 0) v = "unknown"
    printf "J\t%s\t%s\n", j, v
  }
}
AWK_PARSER

for ((i = 0; i < nfiles; i++)); do
  awk "$awk_parser" "${files[i]}" >"$work/facts.$i" || {
    echo "check-workflow-posture: awk failed on '${files[i]}'" >&2
    exit 1
  }
done

# --- the driver ------------------------------------------------------------

viol="$work/violations"
: >"$viol"
fail() { printf '  %s\n' "$*" >>"$viol"; }

# fact <index> <letter> — the fact lines of one kind for one file.
fact() { grep "^$2	" "$work/facts.$1" 2>/dev/null || true; }

# Parse failures first: a file the parser could not read tells us nothing, so
# every later assertion about it would be a vacuous pass.
parse_failed=0
for ((i = 0; i < nfiles; i++)); do
  while IFS=$'\t' read -r _ ln msg; do
    [ -n "${msg:-}" ] || continue
    fail "${files[i]}:$ln: parse failure — $msg"
    parse_failed=1
  done < <(fact "$i" E)
done

if [ "$parse_failed" -eq 0 ]; then
  # Reachability: files carrying a `pull_request` trigger, plus the transitive
  # closure over local reusable-workflow `uses:` edges. A local target is
  # matched by basename within the scanned set, so the closure works the same
  # for the repo's own .github/workflows and for a fixture directory.
  reach=()
  for ((i = 0; i < nfiles; i++)); do
    reach[i]=0
    if fact "$i" T | grep -qx $'T\tpull_request'; then reach[i]=1; fi
  done

  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    for ((i = 0; i < nfiles; i++)); do
      [ "${reach[i]}" -eq 1 ] || continue
      while IFS=$'\t' read -r _ job kind target; do
        [ "${kind:-}" = "local" ] || continue
        base="${target##*/}"
        for ((j = 0; j < nfiles; j++)); do
          [ "${files[j]##*/}" = "$base" ] || continue
          if [ "${reach[j]}" -eq 0 ]; then
            reach[j]=1
            changed=1
          fi
        done
      done < <(fact "$i" U)
    done
  done

  for ((i = 0; i < nfiles; i++)); do
    file="${files[i]}"
    triggers="$(fact "$i" T | cut -f2)"
    top_perm="$(fact "$i" P | cut -f2)"

    # 1. pull_request_target is banned outright, reachable or not.
    if printf '%s\n' "$triggers" | grep -qx 'pull_request_target'; then
      fail "$file: uses the \`pull_request_target\` trigger, which runs PR-authored code in the base repo's context with secrets and a write token (D-6 forbids it)"
    fi

    # 2 & 3. Everything reachable from pull_request.
    if [ "${reach[i]}" -eq 1 ]; then
      while IFS=$'\t' read -r _ job verdict; do
        [ -n "${job:-}" ] || continue
        eff="$verdict"
        [ "$eff" = "absent" ] && eff="$top_perm"
        case "$eff" in
          read) ;;
          absent)
            fail "$file: job '$job' is reachable from \`pull_request\` and has no permissions declaration (neither job-level nor top-level), so its effective token comes from repo/org settings and cannot be proven read-only"
            ;;
          write)
            fail "$file: job '$job' is reachable from \`pull_request\` with write effective permissions; D-6 requires a read-only token on that path"
            ;;
          *)
            fail "$file: job '$job' is reachable from \`pull_request\` and its effective permissions are unrecognized, so read-only cannot be proven"
            ;;
        esac
      done < <(fact "$i" J)

      while IFS=$'\t' read -r _ ln name; do
        [ -n "${name:-}" ] || continue
        fail "$file:$ln: stored secret '$name' is reachable from \`pull_request\`; only \`secrets.GITHUB_TOKEN\` may appear on that path"
      done < <(fact "$i" R)

      while IFS=$'\t' read -r _ job _; do
        [ -n "${job:-}" ] || continue
        fail "$file: job '$job' passes \`secrets: inherit\` on a path reachable from \`pull_request\`, handing every stored secret to the called workflow"
      done < <(fact "$i" S)

      # A local `uses:` the closure above could not resolve. Reported here,
      # once per edge, rather than inside the closure loop, which revisits
      # every reachable file on each iteration.
      while IFS=$'\t' read -r _ job kind target; do
        [ "${kind:-}" = "local" ] || continue
        base="${target##*/}"
        found=0
        for ((j = 0; j < nfiles; j++)); do
          [ "${files[j]##*/}" = "$base" ] && found=1
        done
        [ "$found" -eq 1 ] || fail "$file: job '$job' calls local reusable workflow '$target', which is not in the scanned set — its reachable surface is unknown (failing closed)"
      done < <(fact "$i" U)
    fi

    # 4. workflow_run: privileged runs must stay pinned to the base branch and
    #    must not unpack anything a PR produced.
    if printf '%s\n' "$triggers" | grep -qx 'workflow_run'; then
      privileged=0
      reason=""
      if [ "$top_perm" != "read" ]; then
        privileged=1
        reason="write or undeclared permissions"
      fi
      while IFS=$'\t' read -r _ job verdict; do
        [ -n "${job:-}" ] || continue
        [ "$verdict" = "absent" ] && continue
        if [ "$verdict" != "read" ]; then
          privileged=1
          reason="write or unrecognized permissions on job '$job'"
        fi
      done < <(fact "$i" J)
      if [ -n "$(fact "$i" R)" ] || [ -n "$(fact "$i" S)" ]; then
        privileged=1
        reason="${reason:+$reason and }stored secrets"
      fi

      if [ "$privileged" -eq 1 ]; then
        if [ -z "$(fact "$i" W)" ]; then
          fail "$file: privileged \`workflow_run\` workflow ($reason) has no \`branches:\` base-branch filter, so a fork PR's workflow can trigger it with the base repo's token"
        fi
        if [ -z "$(fact "$i" H)" ]; then
          fail "$file: privileged \`workflow_run\` workflow ($reason) has no \`github.event.workflow_run.head_repository.full_name == github.repository\` clause, so nothing scopes the trigger to runs this repository produced — a fork PR's run can fire it with the base repo's token"
        fi
        while IFS=$'\t' read -r _ ln; do
          [ -n "${ln:-}" ] || continue
          fail "$file:$ln: privileged \`workflow_run\` workflow ($reason) consumes a PR-produced artifact — the documented artifact-poisoning path"
        done < <(fact "$i" A)
      fi
    fi
  done
fi

# --- the platform matrix (--matrix) -----------------------------------------
#
# A second, narrower pass over the one named workflow, run only once every
# file parsed above, so it can lean on the same block-style subset. It writes
# its own fact file (facts.matrix), whose letters are its own:
#   E <line> <message>              a shape this pass does not model
#   J <job>                         a job
#   O <job> <runs-on>               the job's scalar runs-on
#   C <job> <image>                 the job's container image
#   I <job> <line> <text>           job-level `if:` text, one per value line
#   S <job> <seq>                   a step
#   N <job> <seq> <name>            that step's name
#   K <job> <seq> <line> <text>     step-level `if:` text, one per value line
#   F <line> <value>                a continue-on-error, at any depth
#   H <line> <value>                a shell:, at any depth
#   T <line>                        a content line that swallows a failure
read -r -d '' awk_matrix <<'AWK_MATRIX' || true
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function unquote(s) { sub(/^["']/, "", s); sub(/["']$/, "", s); return s }
# The fact file is tab-separated, so a tab in workflow text becomes a space.
function clean(s) { gsub(/\t/, " ", s); gsub(/[^[:print:]]/, "", s); return s }
# A trailing comment ends a plain value; a quoted value ends at its closing
# quote, so a `#` inside the quotes is content.
function value(v) {
  if (v ~ /^"/) { if (match(v, /^"([^"\\]|\\.)*"/)) return substr(v, 1, RLENGTH); return v }
  if (v ~ /^'/) { if (match(v, /^'([^']|'')*'/)) return substr(v, 1, RLENGTH); return v }
  sub(/[ \t]+#.*$/, "", v)
  return v
}
function emit_if(text) {
  if (if_kind == "job") printf "I\t%s\t%d\t%s\n", cur, NR, clean(text)
  else printf "K\t%s\t%d\t%d\t%s\n", cur, seq, NR, clean(text)
}
BEGIN { section = ""; jobs_child = -1; job_body = -1; cur = ""; bs = 0; if_kind = ""; if_cont = 0 }
{
  line = $0
  sub(/\r$/, "", line)
  if (line ~ /^[ \t]*$/) next
  match(line, /^ */)
  indent = RLENGTH
  rest = substr(line, indent + 1)
  # A whole-line `#` inside a block scalar is its text (a shell comment in a
  # run: body, or part of an if: expression), not a YAML comment.
  if (rest ~ /^#/ && !(bs && indent > bs_indent)) next

  soft = (rest ~ /\|\|[ \t]*(true|:|\/bin\/true|\/usr\/bin\/true|exit[ \t]+0)([ \t;)&|'"}\\]|$)/ ||
          rest ~ /\|\|[ \t]*\{[ \t]*(true|:)[ \t]*;/ ||
          rest ~ /(^|[^A-Za-z0-9_-])set[ \t]+(\+[A-Za-z]*e[A-Za-z]*|\+o[ \t]+errexit)([ \t;)]|$)/)
  # A shell list continues past a trailing `||` (or `|| \`) onto the next line.
  if (or_pending && rest ~ /^(true|:|\/bin\/true|\/usr\/bin\/true|exit[ \t]+0|\{[ \t]*(true|:)[ \t]*;)([ \t;)&|'"}\\]|$)/) soft = 1
  or_pending = (rest ~ /\|\|[ \t]*\\?[ \t]*$/)
  if (soft) printf "T\t%d\n", NR

  if (bs) {
    if (indent > bs_indent) { if (if_kind != "") emit_if(rest); next }
    bs = 0; if_kind = ""
  }
  if (if_cont) {
    if (indent > if_indent) { emit_if(rest); next }
    if_cont = 0; if_kind = ""
  }

  isseq = (rest ~ /^-([ \t]|$)/)
  body = rest; kindent = indent
  if (isseq) {
    if (match(rest, /^-[ \t]+/)) { kindent = indent + RLENGTH; body = substr(rest, RLENGTH + 1) } else body = ""
  }
  haskey = 0; key = ""; val = ""
  if (match(body, /^("[^"]*"|'[^']*'|[A-Za-z_][A-Za-z0-9_.-]*)[ \t]*:([ \t]|$)/)) {
    haskey = 1
    key = trim(substr(body, 1, RLENGTH)); sub(/:$/, "", key); key = unquote(trim(key))
    val = trim(value(trim(substr(body, RLENGTH + 1))))
  }
  scalar = (haskey && val ~ /^[|>]([0-9][+-]?|[+-][0-9]?)?$/)
  if (haskey && key == "continue-on-error") printf "F\t%d\t%s\n", NR, clean(unquote(val))
  if (haskey && val ~ /^[{[]/ && val ~ /continue-on-error/) printf "F\t%d\t%s\n", NR, "a flow mapping"
  if (haskey && key == "shell") printf "H\t%d\t%s\n", NR, clean(unquote(val))

  if (indent == 0) {
    section = (haskey && key == "jobs") ? "jobs" : ""
    jobs_child = -1
    if (scalar) { bs = 1; bs_indent = kindent }
    next
  }
  if (section != "jobs") { if (scalar) { bs = 1; bs_indent = kindent }; next }
  if (isseq && body ~ /^[{[]/) printf "E\t%d\t%s\n", NR, "a flow-style sequence item is outside the matrix pass's subset"

  if (jobs_child < 0) jobs_child = indent
  if (indent == jobs_child && haskey && !isseq) {
    cur = clean(key)
    if (cur !~ /^[A-Za-z_][A-Za-z0-9_-]*$/) printf "E\t%d\t%s\n", NR, "a job id outside GitHub's grammar"
    printf "J\t%s\n", cur
    job_body = -1; in_steps = 0; in_container = 0; steps_item = -1; step_key = -1; seq = 0
    next
  }
  if (job_body < 0) job_body = indent
  if (indent == job_body && !isseq) {
    in_steps = 0; in_container = 0
    if (key == "runs-on") printf "O\t%s\t%s\n", cur, clean(unquote(val))
    else if (key == "container") { if (val != "") printf "C\t%s\t%s\n", cur, clean(unquote(val)); else in_container = 1 }
    else if (key == "if") {
      if_kind = "job"
      if (scalar) { bs = 1; bs_indent = kindent; next }
      emit_if(val); if_cont = 1; if_indent = kindent; next
    }
    else if (key == "steps") { in_steps = 1; steps_item = -1 }
    if (scalar) { bs = 1; bs_indent = kindent }
    next
  }
  if (in_container && haskey && key == "image") { printf "C\t%s\t%s\n", cur, clean(unquote(val)); in_container = 0 }
  if (in_steps && indent >= job_body) {
    stepkey = 0
    if (isseq && (steps_item < 0 || indent == steps_item)) {
      steps_item = indent; step_key = kindent; seq++
      printf "S\t%s\t%d\n", cur, seq
      stepkey = haskey
    } else if (indent == step_key && haskey && !isseq) {
      stepkey = 1
    }
    if (stepkey) {
      if (key == "name") printf "N\t%s\t%d\t%s\n", cur, seq, clean(unquote(val))
      else if (key == "if") {
        if_kind = "step"
        if (scalar) { bs = 1; bs_indent = kindent; next }
        emit_if(val); if_cont = 1; if_indent = kindent; next
      }
    }
  }
  if (scalar) { bs = 1; bs_indent = kindent }
}
AWK_MATRIX

# Judges the fact file in one pass and prints one violation per line. The
# scope REQ-B1.4 gives the Alpine job is held by step name: a step named
# `setup: <what>` prepares the container and is the only other shape allowed.
read -r -d '' awk_judge <<'AWK_JUDGE' || true
function bare(t) {
  t = tolower(t)
  gsub(/^[ \t"']+/, "", t); gsub(/[ \t"']+$/, "", t)
  sub(/^\$\{\{[ \t]*/, "", t); sub(/[ \t]*\}\}$/, "", t)
  return t
}
function run_anyway(t) { t = bare(t); return (t == "always()" || t == "!cancelled()" || t == "success()") }
function platform(t) { return tolower(t) ~ /runner\.os|runner\.arch|matrix\.os|macos|ubuntu|alpine|linux|windows|darwin/ }
function scope(n) { return (n == "shell suite" || n == "install smoke" || n == "bake-off harness") }
# Reading nm[] by subscript would create the entry; every read goes through here.
function stepname(j, s) { return ((j SUBSEP s) in nm) ? nm[j SUBSEP s] : "" }
function v(msg) { printf "%s\n", msg }
BEGIN { FS = "\t"; file = ENVIRON["MATRIX_FILE"] }
$1 == "E" { v(file ":" $2 ": parse failure — " $3) }
$1 == "J" { nj++; job[nj] = $2 }
$1 == "O" { ro[$2] = $3 }
$1 == "C" { if (!($2 in img)) img[$2] = $3 }
$1 == "I" {
  jif[$2] = $3
  if (!run_anyway($4)) gated[$2] = 1
  if (platform($4)) v(file ":" $3 ": job '" $2 "' is gated by an `if:` naming a platform, so that platform can stop running it")
}
$1 == "S" { ns[$2] = $3 }
$1 == "N" { nm[$2 SUBSEP $3] = $4 }
$1 == "K" { nk++; kjob[nk] = $2; kseq[nk] = $3; kline[nk] = $4; ktext[nk] = $5 }
$1 == "F" { if ($3 != "false") v(file ":" $2 ": `continue-on-error` lets a failing step or job pass; every step on every platform must block") }
$1 == "H" {
  if ($3 !~ /^(bash|sh)$/ && $3 !~ /(^|[ \t])-[a-z]*e[a-z]*([ \t]|$)/)
    v(file ":" $2 ": `shell: " $3 "` runs without -e, so every line of a step but the last can fail silently; every step on every platform must block")
}
$1 == "T" { v(file ":" $2 ": a line swallows a failure (`||` onto true, `:`, or exit 0, or `set +e`); every step on every platform must block") }
END {
  nalpine = 0
  for (i = 1; i <= nj; i++) {
    j = job[i]; base = img[j]; sub(/.*\//, "", base)
    if (base ~ /^alpine([:@]|$)/) { kind[j] = "alpine"; nalpine++; alpine_job = (alpine_job == "" ? j : alpine_job " " j) }
    else if (img[j] == "" && ro[j] ~ /^macos-/) kind[j] = "macos"
    else if (img[j] == "" && ro[j] ~ /^ubuntu-/) kind[j] = "ubuntu"
    if ((kind[j] == "macos" || kind[j] == "alpine") && (j in jif))
      v(file ":" jif[j] ": platform job '" j "' carries a job-level `if:`; a matrix job runs on every pull request")
    for (s = 1; s <= ns[j]; s++) if (stepname(j, s) == "install smoke" && !gated[j]) smoke[kind[j]] = 1
    if (kind[j] != "") have[kind[j]] = 1
  }
  for (k = 1; k <= nk; k++) {
    if (platform(ktext[k])) v(file ":" kline[k] ": a step of job '" kjob[k] "' is gated by an `if:` naming a platform, so that platform can skip it")
    n = stepname(kjob[k], kseq[k])
    if (scope(n) && !run_anyway(ktext[k])) v(file ":" kline[k] ": the `" n "` step of job '" kjob[k] "' carries an `if:` that can switch it off; a scope step runs on every pull request")
  }
  if (!have["ubuntu"]) v(file ": no Ubuntu job (runs-on ubuntu-*, no container) — the matrix needs Linux with glibc")
  if (!have["macos"]) v(file ": no macOS job (runs-on macos-*) — the matrix needs the system bash and BSD userland")
  if (nalpine < 1) v(file ": no Alpine job (a container image whose last path component is alpine) — the matrix needs musl with dash and busybox")
  if (nalpine > 1) v(file ": more than one Alpine job (" alpine_job "), so the Alpine scope has no single job to hold to")
  if (have["ubuntu"] && !smoke["ubuntu"]) v(file ": no ungated Ubuntu job carries an `install smoke` step")
  if (have["macos"] && !smoke["macos"]) v(file ": no ungated macOS job carries an `install smoke` step")
  if (nalpine == 1) {
    j = alpine_job; suite = 0; smokes = 0; harness = 0
    for (s = 1; s <= ns[j]; s++) {
      if (!((j SUBSEP s) in nm)) { v(file ": Alpine job '" j "' has a step with no `name:`, so its place in the Alpine scope cannot be read"); continue }
      n = stepname(j, s)
      if (n == "shell suite") suite++
      else if (n == "install smoke") smokes++
      else if (n == "bake-off harness") harness++
      else if (n !~ /^setup: ./)
        v(file ": Alpine job '" j "' step '" n "' is outside the Alpine scope (the shell suite, the bake-off harness, the install smoke, and `setup: ` steps); run it on Ubuntu and name it there")
    }
    if (suite != 1) v(file ": Alpine job '" j "' carries " suite " `shell suite` step(s); the Alpine scope needs exactly one")
    if (smokes != 1) v(file ": Alpine job '" j "' carries " smokes " `install smoke` step(s); the Alpine scope needs exactly one")
    if (harness > 1) v(file ": Alpine job '" j "' carries " harness " `bake-off harness` steps; the Alpine scope allows one")
  }
}
AWK_JUDGE

if [ -n "$matrix" ] && [ "$parse_failed" -eq 0 ]; then
  mfile="$dir/$matrix"
  if [ ! -f "$mfile" ]; then
    fail "$mfile: the platform-matrix workflow is absent, so the matrix cannot be verified (failing closed)"
  elif ! awk "$awk_matrix" "$mfile" >"$work/facts.matrix"; then
    fail "$mfile: awk failed reading the platform matrix"
  elif ! MATRIX_FILE="$mfile" awk "$awk_judge" "$work/facts.matrix" >"$work/matrix.viol"; then
    fail "$mfile: awk failed judging the platform matrix"
  else
    while IFS= read -r m; do
      fail "$m"
    done <"$work/matrix.viol"
  fi
fi

if [ -s "$viol" ]; then
  echo "check-workflow-posture: the workflow posture does not hold (the D-6 fork-PR posture, and the platform matrix under --matrix)." >&2
  cat "$viol" >&2
  exit 1
fi

if [ -n "$matrix" ]; then
  echo "check-workflow-posture: $nfiles workflow file(s) under '$dir' hold the D-6 fork-PR posture, and '$matrix' holds the platform matrix."
else
  echo "check-workflow-posture: $nfiles workflow file(s) under '$dir' hold the D-6 fork-PR posture."
fi
exit 0
