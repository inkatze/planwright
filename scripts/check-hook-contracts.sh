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
# an unreadable or unparseable `hooks.json`, a missing fixture directory, an
# event the contract table below does not model (its silence semantics are
# exactly what must not be assumed), a registered event with no payload fixture,
# a registered command that is absent or not executable, and a hook type other
# than `command`.
#
# THE CONTRACT TABLE below is this guard's own knowledge and the reason it can
# be trusted: each row was read out of the CLI's payload construction and
# dispatch sites rather than the published docs, which omit `WorktreeCreate`'s
# input schema and have drifted on several others. Adding a row is a deliberate
# act — it asserts you checked what silence means on that event.
#
# IT RUNS THE HOOKS IT CHECKS. Proving a decision hook satisfies its output
# contract means feeding it the event's fixture and reading what comes back —
# a static scan cannot tell a handler that emits a decision from one that
# intends to. The commands come from the repo's own tracked `hooks.json`, which
# is as trusted as the rest of the checkout, and each run is bounded by
# `timeout`. Point `--hooks` at a registration file you do not trust and you are
# executing its commands; that flag exists for this guard's own tests.
#
# Usage: check-hook-contracts.sh [--hooks <hooks.json>] [--fixtures <dir>]
#                               [--implementer <Event>]...
# Exit:  0 clean · 1 findings · 2 usage or environment error (fail closed).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/hook-payloads"
IMPLEMENTERS=""
HOOK_TIMEOUT=20

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
      HOOKS_JSON="$2"
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

command -v jq >/dev/null 2>&1 || die "jq is not on PATH, so hooks.json cannot be parsed — refusing (fail closed)"
[ -f "$HOOKS_JSON" ] || die "no hooks registration file at $HOOKS_JSON — refusing (fail closed)"
[ -d "$FIXTURE_DIR" ] || die "no payload-fixture directory at $FIXTURE_DIR — refusing (fail closed)"
jq -e . "$HOOKS_JSON" >/dev/null 2>&1 || die "$HOOKS_JSON is not parseable JSON — refusing (fail closed)"

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
  # resolve_command <command-string> — substitute the plugin root, drop the
  # quoting the harness strips, and print the script path (first token) alone.
  # Substitution is shell string replacement rather than sed: a repo path may
  # legally contain `&` or the delimiter, both of which sed would reinterpret.
  rc_s=${1//\$\{CLAUDE_PLUGIN_ROOT\}/$REPO_ROOT}
  rc_s=${rc_s//\$CLAUDE_PLUGIN_ROOT/$REPO_ROOT}
  rc_s=${rc_s//\"/}
  printf '%s' "${rc_s%% *}"
}

run_hook() {
  # run_hook <script> <args...> — feed the event fixture on stdin, capture
  # stdout. Bounded, and stderr is discarded exactly as the harness discards it
  # (checking what an operator would actually see, not what the hook wishes it
  # had said).
  if command -v timeout >/dev/null 2>&1; then
    timeout "$HOOK_TIMEOUT" "$@" 2>/dev/null </dev/stdin
  else
    "$@" 2>/dev/null </dev/stdin
  fi
}

# Registered (event, type, command) triples, tab-separated.
registrations=$(jq -r '
  (.hooks // {}) | to_entries[]
  | .key as $event
  | (.value // [])[]?
  | (.hooks // [])[]?
  | [$event, (.type // "missing"), (.command // "")] | @tsv
' "$HOOKS_JSON" 2>/dev/null) || die "could not read hook registrations from $HOOKS_JSON — refusing (fail closed)"

if [ -z "$registrations" ]; then
  printf 'hook-contracts: %s registers no hooks — nothing to check.\n' "$HOOKS_JSON"
  exit 0
fi

checked_events=""
while IFS="$(printf '\t')" read -r event type command; do
  [ -n "${event:-}" ] || continue

  row=$(contract_row "$event")
  if [ -z "$row" ]; then
    finding "\`$event\` is registered but this guard does not model it, so what its silence means is unknown." \
      "read the event's dispatch site out of the CLI, add a row to the CONTRACT TABLE in $(basename "$0") recording whether silence proceeds or refuses, and add a payload fixture."
    continue
  fi
  silence=$(printf '%s' "$row" | cut -d'|' -f2)
  control=$(printf '%s' "$row" | cut -d'|' -f3)
  noun=$(printf '%s' "$row" | cut -d'|' -f4)

  if [ "$type" != "command" ]; then
    finding "\`$event\` registers a hook of type \`$type\`; this guard only models \`command\` hooks." \
      "use a command hook, or extend the guard to model this type before relying on it."
    continue
  fi

  # --- the payload fixture (REQ-H1.1) ---
  fixture="$FIXTURE_DIR/$event.json"
  if [ ! -f "$fixture" ]; then
    finding "\`$event\` is registered but has no payload fixture, so nothing pins the schema its handler reads." \
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
  script=$(resolve_command "$command")
  if [ -z "$script" ]; then
    finding "\`$event\` registers an empty command." \
      "give the registration a command, or remove the block."
    continue
  fi
  if [ ! -f "$script" ]; then
    finding "\`$event\` registers \`$script\`, which does not exist; the harness would report a hook failure with no way to tell a typo from a deleted file." \
      "correct the path in $HOOKS_JSON, or restore the script."
    continue
  fi
  if [ ! -x "$script" ]; then
    finding "\`$event\` registers \`$script\`, which is not executable." \
      "chmod +x $script."
    continue
  fi

  # --- the silence rule (REQ-H1.2) ---
  if [ "$silence" = "refuses" ]; then
    if ! is_implementer "$event"; then
      finding "\`$event\` is registered to \`$(basename "$script")\`, but on this event silence refuses the operation: registering a hook REPLACES the native behaviour, so a handler that stays quiet has blocked it. This is the shape that broke worktree creation fleet-wide." \
        "unregister \`$event\` unless this hook is the operation's implementer; if it genuinely is, declare it with --implementer $event so its output contract is checked."
      continue
    fi
    out=$(run_hook "$script" <"$fixture")
    first=$(printf '%s' "$out" | sed -n '1p')
    if [ -z "$first" ]; then
      finding "\`$event\` is declared implemented by \`$(basename "$script")\`, but run against its own payload fixture it emitted no ${noun:-required output} — on this event that is a refusal, and the operation fails." \
        "make the handler read the fixture's keys and emit the ${noun:-required output} on stdout; check the key set in $fixture."
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
    out=$(run_hook "$script" <"$fixture")
    [ -n "$out" ] || continue # silence proceeds here: a legitimate no-op.
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
  printf '\nhook-contracts: %d finding(s) in %s\n' "$findings" "$HOOKS_JSON" >&2
  exit 1
fi

n=$(printf '%s' "$checked_events" | wc -w | tr -d ' ')
printf 'hook-contracts: %s event(s) registered in %s, each fixture-pinned and contract-clean.\n' \
  "$n" "$HOOKS_JSON"
exit 0
