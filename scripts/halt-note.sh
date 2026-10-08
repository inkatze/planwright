#!/bin/sh
# halt-note.sh — record a halting execution skill's Awaiting-input or Deferred
# reference bullet in a spec store that lies outside the work repository
# (custom-spec-location REQ-E1.9, D-13): in separate-repo and plain the bundle
# has no task branch to carry the write, so the bullet lands as an uncommitted
# edit to the store's primary-view tasks.md and nothing is committed,
# branched, or pushed there. The printed path is the file the handoff names;
# committing it is the operator's.
#
# A same-repo store is refused: there the halt writes the bundle copy on the
# task branch and commits it, as before.
#
# Usage: halt-note.sh [--section awaiting|deferred] <spec> <task-id> <text>
#   Run from the work repository: the spec root resolves from the current
#   directory, as the halting skill's own resolver call does.
#   <spec>     the bare identifier (`specs/<spec>` accepted as an alias, one
#              trailing slash allowed)
#   <task-id>  ^[0-9]+(\.[0-9]+)?$, naming a `### Task` block in the bundle
#   <text>     the payload, one line with no C0 control byte or DEL (the C1
#              range is left alone, since those bytes continue UTF-8
#              characters). An Awaiting-input bullet the task already has
#              gains it as a further `; ` segment; a Deferred bullet the task
#              already has is refused.
#
# The bullet is `- **Task <id>** — <text>`, placed under the section heading
# (replacing a `(none yet)` placeholder); a bullet for the task under another
# of the three payload sections is refused, since a task carries at most one.
# Format-version 2 bundles only: a version 1 bundle parks by moving the block,
# which stays a hand edit. The file is replaced through a temp file in the
# same directory, never written through a symlink, under a lock beside it
# (scripts/lock-lib.sh), so concurrent halts on one bundle each land.
#
# Exit: 0 written, the file's path on stdout · 2 usage, a bad argument, or a
#   broken install (a sibling library missing or not a readable file) ·
#   3 the store is same-repo · 4 the bundle cannot take the bullet (missing,
#   unreadable, not format-version 2, no such task or section, a fence left
#   open, already parked) · 5 the spec root did not resolve · 6 the write or
#   its lock failed.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

case $0 in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac
TAB=$(printf '\t')

say() { printf 'halt-note: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237')" >&2; }
usage() {
  say "usage: halt-note.sh [--section awaiting|deferred] <spec> <task-id> <text>"
  exit 2
}

for lib in spec-id-lib.sh spec-parse.sh lock-lib.sh; do
  [ -f "$script_dir/$lib" ] && [ -r "$script_dir/$lib" ] || {
    say "broken install: $script_dir/$lib is missing or not readable"
    exit 2
  }
done
# shellcheck source=scripts/spec-id-lib.sh
. "$script_dir/spec-id-lib.sh"
# shellcheck source=scripts/spec-parse.sh
. "$script_dir/spec-parse.sh"
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh"

section=awaiting
case ${1:-} in
  --section)
    [ "$#" -ge 2 ] || usage
    section=$2
    shift 2
    ;;
  --section=*)
    section=${1#--section=}
    shift
    ;;
esac
case $section in
  awaiting) heading='Awaiting input' ;;
  deferred) heading='Deferred' ;;
  *) usage ;;
esac
[ "$#" -eq 3 ] || usage

spec_id_canon "$1"
spec=$SPEC_ID
case $spec in
  '' | */* | *[!a-z0-9-]* | [!a-z0-9]* | flight)
    say "not a spec identifier: '$1'"
    exit 2
    ;;
esac
[ "${#spec}" -le 64 ] || {
  say "the spec identifier is longer than 64 characters"
  exit 2
}
id=$2
case $id in
  '' | *[!0-9.]* | .* | *. | *.*.*) id_ok=0 ;;
  *) id_ok=1 ;;
esac
[ "$id_ok" -eq 1 ] || {
  say "not a task id: '$2'"
  exit 2
}
text=$3
[ -n "$text" ] && [ "$(printf '%s' "$text" | tr -d '\000-\037\177')" = "$text" ] || {
  say "the text must be one non-empty line with no control byte"
  exit 2
}

line=$(env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" spec --primary --explain) || {
  say "the spec root did not resolve"
  exit 5
}
rest=${line#*"$TAB"}
root=${rest%%"$TAB"*}
rest=${rest#*"$TAB"}
posture=${rest%%"$TAB"*}
case $posture in
  separate-repo | plain) ;;
  same-repo)
    say "the spec root is in the work repository (same-repo): write the bullet on the task branch's copy and commit it"
    exit 3
    ;;
  *)
    say "the spec root's posture is unknown"
    exit 5
    ;;
esac

file=$root/$spec/tasks.md
# Halts on one bundle can race (a re-anchor fails every in-flight worker's
# gate at once), so the rewrite holds a lock beside the file. It is named from
# inside the bundle, since lock-lib refuses a `#` a root path may carry.
if [ ! -d "$root/$spec" ] || ! cd -- "$root/$spec"; then
  say "no regular tasks.md for '$spec' under the spec root"
  exit 4
fi
tmp=''
cleanup() {
  pw_lock_release_all
  [ -z "$tmp" ] || rm -f "$tmp"
}
trap cleanup EXIT
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
# A bounded wait (lock-lib's default spins for minutes): a rewrite holds the
# lock for well under a second, and a caller's tool timeout must see exit 6.
pw_lock_acquire .tasks.md.halt.lock 400
case $? in
  0) ;;
  1)
    say "$file stayed locked by another halt"
    exit 6
    ;;
  *)
    say "cannot lock $file"
    exit 6
    ;;
esac
if [ -L "$file" ] || [ ! -f "$file" ]; then
  say "no regular tasks.md for '$spec' under the spec root"
  exit 4
fi
[ -r "$file" ] || {
  say "cannot read $file"
  exit 4
}
fv=$(spec_parse_header_value "$file" Format-version) || fv=''
[ "$fv" = 2 ] || {
  say "$spec is not a format-version 2 bundle; a version 1 park moves the task block by hand"
  exit 4
}

tmp=$(mktemp .tasks.md.halt.XXXXXX 2>/dev/null) || {
  tmp=''
  say "could not write next to $file"
  exit 6
}

# The rewrite. The parse runs on the shared fence lexer and grammar
# (scripts/spec-parse.sh), so no fenced line reaches a rule here. A rewrite
# must still print every line, so the one rule ahead of the lexer only keeps
# each raw line, parsing nothing, and END prints the file back with the single
# edit applied: the task's own bullet extended, the placeholder replaced, or
# a new bullet after the section's last non-blank line (fenced lines count as
# content), or straight under the heading, between blank lines, when the
# section holds nothing. Matching is CRLF-tolerant; every other line stays
# verbatim. The text rides the environment: `awk -v` would turn a backslash in
# it into an escape.
HALT_NOTE_TEXT=$text awk -v id="$id" -v heading="$heading" -v section="$section" '{ raw[NR] = $0 }'"$spec_parse_awk_fence$spec_parse_awk_grammar"'
  function norm(s) { sub(/\r$/, "", s); return s }
  function payload(s) { return s == "Awaiting input" || s == "Deferred" || s == "Out of scope" }
  # Leaving the target section with nothing placed: after its last non-blank
  # line, or under its heading when it has none.
  function place() { if (last) at = last; else { at = shead; bare = 1 }; done = 1 }
  BEGIN { lead = "- **Task " id "**"; text = ENVIRON["HALT_NOTE_TEXT"] }
  {
    if (insec && NR > prev + 1) last = NR - 1
    prev = NR
    l = norm($0)
    if (l ~ /^## /) {
      if (insec && !done) place()
      sec = substr(l, 4); sub(/[ \t]+$/, "", sec)
      insec = (sec == heading)
      if (sec == "Tasks") tasks = 1
      if (insec) { found = 1; last = 0; shead = NR }
      next
    }
    if (insec && l !~ /^[ \t]*$/) last = NR
    # A string compare: as numbers, `01` and `1.0` would name Task 1.
    if (tasks && (spec_parse_task_id($0) "") == (id "")) hasblock = 1
    if (payload(sec) && index(l, lead) == 1) {
      if (!insec) { other = 1 }
      else if (section == "awaiting" && !done) { edit = NR; extend = 1; done = 1; next }
      else { dup = 1 }
    }
    if (insec && !done && l ~ /^\(none yet\)[ \t]*$/) { edit = NR; done = 1 }
  }
  END {
    spec_parse__fence_eof()
    if (insec && !done) place()
    if (!found) exit 7
    if (!hasblock) exit 4
    if (other || dup) exit 6
    # A written line takes the line ending of the first line of the file.
    eol = (raw[1] ~ /\r$/) ? "\r" : ""
    bullet = "- **Task " id "** — " text eol
    for (i = 1; i <= NR; i++) {
      if (i == edit && extend) print norm(raw[i]) "; " text eol
      else if (i == edit) print bullet
      else print raw[i]
      if (i != at) continue
      if (bare) print eol
      print bullet
      if (bare && i < NR && norm(raw[i + 1]) !~ /^[ \t]*$/) print eol
    }
  }
' "$file" >"$tmp"
rc=$?
case $rc in
  0) ;;
  3)
    say "$file ends inside an open code fence"
    exit 4
    ;;
  4)
    say "$spec has no Task $id block"
    exit 4
    ;;
  7)
    say "$file has no ## $heading section"
    exit 4
    ;;
  6)
    say "Task $id is already parked in $file; a task carries one reference bullet"
    exit 4
    ;;
  *)
    say "could not rewrite $file"
    exit 6
    ;;
esac
# mktemp creates the temp file 0600, so give it the original's mode before it
# replaces the original.
chmod "$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo 644)" "$tmp" 2>/dev/null || :
mv -f -- "$tmp" "$file" || {
  say "could not replace $file"
  exit 6
}
tmp=''
printf '%s\n' "$file"
