#!/usr/bin/env bash
# check-doc-links.sh — prose cross-reference link-check (Task 2, REQ-G1.7).
#
# The doctrine docs reference each other by relative markdown links; a renamed
# or deleted target must fail CI rather than rot silently. Each inline
# [text](target) link in the given markdown files is resolved against the
# linking file's own directory; a missing target is an error.
#
# Usage: check-doc-links.sh [<file.md>...]
#   With no arguments, scans the repo's curated prose: README.md,
#   doctrine/*.md, docs/*.md, and skills/ markdown recursively (the
#   lint:md scope minus specs, whose cross-references are validated by
#   the spec validator, Task 5).
#
# Skipped link forms: http(s):// and mailto:. A #fragment (anchor) — whether on
# a file link (file.md#sec) or same-page (#sec) — IS verified: the fragment must
# match a heading in the target markdown file under GitHub's heading-slug rule
# (lowercase; drop chars outside [a-z0-9 _-]; spaces -> hyphens; trim leading and
# trailing hyphens; internal repeats are kept). Anchors on non-.md targets are
# not checked.
#
# Known anchor limitations (the slug rule is deliberately a subset of GitHub's;
# none occur in this repo's docs, and a future link that hits one fails closed,
# i.e. reported as broken, never silently passed):
#   - Duplicate-heading disambiguation is NOT applied. GitHub suffixes repeated
#     slugs (#sec, #sec-1, #sec-2, ...); this checker emits the base slug for
#     every heading, so a link to the second-or-later instance (#sec-1) is
#     reported as a missing anchor.
#   - Fragments are matched literally, not percent-decoded. A URL-encoded anchor
#     (#a%20section) will not match the decoded heading slug (a-section).
# Parser constraints (documented, like check-options-reference.sh):
# inline one-line links only — reference-style definitions and links wrapped
# across lines are invisible to it; ATX (#) headings only, and heading-like lines
# inside fenced code blocks are counted as headings (this only makes the anchor
# check more lenient, never falsely failing a valid anchor).
#
# Exit codes: 0 all targets resolve, 1 broken link found, 2 usage error.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale so bracket expressions mean exactly their ASCII range on
# every host (defensive; mirrors check-options-reference.sh).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitutions below and
# corrupt the path derivations.
unset CDPATH

# heading_slugs <file> — emit one GitHub-style anchor slug per ATX heading.
# Used to verify #fragment link targets. See the slug rule in the header.
heading_slugs() {
  awk '
    /^#{1,6}[ \t]/ {
      line = $0
      sub(/^#{1,6}[ \t]+/, "", line)      # strip the leading marker
      sub(/[ \t]+#+[ \t]*$/, "", line)    # strip a closing-ATX run (## Foo ##)
      s = tolower(line)
      gsub(/[^a-z0-9 _-]/, "", s)         # keep alnum, space, underscore, hyphen
      gsub(/ /, "-", s)                   # spaces -> hyphens (no collapse)
      sub(/^-+/, "", s); sub(/-+$/, "", s)
      if (s != "") print s
    }
  ' "$1"
}

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=("$repo_root/README.md")
  for f in "$repo_root"/doctrine/*.md "$repo_root"/docs/*.md; do
    [ -f "$f" ] && files=("${files[@]}" "$f")
  done
  # skills/ is scanned recursively (find, since bash 3.2 has no globstar)
  # to match lint:md's skills/**/*.md scope at any depth: nested skill
  # docs must not be linted-but-unlinked.
  if [ -d "$repo_root/skills" ]; then
    while IFS= read -r f; do
      files=("${files[@]}" "$f")
    done < <(find "$repo_root/skills" -type f -name '*.md' | sort)
  fi
fi

for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    echo "check-doc-links: input file not found: $f" >&2
    exit 2
  fi
  # A file the checker cannot scan must not be reported as "all resolve".
  if [ ! -r "$f" ]; then
    echo "check-doc-links: input file not readable: $f" >&2
    exit 2
  fi
done

status=0
checked=0

for f in "${files[@]}"; do
  dir="$(cd "$(dirname "$f")" && pwd -P)"
  # Each inline link's target: grep -o isolates every [text](target) on a
  # line, sed keeps the parenthesized part. Targets contain no spaces or
  # nested parens in this repo's prose; both are documented constraints.
  # -a forces text mode so a stray NUL byte does not make grep emit
  # "Binary file ... matches" as a bogus target.
  targets="$(grep -a -o '\[[^]]*\]([^)]*)' "$f" 2>/dev/null \
    | sed 's/^\[[^]]*\](\([^)]*\))$/\1/')"
  [ -z "$targets" ] && continue
  while IFS= read -r target; do
    case "$target" in
      http://* | https://* | mailto:*) continue ;;
    esac
    path="${target%%#*}"
    case "$target" in
      *'#'*) frag="${target#*#}" ;;
      *) frag="" ;;
    esac
    # File part: resolve it relative to the linking file (unless this is a
    # pure same-page #anchor, where the anchor's file is the linking file).
    if [ -n "$path" ]; then
      checked=$((checked + 1))
      if [ ! -e "$dir/$path" ]; then
        echo "check-doc-links: $f links to missing target: $path" >&2
        status=1
        continue
      fi
      anchor_file="$dir/$path"
    else
      anchor_file="$f"
    fi
    # Anchor part: a #fragment must match a heading in the target .md file.
    # Only markdown targets carry verifiable anchors; others are left alone.
    [ -z "$frag" ] && continue
    case "$anchor_file" in
      *.md)
        [ -f "$anchor_file" ] || continue
        checked=$((checked + 1))
        if ! heading_slugs "$anchor_file" | grep -Fxq -- "$frag"; then
          where="${path:-$(basename "$f")}"
          echo "check-doc-links: $f links to missing anchor #$frag in $where" >&2
          status=1
        fi
        ;;
    esac
  done <<EOF
$targets
EOF
done

if [ "$status" -eq 0 ]; then
  echo "check-doc-links: all $checked links and anchors resolve"
fi
exit "$status"
