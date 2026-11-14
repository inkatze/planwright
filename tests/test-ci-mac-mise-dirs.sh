#!/bin/bash
# Tests that no two macOS CI jobs running at once on one host can share mise's
# directories. The self-hosted Mac runners on a host all run under one account,
# so under mise's defaults every concurrent shard installs into one
# ~/.local/share/mise and rewrites one bin/mise; a shard spawning mise mid-write
# dies with "spawn Unknown system error -88" (EBADMACHO).
#
# Every macOS job must run its `setup: per-runner mise directories` step before
# mise-action, and that step, run for two runners, must export a different
# MISE_DATA_DIR, MISE_CACHE_DIR and MISE_STATE_DIR for each. mise-action takes
# its binary and cache path from MISE_DATA_DIR, so nothing else in the workflow
# may set those variables or the action's `mise_dir` input. The step body is run
# here with bash -e, as a GitHub `run:` is on a Mac, under a scratch HOME.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
SETUP_NAME="setup: per-runner mise directories"
VARS="MISE_DATA_DIR MISE_CACHE_DIR MISE_STATE_DIR"

failures=0
pass() { printf 'ok: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# One fact per line, tab-separated:
#   M <job>                      a job whose runs-on names a Mac
#   A <job> <line>               the job's mise-action step
#   S <job> <line> <from> <to>   the setup step and its run: body's lines
#   V <job> <line>               a line outside comments naming a mise
#                                directory variable or the mise_dir input
read -r -d '' facts_awk <<'AWK' || true
function close_step() {
  if (step_is_setup && body_from) printf "S\t%s\t%d\t%d\t%d\n", job, step_line, body_from, body_to
  step_is_setup = 0; body_from = 0; body_to = 0; in_body = 0
}
{
  line = $0
  match(line, /^ */); indent = RLENGTH
  rest = substr(line, indent + 1)
  if (in_body) {
    if (rest == "" || indent > step_indent + 2) { if (rest != "") body_to = NR; next }
    in_body = 0
  }
  if (rest == "" || rest ~ /^#/) next
  if (indent == 0) { close_step(); in_jobs = (rest ~ /^jobs:[ \t]*$/); job = ""; next }
  if (in_jobs && indent == 2 && rest ~ /^[A-Za-z0-9_-]+:[ \t]*$/) {
    close_step(); job = rest; sub(/:.*/, "", job); next
  }
  if (rest ~ /(MISE_DATA_DIR|MISE_CACHE_DIR|MISE_STATE_DIR|mise_dir)/)
    printf "V\t%s\t%d\n", job, NR
  if (job == "") next
  if (indent == 4 && rest ~ /^runs-on:/ && tolower(rest) ~ /macos/) printf "M\t%s\n", job
  if (rest ~ /^- /) { close_step(); step_line = NR; step_indent = indent; rest = substr(rest, 3) }
  if (rest ~ /^uses:[ \t]*jdx\/mise-action@/) printf "A\t%s\t%d\n", job, NR
  if (rest ~ /^name:/) {
    n = rest; sub(/^name:[ \t]*/, "", n); gsub(/^["']|["']$/, "", n)
    if (n == ENVIRON["SETUP_NAME"]) step_is_setup = 1
  }
  if (rest ~ /^run:[ \t]*\|[ \t]*$/) { in_body = 1; body_from = NR + 1; body_to = NR }
}
END { close_step() }
AWK

run_body() { # <case> <runner-environment, or - for unset> <runner-name>
  mkdir -p "$tmp/home.$1"
  : >"$tmp/env.$1"
  if [ "$2" = - ]; then
    env -u RUNNER_ENVIRONMENT HOME="$tmp/home.$1" GITHUB_ENV="$tmp/env.$1" RUNNER_NAME="$3" \
      /bin/bash -e "$body" >"$tmp/out.$1" 2>&1
  else
    env HOME="$tmp/home.$1" GITHUB_ENV="$tmp/env.$1" RUNNER_ENVIRONMENT="$2" RUNNER_NAME="$3" \
      /bin/bash -e "$body" >"$tmp/out.$1" 2>&1
  fi
}
value() { sed -n "s/^$2=//p" "$tmp/env.$1" | tail -n 1; }

# check <workflow> — prints one violation per line; prints nothing when every
# macOS job keys mise's directories on its runner.
check() {
  wf="$1"
  facts="$tmp/facts"
  SETUP_NAME="$SETUP_NAME" awk "$facts_awk" "$wf" >"$facts" || {
    echo "awk failed reading $wf"
    return
  }
  awk -F'\t' '$1 == "V" && $2 == "" { print "line " $3 " sets a mise directory for the whole workflow" }' "$facts"
  jobs="$(awk -F'\t' '$1 == "M" { print $2 }' "$facts")"
  if [ -z "$jobs" ]; then
    echo "no macOS job found, so nothing was checked"
    return
  fi
  for j in $jobs; do
    action="$(awk -F'\t' -v j="$j" '$1 == "A" && $2 == j { print $3; exit }' "$facts")"
    setup="$(awk -F'\t' -v j="$j" '$1 == "S" && $2 == j { print $3 "\t" $4 "\t" $5; exit }' "$facts")"
    if [ -z "$action" ]; then
      echo "$j: no jdx/mise-action step"
      continue
    fi
    if [ -z "$setup" ]; then
      echo "$j: no '$SETUP_NAME' step with a run: | body, so its shards share ~/.local/share/mise"
      continue
    fi
    sline="${setup%%	*}"
    range="${setup#*	}"
    from="${range%%	*}"
    to="${range#*	}"
    if [ "$sline" -gt "$action" ]; then
      echo "$j: '$SETUP_NAME' runs after mise-action, which has already installed into the shared directory"
    fi
    # The run: body's own lines are skipped by the parser, so every V fact
    # in the job is outside the setup step.
    awk -F'\t' -v j="$j" '$1 == "V" && $2 == j { print j ": line " $3 " sets a mise directory outside the setup step" }' "$facts"
    body="$tmp/body.$j.sh"
    sed -n "${from},${to}p" "$wf" | awk 'NR == 1 { match($0, /^ */); n = RLENGTH } { print substr($0, n + 1) }' >"$body"
    run_body a self-hosted inkatze-planwright-1 || echo "$j: the setup step failed for a named runner: $(cat "$tmp/out.a")"
    run_body b self-hosted "inkatze planwright 2" || echo "$j: the setup step failed for a runner name with spaces: $(cat "$tmp/out.b")"
    run_body c - inkatze-planwright-3 || echo "$j: the setup step failed with RUNNER_ENVIRONMENT unset: $(cat "$tmp/out.c")"
    for v in $VARS; do
      va="$(value a "$v")"
      vb="$(value b "$v")"
      vc="$(value c "$v")"
      case "$va" in
        "$tmp"/home.a/?*) ;;
        *) echo "$j: $v for runner inkatze-planwright-1 is '$va', not a directory under HOME" ;;
      esac
      case "$vb" in
        *" "*) echo "$j: $v for a runner name with spaces keeps the spaces: '$vb'" ;;
        "") echo "$j: $v is not exported for a second runner" ;;
      esac
      [ -n "$vc" ] || echo "$j: $v is not exported when RUNNER_ENVIRONMENT is unset; only a hosted Mac may keep the defaults"
      if [ -n "$va" ] && [ "${va#"$tmp"/home.a}" = "${vb#"$tmp"/home.b}" ]; then
        echo "$j: two runners get the same $v (${va#"$tmp"/home.a} under HOME)"
      fi
    done
    run_body d github-hosted "GitHub Actions 7" || echo "$j: the setup step failed on a hosted Mac: $(cat "$tmp/out.d")"
    [ -s "$tmp/env.d" ] && echo "$j: a hosted Mac (one job per machine) moves mise's directories, so its saved cache path no longer matches"
    : >"$tmp/env.e"
    if env HOME="$tmp/home.a" GITHUB_ENV="$tmp/env.e" RUNNER_ENVIRONMENT=self-hosted RUNNER_NAME= \
      /bin/bash -e "$body" >"$tmp/out.e" 2>&1; then
      echo "$j: the setup step passes for a runner with no name, which keys every such runner the same"
    fi
  done
}

expect_clean() { # <label> <workflow>
  out="$(check "$2")"
  if [ -z "$out" ]; then pass "$1"; else fail "$1: $out"; fi
}
expect_caught() { # <label> <workflow> <expected text>
  out="$(check "$2")"
  case "$out" in
    *"$3"*) pass "$1" ;;
    *) fail "$1: expected '$3' in: ${out:-<no violation>}" ;;
  esac
}

expect_clean "every macOS job in ci.yml keys mise's directories on its runner" "$WORKFLOW"

# Each mutation is a regression the check must catch.
grep -v "$SETUP_NAME" "$WORKFLOW" >"$tmp/no-setup.yml"
expect_caught "a macOS job with no setup step is caught" "$tmp/no-setup.yml" "so its shards share"

# shellcheck disable=SC2016 # the pattern is workflow text, so `$` is literal
sed 's/\$RUNNER_NAME/fixed/' "$WORKFLOW" >"$tmp/unkeyed.yml"
expect_caught "a setup step not keyed on the runner is caught" "$tmp/unkeyed.yml" "two runners get the same MISE_DATA_DIR"

awk '/jdx\/mise-action@/ { print; print "        with:"; print "          mise_dir: /tmp/shared"; skip = 1; next } skip && /^        with:/ { skip = 0; next } { skip = 0; print }' \
  "$WORKFLOW" >"$tmp/mise-dir.yml"
expect_caught "a mise_dir input beside the setup step is caught" "$tmp/mise-dir.yml" "sets a mise directory outside the setup step"

# Moves each setup step to just after the step that follows it (mise-action).
awk -v name="$SETUP_NAME" '
  state == 0 && index($0, name) { n = 0; held[++n] = $0; state = 1; next }
  state == 1 && /^      - / { print; state = 2; next }
  state == 1 { held[++n] = $0; next }
  state == 2 && /^      - / { for (i = 1; i <= n; i++) print held[i]; state = 0 }
  { print }
' "$WORKFLOW" >"$tmp/late.yml"
expect_caught "a setup step after mise-action is caught" "$tmp/late.yml" "runs after mise-action"

if [ "$failures" -gt 0 ]; then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all ci mac mise-dir tests passed"
