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
unset CLAUDE_CODE_REMOTE PLANWRIGHT_INCEPTION_EPHEMERAL

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
# Fake gh: auth succeeds; repo create makes a bare repo and wires it as the
# remote, recording the arguments it was given.
printf '%s\n' "\$*" >>"$tmp/gh-calls.log"
case "\$1 \$2" in
  "auth status") exit 0 ;;
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
    bare="$tmp/remotes/\$(printf '%s' "\$name" | tr / _).git"
    git init -q --bare "\$bare" || exit 1
    git -C "\$src" remote add "\$remote" "\$bare" || exit 1
    exit 0
    ;;
esac
exit 1
EOF
cat >"$stubs/gh-noauth/gh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$stubs/nogit/git" "$stubs/gh-ok/gh" "$stubs/gh-noauth/gh"

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

PATH="$stubs/nogit:$PATH" PLANWRIGHT_INCEPTION_EPHEMERAL=1 venture detect
assert_contains "H1.1 no git and ephemeral is still session-only" "$(printf 'local\tsession-only')" "$out"

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

venture create --home sideways --root "$tmp/v-guard" beta
assert_eq "create rejects an unknown home (usage exit 2)" 2 "$rc"

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

venture bundle-init --title "Again" "$rp"
assert_eq "bundle-init never overwrites an existing bundle (exit 5)" 5 "$rc"

venture resume-point "$rp"
assert_contains "B1.7 a fresh skeleton resumes at the first phase" "$(printf 'next\tseed')" "$out"
assert_contains "B1.7 a fresh skeleton has no completed phase" "$(printf 'done\tnone')" "$out"

venture mark-phase "$rp" seed
assert_eq "B1.7 mark-phase records a phase (exit)" 0 "$rc"
venture mark-phase "$rp" opportunity
venture resume-point "$rp"
assert_contains "B1.7 resume picks up after the last completed phase" "$(printf 'next\tdisciplines')" "$out"
assert_contains "B1.7 resume names the last completed phase" "$(printf 'done\topportunity')" "$out"
assert_eq "B1.7 the phase log lands in the Changelog section" 2 "$(sed -n '/^## Changelog/,$p' "$rp/brief.md" | grep -c 'Elicitation:')"

venture mark-phase "$rp" bogus
assert_eq "mark-phase rejects an unknown phase (exit 2)" 2 "$rc"

for p in disciplines reframe core registers finalize; do
  venture mark-phase "$rp" "$p"
done
venture resume-point "$rp"
assert_contains "B1.7 a finished elicitation resumes into re-entry" "$(printf 'next\tcomplete')" "$out"

sed 's/^\*\*Format-version:\*\* 1\.0$/**Format-version:** 9.0/' "$rp/plan.md" >"$rp/plan.md.new" && mv "$rp/plan.md.new" "$rp/plan.md"
venture resume-point "$rp"
assert_eq "C1.7 resume refuses an unsupported format-version (exit 3)" 3 "$rc"
assert_contains "C1.7 the refusal is the validator's plain-language message" "unsupported format-version" "$out"

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
venture save "$lv" "Record the elicited bundle"
assert_eq "dry run (local): the filled bundle saves" 0 "$rc"
/bin/sh "$VALIDATE" "$lv" >/dev/null 2>&1
assert_eq "dry run (local): the bundle is validator-clean" 0 "$?"
assert_eq "dry run (local): the export rode the save" exports/venture.html "$(git -C "$lv" ls-files exports/venture.html)"
assert_eq "dry run (local): two saves landed" 2 "$(git -C "$lv" rev-list --count HEAD)"

venture save --expert "$lv" "Expert-mode save with nothing to save"
assert_eq "H1.2 expert save with nothing staged is not an error" 0 "$rc"

venture save --push "$lv" "Try to push"
assert_eq "A1.4 the local arm refuses to push (exit 6)" 6 "$rc"
assert_contains "A1.4 the refusal says nothing leaves the machine" "nothing leaves this machine" "$out"

venture handoff "$lv"
assert_contains "handoff names the rung" "$(printf 'rung\tgit')" "$out"
assert_contains "handoff names the validator result" "$(printf 'bundle\tclean')" "$out"

# REQ-H1.3 — the local-only venture gains a remote later: same repo, history kept.
before=$(git -C "$lv" rev-parse HEAD)
PATH="$stubs/gh-ok:$PATH" venture add-remote "$lv"
assert_eq "H1.3 add-remote succeeds" 0 "$rc"
assert_eq "H1.3 nothing re-initialized: history preserved" "$before" "$(git -C "$lv" rev-parse HEAD)"
assert_eq "H1.3 the remote is wired" origin "$(git -C "$lv" remote)"
assert_exists "H1.3 the CI guard joins on the remote rung" "$lv/.github/workflows/venture-guard.yml"
assert_exists "H1.3 the repo was created private" "$tmp/remotes/northwind-signals.git"
assert_contains "H1.3 gh was asked for a private repo" "--private" "$(cat "$tmp/gh-calls.log")"

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
PATH="$stubs/gh-ok:$PATH" venture save --push "$rv" "Record the elicited bundle"
assert_eq "dry run (remote): save and push succeed" 0 "$rc"
/bin/sh "$VALIDATE" "$rv" >/dev/null 2>&1
assert_eq "dry run (remote): the bundle is validator-clean" 0 "$?"
assert_eq "dry run (remote): the push reached the private remote" \
  "$(git -C "$rv" rev-parse HEAD)" "$(git -C "$tmp/remotes/harbor-ledger.git" rev-parse refs/heads/main)"

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
PATH="$stubs/nogit:$PATH" venture handoff "$pv"
assert_contains "H1.5 plain rung degradation repeated at handoff" "git unavailable" "$out"

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
rm -f "$lv/leak.md"
git -C "$lv" reset -q

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

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all inception-venture tests passed"
