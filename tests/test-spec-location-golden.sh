#!/bin/bash
# The spec-location golden fixture: with every new option unset, the scripts
# the spec-location migration moves onto the resolver keep printing the same
# paths and messages, from a primary checkout and from a worktree, except for
# the named corrections each migration task declares.
#
# Three halves:
#   * the probes: each migrated script run against a fixture repository and
#     replayed against tests/fixtures/spec-location-golden/baseline.txt,
#     overridden by the expected-change sets under changes/ and checked against
#     the correction registry (tests/lib/golden-replay.sh holds the rules);
#   * the bundles: every in-repo bundle at the baseline commit recomputes the
#     content anchor recorded in anchors.tsv, and every fragment archived at
#     that commit still carries its Consumed-by lines;
#   * the comparator itself, on planted records.
#
# The baseline was captured from the pre-migration scripts and is never
# regenerated from the current tree: a changed output is a declaration in the
# changing task's set, which is the conversation this fixture exists to force.
# `--record-probes` and `--record-anchors` print a fresh capture on stdout for
# a reviewer to diff against the committed files.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
FIXTURE="$REPO_ROOT/tests/fixtures/spec-location-golden"
# The pre-migration main the baseline was captured from.
BASELINE_COMMIT=821fb2f8d063646e5b26d123da91fb576918b954
S="$REPO_ROOT/scripts"

# shellcheck source=tests/lib/golden-replay.sh
. "$REPO_ROOT/tests/lib/golden-replay.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/spec-location-golden.XXXXXX")" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Hermetic environment: no inherited roots or overlay pointers, a private HOME,
# git discovery fenced at $tmp, and fixed identities and dates so commit ids
# are stable across machines.
hermetic() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u TMUX -u TMUX_PANE \
    HOME="${GOLDEN_HOME:-$tmp/home}" GIT_CEILING_DIRECTORIES="$tmp" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
    "$@"
}

# make_fixture <dir> — a repository holding one Ready format-version 2 bundle
# with a valid sign-off anchor, an empty observation store, a machine-local
# overlay the primary checkout sees, and a linked worktree at the placement
# path planwright uses.
make_fixture() {
  mf_p=$1
  hermetic git -c init.defaultBranch=main init -q "$mf_p" || return 1
  mf_d=$mf_p/specs/demo
  mkdir -p "$mf_d" "$mf_p/.claude" || return 1
  printf '# Demo — Requirements\n\n**Status:** Ready\n**Format-version:** 2\n\n## Goal\n\nA fixture.\n' >"$mf_d/requirements.md"
  printf '# Demo — Design\n\nA fixture.\n' >"$mf_d/design.md"
  printf '# Demo — Test spec\n\nA fixture.\n' >"$mf_d/test-spec.md"
  cat >"$mf_d/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2

## Tasks

### Task 1 — the unit

- **Deliverables:** a thing
- **Done when:** the thing exists
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day
EOF
  mf_anchor=$(cd "$mf_p" && hermetic "$S/spec-anchor.sh" specs/demo) || return 1
  cat >"$mf_d/kickoff-brief.md" <<EOF
# Demo — Kickoff brief

## Amendment log

Class: expression-only
Anchor: \`$mf_anchor\` — computed as
\`scripts/spec-anchor.sh specs/demo\`
EOF
  hermetic git -C "$mf_p" add -A && hermetic git -C "$mf_p" commit -q -m init || return 1
  printf 'review_sequence: [polish, self-review]\ndispatch_isolation: per-unit\n' \
    >"$mf_p/.claude/planwright.local.yml"
  hermetic git -C "$mf_p" worktree add -q "$mf_p/.claude/worktrees/wt" -b wt 2>/dev/null || return 1
  # Untracked, as a store with no fragments yet is.
  mkdir -p "$mf_p/specs/_observations/entries" "$mf_p/.claude/worktrees/wt/specs/_observations/entries"
}

# normalize <fixture-tmp> — machine paths to placeholders, minted observation
# ids and today's date to stable tokens.
normalize() {
  sed -e "s#$2/primary/.claude/worktrees/wt#<WORKTREE>#g" \
    -e "s#$2/primary#<PRIMARY>#g" -e "s#$REPO_ROOT#<INSTALL>#g" -e "s#$2#<TMP>#g" \
    -e "s#$(date -u +%Y-%m-%d)#<TODAY>#g" -e "s#$(date +%Y-%m-%d)#<TODAY>#g" \
    -e 's#-[0-9a-f]\{8\}\.md#-<UID>.md#g' -e 's#uid [0-9a-f]\{8\}#uid <UID>#g'
}

# The single-quoted `sh -c` bodies expand their positional arguments in the
# child shell, which is the point.
# shellcheck disable=SC2016
# record_vantage <vantage> <fixture-tmp> — run every probe from the vantage's
# directory and print the records. Probes run in order: the dispatch probe
# creates a worktree, so it runs last.
record_vantage() {
  rv_v=$1 rv_t=$2
  case $rv_v in
    primary) rv_dir=$rv_t/primary ;;
    worktree) rv_dir=$rv_t/primary/.claude/worktrees/wt ;;
  esac
  mkdir -p "$rv_t/empty" "$rv_t/venture" "$rv_t/fleet"
  # probe <name> <command...> — run with the install root pinned to this tree.
  probe() {
    pr_name=$1
    shift
    printf '@@ %s %s\n' "$pr_name" "$rv_v"
    (
      cd "$rv_dir" && hermetic PLANWRIGHT_ROOT="$REPO_ROOT" "$@" 2>&1
      echo "rc=$?"
    ) | normalize "$rv_v" "$rv_t"
  }
  # The install-root chain with no explicit root and a content-less plugin
  # arm: the arm the chain convergence starts skipping with a warning.
  probe rule-doc-contentless-arm env -u PLANWRIGHT_ROOT CLAUDE_PLUGIN_ROOT="$rv_t/empty" \
    "$S/resolve-rule-doc.sh" --explain spec-format
  probe rule-doc "$S/resolve-rule-doc.sh" --explain spec-format
  probe config-get "$S/config-get.sh" --explain review_sequence
  probe review-sequence "$S/resolve-review-sequence.sh"
  probe config-knob "$S/resolve-config-knob.sh" --key dispatch_isolation --type enum \
    --values 'per-step per-unit' --fallback per-step
  probe overlay-repo-tracked "$S/resolve-overlay-root.sh" repo-tracked
  probe overlay-machine-local "$S/resolve-overlay-root.sh" machine-local
  # The layers entries came from, not the entries: the catalog's content is
  # outside this fixture's concern.
  probe catalog sh -c '"$1" decision-domains --explain | cut -f2 | sort -u' sh "$S/resolve-catalog.sh"
  probe spec-root "$S/resolve-root.sh" spec --explain
  probe inception-scaffold "$S/inception-scaffold.sh" "$rv_t/venture"
  probe anchor-freshness "$S/check-anchor-freshness.sh" specs
  probe ledger "$S/check-ledger.sh" specs/demo/tasks.md
  probe memory-links "$S/check-memory-links.sh" specs/demo
  probe state "$S/orchestrate-state.sh" specs/demo
  probe status "$S/spec-status.sh" specs/demo
  probe meta-select "$S/orchestrate-meta-select.sh" specs/demo
  probe tasks-pr-sync "$S/tasks-pr-sync.sh" reconcile specs/demo
  probe migrate-status "$S/migrate-status-lifecycle.sh" specs
  probe lock sh -c '"$1" acquire specs/demo && find specs -name "*.lock*" && "$1" release specs/demo' \
    sh "$S/orchestrate-lock.sh"
  probe marker sh -c '"$1" write specs/demo 1 && "$1" clear specs/demo 1' sh "$S/orchestrate-marker.sh"
  probe trailers sh -c 'printf "feat: x\n" | "$1" demo/1' sh "$S/planwright-commit-trailers.sh"
  probe fence-refname "$S/fleet-fence.sh" refname --spec demo 1
  probe fence-check "$S/fleet-fence.sh" check --checkout "$rv_dir" --spec demo 1
  probe dispatch-fetch "$S/dispatch-fetch.sh" --spec specs/demo .
  probe watchdog env PLANWRIGHT_FLEET_STATE_DIR="$rv_t/fleet" \
    "$S/fleet-tower-watchdog.sh" "$rv_dir/specs/demo"
  probe observations sh -c '"$1/obs-record.sh" --slug fixture --scope fixture --text "a fixture observation" >/dev/null &&
    ls specs/_observations/entries && "$1/check-obs.sh" && "$1/obs-render.sh" &&
    "$1/observation-carry.sh" --dry-run . &&
    uid=$(ls specs/_observations/entries | sed "s/.*-\([0-9a-f]\{8\}\)\.md$/\1/") &&
    "$1/obs-consume.sh" --uid "$uid" --spec demo --today 2026-01-01 &&
    grep -rh "^Consumed-by:" specs/_observations' sh "$S"
  probe dispatch-worktree "$S/fleet-dispatch-worktree.sh" dispatch demo 1 --no-attach
}

# record_probes — both vantages, each in its own fixture so a probe's side
# effects from one vantage never reach the other.
record_probes() {
  mkdir -p "$tmp/home"
  for rp_v in primary worktree; do
    (
      GOLDEN_HOME=$tmp/$rp_v/home
      mkdir -p "$GOLDEN_HOME" && make_fixture "$tmp/$rp_v/primary" \
        && record_vantage "$rp_v" "$tmp/$rp_v" >"$tmp/$rp_v.rec"
    ) &
  done
  wait
  cat "$tmp/primary.rec" "$tmp/worktree.rec"
}

# record_anchors — every bundle at the baseline commit, `<bundle> TAB <anchor>`.
record_anchors() {
  git -C "$REPO_ROOT" cat-file -e "$BASELINE_COMMIT^{commit}" 2>/dev/null || {
    echo "baseline commit $BASELINE_COMMIT is not in this clone's history (a shallow clone?)" >&2
    return 2
  }
  mkdir -p "$tmp/at-baseline"
  git -C "$REPO_ROOT" archive "$BASELINE_COMMIT" specs | tar -x -C "$tmp/at-baseline" || return 2
  for ra_d in "$tmp/at-baseline/specs"/*/; do
    ra_b=$(basename "$ra_d")
    case $ra_b in _*) continue ;; esac
    (cd "$tmp/at-baseline" && "$S/spec-anchor.sh" "specs/$ra_b" >"$tmp/anchor.$ra_b" 2>&1) &
  done
  wait
  for ra_d in "$tmp/at-baseline/specs"/*/; do
    ra_b=$(basename "$ra_d")
    case $ra_b in _*) continue ;; esac
    printf '%s\t%s\n' "$ra_b" "$(cat "$tmp/anchor.$ra_b")"
  done
}

case "${1:-}" in
  --record-probes)
    record_probes
    exit
    ;;
  --record-anchors)
    record_anchors
    exit
    ;;
  "") ;;
  *)
    echo "usage: $0 [--record-probes | --record-anchors]" >&2
    exit 2
    ;;
esac

# --- The comparator on planted records --------------------------------------

planted=$tmp/planted
mkdir -p "$planted/changes"
printf 'comment\n@@ a primary\none\n@@ b primary\ntwo\n' >"$planted/baseline.txt"
printf 'fix-a\t3\tREQ-X\nfix-b\t5\tREQ-Y\nold\tbaseline\tREQ-Z\n' >"$planted/registry.tsv"
printf '@@ a primary\none\n@@ b primary\ntwo\n' >"$planted/same.txt"
printf '@@ a primary\nONE\n@@ b primary\ntwo\n' >"$planted/a-changed.txt"
replay() { golden_replay "$planted/baseline.txt" "$planted/changes" "$planted/registry.tsv" "$1" 2>&1; }

if out=$(replay "$planted/same.txt"); then ok "comparator: unchanged output with no declared set passes"; else fail "comparator: unchanged output failed: $out"; fi

if out=$(replay "$planted/a-changed.txt"); then
  fail "comparator: an undeclared difference passed"
else
  case $out in *"a primary differs"*) ok "comparator: an undeclared difference fails" ;; *) fail "comparator: undeclared difference misreported: $out" ;; esac
fi

printf '# the pre-migration task declares nothing\n' >"$planted/changes/task-4.txt"
if out=$(replay "$planted/same.txt"); then ok "comparator: an empty declared set passes on unchanged output"; else fail "comparator: empty set failed: $out"; fi

printf '@@ a primary fix-a\nONE\n' >"$planted/changes/task-3.txt"
if out=$(replay "$planted/a-changed.txt"); then ok "comparator: a declared difference passes"; else fail "comparator: declared difference failed: $out"; fi
if out=$(replay "$planted/same.txt"); then
  fail "comparator: a declared change that did not happen passed"
else
  ok "comparator: a declared change that did not happen fails"
fi

printf '# declares nothing\n' >"$planted/changes/task-5.txt"
if out=$(replay "$planted/a-changed.txt"); then
  fail "comparator: a declared set omitting its correction passed"
else
  case $out in *"'fix-b' is absent from task 5"*) ok "comparator: a declared set omitting its correction fails" ;; *) fail "comparator: omitted correction misreported: $out" ;; esac
fi
rm -f "$planted/changes/task-5.txt"

printf '@@ a primary fix-a\nONE\n@@ b primary old\ntwo\n' >"$planted/changes/task-3.txt"
if out=$(replay "$planted/a-changed.txt"); then
  fail "comparator: a baseline-owned correction in a set passed"
else
  case $out in *"assigns to baseline"*) ok "comparator: a correction owned by the baseline cannot be declared" ;; *) fail "comparator: baseline correction misreported: $out" ;; esac
fi

printf '@@ a primary fix-a\nONE\n@@ c primary fix-a\nx\n' >"$planted/changes/task-3.txt"
if out=$(replay "$planted/a-changed.txt"); then
  fail "comparator: a set naming an unrecorded probe passed"
else
  case $out in *"c primary, which the baseline does not record"*) ok "comparator: a set naming an unrecorded probe fails" ;; *) fail "comparator: unrecorded probe misreported: $out" ;; esac
fi

printf '@@ a primary unknown\nONE\n' >"$planted/changes/task-3.txt"
if out=$(replay "$planted/a-changed.txt"); then
  fail "comparator: an unregistered correction passed"
else
  case $out in *"unregistered correction 'unknown'"*) ok "comparator: an unregistered correction fails" ;; *) fail "comparator: unregistered correction misreported: $out" ;; esac
fi

printf '@@ a primary fix-a\nONE\n' >"$planted/changes/task-3.txt"
printf '@@ a primary fix-b\nUNO\n' >"$planted/changes/task-5.txt"
printf '@@ a primary\nUNO\n@@ b primary\ntwo\n' >"$planted/a-twice.txt"
if out=$(replay "$planted/a-twice.txt"); then ok "comparator: later sets override earlier ones in task order"; else fail "comparator: set ordering failed: $out"; fi
rm -f "$planted/changes/task-5.txt"

printf '@@ a primary\none\n' >"$planted/missing.txt"
if out=$(replay "$planted/missing.txt"); then
  fail "comparator: a recording missing a probe passed"
else
  ok "comparator: a recording missing a probe fails"
fi

# --- The probes -------------------------------------------------------------

record_probes >"$tmp/actual.txt"
if out=$(golden_replay "$FIXTURE/baseline.txt" "$FIXTURE/changes" "$FIXTURE/corrections.tsv" "$tmp/actual.txt" 2>&1); then
  ok "probes: every migrated script matches the baseline plus the declared sets"
else
  fail "probes: replay against the baseline failed:
$out"
fi

if [ -f "$FIXTURE/changes/task-4.txt" ] && ! grep -q '^@@ ' "$FIXTURE/changes/task-4.txt"; then
  ok "probes: the pre-migration task's set is declared and empty"
else
  fail "probes: changes/task-4.txt must exist and declare nothing"
fi

# --- The bundles ------------------------------------------------------------

if record_anchors >"$tmp/anchors.tsv"; then
  grep -v '^#' "$FIXTURE/anchors.tsv" >"$tmp/anchors.expected"
  if diff -u "$tmp/anchors.expected" "$tmp/anchors.tsv" >"$tmp/anchors.diff"; then
    ok "bundles: every bundle at the baseline commit recomputes its recorded anchor"
  else
    fail "bundles: anchors changed:
$(cat "$tmp/anchors.diff")"
  fi
else
  fail "bundles: could not recompute the anchors"
fi

# Archived fragments keep their Consumed-by lines: a later consumption may add
# one, a migration must not rewrite or drop one, nor remove the fragment.
consumed_lines() {
  (cd "$1" && for cl_f in specs/_observations/archive/*.md; do
    [ -f "$cl_f" ] || continue
    awk -v f="$cl_f" '/^Consumed-by: / { print f "\t" $0; n++ } END { if (!n) print f "\t" }' "$cl_f"
  done) | sort
}
consumed_lines "$tmp/at-baseline" >"$tmp/consumed.baseline"
consumed_lines "$REPO_ROOT" >"$tmp/consumed.now"
comm -23 "$tmp/consumed.baseline" "$tmp/consumed.now" >"$tmp/consumed.lost"
if [ ! -s "$tmp/consumed.baseline" ]; then
  fail "bundles: no archived fragments at the baseline commit; the check proves nothing"
elif [ -s "$tmp/consumed.lost" ]; then
  fail "bundles: archived fragments lost Consumed-by lines or were removed:
$(sed 's/^/  /' "$tmp/consumed.lost")"
else
  ok "bundles: every archived fragment keeps its Consumed-by lines"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "all spec-location golden tests passed"
  exit 0
fi
echo "$failures spec-location golden test(s) failed" >&2
exit 1
