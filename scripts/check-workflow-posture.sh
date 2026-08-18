#!/usr/bin/env bash
# check-workflow-posture.sh — the fork-PR posture guard (guard-coverage Task 4;
# D-6; REQ-C1.1, REQ-C1.2, REQ-H1.3).
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
#      `secrets: inherit`. The workflow's own `secrets.GITHUB_TOKEN` is exempt
#      — it is not a stored secret, and its privilege is governed by assertion
#      2. Reachability follows local reusable-workflow `uses:` edges.
#   4. Any `workflow_run` workflow holding write permissions or secrets keeps a
#      base-branch filter and consumes no PR-produced artifact. A `workflow_run`
#      fired by a fork PR's workflow runs with the base repo's secrets and write
#      token, so an unfiltered one — or one that unpacks an artifact the PR
#      produced — is the documented cache/artifact-poisoning path.
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
# keys, and flow mappings as the value of a structural key are NOT modeled and
# are reported as parse failures rather than half-read. Job-level keys are read
# only at the job's own body indent, so a step's `uses:` is never mistaken for
# a reusable-workflow call. Block-scalar bodies are skipped for STRUCTURE (a
# `- run: |` script is text, and a line reading `name: &anchor` in it is shell)
# but still scanned as TEXT for secret and artifact references. Full-line
# comments are skipped by both; a trailing comment is scanned, so a comment
# mentioning `secrets.FOO` over-blocks — the fail-loud direction, and cheaper
# than deciding whether a `#` sits inside a quoted string.
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
# Usage: check-workflow-posture.sh [<workflows-dir>]
#   Default: <repo-root>/.github/workflows (the repo root is derived from this
#   script's location, so a bare invocation works from any directory).
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

if [ $# -gt 1 ]; then
  echo "usage: check-workflow-posture.sh [<workflows-dir>]" >&2
  exit 2
fi

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
read -r -d '' awk_parser <<'AWK_PARSER' || true
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function unquote(s) { sub(/^["']/, "", s); sub(/["']$/, "", s); return s }
function err(msg) { printf "E\t%d\t%s\n", NR, msg; errs++ }
# read-all / write-all / {} are the three scalar permission spellings; anything
# else (including a bare `permissions:` with no entries) is unknown, and the
# driver treats unknown exactly like write.
function scalar_perm(v) {
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
function record_trigger(t) {
  t = unquote(trim(t))
  sub(/:$/, "", t)
  if (t == "") return
  printf "T\t%s\n", t
  ntrig++
  cur_trigger = t
}
# `on: push`, `on: [push, pull_request]`. A flow MAPPING is not modeled.
function inline_triggers(v,   inner, n, parts, i) {
  if (v ~ /^\{/) { err("flow-mapping `on:` value is outside the parsed subset"); return }
  if (v ~ /^\[.*\]$/) {
    inner = substr(v, 2, length(v) - 2)
    n = split(inner, parts, ",")
    for (i = 1; i <= n; i++) record_trigger(parts[i])
    return
  }
  record_trigger(v)
}
BEGIN {
  section = ""; on_child = -1; perm_child = -1; jobs_child = -1
  job_body = -1; jperm_child = -1; in_jperm = 0
  top_perm = "absent"; top_perm_n = 0
  cur_job = ""; njobs = 0; ntrig = 0; errs = 0; fatal = 0
  bs = 0; bs_indent = -1; ndocs = 0; seen_content = 0
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
  # structured value can.
  s = rest
  while (match(s, /secrets[ \t]*(\.[A-Za-z_][A-Za-z0-9_]*|\[[ \t]*["'][A-Za-z_][A-Za-z0-9_]*["'][ \t]*\])/)) {
    tok = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    sub(/^secrets[ \t]*/, "", tok)
    gsub(/[^A-Za-z0-9_]/, "", tok)
    if (tok != "GITHUB_TOKEN") printf "R\t%d\t%s\n", NR, tok
  }
  if (rest ~ /download-artifact/ || rest ~ /gh[ \t]+run[ \t]+download/) printf "A\t%d\n", NR

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
  if ((haskey && val ~ /^[|>][0-9]*[+-]?$/) ||
      (isseq && rest ~ /:[ \t]*[|>][0-9]*[+-]?[ \t]*$/) ||
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
      } else if (key == "secrets" && val == "inherit") {
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
        while IFS=$'\t' read -r _ ln; do
          [ -n "${ln:-}" ] || continue
          fail "$file:$ln: privileged \`workflow_run\` workflow ($reason) consumes a PR-produced artifact — the documented artifact-poisoning path"
        done < <(fact "$i" A)
      fi
    fi
  done
fi

if [ -s "$viol" ]; then
  echo "check-workflow-posture: the fork-PR posture pinned by D-6 (REQ-C1.2) does not hold." >&2
  cat "$viol" >&2
  exit 1
fi

echo "check-workflow-posture: $nfiles workflow file(s) under '$dir' hold the D-6 fork-PR posture."
exit 0
