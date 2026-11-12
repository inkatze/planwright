#!/bin/bash
# Tests for scripts/host-registry.sh: the machine-local remote-host registry.
# Fixtures only: placeholder aliases, a fake config and a fake registry under
# a scratch directory; no SSH call and no real host config is ever read.
# Plain bash 3.2, inline asserts.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
HR="$REPO_ROOT/scripts/host-registry.sh"

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
assert_contains() {
  case $3 in
    *"$2"*) pass "$1" ;;
    *) fail "$1 (expected to contain '$2', got '$3')" ;;
  esac
}

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/adopter" "$tmp/pdata"
printf 'unrelated_key: 1\n' >"$tmp/core.yml"

# run <repo-root-or-none> <local-config> <args...>: one reader call with every
# config layer pinned under the scratch directory.
run() {
  rn_repo=$1
  rn_local=$2
  shift 2
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR HOME="$tmp/home" \
    CLAUDE_PLUGIN_DATA="$tmp/pdata" PLANWRIGHT_CONFIG_DEFAULTS="$tmp/core.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" PLANWRIGHT_REPO_ROOT="$rn_repo" \
    PLANWRIGHT_LOCAL_CONFIG="$rn_local" GIT_CEILING_DIRECTORIES="$tmp" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    /bin/sh "$HR" "$@" >"$tmp/.out" 2>"$tmp/.err"
  rc=$?
  out=$(cat "$tmp/.out")
  err=$(cat "$tmp/.err")
}

# conf <registry-path>: a machine-local config pointing at the registry.
conf() {
  printf 'remote_hosts_file: %s\n' "$1" >"$tmp/local.yml"
}
GOOD='host box-a account=acct-one ceiling=2 compute=accepted clone.demo=/srv/demo clone.other=/srv/other'
reg() { printf '%s\n' "$@" >"$tmp/reg.txt"; }
reg "$GOOD"
conf "$tmp/reg.txt"

# A valid registry resolves, with defaults for the optional fields.
run none "$tmp/local.yml" validate
assert_eq "valid registry validates" 0 "$rc"
run none "$tmp/local.yml" get box-a ceiling
assert_eq "ceiling read" 2 "$out"
run none "$tmp/local.yml" get box-a clone.demo
assert_eq "clone path read" /srv/demo "$out"
run none "$tmp/local.yml" get box-a grace
assert_eq "grace defaults to thirty minutes" 30 "$out"
run none "$tmp/local.yml" get box-a shared
assert_eq "shared defaults to no" no "$out"
run none "$tmp/local.yml" get box-a hold
assert_eq "hold defaults to no" no "$out"
run none "$tmp/local.yml" get box-a account
assert_eq "account label read" acct-one "$out"
run none "$tmp/local.yml" list
assert_eq "list names each host" box-a "$out"
run none "$tmp/local.yml" get box-missing ceiling
assert_eq "unknown host is not found" 3 "$rc"

# A malformed alias is refused with the field named.
# shellcheck disable=SC2016
for bad in -lead 'sp;ace' 'a$b' ''; do
  reg "host $bad account=acct-one ceiling=1 compute=accepted"
  run none "$tmp/local.yml" validate
  assert_eq "alias '$bad' refused" 1 "$rc"
  assert_contains "alias '$bad' names the field" alias "$err"
done
reg "$GOOD"

# A relative clone path is refused with the field named.
reg 'host box-a account=acct-one ceiling=1 compute=accepted clone.demo=rel/path'
run none "$tmp/local.yml" validate
assert_eq "relative clone path refused" 1 "$rc"
assert_contains "relative clone path names the field" clone.demo "$err"
reg 'host box-a account=acct-one ceiling=1 compute=accepted clone.demo=/a/../b'
run none "$tmp/local.yml" validate
assert_eq "dotdot clone path refused" 1 "$rc"

# Other fields are refused with the field named.
reg 'host box-a ceiling=1 compute=accepted'
run none "$tmp/local.yml" validate
assert_eq "missing account refused" 1 "$rc"
assert_contains "missing account names the field" account "$err"
reg 'host box-a account=acct-one ceiling=zero compute=accepted'
run none "$tmp/local.yml" validate
assert_eq "non-numeric ceiling refused" 1 "$rc"
assert_contains "ceiling names the field" ceiling "$err"
reg 'host box-a account=acct-one ceiling=1 shared=maybe compute=accepted'
run none "$tmp/local.yml" validate
assert_eq "bad shared flag refused" 1 "$rc"
reg 'host box-a account=acct-one ceiling=1 bogus=1'
run none "$tmp/local.yml" validate
assert_eq "unknown field refused" 1 "$rc"
assert_contains "unknown field named" bogus "$err"
reg 'host box-a account=acct-one ceiling=1' 'host box-a account=acct-one ceiling=2'
run none "$tmp/local.yml" validate
assert_eq "duplicate alias refused" 1 "$rc"

# No compute stance: refused for compute, accepted for workers.
reg 'host box-a account=acct-one ceiling=1 clone.demo=/srv/demo'
run none "$tmp/local.yml" validate
assert_eq "no stance still validates" 0 "$rc"
run none "$tmp/local.yml" validate --for workers
assert_eq "no stance accepted for workers" 0 "$rc"
run none "$tmp/local.yml" validate --for compute
assert_eq "no stance refused for compute" 1 "$rc"
assert_contains "compute refusal names the field" compute "$err"
run none "$tmp/local.yml" validate --for compute --host box-a
assert_eq "no stance refused for compute, named host" 1 "$rc"
for stance in login-free accepted; do
  reg "host box-a account=acct-one ceiling=1 compute=$stance"
  run none "$tmp/local.yml" validate --for compute
  assert_eq "stance $stance takes compute" 0 "$rc"
done
reg 'host box-a account=acct-one ceiling=1 compute=whatever'
run none "$tmp/local.yml" validate
assert_eq "unknown stance refused" 1 "$rc"
reg "$GOOD"

# Comments and blank lines are ignored; no registry configured is exit 3.
reg '# a comment' '' "$GOOD"
run none "$tmp/local.yml" validate
assert_eq "comments and blanks ignored" 0 "$rc"
printf 'unrelated_key: 1\n' >"$tmp/none.yml"
run none "$tmp/none.yml" validate
assert_eq "no registry configured is exit 3" 3 "$rc"
conf "$tmp/missing.txt"
run none "$tmp/local.yml" validate
assert_eq "missing registry file is exit 3" 3 "$rc"
conf "$tmp/reg.txt"

# Usage errors.
run none "$tmp/local.yml" frobnicate
assert_eq "unknown verb is a usage error" 2 "$rc"
run none "$tmp/local.yml" get box-a 'bad field'
assert_eq "bad field name is a usage error" 2 "$rc"

# A registry in a tracked file is refused with the field named.
repo=$tmp/repo
mkdir -p "$repo/.claude"
git init -q "$repo"
printf 'remote_hosts_file: %s\n' "$tmp/reg.txt" >"$repo/.claude/planwright.yml"
run "$repo" "$tmp/none.yml" validate
assert_eq "registry key in tracked config refused" 1 "$rc"
assert_contains "tracked config names the field" remote_hosts_file "$err"
rm -f "$repo/.claude/planwright.yml"
cp "$tmp/reg.txt" "$repo/hosts.txt"
git -C "$repo" add hosts.txt
conf "$repo/hosts.txt"
run "$repo" "$tmp/local.yml" validate
assert_eq "tracked registry file refused" 1 "$rc"
assert_contains "tracked registry file says tracked" tracked "$err"
git -C "$repo" rm -q --cached hosts.txt
run "$repo" "$tmp/local.yml" validate
assert_eq "untracked registry file in a repo accepted" 0 "$rc"

# The adopter layer is not machine-local: the key there is refused.
printf 'remote_hosts_file: %s\n' "$tmp/reg.txt" >"$tmp/adopter/planwright.yml"
run none "$tmp/none.yml" validate
assert_eq "registry key in the adopter layer refused" 1 "$rc"
assert_contains "adopter layer refusal names the field" remote_hosts_file "$err"
rm -f "$tmp/adopter/planwright.yml"
conf "$tmp/reg.txt"

# A field given twice, an unknown --host and a malformed --host.
reg 'host box-a account=acct-one account=acct-two ceiling=1'
run none "$tmp/local.yml" validate
assert_eq "duplicate field refused" 1 "$rc"
assert_contains "duplicate field named" account "$err"
reg "$GOOD"
run none "$tmp/local.yml" validate --host box-missing
assert_eq "unknown --host is exit 3" 3 "$rc"
run none "$tmp/local.yml" validate --host box-a
assert_eq "known --host validates" 0 "$rc"
run none "$tmp/local.yml" validate --host -x
assert_eq "malformed --host refused" 1 "$rc"
assert_contains "malformed --host names the field" alias "$err"

# More defaults and refusals, each naming its field.
run none "$tmp/local.yml" get box-a idle
assert_eq "idle defaults to ten minutes" 10 "$out"
run none "$tmp/local.yml" get box-a compute
assert_eq "compute stance read" accepted "$out"
reg 'host box-a account=acct-one ceiling=0'
run none "$tmp/local.yml" validate
assert_eq "zero ceiling refused" 1 "$rc"
assert_contains "zero ceiling names the field" ceiling "$err"
reg 'host box-a account=acct-one ceiling=1 clone.Bad=/srv/x'
run none "$tmp/local.yml" validate
assert_eq "bad repository alias refused" 1 "$rc"
assert_contains "bad repository alias names the field" clone.Bad "$err"
reg 'host box-a account=acct-one ceiling=1 clone.demo=/a/../b'
run none "$tmp/local.yml" validate
assert_contains "dotdot clone path names the field" clone.demo "$err"
reg 'host box-a account=acct-one ceiling=1 hold=maybe'
run none "$tmp/local.yml" validate
assert_contains "bad hold flag names the field" hold "$err"
reg '  # indented comment' "$GOOD"
run none "$tmp/local.yml" validate
assert_eq "indented comment ignored" 0 "$rc"
reg "$GOOD	tab"
run none "$tmp/local.yml" validate
assert_eq "control byte refused" 1 "$rc"
reg "$GOOD"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
