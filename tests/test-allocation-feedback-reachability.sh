#!/bin/bash
# Tests that the escalation feedback loop is REACHED by the shipped pipeline —
# that something actually runs the two terminal-state owners (model-allocation
# D-11; REQ-F1.2, REQ-E1.1).
#
# WHY THIS FILE EXISTS BESIDE tests/test-allocation-feedback-callsites.sh. That
# suite proves the two owners evaluate correctly once invoked. It cannot prove
# anything invokes them, and for a while nothing did: `fleet-fence.sh gc`,
# `fleet-fence.sh sweep` and `fleet-liveness.sh crash-record` appeared only in
# docs/fleet.md and docs/options-reference.md, so a loop that was correct at
# every layer still never ran. Wiring the owners without wiring their callers
# moves an inert mechanism out one level rather than closing it; this file is
# the guard against that regression.
#
# THE CALLER IS SKILL PROSE, AND THAT IS THE HONEST ANSWER. Both terminal
# states are observed in `/orchestrate`'s reconcile sweep — a merged unit at
# step 2, a dead worker at step 3/4 — and that sweep is model-executed
# instructions, not a script. The same skill already drives the LAUNCH end of
# this exact ladder from prose (`allocation-adapt.sh resolve` at the dispatch
# step), so the terminal end sits in the same place for the same reason. Every
# scripted alternative is worse: `fleet-sweep.sh` has no caller of its own, and
# `tasks-pr-sync.sh` runs as a PostToolUse hook in whatever session merged the
# PR — often a worker, whose branch is exactly where an observation fragment
# must not be stranded.
#
# SO THE PROSE IS MADE EXECUTABLE RATHER THAN MERELY ASSERTED. A test that only
# grepped the skill for a command name would pin the words and not the contract:
# a renamed verb, a dropped flag, or a flag pair that the callee refuses as
# all-or-none would all still read as "wired". This file instead EXTRACTS each
# documented invocation from the skill, substitutes fixture values for its
# `<placeholder>` tokens, and RUNS it. What is proven is that the command the
# tower is told to run is a command that works.
#
# What is covered here:
#   - the skill documents both invocations, each carrying the identity flags
#     its callee needs (the flags are all-or-none at both owners, so a partial
#     set is a usage error rather than a silently-skipped evaluation);
#   - every placeholder the skill uses is one this fixture knows how to fill —
#     fail closed, so prose and test cannot drift apart silently;
#   - each extracted command RUNS, exits clean, and REACHES the evaluation,
#     proven by a spy on the sibling path the owners invoke rather than by the
#     absence of output, which an unwired call site satisfies just as well;
#   - THE SHIPPED POSTURE: read against the repo's real config/defaults.yml,
#     where allocation_adaptation is `off`, the reached evaluation reports
#     `fired no` / `below-thresholds` and writes no fragment and no ledger
#     mark — and the unit really does carry ledger history, so the silence is
#     the ladder's rather than an empty fixture's.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-allocation-feedback-reachability.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

# Isolate git fully from the host's global/system config: signing
# (commit.gpgsign plus a signer that blocks non-interactively) and a global
# core.hooksPath would otherwise hang or reshape the fixture commits. The sweep
# suite's posture, for the same reason.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
REAL_DEFAULTS="$here/../config/defaults.yml"
SKILL="$here/../skills/orchestrate/SKILL.md"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -r "$SKILL" ] || fail "skills/orchestrate/SKILL.md is missing or unreadable"
[ -r "$REAL_DEFAULTS" ] || fail "config/defaults.yml is missing or unreadable"

tmp=$(mktemp -d)
# The fatal signals as well as EXIT: bash runs no EXIT trap when killed by an
# untrapped INT/TERM, and this fixture holds a bare repo, a clone and a fleet
# state dir that a Ctrl-C would otherwise leak. The signal arms re-exit rather
# than returning, because a trapped handler otherwise RESUMES the script — which
# would carry on against a fixture it had just deleted and fail somewhere
# misleading.
trap 'rm -rf "$tmp"' EXIT
trap 'rm -rf "$tmp"; exit 130' INT
trap 'rm -rf "$tmp"; exit 143' TERM
trap 'rm -rf "$tmp"; exit 129' HUP

# The extracted commands are split on whitespace to build an argv, so a fixture
# path carrying a space would silently produce a different command than the one
# the skill documents. Refuse rather than test a fiction.
case $tmp in
  *[[:space:]]*) fail "the fixture temp dir '$tmp' contains whitespace" ;;
esac

# Every script resolves its siblings through its own dir, so the suite runs them
# out of one copied tree (the callsites suite's fixture shape).
sbin="$tmp/sbin"
mkdir -p "$sbin"
cp "$here/../scripts/"*.sh "$sbin/"

# The spy. The evaluation is invoked as a SIBLING of each owner, so that
# sibling's own path is the seam that records whether the owner was reached.
# The wrapper appends its argv and then execs the real script, so every
# assertion below is made against real behavior rather than a stub's — and
# "ran and recorded nothing" stays distinguishable from "never ran", which is
# the whole question this file asks.
real_afb="$sbin/allocation-feedback.real.sh"
mv "$sbin/allocation-feedback.sh" "$real_afb"
calls="$tmp/afb-calls"
: >"$calls"
cat >"$sbin/allocation-feedback.sh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$calls"
exec "$real_afb" "\$@"
EOF
chmod +x "$sbin/allocation-feedback.sh"

call_count() {
  awk 'END { print NR + 0 }' "$calls"
}

calls_reset() {
  : >"$calls"
}

LEDGER="$sbin/allocation-ledger.sh"
AD="$sbin/allocation-adapt.sh"

# Outbound clients are stubbed: an LLM/API call anywhere in a terminal-state
# path would break the determinism floor (REQ-A1.1).
stubbin="$tmp/stubbin"
mkdir -p "$stubbin"
for c in claude curl wget; do
  printf '#!/bin/sh\nexit 0\n' >"$stubbin/$c"
  chmod +x "$stubbin/$c"
done
# `gh` is stubbed separately, because the derivation engine genuinely probes it.
: >"$tmp/gh-prs"
cat >"$stubbin/gh" <<EOF
#!/bin/sh
cat "$tmp/gh-prs"
EOF
chmod +x "$stubbin/gh"

fleet_home="$tmp/fleet"
adopter_root="$tmp/adopter"
mkdir -p "$fleet_home" "$adopter_root"
chmod 700 "$fleet_home"

# The fence reads terminality off git ground truth, so the checkout is a real
# clone of a real origin carrying a real spec bundle.
origin="$tmp/origin.git"
co="$tmp/co"
git -c init.defaultBranch=main init -q --bare "$origin"
git clone -q "$origin" "$co" 2>/dev/null
git -C "$co" config user.email reach@test.invalid
git -C "$co" config user.name reach-test
git -C "$co" symbolic-ref HEAD refs/heads/main

mkdir -p "$co/specs/demo"
cat >"$co/specs/demo/tasks.md" <<'TASKS'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — Terminal by trailer

- **Deliverables:** a thing
- **Done when:** it is done
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** half day

## Completed

(none yet)

## In progress

(none yet)

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
TASKS

git -C "$co" add specs
git -C "$co" commit -qm "spec fixture"
git -C "$co" commit -q --allow-empty -m "close task 1

Planwright-Task: demo/1"
git -C "$co" push -q origin HEAD:refs/heads/main
git -C "$co" fetch -q origin

unit=demo:task-1
worker=reach-worker
wscope=demo
obs_store="$co/specs/_observations"

# The SHIPPED defaults, deliberately: this file's whole no-op claim is about the
# values the plugin actually ships, so it reads config/defaults.yml itself and
# layers nothing over it.
pw() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    -u PLANWRIGHT_ALLOC_LOCK_HELD \
    PATH="$stubbin:$PATH" \
    PLANWRIGHT_BASE_REF=main \
    PLANWRIGHT_FLEET_STATE_DIR="$fleet_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$REAL_DEFAULTS" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$co" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$@" </dev/null
}

frag_count() {
  find "$obs_store/entries" -maxdepth 1 -type f -name '*.md' 2>/dev/null \
    | awk 'END { print NR + 0 }'
}

marks_of() {
  pw "$LEDGER" rows "$1" 2>/dev/null \
    | awk -F "$TAB" 'NF == 15 && $6 == "feedback" && $14 == "recorded" { n++ } END { print n + 0 }'
}

# extract_invocation <needle>: the one line of the skill that documents this
# command, taken from the fenced block verbatim. Exactly one match is required:
# zero means the caller is gone (the regression this file exists for), and more
# than one means the fixture cannot tell which the tower is told to run.
# The needle is matched LITERALLY at position 1 (awk index, not grep): a script
# path carries dots, and as a regex those match any byte, so the guard would
# accept a line this fixture never meant to run.
extract_invocation() {
  ei_hits=$(awk -v p="$1 " 'index($0, p) == 1 { n++ } END { print n + 0 }' "$SKILL")
  [ "$ei_hits" = 1 ] \
    || fail "expected exactly one '$1' invocation in skills/orchestrate/SKILL.md, found $ei_hits — the escalation feedback loop's caller is missing or ambiguous"
  awk -v p="$1 " 'index($0, p) == 1' "$SKILL"
}

# fill <command>: substitute this fixture's values for the skill's
# `<placeholder>` tokens. An UNKNOWN placeholder is a hard failure rather than a
# pass-through, so prose and fixture cannot drift apart while still reading
# green — the failure mode a grep-only test has by construction.
fill() {
  fi_cmd=$1
  fi_cmd=${fi_cmd//<absolute-primary-checkout>/$co}
  fi_cmd=${fi_cmd//<spec>/demo}
  # The batched form first: the gc line takes several ids, so `<unit-id>...` has
  # to resolve before the bare token would eat its stem and leave a stray `...`.
  fi_cmd=${fi_cmd//<unit-id>.../1}
  fi_cmd=${fi_cmd//<unit-id>/1}
  fi_cmd=${fi_cmd//<repo-name>/planwright}
  fi_cmd=${fi_cmd//<worker-handle>/$worker}
  fi_cmd=${fi_cmd//<worker-scope>/$wscope}
  fi_cmd=${fi_cmd/#scripts\//$sbin/}
  case $fi_cmd in
    *'<'*'>'*)
      fail "the skill's invocation carries a placeholder this fixture cannot fill: $fi_cmd"
      ;;
  esac
  printf '%s\n' "$fi_cmd"
}

# ==========================================================================
# R1 — the skill documents both invocations, with the flags each callee needs
# ==========================================================================
#
# The identity flags are all-or-none at both owners (the callsites suite pins
# that), so a documented invocation missing one of them is not a partial wiring
# that records less — it is a usage error the tower would hit every pass.

gc_cmd=$(extract_invocation "scripts/fleet-fence.sh gc")
for f in --checkout --spec --alloc-key --obs-scope; do
  case " $gc_cmd " in
    *" $f "*) ;;
    *) fail "R1a: the documented fence-gc invocation omits $f: $gc_cmd" ;;
  esac
done
echo "ok R1a: the skill documents a fence-gc invocation carrying the feedback identity"

cr_cmd=$(extract_invocation "scripts/fleet-liveness.sh crash-record")
for f in --alloc-unit --alloc-key --obs-scope --obs-dir; do
  case " $cr_cmd " in
    *" $f "*) ;;
    *) fail "R1b: the documented crash-record invocation omits $f: $cr_cmd" ;;
  esac
done
echo "ok R1b: the skill documents a crash-record invocation carrying the feedback identity"

# ==========================================================================
# R2 — the unit really has ledger history, so R3/R4's silence means something
# ==========================================================================
#
# Two launches driven through the adaptation engine on a triggering event, under
# the SHIPPED defaults. With allocation_adaptation `off` nothing escalates, so
# the unit ends where it started with zero applied up-steps — which is exactly
# the posture whose no-op has to be proven by mechanism rather than by an empty
# store.
pw "$AD" resolve "$unit" --key execution --step s1 --attempt 1 \
  --event step-failure >/dev/null || fail "R2a: the first shipped-posture launch failed"
pw "$AD" resolve "$unit" --key execution --step s2 --attempt 1 \
  --event step-failure >/dev/null || fail "R2b: the second shipped-posture launch failed"
rows=$(pw "$LEDGER" rows "$unit" | awk 'END { print NR + 0 }')
[ "$rows" -gt 0 ] \
  || fail "R2c: the fixture unit has no ledger history, so the no-op assertions below would prove nothing"
echo "ok R2: the fixture unit carries real ledger history under the shipped defaults"

# ==========================================================================
# R3 — the documented fence-gc invocation runs and reaches the evaluation
# ==========================================================================
calls_reset
filled=$(fill "$gc_cmd")
# The skill's line IS the argv, so it is split on whitespace — with pathname
# expansion off, because a token of it is a filesystem path and a glob character
# reaching the split would hand the callee a different command than the one
# documented (the discipline every script here runs under).
set -f
# shellcheck disable=SC2086 # deliberate word-split, guarded by set -f above
set -- $filled
set +f
pw "$@" >/dev/null 2>"$tmp/gc-err" \
  || fail "R3a: the invocation the skill documents failed: $(cat "$tmp/gc-err")"
[ "$(call_count)" = 1 ] \
  || fail "R3b: the documented fence-gc invocation did not reach the evaluation (calls=$(call_count))"
# The SUBJECT is asserted beside the state. The fence assembles the ledger unit
# key from the spec and unit id the skill's line hands it, so a placeholder that
# filled wrongly would still reach the evaluation — just about a unit that is
# not the one being retired, which every later assertion here would read as a
# clean no-op.
grep -q -- "evaluate $unit .*--terminal completed" "$calls" \
  || fail "R3c: fence gc did not evaluate $unit as completed: $(cat "$calls")"
[ "$(frag_count)" = 0 ] \
  || fail "R3d: the shipped posture recorded an observation through fence gc"
[ "$(marks_of "$unit")" = 0 ] \
  || fail "R3e: the shipped posture wrote a ledger mark through fence gc"
echo "ok R3: the documented fence-gc invocation runs, reaches the evaluation, and records nothing"

# ==========================================================================
# R4 — the documented crash-record invocation runs and reaches the evaluation
# ==========================================================================
#
# Only the DISABLING crash is terminal, so the same command run to the shipped
# `fleet_crash_disable_threshold` reaches the evaluation exactly once. Running
# the documented line unchanged every time is the point: the tower is not told
# to count crashes and pass the flags only on the last one. The one addition is
# `--now`, which pins the clock so the streak is the fixture's rather than the
# wall's; it is not part of what the skill documents.
calls_reset
filled=$(fill "$cr_cmd")
set -f
# shellcheck disable=SC2086 # deliberate word-split, guarded by set -f (see R3)
set -- $filled
set +f
# Read through the resolver the callee itself reads (fleet-liveness.sh's `knob`,
# same key, type and fallback), not a second parser of the same YAML: a
# hand-rolled reader here would drift from the real one on a trailing comment or
# a quoted value, and this suite would then disagree with the code it tests.
threshold=$(pw "$sbin/resolve-config-knob.sh" --key fleet_crash_disable_threshold \
  --type posint --fallback 3) \
  || fail "R4a: could not resolve fleet_crash_disable_threshold"
case $threshold in
  "" | *[!0-9]*) fail "R4a: fleet_crash_disable_threshold resolved to '$threshold'" ;;
esac
i=1
while [ "$i" -le "$threshold" ]; do
  pw "$@" --now "$((1000 + i * 100))" >"$tmp/cr-out" 2>"$tmp/cr-err" \
    || fail "R4b: crash $i of the documented crash-record invocation failed: $(cat "$tmp/cr-err")"
  i=$((i + 1))
done
grep -q '^disabled ' "$tmp/cr-out" \
  || fail "R4c: $threshold crashes did not disable the worker: $(cat "$tmp/cr-out")"
[ "$(call_count)" = 1 ] \
  || fail "R4d: the documented crash-record invocation did not reach the evaluation exactly once (calls=$(call_count))"
grep -q -- "evaluate $unit .*--terminal disabled" "$calls" \
  || fail "R4e: crash-record did not evaluate $unit as disabled: $(cat "$calls")"
[ "$(frag_count)" = 0 ] \
  || fail "R4f: the shipped posture recorded an observation through crash-record"
[ "$(marks_of "$unit")" = 0 ] \
  || fail "R4g: the shipped posture wrote a ledger mark through crash-record"
echo "ok R4: the documented crash-record invocation runs, reaches the evaluation, and records nothing"

# ==========================================================================
# R5 — the no-op is the LADDER's verdict, read off the evaluation's own report
# ==========================================================================
#
# R3 and R4 assert an absence; an absence is also what a call site that quietly
# did nothing produces. The spy separates those two, and this reads the reason
# the evaluation itself gives for the silence.
verdict=$(pw "$sbin/allocation-feedback.sh" evaluate "$unit" \
  --key execution --terminal completed --scope planwright --obs-dir "$obs_store")
printf '%s\n' "$verdict" | grep -q "^fired${TAB}no$" \
  || fail "R5a: the shipped-posture evaluation fired: $verdict"
printf '%s\n' "$verdict" | grep -q "^reason${TAB}below-thresholds$" \
  || fail "R5b: expected below-thresholds on the shipped defaults, got: $verdict"
printf '%s\n' "$verdict" | grep -q "^escalations${TAB}0$" \
  || fail "R5c: the shipped defaults escalated a unit: $verdict"
echo "ok R5: the shipped-posture silence is the ladder reaching neither firing condition"

echo "PASS: tests/test-allocation-feedback-reachability.sh"
