#!/bin/bash
# The observation store follows the spec root, and named targets route a
# fragment to another root on the same machine (custom-spec-location D-17,
# D-18):
#   REQ-F1.1 each observation script, with the root relocated and no
#            --obs-dir, works under <root>/_observations of the checkout-local
#            view; carry in plain is a no-op that says so.
#   REQ-F1.2 obs-record --target lands a UID-named fragment in the target
#            root's entries/; an unknown alias, a marker-less non-default
#            target, and a target that is not an absolute or ~/ path are
#            refused; the default root of a git checkout is accepted by shape.
#   REQ-F1.3 a --target fragment carrying an absolute path, a ~ path, or a
#            hostname is refused naming the screen, nothing written; one
#            naming a repo-relative file is written.
#   REQ-F1.4 no routing script invokes gh, git push, or a network client.
#   REQ-F1.5 the duplicate-UID refusal holds within one accumulator and not
#            across two; the carry runs in a holder.
#   REQ-A1.5 the reserved accumulator is a child of the checkout-local view.
#   REQ-H1.3 observation_targets ships empty and spec_root ships absent.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$REPO_ROOT/scripts"
TAB=$(printf '\t')

failures=0
ok() { echo "ok: $1"; }
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/obs-store-root.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

REAL_GIT=$(command -v git)
inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
mkdir -p "$tmp/home" "$tmp/adopter"
hermetic() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    HOME="$tmp/home" GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" PLANWRIGHT_ROOT="$REPO_ROOT" "$@"
}
gitq() { hermetic git "$@" >/dev/null 2>&1; }
# at <dir> <cmd...> — run a command from <dir>; sets out (stdout), err, rc.
at() {
  i_dir=$1
  shift
  out=$(cd "$i_dir" && hermetic "$@" 2>"$tmp/.err")
  rc=$?
  err=$(cat "$tmp/.err")
}
count() { find "$1" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }
# make_od <dir> <uid> — an od stub minting a fixed UID.
make_od() {
  mkdir -p "$1"
  printf '#!/bin/sh\nprintf " %s %s %s %s\\n"\n' "${2%??????}" \
    "$(printf '%s' "$2" | cut -c3-4)" "$(printf '%s' "$2" | cut -c5-6)" \
    "$(printf '%s' "$2" | cut -c7-8)" >"$1/od"
  chmod +x "$1/od"
}
new_repo() {
  gitq -c init.defaultBranch=main init -q "$1"
  printf 'x\n' >"$1/file"
  gitq -C "$1" add -A && gitq -C "$1" commit -q -m init
}
# rec: obs-record with a fixed slug and scope, as a file so env can run it.
rec=$tmp/rec
printf '#!/bin/sh\nexec "%s/obs-record.sh" --slug topic --scope fixture "$@"\n' "$S" >"$rec"
chmod +x "$rec"

# --- REQ-F1.1, REQ-A1.5: same-repo, relocated inside the repository --------

w=$tmp/work
new_repo "$w"
mkdir -p "$w/store" "$w/.claude"
printf 'spec_root: store\n' >"$w/.claude/planwright.local.yml"
at "$w" "$S/resolve-root.sh" spec --init
[ "$rc" -eq 0 ] || fail "fixture: --init on the in-repo root failed: $err"
gitq -C "$w" add -A && gitq -C "$w" commit -q -m marker
gitq -C "$w" worktree add -q "$w/.claude/worktrees/wt" -b wt
wt=$w/.claude/worktrees/wt
mkdir -p "$wt/.claude"
cp "$w/.claude/planwright.local.yml" "$wt/.claude/"

at "$w" "$rec" --text 'a relocated observation'
case $out in
  store/_observations/entries/*-topic-*.md) ok "record: the store is <root>/_observations, in the caller's frame" ;;
  *) fail "record from the primary (rc=$rc): $out $err" ;;
esac
[ "$(count "$w/store/_observations/entries")" -eq 1 ] || fail "record: no fragment under the relocated store"
[ ! -e "$w/specs" ] || fail "record: the old default specs/ was created"

at "$w" "$S/check-obs.sh"
if [ "$rc" -eq 0 ]; then
  ok "check-obs: validates the relocated store"
else
  fail "check-obs (rc=$rc): $err"
fi
at "$w" "$S/obs-render.sh"
case $out in
  *"[fixture] a relocated observation"*) ok "render: reads the relocated store" ;;
  *) fail "render (rc=$rc): $out $err" ;;
esac
uid=$(find "$w/store/_observations/entries" -name '*.md' | sed 's/.*-\([0-9a-f]\{8\}\)\.md$/\1/')
at "$w" "$S/obs-consume.sh" --uid "$uid" --spec demo --today 2026-01-01
if [ "$rc" -eq 0 ] && [ "$(count "$w/store/_observations/archive")" -eq 1 ]; then
  ok "consume: archives within the relocated store"
else
  fail "consume (rc=$rc): $err"
fi
# A planted bad file under the relocated store is what check-obs must see.
: >"$w/store/_observations/entries/not-a-fragment.md"
at "$w" "$S/check-obs.sh"
if [ "$rc" -eq 1 ]; then
  ok "check-obs: flags a bad file in the relocated store"
else
  fail "check-obs missed a bad file (rc=$rc)"
fi
rm -f "$w/store/_observations/entries/not-a-fragment.md"

# A relocated in-repo root carries from its own path in the work repository.
at "$w" "$rec" --text 'to carry'
gitq -C "$w" checkout -q -b notes
gitq -C "$w" add -A && gitq -C "$w" commit -q -m notes
at "$w" "$S/observation-carry.sh" --dry-run "$w"
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx "stranded${TAB}1"; then
  ok "carry: --dry-run counts a relocated in-repo root's stranded fragment"
else
  fail "carry dry run on an in-repo root (rc=$rc): $out $err"
fi

primary_before=$(count "$w/store/_observations/entries")
at "$wt" "$rec" --text 'from a worktree'
if [ "$rc" -eq 0 ] && [ "$(count "$wt/store/_observations/entries")" -eq 1 ] \
  && [ "$(count "$w/store/_observations/entries")" -eq "$primary_before" ]; then
  ok "record: a worktree writes its own checkout-local copy"
else
  fail "record from a worktree (rc=$rc): $out $err"
fi

# An ignored in-repo root is absent from a fresh worktree; a fragment written
# there would go with the worktree.
g=$tmp/ignored
new_repo "$g"
mkdir -p "$g/notes" "$g/.claude"
printf 'notes/\n' >>"$g/.git/info/exclude"
printf 'spec_root: notes\n' >"$g/.claude/planwright.local.yml"
at "$g" "$S/resolve-root.sh" spec --init
[ "$rc" -eq 0 ] || fail "fixture: --init on the ignored root failed: $err"
gitq -C "$g" worktree add -q "$tmp/ignored-wt" -b wt
mkdir -p "$tmp/ignored-wt/.claude"
cp "$g/.claude/planwright.local.yml" "$tmp/ignored-wt/.claude/"
at "$tmp/ignored-wt" "$rec" --text 'would be stranded'
if [ "$rc" -eq 1 ] && [ ! -e "$tmp/ignored-wt/notes" ]; then
  case $err in
    *"not present in this checkout"*) ok "record: a root missing from the checkout is refused, not created" ;;
    *) fail "record into a missing root refused without naming why: $err" ;;
  esac
else
  fail "record into a root missing from the worktree (rc=$rc): $out $err"
fi

# A root whose relative path opens with a hyphen is still a usable store.
hy=$tmp/hyphen
new_repo "$hy"
mkdir -p "$hy/-notes" "$hy/.claude"
printf 'spec_root: -notes\n' >"$hy/.claude/planwright.local.yml"
at "$hy" "$S/resolve-root.sh" spec --init
[ "$rc" -eq 0 ] || fail "fixture: --init on the hyphen-led root failed: $err"
at "$hy" "$rec" --text 'a hyphen-led root'
if [ "$rc" -eq 0 ] && [ "$(count "$hy/-notes/_observations/entries")" -eq 1 ]; then
  ok "record: a hyphen-led relative root takes the fragment"
else
  fail "record into a hyphen-led root (rc=$rc): $out $err"
fi
for s in check-obs.sh obs-render.sh; do
  at "$hy" "$S/$s"
  if [ "$rc" -eq 0 ]; then
    ok "$s: reads a hyphen-led relative root"
  else
    fail "$s on a hyphen-led root (rc=$rc): $err"
  fi
done

# The default root: from the top, the paths printed are the ones they were.
d=$tmp/default
new_repo "$d"
at "$d" "$rec" --text 'default store'
case $out in
  specs/_observations/entries/*-topic-*.md) ok "record: the default root prints the pre-feature relative path" ;;
  *) fail "record on the default root (rc=$rc): $out $err" ;;
esac
mkdir -p "$d/sub"
at "$d/sub" "$rec" --text 'from a subdirectory'
if [ "$rc" -eq 0 ] && [ "$(count "$d/specs/_observations/entries")" -eq 2 ] && [ ! -e "$d/sub/specs" ]; then
  ok "record: a subdirectory writes the repository's store, not its own"
else
  fail "record from a subdirectory (rc=$rc): $out $err"
fi

# No root resolves: refused, nothing composed.
n=$tmp/norepo
mkdir -p "$n"
at "$n" "$rec" --text 'nowhere'
if [ "$rc" -ne 0 ] && [ ! -e "$n/specs" ]; then
  ok "record: outside any repository it refuses rather than compose a path"
else
  fail "record outside a repository (rc=$rc): $out"
fi
for s in check-obs.sh obs-render.sh; do
  at "$n" "$S/$s"
  if [ "$rc" -eq 2 ]; then
    ok "$s: an unresolved root is an error"
  else
    fail "$s outside a repository (rc=$rc)"
  fi
done
b=$tmp/broken
new_repo "$b"
mkdir -p "$b/.claude"
printf 'spec_root: %s\n' "$tmp/missing-root" >"$b/.claude/planwright.local.yml"
at "$b" "$rec" --text 'refused root'
if [ "$rc" -ne 0 ] && [ ! -e "$b/specs" ]; then
  ok "record: a refused spec_root never falls back to the default"
else
  fail "record with a refused spec_root (rc=$rc): $out"
fi
at "$b" "$S/observation-carry.sh" --dry-run "$b"
if [ "$rc" -eq 2 ]; then
  ok "carry: a refused spec_root is an error, not a carry"
else
  fail "carry with a refused spec_root (rc=$rc): $out"
fi

# --- REQ-F1.1, REQ-F1.5: separate-repo (a holder) ---------------------------

h=$tmp/holder
new_repo "$h"
gitq clone -q --bare "$h" "$tmp/holder-origin.git"
gitq -C "$h" remote add origin "$tmp/holder-origin.git"
gitq -C "$h" fetch -q origin
z=$h/proj
hw=$tmp/hwork
new_repo "$hw"
mkdir -p "$z" "$hw/.claude"
printf 'spec_root: %s\n' "$z" >"$hw/.claude/planwright.local.yml"
at "$hw" "$S/resolve-root.sh" spec --init
[ "$rc" -eq 0 ] || fail "fixture: --init on the holder root failed: $err"
at "$hw" "$rec" --text 'into the holder'
if [ "$rc" -eq 0 ] && [ "$out" = "$(find "$z/_observations/entries" -name '*.md')" ]; then
  ok "record: a holder root takes the fragment, named by absolute path"
else
  fail "record into a holder (rc=$rc): $out $err"
fi
[ ! -e "$hw/specs" ] || fail "record: the holder write touched the work repository"

gitq -C "$h" checkout -q -b notes
gitq -C "$h" add -A && gitq -C "$h" commit -q -m notes
at "$hw" "$S/observation-carry.sh" --dry-run "$hw"
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx "stranded${TAB}1"; then
  ok "carry: --dry-run counts the holder's stranded fragment"
else
  fail "carry dry run in a holder (rc=$rc): $out $err"
fi
# A git hook in the work repository exports GIT_DIR; the holder is still the
# holder.
at "$hw" env GIT_DIR="$hw/.git" GIT_WORK_TREE="$hw" "$S/observation-carry.sh" --dry-run "$hw"
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx "stranded${TAB}1"; then
  ok "carry: an inherited GIT_DIR does not redirect the holder carry"
else
  fail "carry dry run in a holder under GIT_DIR (rc=$rc): $out $err"
fi
mkdir -p "$tmp/ghbin" "$tmp/ghstate"
cat >"$tmp/ghbin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "pr list") exit 0 ;;
  "pr create") pwd -P >"$GH_STATE/create-cwd"; echo https://example.invalid/pr/1 ;;
esac
EOF
chmod +x "$tmp/ghbin/gh"
at "$hw" env GH_STATE="$tmp/ghstate" PATH="$tmp/ghbin:$PATH" \
  PLANWRIGHT_OBSERVATION_CARRY_STATE_DIR="$tmp/carry-state" "$S/observation-carry.sh" "$hw"
carried=$(hermetic git -C "$tmp/holder-origin.git" ls-tree -r --name-only planwright/chore/observations -- proj/_observations/entries 2>/dev/null)
if [ "$rc" -eq 0 ] && [ -n "$carried" ] && [ "$(cat "$tmp/ghstate/create-cwd" 2>/dev/null)" = "$h" ]; then
  ok "carry: pushes the holder's fragment to the holder's chore branch and opens its PR there"
else
  fail "carry in a holder (rc=$rc): $out $err"
fi
if [ -z "$(hermetic git -C "$hw" for-each-ref --format='%(refname)' refs/heads/planwright)" ]; then
  ok "carry: the work repository gains no branch"
else
  fail "carry: a branch appeared in the work repository"
fi
at "$hw" env GH_STATE="$tmp/ghstate" PATH="$tmp/ghbin:$PATH" \
  PLANWRIGHT_OBSERVATION_CARRY_STATE_DIR="$tmp/carry-state" "$S/observation-carry.sh" "$hw"
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -qx "carry${TAB}noop"; then
  ok "carry: a repeat run in the holder carries nothing"
else
  fail "carry repeat in a holder (rc=$rc): $out $err"
fi
at "$hw" "$rec" --text 'a second holder note'
gitq -C "$h" add -A && gitq -C "$h" commit -q -m notes2
at "$hw" env GH_STATE="$tmp/ghstate" PATH="$tmp/ghbin:$PATH" "$S/observation-carry.sh" "$hw"
if [ "$rc" -eq 0 ] && [ -d "$h/.claude/orchestrate.local" ] && [ ! -e "$hw/.claude/orchestrate.local" ]; then
  ok "carry: the holder carry takes its lock in the holder"
else
  fail "carry lock in a holder (rc=$rc): $out $err"
fi

# Per-accumulator identity: one UID, two accumulators.
make_od "$tmp/odfix" abcd1234
at "$w" env PATH="$tmp/odfix:$PATH" "$S/obs-record.sh" --slug same --scope fixture --text 'one'
r1=$rc
at "$hw" env PATH="$tmp/odfix:$PATH" "$S/obs-record.sh" --slug same --scope fixture --text 'two'
r2=$rc
if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ]; then
  ok "identity: the same UID is free in a second accumulator"
else
  fail "identity: one UID in two accumulators (rc=$r1/$r2)"
fi
at "$w" env PATH="$tmp/odfix:$PATH" "$S/obs-record.sh" --slug again --scope fixture --text 'three'
if [ "$rc" -eq 3 ]; then
  ok "identity: a UID already in the accumulator is refused there"
else
  fail "identity: duplicate within one accumulator (rc=$rc)"
fi
at "$w" "$S/check-obs.sh"
r1=$rc
at "$hw" "$S/check-obs.sh"
r2=$rc
if [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ]; then
  ok "identity: each accumulator passes check-obs"
else
  fail "identity: check-obs (rc=$r1/$r2)"
fi

# --- REQ-F1.1: plain ---------------------------------------------------------

p=$tmp/plain-root
pw=$tmp/pwork
new_repo "$pw"
mkdir -p "$p" "$pw/.claude"
printf 'spec_root: %s\n' "$p" >"$pw/.claude/planwright.local.yml"
at "$pw" "$S/resolve-root.sh" spec --init
at "$pw" "$rec" --text 'into a plain store'
if [ "$rc" -eq 0 ] && [ "$(count "$p/_observations/entries")" -eq 1 ]; then
  ok "record: a plain root takes the fragment"
else
  fail "record into plain (rc=$rc): $err"
fi
at "$pw" "$S/observation-carry.sh" "$pw"
if [ "$rc" -eq 0 ] && [ "$out" = "carry${TAB}noop
stranded${TAB}0" ]; then
  case $err in
    *plain*) ok "carry: a no-op in plain, saying so" ;;
    *) fail "carry in plain did not name the no-op: $err" ;;
  esac
else
  fail "carry in plain (rc=$rc): $out $err"
fi

# --- REQ-F1.2: named targets -------------------------------------------------

o=$tmp/other
new_repo "$o"
mkdir -p "$o/specs"
nm=$tmp/nomarker
mkdir -p "$nm" "$tmp/home/tgt/specs"
new_repo "$tmp/home/tgt"
mkdir -p "$tmp/home/tgt/specs"
t=$tmp/twork
new_repo "$t"
mkdir -p "$t/.claude"
printf 'observation_targets: {other: %s, holder: %s, bare: %s, gone: %s/missing, rel: other/specs, tilde: ~/tgt/specs}\n' \
  "$o/specs" "$z" "$nm" "$tmp" >"$t/.claude/planwright.local.yml"

at "$t" "$rec" --target other --text 'routed to another root'
if [ "$rc" -eq 0 ] && [ "$(count "$o/specs/_observations/entries")" -eq 1 ] \
  && [ "$out" = "$(find "$o/specs/_observations/entries" -name '*.md')" ]; then
  case ${out##*/} in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-topic-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f].md)
      ok "target: the default root of a git checkout takes a UID-named fragment"
      ;;
    *) fail "target: unexpected fragment name $out" ;;
  esac
else
  fail "target other (rc=$rc): $out $err"
fi
[ ! -e "$t/specs" ] || fail "target: the routed write touched the caller's store"
at "$t" env GIT_OBJECT_DIRECTORY="$tmp/no-objects" "$rec" --target other --text 'under a stray object directory'
if [ "$rc" -eq 0 ]; then
  ok "target: the shape check ignores an inherited GIT_OBJECT_DIRECTORY"
else
  fail "target under GIT_OBJECT_DIRECTORY (rc=$rc): $err"
fi
at "$o" "$S/check-obs.sh"
if [ "$rc" -eq 0 ]; then
  ok "target: check-obs passes in the target root"
else
  fail "target: check-obs in the target (rc=$rc): $err"
fi
at "$t" "$rec" --target holder --text 'routed to a holder'
if [ "$rc" -eq 0 ]; then
  ok "target: a marker-bearing root is accepted"
else
  fail "target holder (rc=$rc): $err"
fi
at "$t" "$rec" --target tilde --text 'routed through home'
if [ "$rc" -eq 0 ] && [ "$(count "$tmp/home/tgt/specs/_observations/entries")" -eq 1 ]; then
  ok "target: a ~/ value expands against HOME"
else
  fail "target tilde (rc=$rc): $err"
fi
# refused <label> <expected stderr fragment> <args...> — obs-record from $t
# exits 1 naming the expected reason.
refused() {
  r_label=$1
  r_want=$2
  shift 2
  at "$t" "$@"
  case $rc:$err in
    1:*"$r_want"*) ok "target: $r_label is refused" ;;
    *) fail "target: $r_label (rc=$rc): $err" ;;
  esac
}
mkdir -p "$t/other/specs" "$tmp/loose/specs" "$o/sub/specs"
long=$(printf '%065d' 0 | tr 0 a)
printf 'observation_targets: {other: %s, holder: %s, bare: %s, gone: %s/missing, rel: other/specs, tilde: ~/tgt/specs, tu: ~alice/specs, loose: %s/loose/specs, sub: %s/sub/specs}\n' \
  "$o/specs" "$z" "$nm" "$tmp" "$tmp" "$o" >"$t/.claude/planwright.local.yml"
refused "an unknown alias" "no observation target is configured" "$rec" --target nosuch --text x
refused "an alias outside the grammar" "identifier grammar" "$rec" --target Bad --text x
refused "an alias over 64 characters" "at most 64" "$rec" --target "$long" --text x
refused "a marker-less directory" "neither a marked spec root" "$rec" --target bare --text x
refused "a specs directory outside any repository" "neither a marked spec root" "$rec" --target loose --text x
refused "a specs directory below a toplevel" "neither a marked spec root" "$rec" --target sub --text x
refused "a missing directory" "not an existing directory" "$rec" --target gone --text x
refused "a relative path" "never a relative one" "$rec" --target rel --text x
refused "a ~user path" "never ~user" "$rec" --target tu --text x
refused "a ~ path with a relative HOME" "HOME is not absolute" env HOME=relhome "$rec" --target tilde --text x
for d in "$nm" "$tmp/loose/specs" "$o/sub/specs" "$t/other/specs"; do
  [ ! -e "$d/_observations" ] || fail "target: a refused target was written into: $d"
done
at "$t" "$rec" --target other --obs-dir "$tmp/x" --text 'both'
if [ "$rc" -eq 2 ]; then
  ok "target: --target with --obs-dir is a usage error"
else
  fail "target with --obs-dir (rc=$rc)"
fi
at "$t" "$rec" --text 'no alias' --target
if [ "$rc" -eq 2 ]; then
  ok "target: --target without its alias is a usage error"
else
  fail "target without an alias (rc=$rc)"
fi
for m in "{other: $o/specs, other: $o/specs}" "{other $o/specs}" "{other: \"$o/specs\"}" \
  "{other: {a: b}}" "{, other: $o/specs}" "{other: $o/specs,}" "{a: x,, other: $o/specs}" \
  "{other: }" "$o/specs"; do
  printf 'observation_targets: %s\n' "$m" >"$t/.claude/planwright.local.yml"
  refused "the malformed map '$m'" "machine-local layer is not a flat inline" "$rec" --target other --text x
done
printf 'observation_targets: {}\n' >"$t/.claude/planwright.local.yml"
refused "an alias the empty map lacks" "no observation target is configured" "$rec" --target other --text x
# A clean configured path can still canonicalize, through a symlink, onto one
# carrying a tab.
ctl="$tmp/ctl${TAB}repo"
new_repo "$ctl"
mkdir -p "$ctl/specs"
ln -s "$ctl/specs" "$tmp/ctl-link"
printf 'observation_targets: {ctl: %s}\n' "$tmp/ctl-link" >"$t/.claude/planwright.local.yml"
refused "a target whose canonical path carries a tab" "control byte" "$rec" --target ctl --text x
[ ! -e "$ctl/specs/_observations" ] || fail "target: the tab-bearing canonical target was written into"
# A checkout's specs/ may be a symlink out of it; its own resolver takes that
# as the default root, and so does the shape check.
new_repo "$tmp/symrepo"
mkdir -p "$tmp/sym-store"
ln -s "$tmp/sym-store" "$tmp/symrepo/specs"
printf 'observation_targets: {sym: %s}\n' "$tmp/symrepo/specs" >"$t/.claude/planwright.local.yml"
at "$t" "$rec" --target sym --text 'through a symlinked specs'
if [ "$rc" -eq 0 ] && [ "$(count "$tmp/sym-store/_observations/entries")" -eq 1 ]; then
  ok "target: a checkout whose specs/ is a symlink is accepted by shape"
else
  fail "target through a symlinked specs (rc=$rc): $out $err"
fi
printf 'observation_targets: {other: %s}\n' "$o/specs" >"$t/.claude/planwright.local.yml"

# --- REQ-F1.3: the hygiene screen --------------------------------------------

before=$(count "$o/specs/_observations")
for txt in 'saw it in /home/someone/notes' 'path=/etc/planwright/x' 'see ~/notes/x' \
  'the ~ dir' '~alice/x holds it' 'ask example.com' 'the box at build.local' \
  'host ci.internal was down' 'mail ops@example.org' 'url https://github.com/x/y'; do
  at "$t" "$rec" --target other --text "$txt"
  if [ "$rc" -eq 1 ]; then
    case $err in
      *"hygiene screen"*) ok "screen: refuses '$txt'" ;;
      *) fail "screen: '$txt' refused without naming the screen: $err" ;;
    esac
  else
    fail "screen: '$txt' was not refused (rc=$rc)"
  fi
done
at "$t" "$S/obs-record.sh" --slug topic --scope box.internal --target other --text 'clean text'
if [ "$rc" -eq 1 ]; then
  ok "screen: a hostname in the scope is refused"
else
  fail "screen: scope hostname (rc=$rc)"
fi
if [ "$(count "$o/specs/_observations")" -eq "$before" ]; then
  ok "screen: a refused fragment writes nothing"
else
  fail "screen: a refused fragment left a file"
fi
for txt in 'scripts/obs-record.sh and docs/spec-location.md drift' 'run /spec-draft then /polish' \
  'took ~400s, see ./tests/x.sh' 'D-17/D-18 and v1.2.3, e.g. this'; do
  at "$t" "$rec" --target other --text "$txt"
  if [ "$rc" -eq 0 ]; then
    ok "screen: writes '$txt'"
  else
    fail "screen: '$txt' refused: $err"
  fi
done
at "$w" "$rec" --text 'an unrouted note naming /home/someone/x'
if [ "$rc" -eq 0 ]; then
  ok "screen: an unrouted write is not screened"
else
  fail "screen ran on an unrouted write (rc=$rc)"
fi

# --- REQ-F1.4: no remote write on the routing path ---------------------------

sb=$tmp/stubs
mkdir -p "$sb"
for c in gh curl wget ssh nc scp rsync; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/remote.log"\nexit 1\n' "$c" "$tmp" >"$sb/$c"
  chmod +x "$sb/$c"
done
cat >"$sb/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  case \$a in
    push | fetch | pull | ls-remote | send-pack) echo "git \$*" >>"$tmp/remote.log" ;;
  esac
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$sb/git"
watched=""
at "$t" env PATH="$sb:$PATH" "$rec" --target other --text 'routed under watch'
watched="$watched$rc"
at "$w" env PATH="$sb:$PATH" "$rec" --text 'local under watch'
watched="$watched$rc"
uid=${out##*-}
uid=${uid%.md}
at "$w" env PATH="$sb:$PATH" "$S/obs-consume.sh" --uid "$uid" --spec demo
watched="$watched$rc"
at "$w" env PATH="$sb:$PATH" "$S/obs-render.sh" --archived
watched="$watched$rc"
at "$w" env PATH="$sb:$PATH" "$S/check-obs.sh"
watched="$watched$rc"
[ "$watched" = 00000 ] || fail "routing: a watched run failed before it could reach the network (exits $watched)"
if [ ! -s "$tmp/remote.log" ]; then
  ok "routing: record, consume, render, and check invoke no remote write"
else
  fail "routing: remote calls: $(cat "$tmp/remote.log")"
fi

# --- REQ-H1.3 and the skills ---------------------------------------------------

if grep -qx 'observation_targets: {}' "$REPO_ROOT/config/defaults.yml" \
  && ! grep -q '^spec_root:' "$REPO_ROOT/config/defaults.yml"; then
  ok "defaults: observation_targets ships empty and spec_root absent"
else
  fail "defaults: observation_targets must ship as {} and spec_root stay absent"
fi
# shellcheck disable=SC2016 # the backticks are literal markdown
if grep -q '^| `observation_targets` |' "$REPO_ROOT/docs/options-reference.md"; then
  ok "options reference: observation_targets has a row"
else
  fail "options reference: no observation_targets row"
fi
hits=$(grep -rn 'specs/_observations' "$REPO_ROOT/skills" || true)
if [ -z "$hits" ]; then
  ok "skills: no step composes specs/_observations"
else
  fail "skills compose the store: $hits"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all observation store tests passed"
