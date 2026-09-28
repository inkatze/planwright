#!/bin/bash
# Tests for the spec kind of scripts/resolve-root.sh: the spec_root option
# across the overlay layers, its value forms and bad values, the root marker
# and --init, posture classification, the two views, --posture and
# --explain. Plain bash 3.2, inline asserts.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RESOLVER="$REPO_ROOT/scripts/resolve-root.sh"
SH=$(command -v dash || echo /bin/sh)
TAB=$(printf '\t')

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
  case $3 in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to contain '$2', got '$3')" >&2
      failures=$((failures + 1))
      ;;
  esac
}

assert_empty() {
  if [ -z "$2" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected nothing, got '$2')" >&2
    failures=$((failures + 1))
  fi
}

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# The core layer is a defaults file without spec_root, as the shipped one
# is; the adopter layer is a fixed directory; git discovery is fenced at
# $tmp.
mkdir -p "$tmp/home" "$tmp/adopter"
printf 'unrelated_key: 1\n' >"$tmp/core.yml"
base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    -u PLANWRIGHT_REPO_ROOT -u PLANWRIGHT_LOCAL_CONFIG HOME="$tmp/home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$tmp/core.yml" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 "$@"
}

run() {
  "$@" >"$tmp/.out" 2>"$tmp/.err"
  rc=$?
  out=$(cat "$tmp/.out")
  err=$(cat "$tmp/.err")
}

# spec <dir> [args...]: run the spec kind from <dir>.
spec() {
  sp_dir=$1
  shift
  (cd "$sp_dir" && base "$SH" "$RESOLVER" spec "$@")
}

gitq() { base git "$@" >/dev/null 2>&1; }
mkrepo() {
  mkdir -p "$1"
  gitq -C "$1" init -q
  gitq -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
}
mark() { printf 'project: fixture\nlayout: 1\n' >"$1/planwright-spec-root.yml"; }

repo=$tmp/repo
wt=$tmp/repo-wt
mkrepo "$repo"
gitq -C "$repo" worktree add -q -b wt "$wt"
mkdir -p "$repo/.claude"

# Layer files: the repo-side layers live in the primary checkout only, so a
# value read from the worktree proves config resolves from the primary.
adopter_cfg=$tmp/adopter/planwright.yml
tracked_cfg=$repo/.claude/planwright.yml
local_cfg=$repo/.claude/planwright.local.yml
clear_layers() { rm -f "$adopter_cfg" "$tracked_cfg" "$local_cfg"; }
set_layer() {
  # set_layer <file> <raw value text>
  printf 'spec_root: %s\n' "$2" >"$1"
}

# ---------------------------------------------------------------------------
# REQ-A1.1 / REQ-A1.9: unset is today's root, in each view
# ---------------------------------------------------------------------------
clear_layers
run spec "$repo"
assert_eq "unset: exit 0 from the primary" 0 "$rc"
assert_eq "unset: the primary prints <primary>/specs" "$repo/specs" "$out"
assert_empty "unset: nothing on stderr" "$err"

run spec "$wt"
assert_eq "unset: a worktree prints its own specs/" "$wt/specs" "$out"
run spec "$wt/" --primary
assert_eq "unset: --primary from a worktree prints the primary's specs/" "$repo/specs" "$out"

mkdir -p "$wt/deep/er"
run spec "$wt/deep/er"
assert_eq "unset: a subdirectory of a worktree still names the worktree's root" "$wt/specs" "$out"

run spec "$wt" --explain
assert_eq "unset: --explain names default, the path, the posture, the view" \
  "default${TAB}$wt/specs${TAB}same-repo${TAB}checkout-local" "$out"
run spec "$wt" --explain --primary
assert_eq "unset: --explain --primary names the primary view" \
  "default${TAB}$repo/specs${TAB}same-repo${TAB}primary" "$out"
run spec "$wt" --posture
assert_eq "unset: --posture prints same-repo alone" "same-repo" "$out"

# ---------------------------------------------------------------------------
# REQ-A1.2: four-layer resolution and value forms
# ---------------------------------------------------------------------------
for d in a t l; do
  mkdir -p "$tmp/roots/$d"
  mark "$tmp/roots/$d"
done

clear_layers
set_layer "$adopter_cfg" "$tmp/roots/a"
run spec "$repo" --explain
assert_eq "layers: the adopter layer alone supplies the root" \
  "adopter${TAB}$tmp/roots/a${TAB}plain${TAB}checkout-local" "$out"
set_layer "$tracked_cfg" "$tmp/roots/t"
run spec "$repo" --explain
assert_eq "layers: repo-tracked wins over adopter" \
  "repo-tracked${TAB}$tmp/roots/t${TAB}plain${TAB}checkout-local" "$out"
set_layer "$local_cfg" "$tmp/roots/l"
run spec "$wt" --explain
assert_eq "layers: machine-local wins, read from the primary even in a worktree" \
  "machine-local${TAB}$tmp/roots/l${TAB}plain${TAB}checkout-local" "$out"

clear_layers
mkdir -p "$tmp/home/holder"
mark "$tmp/home/holder"
set_layer "$local_cfg" \~/holder
run spec "$repo"
assert_eq "forms: ~/ expands against HOME" "$tmp/home/holder" "$out"

mark "$tmp/home"
set_layer "$local_cfg" \~
run spec "$repo"
assert_eq "forms: ~ alone is HOME" "$tmp/home" "$out"
rm -f "$tmp/home/planwright-spec-root.yml"

set_layer "$local_cfg" \~root/specs
run spec "$repo"
assert_eq "forms: a ~user form is refused (exit)" 5 "$rc"
assert_empty "forms: a refused ~user form prints no root" "$out"
assert_contains "forms: the ~user refusal names the form" "~user" "$err"

set_layer "$local_cfg" '"  '"$tmp/roots/l"'  "'
run spec "$repo"
assert_eq "forms: surrounding whitespace is trimmed" "$tmp/roots/l" "$out"

set_layer "$local_cfg" "$tmp/roots/l/"
run spec "$repo"
assert_eq "forms: a trailing slash is canonicalized away" "$tmp/roots/l" "$out"

mkdir -p "$repo/docs/specs"
mark "$repo/docs/specs"
set_layer "$local_cfg" "docs/specs"
run spec "$repo"
assert_eq "forms: a relative value resolves against the primary checkout" \
  "$repo/docs/specs" "$out"

ln -s "$tmp/roots/l" "$tmp/roots-link"
set_layer "$local_cfg" "$tmp/roots-link"
run spec "$repo"
assert_eq "forms: a symlinked value prints its canonical target" "$tmp/roots/l" "$out"

# ---------------------------------------------------------------------------
# REQ-A1.3: empty values and bad values
# ---------------------------------------------------------------------------
clear_layers
set_layer "$tracked_cfg" "$tmp/roots/t"
set_layer "$local_cfg" ""
run spec "$repo" --explain
assert_eq "empty: an empty machine-local value over repo-tracked reaches the default" \
  "default${TAB}$repo/specs${TAB}same-repo${TAB}checkout-local" "$out"
assert_empty "empty: cancelling a value warns nothing" "$err"

clear_layers
set_layer "$tracked_cfg" ""
run spec "$repo"
assert_eq "empty: an empty value everywhere is the default" "$repo/specs" "$out"

touch "$tmp/afile"
for layer in adopter tracked local; do
  case $layer in
    adopter) f=$adopter_cfg name=adopter ;;
    tracked) f=$tracked_cfg name=repo-tracked ;;
    local) f=$local_cfg name=machine-local ;;
  esac
  for bad in missing file escape nomarker; do
    clear_layers
    case $bad in
      missing) set_layer "$f" "$tmp/nowhere" ;;
      file) set_layer "$f" "$tmp/afile" ;;
      escape) set_layer "$f" "../" ;;
      nomarker)
        mkdir -p "$tmp/unmarked"
        set_layer "$f" "$tmp/unmarked"
        ;;
    esac
    run spec "$repo"
    assert_eq "bad: $bad from $name is refused (exit)" 5 "$rc"
    assert_empty "bad: $bad from $name prints no root" "$out"
    assert_contains "bad: $bad from $name names the layer" "the $name layer" "$err"
  done
done

clear_layers
set_layer "$tracked_cfg" "$tmp/roots/t"
set_layer "$local_cfg" "$tmp/nowhere"
run spec "$repo"
assert_eq "bad: a refused value never falls back to a valid lower layer (exit)" 5 "$rc"
assert_empty "bad: a refused value over a valid lower layer prints no root" "$out"

clear_layers
set_layer "$local_cfg" "../repo/docs/specs"
run spec "$repo"
assert_eq "bad: a relative value that re-enters the checkout is not an escape" \
  "$repo/docs/specs" "$out"

ln -s "$tmp/roots/l" "$repo/escape-link"
set_layer "$local_cfg" "escape-link"
run spec "$repo"
assert_eq "bad: a relative symlink that escapes after canonicalization is refused" 5 "$rc"
rm -f "$repo/escape-link"

clear_layers
# shellcheck disable=SC2088 # a literal ~ is the value under test
set_layer "$local_cfg" "~/specs"
# shellcheck disable=SC2016 # the inner shell expands its own arguments
run base env -u HOME sh -c 'cd "$1" && exec "$2" "$3" spec' _ "$repo" "$SH" "$RESOLVER"
assert_eq "home: a ~/ value with HOME unset is refused" 5 "$rc"
assert_contains "home: the refusal says why" "HOME is not set" "$err"

# A relative HOME would resolve against the working directory.
mkdir -p "$repo/relhome/holder"
mark "$repo/relhome/holder"
# shellcheck disable=SC2088 # a literal ~ is the value under test
set_layer "$local_cfg" "~/holder"
# shellcheck disable=SC2016 # the inner shell expands its own arguments
run base sh -c 'cd "$1" && HOME=relhome exec "$2" "$3" spec' _ "$repo" "$SH" "$RESOLVER"
assert_eq "home: a ~/ value with a relative HOME is refused" 5 "$rc"
assert_empty "home: a relative HOME prints no root" "$out"
assert_contains "home: the refusal says HOME must be absolute" "absolute" "$err"

# A canonical path carrying a control byte or tab would break the fields.
for c in tab ctl; do
  case $c in
    tab) cdir="$tmp/with${TAB}tab" ;;
    ctl) cdir="$tmp/with$(printf '\001')ctl" ;;
  esac
  mkdir -p "$cdir"
  mark "$cdir"
  ln -s "$cdir" "$tmp/$c-link"
  set_layer "$local_cfg" "$tmp/$c-link"
  run spec "$repo" --explain
  assert_eq "path bytes: a root whose canonical path has a $c is refused" 5 "$rc"
  assert_empty "path bytes: a $c path prints nothing" "$out"
done

# A control byte is malformed text: the by-layer policy, not a refusal.
clear_layers
set_layer "$tracked_cfg" "$tmp/roots/t"
printf 'spec_root: %s\001x\n' "$tmp/roots/l" >"$local_cfg"
run spec "$repo"
assert_eq "control byte: machine-local warns and falls through (exit)" 0 "$rc"
assert_eq "control byte: machine-local falls through to repo-tracked" "$tmp/roots/t" "$out"
assert_contains "control byte: the fall-through warns" "machine-local" "$err"

clear_layers
printf 'spec_root: %s\001x\n' "$tmp/roots/a" >"$adopter_cfg"
run spec "$repo" --explain
assert_eq "control byte: adopter warns and falls through to the default" \
  "default${TAB}$repo/specs${TAB}same-repo${TAB}checkout-local" "$out"
assert_contains "control byte: the adopter fall-through warns" "adopter" "$err"

clear_layers
printf 'spec_root: %s\001x\n' "$tmp/roots/t" >"$tracked_cfg"
run spec "$repo"
assert_eq "control byte: repo-tracked hard-fails (exit)" 6 "$rc"
assert_empty "control byte: repo-tracked prints no root" "$out"
assert_contains "control byte: the repo-tracked refusal names the layer" "repo-tracked" "$err"

# ---------------------------------------------------------------------------
# REQ-A1.4: the marker, the default by resolved path, --init
# ---------------------------------------------------------------------------
clear_layers
mkdir -p "$repo/specs"
set_layer "$local_cfg" "specs"
run spec "$repo" --explain
assert_eq "marker: a value naming <primary>/specs needs no marker" \
  "machine-local${TAB}$repo/specs${TAB}same-repo${TAB}checkout-local" "$out"
set_layer "$local_cfg" "$repo/specs"
run spec "$wt" --explain
assert_eq "marker: the absolute form of the default is re-based in a worktree" \
  "machine-local${TAB}$wt/specs${TAB}same-repo${TAB}checkout-local" "$out"

run spec "$repo" --init
assert_eq "init: the default root is left alone (exit)" 0 "$rc"
assert_eq "init: the default root gains no marker" absent \
  "$(test -e "$repo/specs/planwright-spec-root.yml" && echo present || echo absent)"

mkdir -p "$repo/relocated"
set_layer "$local_cfg" "relocated"
run spec "$repo"
assert_eq "init: before --init the unmarked root is refused" 5 "$rc"
assert_contains "init: the refusal points at --init" "--init" "$err"
run spec "$repo" --init
assert_eq "init: --init succeeds (exit)" 0 "$rc"
assert_eq "init: --init prints the root" "$repo/relocated" "$out"
assert_contains "init: the marker names the project" "project: repo" \
  "$(cat "$repo/relocated/planwright-spec-root.yml")"
assert_contains "init: the marker carries the layout" "layout: 1" \
  "$(cat "$repo/relocated/planwright-spec-root.yml")"
run spec "$repo"
assert_eq "init: after --init the root resolves" "$repo/relocated" "$out"

# REQ-A1.5: the local-only entries are ignored wherever git sees the root.
mkdir -p "$repo/relocated/_pending" "$repo/relocated/feat/.orchestrate"
for f in _pending/notes.md feat/.orchestrate.lock feat/.tasks-pr-sync.tmp feat/.orchestrate/m; do
  touch "$repo/relocated/$f"
  base git -C "$repo" check-ignore -q "relocated/$f"
  assert_eq "init: git ignores relocated/$f" 0 "$?"
done
touch "$repo/relocated/_pending/other.md"
base git -C "$repo" check-ignore -q "relocated/_pending/other.md"
assert_eq "init: other _pending entries stay tracked" 1 "$?"

run spec "$repo" --init
assert_eq "init: a second --init is a no-op (exit)" 0 "$rc"
assert_eq "init: a second --init adds no duplicate rules" 1 \
  "$(grep -c -Fx /_pending/notes.md "$repo/relocated/.gitignore")"

set_layer "$local_cfg" "$tmp/nowhere"
run spec "$repo" --init
assert_eq "init: --init never creates the directory" 5 "$rc"
assert_eq "init: the missing directory is still missing" absent \
  "$(test -e "$tmp/nowhere" && echo present || echo absent)"

mkdir -p "$tmp/plaindir"
set_layer "$local_cfg" "$tmp/plaindir"
run spec "$repo" --init
assert_eq "init: a plain directory is initialized (exit)" 0 "$rc"
assert_eq "init: a plain directory gets no ignore file" absent \
  "$(test -e "$tmp/plaindir/.gitignore" && echo present || echo absent)"

mkdir -p "$repo/nonl"
printf 'keep-me' >"$repo/nonl/.gitignore"
set_layer "$local_cfg" "nonl"
run spec "$repo" --init
assert_eq "init: an ignore file without a final newline (exit)" 0 "$rc"
assert_eq "init: the existing last rule survives" 1 "$(grep -c -Fx keep-me "$repo/nonl/.gitignore")"
mkdir -p "$repo/nonl/_pending"
touch "$repo/nonl/_pending/notes.md"
base git -C "$repo" check-ignore -q "nonl/_pending/notes.md"
assert_eq "init: the notes rule still applies after a newline-less file" 0 "$?"

mkdir -p "$repo/badignore/.gitignore"
set_layer "$local_cfg" "badignore"
run spec "$repo" --init
assert_eq "init: an unwritable ignore file refuses (exit)" 5 "$rc"
assert_eq "init: a failed ignore write leaves no marker" absent \
  "$(test -e "$repo/badignore/planwright-spec-root.yml" && echo present || echo absent)"
assert_eq "init: the failed write leaks no shell error" 0 \
  "$(printf '%s\n' "$err" | grep -c 'Is a directory')"

mkdir -p "$repo/dirmarker/planwright-spec-root.yml"
set_layer "$local_cfg" "dirmarker"
run spec "$repo" --init
assert_eq "init: a marker path that is not a file is refused" 5 "$rc"

mkdir -p "$repo/symmarker"
ln -s "$tmp/marker-victim" "$repo/symmarker/planwright-spec-root.yml"
set_layer "$local_cfg" "symmarker"
run spec "$repo" --init
assert_eq "init: a dangling symlink at the marker path is refused" 5 "$rc"
assert_eq "init: the write never follows the planted symlink" absent \
  "$(test -e "$tmp/marker-victim" && echo present || echo absent)"
assert_contains "init: the refusal names the symlink" "symlink" "$err"

mkdir -p "$repo/tmpcheck"
set_layer "$local_cfg" "tmpcheck"
run spec "$repo" --init
assert_eq "init: a fresh root is initialized (exit)" 0 "$rc"
assert_empty "init: no temporary marker file is left behind" \
  "$(find "$repo/tmpcheck" -name '.planwright-spec-root.yml*')"

mkdir -p "$repo/kept"
printf 'project: other\nlayout: 1\n' >"$repo/kept/planwright-spec-root.yml"
set_layer "$local_cfg" "kept"
run spec "$repo" --init
assert_eq "init: an existing valid marker is accepted (exit)" 0 "$rc"
assert_contains "init: an existing marker is never rewritten" "project: other" \
  "$(cat "$repo/kept/planwright-spec-root.yml")"

mkdir -p "$repo/symignore"
printf 'victim-rule\n' >"$tmp/ignore-victim"
ln -s "$tmp/ignore-victim" "$repo/symignore/.gitignore"
set_layer "$local_cfg" "symignore"
run spec "$repo" --init
assert_eq "init: a symlinked ignore file is refused" 5 "$rc"
assert_eq "init: the symlink's target is untouched" "victim-rule" "$(cat "$tmp/ignore-victim")"
assert_eq "init: a refused ignore file leaves no marker" absent \
  "$(test -e "$repo/symignore/planwright-spec-root.yml" && echo present || echo absent)"

# The marker's fields are validated, not just its existence.
mkdir -p "$repo/checked"
set_layer "$local_cfg" "checked"
cm="$repo/checked/planwright-spec-root.yml"
for body in 'project: Fixture\nlayout: 1\n' 'project: -x\nlayout: 1\n' \
  'project: a/b\nlayout: 1\n' 'project:\nlayout: 1\n' 'layout: 1\n' \
  'project: fixture\nlayout: 2\n' 'project: fixture\n' \
  "project: $(printf '%065d' 0)\nlayout: 1\n"; do
  # shellcheck disable=SC2059 # the body is a format with \n escapes
  printf "$body" >"$cm"
  run spec "$repo"
  # shellcheck disable=SC2059 # the body is a format with \n escapes
  assert_eq "marker: '$(printf "$body" | tr '\n' ' ')' is refused (exit)" 5 "$rc"
  assert_empty "marker: an invalid marker prints no root" "$out"
  run spec "$repo" --init
  assert_eq "marker: --init refuses an invalid existing marker too" 5 "$rc"
done
printf 'project: fixture-2\nlayout: 1\n' >"$cm"
run spec "$repo"
assert_eq "marker: a valid marker resolves" "$repo/checked" "$out"
rm -f "$cm"
printf 'project: fixture\nlayout: 1\n' >"$tmp/marker-real"
ln -s "$tmp/marker-real" "$cm"
run spec "$repo"
assert_eq "marker: a symlinked marker is refused" 5 "$rc"
assert_contains "marker: the symlink refusal says so" "symlink" "$err"

# ---------------------------------------------------------------------------
# REQ-E1.1: posture classification
# ---------------------------------------------------------------------------
clear_layers
set_layer "$local_cfg" "relocated"
run spec "$repo" --posture
assert_eq "posture: an in-repo root is same-repo" same-repo "$out"

printf 'relocated/\n' >>"$repo/.git/info/exclude"
run spec "$repo" --posture
assert_eq "posture: a gitignored in-repo root is still same-repo" same-repo "$out"

mkdir -p "$wt/wtroot"
mark "$wt/wtroot"
set_layer "$local_cfg" "$wt/wtroot"
run spec "$repo" --posture
assert_eq "posture: a root in another worktree of the repository is same-repo" same-repo "$out"
run spec "$repo"
assert_eq "posture: a root in another worktree is not re-based" "$wt/wtroot" "$out"

mkrepo "$tmp/holder"
mkdir -p "$tmp/holder/work"
mark "$tmp/holder/work"
set_layer "$local_cfg" "$tmp/holder/work"
run spec "$wt" --posture
assert_eq "posture: a root in a second repository is separate-repo" separate-repo "$out"
run spec "$wt" --explain
assert_eq "posture: a holder root is the same in both views" \
  "machine-local${TAB}$tmp/holder/work${TAB}separate-repo${TAB}checkout-local" "$out"
run spec "$wt" --explain --primary
assert_eq "posture: a holder root is the same in the primary view" \
  "machine-local${TAB}$tmp/holder/work${TAB}separate-repo${TAB}primary" "$out"

mkdir -p "$tmp/holder/fresh/_pending"
set_layer "$local_cfg" "$tmp/holder/fresh"
run spec "$repo" --init
assert_eq "posture: a holder root is initialized (exit)" 0 "$rc"
touch "$tmp/holder/fresh/_pending/notes.md"
base git -C "$tmp/holder" check-ignore -q "fresh/_pending/notes.md"
assert_eq "posture: --init ignores the notes file inside the holder" 0 "$?"

set_layer "$local_cfg" "$tmp/plaindir"
run spec "$repo" --posture
assert_eq "posture: a directory in no repository is plain" plain "$out"
run spec "$repo"
assert_eq "posture: the default output stays the bare path" "$tmp/plaindir" "$out"

# ---------------------------------------------------------------------------
# REQ-A1.9: the two views of an in-repo root
# ---------------------------------------------------------------------------
clear_layers
mkdir -p "$wt/relocated"
set_layer "$local_cfg" "relocated"
run spec "$wt"
assert_eq "views: a relative value is re-based onto the worktree" "$wt/relocated" "$out"
run spec "$wt" --primary
assert_eq "views: --primary keeps the primary's copy" "$repo/relocated" "$out"
set_layer "$local_cfg" "$repo/relocated"
run spec "$wt"
assert_eq "views: an absolute in-repo value is re-based onto the worktree" "$wt/relocated" "$out"
run spec "$wt" --primary
assert_eq "views: --primary of an absolute in-repo value" "$repo/relocated" "$out"

# A specs/ that is a symlink out of the checkout is still the default root,
# whether the value names it or is unset.
symrepo=$tmp/symrepo
mkrepo "$symrepo"
gitq -C "$symrepo" worktree add -q -b wt "$tmp/symrepo-wt"
mkdir -p "$tmp/outside" "$symrepo/.claude"
ln -s "$tmp/outside" "$symrepo/specs"
run spec "$tmp/symrepo-wt" --explain
assert_eq "views: unset, a symlinked specs/ is the default re-based" \
  "default${TAB}$tmp/symrepo-wt/specs${TAB}same-repo${TAB}checkout-local" "$out"
for v in specs "$tmp/outside"; do
  set_layer "$symrepo/.claude/planwright.local.yml" "$v"
  run spec "$tmp/symrepo-wt"
  assert_eq "views: '$v' through a symlinked specs/ resolves like unset" "$tmp/symrepo-wt/specs" "$out"
done

# ---------------------------------------------------------------------------
# usage and no-repository cases
# ---------------------------------------------------------------------------
mkdir -p "$tmp/norepo"
run spec "$tmp/norepo"
assert_eq "no repo: the spec kind exits 3 outside a repository" 3 "$rc"
assert_empty "no repo: nothing is printed" "$out"
run spec "$repo" --checkout
assert_eq "usage: spec takes no --checkout" 2 "$rc"
run base "$SH" "$RESOLVER" repo --primary --posture
assert_eq "usage: --posture belongs to the spec kind" 2 "$rc"
run base "$SH" "$RESOLVER" install --init
assert_eq "usage: --init belongs to the spec kind" 2 "$rc"

# ---------------------------------------------------------------------------
# REQ-H1.3: the option ships dark
# ---------------------------------------------------------------------------
grep -q '^spec_root:' "$REPO_ROOT/config/defaults.yml"
assert_eq "dark: config/defaults.yml carries no spec_root key" 1 "$?"
# shellcheck disable=SC2016 # the backticks are literal markdown
grep -q '^| `spec_root` |' "$REPO_ROOT/docs/options-reference.md"
assert_eq "dark: the options reference documents spec_root" 0 "$?"
run "$REPO_ROOT/scripts/check-options-reference.sh"
assert_eq "dark: the options-reference check passes with the key absent" 0 "$rc"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all resolve-root spec tests passed"
