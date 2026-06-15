#!/usr/bin/env bash
# builder-guards.sh — the testable detection core of the builder skill
# (Task 16, REQ-G1.2/G1.5/G1.7). Detects a project's stack and prints the
# quality guards the core catalog (config/guard-catalog.yaml) recommends for
# it. The builder skill drives this script, then layers judgment on top
# (apply vs recommend, stake escalation, lifecycle wiring); the mechanical
# detect-and-map step lives here so it is reproducible and CI-testable — the
# dogfood loop runs this against planwright itself.
#
# Usage: builder-guards.sh [--core] [--catalog <path>] [<target-dir>]
#   --core            emit only the universal core guards (skip advisory
#                     breadth dimensions)
#   --catalog <path>  use this catalog instead of planwright's own; also
#                     settable via PLANWRIGHT_GUARD_CATALOG (flag wins)
#   <target-dir>      project to inspect (default: current directory)
#
# Output: one guard per line, tab-separated `<id>\t<category>\t<tool>`,
# sorted by id. Detection signals (catalog `detect` field, space-separated):
# a glob matched by file name, a "dir/glob" matched by relative path, or the
# literal "git" (matches inside a git work tree). "manual" never auto-fires.
#
# Exit: 0 on success, 1 on a missing/unreadable catalog, 2 on usage error.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

core_only=0
catalog="${PLANWRIGHT_GUARD_CATALOG:-}"
target="."

while [ $# -gt 0 ]; do
  case "$1" in
    --core) core_only=1 ;;
    --catalog)
      shift
      [ $# -gt 0 ] || {
        echo "builder-guards: --catalog needs a path" >&2
        exit 2
      }
      catalog="$1"
      ;;
    --catalog=*) catalog="${1#--catalog=}" ;;
    -h | --help)
      # Print the comment header (from line 2 to the first non-comment line),
      # stripping the leading "# " — robust to the header's length.
      awk 'NR>=2 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
      exit 0
      ;;
    -*)
      echo "builder-guards: unknown option '$1'" >&2
      exit 2
      ;;
    *) target="$1" ;;
  esac
  shift
done

# Default catalog: planwright's own, resolved relative to this script (the
# framework ships it; the target project does not have to).
if [ -z "$catalog" ]; then
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  catalog="$script_dir/../config/guard-catalog.yaml"
fi
if [ ! -f "$catalog" ] || [ ! -r "$catalog" ]; then
  echo "builder-guards: guard catalog not found or unreadable: $catalog" >&2
  exit 1
fi
if [ ! -d "$target" ]; then
  echo "builder-guards: target directory not found: $target" >&2
  exit 2
fi

# detect_match <target> <detect-string> — true if any signal matches.
detect_match() {
  local t="$1" detect="$2" sig
  local -a signals
  read -ra signals <<<"$detect"
  # Guard the empty-array case: on the bash 3.2 floor, expanding "${arr[@]}"
  # of an empty array under `set -u` aborts the script (REQ-K1.5). An empty
  # detect simply matches nothing.
  [ "${#signals[@]}" -gt 0 ] || return 1
  for sig in "${signals[@]}"; do
    case "$sig" in
      git)
        git -C "$t" rev-parse --is-inside-work-tree >/dev/null 2>&1 && return 0
        ;;
      manual) : ;; # advisory only; never auto-fires
      */*)
        find "$t" \( -name .git -o -name node_modules -o -name .venv \
          -o -name vendor \) -prune -o -path "*/$sig" -print 2>/dev/null \
          | grep -q . && return 0
        ;;
      *)
        find "$t" \( -name .git -o -name node_modules -o -name .venv \
          -o -name vendor \) -prune -o -name "$sig" -print 2>/dev/null \
          | grep -q . && return 0
        ;;
    esac
  done
  return 1
}

# Parse the catalog's guards: / breadth: sequences into tab-separated records:
# id, category, tool, detect, core, section.
parse_catalog() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function val(line) {
      sub(/^[^:]*:[ \t]*/, "", line)
      line = trim(line)
      sub(/^"/, "", line); sub(/"$/, "", line)
      return line
    }
    function flush() {
      if (have) printf "%s|%s|%s|%s|%s|%s\n", id, cat, tool, detect, core, section
      have = 0
    }
    /^guards:[ \t]*$/   { flush(); section = "guards";  next }
    /^breadth:[ \t]*$/  { flush(); section = "breadth"; next }
    /^[A-Za-z]/         { flush(); section = "" }
    section == ""       { next }
    /^[ \t]*#/          { next }
    /^  -[ \t]+id:/     { flush(); id = val($0); cat = tool = detect = core = ""; have = 1; next }
    have && /^    category:/ { cat = val($0); next }
    have && /^    tool:/     { tool = val($0); next }
    have && /^    detect:/   { detect = val($0); next }
    have && /^    core:/     { core = val($0); next }
    END { flush() }
  ' "$catalog"
}

emit=""
while IFS='|' read -r id cat tool detect core section; do
  [ -n "$id" ] || continue
  # A guard missing any required field is a malformed catalog entry — most
  # often an adopter slip. Skip it with a warning rather than emitting a junk
  # line, dropping it silently, or aborting the run (REQ-K1.7 graceful
  # degradation; the catalog is adopter-extensible, REQ-G1.5). category and
  # tool are required of every entry, breadth included: breadth entries are
  # emitted with the same `<id>\t<category>\t<tool>` columns, so a breadth
  # entry missing either would otherwise emit a contract-violating empty
  # column. A detect signal is required only of non-breadth guards; breadth
  # entries are advisory and carry no real detect.
  missing=""
  [ -n "$cat" ] || missing="category"
  [ -n "$tool" ] || missing="${missing:+$missing, }tool"
  if [ "$section" != "breadth" ]; then
    [ -n "$(printf '%s' "$detect" | tr -d '[:space:]')" ] \
      || missing="${missing:+$missing, }detect"
  fi
  if [ -n "$missing" ]; then
    echo "builder-guards: catalog entry '$id' missing $missing; skipping" >&2
    continue
  fi
  if [ "$core_only" -eq 1 ]; then
    [ "$core" = "true" ] || continue
    if detect_match "$target" "$detect"; then
      emit="$emit$id	$cat	$tool
"
    fi
  else
    if [ "$section" = "breadth" ]; then
      emit="$emit$id	$cat	$tool
"
    elif detect_match "$target" "$detect"; then
      emit="$emit$id	$cat	$tool
"
    fi
  fi
done <<EOF
$(parse_catalog)
EOF

[ -n "$emit" ] || exit 0
printf '%s' "$emit" | sort
