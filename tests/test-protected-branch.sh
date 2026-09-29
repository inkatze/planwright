#!/bin/bash
# Tests for scripts/protected-branch.sh and the protected_branches arm of
# scripts/resolve-policy-knob.sh: the protected set is the core floor plus the
# knob's additions, read locally, and any read failure refuses the act.
#
# Covers REQ-F1.5 at the resolver level; the guard that calls it arrives
# later.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-protected-branch.sh
set -euf
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RPK="$here/../scripts/resolve-policy-knob.sh"
PB="$here/../scripts/protected-branch.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RPK" ] || fail "scripts/resolve-policy-knob.sh missing or not executable"
[ -x "$PB" ] || fail "scripts/protected-branch.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude" "$tmp/bin"
adopter_cfg="$adopter_root/planwright.yml"
tracked_cfg="$repo/.claude/planwright.yml"
mlocal_cfg="$repo/.claude/planwright.local.yml"

# Host stubs: any call lands in the log, and the protected-set assertions
# require it to stay empty (the set is read locally, never from the host). git
# passes through except for the subcommands that reach a remote.
host_log="$tmp/host-calls.log"
: >"$host_log"
for tool in gh curl; do
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 1\n' "$tool" "$host_log" >"$tmp/bin/$tool"
  chmod +x "$tmp/bin/$tool"
done
real_git=$(command -v git)
cat >"$tmp/bin/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    ls-remote | fetch | pull | push | remote)
      echo "git \$*" >>"$host_log"
      exit 1
      ;;
  esac
done
exec "$real_git" "\$@"
EOF
chmod +x "$tmp/bin/git"

reset_layers() {
  rm -f "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"
}

with_layers() {
  PATH="$tmp/bin:$PATH" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    "$@"
}

rpk() {
  with_layers /bin/sh "$RPK" "$@"
}

# --- The protected set.
pb() {
  with_layers /bin/sh "$PB" "$@"
}

printf 'protected_branches:\n' >"$core_cfg"
reset_layers
set_out=$(rpk protected_branches) || fail "protected_branches: the unset knob did not resolve"
for floor in main master 'planwright/*/spec'; do
  case " $set_out " in
    *" $floor "*) ;;
    *) fail "protected_branches: the floor entry '$floor' is missing from '$set_out'" ;;
  esac
done
echo "ok: the core floor is present with the knob unset"

# pb_expect <expected exit> <branch> <label>
pb_expect() {
  _rc=0
  pb "$2" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" = "$1" ] || fail "protected-branch: $3 ('$2') exited $_rc, expected $1"
}
pb_expect 1 main "the floor protects main"
pb_expect 1 master "the floor protects master"
pb_expect 1 planwright/human-gates/spec "the floor protects a spec branch"
pb_expect 1 refs/heads/main "a refs/heads/ target is stripped before matching"
pb_expect 0 planwright/a/b/spec "the spec pattern's * does not span a /"
pb_expect 0 planwright/human-gates/task-4 "a task branch is outside the floor"
pb_expect 0 mainline "a floor name is not a prefix match"

for layer_cfg in "$adopter_cfg" "$mlocal_cfg"; do
  reset_layers
  printf 'protected_branches: release/*\n' >"$layer_cfg"
  pb_expect 1 release/1.0 "an addition in $layer_cfg protects its matches"
done
reset_layers
printf 'protected_branches: release/* hotfix\n' >"$tracked_cfg"
pb_expect 1 release/1.0 "an overlay glob protects its matches"
pb_expect 0 release/1.0/rc "an overlay glob's * does not span a /"
pb_expect 1 hotfix "an overlay name protects its branch"
pb_expect 1 main "an overlay keeps the floor"
printf 'protected_branches: feature-x\n' >"$tracked_cfg"
pb_expect 1 main "an overlay naming only a feature branch leaves main protected"
pb_expect 1 feature-x "the overlay's feature branch is protected"
printf 'protected_branches: refs/heads/stable\n' >"$tracked_cfg"
pb_expect 1 stable "an overlay entry is stripped of refs/heads/ too"
echo "ok: overlay additions join the floor and never shrink it"

# An entry that could never match a branch is malformed, not silently inert:
# an operator writing `release/**` or `release/` meant to protect something.
for bad in 'release/' '/release' 'release//x' 'a..b/*' '.' 'release/**' '.hidden' 'x.lock' 'HEAD' 'release.' 'a/b.'; do
  printf 'protected_branches: %s\n' "$bad" >"$tracked_cfg"
  rc=0
  rpk protected_branches >/dev/null 2>&1 || rc=$?
  [ "$rc" = 4 ] || fail "resolve-policy-knob: the unmatchable entry '$bad' exited $rc, expected 4"
done
reset_layers
echo "ok: an entry that can never match a branch is a read failure"

# Case folds, as the tower queue's push screen folds it: over-refusing is the
# safe direction, and a case-insensitive filesystem makes `Main` the same ref.
pb_expect 1 Main "the floor matches regardless of case"
pb_expect 1 refs/heads/MASTER "a stripped target matches regardless of case"
printf 'protected_branches: Release/*\n' >"$tracked_cfg"
pb_expect 1 release/1.0 "an overlay entry matches regardless of case"
printf 'protected_branches: Refs/Heads/release/*\n' >"$tracked_cfg"
pb_expect 1 release/1.0 "an entry's refs/heads/ prefix is stripped regardless of case"
printf 'protected_branches: REFS/HEADS/HEAD\n' >"$tracked_cfg"
rc=0
rpk protected_branches >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "resolve-policy-knob: an unmatchable entry behind a folded refs/heads/ exited $rc, expected 4"
reset_layers
pb_expect 1 REFS/HEADS/main "a target's refs/heads/ prefix is stripped regardless of case"
pb_expect 2 Refs/heads/HEAD "a target's name is validated after a folded strip"
echo "ok: protected-branch matching folds case"

for layer_cfg in "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"; do
  for body in 'protected_branches: main,master' 'protected_branches : release' 'protected_branches:
protected_branches: release' 'protected_branches:
  - release' 'protected_branches: release
other:
  - x'; do
    reset_layers
    printf '%s\n' "$body" >"$layer_cfg"
    rc=0
    pb release >/dev/null 2>&1 || rc=$?
    [ "$rc" = 4 ] || fail "protected-branch: a malformed $layer_cfg ('$body') exited $rc, expected 4"
    rc=0
    rpk protected_branches >/dev/null 2>&1 || rc=$?
    [ "$rc" = 4 ] || fail "resolve-policy-knob: a malformed $layer_cfg ('$body') exited $rc, expected 4"
  done
done
reset_layers
: >"$core_cfg"
for cmd in pb rpk; do
  rc=0
  if [ "$cmd" = pb ]; then pb feature-x >/dev/null 2>&1 || rc=$?; else rpk protected_branches >/dev/null 2>&1 || rc=$?; fi
  [ "$rc" = 5 ] || fail "$cmd: an unset protected_branches exited $rc, expected 5"
done
echo "ok: a malformed or unset protected_branches is a read failure, never the floor alone"

printf 'protected_branches:\n' >"$core_cfg"
reset_layers
# shellcheck disable=SC2016 # the literal `$(x)` is the refused input
for bad in "" "-main" 'ma$(x)in' "a b" "a//b" "/main" "main/" "a..b" HEAD a.lock .x a/.b release. \
  "$(printf 'a%.0s' $(seq 256))"; do
  rc=0
  pb "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "protected-branch: the invalid name '$bad' exited $rc, expected 2"
done
rc=0
pb >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "protected-branch: no argument exited $rc, expected 2"
echo "ok: an invalid branch name is refused before it is matched"

# A broken install (the shared resolver missing) is exit 5, never a code a
# caller could read as "usage" or "protected".
broken="$tmp/broken/scripts"
mkdir -p "$broken"
cp "$RPK" "$PB" "$here/../scripts/echo-safety.sh" "$broken/"
for cmd in "resolve-policy-knob.sh unpushed_rewrite" "protected-branch.sh feature-x"; do
  rc=0
  # shellcheck disable=SC2086
  with_layers /bin/sh "$broken"/$cmd >/dev/null 2>&1 || rc=$?
  [ "$rc" = 5 ] || fail "broken install: '$cmd' exited $rc, expected 5"
done
# Any other resolver failure reaches the caller as 5 too.
printf '#!/bin/sh\nexit 127\n' >"$broken/resolve-policy-knob.sh"
rc=0
with_layers /bin/sh "$broken/protected-branch.sh" feature-x >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "broken install: an unexpected resolver exit reached protected-branch.sh's caller as $rc, expected 5"
echo "ok: a missing shared resolver is a broken install (exit 5)"

[ ! -s "$host_log" ] || fail "a host call was made: $(cat "$host_log")"
echo "ok: no host call in the stubbed call log"

echo "ALL PASS: protected-branch"
