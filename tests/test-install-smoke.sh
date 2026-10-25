#!/bin/sh
# Tests for scripts/install-smoke.sh (universal-binary REQ-B1.1, REQ-B1.3):
# the allowlist PATH is real (an entry point invoking cargo, go, node, or
# python fails even when the host carries all four, and the installer itself
# runs under it), the POSIX utilities a shell also has as builtins stay
# reachable through PATH, the entry point sees no inherited variable, both
# delivery modes install and run their entry point (the marketplace mode
# against a stub Claude CLI; the workflow's install smoke step drives the real
# one on every platform), and an entry point that lost its execute bit fails.
set -u
unset CDPATH

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SMOKE="$REPO_ROOT/scripts/install-smoke.sh"

failures=0
ok() { printf 'ok: %s\n' "$1"; }
bad() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
expect() {
  # expect <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then ok "$1"; else bad "$1 (expected exit $2, got $3)"; fi
}
says() {
  # says <label> <needle>: the last smoke run's output carries the needle.
  if grep -qF -- "$2" "$TMP/out"; then
    ok "$1"
  else
    bad "$1 (missing '$2')"
    cat "$TMP/out" >&2
  fi
}

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# A host carrying every toolchain the constraint excludes: each stands in as
# a stub that succeeds, ahead of everything else on PATH.
toolchain="$TMP/toolchain"
mkdir -p "$toolchain"
for t in cargo go node python; do
  printf '#!/bin/sh\nexit 0\n' >"$toolchain/$t"
  chmod 755 "$toolchain/$t"
done
HOST_PATH="$toolchain:$PATH"

# fixture_tree <dir>: a minimal tree install.sh accepts, with fixture entry
# points under scripts/.
fixture_tree() {
  mkdir -p "$1/scripts" "$1/doctrine" "$1/config"
  cp -p "$REPO_ROOT/scripts/install.sh" "$1/scripts/install.sh"
  cat >"$1/scripts/uses-posix.sh" <<'EOF'
#!/bin/sh
printf 'posix\n' | awk '{ print }' >/dev/null && git --version >/dev/null
EOF
  # Utilities the shell also has as builtins, run where only PATH finds them.
  cat >"$1/scripts/uses-exec-utilities.sh" <<'EOF'
#!/bin/sh
printf 'x\n' | xargs printf '%s\n' >/dev/null && env true \
  && find . -prune -exec test -d {} \; && printf 'x\n' | xargs >/dev/null
EOF
  # Fails when anything but the four variables the smoke sets is inherited.
  cat >"$1/scripts/uses-clean-env.sh" <<'EOF'
#!/bin/sh
[ -z "${CARGO_HOME:-}" ] && [ -z "${SMOKE_LEAK:-}" ]
EOF
  cp "$1/scripts/uses-posix.sh" "$1/scripts/a..b.sh"
  for t in cargo go node python; do
    printf '#!/bin/sh\n%s --version\n' "$t" >"$1/scripts/uses-$t.sh"
  done
  chmod 755 "$1"/scripts/*.sh
  printf '#!/bin/sh\nexit 0\n' >"$1/scripts/no-exec.sh"
  chmod 644 "$1/scripts/no-exec.sh"
}
src="$TMP/src"
fixture_tree "$src"

smoke() { PATH="$HOST_PATH" sh "$SMOKE" "$@" >"$TMP/out" 2>&1; }

# The fixtures themselves run on the host: what fails below is the allowlist.
for t in cargo go node python; do
  PATH="$HOST_PATH" "$src/scripts/uses-$t.sh" >/dev/null 2>&1
  expect "the uses-$t fixture runs on the toolchain host" 0 $?
done

smoke --modes writer --source "$src" --entry scripts/uses-posix.sh
expect "a POSIX-and-git entry point passes under the allowlist" 0 $?
smoke --modes writer --source "$src" --entry scripts/uses-exec-utilities.sh
expect "builtin-shadowed POSIX utilities stay reachable through PATH" 0 $?
smoke --modes writer --source "$src" --entry scripts/a..b.sh
expect "an entry name holding .. inside a segment is accepted" 0 $?

CARGO_HOME=/opt/cargo SMOKE_LEAK=1 PATH="$HOST_PATH" sh "$SMOKE" --modes writer \
  --source "$src" --entry scripts/uses-clean-env.sh >"$TMP/out" 2>&1
expect "the entry point inherits no caller variable" 0 $?

for t in cargo go node python; do
  smoke --modes writer --source "$src" --entry "scripts/uses-$t.sh"
  expect "an entry point invoking $t fails under the allowlist" 1 $?
  says "the $t failure names the entry point" "scripts/uses-$t.sh failed under the allowlist PATH"
done

smoke --modes writer --source "$src" --entry scripts/no-exec.sh
expect "an entry point without its execute bit fails" 1 $?
says "the execute-bit failure names the entry point" "scripts/no-exec.sh failed under the allowlist PATH"

# The installer runs under the allowlist too.
bad_src="$TMP/bad-src"
fixture_tree "$bad_src"
printf '#!/bin/sh\npython --version\n' >"$bad_src/scripts/install.sh"
smoke --modes writer --source "$bad_src" --entry scripts/uses-posix.sh
expect "an installer invoking python fails under the allowlist" 1 $?
says "the installer failure names the writer" "writer mode: scripts/install.sh failed under the allowlist PATH"

# The named entry point through the real writer install.
smoke --modes writer
rc=$?
expect "the writer mode runs scripts/step-record.sh under the allowlist" 0 "$rc"
[ "$rc" -eq 0 ] || cat "$TMP/out" >&2

# The marketplace mode against a stub CLI, which records each call and, on
# `plugin install`, lays down the copy a real install would: the fixture tree
# under the scratch plugin cache, at as many versions as STUB_VERSIONS names.
stub="$TMP/stub-bin"
mkdir -p "$stub"
cat >"$stub/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_LOG"
case "$1 $2" in
  "plugin marketplace") [ "${STUB_FAIL:-}" != add ] || exit 1 ;;
  "plugin install")
    [ "${STUB_FAIL:-}" != install ] || exit 1
    for v in $STUB_VERSIONS; do
      mkdir -p "$CLAUDE_CONFIG_DIR/plugins/cache/planwright/planwright/$v"
      cp -Rp "$STUB_TREE/." "$CLAUDE_CONFIG_DIR/plugins/cache/planwright/planwright/$v/"
    done
    ;;
esac
EOF
chmod 755 "$stub/claude"
market() {
  STUB_LOG="$TMP/stub.log" STUB_TREE="$src" PATH="$stub:$HOST_PATH" \
    sh "$SMOKE" --modes marketplace --source "$src" "$@" >"$TMP/out" 2>&1
}

: >"$TMP/stub.log"
STUB_VERSIONS=1.0.0 market --entry scripts/uses-posix.sh
expect "the marketplace mode runs the installed copy's entry point" 0 $?
if grep -qx "plugin marketplace add $src" "$TMP/stub.log" \
  && grep -qx "plugin install planwright@planwright" "$TMP/stub.log"; then
  ok "the marketplace mode adds the source and installs planwright@planwright"
else
  bad "the marketplace mode adds the source and installs planwright@planwright"
  cat "$TMP/stub.log" >&2
fi
STUB_VERSIONS=1.0.0 market --entry scripts/uses-node.sh
expect "a marketplace entry point invoking node fails under the allowlist" 1 $?
STUB_VERSIONS=1.0.0 STUB_FAIL=add market --entry scripts/uses-posix.sh
expect "a failed marketplace add fails the run" 1 $?
says "the add failure is named" "claude plugin marketplace add failed"
STUB_VERSIONS=1.0.0 STUB_FAIL=install market --entry scripts/uses-posix.sh
expect "a failed plugin install fails the run" 1 $?
says "the install failure is named" "claude plugin install failed"
STUB_VERSIONS='' market --entry scripts/uses-posix.sh
expect "an install that lays down no copy fails the run" 1 $?
says "the missing copy is named" "no installed copy"
STUB_VERSIONS='1.0.0 1.0.1' market --entry scripts/uses-posix.sh
expect "two installed versions fail the run" 1 $?
says "the ambiguous copy is named" "more than one installed version"

nocli="$TMP/no-cli"
mkdir -p "$nocli"
for t in sh env mktemp mkdir rm ln tr cat cp dirname git printf; do
  p=$(command -v "$t") && case $p in /*) ln -s "$p" "$nocli/$t" ;; esac
done
PATH="$nocli" sh "$SMOKE" --modes marketplace --source "$src" >"$TMP/out" 2>&1
expect "the marketplace mode without a claude CLI fails" 1 $?
says "the missing CLI is named" "no claude on PATH"

smoke --modes writer,carrier
expect "an unknown delivery mode is a usage error" 2 $?
smoke --modes ''
expect "an empty mode list is a usage error" 2 $?
smoke --modes writer,writer
expect "a mode named twice is a usage error" 2 $?
smoke --modes writer --source "$src" --entry /bin/true
expect "an absolute entry path is a usage error" 2 $?
smoke --modes writer --source "$src" --entry ../src/scripts/uses-posix.sh
expect "an entry path climbing out of the installed root is a usage error" 2 $?
smoke --entry
expect "a flag without its value is a usage error" 2 $?
smoke --verbose
expect "an unknown argument is a usage error" 2 $?
smoke --source "$TMP"
expect "a source without scripts/install.sh is a usage error" 2 $?

if [ "$failures" -gt 0 ]; then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all install-smoke tests passed\n'
