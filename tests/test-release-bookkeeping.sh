#!/bin/bash
# Tests for scripts/release-bookkeeping.sh — the belt-and-suspenders release
# report the `/orchestrate --bookkeeping` surface calls (autopilot-reflex Task 7;
# D-7, D-8; REQ-F1.2). It is the "report branch" test-spec.md REQ-F1.2 names: a
# thin, testable wrapper over the shared comparator (release-pending.sh) that,
# in the untagged window, reports the pending version and the publish command,
# and outside the window stays silent on releases.
#
# Contract under test:
#   - pending window  → a report on stdout naming the pending version AND the
#                       publish command (`scripts/release-publish.sh`); exit 0;
#   - no window (none)→ nothing on stdout (silent on releases); exit 0;
#   - first release   → treated as pending (the comparator's first-release rule);
#   - comparator error→ non-blocking: nothing on stdout, a diagnostic on stderr,
#                       exit 0 (belt-and-suspenders never breaks a bookkeeping run);
#   - comparator absent→ degrades with a message, exit 0 (non-dispatch path).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
BOOK="$here/../scripts/release-bookkeeping.sh"
failures=0

[ -x "$BOOK" ] || {
  echo "FAIL: scripts/release-bookkeeping.sh missing or not executable" >&2
  exit 1
}

gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# make_repo <dir> <version> — a fixture repo whose plugin.json holds <version>.
make_repo() {
  mkdir -p "$1/.claude-plugin"
  cat >"$1/.claude-plugin/plugin.json" <<EOF
{
  "name": "fixture",
  "version": "$2"
}
EOF
  gitc "$1" init -q
  gitc "$1" add -A
  gitc "$1" commit -q -m "version $2"
}

assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 — expected [$3], got [$2]" >&2
    failures=$((failures + 1))
  fi
}

# assert_contains <label> <haystack> <needle>
assert_contains() {
  case "$2" in
    *"$3"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 — [$2] does not contain [$3]" >&2
      failures=$((failures + 1))
      ;;
  esac
}

runbook() { # runbook <repo> — run the surface in <repo>, isolated git config
  (cd "$1" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$BOOK")
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Pending window: version of truth ahead of the latest tag → a report naming
#    the pending version and the publish command.
r="$tmp/pending"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
out=$(runbook "$r")
assert_contains "pending window reports the pending version" "$out" "0.2.0"
assert_contains "pending window says pending" "$out" "pending"
assert_contains "pending window names the publish command" "$out" "scripts/release-publish.sh"

# 2. No window: version equal to the latest tag → silent on releases (no stdout).
r="$tmp/none"
make_repo "$r" 0.1.0
gitc "$r" tag v0.1.0
out=$(runbook "$r")
assert_eq "outside the window the surface is silent on releases" "$out" ""

# 3. First release (no tags at all) → pending report (comparator's first rule).
r="$tmp/first"
make_repo "$r" 0.1.0
out=$(runbook "$r")
assert_contains "first release is reported as pending" "$out" "0.1.0"
assert_contains "first release names the publish command" "$out" "scripts/release-publish.sh"

# 4. Comparator error (malformed version of truth): non-blocking. Nothing on
#    stdout, a diagnostic on stderr, exit 0 — bookkeeping must never break here.
r="$tmp/bad"
make_repo "$r" "not-a-version"
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$BOOK" 2>/dev/null) || rc=$?
assert_eq "comparator error is non-blocking (exit 0)" "$rc" "0"
assert_eq "comparator error prints nothing on stdout" "$out" ""
err=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$BOOK" 2>&1 >/dev/null) || true
assert_contains "comparator error surfaces a diagnostic on stderr" "$err" "release-bookkeeping"

# 5. Comparator absent: the surface degrades with a message (missing prerequisite
#    on a non-dispatch path), nothing on stdout, exit 0. echo-safety.sh IS copied
#    so release-pending.sh is the *only* missing prerequisite — the script sources
#    echo-safety.sh (line ~39) before the comparator check, so omitting it would
#    add a separate `source` error to stderr and let the test pass for the wrong
#    reason, masking whether the missing-comparator diagnostic actually fires.
work="$tmp/no-comparator/scripts"
mkdir -p "$work"
cp "$here/../scripts/release-bookkeeping.sh" "$here/../scripts/echo-safety.sh" "$work/"
r="$tmp/no-comparator"
make_repo "$r" 0.2.0
gitc "$r" tag v0.1.0
rc=0
out=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null scripts/release-bookkeeping.sh 2>/dev/null) || rc=$?
assert_eq "a missing comparator degrades (exit 0)" "$rc" "0"
assert_eq "a missing comparator prints nothing on stdout" "$out" ""
err=$(cd "$r" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null scripts/release-bookkeeping.sh 2>&1 >/dev/null) || true
assert_contains "a missing comparator surfaces a diagnostic on stderr" "$err" "comparator scripts/release-pending.sh is missing"

# 6. CDPATH regression (REQ-D1.9): a hostile CDPATH with a decoy `scripts/` must
#    not corrupt the script's `cd "$(dirname "$0")"` (it calls `unset CDPATH`).
#    House pattern: the full script set is copied under `scripts/` in the cwd and
#    invoked by the BARE relative name — the only shape where CDPATH bites an
#    un-guarded cd.
work="$tmp/cdpath"
mkdir -p "$work/scripts" "$work/.claude-plugin" "$tmp/decoy/scripts"
cp "$here/../scripts/release-bookkeeping.sh" "$here/../scripts/release-pending.sh" \
  "$here/../scripts/release-lib.sh" "$here/../scripts/echo-safety.sh" \
  "$here/../scripts/config-get.sh" "$work/scripts/"
printf '{\n  "name": "fixture",\n  "version": "0.2.0"\n}\n' >"$work/.claude-plugin/plugin.json"
gitc "$work" init -q
gitc "$work" add -A
gitc "$work" commit -q -m "version 0.2.0"
gitc "$work" tag v0.1.0
out=$(cd "$work" && CDPATH="$tmp/decoy" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
  scripts/release-bookkeeping.sh)
assert_contains "a hostile CDPATH does not corrupt the surface" "$out" "0.2.0"

# 7. Malformed comparator output: the comparator exists and exits 0 but emits an
#    unexpected shape — no TAB, a non-`pending` state, or an empty version. The
#    surface must honor its documented fail-safe contract (header + the defensive
#    split): degrade to a no-op — nothing on stdout, a one-line stderr diagnostic
#    (this path is genuinely one line: the stub comparator exits 0, so only our
#    own guard writes to stderr), exit 0. This is the branch the repo's real
#    single-source comparator never reaches, so a stub comparator
#    that echoes a caller-supplied $STUB_OUT is what exercises it. No git repo or
#    plugin.json is needed — the stub replaces every git-touching step.
tab=$(printf '\t')
i=0
for spec in "no-tab:::garbage-no-tab" "wrong-state:::notpending${tab}1.2.3" "empty-version:::pending${tab}"; do
  name=${spec%%:::*}
  raw=${spec#*:::}
  i=$((i + 1))
  sw="$tmp/stub$i/scripts"
  mkdir -p "$sw"
  cp "$here/../scripts/release-bookkeeping.sh" "$here/../scripts/echo-safety.sh" "$sw/"
  # $STUB_OUT is written literally into the stub so it expands at the stub's
  # runtime (from the invocation env below), not here — single quotes are intended.
  # shellcheck disable=SC2016
  printf '#!/bin/sh\nprintf "%%s\\n" "$STUB_OUT"\n' >"$sw/release-pending.sh"
  chmod +x "$sw/release-pending.sh"
  rc=0
  out=$(cd "$tmp/stub$i" && env STUB_OUT="$raw" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    scripts/release-bookkeeping.sh 2>/dev/null) || rc=$?
  assert_eq "malformed comparator output ($name) degrades to a no-op (exit 0)" "$rc" "0"
  assert_eq "malformed comparator output ($name) prints nothing on stdout" "$out" ""
  err=$(cd "$tmp/stub$i" && env STUB_OUT="$raw" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    scripts/release-bookkeeping.sh 2>&1 >/dev/null) || true
  assert_contains "malformed comparator output ($name) surfaces a diagnostic on stderr" "$err" "unexpected comparator output"
done

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "PASS: test-release-bookkeeping.sh"
