#!/bin/bash
# Tests for scripts/install.sh — the ~/.claude/ writer fallback (REQ-I1.2,
# D-24). Verifies namespaced writes only: the writer must never touch user
# config outside its namespace (kickoff brief, REQ-I1.2 risk note).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$REPO_ROOT/scripts/install.sh"
RESOLVER="$REPO_ROOT/scripts/resolve-rule-doc.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

assert_file() {
  if [ -f "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (missing file $2)" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$INSTALLER" ]; then
  echo "FAIL: installer script missing at $INSTALLER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

claude_dir="$tmp/claude"

# Pre-existing user config that must survive untouched.
mkdir -p "$claude_dir"
echo '{"user": "owned"}' > "$claude_dir/settings.json"
mkdir -p "$claude_dir/skills/user-skill"
echo "user skill" > "$claude_dir/skills/user-skill/SKILL.md"

# 1. Install succeeds into an overridden claude dir.
CLAUDE_DIR="$claude_dir" /bin/bash "$INSTALLER" >/dev/null
assert "install exits 0" 0 $?

# 2. Namespaced content landed.
assert_file "default config installed" "$claude_dir/planwright/config/defaults.yml"
assert_file "doctrine installed" "$claude_dir/planwright/doctrine/README.md"
assert_file "resolver installed" "$claude_dir/planwright/scripts/resolve-rule-doc.sh"

# 3. The resolution path resolves in writer mode against the installed tree
#    (Done-when: the rule-doc resolution path resolves from both delivery
#    modes). Rule docs land with the doctrine task, so plant a kebab-case
#    fixture doc in the exact directory the installer writes to: this proves
#    the resolver searches where the writer installs.
echo "fixture" > "$claude_dir/planwright/doctrine/fixture-doc.md"
PLANWRIGHT_ROOT="" CLAUDE_PLUGIN_ROOT="" CLAUDE_DIR="$claude_dir" \
  /bin/bash "$RESOLVER" fixture-doc >/dev/null
assert "writer-mode resolution works post-install" 0 $?

# 4. User config outside the namespace is untouched.
if [ "$(cat "$claude_dir/settings.json")" = '{"user": "owned"}' ]; then
  echo "ok: settings.json untouched"
else
  echo "FAIL: settings.json was modified" >&2
  failures=$((failures + 1))
fi
if [ "$(cat "$claude_dir/skills/user-skill/SKILL.md")" = "user skill" ]; then
  echo "ok: unrelated user skill untouched"
else
  echo "FAIL: user skill was modified" >&2
  failures=$((failures + 1))
fi

# 5. Idempotent: a second run succeeds and the tree is still valid.
CLAUDE_DIR="$claude_dir" /bin/bash "$INSTALLER" >/dev/null
assert "second install exits 0" 0 $?
assert_file "default config still present" "$claude_dir/planwright/config/defaults.yml"

# 6. Skills/commands branches and the default claude-dir: build a hermetic
#    fake source tree (install.sh derives its source root from its own
#    location), install with CLAUDE_DIR unset and HOME redirected, and check
#    everything landed under $HOME/.claude.
src="$tmp/src"
mkdir -p "$src/scripts" "$src/doctrine" "$src/config" \
  "$src/skills/sample-skill" "$src/commands"
cp "$INSTALLER" "$src/scripts/install.sh"
echo "doc" > "$src/doctrine/sample.md"
echo "key: value" > "$src/config/defaults.yml"
echo "skill body" > "$src/skills/sample-skill/SKILL.md"
echo "command body" > "$src/commands/sample-command.md"
mkdir -p "$tmp/home"
HOME="$tmp/home" /bin/bash -c 'unset CLAUDE_DIR; exec /bin/bash "$1"' _ "$src/scripts/install.sh" >/dev/null
assert "install with default claude-dir exits 0" 0 $?
assert_file "default-dir config installed" "$tmp/home/.claude/planwright/config/defaults.yml"
assert_file "skill copied" "$tmp/home/.claude/skills/sample-skill/SKILL.md"
assert_file "command copied" "$tmp/home/.claude/commands/sample-command.md"

# 6b. Running the installed copy of the writer (source == destination) is
#     refused with a clear message (exit 2), not a mid-run cp crash that
#     leaves the install half-touched (REQ-K1.7).
out="$(/bin/bash -c 'unset CLAUDE_DIR; HOME="$1"; export HOME; exec /bin/bash "$1/.claude/planwright/scripts/install.sh"' _ "$tmp/home" 2>&1)"
assert "self-install refused" 2 $?
case "$out" in
  *"installed location"*) echo "ok: self-install refusal names the cause" ;;
  *)
    echo "FAIL: self-install refusal message unclear: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 6b2. The self-install refusal also holds when the installed location is
#      reached through a symlink (logical vs physical path).
ln -s "$tmp/home/.claude/planwright" "$tmp/sym-link"
/bin/bash -c 'unset CLAUDE_DIR; HOME="$1"; export HOME; exec /bin/bash "$2/scripts/install.sh"' _ "$tmp/home" "$tmp/sym-link" >/dev/null 2>&1
assert "symlinked self-install refused" 2 $?

# 6b3. Installed scripts keep their executable bit under a restrictive umask.
mkdir -p "$tmp/umask-home"
( umask 0133; HOME="$tmp/umask-home" /bin/bash -c 'unset CLAUDE_DIR; exec /bin/bash "$1"' _ "$INSTALLER" >/dev/null )
assert "install under umask 0133 exits 0" 0 $?
if [ -x "$tmp/umask-home/.claude/planwright/scripts/resolve-rule-doc.sh" ]; then
  echo "ok: installed resolver is executable under umask 0133"
else
  echo "FAIL: installed resolver lost its executable bit under umask 0133" >&2
  failures=$((failures + 1))
fi

# 6c. With neither CLAUDE_DIR nor HOME set, the writer refuses with a clear
#     message (exit 2) instead of a bash unbound-variable error.
env -u HOME -u CLAUDE_DIR /bin/bash "$INSTALLER" >/dev/null 2>&1
assert "missing CLAUDE_DIR and HOME is a clear usage error" 2 $?

# 6d. A hostile CDPATH must not corrupt the installer's source-root
#     derivation when invoked via a relative path.
mkdir -p "$tmp/decoy2/scripts" "$tmp/home2"
(cd "$src" && CDPATH="$tmp/decoy2" HOME="$tmp/home2" /bin/bash -c 'unset CLAUDE_DIR; exec /bin/bash scripts/install.sh' >/dev/null 2>&1)
assert "CDPATH does not corrupt installer source derivation" 0 $?
assert_file "CDPATH run still installs correctly" "$tmp/home2/.claude/planwright/config/defaults.yml"

# 7. Partial failure is surfaced, not swallowed (REQ-K1.7: fail clearly, never
#    opaquely): an unwritable destination must produce a non-zero exit, not a
#    cheerful "done" report. Skipped as root: permission bits do not bind the
#    superuser, so the fixture cannot create an unwritable destination.
if [ "$(id -u)" -ne 0 ]; then
  readonly_dir="$tmp/readonly"
  mkdir -p "$readonly_dir"
  chmod 555 "$readonly_dir"
  CLAUDE_DIR="$readonly_dir/claude" /bin/bash "$INSTALLER" >/dev/null 2>&1
  rc=$?
  chmod 755 "$readonly_dir"
  if [ "$rc" -ne 0 ]; then
    echo "ok: unwritable destination fails loudly (exit $rc)"
  else
    echo "FAIL: install exited 0 despite an unwritable destination" >&2
    failures=$((failures + 1))
  fi
else
  echo "skip: unwritable-destination case (running as root)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all install-writer tests passed"
