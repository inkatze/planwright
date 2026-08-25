#!/bin/sh
# anchor-sweep.sh — recompute every bundle's content anchor and compare it
# against the one its kickoff brief records (format-grammar REQ-C1.4 · D-9).
#
# REQ-C1.4: any parser change that moves a shipped bundle's content anchor
# lands with an expression-only re-anchor sweep over the affected bundles in
# the SAME change, so no freshness gate trips on an unamended bundle. This is
# that sweep, and it asks exactly the question the gate will ask — does the
# recorded anchor still recompute? — so a clean run is the evidence that
# landing the change breaks no dispatch.
#
# It reports; it never writes. Deciding that a moved anchor is expression-only,
# and recording the paired entry, is the amendment ritual's business (a
# machine-written entry marked `Class: expression-only` citing its changelog
# line, doctrine/spec-format.md *Writers*), not a sweep's.
#
# Usage:
#   anchor-sweep.sh <specs-root | spec-dir>
#
# Output, one TAB-separated record per bundle:
#   ok           <spec>                    the recorded anchor recomputes
#   moved        <spec>  <recorded>  <now>  needs a paired re-anchor entry
#   unanchored   <spec>                    no brief, or no anchor entry in one
#   unparseable  <spec>                    an anchor entry with no digest
#   error        <spec>  <detail>          the anchor tool refused
#
# Exit codes: 0 nothing moved, 1 at least one moved anchor, 2 usage, 3 fail
# closed (an anchor-tool error or an unparseable entry — a bundle whose
# anchor could not be established is never reported as unchanged by omission).
#
# Portable: /bin/sh + awk + git, plus scripts/spec-anchor.sh. No eval; input
# treated as data only.
set -eu

LC_ALL=C
export LC_ALL

unset CDPATH
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

anchor_sh="$script_dir/spec-anchor.sh"
if [ ! -x "$anchor_sh" ]; then
  printf '%s\n' "anchor-sweep: $(sanitize_printable "$anchor_sh") missing or not executable" >&2
  exit 2
fi

[ $# -eq 1 ] || {
  echo "usage: anchor-sweep.sh <specs-root-or-spec-dir>" >&2
  exit 2
}
target=$1
[ -d "$target" ] || {
  printf '%s\n' "anchor-sweep: not a directory: $(sanitize_printable "$target")" >&2
  exit 2
}

tab=$(printf '\t')
moved=0
closed=0

# recorded_entry <brief> — print the brief's MOST RECENT anchor entry: the last
# `Anchor:` line plus the line after it, which is where the canonical two-line
# form keeps its command. Later entries supersede earlier ones, so a bundle a
# re-anchor already settled is not resurrected by its own history.
recorded_entry() {
  awk '
    /^Anchor:/ { n = NR }
    { line[NR] = $0 }
    END {
      if (!n) exit 1
      print line[n]
      if (n + 1 in line) print line[n + 1]
    }
  ' "$1"
}

# entry_digest — read an entry on stdin, print its 40-hex digest. Liberal about
# the surrounding punctuation on purpose: briefs carry the two shapes the
# format has used (a backticked hash followed by `— computed as`, and a bare
# hash with the command in parentheses), and the digest is the only field this
# sweep needs from either.
entry_digest() {
  awk '
    {
      n = split($0, t, /[^0-9a-f]+/)
      for (i = 1; i <= n; i++)
        if (length(t[i]) == 40) { print t[i]; exit }
    }
  '
}

# recompute <spec-dir> <entry> — recompute the anchor with the form the ENTRY
# recorded. Both sanctioned forms are honored (doctrine/spec-format.md,
# *Sanctioned command forms*): recomputing an interim whole-file entry with the
# canonical extraction would report every such bundle as moved, which is a
# false alarm about the one thing this sweep exists to detect truthfully.
recompute() {
  case $2 in
    *spec-anchor.sh*)
      "$anchor_sh" "$1"
      ;;
    *"git hash-object"*)
      # The interim form is defined relative to the bundle, and its own
      # failure must not be masked by the pipeline's last command.
      rc_files=$(cd "$1" \
        && git hash-object requirements.md design.md tasks.md test-spec.md) || return 1
      printf '%s\n' "$rc_files" | git hash-object --stdin
      ;;
    *)
      return 2
      ;;
  esac
}

sweep_bundle() {
  sb_dir=$1
  sb_name=$(basename "$sb_dir")
  sb_brief="$sb_dir/kickoff-brief.md"

  if [ ! -f "$sb_brief" ] || [ ! -r "$sb_brief" ]; then
    printf 'unanchored%s%s\n' "$tab" "$sb_name"
    return 0
  fi
  sb_entry=$(recorded_entry "$sb_brief") || {
    printf 'unanchored%s%s\n' "$tab" "$sb_name"
    return 0
  }
  sb_recorded=$(printf '%s\n' "$sb_entry" | entry_digest)
  if [ -z "$sb_recorded" ]; then
    printf 'unparseable%s%s\n' "$tab" "$sb_name"
    closed=1
    return 0
  fi

  sb_rc=0
  sb_now=$(recompute "$sb_dir" "$sb_entry" 2>"$gtmp/anchor.err") || sb_rc=$?
  if [ "$sb_rc" -eq 2 ]; then
    printf 'unparseable%s%s\n' "$tab" "$sb_name"
    closed=1
    return 0
  fi
  if [ "$sb_rc" -ne 0 ] || [ -z "$sb_now" ]; then
    printf 'error%s%s%s%s\n' "$tab" "$sb_name" "$tab" \
      "$(sanitize_printable "$(cat "$gtmp/anchor.err" 2>/dev/null)" "(no diagnostic)")"
    closed=1
    return 0
  fi

  if [ "$sb_recorded" = "$sb_now" ]; then
    printf 'ok%s%s\n' "$tab" "$sb_name"
  else
    printf 'moved%s%s%s%s%s%s\n' "$tab" "$sb_name" "$tab" "$sb_recorded" "$tab" "$sb_now"
    moved=1
  fi
}

gtmp=$(mktemp -d) || exit 2
trap 'rm -rf "$gtmp"' EXIT

is_bundle() {
  for ib_f in requirements.md design.md tasks.md test-spec.md; do
    [ -f "$1/$ib_f" ] || return 1
  done
  return 0
}

if is_bundle "$target"; then
  sweep_bundle "$target"
else
  # Glob iteration rather than `find | split`, matching spec-validate.sh: an
  # expansion result arrives as one word, so a name carrying a splittable byte
  # cannot fragment into phantom entries. Underscore-prefixed accumulators are
  # never bundles.
  for d in "$target"/*; do
    [ -d "$d" ] || continue
    case $(basename "$d") in
      _*) continue ;;
    esac
    is_bundle "$d" || continue
    sweep_bundle "$d"
  done
fi

[ "$closed" -eq 0 ] || exit 3
[ "$moved" -eq 0 ] || exit 1
exit 0
