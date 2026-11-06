#!/bin/bash
# Tests for scripts/fleet-usage-mirror.sh: the writer of the status-line usage
# mirror, its statusline wrapper, the spend-limit weekly reading, the opt-out,
# and that a write never blanks the wrapped status line. Each case is named in
# its own `ok:` line.
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-usage-mirror.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FUM="$here/../scripts/fleet-usage-mirror.sh"
FUG="$here/../scripts/fleet-usage-gate.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FUM" ] || fail "scripts/fleet-usage-mirror.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# HOME and XDG_CACHE_HOME are pinned to scratch dirs for the whole file: the
# writer resolves the mirror from them, and an unpinned call writes the
# operator's live mirror.
export HOME="$tmp/home"
xdg_cache="$tmp/xdg-cache"
export XDG_CACHE_HOME="$xdg_cache"
mkdir -p "$HOME"
mirror_file="$xdg_cache/claude-usage/rate-limits.json"
core_cfg="$tmp/core-defaults.yml"
repo="$tmp/repo"
adopter_root="$tmp/adopter"
mkdir -p "$repo/.claude" "$adopter_root"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$repo"
cat >"$core_cfg" <<'EOF'
fleet_usage_read_cadence_seconds: 60
fleet_usage_signal_ttl_seconds: 300
EOF

unset PLANWRIGHT_USAGE_MIRROR

now_s=$(date +%s)
in_hour=$((now_s + 7200))
in_day=$((now_s + 259200))
in_month=$((now_s + 1209600))

full_payload="{\"session_id\":\"abc\",\"model\":{\"display_name\":\"Opus\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":23.5,\"resets_at\":$in_hour},\"seven_day\":{\"used_percentage\":41.2,\"resets_at\":$in_day}}}"
spend_payload="{\"session_id\":\"abc\",\"rate_limits\":{\"spend_limit\":{\"used_percentage\":112.4,\"resets_at\":$in_month,\"used_usd\":1124.0,\"limit_usd\":1000,\"period\":\"monthly\"}}}"
bare_payload='{"session_id":"abc","model":{"display_name":"Opus"}}'

reset_state() {
  rm -rf "$xdg_cache"
}

# gate_run: the gate's read-only `signal`, against this test's cache and config.
gate_run() {
  PATH="$tmp/no-llm:$PATH" \
    XDG_CACHE_HOME="$xdg_cache" \
    PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FUG" "$@"
}

sig_of() {
  printf '%s\n' "$2" | awk -F'\t' -v w="$1" '$1==w{print $2; exit}'
}

# --- 1. A full status-line payload writes both windows; the gate reads them. ---
reset_state
printf '%s\n' "$full_payload" | /bin/bash "$FUM" write || fail "write (full payload) exited non-zero"
[ -f "$mirror_file" ] || fail "write must create the mirror at \$XDG_CACHE_HOME/claude-usage/rate-limits.json"
sig=$(gate_run signal) || fail "gate signal on a writer-made mirror failed"
[ "$(sig_of session "$sig")" = 23 ] || fail "the five_hour window must round-trip (got: $sig)"
[ "$(sig_of weekly "$sig")" = 41 ] || fail "the seven_day window must round-trip (got: $sig)"
echo "ok: a full status-line payload writes both windows and the gate reads them"

# --- 2. No rate_limits: nothing is written, nothing fails. ---
reset_state
rc=0
printf '%s\n' "$bare_payload" | /bin/bash "$FUM" write >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "a payload without rate_limits must exit 0 (got $rc)"
[ ! -e "$mirror_file" ] || fail "a payload without rate_limits must not write a mirror"
echo "ok: a payload without rate_limits writes nothing and exits 0"

# --- 3. A dollar-budget account: spend_limit is the weekly window, clamped. ---
reset_state
printf '%s\n' "$spend_payload" | /bin/bash "$FUM" write || fail "write (spend payload) exited non-zero"
sig=$(gate_run signal) || fail "gate signal on a spend-limit mirror failed"
[ "$(sig_of session "$sig")" = unavailable ] || fail "a spend-only account has no session window (got: $sig)"
[ "$(sig_of weekly "$sig")" = 100 ] || fail "an over-limit spend must clamp to 100 so the top rung engages (got: $sig)"
echo "ok: a dollar-budget account's spend_limit reads as the weekly window, clamped to 100"

# --- 4. Opt-out and relative override write nothing. ---
reset_state
printf '%s\n' "$full_payload" | PLANWRIGHT_USAGE_MIRROR= /bin/bash "$FUM" write || fail "opt-out write exited non-zero"
[ ! -e "$mirror_file" ] || fail "PLANWRIGHT_USAGE_MIRROR set empty must disable the writer"
(cd "$tmp" && printf '%s\n' "$full_payload" | PLANWRIGHT_USAGE_MIRROR=rel/rate-limits.json /bin/bash "$FUM" write) \
  || fail "relative-override write exited non-zero"
[ ! -e "$tmp/rel/rate-limits.json" ] || fail "a relative PLANWRIGHT_USAGE_MIRROR must be refused"
echo "ok: the opt-out and a relative override write nothing"

# --- 5. A non-JSON payload leaves an earlier mirror untouched. ---
reset_state
printf '%s\n' "$full_payload" | /bin/bash "$FUM" write
before=$(cat "$mirror_file")
printf 'not json at all \001\n' | /bin/bash "$FUM" write || fail "write (garbage payload) exited non-zero"
[ "$(cat "$mirror_file")" = "$before" ] || fail "a garbage payload must not overwrite a good mirror"
echo "ok: a non-JSON payload leaves the earlier mirror in place"

# --- 6. No temp file is left beside the mirror after a write. ---
reset_state
printf '%s\n' "$full_payload" | /bin/bash "$FUM" write
printf '%s\n' "$spend_payload" | /bin/bash "$FUM" write
leftovers=$(find "$(dirname "$mirror_file")" -mindepth 1 ! -name rate-limits.json | wc -l | tr -d ' ')
[ "$leftovers" = 0 ] || fail "a write must leave no temp file beside the mirror (found $leftovers)"
echo "ok: the write is atomic and leaves no temp file"

# --- 7. The statusline form passes stdin through to the wrapped command, its
#        stdout and exit status unchanged, and still writes the mirror. ---
reset_state
out=$(printf '%s\n' "$full_payload" | /bin/bash "$FUM" statusline "cat; echo rendered; exit 3") && rc=0 || rc=$?
[ "$rc" = 3 ] || fail "the wrapper must pass the wrapped command's exit status through (got $rc)"
case $out in
  *'"rate_limits"'*rendered) ;;
  *) fail "the wrapped command must receive the stdin payload and its output must pass through (got: $out)" ;;
esac
[ -f "$mirror_file" ] || fail "the statusline form must write the mirror"
echo "ok: the statusline form passes stdin and output through and writes the mirror"

# --- 8. The statusline form still runs the wrapped command when the writer
#        cannot write (the mirror's directory is a regular file). ---
reset_state
mkdir -p "$xdg_cache"
printf 'blocker\n' >"$xdg_cache/claude-usage"
out=$(printf '%s\n' "$full_payload" | /bin/bash "$FUM" statusline "echo still-rendered") && rc=0 || rc=$?
[ "$rc" = 0 ] || fail "an unwritable mirror must not fail the status line (got $rc)"
[ "$out" = still-rendered ] || fail "an unwritable mirror must still render the wrapped line (got: $out)"
echo "ok: an unwritable mirror never blanks the wrapped status line"

# --- 9. The statusline form with no wrapped command prints nothing. ---
reset_state
out=$(printf '%s\n' "$full_payload" | /bin/bash "$FUM" statusline) && rc=0 || rc=$?
[ "$rc" = 0 ] || fail "statusline with no command must exit 0 (got $rc)"
[ -z "$out" ] || fail "statusline with no command must print nothing (got: $out)"
[ -f "$mirror_file" ] || fail "statusline with no command must still write the mirror"
echo "ok: the statusline form with no command prints nothing and still writes"

echo "ALL fleet-usage-mirror tests passed"
