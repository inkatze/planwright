#!/bin/bash
# Tests for scripts/resolve-policy-knob.sh and scripts/protected-branch.sh: the
# human-gates policy knobs, each resolved through the four-layer overlay with a
# strict degrade target, and the protected-branch set built from its core
# floor plus the protected_branches additions.
#
# Covers REQ-C1.1, REQ-D1.1, REQ-D1.8, REQ-E1.1, REQ-E1.2, REQ-F1.1, REQ-F1.5,
# and REQ-H1.3 at the resolver level; the readers arrive with the guard and the
# helpers.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-resolve-policy-knob.sh
set -euf
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RPK="$here/../scripts/resolve-policy-knob.sh"
PB="$here/../scripts/protected-branch.sh"
shipped_defaults="$here/../config/defaults.yml"
options_ref="$here/../docs/options-reference.md"

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
# require it to stay empty (the set is read locally, never from the host).
host_log="$tmp/host-calls.log"
: >"$host_log"
for tool in gh curl; do
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 1\n' "$tool" "$host_log" >"$tmp/bin/$tool"
  chmod +x "$tmp/bin/$tool"
done

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

# The knob table: name | legal values | the core value the fixture ships (the
# permissive one where the knob has one, so a degrade that fell to core would
# be visible) | the strict degrade target | a malformed value.
KNOBS='ready_flip_policy|human unit-owner|unit-owner|human|agent
merge_policy|human on-approval policy-class|policy-class|human|auto
merge_class_max_lines|0 1 400|400|0|-5
merge_class_exclude_paths|docs/* vendor/*.lock|docs/*|*|a,b
merge_class_strategy|sole-allowed squash merge rebase|squash|sole-allowed|fast-forward
worker_base_merge|allow deny|allow|deny|yes
worker_merge_conflict_policy|halt resolve|resolve|halt|merge
unpushed_rewrite|allow deny|allow|deny|sometimes'

# A stubbed reader: the contract every reader follows is that a resolver
# failure is a refusal of the act, whatever the value would have been.
stub_reader() {
  _v=$(rpk "$1" 2>/dev/null) || {
    echo deny
    return 0
  }
  echo "value:$_v"
}

printf '%s\n' "$KNOBS" | while IFS='|' read -r knob legal permissive strict malformed; do
  printf '%s: %s\n' "$knob" "$permissive" >"$core_cfg"

  # Every legal value resolves from every layer.
  for v in $legal; do
    printf '%s: %s\n' "$knob" "$v" >"$core_cfg"
    reset_layers
    got=$(rpk "$knob") || fail "$knob: core '$v' did not resolve"
    [ "$got" = "$v" ] || fail "$knob: core '$v' resolved to '$got'"
    printf '%s: %s\n' "$knob" "$permissive" >"$core_cfg"
    for layer_cfg in "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"; do
      reset_layers
      printf '%s: %s\n' "$knob" "$v" >"$layer_cfg"
      got=$(rpk "$knob") || fail "$knob: '$v' in $layer_cfg did not resolve"
      [ "$got" = "$v" ] || fail "$knob: '$v' in $layer_cfg resolved to '$got'"
    done
  done

  # A malformed repo-tracked value exits non-zero, and a reader denies.
  reset_layers
  printf '%s: %s\n' "$knob" "$malformed" >"$tracked_cfg"
  rc=0
  rpk "$knob" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 4 ] || fail "$knob: malformed repo-tracked value exited $rc, expected 4"
  [ "$(stub_reader "$knob")" = deny ] || fail "$knob: the stub reader did not deny a malformed repo-tracked value"

  # A malformed adopter or machine-local value degrades to the strict target
  # with a warning, never to the core value the fixture ships.
  for layer_cfg in "$adopter_cfg" "$mlocal_cfg"; do
    reset_layers
    printf '%s: %s\n' "$knob" "$malformed" >"$layer_cfg"
    rc=0
    got=$(rpk "$knob" 2>"$tmp/err") || rc=$?
    [ "$rc" = 0 ] || fail "$knob: malformed $layer_cfg exited $rc, expected 0"
    [ "$got" = "$strict" ] || fail "$knob: malformed $layer_cfg resolved to '$got', expected '$strict'"
    grep -q warning "$tmp/err" || fail "$knob: malformed $layer_cfg degraded without a warning"
    # A malformed FILE in that layer is the same case, even when the file
    # also sets the knob to its strict value on a well-formed line.
    printf '%s: %s\nother:\n  - x\n' "$knob" "$strict" >"$layer_cfg"
    got=$(rpk "$knob" 2>/dev/null) || fail "$knob: a malformed $layer_cfg file did not resolve"
    [ "$got" = "$strict" ] || fail "$knob: a malformed $layer_cfg file resolved to '$got', expected '$strict'"
  done

  # A key no layer sets falls back to the strict target too.
  reset_layers
  : >"$core_cfg"
  got=$(rpk "$knob" 2>/dev/null) || fail "$knob: an unset key did not resolve"
  [ "$got" = "$strict" ] || fail "$knob: an unset key resolved to '$got', expected '$strict'"
done
echo "ok: each gate knob resolves through all four layers and degrades to its strict target"

# The flip wait is a bound, not a gate: a malformed overlay value degrades to
# the core default like every other duration knob.
printf 'ready_flip_ci_wait: 10m\n' >"$core_cfg"
reset_layers
[ "$(rpk ready_flip_ci_wait)" = 10m ] || fail "ready_flip_ci_wait: the core value did not resolve"
printf 'ready_flip_ci_wait: 30s\n' >"$mlocal_cfg"
[ "$(rpk ready_flip_ci_wait)" = 30s ] || fail "ready_flip_ci_wait: a machine-local value did not resolve"
reset_layers
printf 'ready_flip_ci_wait: soon\n' >"$adopter_cfg"
[ "$(rpk ready_flip_ci_wait 2>/dev/null)" = 10m ] || fail "ready_flip_ci_wait: a malformed adopter value did not degrade to the core default"
reset_layers
printf 'ready_flip_ci_wait: soon\n' >"$tracked_cfg"
rc=0
rpk ready_flip_ci_wait >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "ready_flip_ci_wait: a malformed repo-tracked value exited $rc, expected 4"
echo "ok: ready_flip_ci_wait resolves as a duration"

# Unknown knob names and missing arguments are usage errors.
for args in "" "no_such_knob" "ready_flip_policy extra"; do
  rc=0
  # shellcheck disable=SC2086
  rpk $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage: '$args' exited $rc, expected 2"
done
echo "ok: an unknown knob is a usage error"

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

for layer_cfg in "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"; do
  for body in 'protected_branches: main,master' 'protected_branches:
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
for bad in "" "-main" 'ma$(x)in' "a b" "a//b" "/main" "main/" "a..b"; do
  rc=0
  pb "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "protected-branch: the invalid name '$bad' exited $rc, expected 2"
done
rc=0
pb >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "protected-branch: no argument exited $rc, expected 2"
echo "ok: an invalid branch name is refused before it is matched"

[ ! -s "$host_log" ] || fail "a host call was made: $(cat "$host_log")"
echo "ok: no host call in the stubbed call log"

# --- The shipped knobs: present, documented, resolvable, and at the defaults
#     the options reference states.
SHIPPED='ready_flip_policy|unit-owner
ready_flip_ci_wait|10m
merge_policy|human
merge_class_max_lines|0
merge_class_exclude_paths|
merge_class_strategy|sole-allowed
worker_base_merge|allow
worker_merge_conflict_policy|halt
unpushed_rewrite|allow
protected_branches|main master planwright/*/spec'
reset_layers
printf '%s\n' "$SHIPPED" | while IFS='|' read -r knob expected; do
  grep -q "^${knob}:" "$shipped_defaults" || fail "'$knob' is not in config/defaults.yml"
  grep -q "| \`$knob\` |" "$options_ref" || fail "'$knob' has no docs/options-reference.md row"
  got=$(PATH="$tmp/bin:$PATH" PLANWRIGHT_CONFIG_DEFAULTS="$shipped_defaults" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" /bin/sh "$RPK" "$knob") \
    || fail "'$knob' did not resolve against the shipped defaults"
  [ "$got" = "$expected" ] || fail "'$knob' ships as '$got', expected '$expected'"
done
/bin/bash "$here/../scripts/check-options-reference.sh" >/dev/null 2>&1 \
  || fail "scripts/check-options-reference.sh failed over the shipped defaults"
echo "ok: every policy knob is shipped, documented, and resolves to its stated default"

echo "ALL PASS: resolve-policy-knob"
