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
#   <spec>     the bare identifier (`specs/<spec>` accepted as an alias, one
#              trailing slash allowed)
#   <task-id>  ^[0-9]+(\.[0-9]+)?$, naming a `### Task` block in the bundle
#   <text>     the payload, one line with no control byte. An Awaiting-input
#              bullet the task already has gains it as a further `; `
#              segment; a Deferred bullet the task already has is refused.
#
# The bullet is `- **Task <id>** — <text>`, placed under the section heading
# (replacing a `(none yet)` placeholder); a bullet for the task under another
# of the three payload sections is refused, since a task carries at most one.
# Format-version 2 bundles only: a version 1 bundle parks by moving the block,
# which stays a hand edit. The file is replaced through a temp file in the
# same directory, never written through a symlink.
#
# Exit: 0 written, the file's path on stdout · 2 usage or a bad argument ·
#   3 the store is same-repo · 4 the bundle cannot take the bullet (missing,
#   not format-version 2, no such task or section, a fence left open, already
#   parked elsewhere) · 5 the spec root did not resolve · 6 the write failed.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

case $0 in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac
TAB=$(printf '\t')

say() { printf 'halt-note: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')" >&2; }
usage() {
  say "usage: halt-note.sh [--section awaiting|deferred] <spec> <task-id> <text>"
  exit 2
}

for lib in spec-id-lib.sh spec-parse.sh; do
  [ -r "$script_dir/$lib" ] || {
    say "broken install: $script_dir/$lib is missing or not readable"
    exit 2
  }
done
# shellcheck source=scripts/spec-id-lib.sh
. "$script_dir/spec-id-lib.sh"
# shellcheck source=scripts/spec-parse.sh
. "$script_dir/spec-parse.sh"

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
if [ -L "$file" ] || [ ! -f "$file" ]; then
  say "no regular tasks.md for '$spec' under the spec root"
  exit 4
fi
fv=$(spec_parse_header_value "$file" Format-version) || fv=''
[ "$fv" = 2 ] || {
  say "$spec is not a format-version 2 bundle; a version 1 park moves the task block by hand"
  exit 4
}

tmp=$(mktemp "$root/$spec/.tasks.md.halt.XXXXXX" 2>/dev/null) || {
  say "could not write next to $file"
  exit 6
}
trap 'rm -f "$tmp"' EXIT

# The rewrite: fence-aware, CRLF-tolerant matching, every line kept verbatim
# except the target section's placeholder or the task's own bullet.
awk -v id="$id" -v heading="$heading" -v text="$text" -v append="$section" '
  function norm(s) { sub(/\r$/, "", s); return s }
  function payload(s) { return s == "Awaiting input" || s == "Deferred" || s == "Out of scope" }
  # Blank lines inside the target section are held back, so a new bullet
  # lands after its last non-blank line rather than after the gap before the
  # next heading.
  function flush() { for (i = 1; i <= nblank; i++) print blank[i]; nblank = 0 }
  function emit_new() { print "- **Task " id "** — " text; done = 1 }
  BEGIN { lead = "- **Task " id "**" }
  {
    raw = $0
    l = norm(raw)
    if (l ~ /^```/) { flush(); fence = !fence; print raw; next }
    if (fence) { print raw; next }
    if (l ~ /^## /) {
      if (insec && !done) emit_new()
      flush()
      sec = substr(l, 4); sub(/[ \t]+$/, "", sec)
      insec = (sec == heading)
      if (sec == "Tasks") tasks = 1
      if (insec) { found = 1; heading_line = 1 }
      print raw
      next
    }
    if (insec && l ~ /^[ \t]*$/) {
      if (heading_line) { print raw; next }
      blank[++nblank] = raw
      next
    }
    heading_line = 0
    flush()
    if (tasks && l ~ /^### Task / && $3 == id) hasblock = 1
    if (payload(sec) && index(l, lead) == 1) {
      if (!insec) { other = 1 }
      else if (append == "awaiting" && !done) { print l "; " text; done = 1; next }
      else { dup = 1 }
    }
    if (insec && !done && l ~ /^\(none yet\)[ \t]*$/) { emit_new(); next }
    print raw
  }
  END {
    if (fence) exit 5
    if (insec && !done) emit_new()
    flush()
    if (!found) exit 3
    if (!hasblock) exit 4
    if (other || dup) exit 6
  }
' "$file" >"$tmp"
rc=$?
case $rc in
  0) ;;
  3)
    say "$file has no ## $heading section"
    exit 4
    ;;
  4)
    say "$spec has no Task $id block"
    exit 4
    ;;
  5)
    say "$file ends inside an open code fence"
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
# A sibling first: a new file's mode then follows the umask, so match the
# original's before it replaces it.
chmod "$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo 644)" "$tmp" 2>/dev/null || :
mv -f -- "$tmp" "$file" || {
  say "could not replace $file"
  exit 6
}
trap - EXIT
printf '%s\n' "$file"
