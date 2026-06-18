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
target_set=0

while [ $# -gt 0 ]; do
  case "$1" in
    --core) core_only=1 ;;
    --catalog)
      shift
      # A non-empty path is required: an empty value (e.g. --catalog "$VAR"
      # with VAR unset) would otherwise fall back to the default catalog
      # silently. Short-circuit guards the unbound "$1" under set -u.
      { [ $# -gt 0 ] && [ -n "$1" ]; } || {
        echo "builder-guards: --catalog needs a non-empty path" >&2
        exit 2
      }
      catalog="$1"
      ;;
    --catalog=*)
      catalog="${1#--catalog=}"
      [ -n "$catalog" ] || {
        echo "builder-guards: --catalog needs a non-empty path" >&2
        exit 2
      }
      ;;
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
    *)
      # Reject a second positional rather than silently using the last one
      # (the repo convention, cf. scripts/spec-validate.sh).
      [ "$target_set" -eq 0 ] || {
        echo "builder-guards: unexpected extra argument '$1'" >&2
        exit 2
      }
      target="$1"
      target_set=1
      ;;
  esac
  shift
done

# Default catalog: planwright's own, read THROUGH the overlay merge path
# (Task 5, scripts/resolve-catalog.sh) so adopter / repo-tracked / machine-local
# overlay catalogs apply automatically — the guard catalog is one of the two
# growable catalogs the overlay mechanism unions (REQ-B1.3, REQ-D1.1). An
# explicit --catalog / PLANWRIGHT_GUARD_CATALOG override still wins and bypasses
# the merge (the catalog the operator names is used verbatim).
if [ -z "$catalog" ]; then
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  resolver="$script_dir/resolve-catalog.sh"
  seed="$script_dir/../config/guard-catalog.yaml"
  # The shipped seed must exist: a missing core seed is a broken install, not a
  # normal absent overlay layer (REQ-A1.4 governs the overlay layers above core,
  # not the framework's own seed). resolve-catalog treats a missing core file as
  # an absent layer (empty output, exit 0), so without this check a broken
  # install would silently emit zero guards instead of hard-failing the way the
  # pre-overlay single-layer read did (D-7: a broken core seed is surfaced as
  # such). The --catalog / PLANWRIGHT_GUARD_CATALOG override bypasses this whole
  # block and keeps its own found-or-readable check below.
  if [ ! -r "$seed" ]; then
    echo "builder-guards: shipped guard catalog seed not found or unreadable: $seed" >&2
    exit 1
  fi
  if [ -r "$resolver" ]; then
    # Explicit template (repo convention, cf. classify-ci-failure.sh): keeps the
    # temp file in $TMPDIR and stays portable across the bash-3.2/BSD floor the
    # header claims, rather than relying on a bare-mktemp default template.
    merged="$(mktemp "${TMPDIR:-/tmp}/builder-guards-merged.XXXXXX")" || {
      echo "builder-guards: cannot create temp file for the merged guard catalog" >&2
      exit 1
    }
    trap 'rm -f "$merged"' EXIT
    # resolve-catalog prints the merged catalog on stdout and surfaces overlay
    # warnings on stderr (let them flow). A nonzero exit is a hard-fail — e.g. a
    # malformed repo-tracked overlay — and must NOT silently fall back to the
    # unmerged seed, or a team-shared misconfiguration would run unintended
    # guards (D-7). The framework seed itself never triggers this path.
    #
    # Pin the core seed to this script's own sibling root (PLANWRIGHT_ROOT): the
    # guard catalog builder-guards ships with is always config/guard-catalog.yaml
    # next to it, so the merge layers overlays on top of THAT seed rather than an
    # unrelated installed copy the global resolution chain might find first. In a
    # real install the sibling root IS the install root, so this is a no-op there.
    if PLANWRIGHT_ROOT="$script_dir/.." /bin/bash "$resolver" guard-catalog >"$merged"; then
      catalog="$merged"
    else
      echo "builder-guards: guard-catalog overlay resolution failed; refusing to fall back to the unmerged seed" >&2
      exit 1
    fi
  else
    # The overlay resolver is unavailable: degrade gracefully to the shipped
    # seed (REQ-K1.7) — a single-layer read, but never a hard failure.
    catalog="$seed"
  fi
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

# Parse the catalog's guards: / breadth: sequences into pipe-delimited records
# (id|category|tool|detect|core|section), read back below with IFS='|'. (The
# script's final stdout is the tab-separated `<id><TAB><category><TAB><tool>`
# contract; this intermediate record format is separate.)
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
parsed=0
while IFS='|' read -r id cat tool detect core section; do
  [ -n "$id" ] || continue
  parsed=$((parsed + 1))
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

# Zero parsed entries despite a declared guards:/breadth: section almost always
# means the entries did not match the constrained reader's expected shape
# (2-space list items, 4-space fields, unquoted or double-quoted scalars; no
# single quotes, inline comments, or reflowed indentation). A silent empty
# result is the worst failure mode for an adopter extending the catalog, so
# warn loudly. The section-detection here is deliberately looser than the
# parser's exact `^guards:$` match: it also catches a header with a trailing
# inline comment or leading indentation (`guards:  # ...`), the very variants
# the strict parser drops — so the warning still fires instead of the section
# slipping through silently. A section-less catalog legitimately yields zero
# and is not flagged. (Stays non-fatal per REQ-K1.7 graceful degradation.)
if [ "$parsed" -eq 0 ] && grep -Eq '^[[:blank:]]*(guards|breadth):' "$catalog"; then
  echo "builder-guards: catalog '$catalog' declares a guards:/breadth: section but no entries parsed — check 2-space list / 4-space field indentation and that scalars are unquoted or double-quoted (single quotes and inline # comments are not supported). See doctrine/guard-catalog.md." >&2
fi

[ -n "$emit" ] || exit 0
printf '%s' "$emit" | sort
