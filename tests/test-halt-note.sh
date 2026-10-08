#!/bin/bash
# scripts/halt-note.sh: a halting execution skill's Awaiting-input or Deferred
# write in a holder or plain store lands as an uncommitted edit to the
# primary view's tasks.md, with no commit, branch, or push in the holder
# (custom-spec-location REQ-E1.9, D-13), and the printed path is the file the
# handoff names.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$REPO_ROOT/scripts"

failures=0
ok() { echo "ok: $1"; }
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  failures=$((failures + 1))
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/halt-note.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
mkdir -p "$tmp/home"
hermetic() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    HOME="$tmp/home" GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$REPO_ROOT" "$@"
}
gitq() { hermetic git "$@" >/dev/null 2>&1; }
# note <dir> <args...> — halt-note.sh from <dir>; sets out and rc.
note() {
  n_dir=$1
  shift
  out=$(cd "$n_dir" && hermetic "$S/halt-note.sh" "$@" 2>&1)
  rc=$?
}

# tasks_v2 <file> — a version 2 tasks.md with two tasks and empty payload
# sections, plus a fenced example heading that must not take the bullet.
tasks_v2() {
  cat >"$1" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2

```markdown
## Awaiting input
```

## Tasks

### Task 1 — the first unit

- **Deliverables:** a thing
- **Done when:** the thing exists
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day

### Task 2 — the second unit

- **Deliverables:** another
- **Done when:** it exists
- **Dependencies:** 1
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

- **Task 2** — retired.
EOF
}

# The holder fixture: a work repository whose spec_root is a marked directory
# in a holder repository, the bundle committed there.
w=$tmp/work
gitq -c init.defaultBranch=main init -q "$w"
printf 'x\n' >"$w/file"
gitq -C "$w" add -A && gitq -C "$w" commit -q -m init
h=$tmp/holder
gitq -c init.defaultBranch=trunk init -q "$h"
z=$h/specs
mkdir -p "$z/demo" "$w/.claude"
printf 'project: fixture\nlayout: 1\n' >"$z/planwright-spec-root.yml"
tasks_v2 "$z/demo/tasks.md"
gitq -C "$h" add -A && gitq -C "$h" commit -q -m bundle
printf 'spec_root: %s\n' "$z" >"$w/.claude/planwright.local.yml"
head_before=$(hermetic git -C "$h" rev-parse HEAD)
refs_before=$(hermetic git -C "$h" for-each-ref --format='%(refname)')

note "$w" demo 1 "the gate found an anchor mismatch"
if [ "$rc" -eq 0 ] && [ "$out" = "$z/demo/tasks.md" ]; then
  ok "holder: the note is written and its file named"
else
  fail "holder: halt-note (rc=$rc): $out"
fi
# section <file> <from> <to> — the lines from the unfenced <from> heading to
# the next <to> heading.
section() { awk -v a="## $2" -v b="## $3" '/^```/ { f = !f; next } !f && $0 == a { p = 1 } p { print } p && $0 == b { exit }' "$1"; }
got=$(section "$z/demo/tasks.md" "Awaiting input" Deferred)
want='## Awaiting input

- **Task 1** — the gate found an anchor mismatch

## Deferred'
if [ "$got" = "$want" ]; then
  ok "holder: the bullet replaces the placeholder"
else
  fail "holder: the section reads: $got"
fi
if grep -c '^- \*\*Task 1\*\*' "$z/demo/tasks.md" | grep -qx 1; then
  ok "holder: the fenced example heading takes no bullet"
else
  fail "holder: the bullet was written twice"
fi

note "$w" specs/demo/ 1 "and the brief has no anchor entry"
if grep -qx -- '- \*\*Task 1\*\* — the gate found an anchor mismatch; and the brief has no anchor entry' "$z/demo/tasks.md"; then
  ok "holder: a second halt adds a segment to the task's bullet"
else
  fail "holder: no segment added (rc=$rc): $out"
fi

if [ "$(hermetic git -C "$h" rev-parse HEAD)" = "$head_before" ] \
  && [ "$(hermetic git -C "$h" for-each-ref --format='%(refname)')" = "$refs_before" ] \
  && [ "$(hermetic git -C "$h" status --porcelain)" = " M specs/demo/tasks.md" ]; then
  ok "holder: the note is an uncommitted edit, with no new commit or branch"
else
  fail "holder: the holder's git state changed: $(hermetic git -C "$h" status --porcelain)"
fi

note "$w" --section deferred demo 1 "a parked task carries one bullet"
if [ "$rc" -eq 4 ]; then
  ok "holder: a second payload section is refused"
else
  fail "holder: a Deferred bullet beside the Awaiting one (rc=$rc): $out"
fi
note "$w" --section deferred demo 2 "already out of scope"
if [ "$rc" -eq 4 ]; then
  ok "holder: a task already out of scope is refused"
else
  fail "holder: a task already parked (rc=$rc): $out"
fi
note "$w" demo 3 "no such task"
if [ "$rc" -eq 4 ]; then
  ok "holder: a task with no block is refused"
else
  fail "holder: an unknown task (rc=$rc): $out"
fi
for numeric in 01 1.0; do
  note "$w" demo "$numeric" "a numeric twin of Task 1"
  if [ "$rc" -eq 4 ] && ! grep -qF -- "**Task $numeric**" "$z/demo/tasks.md"; then
    ok "holder: the task id '$numeric' names no block, so it is refused"
  else
    fail "holder: the task id '$numeric' (rc=$rc): $out"
  fi
done
for bad in '1;2' 1.2.3 '-1' ''; do
  note "$w" demo "$bad" text
  if [ "$rc" -eq 2 ]; then
    ok "holder: the task id '$bad' is refused"
  else
    fail "holder: the task id '$bad' (rc=$rc): $out"
  fi
done
note "$w" demo 1 "$(printf 'two\nlines')"
if [ "$rc" -eq 2 ]; then
  ok "holder: a multi-line text is refused"
else
  fail "holder: a multi-line text (rc=$rc): $out"
fi
# A refused argument is echoed back without its control bytes: C0 and DEL,
# and the C1 range the canonical sanitizer (scripts/echo-safety.sh) drops,
# whose 0x9b opens a control sequence on a terminal honouring 8-bit controls.
note "$w" "$(printf 'x\033[31m\23331m')" 1 text
if [ "$rc" -eq 2 ] && ! printf '%s' "$out" | LC_ALL=C grep -q "$(printf '[\033\233]')"; then
  ok "holder: a refused identifier reaches stderr with no control byte"
else
  fail "holder: control bytes in a refused identifier (rc=$rc)"
fi
# A library replaced by a directory is a broken install, refused as one:
# dash sources a directory silently and bash's sh only warns, so a bare
# readability test lets the run go on without the library.
cp -R "$S" "$tmp/broken-install"
rm "$tmp/broken-install/lock-lib.sh"
mkdir "$tmp/broken-install/lock-lib.sh"
for sh in dash sh; do
  command -v "$sh" >/dev/null 2>&1 || continue
  out=$(cd "$w" && hermetic "$sh" "$tmp/broken-install/halt-note.sh" demo 1 text 2>&1)
  rc=$?
  if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'broken install'; then
    ok "holder: a library that is a directory is a broken install under $sh"
  else
    fail "holder: a directory library under $sh (rc=$rc): $out"
  fi
done
# A backslash is text, never an escape: `\n` must not split the bullet.
gitq -C "$h" checkout -q -- specs/demo/tasks.md
note "$w" demo 1 'see C:\new\table and \\ here'
if [ "$rc" -eq 0 ] && grep -qxF -- '- **Task 1** — see C:\new\table and \\ here' "$z/demo/tasks.md"; then
  ok "holder: a backslash in the text lands verbatim on one line"
else
  fail "holder: a backslash in the text (rc=$rc): $(section "$z/demo/tasks.md" "Awaiting input" Deferred)"
fi
gitq -C "$h" checkout -q -- specs/demo/tasks.md

# Deferred, on a fresh bundle.
gitq -C "$h" checkout -q -- specs/demo/tasks.md
note "$w" --section deferred demo 1 "waits on the holder's guard recipe"
if section "$z/demo/tasks.md" Deferred "Out of scope" | grep -qx -- '- \*\*Task 1\*\* — waits on the holder.s guard recipe'; then
  ok "holder: a Deferred bullet lands under Deferred"
else
  fail "holder: Deferred (rc=$rc): $out"
fi
gitq -C "$h" checkout -q -- specs/demo/tasks.md

# A second Deferred bullet for one task, an open fence, and a missing
# section are each refused.
note "$w" --section=deferred demo 1 "first deferral"
note "$w" --section deferred demo 1 "second deferral"
if [ "$rc" -eq 4 ] && [ "$(grep -c '^- \*\*Task 1\*\*' "$z/demo/tasks.md")" -eq 1 ]; then
  ok "holder: a second Deferred bullet for the task is refused"
else
  fail "holder: a duplicate Deferred bullet (rc=$rc): $out"
fi
gitq -C "$h" checkout -q -- specs/demo/tasks.md
printf '\n```text\nunclosed\n' >>"$z/demo/tasks.md"
note "$w" demo 1 text
if [ "$rc" -eq 4 ] && ! grep -q '^- \*\*Task 1\*\*' "$z/demo/tasks.md"; then
  ok "holder: a tasks.md ending in an open fence is refused"
else
  fail "holder: an open fence (rc=$rc): $out"
fi
gitq -C "$h" checkout -q -- specs/demo/tasks.md
mkdir -p "$z/nosection"
printf '# N\n\n**Status:** Ready\n**Format-version:** 2\n\n## Tasks\n\n### Task 1 — x\n' >"$z/nosection/tasks.md"
note "$w" nosection 1 text
if [ "$rc" -eq 4 ]; then
  ok "holder: a bundle with no Awaiting input section is refused"
else
  fail "holder: no section (rc=$rc): $out"
fi
for bad in '--section=later' '--section later'; do
  # shellcheck disable=SC2086 # the flag and its value split on purpose
  note "$w" $bad demo 1 text
  if [ "$rc" -eq 2 ]; then
    ok "holder: '$bad' is refused"
  else
    fail "holder: '$bad' (rc=$rc): $out"
  fi
done
note "$w" Not_A_Spec 1 text
if [ "$rc" -eq 2 ]; then
  ok "holder: a malformed spec identifier is refused"
else
  fail "holder: a malformed spec identifier (rc=$rc): $out"
fi

# A version 1 bundle and a symlinked tasks.md are refused.
mkdir -p "$z/old" "$z/linked"
printf '# Old\n\n**Status:** Ready\n**Format-version:** 1\n\n## Awaiting input\n\n(none yet)\n' >"$z/old/tasks.md"
note "$w" old 1 text
if [ "$rc" -eq 4 ]; then
  ok "holder: a version 1 bundle is refused"
else
  fail "holder: version 1 (rc=$rc): $out"
fi
tasks_v2 "$tmp/elsewhere-tasks.md"
ln -s "$tmp/elsewhere-tasks.md" "$z/linked/tasks.md"
note "$w" linked 1 text
if [ "$rc" -eq 4 ]; then
  ok "holder: a symlinked tasks.md is refused"
else
  fail "holder: a symlink (rc=$rc): $out"
fi

if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$z/locked"
  tasks_v2 "$z/locked/tasks.md"
  chmod 000 "$z/locked/tasks.md"
  note "$w" locked 1 text
  chmod 644 "$z/locked/tasks.md"
  case $rc:$out in
    4:*"cannot read"*) ok "holder: an unreadable tasks.md is refused as unreadable" ;;
    *) fail "holder: an unreadable tasks.md (rc=$rc): $out" ;;
  esac
fi

if [ -z "$(find "$z" -name '.tasks.md.halt*')" ]; then
  ok "holder: no refusal leaves a temp file or lock behind"
else
  fail "holder: left behind: $(find "$z" -name '.tasks.md.halt*' | tr '\n' ' ')"
fi

# plain: the same write, no repository anywhere near the store.
pw=$tmp/plainwork
gitq -c init.defaultBranch=main init -q "$pw"
p=$tmp/plainstore
mkdir -p "$p/demo" "$pw/.claude"
printf 'project: fixture\nlayout: 1\n' >"$p/planwright-spec-root.yml"
tasks_v2 "$p/demo/tasks.md"
printf 'spec_root: %s\n' "$p" >"$pw/.claude/planwright.local.yml"
note "$pw" demo 2 "blocked"
if [ "$rc" -eq 4 ]; then
  ok "plain: a task already out of scope is refused"
else
  fail "plain: (rc=$rc): $out"
fi
note "$pw" demo 1 "blocked on the operator"
if [ "$rc" -eq 0 ] && [ "$out" = "$p/demo/tasks.md" ] \
  && grep -qx -- '- \*\*Task 1\*\* — blocked on the operator' "$p/demo/tasks.md"; then
  ok "plain: the note lands in the store and its file is named"
else
  fail "plain: (rc=$rc): $out"
fi

# A signal mid-rewrite removes the temp file and releases the lock, leaving
# tasks.md as it was. A stub awk holds the rewrite open long enough to land
# the signal inside it; dash where present, since it runs no EXIT trap on a
# signal of its own accord.
sig_sh=/bin/sh
[ -x /bin/dash ] && sig_sh=/bin/dash
mkdir -p "$tmp/slowbin"
real_awk=$(command -v awk)
cat >"$tmp/slowbin/awk" <<EOF
#!/bin/sh
[ -z "\${HALT_NOTE_TEXT:-}" ] || sleep 3
exec "$real_awk" "\$@"
EOF
chmod +x "$tmp/slowbin/awk"
tasks_v2 "$p/demo/tasks.md"
cp "$p/demo/tasks.md" "$tmp/before-signal.md"
(
  cd "$pw" || exit 1
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  exec env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    HOME="$tmp/home" GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    PLANWRIGHT_ROOT="$REPO_ROOT" PATH="$tmp/slowbin:$PATH" "$sig_sh" "$S/halt-note.sh" demo 1 "interrupted"
) >/dev/null 2>&1 &
sig_pid=$!
n=0
while [ -z "$(find "$p/demo" -name '.tasks.md.halt.??????')" ] && [ "$n" -lt 100 ]; do
  sleep 0.1
  n=$((n + 1))
done
kill -TERM "$sig_pid" 2>/dev/null
wait "$sig_pid"
sig_rc=$?
if [ "$sig_rc" -eq 143 ] && [ -z "$(find "$p/demo" -name '.tasks.md.halt*')" ] \
  && cmp -s "$p/demo/tasks.md" "$tmp/before-signal.md"; then
  ok "plain: a TERM mid-rewrite leaves tasks.md, and no temp file or lock"
else
  fail "plain: a TERM mid-rewrite (rc=$sig_rc): $(find "$p/demo" -name '.tasks.md.halt*' | tr '\n' ' ')"
fi

# Concurrent halts on one bundle (a re-anchor fails every in-flight worker's
# gate at once) each keep their bullet.
mkdir -p "$p/many"
{
  printf '# Many\n\n**Status:** Ready\n**Format-version:** 2\n\n## Tasks\n\n'
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '### Task %s — unit %s\n\n' "$i" "$i"; done
  printf '## Awaiting input\n\n(none yet)\n\n## Deferred\n\n(none yet)\n'
} >"$p/many/tasks.md"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  (cd "$pw" && hermetic "$S/halt-note.sh" many "$i" "halt $i" >/dev/null 2>&1) &
done
wait
kept=$(grep -c '^- \*\*Task [0-9]*\*\* — halt [0-9]*$' "$p/many/tasks.md")
if [ "$kept" -eq 12 ] && [ -z "$(find "$p/many" -name '.tasks.md.halt*')" ]; then
  ok "plain: twelve concurrent halts keep all twelve bullets and leave nothing behind"
else
  fail "plain: concurrent halts kept $kept of 12 bullets: $(find "$p/many" | tr '\n' ' ')"
fi

# A section left with neither a placeholder nor a bullet (a hand unpark that
# dropped both) takes the bullet under its heading, with a blank line on each
# side, whether a blank line or the next heading follows the heading.
for gap in blank none; do
  tasks_v2 "$p/demo/tasks.md"
  awk '!d && $0 == "(none yet)" { d = 1; s = 1; next } s { s = 0; next } { print }' \
    "$p/demo/tasks.md" >"$p/demo/tasks.bare" && mv "$p/demo/tasks.bare" "$p/demo/tasks.md"
  if [ "$gap" = none ]; then
    awk '/^```/ { f = !f } !f && !d && $0 == "## Awaiting input" { d = 1; print; getline; if ($0 != "") print; next } { print }' \
      "$p/demo/tasks.md" >"$p/demo/tasks.bare" && mv "$p/demo/tasks.bare" "$p/demo/tasks.md"
  fi
  note "$pw" demo 1 "bare section"
  got=$(section "$p/demo/tasks.md" "Awaiting input" Deferred)
  want='## Awaiting input

- **Task 1** — bare section

## Deferred'
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    ok "plain: an empty section ($gap after the heading) takes the bullet between blank lines"
  else
    fail "plain: an empty section ($gap, rc=$rc) reads: $got"
  fi
done

# A CRLF bundle keeps CRLF on the lines the helper writes, a new bullet and
# an added segment alike.
tasks_v2 "$p/demo/tasks.md"
sed 's/$/\r/' "$p/demo/tasks.md" >"$p/demo/tasks.crlf" && mv "$p/demo/tasks.crlf" "$p/demo/tasks.md"
note "$pw" demo 1 "first"
note "$pw" demo 1 "second"
if [ "$rc" -eq 0 ] && grep -qx -- $'- \\*\\*Task 1\\*\\* — first; second\r' "$p/demo/tasks.md" \
  && [ "$(grep -vc $'\r$' "$p/demo/tasks.md")" -eq 0 ]; then
  ok "plain: a CRLF tasks.md keeps CRLF on the written lines"
else
  fail "plain: CRLF (rc=$rc): $(grep -vn $'\r$' "$p/demo/tasks.md" | tr '\n' ' ')"
fi

# A spec root that does not resolve.
gitq -c init.defaultBranch=main init -q "$tmp/broken"
mkdir -p "$tmp/broken/.claude"
printf 'spec_root: %s\n' "$tmp/nowhere" >"$tmp/broken/.claude/planwright.local.yml"
note "$tmp/broken" demo 1 text
if [ "$rc" -eq 5 ]; then
  ok "a spec root that does not resolve is refused"
else
  fail "an unresolved spec root (rc=$rc): $out"
fi

# same-repo: the halt rides the task branch, so the helper refuses.
gitq -c init.defaultBranch=main init -q "$tmp/same"
mkdir -p "$tmp/same/specs/demo"
tasks_v2 "$tmp/same/specs/demo/tasks.md"
note "$tmp/same" demo 1 text
if [ "$rc" -eq 3 ]; then
  ok "same-repo: the helper refuses and points at the task branch"
else
  fail "same-repo: (rc=$rc): $out"
fi

if [ "$failures" -ne 0 ]; then
  echo "FAIL: test-halt-note.sh ($failures failure(s))" >&2
  exit 1
fi
echo "PASS: test-halt-note.sh"
