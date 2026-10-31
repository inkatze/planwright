# shellcheck shell=bash
# two-repo-fixture.sh — a sourced harness: work repositories `alpha` and
# `beta` registered in a fixture work-repository registry against a marked
# spec root (project `hub`) at $TRF/holder/specs, held by a third repository,
# plus a gh stub on PATH reading $TRF/gh/<repo>.tsv (headRefName, state,
# number, mergedAt) and failing for a repository with $TRF/gh/<repo>.fail.
# Built to be shared with custom-spec-location's holder-dispatch tests.
#
# Usage: trf_setup <scripts-dir> [<spec>], then run every command through
# trf_env, which pins HOME, the plugin data home, the config layers, and git's
# config to the fixture.
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

trf_env() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_BASE_REF \
    -u PLANWRIGHT_ORCH_STATE_DIR -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE \
    HOME="$TRF/home" CLAUDE_PLUGIN_DATA="$TRF/pdata" \
    PLANWRIGHT_CONFIG_DEFAULTS="$TRF/core.yml" PLANWRIGHT_ADOPTER_OVERLAY="$TRF/adopter" \
    GIT_CEILING_DIRECTORIES="$TRF" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    TRF_GH="$TRF/gh" PATH="$TRF/ghstub:$PATH" "$@"
}

trf_git() {
  trf_env git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
    -c init.defaultBranch=main "$@" >/dev/null 2>&1
}

trf_repo() {
  mkdir -p "$1"
  trf_git -C "$1" init -q
  trf_git -C "$1" commit -q --allow-empty -m init
  [ -z "${2:-}" ] || trf_git -C "$1" remote add origin "$2"
}

# trf_setup <script-dir> [<spec>] — build the layout with an empty bundle
# directory for <spec> (default demo) and register both work repositories.
trf_setup() {
  TRF_SCRIPTS=$1
  TRF_SPEC=${2:-demo}
  TRF=$(cd "$(mktemp -d)" && pwd -P) || return 1
  mkdir -p "$TRF/home" "$TRF/adopter" "$TRF/pdata" "$TRF/ghstub" "$TRF/gh"
  printf 'unrelated_key: 1\n' >"$TRF/core.yml"
  # shellcheck disable=SC2016 # the stub's own expansions
  printf '%s\n' '#!/bin/sh' \
    'r=${PWD##*/}' \
    '[ ! -e "$TRF_GH/$r.fail" ] || { echo "gh: simulated failure" >&2; exit 1; }' \
    '[ ! -f "$TRF_GH/$r.tsv" ] || cat "$TRF_GH/$r.tsv"' >"$TRF/ghstub/gh"
  chmod +x "$TRF/ghstub/gh"
  trf_repo "$TRF/holder"
  TRF_ROOT=$TRF/holder/specs
  mkdir -p "$TRF_ROOT/$TRF_SPEC"
  printf 'project: hub\nlayout: 1\n' >"$TRF_ROOT/planwright-spec-root.yml"
  for r in alpha beta; do
    trf_repo "$TRF/src/$r" "https://example.invalid/acme/$r.git"
    mkdir -p "$TRF/src/$r/.claude"
    printf 'spec_root: %s\n' "$TRF_ROOT" >"$TRF/src/$r/.claude/planwright.local.yml"
    trf_register "$r" || return 1
  done
}

trf_teardown() {
  [ -z "${TRF:-}" ] || rm -rf "$TRF"
}

# trf_bundle <tasks.md-body> — write the bundle: a Ready requirements.md and
# a version 3 tasks.md whose body (task blocks and human-payload sections)
# is the argument.
trf_bundle() {
  printf '# Demo — Requirements\n\n**Status:** Ready\n**Format-version:** 3\n' \
    >"$TRF_ROOT/$TRF_SPEC/requirements.md"
  printf '# Demo — Tasks\n\n**Status:** Ready\n**Format-version:** 3\n\n## Tasks\n\n%s\n' "$1" \
    >"$TRF_ROOT/$TRF_SPEC/tasks.md"
}

# trf_branch <repo> <id> — a task branch with one commit beyond main, left
# unmerged (in-progress evidence in that repository).
trf_branch() {
  trf_git -C "$TRF/src/$1" checkout -q -b "planwright/$TRF_SPEC/task-$2" main
  trf_git -C "$TRF/src/$1" commit -q --allow-empty -m "task $2 work"
  trf_git -C "$TRF/src/$1" checkout -q main
}

# trf_pr <repo> <id> <state> [<number>] — a pull request row for the task's
# branch in that repository's stub evidence.
trf_pr() {
  printf 'planwright/%s/task-%s\t%s\t%s\t%s\n' "$TRF_SPEC" "$2" "$3" "${4:-7}" \
    "$([ "$3" = MERGED ] && printf '2026-10-30T00:00:00Z')" >>"$TRF/gh/$1.tsv"
}

trf_fail_gh() { : >"$TRF/gh/$1.fail"; }
trf_heal_gh() { rm -f "$TRF/gh/$1.fail"; }
trf_reset_evidence() {
  rm -f "$TRF/gh/"*.tsv "$TRF/gh/"*.fail
  for r in alpha beta; do
    for b in $(trf_env git -C "$TRF/src/$r" for-each-ref --format='%(refname:short)' "refs/heads/planwright/"); do
      trf_git -C "$TRF/src/$r" branch -q -D "$b"
    done
  done
}

# trf_unregister <repo> — drop a repository's row from the fixture registry,
# so its alias resolves to nothing; trf_register puts it back.
trf_unregister() {
  awk -F'\t' -v r="$1" '$3 != r' "$TRF/pdata/work-repos/registry.tsv" >"$TRF/registry.tmp" \
    && mv "$TRF/registry.tmp" "$TRF/pdata/work-repos/registry.tsv"
}
trf_register() {
  (cd "$TRF/src/$1" && trf_env /bin/sh "$TRF_SCRIPTS/work-repo-registry.sh" register >/dev/null 2>&1)
}
