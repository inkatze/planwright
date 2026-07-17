#!/usr/bin/env bash
# resolve-rule-doc.sh — print the absolute path of a planwright rule doc,
# resolved through the four-layer overlay precedence (REQ-I1.1, D-24; the
# doctrine-overlay arm: REQ-A1.2, REQ-B1.2, REQ-B1.4, REQ-B1.6, REQ-B1.7,
# REQ-D1.2, REQ-E1.4, REQ-E1.5; D-4, D-5, D-7, D-8, D-9, D-11).
#
# This is the stable rule-doc resolution path: skills and hooks resolve
# externalized doctrine docs through one convention that works in both delivery
# modes, with no mode detection. Doctrine overlays merge by whole-doc shadow
# (D-5): the highest-precedence layer that supplies a doc of a given name wins
# in full — no fragment or section merge.
#
# Usage:
#   resolve-rule-doc.sh [--explain] <doc-name>
#   <doc-name> is the doc's basename, with or without the .md suffix,
#   matching ^[a-z0-9][a-z0-9-]*$ (the REQ-A1.8 identifier discipline).
#   --explain prints "<layer>\t<path>" (the supplying layer, then the resolved
#   path, tab-separated) instead of the bare path (D-9 provenance). <layer> is
#   one of: machine-local | repo-tracked | adopter | core.
#
# Resolution order (highest precedence first; first hit wins, whole-doc shadow):
#   1. machine-local  <repo>/.claude/doctrine.local/<name>.md
#   2. repo-tracked   <repo>/.claude/doctrine/<name>.md
#   3. adopter        <adopter-overlay-root>/doctrine/<name>.md
#   4. core           the core chain (first hit wins):
#        a. $PLANWRIGHT_ROOT/doctrine/        explicit override (tests, adopters)
#        b. $CLAUDE_PLUGIN_ROOT/doctrine/     plugin delivery (set by Claude Code)
#        c. <claude-dir>/planwright/doctrine/ writer delivery
#           (<claude-dir> is $CLAUDE_DIR when set, else ~/.claude; this arm is
#           skipped when neither CLAUDE_DIR nor HOME is set, so HOME-less
#           environments resolve via arms a-b and d only)
#        d. <script-dir>/../doctrine/         self-location (final fallback):
#           the core doctrine ships beside this script, so it resolves relative
#           to $0 when every env arm above misses — the case where Claude Code
#           does not export CLAUDE_PLUGIN_ROOT into a skill's Bash subshell.
#           Additive and lowest-precedence, so it never overrides an env root.
#
# The three overlay-layer roots come from scripts/resolve-overlay-root.sh (the
# Task 2 primitive), which owns layer-location and namespace logic; this script
# only inserts them into the precedence chain. Every overlay doc path is run
# through that helper's canonicalize-then-contain check before any read (D-8,
# REQ-E1.5): a path escaping its overlay root (`../`, absolute, or an escaping
# symlink) is rejected and never read.
#
# Malformed-by-layer (D-7, REQ-E1.4): an overlay doc path that exists but is not
# a readable regular file (a directory, an unreadable file) is malformed for the
# doctrine kind. A malformed adopter or machine-local overlay degrades to the
# next lower layer with a loud stderr warning; a malformed repo-tracked
# (team-shared) overlay hard-fails — a broken shared overlay must never degrade
# silently.
#
# Protected-doc shadow (D-11, REQ-B1.7): when an overlay layer supplies one of
# the protected core governance/security docs, resolution still succeeds
# (warn-but-allow — the operator owns their fork) but a loud stderr warning
# fires, naming the doc and the risk. Shadowing a non-protected doc is silent.
# D-11 is the single normative source of the protected set; PROTECTED_DOCS below
# is the operative copy.
#
# Exit codes: 0 found (path or "<layer>\t<path>" on stdout); 1 not found in any
#   layer; 2 usage / invalid name / path-traversal escape; 3 malformed
#   repo-tracked overlay (hard-fail, D-7).
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale: [a-z] range globs are collation-dependent and would
# otherwise admit uppercase under UTF-8 locales.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo the destination into the command
# substitution that derives the script dir (house pattern).
unset CDPATH

# --explain provenance flag (D-9). Accepted as the leading argument.
explain=0
if [ "${1:-}" = "--explain" ]; then
  explain=1
  shift
fi

name="${1:-}"
if [ -z "$name" ]; then
  echo "usage: resolve-rule-doc.sh [--explain] <doc-name>" >&2
  exit 2
fi

# Strip an optional .md suffix, then validate the bare name before it is
# interpolated into any path (REQ-D1.6 framework-script security). The charset
# already forbids `/` and `..`, so the doc name itself cannot traverse; the
# overlay symlink surface is what the containment check below guards.
name="${name%.md}"
case "$name" in
  *[!a-z0-9-]* | -* | "")
    echo "planwright: invalid rule-doc name '$1' (must match ^[a-z0-9][a-z0-9-]*$)" >&2
    exit 2
    ;;
esac

# The normative D-11 protected core governance/security docs. D-11 is the single
# source; this list is the operative copy the resolver reads (REQ-B1.7 mirrors
# it for readability). The REQ-B1.7 test asserts each named doc resolves in core
# (R3), so a renamed/removed core doc that fell out of protection fails the test.
PROTECTED_DOCS="spec-format security-posture validation-rigor discovery-rigor finding-categorization gate-wiring"

is_protected() {
  case " $PROTECTED_DOCS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
overlay_helper="$script_dir/resolve-overlay-root.sh"
# The overlay helper ships beside this script and is invoked directly (below),
# so it must be executable. If it is missing or not executable (a broken/partial
# install), resolve core doctrine only rather than dropping overlays opaquely:
# warn once and continue (REQ-K1.6 graceful degradation). We test -x, not -f, so
# a present-but-non-executable helper takes the warn-and-degrade path instead of
# being treated as available and then silently failing every invocation below.
if [ ! -x "$overlay_helper" ]; then
  echo "planwright: WARNING overlay helper '$overlay_helper' not found or not executable; resolving core doctrine only (overlays unavailable)" >&2
  overlay_helper=""
fi

# emit <layer> <path> — print the resolved result and exit 0. Fires the
# protected-doc warning first when an overlay layer shadows a protected core doc
# (D-11 warn-but-allow): the resolution still succeeds, but never silently.
emit() {
  em_layer=$1
  em_path=$2
  if [ "$em_layer" != "core" ] && is_protected "$name"; then
    echo "planwright: WARNING $em_layer overlay shadows protected core doc '$name' ($em_path); a framework-guarantee doc is being overridden — confirm this is intended (D-11)" >&2
  fi
  if [ "$explain" -eq 1 ]; then
    printf '%s\t%s\n' "$em_layer" "$em_path"
  else
    printf '%s\n' "$em_path"
  fi
  exit 0
}

# try_overlay <layer> <subdir> — attempt one overlay layer. On a usable hit it
# prints and exits 0 (via emit); a path escape exits 2; a malformed repo-tracked
# overlay exits 3. Otherwise it returns 0 so the caller falls through to the
# next-lower layer (the layer is absent, or a malformed adopter/machine-local
# overlay degrades with a warning).
try_overlay() {
  to_layer=$1
  to_subdir=$2
  [ -n "$overlay_helper" ] || return 0
  # Let the helper's own stderr through: it explains why a layer is absent (e.g.
  # an invalid plugin-manifest name dropping the adopter layer) or that the
  # helper itself failed (bad interpreter, lost permissions). An empty stdout is
  # the helper's normal "layer absent" signal, and a non-zero exit (a broken
  # helper) degrades this layer to absent rather than hard-failing the resolver
  # (REQ-K1.6 graceful degradation) — but never silently, now that the diagnostic
  # is visible.
  to_root=$("$overlay_helper" "$to_layer") || to_root=""
  [ -n "$to_root" ] || return 0 # layer absent (namespace/repo underivable)
  [ -d "$to_root" ] || return 0 # overlay root dir does not exist → layer absent
  to_rel="$to_subdir/$name.md"
  to_cand="$to_root/$to_rel"
  # Nothing at the path (not even a dangling symlink) → absent at this layer.
  if [ ! -e "$to_cand" ] && [ ! -L "$to_cand" ]; then
    return 0
  fi
  # Canonicalize-then-contain via the shared Task 2 helper (D-8, REQ-E1.5): a
  # `../`, absolute, or escaping-symlink path is rejected here and never read.
  if ! to_canon=$("$overlay_helper" --contain "$to_root" "$to_rel" 2>/dev/null); then
    echo "planwright: doctrine overlay path '$to_rel' in the $to_layer layer escapes its overlay root '$to_root' and was refused (path-traversal confinement; D-8, REQ-E1.5)" >&2
    exit 2
  fi
  # Contained. A usable doc must be a readable regular file.
  if [ -f "$to_canon" ] && [ -r "$to_canon" ]; then
    emit "$to_layer" "$to_canon"
  fi
  # Present but not a readable regular file → malformed for this kind (D-7).
  case $to_layer in
    repo-tracked)
      echo "planwright: repo-tracked doctrine overlay '$to_canon' is malformed (not a readable file); refusing to degrade a team-shared overlay silently (D-7, REQ-E1.4)" >&2
      exit 3
      ;;
    *)
      echo "planwright: WARNING $to_layer doctrine overlay '$to_canon' is malformed (not a readable file); degrading to the next lower layer (D-7, REQ-E1.4)" >&2
      return 0
      ;;
  esac
}

# Highest precedence first (whole-doc shadow): machine-local, then repo-tracked,
# then adopter. Each shares <repo>/.claude for the repo-side pair, distinguished
# by the doctrine.local/ vs doctrine/ subdir (D-4).
try_overlay machine-local doctrine.local
try_overlay repo-tracked doctrine
try_overlay adopter doctrine

# Core (lowest precedence): the three env-root arms (unchanged, REQ-D1.2 / R4
# no-regression) plus a final delivery-mode-agnostic self-location arm.
# Writer-mode root is derivable only when CLAUDE_DIR or HOME is present; plugin
# mode must keep working in HOME-less containers, so the earlier arms never
# depend on it.
#
# "$script_dir/.." is appended as the final, lowest-precedence arm: the core
# doctrine ships at $script_dir/../doctrine/, so the resolver can always locate
# it relative to its own path when no env root is set — the real-world case
# where Claude Code does not export CLAUDE_PLUGIN_ROOT into a skill's Bash
# subshell and nothing set PLANWRIGHT_ROOT. It is additive and only fires when
# every env arm misses, so it cannot regress any case where an env root
# resolves; it subsumes both the plugin-delivery and writer-delivery roots.
# This matches the self-location the sibling scripts (resolve-review-sequence,
# config-get, resolve-overlay-root, builder-guards) already use.
writer_root=""
if [ -n "${CLAUDE_DIR:-}" ]; then
  writer_root="$CLAUDE_DIR/planwright"
elif [ -n "${HOME:-}" ]; then
  writer_root="$HOME/.claude/planwright"
fi

for root in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" "$writer_root" "$script_dir/.."; do
  [ -n "$root" ] || continue
  if [ -f "$root/doctrine/$name.md" ]; then
    emit core "$root/doctrine/$name.md"
  fi
done

echo "planwright: rule doc '$name' not found (checked overlays then core: PLANWRIGHT_ROOT='${PLANWRIGHT_ROOT:-unset}', CLAUDE_PLUGIN_ROOT='${CLAUDE_PLUGIN_ROOT:-unset}', writer root='${writer_root:-unset: CLAUDE_DIR and HOME both missing}', self-located root='$script_dir/..')" >&2
exit 1
