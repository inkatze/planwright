#!/bin/sh
# resolve-card.sh — resolve a discipline card id to its card file through the
# `discipline-cards` catalog merge (inception Task 4; REQ-P1.10 · D-3, D-17).
#
# doctrine/discipline-cards.md (*Where cards live*) is the normative home of
# the layout. The catalog is merged across the four overlay layers by
# scripts/resolve-catalog.sh; the layer that supplies an entry supplies its
# card, so a team card is overlay content and a supersede-by-id ships its own
# file. Per-layer card locations:
#   core           <core-root>/cards/<id>.md
#   adopter        <adopter-root>/cards/<id>.md
#   repo-tracked   <repo>/.claude/cards/<id>.md
#   machine-local  <repo>/.claude/cards.local/<id>.md
#
# Usage:
#   resolve-card.sh <card-id>   print the card file's canonical path
#   resolve-card.sh --list      print `<id><TAB><layer><TAB><path>` for every
#                               merged entry, in merged order
#
# Every id, the argument and each one the merged catalog yields, is checked
# against the identifier charset before it reaches a path, and each card path
# goes through resolve-overlay-root.sh --contain, so a card symlinked out of
# its layer root is never returned.
#
# A layer that lists an id but holds no usable card file fails the lookup in
# every layer, never falling back to a lower layer's card: unlike the catalog
# merge's by-layer degrade, a fallback would hand back a card other than the
# one the merged catalog names (doctrine/discipline-cards.md).
#
# Exit: 0 resolved (for --list: every entry resolved) · 1 not found, no card
#   file, a refused path, or a catalog hard-fail · 2 usage or invalid id.
#
# Portable POSIX sh; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: resolve-card.sh <card-id> | --list" >&2
  exit 2
}

valid_id() {
  case $1 in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

[ "$#" -eq 1 ] || usage
want=$1
case $want in
  --list) ;;
  -*) usage ;;
  *)
    valid_id "$want" || {
      echo "resolve-card: invalid card id (must match ^[a-z0-9][a-z0-9-]*\$, max 64)" >&2
      exit 2
    }
    ;;
esac

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
catalog="$script_dir/resolve-catalog.sh"
overlay_root="$script_dir/resolve-overlay-root.sh"
for helper in "$catalog" "$overlay_root"; do
  if [ ! -r "$helper" ]; then
    printf '%s\n' "resolve-card: helper not found or unreadable at $helper (broken install)" >&2
    exit 1
  fi
done

explain=$(/bin/bash "$catalog" discipline-cards --explain) || exit 1

# card_path <id> <layer>: print the contained card path, or explain on stderr
# why there is none and return 1.
card_path() {
  case $2 in
    core | adopter | repo-tracked) rel="cards/$1.md" ;;
    machine-local) rel="cards.local/$1.md" ;;
    *)
      printf '%s\n' "resolve-card: $1: unknown layer from the catalog merge" >&2
      return 1
      ;;
  esac
  root=$(/bin/sh "$overlay_root" "$2") || return 1
  if [ -z "$root" ]; then
    printf '%s\n' "resolve-card: $1: the $2 layer is absent" >&2
    return 1
  fi
  if [ ! -f "$root/$rel" ]; then
    printf '%s\n' "resolve-card: $1: the $2 layer lists it but has no card file at $rel" >&2
    return 1
  fi
  if [ ! -r "$root/$rel" ]; then
    printf '%s\n' "resolve-card: $1: the $2 card file is unreadable; refused" >&2
    return 1
  fi
  # The helper's own refusal text stays silent: it can carry an unsanitized
  # path, and the message below names the card.
  contained=$(/bin/sh "$overlay_root" --contain "$root" "$rel" 2>/dev/null) || {
    printf '%s\n' "resolve-card: $1: the $2 card file does not resolve inside its layer root; refused" >&2
    return 1
  }
  # The canonical path follows symlinks, so a contained target's name can
  # still carry terminal control bytes; such a path is never printed.
  case $contained in
    *[[:cntrl:]]*)
      printf '%s\n' "resolve-card: $1: the $2 card file's canonical path carries a control byte; refused" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$contained"
}

tab=$(printf '\t')
rc=0
found=0
# A malformed merged entry (an id outside the charset, a field more than
# <id> and <layer>, an unknown layer) fails --list; a single-id lookup answers
# for its own id only.
while IFS="$tab" read -r id layer extra; do
  [ -n "$id" ] || continue
  malformed=
  valid_id "$id" || malformed="an id outside the charset"
  [ -z "$malformed" ] && [ -n "$extra" ] && malformed="a field too many"
  if [ -z "$malformed" ]; then
    case $layer in
      core | adopter | repo-tracked | machine-local) ;;
      *) malformed="an unknown layer" ;;
    esac
  fi
  if [ -n "$malformed" ]; then
    if [ "$want" = "--list" ]; then
      printf '%s\n' "resolve-card: skipping a catalog entry with $malformed" >&2
      rc=1
    fi
    continue
  fi
  if [ "$want" = "--list" ]; then
    if path=$(card_path "$id" "$layer"); then
      printf '%s\t%s\t%s\n' "$id" "$layer" "$path"
    else
      rc=1
    fi
  elif [ "$id" = "$want" ]; then
    found=1
    card_path "$id" "$layer" || rc=1
    break
  fi
done <<EOF
$explain
EOF

if [ "$want" != "--list" ] && [ "$found" -eq 0 ]; then
  printf '%s\n' "resolve-card: $want: not in the merged discipline-cards catalog" >&2
  exit 1
fi
exit "$rc"
