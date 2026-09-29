#!/bin/bash
# The spec-location golden fixture: with every new option unset, the scripts
# the spec-location migration moves onto the resolver keep printing the same
# paths and messages, from a primary checkout and from a worktree, except for
# the named corrections each migration task declares.
#
# Three parts:
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
# Glob order, which the anchor listing follows, is byte order.
LC_ALL=C
export LC_ALL
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
FIXTURE="$REPO_ROOT/tests/fixtures/spec-location-golden"
# The pre-migration main the baseline was captured from.
BASELINE_COMMIT=821fb2f8d063646e5b26d123da91fb576918b954
S="$REPO_ROOT/scripts"

# shellcheck source=tests/lib/golden-replay.sh
. "$REPO_ROOT/tests/lib/golden-replay.sh"

failures=0
ok() { echo "ok: $1"; }
# Failure text quotes probe output and repo content, so it is stripped of
# control bytes before it reaches the terminal.
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177\200-\237' >&2
  failures=$((failures + 1))
}

# Two steps: bash 3.2 reads `cd ""` as success, so a failed mktemp inside one
# substitution would make $tmp the current directory, which the trap deletes.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/spec-location-golden.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# Every PLANWRIGHT_* variable the caller exports, as `-u` arguments: any of
# them (a base ref, a state directory) changes what a probe prints or where it
# writes.
inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')

# Hermetic environment: no inherited planwright variables, roots, or overlay
# pointers, a private HOME and tmux socket directory, git discovery fenced at
# $tmp, and fixed identities and dates so commit ids are stable across
# machines. GOLDEN_HOME is set per vantage.
hermetic() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    -u TMUX -u TMUX_PANE TMUX_TMPDIR="$GOLDEN_HOME" \
    HOME="$GOLDEN_HOME" GIT_CEILING_DIRECTORIES="$tmp" \
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
  printf 'steps_convergence: [polish, self-review]\ndispatch_isolation: per-unit\n' \
    >"$mf_p/.claude/planwright.local.yml"
  hermetic git -C "$mf_p" worktree add -q "$mf_p/.claude/worktrees/wt" -b wt || return 1
  # Untracked, as a store with no fragments yet is.
  mkdir -p "$mf_p/specs/_observations/entries" "$mf_p/.claude/worktrees/wt/specs/_observations/entries"
}

today_utc=$(date -u +%Y-%m-%d)
today_local=$(date +%Y-%m-%d)

# normalize <fixture-tmp> — machine paths to placeholders (replaced as literal
# strings, so a path byte is never a pattern), minted observation ids, commit
# and anchor hashes, and today's date to stable tokens. Record headers pass
# through untouched; `probe` has already escaped any body line opening with
# `@@`.
normalize() {
  NZ_WT=$1/primary/.claude/worktrees/wt NZ_PRIMARY=$1/primary NZ_INSTALL=$REPO_ROOT \
    NZ_TMP=$1 NZ_TODAY_U=$today_utc NZ_TODAY_L=$today_local awk '
    function now(flag,   cmd, d) {
      cmd = "date " flag " +%Y-%m-%d"; d = ""
      cmd | getline d; close(cmd)
      return d
    }
    function lit(s, from, to,   out, i) {
      if (from == "") return s
      out = ""
      while ((i = index(s, from)) > 0) { out = out substr(s, 1, i - 1) to; s = substr(s, i + length(from)) }
      return out s
    }
    {
      s = $0
      if (substr(s, 1, 3) == "@@ ") { print; next }
      s = lit(s, ENVIRON["NZ_WT"], "<WORKTREE>"); s = lit(s, ENVIRON["NZ_PRIMARY"], "<PRIMARY>")
      s = lit(s, ENVIRON["NZ_INSTALL"], "<INSTALL>"); s = lit(s, ENVIRON["NZ_TMP"], "<TMP>")
      s = lit(s, ENVIRON["NZ_TODAY_U"], "<TODAY>"); s = lit(s, ENVIRON["NZ_TODAY_L"], "<TODAY>")
      # A line stamped after midnight carries the date the line was written,
      # which lies between the start date and now.
      if (s ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) { s = lit(s, now("-u"), "<TODAY>"); s = lit(s, now(""), "<TODAY>") }
      gsub(/-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]\.md/, "-<UID>.md", s)
      gsub(/[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]/, "<SHA>", s)
      print s
    }'
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
  # probe <name> <command...> — run with the install root pinned to this tree
  # and the fleet state inside the fixture.
  probe() {
    pr_name=$1
    shift
    printf '@@ %s %s\n' "$pr_name" "$rv_v"
    (
      cd "$rv_dir" && hermetic PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_FLEET_STATE_DIR="$rv_t/fleet" "$@" 2>&1
      echo "rc=$?"
    ) | sed 's/^@@/\\@@/'
  }
  # The install-root chain with no explicit root and a content-less plugin
  # arm: the arm the chain convergence starts skipping with a warning.
  probe rule-doc-contentless-arm env -u PLANWRIGHT_ROOT CLAUDE_PLUGIN_ROOT="$rv_t/empty" \
    "$S/resolve-rule-doc.sh" --explain spec-format
  probe rule-doc "$S/resolve-rule-doc.sh" --explain spec-format
  probe config-get "$S/config-get.sh" --explain steps_convergence
  probe convergence-steps "$S/resolve-steps.sh" convergence --unattended
  probe config-knob "$S/resolve-config-knob.sh" --key dispatch_isolation --type enum \
    --values 'per-step per-unit' --fallback per-step
  probe overlay-repo-tracked "$S/resolve-overlay-root.sh" repo-tracked
  probe overlay-machine-local "$S/resolve-overlay-root.sh" machine-local
  # A repo-root override naming a directory that is not a git toplevel: the
  # value the narrowing starts refusing.
  probe overlay-repo-root-override env PLANWRIGHT_REPO_ROOT="$rv_dir/specs" \
    "$S/resolve-overlay-root.sh" machine-local
  # The layers entries came from, not the entries: the catalog's content is
  # outside this fixture's concern.
  probe catalog sh -c 'o=$("$1" decision-domains --explain); r=$?; printf "%s\n" "$o" | cut -f2 | sort -u; exit $r' \
    sh "$S/resolve-catalog.sh"
  probe spec-root "$S/resolve-root.sh" spec --explain
  # The rung line only: the scaffold's file inventory belongs to inception.
  probe inception-scaffold sh -c 'o=$("$1" "$2" 2>&1); r=$?; printf "%s\n" "$o" | tail -n 1; exit $r' \
    sh "$S/inception-scaffold.sh" "$rv_t/venture"
  probe anchor-freshness "$S/check-anchor-freshness.sh" specs
  probe ledger "$S/check-ledger.sh" specs/demo/tasks.md
  probe memory-links "$S/check-memory-links.sh" specs/demo
  probe state "$S/orchestrate-state.sh" specs/demo
  probe status "$S/spec-status.sh" specs/demo
  probe meta-select "$S/orchestrate-meta-select.sh" specs/demo
  probe tasks-pr-sync "$S/tasks-pr-sync.sh" reconcile specs/demo
  probe migrate-status "$S/migrate-status-lifecycle.sh" specs
  probe migrate-format "$S/migrate-format-version.sh" specs/demo
  probe walkthrough "$S/spec-walkthrough.sh" --scope tasks specs/demo
  probe headless-status "$S/fleet-dispatch-headless.sh" status demo 1
  probe flight-id sh -c '"$1" branch fixture-1a2b3c4d && "$1" taken fixture-1a2b3c4d' sh "$S/flight-id.sh"
  probe sweep "$S/fleet-sweep.sh" --repo "$rv_dir"
  probe lock sh -c '"$1" acquire specs/demo && find specs -name "*.lock*" && "$1" release specs/demo' \
    sh "$S/orchestrate-lock.sh"
  probe marker sh -c '"$1" write specs/demo 1 && find specs -path "*/markers/*" && "$1" clear specs/demo 1' \
    sh "$S/orchestrate-marker.sh"
  probe trailers sh -c 'printf "feat: x\n" | "$1" demo/1' sh "$S/planwright-commit-trailers.sh"
  probe fence-refname "$S/fleet-fence.sh" refname --spec demo 1
  probe fence-check "$S/fleet-fence.sh" check --checkout "$rv_dir" --spec demo 1
  probe dispatch-fetch "$S/dispatch-fetch.sh" --spec specs/demo .
  probe watchdog "$S/fleet-tower-watchdog.sh" "$rv_dir/specs/demo"
  probe observations sh -c '"$1/obs-record.sh" --slug fixture --scope fixture --text "a fixture observation" >/dev/null &&
    ls specs/_observations/entries && "$1/check-obs.sh" && "$1/obs-render.sh" &&
    "$1/observation-carry.sh" --dry-run . &&
    uid=$(ls specs/_observations/entries | sed "s/.*-\([0-9a-f]\{8\}\)\.md$/\1/") &&
    "$1/obs-consume.sh" --uid "$uid" --spec demo --today 2026-01-01 &&
    grep -rh "^Consumed-by:" specs/_observations' sh "$S"
  probe dispatch-worktree "$S/fleet-dispatch-worktree.sh" dispatch demo 1 --no-attach
}

# record_probes — both vantages, each in its own fixture so a probe's side
# effects from one vantage never reach the other. A vantage whose fixture
# cannot be built fails the recording rather than shrinking it.
record_probes() {
  rp_pids=''
  for rp_v in primary worktree; do
    (
      GOLDEN_HOME=$tmp/$rp_v/home
      mkdir -p "$GOLDEN_HOME" && make_fixture "$tmp/$rp_v/primary" || exit 1
      record_vantage "$rp_v" "$tmp/$rp_v" | normalize "$tmp/$rp_v" >"$tmp/$rp_v.rec"
    ) &
    rp_pids="$rp_pids $!"
  done
  rp_rc=0
  for rp_pid in $rp_pids; do
    wait "$rp_pid" || rp_rc=1
  done
  [ "$rp_rc" -eq 0 ] || {
    echo "record_probes: a vantage's fixture or recording did not complete" >&2
    return 1
  }
  cat "$tmp/primary.rec" "$tmp/worktree.rec"
}

# record_anchors — every bundle at the baseline commit, `<bundle> TAB <anchor>`.
record_anchors() {
  git -C "$REPO_ROOT" cat-file -e "$BASELINE_COMMIT^{commit}" 2>/dev/null || {
    echo "baseline commit $BASELINE_COMMIT is not in this clone's history (a shallow clone?)" >&2
    return 2
  }
  mkdir -p "$tmp/at-baseline"
  # Both ends of the pipe are checked: bsdtar exits 0 on an empty stream.
  git -C "$REPO_ROOT" archive "$BASELINE_COMMIT" specs | tar -x -C "$tmp/at-baseline"
  ra_st="${PIPESTATUS[0]} ${PIPESTATUS[1]}"
  [ "$ra_st" = "0 0" ] && [ -d "$tmp/at-baseline/specs" ] || {
    echo "could not extract specs/ at the baseline commit" >&2
    return 2
  }
  for ra_d in "$tmp/at-baseline/specs"/*/; do
    ra_b=$(basename "$ra_d")
    case $ra_b in _*) continue ;; esac
    (
      cd "$tmp/at-baseline" || exit 1
      # A failing recompute shows as its status, never as whatever it printed.
      ra_a=$("$S/spec-anchor.sh" "specs/$ra_b" 2>&1) || ra_a="ERROR rc=$?: $ra_a"
      printf '%s\t%s\n' "$ra_b" "$ra_a" >"$tmp/anchor.$ra_b"
    ) &
  done
  wait
  cat "$tmp"/anchor.*
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
mkdir -p "$planted/changes" "$planted/no-changes"
printf 'comment\n@@ a primary\none\n@@ b primary\ntwo\n' >"$planted/baseline.txt"
printf 'fix-a\t3\tREQ-X\ta\nfix-b\t5\tREQ-Y\tb\nold\tbaseline\tREQ-Z\tz\n' >"$planted/registry.tsv"
printf '@@ a primary\none\n@@ b primary\ntwo\n' >"$planted/same.txt"
printf '@@ a primary\nONE\n@@ b primary\ntwo\n' >"$planted/a-changed.txt"
# The comparator's own scratch goes under $tmp, so this file's trap covers an
# interrupted replay too.
replay() { TMPDIR=$tmp golden_replay "$planted/baseline.txt" "$planted/changes" "$planted/registry.tsv" "$1" 2>&1; }

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
  case $out in *"a primary differs"*) ok "comparator: a declared change that did not happen fails" ;; *) fail "comparator: undelivered change misreported: $out" ;; esac
fi

# A declared override that cannot be applied fails, rather than leaving the
# baseline's body as the expected output.
mkdir -p "$tmp/cp-shim"
printf '#!/bin/sh\nexit 1\n' >"$tmp/cp-shim/cp"
chmod +x "$tmp/cp-shim/cp"
if out=$(PATH="$tmp/cp-shim:$PATH" replay "$planted/same.txt"); then
  fail "comparator: an override that could not be applied passed"
else
  case $out in *"could not apply task 3's a primary"*) ok "comparator: an override that cannot be applied fails" ;; *) fail "comparator: failed override misreported: $out" ;; esac
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

# Numeric task order, not lexical: 6 before 6.5 before 10.
printf 'fix-a\t3\tREQ-X\ta\nfix-b\t5\tREQ-Y\tb\nold\tbaseline\tREQ-Z\tz\nfix-6\t6\tR\t6\nfix-65\t6.5\tR\t65\nfix-10\t10\tR\t10\n' >"$planted/registry.tsv"
printf '@@ a primary fix-a\nONE\n' >"$planted/changes/task-3.txt"
printf '@@ a primary fix-10\nTEN\n' >"$planted/changes/task-10.txt"
printf '@@ a primary fix-65\nSIX-FIVE\n' >"$planted/changes/task-6.5.txt"
printf '@@ a primary fix-6\nSIX\n' >"$planted/changes/task-6.txt"
printf '@@ a primary\nTEN\n@@ b primary\ntwo\n' >"$planted/a-ten.txt"
if out=$(replay "$planted/a-ten.txt"); then ok "comparator: later sets override earlier ones in numeric task order"; else fail "comparator: set ordering failed: $out"; fi
rm -f "$planted/changes/task-10.txt"
# 6.5 after 6, from a changes directory whose own path carries a dotted digit.
mkdir -p "$planted/v.9"
mv "$planted/changes" "$planted/v.9/changes"
printf '@@ a primary\nSIX-FIVE\n@@ b primary\ntwo\n' >"$planted/a-sixfive.txt"
if out=$(TMPDIR=$tmp golden_replay "$planted/baseline.txt" "$planted/v.9/changes" "$planted/registry.tsv" "$planted/a-sixfive.txt"); then
  ok "comparator: 6.5 overrides 6 whatever dots the path carries"
else
  fail "comparator: 6 and 6.5 misordered: $out"
fi
mv "$planted/v.9/changes" "$planted/changes"
rm -f "$planted/changes/task-6.5.txt" "$planted/changes/task-6.txt"
printf 'fix-a\t3\tREQ-X\ta\nfix-b\t5\tREQ-Y\tb\nold\tbaseline\tREQ-Z\tz\n' >"$planted/registry.tsv"

# A set is named for a task id, so `baseline` or an empty id cannot declare
# anything.
for odd in baseline ''; do
  rm -rf "$planted/odd-changes"
  mkdir -p "$planted/odd-changes"
  printf '@@ b primary old\ntwo\n' >"$planted/odd-changes/task-$odd.txt"
  if out=$(TMPDIR=$tmp golden_replay "$planted/baseline.txt" "$planted/odd-changes" "$planted/registry.tsv" "$planted/same.txt"); then
    fail "comparator: a set named task-$odd.txt passed"
  else
    case $out in *"is not named for a task id"*) ok "comparator: a set named task-$odd.txt is refused" ;; *) fail "comparator: task-$odd.txt misreported: $out" ;; esac
  fi
done

# Task ids compare as strings: 6.10 is not 6.1, so declaring 6.1's set does
# not declare 6.10's.
rm -rf "$planted/odd-changes"
mkdir -p "$planted/odd-changes"
printf 'fix-61\t6.1\tR\tx\nfix-610\t6.10\tR\ty\n' >"$planted/ids.tsv"
printf '@@ a primary fix-61\nVAL\n' >"$planted/odd-changes/task-6.1.txt"
printf '@@ a primary\nVAL\n@@ b primary\ntwo\n' >"$planted/a-val.txt"
if out=$(TMPDIR=$tmp golden_replay "$planted/baseline.txt" "$planted/odd-changes" "$planted/ids.tsv" "$planted/a-val.txt"); then
  ok "comparator: task 6.1's set does not stand in for task 6.10's"
else
  fail "comparator: 6.1 and 6.10 confused: $out"
fi

printf '@@ ../escape primary\nx\n' >"$planted/escape.txt"
if out=$(replay "$planted/escape.txt"); then
  fail "comparator: a header naming a path passed"
else
  case $out in *"header field is not a name"*) ok "comparator: a header field that is not a name is refused" ;; *) fail "comparator: path header misreported: $out" ;; esac
fi

printf '@@ a primary\n\033[31mred\n@@ b primary\ntwo\n' >"$planted/escape-bytes.txt"
out=$(replay "$planted/escape-bytes.txt")
case $out in
  *$'\033'*) fail "comparator: a control byte from a record reached the terminal" ;;
  *"a primary differs"*) ok "comparator: reported output is stripped of control bytes" ;;
  *) fail "comparator: control-byte mismatch misreported: $out" ;;
esac

if out=$(TMPDIR=$tmp golden_replay "$planted/baseline.txt" "$planted/changes" "$planted/no-registry.tsv" "$planted/same.txt"); then
  fail "comparator: a missing registry passed"
else
  case $out in *"no-registry.tsv is missing"*) ok "comparator: a missing registry fails closed" ;; *) fail "comparator: missing registry misreported: $out" ;; esac
fi

# Registry rows carry four fields, a unique correction name, and an owner that
# is a task id or `baseline`.
for bad in 'short\t3' 'fix-a\t3\tR\ta\nfix-a\t5\tR\tb' 'odd\ttask-3\tR\tx' 'sp ace\t3\tR\tx'; do
  printf '%b\n' "$bad" >"$planted/bad-registry.tsv"
  if out=$(TMPDIR=$tmp golden_replay "$planted/baseline.txt" "$planted/no-changes" "$planted/bad-registry.tsv" "$planted/same.txt"); then
    fail "comparator: a malformed registry row passed: $bad"
  else
    case $out in *"bad-registry.tsv:"*) ok "comparator: a malformed registry row is refused: $bad" ;; *) fail "comparator: malformed registry misreported ($bad): $out" ;; esac
  fi
done

printf 'commentary only\n' >"$planted/no-records.txt"
if out=$(TMPDIR=$tmp golden_replay "$planted/no-records.txt" "$planted/no-changes" "$planted/registry.tsv" "$planted/no-records.txt"); then
  fail "comparator: a baseline with no records passed"
else
  case $out in *"holds no records"*) ok "comparator: a baseline with no records fails" ;; *) fail "comparator: empty baseline misreported: $out" ;; esac
fi

printf '@@ a primary\none\n' >"$planted/missing.txt"
if out=$(replay "$planted/missing.txt"); then
  fail "comparator: a recording missing a probe passed"
else
  case $out in *"recorded probes differ from the baseline"*) ok "comparator: a recording missing a probe fails" ;; *) fail "comparator: missing probe misreported: $out" ;; esac
fi

# A date stamped after midnight still normalizes: the recording can outlast
# the day it started on.
nz_u=$today_utc nz_l=$today_local
today_utc=1999-01-01 today_local=1999-01-01
got=$(printf 'x %s\n' "$(date -u +%Y-%m-%d)" | normalize "$tmp/none")
today_utc=$nz_u today_local=$nz_l
if [ "$got" = "x <TODAY>" ]; then ok "normalize: a date stamped after the run started is today"; else fail "normalize: a later date stayed literal: $got"; fi

# nr <label> <want> <changes-dir> <actual> — expect a failing replay whose
# report carries <want>.
nr() {
  if out=$(TMPDIR=$tmp golden_replay "$planted/baseline.txt" "$3" "$planted/registry.tsv" "$4"); then
    fail "comparator: $1 passed"
  else
    case $out in *"$2"*) ok "comparator: $1 fails" ;; *) fail "comparator: $1 misreported: $out" ;; esac
  fi
}
printf '@@ a primary\none\n@@ a primary\none\n@@ b primary\ntwo\n' >"$planted/dup.txt"
nr "a duplicate record" "duplicate record a primary" "$planted/no-changes" "$planted/dup.txt"
printf '@@ a primary\none\n@@ b primary\ntwo\n@@ c primary\nx\n' >"$planted/extra.txt"
nr "a recording with an extra probe" "recorded probes differ from the baseline" "$planted/no-changes" "$planted/extra.txt"
rm -rf "$planted/odd-changes"
mkdir -p "$planted/odd-changes"
printf '@@ a primary\nONE\n' >"$planted/odd-changes/task-3.txt"
nr "a set entry without its correction" "header needs 3 fields" "$planted/odd-changes" "$planted/a-changed.txt"
rm -f "$planted/odd-changes/task-3.txt"
printf '@@ a primary fix-a\nONE\n' >"$planted/odd-changes/task-5.txt"
nr "a set declaring another task's correction" "which the registry assigns to 3" "$planted/odd-changes" "$planted/a-changed.txt"

# --- The probes -------------------------------------------------------------

# The bundle part shares nothing with the probes, so it runs beside them.
record_anchors >"$tmp/anchors.tsv" 2>"$tmp/anchors.err" &
anchors_pid=$!

record_probes >"$tmp/actual.txt" || fail "probes: the recording did not complete"
if out=$(TMPDIR=$tmp golden_replay "$FIXTURE/baseline.txt" "$FIXTURE/changes" "$FIXTURE/corrections.tsv" "$tmp/actual.txt" 2>&1); then
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

if wait "$anchors_pid"; then
  grep -v '^#' "$FIXTURE/anchors.tsv" >"$tmp/anchors.expected"
  if diff -u "$tmp/anchors.expected" "$tmp/anchors.tsv" >"$tmp/anchors.diff"; then
    ok "bundles: every bundle at the baseline commit recomputes its recorded anchor"
  else
    fail "bundles: anchors changed:
$(cat "$tmp/anchors.diff")"
  fi
else
  fail "bundles: could not recompute the anchors: $(cat "$tmp/anchors.err")"
fi

# Archived fragments keep their Consumed-by lines: a later consumption may add
# one, a migration must not rewrite or drop one, nor remove the fragment.
# Every fragment also gets a bare `<path> TAB` row, so its removal shows
# whether or not it carries a line, and a first consumption removes nothing.
# The legacy single-file archive carries its consumptions inline, one
# `consumed-by: specs/<id> (<date>)` annotation each, counted as rows too.
consumed_lines() {
  (cd "$1" && set -- specs/_observations/archive/*.md && [ -f "$1" ] \
    && awk 'FNR == 1 { print FILENAME "\t" }
      /^Consumed-by: / { print FILENAME "\t" $0 }' "$@" \
    && if [ -f specs/_observations/archive.md ]; then
      grep -io 'consumed-by: specs/[^ ]* ([^)]*)' specs/_observations/archive.md \
        | awk '{ print "specs/_observations/archive.md\t" $0 }'
    fi) | sort
}
# On planted stores: a first consumption is not a loss, a removal is.
for cl in was now gone; do mkdir -p "$tmp/cl-$cl/specs/_observations/archive"; done
printf 'x\n' >"$tmp/cl-was/specs/_observations/archive/a.md"
printf 'x\nConsumed-by: specs/demo (2026-01-01)\n' >"$tmp/cl-now/specs/_observations/archive/a.md"
printf 'x\n' >"$tmp/cl-gone/specs/_observations/archive/b.md"
consumed_lines "$tmp/cl-was" >"$tmp/cl-was.txt"
if [ -z "$(consumed_lines "$tmp/cl-now" | comm -23 "$tmp/cl-was.txt" -)" ]; then
  ok "bundles: a fragment's first Consumed-by line is not a loss"
else
  fail "bundles: a first consumption read as a lost line"
fi
if [ -n "$(consumed_lines "$tmp/cl-gone" | comm -23 "$tmp/cl-was.txt" -)" ]; then
  ok "bundles: a removed fragment with no Consumed-by line is a loss"
else
  fail "bundles: a removed unconsumed fragment went unnoticed"
fi

printf -- '- 2026-01-01 [x] an entry — consumed-by: specs/demo (2026-01-02)\n' >"$tmp/cl-was/specs/_observations/archive.md"
printf -- '- 2026-01-01 [x] an entry\n' >"$tmp/cl-now/specs/_observations/archive.md"
consumed_lines "$tmp/cl-was" >"$tmp/cl-was.txt"
if [ -n "$(consumed_lines "$tmp/cl-now" | comm -23 "$tmp/cl-was.txt" -)" ]; then
  ok "bundles: a consumed-by annotation dropped from the legacy archive is a loss"
else
  fail "bundles: a dropped legacy consumed-by annotation went unnoticed"
fi

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
