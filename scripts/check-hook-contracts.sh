#!/usr/bin/env bash
# check-hook-contracts.sh — the hook-registration guard (fleet-lifecycle-closure
# Task 2; D-11; REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-K1.1).
#
# WHAT THIS EXISTS TO PREVENT. planwright registered a passive worktree tracker
# on `WorktreeCreate` and thereby became the thing that creates worktrees. The
# tracker read `worktree_path` from a payload that carries `name`, found
# nothing, echoed nothing, and exited 0 — and because that event reads silence
# as refusal, worktree creation broke on every installed machine, explained only
# on stderr the harness discards. Nothing failed until a human hand-probed the
# hook.
#
# THE DISTINCTION THAT MATTERS is not "can this event block something" but
# WHAT SILENCE MEANS on it:
#
#   silence=proceeds — a hook that exits 0 with no output leaves the operation
#     exactly as it would have been. Registering an observer here is free.
#     `PreToolUse` and `Stop` live here: they CAN block, but only if the hook
#     says so. This is the ordinary case.
#   silence=refuses — registering a hook REPLACES the native operation, so a
#     hook that says nothing has refused it. An observer here is not a
#     no-op, it is an outage. `WorktreeCreate` is the one such event.
#
# So the guard's central rule: nothing may be registered on a silence=refuses
# event unless it is declared that operation's implementer (`--implementer`)
# and demonstrably produces the required output against the event's fixture.
# planwright declares no implementer, which is why it registers no such event —
# worktree tracking rides `record-create` at the dispatch seam and the `scan`
# reconcile instead, neither of which can refuse anything.
#
# FAIL-CLOSED. The guard fails, never passes, when it cannot prove the posture:
# an unreadable or unparseable `hooks.json`, a missing fixture directory, a
# checkout path carrying whitespace (registered commands become unsplittable),
# an event the contract table below does not model (its silence semantics are
# exactly what must not be assumed), a registered event with no payload fixture,
# a registered command that is absent or not executable, a decision hook that
# dies against its own fixture rather than declining to decide, an implementer
# whose output the harness would discard because it exited non-zero, and a hook
# type other than `command`.
#
# THE CONTRACT TABLE below is this guard's own knowledge and the reason it can
# be trusted: each row was read out of the CLI's payload construction and
# dispatch sites rather than the published docs, which omit `WorktreeCreate`'s
# input schema and have drifted on several others. Adding a row is a deliberate
# act — it asserts you checked what silence means on that event.
#
# IT RUNS THE HOOKS IT CHECKS, AS REGISTERED. Proving a decision hook satisfies
# its output contract means feeding it the event's fixture and reading what
# comes back — a static scan cannot tell a handler that emits a decision from
# one that intends to. Registered arguments are passed too: the liveness hooks
# are wired as `fleet-liveness.sh hook <event>`, so dropping them would check an
# invocation the harness never makes. The commands come from the repo's own
# tracked registration files, as trusted as the rest of the checkout, and each
# run is bounded by `timeout` with the worker identity neutralised. Point
# `--hooks` at a registration file you do not trust and you are executing its
# commands; that flag exists for this guard's own tests.
#
# Usage: check-hook-contracts.sh [--hooks <file>]... [--fixtures <dir>]
#                               [--implementer <Event>]...
#        --hooks defaults to the three surfaces planwright registers through:
#        hooks/hooks.json, config/worker-settings.json, config/tower-settings.json.
#        The first --hooks replaces that set; further ones add to it.
# Exit:  0 clean · 1 findings · 2 usage or environment error (fail closed).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/hook-payloads"
IMPLEMENTERS=""
HOOK_TIMEOUT=20

# planwright registers hooks in three places, and all three are the surface:
# the plugin-global file, plus the worker and tower settings fragments that
# each wire a PreToolUse command guard. Checking only the first would report
# clean over two thirds of what actually gets registered.
HOOKS_FILES=(
  "$REPO_ROOT/hooks/hooks.json"
  "$REPO_ROOT/config/worker-settings.json"
  "$REPO_ROOT/config/tower-settings.json"
)
HOOKS_OVERRIDDEN=0

# CONTRACT TABLE: <event>|<silence>|<control>|<required-output-noun>
# The noun is used only for silence=refuses rows, to name what a declared
# implementer failed to produce.
CONTRACTS='
PreToolUse|proceeds|decision|
PostToolUse|proceeds|observation|
SessionStart|proceeds|observation|
SessionEnd|proceeds|observation|
Stop|proceeds|decision|
StopFailure|proceeds|observation|
Notification|proceeds|observation|
PermissionRequest|proceeds|decision|
WorktreeCreate|refuses|decision|worktree path
WorktreeRemove|proceeds|observation|
'

die() {
  printf 'check-hook-contracts: %s\n' "$1" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --hooks)
      [ $# -ge 2 ] || die "--hooks needs a path"
      # The first --hooks replaces the default set; further ones add to it.
      if [ "$HOOKS_OVERRIDDEN" -eq 0 ]; then
        HOOKS_FILES=("$2")
        HOOKS_OVERRIDDEN=1
      else
        HOOKS_FILES+=("$2")
      fi
      shift 2
      ;;
    --fixtures)
      [ $# -ge 2 ] || die "--fixtures needs a directory"
      FIXTURE_DIR="$2"
      shift 2
      ;;
    --implementer)
      [ $# -ge 2 ] || die "--implementer needs an event name"
      IMPLEMENTERS="$IMPLEMENTERS $2"
      shift 2
      ;;
    -h | --help)
      sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq is not on PATH, so hook registrations cannot be parsed — refusing (fail closed)"
[ -d "$FIXTURE_DIR" ] || die "no payload-fixture directory at $FIXTURE_DIR — refusing (fail closed)"
# A registration carries the plugin root and the hook's arguments separated by
# the same whitespace, so a root containing any is unsplittable: the split would
# hand back a truncated script path and every registered hook would be reported
# as a missing file — a refusal naming a path nobody registered, which is
# exactly what REQ-K1.1 forbids. Say what cannot be established instead.
case $REPO_ROOT in
  *[[:space:]]*)
    die "this checkout's path contains whitespace ($REPO_ROOT), so a registered command cannot be split back into its script and arguments — refusing (fail closed). Check out the repository at a path without whitespace to run this guard."
    ;;
esac
for hf in "${HOOKS_FILES[@]}"; do
  [ -f "$hf" ] || die "no hooks registration file at $hf — refusing (fail closed)"
  jq -e . "$hf" >/dev/null 2>&1 || die "$hf is not parseable JSON — refusing (fail closed)"
done

# Somewhere disposable for any state a checked handler decides to write.
SCRATCH=$(mktemp -d) || die "could not create a scratch directory for hook execution"
trap 'rm -rf "$SCRATCH"' EXIT INT TERM

findings=0
finding() {
  # finding <what> <remedy>
  findings=$((findings + 1))
  printf '\n  [%d] %s\n      remedy: %s\n' "$findings" "$1" "$2"
}

contract_row() {
  # contract_row <event> — the table row, or empty when unmodelled.
  printf '%s\n' "$CONTRACTS" | while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in "$1|"*) printf '%s\n' "$row" ;; esac
  done
}

is_implementer() {
  # is_implementer <event>
  case " $IMPLEMENTERS " in *" $1 "*) return 0 ;; esac
  return 1
}

resolve_command() {
  # resolve_command <command-string> — substitute the plugin root and drop the
  # quoting the harness strips, printing the WHOLE command, arguments included.
  # The arguments are not incidental: every liveness hook is registered as
  # `fleet-liveness.sh hook <event>`, so running the bare script would exercise
  # an invocation the harness never makes and report clean over a handler never
  # actually checked. Substitution is shell string replacement rather than sed:
  # a repo path may legally contain `&` or a delimiter, which sed reinterprets.
  rc_s=${1//\$\{CLAUDE_PLUGIN_ROOT\}/$REPO_ROOT}
  rc_s=${rc_s//\$CLAUDE_PLUGIN_ROOT/$REPO_ROOT}
  rc_s=${rc_s//\"/}
  printf '%s' "$rc_s"
}

run_hook() {
  # run_hook <script> <args...> — feed the event fixture on stdin, capture
  # stdout. Bounded, and stderr is discarded exactly as the harness discards it
  # (checking what an operator would actually see, not what the hook wishes it
  # had said).
  #
  # NEUTRALISED IDENTITY. These are the real handlers, and they have real side
  # effects. This guard runs inside `mise run check`, which runs inside
  # dispatched workers, where `PLANWRIGHT_WORKER_HANDLE`/`_SCOPE` are set — so
  # an un-neutralised run would have `fleet-liveness.sh` push liveness
  # transitions for whichever worker happens to be running CI, corrupting the
  # attention surface the operator reads. The identity vars are dropped and the
  # fleet state root is pointed at a scratch directory, so a handler that writes
  # state writes it somewhere disposable.
  if command -v timeout >/dev/null 2>&1; then
    env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
      PLANWRIGHT_FLEET_STATE_DIR="$SCRATCH/fleet" \
      timeout "$HOOK_TIMEOUT" "$@" 2>/dev/null
  else
    env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
      PLANWRIGHT_FLEET_STATE_DIR="$SCRATCH/fleet" \
      "$@" 2>/dev/null
  fi
}

# Registered (event, type, command) triples, tab-separated.
registrations=""
for hf in "${HOOKS_FILES[@]}"; do
  rows=$(jq -r --arg f "$hf" '
    (.hooks // {}) | to_entries[]
    | .key as $event
    | (.value // [])[]?
    | (.hooks // [])[]?
    | [$f, $event, (.type // "missing"), (.command // "")] | @tsv
  ' "$hf" 2>/dev/null) || die "could not read hook registrations from $hf — refusing (fail closed)"
  [ -z "$rows" ] || registrations="${registrations}${rows}
"
done

if [ -z "$registrations" ]; then
  printf 'hook-contracts: no hooks registered in %s — nothing to check.\n' "${HOOKS_FILES[*]}"
  exit 0
fi

checked_events=""
while IFS="$(printf '\t')" read -r source event type command; do
  [ -n "${event:-}" ] || continue
  where="${source#"$REPO_ROOT"/}"

  row=$(contract_row "$event")
  if [ -z "$row" ]; then
    finding "\`$event\` is registered in $where but this guard does not model it, so what its silence means is unknown." \
      "read the event's dispatch site out of the CLI, add a row to the CONTRACT TABLE in $(basename "$0") recording whether silence proceeds or refuses, and add a payload fixture."
    continue
  fi
  silence=$(printf '%s' "$row" | cut -d'|' -f2)
  control=$(printf '%s' "$row" | cut -d'|' -f3)
  noun=$(printf '%s' "$row" | cut -d'|' -f4)

  if [ "$type" != "command" ]; then
    finding "\`$event\` registers a hook of type \`$type\` in $where; this guard only models \`command\` hooks." \
      "use a command hook, or extend the guard to model this type before relying on it."
    continue
  fi

  # --- the payload fixture (REQ-H1.1) ---
  fixture="$FIXTURE_DIR/$event.json"
  if [ ! -f "$fixture" ]; then
    finding "\`$event\` is registered in $where but has no payload fixture, so nothing pins the schema its handler reads." \
      "add $fixture with the event's real stdin key set (see $FIXTURE_DIR/README.md for how to read it out of the CLI)."
    continue
  fi
  if ! jq -e . "$fixture" >/dev/null 2>&1; then
    finding "the \`$event\` payload fixture is not parseable JSON." \
      "repair $fixture."
    continue
  fi
  fixture_event=$(jq -r '.hook_event_name // ""' "$fixture" 2>/dev/null)
  if [ "$fixture_event" != "$event" ]; then
    finding "the \`$event\` fixture identifies itself as \`${fixture_event:-<absent>}\`." \
      "set hook_event_name to \"$event\" in $fixture."
    continue
  fi
  case " $checked_events " in *" $event "*) ;; *) checked_events="$checked_events $event" ;; esac

  # --- the registered command exists (REQ-K1.1) ---
  resolved=$(resolve_command "$command")
  # Split into argv the way the harness would; the script is the first word,
  # and the rest are the arguments the registration actually passes.
  read -r -a argv <<<"$resolved"
  script=${argv[0]:-}
  if [ -z "$script" ]; then
    finding "\`$event\` registers an empty command in $where." \
      "give the registration a command, or remove the block."
    continue
  fi
  if [ ! -f "$script" ]; then
    finding "\`$event\` registers \`$script\` in $where, which does not exist; the harness would report a hook failure with no way to tell a typo from a deleted file." \
      "correct the path in $where, or restore the script."
    continue
  fi
  if [ ! -x "$script" ]; then
    finding "\`$event\` registers \`$script\` in $where, which is not executable." \
      "chmod +x $script."
    continue
  fi

  # --- the silence rule (REQ-H1.2) ---
  if [ "$silence" = "refuses" ]; then
    if ! is_implementer "$event"; then
      finding "\`$event\` is registered to \`$(basename "$script")\`, but on this event silence refuses the operation: registering a hook REPLACES the native behaviour, so a handler that stays quiet has blocked it. This is the shape that broke worktree creation fleet-wide." \
        "unregister \`$event\` from $where unless this hook is the operation's implementer; if it genuinely is, declare it with --implementer $event so its output contract is checked."
      continue
    fi
    out=$(run_hook "${argv[@]}" <"$fixture")
    hook_rc=$?
    first=$(printf '%s' "$out" | sed -n '1p')
    if [ -z "$first" ]; then
      finding "\`$event\` is declared implemented by \`$(basename "$script")\`, but run against its own payload fixture it emitted no ${noun:-required output} — on this event that is a refusal, and the operation fails." \
        "make the handler read the fixture's keys and emit the ${noun:-required output} on stdout; check the key set in $fixture."
      continue
    fi
    # Emitting the output is necessary but not sufficient. The harness keeps
    # only the hooks that SUCCEEDED before it looks for the output, so a handler
    # that prints a perfect answer and then exits non-zero has its answer thrown
    # away — and on this event a discarded answer is silence, which refuses. The
    # decision branch below flags the mirror case; both are the same defect
    # reached from different sides.
    if [ "$hook_rc" -ne 0 ]; then
      finding "\`$event\`'s implementer \`$(basename "$script")\` emitted a ${noun:-required output} but exited $hook_rc, so the harness discards it and the operation refuses anyway — the emitted value never reaches it." \
        "exit 0 once the ${noun:-required output} is on stdout; report a genuine failure by emitting nothing, which refuses deliberately rather than by accident."
      continue
    fi
    case "$first" in
      /*) ;;
      *)
        finding "\`$event\`'s implementer emitted \`$first\`, which is not an absolute path." \
          "emit an absolute ${noun:-path} on stdout."
        continue
        ;;
    esac
    continue
  fi

  # --- the decision-output contract (REQ-H1.2) ---
  if [ "$control" = "decision" ]; then
    out=$(run_hook "${argv[@]}" <"$fixture")
    hook_rc=$?
    if [ -z "$out" ]; then
      # Silence proceeds here, so a clean exit is a legitimate no-op. A hook
      # that DIED is not that: it produced no decision because it could not
      # run, and running the hooks for real is the only reason this guard is
      # not a static scan. Treating the two alike would report clean over a
      # handler that never works (REQ-K1.1). `timeout` reports 124, so a hook
      # that hangs lands here too.
      if [ "$hook_rc" -ne 0 ]; then
        finding "\`$event\` is a decision event and \`$(basename "$script")\` exited $hook_rc against its own payload fixture without emitting anything, so whether it can produce a decision at all is unproven — a handler that dies looks exactly like one with nothing to say." \
          "run \`$(basename "$script")\` against $fixture and fix what it reports on stderr, or exit 0 when there is no decision to make."
      fi
      continue
    fi
    if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      finding "\`$event\` is a decision event and \`$(basename "$script")\` emitted output that is not JSON, so the harness cannot read a decision from it and the hook's intent is silently dropped." \
        "emit a hookSpecificOutput JSON object, or emit nothing at all when there is no decision to make."
      continue
    fi
    named=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)
    if [ -z "$named" ]; then
      finding "\`$event\`'s handler \`$(basename "$script")\` emitted JSON with no hookSpecificOutput.hookEventName, so the harness cannot route the decision." \
        "set hookSpecificOutput.hookEventName to \"$event\"."
      continue
    fi
    if [ "$named" != "$event" ]; then
      finding "\`$event\`'s handler \`$(basename "$script")\` emitted a decision naming hookEventName \`$named\`; the harness ignores it and the refusal never fires." \
        "set hookSpecificOutput.hookEventName to \"$event\" in $script."
      continue
    fi
  fi
done <<EOF
$registrations
EOF

if [ "$findings" -gt 0 ]; then
  printf '\nhook-contracts: %d finding(s) across %s\n' "$findings" "${HOOKS_FILES[*]#"$REPO_ROOT"/}" >&2
  exit 1
fi

n=$(printf '%s' "$checked_events" | wc -w | tr -d ' ')
checked_files="${HOOKS_FILES[*]#"$REPO_ROOT"/}"
printf 'hook-contracts: %s event(s) across %s — each fixture-pinned and contract-clean.\n' \
  "$n" "$checked_files"
exit 0
