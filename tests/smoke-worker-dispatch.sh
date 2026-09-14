#!/bin/bash
# smoke-worker-dispatch.sh — prove a dispatched worker will not stall at the
# harness permission gate.
#
# WHY THIS EXISTS, AND WHY tests/test-worker-command-guard.sh IS NOT ENOUGH.
# On 2026-09-14 two dispatched workers stalled on their FIRST tool call and
# unattended fleet dispatch was impossible for weeks. The guard unit suite was
# green throughout. It was green because it asserts the shapes someone thought
# to write down, run against the REPO copy of the hook, called directly. Three
# things it therefore cannot see:
#
#   1. A read-only shape nobody enumerated (awk's `||`, `env | grep`, `jq`).
#      A unit suite only covers its own imagination; a corpus grown from real
#      stalls covers what workers actually ran.
#   2. The hook as config/worker-settings.json SPELLS it. That file carries a
#      deliberately unbraced, quoted "$CLAUDE_PLUGIN_ROOT" because the braced
#      form substitutes empty outside plugin context and the hook then silently
#      never runs. Calling the script by path cannot catch that class.
#   3. The INSTALLED PLUGIN CACHE. A worker loads the hook from
#      $CLAUDE_PLUGIN_ROOT — ~/.claude/plugins/cache/... — never from this
#      checkout. A fix merged to main does not reach a worker until the plugin
#      is reinstalled, so a repo-only test can be green while every worker on
#      the machine still stalls.
#
# So this smoke drives the hook through the settings-file spelling, and can
# point at either copy.
#
# ROOT
#   (default)     this checkout — the code CI is actually validating, so the
#                 suite stays deterministic and machine-independent.
#   --installed   the newest installed plugin cache: what a dispatched worker
#                 really loads. Not the default precisely because it is a
#                 machine-local condition; a stale cache is an operational
#                 fact, not a defect in the diff under review. This is the
#                 release-time check, run after updating the plugin.
#   --root <dir>  an explicit tree (e.g. a branch export, before merge).
#
# MODES
#   (default)  offline. Replay the corpus through the hook as wired. Fast,
#              deterministic, no model, no spend — safe for `mise run check`.
#   --live     additionally launch ONE real worker through
#              scripts/fleet-streamjson.sh and assert its receipt journal
#              records zero permission control_requests. Costs tokens and wall
#              clock; this is the release gate, not a CI gate.
#
# EXIT  0 all assertions held · 1 a corpus row or the live probe failed ·
#       2 the harness could not run (missing jq, unreadable root, no corpus).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="$REPO_ROOT/tests/fixtures/worker-guard-corpus.tsv"
SETTINGS="$REPO_ROOT/config/worker-settings.json"
ROOT=""
LIVE=0
TAB=$(printf '\t')
# The corpus is the evidence; a parse that yields fewer rows than this means
# the file was mangled, not that the guard got better.
MIN_ROWS=30

usage() {
  cat >&2 <<'USAGE'
usage: tests/smoke-worker-dispatch.sh [--root <dir> | --installed] [--corpus <file>] [--live]
  --root       tree the hook is loaded from (default: this checkout)
  --installed  use the newest installed plugin cache — what a dispatched
               worker actually loads (release-time check, not a CI gate)
  --corpus     expectation table (default: tests/fixtures/worker-guard-corpus.tsv)
  --live       also launch one real worker and assert zero permission requests
USAGE
  exit 2
}

while [ $# -gt 0 ]; do
  case $1 in
    --root)
      [ $# -ge 2 ] || usage
      ROOT=$2
      shift 2
      ;;
    --installed)
      ROOT=installed
      shift
      ;;
    --corpus)
      [ $# -ge 2 ] || usage
      CORPUS=$2
      shift 2
      ;;
    --live)
      LIVE=1
      shift
      ;;
    -h | --help) usage ;;
    *)
      echo "smoke: unknown argument: $1" >&2
      usage
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "smoke: jq is required" >&2
  exit 2
}

# --installed resolves the newest version directory under the plugin cache:
# what a dispatched worker really loads. It is opt-in, not the default,
# because a stale cache is a machine-local operational fact and would make a
# CI-gating suite fail for a reason that has nothing to do with the diff.
if [ "$ROOT" = installed ]; then
  cache_base="${HOME}/.claude/plugins/cache/planwright/planwright"
  ROOT=""
  if [ -d "$cache_base" ]; then
    ROOT=$(find "$cache_base" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null \
      | sed 's#.*/##' | sort -V | tail -1)
    [ -n "$ROOT" ] && ROOT="$cache_base/$ROOT"
  fi
  if [ -z "$ROOT" ]; then
    echo "smoke: --installed given but no plugin cache under $cache_base" >&2
    exit 2
  fi
fi
[ -n "$ROOT" ] || ROOT="$REPO_ROOT"

[ -d "$ROOT" ] || {
  echo "smoke: plugin root not a directory: $ROOT" >&2
  exit 2
}
[ -r "$CORPUS" ] || {
  echo "smoke: corpus not readable: $CORPUS" >&2
  exit 2
}
[ -r "$SETTINGS" ] || {
  echo "smoke: worker-settings not readable: $SETTINGS" >&2
  exit 2
}

# The hook command EXACTLY as the settings fragment spells it. Driving this
# string (rather than a path we compose here) is what makes the quoting and
# the unbraced-variable pin part of what the smoke actually asserts.
HOOK_CMD=$(jq -r '.hooks.PreToolUse[]
                  | select(.matcher == "Bash")
                  | .hooks[]
                  | select(.type == "command")
                  | .command' "$SETTINGS" 2>/dev/null | head -1)
if [ -z "$HOOK_CMD" ]; then
  echo "smoke: no PreToolUse Bash command hook in $SETTINGS" >&2
  exit 2
fi

echo "smoke: plugin root : $ROOT"
echo "smoke: hook command: $HOOK_CMD"
echo "smoke: corpus      : $CORPUS"
echo

# Report whether the root under test matches this checkout. A mismatch is not
# a failure (checking a stale cache is a legitimate thing to ask for) but it is
# exactly the confusion that cost weeks, so it is always stated.
if [ -r "$ROOT/scripts/worker-command-guard.sh" ]; then
  if cmp -s "$ROOT/scripts/worker-command-guard.sh" "$REPO_ROOT/scripts/worker-command-guard.sh"; then
    echo "smoke: deployed guard is IDENTICAL to this checkout"
  else
    echo "smoke: NOTE deployed guard DIFFERS from this checkout"
    echo "smoke:      (a fix here has not reached workers until the plugin is reinstalled)"
  fi
else
  echo "smoke: NOTE no worker-command-guard.sh under $ROOT" >&2
fi
echo

passes=0
failures=0
false_allows=0

# decide <command> -> prints "allow" or "defer"
decide() {
  local payload out
  payload=$(printf '%s' "$1" | jq -Rs \
    --arg cwd "$REPO_ROOT" \
    '{hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:.}, cwd:$cwd}')
  # Evaluated, not called by path: the settings spelling is under test.
  out=$(printf '%s' "$payload" \
    | CLAUDE_PLUGIN_ROOT="$ROOT" PLANWRIGHT_ROOT="$ROOT" \
      eval "$HOOK_CMD" 2>/dev/null)
  case $out in
    *'"permissionDecision"'*'"allow"'*) echo allow ;;
    *) echo defer ;;
  esac
}

# Positive control. A corpus row deferring and a hook that never ran look
# identical from here (defer IS silence), so before trusting a single `defer`
# verdict, prove the hook is reachable and decides: one canary that must
# allow, one that must defer. Without this, `--root` pointing anywhere at all
# reports every defer-expected row as passing.
canary_allow=$(decide 'true')
canary_defer=$(decide 'rm -rf /')
if [ "$canary_allow" != allow ] || [ "$canary_defer" != defer ]; then
  echo "smoke: POSITIVE CONTROL FAILED - the hook is not deciding" >&2
  echo "smoke:   expected allow for 'true', got $canary_allow" >&2
  echo "smoke:   expected defer for 'rm -rf /', got $canary_defer" >&2
  echo "smoke:   (a hook that cannot run defers everything, which would" >&2
  echo "smoke:    otherwise read as every defer-expected row passing)" >&2
  exit 2
fi
echo "smoke: positive control ok (hook reachable and deciding)"
echo

rows=0
lineno=0
while IFS= read -r line; do
  lineno=$((lineno + 1))
  line=${line%$'\r'}                       # tolerate a CRLF corpus
  trimmed=${line#"${line%%[![:space:]]*}"} # strip leading whitespace
  case $trimmed in '' | '#'*) continue ;; esac

  expect=${trimmed%%"$TAB"*}
  command=${trimmed#*"$TAB"}
  # A row whose tab was eaten (editor, copy-paste, patch mangling) would
  # otherwise be skipped silently and the suite would still report PASS.
  if [ "$expect" = "$trimmed" ] || [ -z "$command" ]; then
    echo "smoke: $CORPUS:$lineno: row has no tab separator" >&2
    exit 2
  fi
  case $expect in
    allow | defer) ;;
    *)
      echo "smoke: $CORPUS:$lineno: expectation must be allow|defer, got '$expect'" >&2
      exit 2
      ;;
  esac

  # The corpus is machine-independent by construction; the harness binds the
  # placeholder to whichever root is under test.
  command=${command//@@PLUGIN_ROOT@@/$ROOT}
  command=${command//@@REPO_ROOT@@/$REPO_ROOT}

  rows=$((rows + 1))
  got=$(decide "$command")
  if [ "$got" = "$expect" ]; then
    passes=$((passes + 1))
  else
    failures=$((failures + 1))
    # An unexpected ALLOW is a security regression; an unexpected DEFER is a
    # worker stall. Both fail, but they are not the same severity of wrong.
    if [ "$got" = allow ]; then
      false_allows=$((false_allows + 1))
      printf 'FALSE-ALLOW (security regression): %s\n' "$command" >&2
    else
      printf 'STALL (expected allow, got defer): %s\n' "$command" >&2
    fi
  fi
done <"$CORPUS"

# A corpus that parsed to nothing is not a pass. Every other guard in this
# repo fails closed on an empty scan; this one used to report PASS.
if [ "$rows" -lt "$MIN_ROWS" ]; then
  echo "smoke: corpus yielded $rows row(s), below the floor of $MIN_ROWS" >&2
  exit 2
fi

echo
printf 'smoke: corpus %d passed, %d failed (%d false-allow)\n' \
  "$passes" "$failures" "$false_allows"

if [ "$LIVE" = 1 ]; then
  echo
  echo "smoke: --live probe"
  probe_prompt=$(mktemp) || exit 2
  probe_dir=""
  # shellcheck disable=SC2329  # invoked by the EXIT trap below
  cleanup() {
    rm -f "$probe_prompt"
    [ -n "$probe_dir" ] && "$ROOT/scripts/fleet-streamjson.sh" stop smoke-probe >/dev/null 2>&1
  }
  trap cleanup EXIT

  # The probe runs the corpus's allow-expected commands and nothing else. If
  # the hook is wired and correct, the worker completes without ever reaching
  # the permission gate.
  {
    echo "Run each of these commands exactly as written, in order, one Bash call each."
    echo "Do not modify them. Do not explain. Report only the count you ran."
    echo
    awk -F'\t' '$1 == "allow" { print "  " $2 }' "$CORPUS" | head -12
  } >"$probe_prompt"

  if "$ROOT/scripts/fleet-streamjson.sh" launch smoke-probe smoke:probe \
    --prompt-file "$probe_prompt" --cwd "$REPO_ROOT" >/dev/null 2>&1; then
    probe_dir="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/planwright-planwright}/fleet/streamjson/smoke-probe"
    # Poll to completion or to the first permission request, whichever lands
    # first: a stall is the thing under test, so it must not be waited out.
    waited=0
    perms=0
    while [ "$waited" -lt 300 ]; do
      if [ -r "$probe_dir/journal" ]; then
        perms=$(awk -F'\t' '$2 == "permission"' "$probe_dir/journal" 2>/dev/null | wc -l)
        [ "$perms" -gt 0 ] && break
      fi
      [ -r "$probe_dir/result" ] && break
      sleep 5
      waited=$((waited + 5))
    done

    if [ "${perms:-0}" -gt 0 ]; then
      failures=$((failures + 1))
      echo "smoke: LIVE FAIL — worker hit $perms permission request(s):" >&2
      while IFS=$'\t' read -r id kind _rest; do
        [ "$kind" = permission ] || continue
        jq -r '"  " + (.request.input.command // "?")' \
          "$probe_dir/req-$id.json" 2>/dev/null
      done <"$probe_dir/journal" >&2
    elif [ "$waited" -ge 300 ]; then
      failures=$((failures + 1))
      echo "smoke: LIVE FAIL — probe worker did not finish within 300s" >&2
    else
      echo "smoke: LIVE PASS — probe completed with zero permission requests"
    fi
  else
    failures=$((failures + 1))
    echo "smoke: LIVE FAIL — could not launch the probe worker" >&2
  fi
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "smoke: PASS"
  exit 0
fi
echo "smoke: FAIL ($failures)" >&2
exit 1
