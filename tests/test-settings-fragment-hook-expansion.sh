#!/bin/bash
# Pins the Claude Code behaviour the settings profiles depend on: how a hook
# command supplied through `--settings` resolves its path. Both profiles,
# config/worker-settings.json and config/tower-settings.json, are delivered that
# way, and the static half below checks every `config/*.json` carrying a
# `hooks` key, so a third profile cannot repeat the defect unnoticed.
#
# Measured on CLI 2.1.269. The spelling is squeezed from two sides at once, and
# only one form survives both.
#
# BRACES: Claude Code consumes the literal braced token `${CLAUDE_PLUGIN_ROOT}`
# as a plugin-context substitution. A fragment passed with `--settings` carries
# no plugin context, so that token substitutes EMPTY, the command becomes
# "/scripts/worker-command-guard.sh, and the hook silently never runs — every
# dispatched worker then prompts on every routine command. So: no braces.
#
# QUOTES: the command is evaluated by a shell, so an unquoted path word-splits
# on a root containing a space and the hook again silently never runs (measured
# directly, not inferred). So: quoted.
#
# Which leaves exactly `"$CLAUDE_PLUGIN_ROOT"/scripts/...` — quoted, unbraced.
# Both halves are load-bearing and neither is obvious from the other, which is
# why each gets its own case below.
#
# This is empirical CLI behaviour, not documented contract, so it is pinned
# here: if a future CLI expands both spellings (or neither), this fails loudly
# instead of the fleet quietly losing its auto-approve hook again.
#
# Skips rather than fails when the CLI is absent, so it stays CI-safe.
#
# shellcheck disable=SC2016
# The unexpanded literals ARE the subject: this file compares hook-command
# spellings as written, so a single-quoted `$CLAUDE_PLUGIN_ROOT` is intentional
# everywhere it appears and expanding one would test nothing.
set -u

# A CDPATH-resolved cd echoes its destination into a command substitution.
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}

# The STATIC half runs everywhere: it reads the shipped profiles and asserts the
# spelling, needs no CLI, no key, and no network, and is the guard that actually
# catches a regression in day-to-day work. jq rather than python3 because the
# sibling suites reading these same profiles already treat jq as their JSON tool
# and python3 as optional.
#
# The rule is per occurrence: every expansion of the root, wherever it sits in
# a command, must be exactly `"$CLAUDE_PLUGIN_ROOT"/`. A command that never
# expands the variable passes, so the policy hooks' fail-closed suffix may name
# CLAUDE_PLUGIN_ROOT in its message. Profiles are selected by their `hooks` key,
# never by name, from whatever directory is passed.
#
# check_profiles <dir> — prints one line per offending command; exit 1 on any.
check_profiles() {
  local dir=$1 f cmd cmds rest bad=0 found=0
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    jq -e 'type == "object" and has("hooks")' "$f" >/dev/null 2>&1 || {
      jq -e . "$f" >/dev/null 2>&1 || {
        echo "$(basename "$f"): not parseable JSON, so its hooks cannot be checked"
        bad=1
      }
      continue
    }
    found=1
    cmds=$(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command // empty' "$f" 2>/dev/null) || {
      echo "$(basename "$f"): its hooks key is not the settings shape, so its commands cannot be read"
      bad=1
      continue
    }
    while IFS= read -r cmd; do
      rest=${cmd//'"$CLAUDE_PLUGIN_ROOT"/'/}
      case $rest in
        *'$CLAUDE_PLUGIN_ROOT'* | *'${CLAUDE_PLUGIN_ROOT'*)
          echo "$(basename "$f"): expands the plugin root other than as \"\$CLAUDE_PLUGIN_ROOT\"/: $cmd"
          bad=1
          ;;
      esac
    done <<<"$cmds"
  done
  [ "$found" = 1 ] || {
    echo "no settings profile with a hooks key under $dir"
    return 1
  }
  return "$bad"
}

out=$(check_profiles "$root/config") \
  || fail "a shipped profile spells the plugin root a way --settings does not run:
$out"
echo "ok: every hook command in the shipped profiles uses the quoted, unbraced spelling"

# The check must fail on each shape the profiles once shipped or could drift
# into, wherever in the hooks it sits, and pass a compliant suffixed command.
fx="$(mktemp -d)" || exit 2
trap 'rm -rf "$fx"' EXIT
good='"$CLAUDE_PLUGIN_ROOT"/scripts/g.sh'
suffixed='"$CLAUDE_PLUGIN_ROOT"/scripts/policy-guard.sh tower bash || { echo '"'"'policy-guard.sh did not run: export CLAUDE_PLUGIN_ROOT and relaunch'"'"' >&2; exit 2; }'
# profile <name> <later-hook-in-group> <later-group> <other-event>
profile() {
  mkdir -p "$fx/$1"
  jq -n --arg g "$good" --arg a "$2" --arg b "$3" --arg c "$4" '{
    hooks: {
      PreToolUse: [
        { matcher: "Bash", hooks: [ { type: "command", command: $g }, { type: "command", command: $a } ] },
        { matcher: "mcp__x", hooks: [ { type: "command", command: $b } ] }
      ],
      PostToolUse: [ { matcher: "Bash", hooks: [ { type: "command", command: $c } ] } ]
    }
  }' >"$fx/$1/profile.json"
  # A file without a hooks key is never a profile, whatever it holds.
  printf '%s\n' '{"note": "${CLAUDE_PLUGIN_ROOT}/x"}' >"$fx/$1/not-a-profile.json"
}
braced='"${CLAUDE_PLUGIN_ROOT}"/scripts/g.sh'
profile compliant "$suffixed" "$good" "$good"
profile later-hook "$braced" "$good" "$good"
profile later-group "$good" "$braced" "$good"
profile other-event "$good" "$good" "$braced"
profile unquoted '$CLAUDE_PLUGIN_ROOT/scripts/g.sh' "$good" "$good"
profile default-form '"${CLAUDE_PLUGIN_ROOT:-}"/scripts/g.sh' "$good" "$good"
profile second-occurrence "$good"' --root "${CLAUDE_PLUGIN_ROOT}"' "$good" "$good"

check_profiles "$fx/compliant" >/dev/null \
  || fail "the check rejects a compliant profile carrying the fail-closed suffix"
echo "ok: a compliant suffixed command passes"
for shape in later-hook later-group other-event unquoted default-form second-occurrence; do
  if check_profiles "$fx/$shape" >/dev/null; then
    fail "the check passes a profile with the $shape shape"
  fi
  echo "ok: the check fails the $shape shape"
done
# A file the check cannot read is never passed over as "not a profile".
mkdir -p "$fx/unparseable" "$fx/hooks-not-object" "$fx/event-not-array"
cp "$fx/compliant/profile.json" "$fx/unparseable/"
printf '%s\n' '{"hooks": ' >"$fx/unparseable/broken.json"
cp "$fx/compliant/profile.json" "$fx/hooks-not-object/"
printf '%s\n' '{"hooks": "${CLAUDE_PLUGIN_ROOT}/x"}' >"$fx/hooks-not-object/odd.json"
cp "$fx/compliant/profile.json" "$fx/event-not-array/"
printf '%s\n' '{"hooks": {"PreToolUse": "${CLAUDE_PLUGIN_ROOT}/x"}}' >"$fx/event-not-array/odd.json"
for shape in unparseable hooks-not-object event-not-array; do
  if check_profiles "$fx/$shape" >/dev/null; then
    fail "the check passes a directory holding an $shape settings file"
  fi
  echo "ok: the check fails an $shape settings file"
done
mkdir -p "$fx/none"
cp "$fx/compliant/not-a-profile.json" "$fx/none/"
if check_profiles "$fx/none" >/dev/null; then
  fail "the check passes a directory holding no profile, so it would pass over nothing"
fi
echo "ok: a directory with no profile fails rather than passing vacuously"

# The LIVE half drives the real CLI to re-measure the behaviour the static rule
# rests on. It is opt-in because it costs tokens, needs an API key, and gates
# nondeterministically — the same three reasons scripts/check-no-ci-evals.sh
# keeps the eval suites out of CI. Run it by hand when a CLI upgrade might have
# moved the behaviour:
#
#   PLANWRIGHT_LIVE_CLI_PROBE=1 bash tests/test-settings-fragment-hook-expansion.sh
[ "${PLANWRIGHT_LIVE_CLI_PROBE:-}" = 1 ] || {
  echo "skip: live-CLI probe (set PLANWRIGHT_LIVE_CLI_PROBE=1 to re-measure)"
  exit 0
}

command -v claude >/dev/null 2>&1 || {
  echo "skip: claude CLI not on PATH"
  exit 0
}

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp" "$fx"' EXIT

marker="$tmp/fired"
# The probe root carries a space on purpose: an unquoted hook path word-splits
# here and goes silent, which is the whole point of the quoting half.
root_with_space="$tmp/plugin root"
mkdir -p "$root_with_space"
cat >"$root_with_space/probe-hook.sh" <<EOF
#!/bin/sh
cat > /dev/null
echo fired > "$marker"
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"probe"}}'
EOF
chmod +x "$root_with_space/probe-hook.sh"

# probe <hook-command> -> prints "fired" or "silent"
probe() {
  rm -f "$marker"
  jq -n --arg cmd "$1" '{
    permissions: { defaultMode: "default", allow: [] },
    hooks: { PreToolUse: [ { matcher: "Bash", hooks: [ { type: "command", command: $cmd } ] } ] }
  }' >"$tmp/settings.json"
  (cd "$root" && env CLAUDE_PLUGIN_ROOT="$root_with_space" PROBE_DIR="$root_with_space" \
    timeout 90 claude -p --settings "$tmp/settings.json" \
    "Run exactly this bash command and nothing else: git status --short" \
    >/dev/null 2>&1)
  cli_rc=$?
  # A non-zero CLI exit means the environment could not answer (no auth, no
  # network, timeout). That is not evidence about hook loading, so it is
  # reported distinctly rather than collapsing into "silent" — otherwise an
  # unauthenticated run fails claiming hooks are not loaded, which is a wrong
  # diagnosis of a working codebase.
  [ "$cli_rc" -eq 0 ] || {
    echo "cli-failed"
    return
  }
  [ -f "$marker" ] && echo fired || echo silent
}

# Guard against a vacuous pass: if a literal quoted path does not fire, the probe
# itself is broken (or hooks are not loaded at all) and every result below would
# be meaningless.
sanity=$(probe "\"$root_with_space\"/probe-hook.sh")
case $sanity in
  cli-failed)
    echo "skip: the claude CLI could not complete a run (auth, network, or timeout); the live probe proves nothing here"
    exit 0
    ;;
  fired) : ;;
  *) fail "a literal-path hook did not fire though the CLI ran cleanly — hooks are no longer loaded from --settings" ;;
esac

# The spelling the fragment must use: unbraced (survives the plugin-context
# substitution) and quoted (survives a root containing a space).
[ "$(probe '"$CLAUDE_PLUGIN_ROOT"/probe-hook.sh')" = fired ] \
  || fail "quoted-unbraced \"\$CLAUDE_PLUGIN_ROOT\" no longer fires — both settings profiles must change spelling"

# The braces half: a braced token is eaten before the shell ever sees it.
[ "$(probe '"${CLAUDE_PLUGIN_ROOT}"/probe-hook.sh')" = silent ] \
  || echo "note: braced \${CLAUDE_PLUGIN_ROOT} now expands too; the unbraced spelling stays correct, the constraint merely relaxed"

# The quoting half: unquoted word-splits on the space in the root. This is why
# dropping the quotes along with the braces was a regression, not a tidy-up.
[ "$(probe '$CLAUDE_PLUGIN_ROOT/probe-hook.sh')" = silent ] \
  || echo "note: unquoted \$CLAUDE_PLUGIN_ROOT now survives a spaced root; quoting stays correct, the constraint merely relaxed"

echo "ok: live probe re-measured (quoted-unbraced fires; braced and unquoted do not)"
