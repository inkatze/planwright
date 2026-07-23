#!/bin/bash
# Tests for scripts/resolve-dispatch-backend.sh — the dispatch-time
# `dispatch_backend` resolver (execution-backends Task 5; D-8, D-9;
# REQ-B1.1–REQ-B1.5).
#
# Contract under test:
#   - `resolve <spec-dir> [--attended --session <token>]` reads the configured
#     backend through the four-layer config overlay — the per-spec entry in the
#     `dispatch_backend_per_spec` inline map when the winning map carries one,
#     else the global `dispatch_backend` value — and prints TSV rows:
#         configured<TAB><value><TAB><per-spec|global>
#         backend<TAB><resolved-backend>
#     plus, exactly when the tmux-context ask should be surfaced this call,
#         ask<TAB>tmux
#   - The per-spec entry WINS over the global value in every layer combination
#     (REQ-B1.3): specificity beats layer precedence across the two keys; an
#     absent per-spec entry falls through to the global value.
#   - `full-session` (the semantic value, REQ-B1.1) resolves via the pinned
#     ladder to the richest present NON-interactive session-grade rung
#     (stream-json-persistent > headless-oneshot), degrading to subagent then
#     in-session; never tmux without the operator's tmux-context answer, never
#     the manual print rung (REQ-B1.4).
#   - An explicitly configured literal is honored when present — including an
#     interactive backend: explicit config is the operator's standing answer —
#     and FAILS CLOSED when not advertised on the host (exit 6, the halt the
#     dispatching skill parks to Awaiting input; stderr names the missing
#     backend; no substitute row on stdout) (REQ-B1.5).
#   - The tmux-context ask (D-8): surfaced only when --attended AND $TMUX is
#     set AND the configured value is full-session AND this tower session has
#     not been asked. Non-blocking: an unanswered ask resolves unattended
#     immediately. Re-ask is suppressed within one tower session via the
#     spec-local ask-state (<spec-dir>/.orchestrate/tmux-ask); a NEW session
#     token re-asks (once per tower session). `answer <spec-dir> --session
#     <token> <yes|no>` records the operator's answer; a `yes` from the same
#     session adds tmux to the candidate set from the next resolve onward.
#     Outside tmux context, attended resolution matches unattended exactly.
#   - Operator-default only (REQ-B1.2): the resolver takes NO per-task
#     parameter — an extra positional is a usage error (exit 2).
#   - The by-layer malformed policy (customization-overlay REQ-E1.4): a
#     malformed repo-tracked value hard-fails (exit 4); a malformed
#     adopter/machine-local value warns and degrades to the core default.
#   - The shipped default flip (REQ-B1.1): config/defaults.yml carries
#     `dispatch_backend: full-session` (asserted directly, not only doc parity).
#   - Input-as-data: a hostile spec-dir basename or session token is refused
#     (exit 2) before any path or command use; an ask-state path occupied by a
#     symlink is never written through.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH
# Hermeticity: presence overrides and tmux context are controlled per
# invocation; ambient values must not leak in.
unset PLANWRIGHT_BACKEND_TMUX PLANWRIGHT_BACKEND_SUBAGENT \
  PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT PLANWRIGHT_BACKEND_HEADLESS_ONESHOT \
  TMUX 2>/dev/null || true

here=$(cd "$(dirname "$0")" && pwd)
RDB="$here/../scripts/resolve-dispatch-backend.sh"
REAL_DEFAULTS="$here/../config/defaults.yml"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RDB" ] || fail "scripts/resolve-dispatch-backend.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
err="$tmp/err"

# Layer fixture files (the test-config-get.sh four-layer wiring).
core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# The spec dir the resolver is pointed at (basename is the per-spec map key).
specdir="$tmp/specs/myspec"
mkdir -p "$specdir"

reset_layers() {
  rm -f "$core_cfg" "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
  printf 'dispatch_backend: full-session\n' >"$core_cfg"
}
reset_ask() {
  rm -rf "$specdir/.orchestrate"
}

# run_rdb [env VAR=... style pairs via leading words] -- <args...>
# All invocations wire the four layers and pin TMUX unset unless the caller
# overrides. Backend presence defaults: subagent forced present, everything
# else forced absent, so the ladder outcome is deterministic on any host.
run_rdb() {
  env -u TMUX \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    PLANWRIGHT_BACKEND_TMUX=0 \
    PLANWRIGHT_BACKEND_SUBAGENT=1 \
    PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=0 \
    PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=0 \
    "$@" /bin/sh "$RDB" resolve "$specdir"
}

row_of() { # <output> <tag> -> the row's remaining fields
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" '$1==t {sub("^" t "\t", ""); print; found=1} END{if(!found) exit 3}'
}
has_row() {
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" '$1==t {f=1} END{exit f?0:1}'
}

# ---------------------------------------------------------------------------
# 1. Global full-session (core default): resolves down the pinned ladder to
#    the richest present non-interactive session-grade rung.
# ---------------------------------------------------------------------------
reset_layers
out=$(run_rdb PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=1) \
  || fail "resolve(full-session, sjp present) exited non-zero"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "full-session should resolve to stream-json-persistent when present, got '$(row_of "$out" backend)'"
[ "$(row_of "$out" configured)" = "full-session${TAB}global" ] \
  || fail "configured row should carry 'full-session<TAB>global', got '$(row_of "$out" configured)'"
out=$(run_rdb PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=1) \
  || fail "resolve(full-session, ho present) exited non-zero"
[ "$(row_of "$out" backend)" = headless-oneshot ] \
  || fail "full-session should walk the ladder to headless-oneshot, got '$(row_of "$out" backend)'"
out=$(run_rdb) || fail "resolve(full-session, no session rung) exited non-zero"
[ "$(row_of "$out" backend)" = subagent ] \
  || fail "full-session with no session-grade rung should degrade to subagent, got '$(row_of "$out" backend)'"
out=$(run_rdb PLANWRIGHT_BACKEND_SUBAGENT=0) \
  || fail "resolve(full-session, no subagent) exited non-zero"
[ "$(row_of "$out" backend)" = in-session ] \
  || fail "full-session should reach the in-session terminal rung, got '$(row_of "$out" backend)'"
echo "ok: full-session walks the pinned ladder over present non-interactive rungs"

# ---------------------------------------------------------------------------
# 2. Unattended matrix (REQ-B1.4): with full-session configured, no presence
#    combination ever resolves to an interactive or manual backend, and $TMUX
#    in the environment does not change the unattended result.
# ---------------------------------------------------------------------------
reset_layers
for tmx in 0 1; do
  for sjp in 0 1; do
    for ho in 0 1; do
      out=$(run_rdb PLANWRIGHT_BACKEND_TMUX=$tmx \
        PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=$sjp \
        PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=$ho TMUX=/tmp/tmux-sock,1,0) \
        || fail "unattended matrix (tmux=$tmx sjp=$sjp ho=$ho) exited non-zero"
      sel=$(row_of "$out" backend)
      [ "$sel" != tmux ] || fail "unattended matrix picked interactive tmux (tmux=$tmx sjp=$sjp ho=$ho)"
      [ "$sel" != print ] || fail "unattended matrix picked manual print"
      has_row "$out" ask && fail "unattended resolve must never surface the tmux ask"
    done
  done
done
echo "ok: unattended full-session never resolves interactive or manual, regardless of \$TMUX"

# ---------------------------------------------------------------------------
# 3. Per-spec map wins over the global value in EVERY layer combination
#    (REQ-B1.3), and an absent per-spec entry falls through to the global.
# ---------------------------------------------------------------------------
set_layer() { # <layer> <content>
  case "$1" in
    core) printf '%s\n' "$2" >>"$core_cfg" ;;
    adopter) printf '%s\n' "$2" >>"$adopter_cfg" ;;
    repo-tracked) printf '%s\n' "$2" >>"$tracked_cfg" ;;
    machine-local) printf '%s\n' "$2" >>"$mlocal_cfg" ;;
  esac
}
for gl in core adopter repo-tracked machine-local; do
  for pl in core adopter repo-tracked machine-local; do
    reset_layers
    rm -f "$core_cfg"
    : >"$core_cfg"
    set_layer "$gl" 'dispatch_backend: subagent'
    set_layer "$pl" 'dispatch_backend_per_spec: {myspec: in-session, other: subagent}'
    out=$(run_rdb) || fail "per-spec combo (global=$gl map=$pl) exited non-zero"
    [ "$(row_of "$out" backend)" = in-session ] \
      || fail "per-spec entry must win over the global value (global=$gl map=$pl), got '$(row_of "$out" backend)'"
    [ "$(row_of "$out" configured)" = "in-session${TAB}per-spec" ] \
      || fail "configured row should mark the per-spec source (global=$gl map=$pl)"
  done
done
# Absent per-spec entry falls through to the global value.
reset_layers
printf 'dispatch_backend_per_spec: {other: in-session}\n' >"$tracked_cfg"
printf 'dispatch_backend: subagent\n' >"$mlocal_cfg"
out=$(run_rdb) || fail "absent per-spec entry resolve exited non-zero"
[ "$(row_of "$out" backend)" = subagent ] \
  || fail "an absent per-spec entry must fall through to the global value"
[ "$(row_of "$out" configured)" = "subagent${TAB}global" ] \
  || fail "fall-through configured row should mark the global source"
echo "ok: per-spec map wins over the global value in every layer combination"

# ---------------------------------------------------------------------------
# 4. Explicit-but-unavailable fails closed (REQ-B1.5): exit 6, stderr names
#    the missing backend, and stdout carries NO substitute backend row —
#    global and per-spec variants.
# ---------------------------------------------------------------------------
reset_layers
printf 'dispatch_backend: headless-oneshot\n' >"$mlocal_cfg"
rc=0
out=$(run_rdb 2>"$err") || rc=$?
[ "$rc" = 6 ] || fail "explicit absent global backend should exit 6, got $rc"
grep -q "headless-oneshot" "$err" || fail "the halt diagnostic must name the missing backend"
if [ -n "$out" ] && has_row "$out" backend; then
  fail "a fail-closed halt must not print a substitute backend row"
fi
reset_layers
printf 'dispatch_backend_per_spec: {myspec: tmux}\n' >"$tracked_cfg"
rc=0
out=$(run_rdb 2>"$err") || rc=$?
[ "$rc" = 6 ] || fail "explicit absent per-spec backend should exit 6, got $rc"
grep -q "tmux" "$err" || fail "the per-spec halt diagnostic must name the missing backend"
echo "ok: an explicitly configured, unadvertised backend halts fail-closed (exit 6)"

# ---------------------------------------------------------------------------
# 5. Explicit literal honored when present — including an interactive backend
#    (explicit config is the operator's standing answer, never a silent pick).
# ---------------------------------------------------------------------------
reset_layers
printf 'dispatch_backend: tmux\n' >"$mlocal_cfg"
out=$(run_rdb PLANWRIGHT_BACKEND_TMUX=1) || fail "explicit present tmux exited non-zero"
[ "$(row_of "$out" backend)" = tmux ] \
  || fail "an explicitly configured, present tmux must be honored, got '$(row_of "$out" backend)'"
echo "ok: an explicitly configured present backend is honored, interactive included"

# ---------------------------------------------------------------------------
# 6. The tmux-context ask (D-8): attended + $TMUX + full-session surfaces the
#    ask exactly once per tower session; unanswered resolves unattended
#    immediately; an answer applies from the next resolve; a new session token
#    re-asks; outside tmux context attended matches unattended.
# ---------------------------------------------------------------------------
reset_layers
reset_ask
att() { # <session> [presence env pairs...]
  s=$1
  shift
  env PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    PLANWRIGHT_BACKEND_TMUX=1 \
    PLANWRIGHT_BACKEND_SUBAGENT=1 \
    PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
    PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=0 \
    TMUX=/tmp/tmux-sock,1,0 \
    "$@" /bin/sh "$RDB" resolve "$specdir" --attended --session "$s"
}
# First attended resolve in tmux context: ask surfaced, resolution unattended.
out=$(att s1) || fail "attended resolve (first ask) exited non-zero"
has_row "$out" ask || fail "first attended resolve in tmux context must surface the ask"
[ "$(row_of "$out" ask)" = tmux ] || fail "the ask row must be 'ask<TAB>tmux'"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "an unanswered ask must resolve unattended immediately, got '$(row_of "$out" backend)'"
# Same session again: re-ask suppressed, still unattended.
out=$(att s1) || fail "attended resolve (re-ask suppression) exited non-zero"
has_row "$out" ask && fail "the ask must not re-surface within one tower session"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "unanswered same-session resolve must stay unattended"
# The operator answers yes: tmux joins the candidate set from the next resolve.
/bin/sh "$RDB" answer "$specdir" --session s1 yes || fail "answer yes exited non-zero"
out=$(att s1) || fail "attended resolve (answered yes) exited non-zero"
has_row "$out" ask && fail "an answered session must not re-ask"
[ "$(row_of "$out" backend)" = tmux ] \
  || fail "an answered-yes session must add tmux to the candidate set, got '$(row_of "$out" backend)'"
# A NEW tower session re-asks (once per tower session); the stale answer does
# not carry — resolution is unattended until the new session answers.
out=$(att s2) || fail "attended resolve (new session) exited non-zero"
has_row "$out" ask || fail "a new tower session must re-ask"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "a new session's resolve must be unattended until answered"
# Answer no: stays unattended, no re-ask.
/bin/sh "$RDB" answer "$specdir" --session s2 no || fail "answer no exited non-zero"
out=$(att s2) || fail "attended resolve (answered no) exited non-zero"
has_row "$out" ask && fail "an answered-no session must not re-ask"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "an answered-no session must resolve unattended"
# Outside tmux context: attended matches unattended, no ask, no ask-state.
reset_ask
out=$(env -u TMUX \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" \
  PLANWRIGHT_BACKEND_TMUX=1 \
  PLANWRIGHT_BACKEND_SUBAGENT=1 \
  PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 \
  PLANWRIGHT_BACKEND_HEADLESS_ONESHOT=0 \
  /bin/sh "$RDB" resolve "$specdir" --attended --session s3) \
  || fail "attended resolve outside tmux context exited non-zero"
has_row "$out" ask && fail "no ask outside tmux context"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "outside tmux context attended must match unattended"
[ -e "$specdir/.orchestrate/tmux-ask" ] \
  && fail "no ask-state should be written outside tmux context"
# A configured literal never asks, even attended in tmux context.
reset_ask
printf 'dispatch_backend: subagent\n' >"$mlocal_cfg"
out=$(att s4) || fail "attended resolve (literal) exited non-zero"
has_row "$out" ask && fail "a configured literal must not surface the tmux ask"
[ "$(row_of "$out" backend)" = subagent ] || fail "literal attended resolve must honor the literal"
rm -f "$mlocal_cfg"
echo "ok: the tmux-context ask is once-per-tower-session, non-blocking, spec-locally persisted"

# ---------------------------------------------------------------------------
# 7. Operator-default only (REQ-B1.2): the resolver takes no per-task
#    parameter — an extra positional after the spec dir is a usage error.
# ---------------------------------------------------------------------------
reset_layers
rc=0
run_rdb >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "baseline resolve should succeed"
rc=0
env PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/sh "$RDB" resolve "$specdir" task-7 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "an extra positional (per-task parameter) must be a usage error (2), got $rc"
echo "ok: the resolver interface admits no per-task parameter"

# ---------------------------------------------------------------------------
# 8. By-layer malformed policy (REQ-E1.4): a malformed repo-tracked value
#    hard-fails (exit 4); a malformed machine-local value warns and degrades
#    to the core default. Same policy for an unparseable per-spec map.
# ---------------------------------------------------------------------------
reset_layers
printf 'dispatch_backend: not a backend!\n' >"$tracked_cfg"
rc=0
run_rdb >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "malformed repo-tracked global value should exit 4, got $rc"
reset_layers
printf 'dispatch_backend: not a backend!\n' >"$mlocal_cfg"
out=$(run_rdb PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 2>"$err") \
  || fail "malformed machine-local value should degrade, not fail"
grep -qi "warn" "$err" || fail "a machine-local degrade must warn on stderr"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "machine-local malformed value must degrade to the core default (full-session)"
reset_layers
printf 'dispatch_backend_per_spec: [not-a-map\n' >"$tracked_cfg"
rc=0
run_rdb >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "malformed repo-tracked per-spec map should exit 4, got $rc"
reset_layers
printf 'dispatch_backend_per_spec: [not-a-map\n' >"$mlocal_cfg"
out=$(run_rdb PLANWRIGHT_BACKEND_STREAM_JSON_PERSISTENT=1 2>"$err") \
  || fail "malformed machine-local per-spec map should degrade, not fail"
grep -qi "warn" "$err" || fail "a machine-local map degrade must warn on stderr"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "a malformed machine-local map must be treated as absent (global wins)"
echo "ok: malformed values follow the by-layer policy (repo-tracked hard-fails)"

# ---------------------------------------------------------------------------
# 9. The shipped default flip (REQ-B1.1): the real config/defaults.yml carries
#    full-session as the dispatch_backend default and ships the per-spec map
#    key, asserted directly (not only doc parity).
# ---------------------------------------------------------------------------
grep -q '^dispatch_backend: full-session$' "$REAL_DEFAULTS" \
  || fail "config/defaults.yml must carry 'dispatch_backend: full-session' (the default flip)"
grep -q '^dispatch_backend_per_spec:' "$REAL_DEFAULTS" \
  || fail "config/defaults.yml must ship the dispatch_backend_per_spec key"
echo "ok: the shipped default is full-session and the per-spec map key exists"

# ---------------------------------------------------------------------------
# 10. Input-as-data: hostile spec-dir basename and hostile session token are
#     refused (exit 2); an ask-state path occupied by a symlink is never
#     written through (the resolve degrades, the symlink target stays intact).
# ---------------------------------------------------------------------------
bad="$tmp/specs/Bad Name"
mkdir -p "$bad"
rc=0
env PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/sh "$RDB" resolve "$bad" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a hostile spec-dir basename must be refused (2), got $rc"
rc=0
att 'bad token; rm -rf' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a hostile session token must be refused (2), got $rc"
reset_layers
reset_ask
mkdir -p "$specdir/.orchestrate"
target="$tmp/symlink-target"
printf 'innocent\n' >"$target"
ln -s "$target" "$specdir/.orchestrate/tmux-ask"
out=$(att s9 2>"$err") || fail "resolve with symlinked ask-state should still resolve"
[ "$(row_of "$out" backend)" = stream-json-persistent ] \
  || fail "symlinked ask-state resolve must stay unattended"
[ "$(cat "$target")" = innocent ] \
  || fail "the resolver must never write through a symlinked ask-state path"
rc=0
/bin/sh "$RDB" answer "$specdir" --session s9 yes >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "answer must refuse to write through a symlinked ask-state path"
[ "$(cat "$target")" = innocent ] \
  || fail "answer must never write through a symlinked ask-state path"
echo "ok: hostile names are refused and symlinked ask-state is never written through"

echo "PASS: resolve-dispatch-backend tests"
