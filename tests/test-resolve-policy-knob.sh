#!/bin/bash
# Tests for scripts/resolve-policy-knob.sh: the human-gates policy knobs, each
# resolved through the four-layer overlay with a strict degrade target. The
# protected set has its own file, tests/test-protected-branch.sh.
#
# Covers REQ-C1.1, REQ-D1.1, REQ-D1.8, REQ-E1.1, REQ-E1.2, REQ-F1.1, and
# REQ-H1.3 at the resolver level; the readers arrive with the guard and the
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
shipped_defaults="$here/../config/defaults.yml"
options_ref="$here/../docs/options-reference.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RPK" ] || fail "scripts/resolve-policy-knob.sh missing or not executable"

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

# The knob table: name | legal values | the core value the fixture ships (the
# permissive one where the knob has one, so a degrade that fell to core would
# be visible) | the strict degrade target | a malformed value.
KNOBS='ready_flip_policy|human unit-owner|unit-owner|human|agent
merge_policy|human on-approval policy-class|policy-class|human|auto
merge_class_max_lines|0 1 400|400|0|-5
merge_class_exclude_paths|docs/* vendor/*.lock *|docs/*|*|a,b
merge_class_strategy|sole-allowed squash merge rebase|squash|sole-allowed|fast-forward
worker_base_merge|allow deny|allow|deny|yes
worker_merge_conflict_policy|halt resolve|resolve|halt|merge
unpushed_rewrite|allow deny|allow|deny|sometimes'

# A stubbed reader <knob> <permissive value>: it allows the act only on the
# permissive value and refuses on anything else, a resolver failure included,
# which is the contract every reader of these knobs follows.
stub_reader() {
  _v=$(rpk "$1" 2>/dev/null) || {
    echo deny
    return 0
  }
  if [ "$_v" = "$2" ]; then echo allow; else echo deny; fi
}

printf '%s\n' "$KNOBS" | while IFS='|' read -r knob legal permissive strict malformed; do
  printf '%s: %s\n' "$knob" "$permissive" >"$core_cfg"

  # Every legal value resolves from every layer.
  overlays_ran=0
  for v in $legal; do
    printf '%s: %s\n' "$knob" "$v" >"$core_cfg"
    reset_layers
    got=$(rpk "$knob") || fail "$knob: core '$v' did not resolve"
    [ "$got" = "$v" ] || fail "$knob: core '$v' resolved to '$got'"
    printf '%s: %s\n' "$knob" "$permissive" >"$core_cfg"
    # Each overlay is exercised with the strict value only: the permissive one
    # is already the core value, so an overlay setting it would pass even if
    # the overlay were ignored, and the core loop already covers the rest.
    [ "$v" = "$strict" ] || continue
    overlays_ran=1
    for layer_cfg in "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"; do
      reset_layers
      printf '%s: %s\n' "$knob" "$v" >"$layer_cfg"
      got=$(rpk "$knob") || fail "$knob: '$v' in $layer_cfg did not resolve"
      [ "$got" = "$v" ] || fail "$knob: '$v' in $layer_cfg resolved to '$got'"
    done
  done

  [ "$overlays_ran" = 1 ] || fail "$knob: the strict value '$strict' is not in the legal list, so no overlay was exercised"

  # A malformed repo-tracked value exits non-zero, and a reader denies.
  reset_layers
  printf '%s: %s\n' "$knob" "$malformed" >"$tracked_cfg"
  rc=0
  rpk "$knob" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 4 ] || fail "$knob: malformed repo-tracked value exited $rc, expected 4"
  [ "$(stub_reader "$knob" "$permissive")" = deny ] || fail "$knob: the stub reader did not deny a malformed repo-tracked value"

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
    [ "$got" != "$permissive" ] || fail "$knob: a reader would allow on a malformed $layer_cfg value"
    # A malformed FILE in that layer is the same case, even when the file
    # also sets the knob to its strict value on a well-formed line.
    printf '%s: %s\nother:\n  - x\n' "$knob" "$strict" >"$layer_cfg"
    got=$(rpk "$knob" 2>/dev/null) || fail "$knob: a malformed $layer_cfg file did not resolve"
    [ "$got" = "$strict" ] || fail "$knob: a malformed $layer_cfg file resolved to '$got', expected '$strict'"
  done

  # A key no layer sets falls back to the strict target too.
  reset_layers
  : >"$core_cfg"
  got=$(rpk "$knob" 2>"$tmp/err") || fail "$knob: an unset key did not resolve"
  [ "$got" = "$strict" ] || fail "$knob: an unset key resolved to '$got', expected '$strict'"
  grep -q warning "$tmp/err" || fail "$knob: an unset key fell back without a warning"
done
echo "ok: each gate knob resolves through all four layers and degrades to its strict target"

# YAML reads `key : v` as the key, and a repeated key as its last value, while
# the flat reader skips the first and takes the first of the second: either
# shape could otherwise land on the permissive core value.
printf 'worker_base_merge: allow\n' >"$core_cfg"
for body in 'worker_base_merge : deny' 'worker_base_merge: allow
worker_base_merge: deny'; do
  reset_layers
  printf '%s\n' "$body" >"$tracked_cfg"
  rc=0
  rpk worker_base_merge >/dev/null 2>&1 || rc=$?
  [ "$rc" = 4 ] || fail "worker_base_merge: a repo-tracked '$body' exited $rc, expected 4"
  for layer_cfg in "$adopter_cfg" "$mlocal_cfg"; do
    reset_layers
    printf '%s\n' "$body" >"$layer_cfg"
    got=$(rpk worker_base_merge 2>"$tmp/err") || fail "worker_base_merge: '$body' in $layer_cfg did not resolve"
    [ "$got" = deny ] || fail "worker_base_merge: '$body' in $layer_cfg resolved to '$got', expected deny"
    grep -q warning "$tmp/err" || fail "worker_base_merge: '$body' in $layer_cfg degraded without a warning"
  done
done
reset_layers
echo "ok: a spaced or repeated gate key is malformed, never read past"

# The flip wait is a bound, not a gate: a malformed overlay value degrades to
# the core default like every other duration knob.
printf 'ready_flip_ci_wait: 10m\n' >"$core_cfg"
reset_layers
[ "$(rpk ready_flip_ci_wait)" = 10m ] || fail "ready_flip_ci_wait: the core value did not resolve"
for layer_cfg in "$adopter_cfg" "$tracked_cfg" "$mlocal_cfg"; do
  reset_layers
  printf 'ready_flip_ci_wait: 30s\n' >"$layer_cfg"
  [ "$(rpk ready_flip_ci_wait)" = 30s ] || fail "ready_flip_ci_wait: a value in $layer_cfg did not resolve"
done
for layer_cfg in "$adopter_cfg" "$mlocal_cfg"; do
  reset_layers
  printf 'ready_flip_ci_wait: soon\n' >"$layer_cfg"
  [ "$(rpk ready_flip_ci_wait 2>/dev/null)" = 10m ] || fail "ready_flip_ci_wait: a malformed $layer_cfg value did not degrade to the core default"
done
reset_layers
: >"$core_cfg"
got=$(rpk ready_flip_ci_wait 2>"$tmp/err") || fail "ready_flip_ci_wait: an unset key did not resolve"
[ "$got" = 10m ] || fail "ready_flip_ci_wait: an unset key resolved to '$got', expected 10m"
grep -q warning "$tmp/err" || fail "ready_flip_ci_wait: an unset key fell back without a warning"
printf 'ready_flip_ci_wait: 10m\n' >"$core_cfg"
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
  row_default=$(grep "^| \`$knob\` |" "$options_ref" | cut -d'|' -f3 | sed -e 's/^ *//' -e 's/ *$//')
  [ -n "$row_default" ] || fail "'$knob' has no docs/options-reference.md row"
  case "$row_default" in
    "(empty)") row_default="" ;;
    *) row_default=$(printf '%s' "$row_default" | tr -d '`') ;;
  esac
  [ "$knob" = protected_branches ] || [ "$row_default" = "$expected" ] \
    || fail "'$knob': the options reference states '$row_default', the config ships '$expected'"
  [ "$knob" != protected_branches ] || [ -z "$row_default" ] \
    || fail "protected_branches: the options reference states '$row_default', the config ships no additions"
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
