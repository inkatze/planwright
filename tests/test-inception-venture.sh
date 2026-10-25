#!/bin/bash
# Tests for the /inception venture helper (inception Task 7; REQ-A1.1,
# REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.8, REQ-A1.9, REQ-B1.7, REQ-H1.1,
# REQ-H1.3, REQ-H1.5, REQ-C1.7 · D-5, D-19).
#
# The skill's mechanical half lives in scripts/inception-venture.sh: identifier
# derivation, ventures_root resolution, capability detection, venture creation
# on both home arms, the wrapped save, the resume point, and the handoff. The
# environment is stubbed through PATH (a `git` that fails reads as no git, a
# `gh` that fakes repo creation against a local bare repo) and the documented
# overrides, so every rung of the ladder runs on any machine.
#
# The closing section is the Task 7 "scripted dry run": a fresh venture repo
# on each home arm, filled and saved through the helper, ends validator-clean.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENTURE="$REPO_ROOT/scripts/inception-venture.sh"
VALIDATE="$REPO_ROOT/scripts/inception-validate.sh"

# shellcheck source=tests/lib/inception-fixture.sh
. "$REPO_ROOT/tests/lib/inception-fixture.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}
assert_exists() {
  if [ -e "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (nothing at $2)" >&2
    failures=$((failures + 1))
  fi
}
assert_absent() {
  if [ -e "$2" ] || [ -L "$2" ]; then
    echo "FAIL: $1 (unexpected $2)" >&2
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
}

# stray_temps <dir> — the helper's temp files left in <dir>, one per line.
stray_temps() {
  for st in "$1"/.inception-venture.*; do
    [ -e "$st" ] && printf '%s\n' "${st##*/}"
  done
}

if [ ! -x "$VENTURE" ]; then
  echo "FAIL: $VENTURE is missing or not executable" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# A private HOME keeps the operator's git config (signing, hooks, templates)
# out of every commit below, and gives `~` a known expansion.
export HOME="$tmp/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
export PLANWRIGHT_ROOT="$REPO_ROOT"
export PLANWRIGHT_INCEPTION_TODAY=2026-08-20
# The built-in screen, not a host gitleaks whose rules may wave the fixture
# token through (the scaffold suite pins it the same way).
export PLANWRIGHT_SECRET_SCREEN_TOOL=none
unset CLAUDE_CODE_REMOTE PLANWRIGHT_INCEPTION_EPHEMERAL PLANWRIGHT_INCEPTION_HOST CLAUDE_PLUGIN_ROOT
unset XDG_CONFIG_HOME GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_DIR GIT_WORK_TREE
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
# Identity comes only from the GIT_* variables below, never guessed from the
# host name, so the no-identity case fails the same way on every host.
printf '[user]\n\tuseConfigOnly = true\n' >"$GIT_CONFIG_GLOBAL"
# Remotes read as GitHub URLs, as a real venture's do; git carries them to the
# local bare repositories the gh stub creates.
mkdir -p "$tmp/remotes"
printf '[url "%s/"]\n\tinsteadOf = https://github.com/\n' "$tmp/remotes" >>"$GIT_CONFIG_GLOBAL"

# Config layers: a fixture core default plus a git-toplevel "repo" whose
# tracked and machine-local layers each test writes as needed.
core_cfg="$tmp/core-defaults.yml"
printf 'ventures_root: ~/ventures\n' >"$core_cfg"
cfg_repo="$tmp/cfg-repo"
mkdir -p "$cfg_repo/.claude"
GIT_CONFIG_GLOBAL=/dev/null git init -q "$cfg_repo"
export PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg"
export PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter"
export PLANWRIGHT_REPO_ROOT="$cfg_repo"
export PLANWRIGHT_LOCAL_CONFIG=""

# Stub directories. `nogit` holds a git that fails; `gh-ok` holds a gh that
# authenticates and creates the "private repo" as a local bare repository;
# `gh-noauth` holds a gh that is installed but signed out.
stubs="$tmp/stubs"
mkdir -p "$stubs/nogit" "$stubs/gh-ok" "$stubs/gh-noauth" "$tmp/remotes"
cat >"$stubs/nogit/git" <<'EOF'
#!/bin/sh
exit 127
EOF
cat >"$stubs/gh-ok/gh" <<EOF
#!/bin/sh
# Fake gh: signed in to github.com; repo create makes a bare repo and wires
# its GitHub URL as the remote, recording the arguments it was given.
printf '%s\n' "\$*" >>"$tmp/gh-calls.log"
case "\$1 \$2" in
  "auth status")
    echo "  Logged in to github.com account fixture (keyring)"
    exit 0
    ;;
  "repo view")
    # A repository named in gh-public-repos reads PUBLIC; otherwise the
    # visibility is whatever the test last wrote, PRIVATE by default.
    case "\$3" in
      -* | '') ;;
      *)
        if [ -f "$tmp/gh-public-repos" ] && grep -qxF -- "\$3" "$tmp/gh-public-repos"; then
          echo PUBLIC
          exit 0
        fi
        ;;
    esac
    if [ -f "$tmp/gh-visibility" ]; then cat "$tmp/gh-visibility"; else echo PRIVATE; fi
    exit 0
    ;;
  "repo create")
    name=\$3
    shift 3
    src=
    remote=origin
    while [ \$# -gt 0 ]; do
      case \$1 in
        --source) src=\$2; shift 2 ;;
        --source=*) src=\${1#--source=}; shift ;;
        --remote) remote=\$2; shift 2 ;;
        --remote=*) remote=\${1#--remote=}; shift ;;
        *) shift ;;
      esac
    done
    bare="$tmp/remotes/\$name.git"
    mkdir -p "\$(dirname "\$bare")" || exit 1
    git init -q --bare "\$bare" || exit 1
    git -C "\$src" remote add "\$remote" "https://github.com/\$name.git" || exit 1
    exit 0
    ;;
esac
exit 1
EOF
cat >"$stubs/gh-noauth/gh" <<'EOF'
#!/bin/sh
exit 1
EOF
mkdir -p "$stubs/gh-fail"
cat >"$stubs/gh-fail/gh" <<'EOF'
#!/bin/sh
# Signed in, but repository creation fails.
case "$1 $2" in
  "auth status") exit 0 ;;
esac
exit 1
EOF
chmod +x "$stubs/nogit/git" "$stubs/gh-ok/gh" "$stubs/gh-noauth/gh" "$stubs/gh-fail/gh"

# venture <args...> — run the helper; stdout+stderr in $out, exit in $rc.
venture() {
  out=$(/bin/sh "$VENTURE" "$@" 2>&1)
  rc=$?
}

# =========================================================================
# REQ-A1.1 — identifier derivation and validation
# =========================================================================

venture id northwind-signals
assert_eq "A1.1 conforming name is accepted as-is (exit)" 0 "$rc"
assert_eq "A1.1 conforming name is accepted as-is (output)" "$(printf 'ok\tnorthwind-signals')" "$out"

venture id "Northwind Signals!"
assert_eq "A1.1 non-conforming name proposes a variant (exit 1)" 1 "$rc"
assert_eq "A1.1 proposed variant is kebab-case" "$(printf 'propose\tnorthwind-signals')" "$out"

venture id "--Lead__Gen  2026--"
assert_eq "A1.1 leading/trailing and repeated separators collapse" "$(printf 'propose\tlead-gen-2026')" "$out"

long=$(printf 'a%.0s' $(seq 1 70))
venture id "$long"
assert_eq "A1.1 overlength name proposes a truncated variant (exit)" 1 "$rc"
variant=${out#*	}
assert_eq "A1.1 truncated variant is exactly 64 chars" 64 "${#variant}"

venture id "$(printf 'x%.0s' $(seq 1 62))- -y"
variant=${out#*	}
assert_eq "A1.1 truncation never leaves a trailing hyphen" "$(printf 'x%.0s' $(seq 1 62))-y" "$variant"

venture id '!!!'
assert_eq "A1.1 a name with no usable characters derives nothing (exit 2)" 2 "$rc"

venture id 'Café Ünïcode'
variant=${out#*	}
assert_eq "A1.1 non-ASCII bytes fold to separators" "caf-n-code" "$variant"

# =========================================================================
# REQ-A1.8 — re-validation at consumption (hostile identifiers)
# =========================================================================

for bad in '../etc' 'a/b' 'Bad' '-lead' '' '.hidden' "$(printf 'a\nb')" "$(printf 'a%.0s' $(seq 1 65))" 'a b'; do
  venture check-id "$bad"
  assert_eq "A1.8 check-id refuses a hostile id ($(printf '%s' "$bad" | tr '\n' '?' | cut -c1-12))" 1 "$rc"
done
venture check-id "$(printf 'a%.0s' $(seq 1 64))"
assert_eq "A1.8 check-id accepts the 64-char boundary" 0 "$rc"
venture check-id ok-id-9
assert_eq "A1.8 check-id accepts a valid id" 0 "$rc"

venture create --home local --root "$tmp/hostile" '../escape'
assert_eq "A1.8 create refuses a hostile id" 1 "$rc"
assert_absent "A1.8 create made nothing for a hostile id" "$tmp/hostile"
assert_absent "A1.8 create made nothing outside the root" "$tmp/escape"

# =========================================================================
# REQ-A1.3 — ventures_root resolution
# =========================================================================

venture root
assert_eq "A1.3 default root resolves (exit)" 0 "$rc"
assert_eq "A1.3 default root is ~/ventures" "$HOME/ventures" "$out"

printf 'ventures_root: %s\n' "$tmp/elsewhere/" >"$cfg_repo/.claude/planwright.local.yml"
venture root
assert_eq "A1.3 machine-local override wins (trailing slash trimmed)" "$tmp/elsewhere" "$out"

printf 'ventures_root: ~/biz\n' >"$cfg_repo/.claude/planwright.local.yml"
venture root
assert_eq "A1.3 a ~/ value expands against HOME" "$HOME/biz" "$out"

printf 'ventures_root: relative/dir\n' >"$cfg_repo/.claude/planwright.local.yml"
venture root
assert_eq "A1.3 malformed machine-local value degrades (exit 0)" 0 "$rc"
assert_contains "A1.3 malformed machine-local value warns" "warning" "$out"
assert_eq "A1.3 malformed machine-local value degrades to the default" "$HOME/ventures" "$(printf '%s\n' "$out" | tail -n 1)"

printf 'ventures_root: ~someone/x\n' >"$cfg_repo/.claude/planwright.local.yml"
venture root
assert_eq "A1.3 ~user form is malformed and degrades" "$HOME/ventures" "$(printf '%s\n' "$out" | tail -n 1)"
rm -f "$cfg_repo/.claude/planwright.local.yml"

printf 'ventures_root: relative/dir\n' >"$cfg_repo/.claude/planwright.yml"
venture root
assert_eq "A1.3 malformed repo-tracked value hard-fails (exit 4)" 4 "$rc"
rm -f "$cfg_repo/.claude/planwright.yml"

# A broken install is an environment error, never exit 5, which the skill
# reads as "the venture path is taken".
printf 'ventures_root: relative/core\n' >"$tmp/bad-core.yml"
PLANWRIGHT_CONFIG_DEFAULTS="$tmp/bad-core.yml" venture root
assert_eq "A1.3 a malformed core default is a broken install (exit 2)" 2 "$rc"
PLANWRIGHT_CONFIG_DEFAULTS="$tmp/bad-core.yml" venture create --home local broken-install
assert_eq "A1.3 create on a broken install exits 2, not 5" 2 "$rc"
printf 'ventures_root: /a\001b\n' >"$tmp/ctl-core.yml"
PLANWRIGHT_CONFIG_DEFAULTS="$tmp/ctl-core.yml" venture create --home local broken-install
assert_eq "A1.3 the resolver's broken-install exit folds into 2" 2 "$rc"

PLANWRIGHT_CONFIG_DEFAULTS="$REPO_ROOT/config/defaults.yml" venture root
assert_eq "A1.3 the shipped default resolves to ~/ventures" "$HOME/ventures" "$out"

# =========================================================================
# REQ-H1.1 / REQ-A1.5 / REQ-H1.5 — capability detection and the ladder
# =========================================================================

PATH="$stubs/gh-ok:$PATH" venture detect
assert_eq "H1.1 detect succeeds" 0 "$rc"
assert_contains "H1.1 git present" "$(printf 'git\tpresent')" "$out"
assert_contains "H1.1 not ephemeral" "$(printf 'ephemeral\tno')" "$out"
assert_contains "H1.1 remote home available" "$(printf 'remote\tavailable')" "$out"
assert_contains "H1.1 local home durable" "$(printf 'local\tdurable')" "$out"
assert_not_contains "H1.5 a clean environment reports no degradation" "degraded" "$out"

PATH="$stubs/nogit:$stubs/gh-ok:$PATH" venture detect
assert_contains "H1.1 stubbed-out git reads as absent" "$(printf 'git\tabsent')" "$out"
assert_contains "H1.1 no git means the plain-folder rung" "$(printf 'local\tplain')" "$out"
assert_contains "H1.1 no git means no remote home" "$(printf 'remote\tunavailable')" "$out"
assert_contains "H1.5 no-git degradation is named" "$(printf 'degraded\tgit unavailable')" "$out"

PATH="$stubs/gh-noauth:$PATH" venture detect
assert_contains "H1.1 signed-out gh means no remote home" "$(printf 'remote\tunavailable')" "$out"
assert_contains "H1.5 remote-home degradation is named" "private-remote home is unavailable" "$out"

PATH="$stubs/gh-ok:$PATH" CLAUDE_CODE_REMOTE=true venture detect
assert_contains "A1.5 a cloud session reads as ephemeral" "$(printf 'ephemeral\tyes')" "$out"
assert_contains "A1.5 ephemeral local arm is session-only" "$(printf 'local\tsession-only')" "$out"
assert_contains "H1.5 ephemeral degradation is named" "does not persist" "$out"

PATH="$stubs/gh-ok:$PATH" CLAUDE_CODE_REMOTE=true PLANWRIGHT_INCEPTION_EPHEMERAL=0 venture detect
assert_contains "A1.5 the operator override wins over detection" "$(printf 'ephemeral\tno')" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_EPHEMERAL=1 venture detect
assert_contains "A1.5 the override can force ephemeral" "$(printf 'local\tsession-only')" "$out"

PATH="$stubs/gh-ok:$PATH" CLAUDE_CODE_REMOTE=false venture detect
assert_contains "A1.5 only CLAUDE_CODE_REMOTE=true reads as a cloud session" "$(printf 'ephemeral\tno')" "$out"

PATH="$stubs/nogit:$PATH" PLANWRIGHT_INCEPTION_EPHEMERAL=1 venture detect
assert_contains "H1.1 no git and ephemeral is still session-only" "$(printf 'local\tsession-only')" "$out"

# =========================================================================
# REQ-H1.4 — host and plugin detection, Cowork caveats
# =========================================================================

PATH="$stubs/gh-ok:$PATH" venture detect
assert_contains "H1.4 no hosted-session signal reads as a local host" "$(printf 'host\tlocal')" "$out"
assert_contains "H1.4 an install the venture hook resolves reads as loaded" "$(printf 'plugin\tloaded')" "$out"
assert_not_contains "H1.4 a local host carries no Cowork caveat" "caveat" "$out"

PATH="$stubs/gh-ok:$PATH" CLAUDE_CODE_REMOTE=true venture detect
assert_contains "H1.4 a cloud session reads as the cloud host" "$(printf 'host\tcloud')" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_HOST=cowork venture detect
assert_eq "H1.4 detect succeeds on a Cowork host" 0 "$rc"
assert_contains "H1.4 the operator names a Cowork host" "$(printf 'host\tcowork')" "$out"
assert_contains "H1.4 a Cowork host defaults to ephemeral" "$(printf 'ephemeral\tyes')" "$out"
assert_contains "H1.4 a Cowork host's local arm is session-only" "$(printf 'local\tsession-only')" "$out"
assert_contains "H1.4 the Cowork egress caveat is surfaced" "$(printf 'caveat\tCowork')" "$out"
assert_contains "H1.4 the caveat names the network allowlist" "allowlist" "$out"
assert_contains "H1.4 the caveat names the advisory protocol" "sync-protocol.md" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_HOST=cowork PLANWRIGHT_INCEPTION_EPHEMERAL=0 venture detect
assert_contains "H1.4 a Cowork local session over a connected folder is durable on override" \
  "$(printf 'local\tdurable')" "$out"
assert_contains "H1.4 the caveat stays with the durable override" "$(printf 'caveat\tCowork')" "$out"

PATH="$stubs/nogit:$PATH" PLANWRIGHT_INCEPTION_HOST=cowork venture detect
assert_contains "H1.4 Cowork without git is still session-only" "$(printf 'local\tsession-only')" "$out"
assert_contains "H1.4 Cowork without git names the missing git" "$(printf 'degraded\tgit unavailable')" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_HOST=bogus venture detect
assert_eq "H1.4 an unrecognized host override still detects" 0 "$rc"
assert_contains "H1.4 an unrecognized host override is ignored" "$(printf 'host\tlocal')" "$out"
assert_contains "H1.4 an unrecognized host override is warned about" "PLANWRIGHT_INCEPTION_HOST" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_ROOT='' CLAUDE_PLUGIN_ROOT='' venture detect
assert_contains "H1.4 no install where the hook looks reads as absent" "$(printf 'plugin\tabsent')" "$out"
assert_contains "H1.4 an absent plugin is a named degradation" "skip the venture guards" "$out"
assert_contains "H1.4 the absent-plugin line names where the hook also looks" ".planwright-local.sh" "$out"

PATH="$stubs/nogit:$PATH" PLANWRIGHT_ROOT='' CLAUDE_PLUGIN_ROOT='' venture detect
assert_not_contains "H1.4 without git there is no hook, so no absent-plugin line" "skip the venture guards" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_ROOT='' CLAUDE_PLUGIN_ROOT="$REPO_ROOT" venture detect
assert_contains "H1.4 a loaded plugin root reads as loaded" "$(printf 'plugin\tloaded')" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_HOST=cowork venture create --home local --root "$tmp/v-cowork" cw
assert_eq "H1.4 create on a Cowork host succeeds" 0 "$rc"
assert_contains "H1.4 a local home on a Cowork host lands on the session rung" "$(printf 'rung\tsession')" "$out"
assert_contains "H1.4 create repeats the Cowork caveat" "$(printf 'caveat\tCowork')" "$out"
assert_exists "G1.8 create scaffolds the sync protocol" "$tmp/v-cowork/cw/sync-protocol.md"
assert_contains "G1.8 create imports the protocol from CLAUDE.md" "@sync-protocol.md" \
  "$(cat "$tmp/v-cowork/cw/CLAUDE.md" 2>/dev/null)"
PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_HOST=cowork venture handoff "$tmp/v-cowork/cw"
assert_contains "H1.4 the handoff repeats the Cowork caveat" "$(printf 'caveat\tCowork')" "$out"
PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_ROOT='' CLAUDE_PLUGIN_ROOT='' venture handoff "$tmp/v-cowork/cw"
assert_contains "H1.5 the handoff repeats the absent-plugin degradation" "skip the venture guards" "$out"

# =========================================================================
# Creation guards (REQ-A1.4, REQ-A1.7 no-overwrite floor)
# =========================================================================

PATH="$stubs/gh-noauth:$PATH" venture create --home remote --root "$tmp/v-guard" alpha
assert_eq "A1.4 remote home refused when unavailable (exit 6)" 6 "$rc"
assert_absent "A1.4 a refused remote home creates nothing" "$tmp/v-guard/alpha"

mkdir -p "$tmp/v-guard/taken"
printf 'keep\n' >"$tmp/v-guard/taken/notes.md"
venture create --home local --root "$tmp/v-guard" taken
assert_eq "A1.7 an existing target is refused, never overwritten (exit 5)" 5 "$rc"
assert_eq "A1.7 the existing directory is untouched" keep "$(cat "$tmp/v-guard/taken/notes.md")"

ln -s "$tmp/nowhere" "$tmp/v-guard/dangling"
venture create --home local --root "$tmp/v-guard" dangling
assert_eq "A1.7 a symlink at the target is refused (exit 5)" 5 "$rc"
assert_eq "A1.7 the symlink is untouched" "$tmp/nowhere" "$(readlink "$tmp/v-guard/dangling")"

PATH="$stubs/gh-fail:$PATH" venture create --home remote --root "$tmp/v-guard" gamma
assert_eq "A1.4 a failed private-repo creation exits 7" 7 "$rc"
assert_absent "A1.4 a failed private-repo creation keeps nothing local" "$tmp/v-guard/gamma"

venture create --home local --root "$tmp/v-guard" --owner 'bad/owner' delta
assert_eq "create refuses a malformed GitHub owner (exit 2)" 2 "$rc"
assert_absent "a refused owner creates nothing" "$tmp/v-guard/delta"

PATH="$stubs/gh-ok:$PATH" venture create --home remote --root "$tmp/v-guard" --owner acme epsilon
assert_eq "create on the remote home with an owner succeeds" 0 "$rc"
assert_contains "the owner prefixes the private repository's name" "repo create acme/epsilon" "$(cat "$tmp/gh-calls.log")"

PATH="$stubs/gh-ok:$PATH" venture create --home local default-root
assert_eq "A1.3 create without --root uses ventures_root (exit)" 0 "$rc"
assert_exists "A1.3 create without --root lands under ~/ventures" "$HOME/ventures/default-root/.git"

venture create --home sideways --root "$tmp/v-guard" beta
assert_eq "create rejects an unknown home (usage exit 2)" 2 "$rc"

venture create --home local --root "$tmp/v-guard"
assert_eq "create without an identifier is a usage error (exit 2)" 2 "$rc"
assert_contains "create without an identifier prints the usage" "usage:" "$out"

# =========================================================================
# Resume point and version refusal (REQ-B1.7, REQ-C1.7)
# =========================================================================

rp="$tmp/resume"
mkdir -p "$rp"
venture bundle-init --title "Resume Probe" "$rp"
assert_eq "B1.7 bundle-init writes the skeleton (exit)" 0 "$rc"
for f in brief.md disciplines.md assumptions.md decisions.md plan.md; do
  assert_exists "B1.7 skeleton has $f" "$rp/$f"
done
/bin/sh "$VALIDATE" --version-check "$rp" >/dev/null 2>&1
assert_eq "C1.7 skeleton passes the version gate" 0 "$?"
/bin/sh "$VALIDATE" "$rp" >/dev/null 2>&1
skeleton_rc=$?
case $skeleton_rc in 0 | 1) skeleton_rc=readable ;; esac
assert_eq "C1.7 the full validator reads the skeleton (findings at most, never a refusal)" readable "$skeleton_rc"

venture bundle-init --title "Again" "$rp"
assert_eq "bundle-init never overwrites an existing bundle (exit 5)" 5 "$rc"

# A failed write leaves no partial bundle, so a retry succeeds.
mkdir -p "$stubs/cat-fail" "$tmp/write-fail"
printf '#!/bin/sh\nexit 1\n' >"$stubs/cat-fail/cat"
chmod +x "$stubs/cat-fail/cat"
PATH="$stubs/cat-fail:$PATH" venture bundle-init --title "Write Fail" "$tmp/write-fail"
assert_eq "a failed bundle-init write exits 2" 2 "$rc"
assert_absent "a failed bundle-init write leaves no partial bundle" "$tmp/write-fail/brief.md"
assert_eq "a failed bundle-init write leaves no temp files" "" "$(stray_temps "$tmp/write-fail")"
venture bundle-init --title "Write Fail" "$tmp/write-fail"
assert_eq "bundle-init succeeds on retry after a failed write" 0 "$rc"

lp="$tmp/link-probe"
mkdir -p "$lp"
ln -s "$tmp/nowhere" "$lp/brief.md"
venture bundle-init --title "Link Probe" "$lp"
assert_eq "bundle-init refuses a dangling symlink at a bundle file (exit 5)" 5 "$rc"
assert_eq "bundle-init leaves the symlink untouched" "$tmp/nowhere" "$(readlink "$lp/brief.md")"

mkdir -p "$tmp/titles"
for bad in '' '   ' "$(printf 'two\nlines')"; do
  venture bundle-init --title "$bad" "$tmp/titles"
  assert_eq "bundle-init refuses a blank or multi-line title ($(printf '%s' "$bad" | tr '\n' '?'))" 2 "$rc"
done
assert_absent "a refused title writes no bundle" "$tmp/titles/brief.md"

venture resume-point "$rp"
assert_contains "B1.7 a fresh skeleton resumes at the first phase" "$(printf 'next\tseed')" "$out"
assert_contains "B1.7 a fresh skeleton has no completed phase" "$(printf 'done\tnone')" "$out"
assert_eq "B1.7 every unfilled disciplines.md table carries the pending marker" 3 "$(grep -cF '_Pending: not yet elicited._' "$rp/disciplines.md")"
assert_eq "B1.7 the pending count covers every file's markers" 17 "$(printf '%s\n' "$out" | sed -n 's/^pending	//p')"

venture mark-phase "$rp" seed
assert_eq "B1.7 mark-phase records a phase (exit)" 0 "$rc"
venture mark-phase "$rp" opportunity
venture resume-point "$rp"
assert_contains "B1.7 resume picks up after the last completed phase" "$(printf 'next\tdisciplines')" "$out"
assert_contains "B1.7 resume names the last completed phase" "$(printf 'done\topportunity')" "$out"
assert_eq "B1.7 the phase log lands in the Changelog section" 2 "$(sed -n '/^## Changelog/,$p' "$rp/brief.md" | grep -c 'Elicitation:')"

dp="$tmp/date-pin"
mkdir -p "$dp"
for bad in 2026-19-01 2026-12-39 2026-00-10 2026-02-00; do
  PLANWRIGHT_INCEPTION_TODAY=$bad venture bundle-init --title "Date Pin" "$dp"
  assert_eq "an impossible pinned date ($bad) still writes the skeleton" 0 "$rc"
  assert_not_contains "an impossible pinned date ($bad) is never written" "$bad" "$(cat "$dp/brief.md")"
  assert_contains "an impossible pinned date ($bad) falls back to the system date" "$(date +%Y-%m-%d)" "$(cat "$dp/brief.md")"
  rm -f "$dp"/*.md
done

venture mark-phase "$rp" bogus
assert_eq "mark-phase rejects an unknown phase (exit 2)" 2 "$rc"

assert_eq "bundle-init and mark-phase leave no temp files behind" "" "$(stray_temps "$rp")"

# An interrupted phase write leaves neither a torn brief.md nor a stray temp
# file the next save would commit. The awk stub writes half a file, then
# signals the helper mid-write.
real_awk=$(command -v awk)
mkdir -p "$stubs/awk-interrupt"
cat >"$stubs/awk-interrupt/awk" <<EOF
#!/bin/sh
case "\$*" in
  *Elicitation:*)
    printf 'torn'
    kill -TERM \$PPID
    sleep 1
    exit 0
    ;;
esac
exec "$real_awk" "\$@"
EOF
chmod +x "$stubs/awk-interrupt/awk"
cp "$rp/brief.md" "$tmp/brief-before-interrupt.md"
PATH="$stubs/awk-interrupt:$PATH" venture mark-phase "$rp" disciplines
assert_eq "an interrupted mark-phase exits on the signal" 143 "$rc"
assert_eq "an interrupted mark-phase leaves brief.md untouched" "" "$(cmp "$tmp/brief-before-interrupt.md" "$rp/brief.md" 2>&1)"
assert_eq "an interrupted mark-phase leaves no temp file" "" "$(stray_temps "$rp")"

for p in disciplines reframe core registers finalize; do
  venture mark-phase "$rp" "$p"
done
venture resume-point "$rp"
assert_contains "B1.7 a finished elicitation resumes into re-entry" "$(printf 'next\tcomplete')" "$out"

sed 's/^\*\*Format-version:\*\* 1\.0$/**Format-version:** 9.0/' "$rp/plan.md" >"$rp/plan.md.new" && mv "$rp/plan.md.new" "$rp/plan.md"
venture resume-point "$rp"
assert_eq "C1.7 resume refuses an unsupported format-version (exit 3)" 3 "$rc"
assert_contains "C1.7 the refusal is the validator's plain-language message" "unsupported format-version" "$out"
cp "$rp/brief.md" "$tmp/brief-before-gate.md"
venture mark-phase "$rp" core
assert_eq "C1.7 mark-phase refuses an unsupported format-version (exit 3)" 3 "$rc"
assert_eq "C1.7 a refused mark-phase leaves brief.md untouched" "" "$(cmp "$tmp/brief-before-gate.md" "$rp/brief.md" 2>&1)"

# An incomplete bundle is told apart from an unreadable one.
ip="$tmp/incomplete"
mkdir -p "$ip"
venture bundle-init --title "Incomplete Probe" "$ip"
rm -f "$ip/plan.md"
venture resume-point "$ip"
assert_eq "B1.7 resume on an incomplete bundle is an environment error (exit 2)" 2 "$rc"
assert_contains "B1.7 the incomplete-bundle message names the missing file" "plan.md is missing" "$out"
PATH="$stubs/gh-ok:$PATH" venture handoff "$ip"
assert_contains "H1.5 handoff reports an incomplete bundle as incomplete" "$(printf 'bundle\tincomplete')" "$out"

# =========================================================================
# Scripted dry run — local-only arm (REQ-A1.4, REQ-A1.9, REQ-H1.2, REQ-H1.5)
# =========================================================================

vroot="$tmp/ventures"
PATH="$stubs/gh-ok:$PATH" venture create --home local --root "$vroot" northwind-signals
assert_eq "dry run (local): create succeeds" 0 "$rc"
assert_contains "dry run (local): reports the git rung" "$(printf 'rung\tgit')" "$out"
lv="$vroot/northwind-signals"
assert_exists "dry run (local): venture repo is a git repo" "$lv/.git"
assert_exists "dry run (local): .gitignore scaffolded" "$lv/.gitignore"
assert_exists "dry run (local): pre-commit hook scaffolded" "$lv/githooks/pre-commit"
assert_absent "dry run (local): no CI guard on the local rung" "$lv/.github"
assert_eq "dry run (local): hooks are wired" githooks "$(git -C "$lv" config core.hooksPath)"
assert_eq "dry run (local): no remote is configured" "" "$(git -C "$lv" remote)"
assert_eq "dry run (local): the branch is main" refs/heads/main "$(git -C "$lv" symbolic-ref HEAD)"

venture bundle-init --title "Northwind Signals" "$lv"
venture save "$lv" "Start the Northwind Signals venture"
assert_eq "dry run (local): the first save succeeds" 0 "$rc"
assert_contains "H1.2 wrapped save speaks plainly" "Saved" "$out"
assert_not_contains "H1.2 wrapped save hides git vocabulary" "commit" "$out"

# Elicitation fills the bundle; the golden fixture stands in for the answers.
inception_fixture_write "$lv"
venture mark-phase "$lv" finalize
venture save --expert "$lv" "Record the elicited bundle"
assert_eq "dry run (local): the filled bundle saves" 0 "$rc"
assert_eq "H1.2 expert save shows the commit" "$(git -C "$lv" log -1 --format='%h %s')" "$out"
/bin/sh "$VALIDATE" "$lv" >/dev/null 2>&1
assert_eq "dry run (local): the bundle is validator-clean" 0 "$?"
assert_eq "dry run (local): the export rode the save" exports/venture.html "$(git -C "$lv" ls-files exports/venture.html)"
assert_eq "dry run (local): two saves landed" 2 "$(git -C "$lv" rev-list --count HEAD)"

venture save --expert "$lv" "Expert-mode save with nothing to save"
assert_eq "H1.2 expert save with nothing staged is not an error" 0 "$rc"
assert_contains "H1.2 a save with nothing staged says so" "Nothing new to save." "$out"

venture save "$lv" '   '
assert_eq "H1.2 a blank save message is refused as usage (exit 2)" 2 "$rc"

venture save --push "$lv" "Try to push"
assert_eq "A1.4 the local arm refuses to push (exit 6)" 6 "$rc"
assert_contains "A1.4 the refusal says nothing leaves the machine" "nothing leaves this machine" "$out"

PATH="$stubs/gh-noauth:$PATH" venture handoff "$lv"
assert_contains "handoff names the rung" "$(printf 'rung\tgit')" "$out"
assert_contains "handoff names the validator result" "$(printf 'bundle\tclean')" "$out"
assert_contains "H1.5 remote-home degradation repeated at handoff" "private-remote home is unavailable" "$out"

# REQ-H1.3 — the local-only venture gains a remote later: same repo, history kept.
before=$(git -C "$lv" rev-parse HEAD)
PATH="$stubs/gh-ok:$PATH" venture add-remote "$lv"
assert_eq "H1.3 add-remote succeeds" 0 "$rc"
assert_eq "H1.3 nothing re-initialized: history preserved" "$before" "$(git -C "$lv" rev-parse HEAD)"
assert_eq "H1.3 the remote is wired" origin "$(git -C "$lv" remote)"
assert_exists "H1.3 the CI guard joins on the remote rung" "$lv/.github/workflows/venture-guard.yml"
assert_exists "H1.3 the remote repository was created" "$tmp/remotes/northwind-signals.git"
assert_contains "H1.3 gh was asked for a private repo" "--private" "$(cat "$tmp/gh-calls.log")"
assert_contains "F2 add-remote rewrites the notes for the remote rung" "**remote** rung" "$(cat "$lv/hygiene-wiring.md")"

# A retry with origin already set re-runs the setup instead of refusing: the
# notes file is rewritten, missing guards return, everything else is kept.
creates_before=$(grep -c 'repo create' "$tmp/gh-calls.log")
printf 'stale local-rung notes\n' >"$lv/hygiene-wiring.md"
rm -f "$lv/.github/workflows/venture-guard.yml"
printf 'custom-ignore\n' >>"$lv/.gitignore"
PATH="$stubs/gh-ok:$PATH" venture add-remote "$lv"
assert_eq "F2 add-remote retried with origin set succeeds" 0 "$rc"
assert_contains "F2 the retry rewrites the notes file" "**remote** rung" "$(cat "$lv/hygiene-wiring.md")"
assert_exists "F2 the retry restores a missing guard" "$lv/.github/workflows/venture-guard.yml"
assert_contains "F2 the retry keeps the operator's other files" "custom-ignore" "$(cat "$lv/.gitignore")"
assert_eq "F2 the retry creates no second repository" "$creates_before" "$(grep -c 'repo create' "$tmp/gh-calls.log")"

# =========================================================================
# Scripted dry run — private-remote arm
# =========================================================================

PATH="$stubs/gh-ok:$PATH" venture create --home remote --root "$vroot" harbor-ledger
assert_eq "dry run (remote): create succeeds" 0 "$rc"
assert_contains "dry run (remote): reports the remote home" "$(printf 'home\tremote')" "$out"
rv="$vroot/harbor-ledger"
assert_exists "dry run (remote): CI guard scaffolded" "$rv/.github/workflows/venture-guard.yml"
assert_eq "dry run (remote): origin wired" origin "$(git -C "$rv" remote)"

venture bundle-init --title "Harbor Ledger" "$rv"
inception_fixture_write "$rv"
for p in seed opportunity disciplines reframe core; do venture mark-phase "$rv" "$p"; done
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Record the elicited bundle"
assert_eq "dry run (remote): save and push succeed" 0 "$rc"
/bin/sh "$VALIDATE" "$rv" >/dev/null 2>&1
assert_eq "dry run (remote): the bundle is validator-clean" 0 "$?"
assert_eq "dry run (remote): the push reached the private remote" \
  "$(git -C "$rv" rev-parse HEAD)" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
PATH="$stubs/gh-noauth:$PATH" venture handoff "$rv"
assert_contains "H1.5 handoff on the remote home names it" "$(printf 'home\tremote')" "$out"
assert_not_contains "H1.5 a remote venture is not warned the remote home is unavailable" "private-remote home is unavailable" "$out"

PATH="$stubs/nogit:$PATH" PLANWRIGHT_INCEPTION_EPHEMERAL=1 venture handoff "$rv"
assert_contains "H1.5 without git a remote venture still reads as remote" "$(printf 'home\tremote')" "$out"
assert_not_contains "H1.5 without git a remote venture is not told to choose the remote home" "choose the private-remote home" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_EPHEMERAL=1 venture create --home remote --root "$vroot" cloud-remote
assert_contains "A1.5 an ephemeral host keeps the remote home on the git rung" "$(printf 'rung\tgit')" "$out"
assert_not_contains "A1.5 a remote venture is not warned it does not persist" "does not persist" "$out"

# A push with nothing ever saved is not blamed on the connection.
ev="$tmp/empty-remote"
git init -q "$ev"
git init -q --bare "$tmp/remotes/empty.git"
git -C "$ev" remote add origin "$tmp/remotes/empty.git"
venture save --push "$ev" "Share nothing"
assert_eq "A1.4 a push with no saved history is refused (exit 6)" 6 "$rc"
assert_contains "A1.4 the empty-push refusal says nothing was saved" "nothing has been saved yet" "$out"

# =========================================================================
# Degraded rungs: plain folder and session-only (REQ-H1.1, REQ-H1.5, REQ-A1.5)
# =========================================================================

PATH="$stubs/nogit:$PATH" venture create --home local --root "$vroot" plain-probe
assert_eq "H1.1 plain rung: create succeeds without git" 0 "$rc"
assert_contains "H1.1 plain rung reported" "$(printf 'rung\tplain')" "$out"
assert_contains "H1.5 plain rung degradation named at creation" "git unavailable" "$out"
pv="$vroot/plain-probe"
assert_absent "H1.1 plain rung has no git" "$pv/.git"
venture bundle-init --title "Plain Probe" "$pv"
inception_fixture_write "$pv"
PATH="$stubs/nogit:$PATH" venture save "$pv" "Record the bundle"
assert_eq "H1.1 plain rung: save still files the bundle" 0 "$rc"
assert_contains "H1.1 plain rung: save names the missing history" "no history" "$out"
/bin/sh "$VALIDATE" "$pv" >/dev/null 2>&1
assert_eq "H1.1 plain rung: the bundle is validator-clean" 0 "$?"
assert_exists "H1.1 plain rung: the save regenerated the export" "$pv/exports/venture.html"
PATH="$stubs/nogit:$PATH" venture save --push "$pv" "Share a plain folder"
assert_eq "H1.1 plain rung: a push is refused (exit 6)" 6 "$rc"
PATH="$stubs/gh-ok:$PATH" venture add-remote "$pv"
assert_eq "H1.3 a plain folder cannot gain a remote (exit 6)" 6 "$rc"
printf 'token: %s\n' "ghp_""0123456789abcdefghijklmnopqrstuvwxyz" >"$pv/leak.md"
PATH="$stubs/nogit:$PATH" venture save "$pv" "Leak attempt"
assert_eq "A1.9 plain rung: a credential is flagged (exit 1)" 1 "$rc"
assert_contains "A1.9 plain rung: the flag says why in plain words" "credential" "$out"
rm -f "$pv/leak.md"
PATH="$stubs/nogit:$PATH" venture handoff "$pv"
assert_contains "H1.5 plain rung degradation repeated at handoff" "git unavailable" "$out"
PATH="$stubs/gh-ok:$PATH" venture handoff "$pv"
assert_contains "H1.5 a plain venture names its missing history even where git now works" "plain folder" "$out"
PATH="$stubs/gh-noauth:$PATH" venture handoff "$pv"
assert_not_contains "H1.5 a plain venture is not warned the remote home is unavailable" "private-remote home is unavailable" "$out"

PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_EPHEMERAL=1 venture create --home local --root "$vroot" session-probe
assert_eq "A1.5 session-only: create proceeds, warned" 0 "$rc"
assert_contains "A1.5 session-only rung reported" "$(printf 'rung\tsession')" "$out"
assert_contains "H1.5 session-only degradation named at creation" "does not persist" "$out"
PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_INCEPTION_EPHEMERAL=1 venture handoff "$vroot/session-probe"
assert_contains "H1.5 session-only degradation repeated at handoff" "does not persist" "$out"

# A save the secret screen refuses is reported, never swallowed.
# Split literal, as the scaffold suite does, so no scanner flags this file.
printf 'token: %s\n' "ghp_""0123456789abcdefghijklmnopqrstuvwxyz" >"$lv/leak.md"
venture save "$lv" "Leak attempt"
assert_eq "A1.9 a save carrying a credential is refused (exit 1)" 1 "$rc"
assert_contains "A1.9 the refusal says why in plain words" "credential" "$out"
assert_eq "A1.9 a refused save leaves nothing staged" "" "$(git -C "$lv" diff --cached --name-only)"
rm -f "$lv/leak.md"

# A host with no git identity is told so, never that the guard stopped it.
printf 'note\n' >"$lv/identity-probe.md"
env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u EMAIL \
  /bin/sh "$VENTURE" save "$lv" "No identity" >"$tmp/id.out" 2>&1
rc=$?
out=$(cat "$tmp/id.out")
assert_eq "H1.2 a save with no git identity is an environment error (exit 2)" 2 "$rc"
assert_contains "H1.2 the no-identity refusal names the missing name and email" "name and email" "$out"
assert_not_contains "H1.2 the no-identity refusal is not blamed on the guard" "guard" "$out"
assert_eq "H1.2 the no-identity refusal leaves nothing staged" "" "$(git -C "$lv" diff --cached --name-only)"
rm -f "$lv/identity-probe.md"

# =========================================================================
# Z2 — an inherited git redirection never steers the helper's git calls
# =========================================================================

other="$tmp/other-repo"
git init -q "$other"
git -C "$other" commit -q --allow-empty -m "other repository root"
other_before=$(git -C "$other" rev-list --count HEAD)
lv_before=$(git -C "$lv" rev-list --count HEAD)
printf 'redirect probe\n' >"$lv/redirect-probe.md"
GIT_DIR="$other/.git" GIT_WORK_TREE="$other" GIT_INDEX_FILE="$other/.git/index" \
  venture save "$lv" "Save despite an inherited redirection"
assert_eq "Z2 a save under an inherited GIT_DIR succeeds" 0 "$rc"
assert_eq "Z2 the unrelated repository gains no commit" "$other_before" "$(git -C "$other" rev-list --count HEAD)"
assert_eq "Z2 the venture gains the commit" "$((lv_before + 1))" "$(git -C "$lv" rev-list --count HEAD)"

# =========================================================================
# Z1 — save screens for secrets itself, not only through the venture's hook
# =========================================================================

token_line() { printf 'token: %s\n' "ghp_""0123456789abcdefghijklmnopqrstuvwxyz"; }

# An unwired hook no longer means an unscreened save.
git -C "$lv" config --unset core.hooksPath
lv_before=$(git -C "$lv" rev-list --count HEAD)
token_line >"$lv/unwired-leak.md"
venture save "$lv" "Leak with the hook unwired"
assert_eq "Z1 a credential is refused even with the hook unwired (exit 1)" 1 "$rc"
assert_contains "Z1 the unwired refusal says why" "credential" "$out"
assert_eq "Z1 the unwired refusal commits nothing" "$lv_before" "$(git -C "$lv" rev-list --count HEAD)"
assert_eq "Z1 the unwired refusal leaves nothing staged" "" "$(git -C "$lv" diff --cached --name-only)"
rm -f "$lv/unwired-leak.md"
git -C "$lv" config core.hooksPath githooks

# The save message is screened too.
printf 'note\n' >"$lv/message-probe.md"
venture save "$lv" "$(token_line)"
assert_eq "Z1 a credential in the save message is refused (exit 1)" 1 "$rc"
assert_eq "Z1 a refused message commits nothing" "$lv_before" "$(git -C "$lv" rev-list --count HEAD)"
assert_not_contains "Z1 the refused message is never echoed" "0123456789abcdefghijklmnopqrstuvwxyz" "$out"
rm -f "$lv/message-probe.md"

# Hook warnings reach the operator instead of being thrown away.
printf 'hook warning probe\n' >"$lv/hook-warning.md"
PLANWRIGHT_ROOT="$tmp/no-planwright" CLAUDE_PLUGIN_ROOT='' venture save "$lv" "Save with the hook unable to find planwright"
assert_eq "Z1 a save whose hook only warned succeeds" 0 "$rc"
assert_contains "Z1 the hook's warning is shown" "planwright not found" "$out"

# Commits made outside the helper are screened before they leave the machine.
for p in seed opportunity disciplines reframe core; do venture mark-phase "$rv" "$p"; done
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Record the core phases"
remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
token_line >"$rv/outside-leak.md"
git -C "$rv" add outside-leak.md
git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify -m "outside commit"
git -C "$rv" rm -q outside-leak.md
git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify -m "remove it again"
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share the outside commits"
assert_eq "Z1 a push whose outgoing history carries a credential is refused (exit 1)" 1 "$rc"
assert_contains "Z1 the push refusal says why" "credential" "$out"
assert_eq "Z1 the refused push leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
git -C "$rv" reset -q --hard HEAD~2

# =========================================================================
# Z3 — a push goes only to a remote confirmed private at push time
# =========================================================================

remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
printf 'visibility probe\n' >"$rv/visibility-probe.md"
printf 'PUBLIC\n' >"$tmp/gh-visibility"
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share after the repository went public"
assert_eq "Z3 a push to a remote no longer private is refused (exit 6)" 6 "$rc"
assert_contains "Z3 the refusal names the visibility" "not private" "$out"
assert_eq "Z3 the refused push leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
rm -f "$tmp/gh-visibility"

PATH="$stubs/gh-noauth:$PATH" venture save --push "$rv" "Share with no way to check"
assert_eq "Z3 a push whose visibility cannot be confirmed is refused (exit 6)" 6 "$rc"
assert_contains "Z3 the unconfirmed refusal says so" "cannot confirm" "$out"
assert_eq "Z3 the unconfirmed push leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"

PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share once confirmed private"
assert_eq "Z3 a push to a confirmed-private remote succeeds" 0 "$rc"
assert_eq "Z3 the confirmed push reaches the remote" "$(git -C "$rv" rev-parse HEAD)" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"

# =========================================================================
# Z4 — bundle files follow the umask, like every other file the helper makes
# =========================================================================

old_umask=$(umask)
umask 022
mp="$tmp/mode-probe"
mkdir -p "$mp"
venture bundle-init --title "Mode Probe" "$mp"
venture mark-phase "$mp" seed
for f in brief.md disciplines.md assumptions.md decisions.md plan.md; do
  assert_eq "Z4 $f follows the umask (0644 under 022)" "$mp/$f" "$(find "$mp/$f" -perm 0644)"
done
umask 077
mp2="$tmp/mode-probe-private"
mkdir -p "$mp2"
venture bundle-init --title "Mode Probe" "$mp2"
assert_eq "Z4 a private umask still yields owner-only files" "$mp2/brief.md" "$(find "$mp2/brief.md" -perm 0600)"
umask "$old_umask"

# =========================================================================
# Z5 — a path carrying a control byte is refused before it reaches output
# =========================================================================

nl_dir="$tmp/forged$(printf '\nrung\tsession')"
mkdir -p "$nl_dir"
for sub in handoff resume-point; do
  venture "$sub" "$nl_dir"
  assert_eq "Z5 $sub refuses a path with a control byte (exit 2)" 2 "$rc"
  assert_not_contains "Z5 $sub forges no key line" "$(printf 'rung\tsession')" "$out"
done
venture bundle-init --title "Forged" "$nl_dir"
assert_eq "Z5 bundle-init refuses a path with a control byte (exit 2)" 2 "$rc"
assert_absent "Z5 bundle-init writes nothing there" "$nl_dir/brief.md"
venture create --home local --root "$tmp/bad$(printf '\nroot')" zeta
assert_eq "Z5 create refuses a root with a control byte (exit 2)" 2 "$rc"
assert_absent "Z5 create makes nothing under such a root" "$tmp/bad$(printf '\nroot')"
# A clean path whose resolved form carries the control byte is refused too.
git init -q "$nl_dir/linked-venture"
ln -s "$nl_dir/linked-venture" "$tmp/linked-venture"
PATH="$stubs/gh-ok:$PATH" venture add-remote "$tmp/linked-venture"
assert_eq "Z5 add-remote refuses a resolved path with a control byte (exit 2)" 2 "$rc"
assert_not_contains "Z5 add-remote forges no key line" "$(printf 'rung\tsession')" "$out"
assert_absent "Z5 add-remote creates no repository for it" "$tmp/remotes/linked-venture.git"

# =========================================================================
# Z6 — a failed create leaves nothing behind and names what it cannot undo
# =========================================================================

real_git=$(command -v git)
mkdir -p "$stubs/git-noinit" "$stubs/gh-502"
cat >"$stubs/git-noinit/git" <<EOF
#!/bin/sh
[ "\$1" = init ] && exit 1
exec "$real_git" "\$@"
EOF
cat >"$stubs/gh-502/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo create")
    printf 'HTTP 502: upstream timed out\n' >&2
    exit 1
    ;;
esac
exit 1
EOF
chmod +x "$stubs/git-noinit/git" "$stubs/gh-502/gh"

PATH="$stubs/git-noinit:$stubs/gh-ok:$PATH" venture create --home local --root "$tmp/z6" eta
assert_eq "Z6 a failed git init exits 2" 2 "$rc"
assert_absent "Z6 a failed git init leaves no half-built venture" "$tmp/z6/eta"
PATH="$stubs/gh-ok:$PATH" venture create --home local --root "$tmp/z6" eta
assert_eq "Z6 the name is free again after a failed create" 0 "$rc"

PATH="$stubs/gh-502:$PATH" venture create --home remote --root "$tmp/z6" --owner acme theta
assert_eq "Z6 a failed private-repo creation exits 7" 7 "$rc"
assert_absent "Z6 a failed private-repo creation keeps nothing local" "$tmp/z6/theta"
assert_contains "Z6 the failure names the repository that may exist" "acme/theta" "$out"
assert_contains "Z6 the failure passes on gh's reason" "HTTP 502: upstream timed out" "$out"
assert_not_contains "Z6 the failure no longer claims nothing was kept" "nothing was kept" "$out"

# =========================================================================
# Fork 1 — the no-durable-home arm is reported and warned as session-only
# =========================================================================

scratch="$tmp/session-scratch"
PATH="$stubs/gh-ok:$PATH" venture create --home session --root "$scratch" iota
assert_eq "F1 create --home session succeeds on a durable host" 0 "$rc"
assert_contains "F1 the session home is reported" "$(printf 'home\tsession')" "$out"
assert_contains "F1 the session home sits on the session rung" "$(printf 'rung\tsession')" "$out"
assert_contains "F1 the session home is warned as not persisting" "does not persist" "$out"
PATH="$stubs/gh-ok:$PATH" venture handoff "$scratch/iota"
assert_contains "F1 handoff keeps the session home" "$(printf 'home\tsession')" "$out"
assert_contains "F1 handoff keeps the session rung" "$(printf 'rung\tsession')" "$out"
assert_contains "F1 handoff repeats the session warning" "does not persist" "$out"
venture bundle-init --title "Iota" "$scratch/iota"
PATH="$stubs/gh-ok:$PATH" venture save --push "$scratch/iota" "Try to share a session venture"
assert_eq "F1 a session venture never pushes (exit 6)" 6 "$rc"

PATH="$stubs/nogit:$PATH" venture create --home session --root "$scratch" kappa
assert_eq "F1 the session home works without git" 0 "$rc"
assert_contains "F1 without git the session home is still the session rung" "$(printf 'rung\tsession')" "$out"
PATH="$stubs/nogit:$PATH" venture handoff "$scratch/kappa"
assert_contains "F1 handoff without git keeps the session home" "$(printf 'home\tsession')" "$out"

# =========================================================================
# Fork 3 — resume at the first phase with no completion line
# =========================================================================

gp="$tmp/gap-probe"
mkdir -p "$gp"
venture bundle-init --title "Gap Probe" "$gp"
venture mark-phase "$gp" seed
venture mark-phase "$gp" disciplines
venture resume-point "$gp"
assert_contains "F3 resume picks the first unmarked phase, not the one after the highest" "$(printf 'next\topportunity')" "$out"
assert_contains "F3 done names the phase before it" "$(printf 'done\tseed')" "$out"
venture mark-phase "$gp" seed
assert_eq "F3 re-marking a phase succeeds" 0 "$rc"
assert_eq "F3 re-marking a phase adds no duplicate line" 1 "$(grep -c 'Elicitation: seed phase complete' "$gp/brief.md")"

# =========================================================================
# Fork 5 — on the remote home, sharing starts once the core phase is recorded
# =========================================================================

PATH="$stubs/gh-ok:$PATH" venture create --home remote --root "$vroot" lambda-early
lr="$vroot/lambda-early"
venture bundle-init --title "Lambda Early" "$lr"
PATH="$stubs/gh-ok:$PATH" venture save --push "$lr" "Start the Lambda Early venture"
assert_eq "F5 an early save on the remote home succeeds" 0 "$rc"
assert_contains "F5 the early save says sharing waits for the minimum core" "minimum core" "$out"
assert_eq "F5 nothing reaches the remote before the core phase" "" "$(git -C "$tmp/remotes/lambda-early.git" rev-parse -q --verify refs/heads/main)"
for p in seed opportunity disciplines reframe core; do venture mark-phase "$lr" "$p"; done
PATH="$stubs/gh-ok:$PATH" venture save --push "$lr" "Record the minimum core"
assert_eq "F5 the save after the core phase pushes" 0 "$rc"
assert_eq "F5 the push reaches the remote once core is recorded" "$(git -C "$lr" rev-parse HEAD)" "$(git -C "$tmp/remotes/lambda-early.git" rev-parse refs/heads/main)"

# =========================================================================
# Z9 — the pre-push screen covers everything origin lacks
# =========================================================================

# leak_and_hide <venture> — commit a token and remove it again, outside the
# helper, so only the screen of the outgoing history can catch it.
leak_and_hide() {
  token_line >"$1/outside-leak.md"
  git -C "$1" add outside-leak.md
  git -C "$1" -c core.hooksPath=/dev/null commit -q --no-verify -m "outside commit"
  git -C "$1" rm -q outside-leak.md
  git -C "$1" -c core.hooksPath=/dev/null commit -q --no-verify -m "remove it again"
}

rv_base=$(git -C "$rv" rev-parse HEAD)
remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
leak_and_hide "$rv"
git -C "$rv" branch -q -f side HEAD
git -C "$rv" branch -q -u side
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share past a local upstream"
assert_eq "Z9 commits origin lacks are screened even behind a local upstream (exit 1)" 1 "$rc"
assert_eq "Z9 the refused push leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
git -C "$rv" branch -q -u origin/main
git -C "$rv" reset -q --hard "$rv_base"
git -C "$rv" branch -q -D side

# =========================================================================
# Z8 — outgoing commit messages are screened too
# =========================================================================

rv_base=$(git -C "$rv" rev-parse HEAD)
remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify --allow-empty -m "$(token_line)"
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share a commit whose message leaks"
assert_eq "Z8 a credential in an outgoing commit message blocks the push (exit 1)" 1 "$rc"
assert_eq "Z8 the refused push leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
git -C "$rv" reset -q --hard "$rv_base"

# =========================================================================
# Z7 — the pre-push screen reads file contents, not the readable diff
# =========================================================================

for shape in attribute nul; do
  rv_base=$(git -C "$rv" rev-parse HEAD)
  remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
  if [ "$shape" = attribute ]; then
    printf '*.dat -diff\n' >"$rv/.gitattributes"
    token_line >"$rv/leak.dat"
  else
    {
      printf 'bin\000ary\n'
      token_line
    } >"$rv/leak.dat"
  fi
  git -C "$rv" add -A
  git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify -m "outside binary commit"
  PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share a $shape file"
  assert_eq "Z7 a credential in a file git diffs as binary ($shape) blocks the push (exit 1)" 1 "$rc"
  assert_eq "Z7 the refused push ($shape) leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
  git -C "$rv" reset -q --hard "$rv_base"
done

# A file that exists only in a merge's resolution shows in no commit's diff.
rv_base=$(git -C "$rv" rev-parse HEAD)
remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
git -C "$rv" checkout -q -b z7-side
printf 'side\n' >"$rv/z7-side.md"
git -C "$rv" add z7-side.md
git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify -m "side change"
git -C "$rv" checkout -q main
printf 'main\n' >"$rv/z7-main.md"
git -C "$rv" add z7-main.md
git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify -m "main change"
git -C "$rv" -c core.hooksPath=/dev/null merge -q --no-ff --no-commit z7-side >/dev/null 2>&1
token_line >"$rv/merge-only.md"
git -C "$rv" add merge-only.md
git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify -m "merge side"
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share a merge-only file"
assert_eq "Z7 a credential added only in a merge resolution blocks the push (exit 1)" 1 "$rc"
assert_eq "Z7 the refused push (merge) leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
git -C "$rv" reset -q --hard "$rv_base"
git -C "$rv" branch -q -D z7-side

# =========================================================================
# Z10 — inherited git config never redirects a push
# =========================================================================

git init -q --bare "$tmp/remotes/decoy.git"
printf 'config redirect probe\n' >"$rv/config-redirect.md"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.pushurl GIT_CONFIG_VALUE_0="$tmp/remotes/decoy.git" \
  PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share despite inherited config"
assert_eq "Z10 a save under inherited git config succeeds" 0 "$rc"
assert_eq "Z10 the decoy repository receives nothing" "" "$(git -C "$tmp/remotes/decoy.git" rev-parse -q --verify refs/heads/main)"
assert_eq "Z10 the push reaches the checked remote" "$(git -C "$rv" rev-parse HEAD)" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
printf 'parameters probe\n' >"$rv/config-parameters.md"
GIT_CONFIG_PARAMETERS="'remote.origin.pushurl'='$tmp/remotes/decoy.git'" \
  PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share despite inherited parameters"
assert_eq "Z10 inherited GIT_CONFIG_PARAMETERS redirect nothing" "" "$(git -C "$tmp/remotes/decoy.git" rev-parse -q --verify refs/heads/main)"

# =========================================================================
# Z11 — the visibility checked is origin's, the remote the push goes to
# =========================================================================

remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
git init -q --bare "$tmp/remotes/upstream.git"
git -C "$rv" remote add upstream "$tmp/remotes/upstream.git"
# The push URL is spelled apart from the fetch URL, so only a check of the
# push URL reads public.
git -C "$rv" config remote.origin.pushurl "$tmp/remotes/./harbor-ledger.git"
git -C "$rv" config remote.origin.url >"$tmp/gh-public-repos"
printf 'visibility target probe\n' >"$rv/visibility-target.md"
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share to a public origin beside a private upstream"
assert_eq "Z11 a public origin is refused whatever other remotes read (exit 6)" 6 "$rc"
assert_eq "Z11 the refused push leaves origin untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
rm -f "$tmp/gh-public-repos"
git -C "$rv" config --unset remote.origin.pushurl
git -C "$rv" remote remove upstream

# =========================================================================
# Z14 — once the private repository exists, a failed setup keeps the venture
# =========================================================================

mkdir -p "$stubs/chmod-fail"
printf '#!/bin/sh\nexit 1\n' >"$stubs/chmod-fail/chmod"
/bin/chmod +x "$stubs/chmod-fail/chmod"
PATH="$stubs/chmod-fail:$stubs/gh-ok:$PATH" venture create --home remote --root "$tmp/z14" --owner acme mu
assert_eq "Z14 a scaffold failure after the repository exists exits 7" 7 "$rc"
assert_exists "Z14 the local venture is kept, not orphaning the repository" "$tmp/z14/mu/.git"
assert_eq "Z14 the kept venture is wired to the repository" origin "$(git -C "$tmp/z14/mu" remote)"
assert_contains "Z14 the failure names the repository" "acme/mu" "$out"
assert_contains "Z14 the failure points to the add-remote retry" "add-remote" "$out"
PATH="$stubs/gh-ok:$PATH" venture add-remote "$tmp/z14/mu"
assert_eq "Z14 add-remote finishes the setup" 0 "$rc"
assert_exists "Z14 the retry lays down the CI guard" "$tmp/z14/mu/.github/workflows/venture-guard.yml"
assert_eq "Z14 the retry wires the hooks" githooks "$(git -C "$tmp/z14/mu" config core.hooksPath)"

# =========================================================================
# Fork F6 — a session venture moved onto a remote stops reading as session
# =========================================================================

PATH="$stubs/gh-ok:$PATH" venture create --home session --root "$scratch" nu
venture bundle-init --title "Nu" "$scratch/nu"
venture save "$scratch/nu" "Start the Nu venture"
PATH="$stubs/gh-ok:$PATH" venture add-remote "$scratch/nu"
assert_eq "F6 add-remote on a session venture succeeds" 0 "$rc"
PATH="$stubs/gh-ok:$PATH" venture handoff "$scratch/nu"
assert_contains "F6 handoff reports the remote home" "$(printf 'home\tremote')" "$out"
assert_contains "F6 handoff reports the git rung" "$(printf 'rung\tgit')" "$out"
assert_not_contains "F6 handoff drops the session warning" "does not persist" "$out"

# =========================================================================
# Z25 — the push screen fails closed when it cannot list what is sent
# =========================================================================

PATH="$stubs/gh-ok:$PATH" venture create --home remote --root "$vroot" xi-missing
xm="$vroot/xi-missing"
venture bundle-init --title "Xi Missing" "$xm"
for p in seed opportunity disciplines reframe core; do venture mark-phase "$xm" "$p"; done
venture save "$xm" "Record the core"
lost=$(git -C "$xm" rev-parse HEAD:plan.md)
rm -f "$xm/.git/objects/$(printf '%s' "$lost" | cut -c1-2)/$(printf '%s' "$lost" | cut -c3-)"
PATH="$stubs/gh-ok:$PATH" venture save --push "$xm" "Share with an object missing"
assert_eq "Z25 a missing object stops the push before it starts (exit 2)" 2 "$rc"
assert_contains "Z25 the refusal says the outgoing files could not be read" "cannot read the files a push would send" "$out"

# =========================================================================
# Z15 — outgoing path names are screened as well as contents
# =========================================================================

rv_base=$(git -C "$rv" rev-parse HEAD)
remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
leak_name="notes-ghp_""0123456789abcdefghijklmnopqrstuvwxyz.md"
printf 'harmless\n' >"$rv/$leak_name"
git -C "$rv" add -A
git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify -m "outside commit with a leaky name"
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share a file whose name leaks"
assert_eq "Z15 a credential in an outgoing file name blocks the push (exit 1)" 1 "$rc"
assert_eq "Z15 the refused push leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
git -C "$rv" reset -q --hard "$rv_base"

# =========================================================================
# Z16 — the screened push file never opens with bytes that look like a
# binary format, which gitleaks' directory mode skips
# =========================================================================

mkdir -p "$stubs/gl-head"
cat >"$stubs/gl-head/gitleaks" <<EOF
#!/bin/sh
# Record the first bytes of each scanned path; report clean.
case "\$*" in *--help*) echo '--exit-code'; exit 0 ;; *planwright-canary*) exit 7 ;; esac
[ "\$1" = dir ] && head -c 8 "\$2" >>"$tmp/gl-head.log" && printf '\n' >>"$tmp/gl-head.log"
exit 0
EOF
chmod +x "$stubs/gl-head/gitleaks"
rv_base=$(git -C "$rv" rev-parse HEAD)
git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify --allow-empty -m '%PDF-1.4 looks like a document'
: >"$tmp/gl-head.log"
PATH="$stubs/gl-head:$stubs/gh-ok:$PATH" PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks \
  venture save --push "$rv" "Share a commit whose message opens like a PDF"
assert_not_contains "Z16 the screened push file does not open with the commit message" "%PDF" "$(cat "$tmp/gl-head.log")"
git -C "$rv" reset -q --hard "$rv_base"
# The stub reports clean, so that push went through; put both refs back.
git -C "$tmp/remotes/harbor-ledger.git" update-ref refs/heads/main "$rv_base"
git -C "$rv" update-ref refs/remotes/origin/main "$rv_base"

if command -v gitleaks >/dev/null 2>&1; then
  remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
  # A key block, which gitleaks' default rules flag (the low-entropy fixture
  # token is allowlisted there). Split literals keep scanners off this file.
  printf -- '%s\n%s\n%s\n' "-----BEGIN RSA PRIVATE KEY""-----" \
    "MIIEowIBAAKCAQEA7Zx2Lm""9Rt4Wb8Nc1Yv6Ha3Pd5Sj0Ug2EfKq" "-----END RSA PRIVATE KEY""-----" >"$rv/pdf-leak.md"
  git -C "$rv" add -A
  git -C "$rv" -c core.hooksPath=/dev/null commit -q --no-verify -m '%PDF-1.4 looks like a document'
  PATH="$stubs/gh-ok:$PATH" PLANWRIGHT_SECRET_SCREEN_TOOL=gitleaks \
    venture save --push "$rv" "Share a leak behind a PDF-looking message"
  assert_eq "Z16 real gitleaks still screens a push opening like a PDF (exit 1)" 1 "$rc"
  assert_eq "Z16 the refused push leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
  git -C "$rv" reset -q --hard "$rv_base"
fi

# =========================================================================
# Z27 — add-remote keeps an operator's own hooks path
# =========================================================================

PATH="$stubs/gh-ok:$PATH" venture create --home local --root "$vroot" omicron-hooks
oh="$vroot/omicron-hooks"
git -C "$oh" config core.hooksPath my-hooks
PATH="$stubs/gh-ok:$PATH" venture add-remote "$oh"
assert_eq "Z27 add-remote succeeds beside a custom hooks path" 0 "$rc"
assert_eq "Z27 the operator's hooks path is kept" my-hooks "$(git -C "$oh" config core.hooksPath)"
assert_contains "Z27 add-remote warns that the venture guards are not wired" "not wired" "$out"

# =========================================================================
# Z17 — every URL a push goes to must read private, not only the first
# =========================================================================

remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
git init -q --bare "$tmp/remotes/public-mirror.git"
first_push=$(git -C "$rv" config remote.origin.url)
git -C "$rv" config --add remote.origin.pushurl "$first_push"
git -C "$rv" config --add remote.origin.pushurl "https://github.com/public-mirror.git"
printf '%s\n' "https://github.com/public-mirror.git" >"$tmp/gh-public-repos"
printf 'second pushurl probe\n' >"$rv/second-pushurl.md"
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share with a public second push URL"
assert_eq "Z17 a public second push URL refuses the push (exit 6)" 6 "$rc"
assert_eq "Z17 the public mirror receives nothing" "" "$(git -C "$tmp/remotes/public-mirror.git" rev-parse -q --verify refs/heads/main)"
assert_eq "Z17 the private remote is untouched too" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
rm -f "$tmp/gh-public-repos"
git -C "$rv" config --unset-all remote.origin.pushurl

# =========================================================================
# Z20 — a stale origin/* ref never hides commits from the push screen
# =========================================================================

rv_base=$(git -C "$rv" rev-parse HEAD)
remote_before=$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)
leak_and_hide "$rv"
git -C "$rv" update-ref refs/remotes/origin/stale HEAD
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Share past a stale remote-tracking ref"
assert_eq "Z20 commits behind a stale origin ref are still screened (exit 1)" 1 "$rc"
assert_eq "Z20 the refused push leaves the remote untouched" "$remote_before" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"
git -C "$rv" update-ref -d refs/remotes/origin/stale
git -C "$rv" reset -q --hard "$rv_base"

# =========================================================================
# Z23 — only a GitHub host the CLI is signed in to can be checked or pushed to
# =========================================================================

PATH="$stubs/gh-ok:$PATH" venture create --home local --root "$vroot" pi-hosts
ph="$vroot/pi-hosts"
venture bundle-init --title "Pi Hosts" "$ph"
for p in seed opportunity disciplines reframe core; do venture mark-phase "$ph" "$p"; done
venture save "$ph" "Record the core"
git init -q --bare "$tmp/remotes/local-path.git"
git -C "$ph" remote add origin "$tmp/remotes/local-path.git"
PATH="$stubs/gh-ok:$PATH" venture save --push "$ph" "Share to a local path"
assert_eq "Z23 a push URL that is not a GitHub remote is refused (exit 6)" 6 "$rc"
assert_contains "Z23 the refusal names a non-GitHub remote" "not a GitHub" "$out"
assert_eq "Z23 the local path receives nothing" "" "$(git -C "$tmp/remotes/local-path.git" rev-parse -q --verify refs/heads/main)"
git -C "$ph" remote set-url origin "https://git.example.invalid/acme/pi-hosts.git"
PATH="$stubs/gh-ok:$PATH" venture save --push "$ph" "Share to another host"
assert_eq "Z23 a host the GitHub CLI is not signed in to is refused (exit 6)" 6 "$rc"
assert_contains "Z23 the refusal names the unsigned host" "not signed in to" "$out"

# =========================================================================
# Fork F7 — resume-point names the venture's home, so a resumed venture
# saves the way its home calls for
# =========================================================================

venture resume-point "$rv"
assert_contains "F7 resume-point names a remote home" "$(printf 'home\tremote')" "$out"
venture resume-point "$gp"
assert_contains "F7 resume-point names a local home" "$(printf 'home\tlocal')" "$out"
venture resume-point "$scratch/iota"
assert_contains "F7 resume-point names a session home" "$(printf 'home\tsession')" "$out"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all inception-venture tests passed"
