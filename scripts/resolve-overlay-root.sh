#!/usr/bin/env bash
# resolve-overlay-root.sh — resolve one overlay layer's root directory, the
# foundational primitive the three per-kind resolvers (config, doctrine,
# catalog) share (Task 2; D-1, D-3, D-4, D-8).
#
# planwright defines four overlay layers in fixed precedence, lowest to
# highest (REQ-A1.1): core defaults < adopter overlay < repo-tracked overlay <
# machine-local overlay. Each kind keeps its native mechanism and per-layer
# location (D-2, D-4); this script answers one question — "where is layer L's
# root?" — so no per-kind resolver rolls its own layer location logic.
#
# Usage:
#   resolve-overlay-root.sh <layer>
#     <layer> is one of: core | adopter | repo-tracked | machine-local
#     Prints the resolved absolute root path on stdout and exits 0. When the
#     layer is legitimately absent (adopter namespace underivable; no repo for
#     the repo-side layers), prints nothing and exits 0 — an absent overlay
#     layer is a normal state, never an error (REQ-A1.4).
#
#   resolve-overlay-root.sh --contain <root> <path>
#     Canonicalize <path> and confirm it resolves under <root> (D-8, REQ-E1.5).
#     Prints the canonical path and exits 0 when contained; rejects a path
#     escaping the root (../, absolute, or symlink-escape) with a clear message
#     and exit 2. The shared canonicalize-then-contain helper the doctrine
#     resolver (Task 4) calls before any overlay read.
#
# Layer roots (D-3, D-4):
#   core           the planwright install root holding config/, doctrine/,
#                  catalogs/. Chain (first existing wins): $PLANWRIGHT_ROOT →
#                  $CLAUDE_PLUGIN_ROOT → <claude-dir>/planwright → scripts/..
#   adopter        per-operator, cross-repo, per-plugin namespace. Chain (first
#                  derivable wins): $PLANWRIGHT_ADOPTER_OVERLAY (explicit
#                  override) → $CLAUDE_PLUGIN_DATA/overlay (plugin mode; the
#                  plugin-data id IS the namespace, update-stable) →
#                  <claude-dir>/planwright/<name>/overlay (writer mode, where
#                  <name> is the plugin manifest `name`, charset-validated).
#   repo-tracked   <repo>/.claude (the tracked team overlay root).
#   machine-local  <repo>/.claude (same root; the gitignored .local-suffixed
#                  files/dirs the kind resolver selects distinguish it, D-4).
#                  <repo> is $PLANWRIGHT_REPO_ROOT, else `git rev-parse
#                  --show-toplevel`; absent (no repo) → layer absent.
#
# <claude-dir> is $CLAUDE_DIR when set, else $HOME/.claude; the writer arm is
# skipped when neither is set (HOME-less containers resolve via the earlier
# arms, mirroring resolve-rule-doc.sh).
#
# Exit codes: 0 resolved (path on stdout) or layer absent (empty stdout);
#   2 usage / invalid layer / path-escape.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale: [a-z] range globs are collation-dependent and would
# otherwise admit uppercase under UTF-8 locales (mirrors the sibling scripts).
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo the destination into the command
# substitutions that derive paths below (house pattern).
unset CDPATH

# The overlay identifier charset (REQ-E1.2, REQ-A1.8): a kebab token, no
# uppercase, no traversal segments, no leading dash, at most 64 chars.
valid_identifier() {
  vi_n=$1
  case $vi_n in
    "" | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#vi_n}" -le 64 ]
}

# canon_path <path> — print the canonical absolute path, resolving symlinks
# (including a final-component symlink) and `..` segments. The path's deepest
# component need not exist, but its parent directory must. Returns 1 when the
# parent cannot be resolved or a symlink chain runs away.
canon_path() {
  cp_p=$1
  cp_n=0
  while [ -L "$cp_p" ]; do
    cp_n=$((cp_n + 1))
    if [ "$cp_n" -gt 40 ]; then
      return 1
    fi
    cp_t=$(readlink -- "$cp_p") || return 1
    case $cp_t in
      /*) cp_p=$cp_t ;;
      *) cp_p=$(dirname -- "$cp_p")/$cp_t ;;
    esac
  done
  if [ -d "$cp_p" ]; then
    (cd -- "$cp_p" 2>/dev/null && pwd -P)
    return
  fi
  # A file (resolved above if it was a symlink) or a not-yet-existing leaf:
  # canonicalize the parent (which resolves any symlinks in the dir path) and
  # re-attach the basename. Strip a trailing slash from the canonical parent so a
  # parent resolving to "/" yields "/leaf", not "//leaf" (a leading "//" is
  # implementation-defined in POSIX). The '--' terminators keep a path beginning
  # with '-' from being read as a tool option.
  cp_d=$(cd -- "$(dirname -- "$cp_p")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "${cp_d%/}" "$(basename -- "$cp_p")"
}

# ---------------------------------------------------------------------------
# --contain mode
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--contain" ]; then
  root="${2:-}"
  cand="${3:-}"
  if [ -z "$root" ] || [ -z "$cand" ]; then
    echo "usage: resolve-overlay-root.sh --contain <root> <path>" >&2
    exit 2
  fi
  if [ ! -d "$root" ]; then
    echo "planwright: overlay root '$root' is not a directory" >&2
    exit 2
  fi
  canon_root=$(canon_path "$root") || {
    echo "planwright: cannot resolve overlay root '$root'" >&2
    exit 2
  }
  canon_cand=$(canon_path "$cand") || {
    echo "planwright: cannot resolve path '$cand' (no such parent directory)" >&2
    exit 2
  }
  # Contained iff canon_cand equals canon_root or sits under it. Build the
  # "under" prefix as "${canon_root%/}/" so the filesystem root "/" (the one
  # pwd -P value carrying a trailing slash) yields "/" rather than a "//*"
  # pattern that would reject real children; for any other root it strips no
  # slash and the boundary "/" still guards against a prefix-sharing sibling.
  under="${canon_root%/}/"
  case $canon_cand in
    "$canon_root" | "$under"*)
      printf '%s\n' "$canon_cand"
      exit 0
      ;;
    *)
      echo "planwright: path '$cand' escapes overlay root '$root' (resolved to '$canon_cand')" >&2
      exit 2
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# layer-root mode
# ---------------------------------------------------------------------------
layer="${1:-}"
if [ -z "$layer" ]; then
  echo "usage: resolve-overlay-root.sh <layer>   (core|adopter|repo-tracked|machine-local)" >&2
  echo "       resolve-overlay-root.sh --contain <root> <path>" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Writer-mode claude dir: derivable only when CLAUDE_DIR or HOME is present.
claude_dir=""
if [ -n "${CLAUDE_DIR:-}" ]; then
  claude_dir="$CLAUDE_DIR"
elif [ -n "${HOME:-}" ]; then
  claude_dir="$HOME/.claude"
fi

# <repo> for the two repo-side layers: an explicit override (tests, adopters,
# worktree callers), else the cwd's git toplevel. Absent → repo layers absent.
repo_root=""
if [ -n "${PLANWRIGHT_REPO_ROOT:-}" ]; then
  repo_root="$PLANWRIGHT_REPO_ROOT"
else
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root=""
fi

case $layer in
  core)
    for root in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" \
      "${claude_dir:+$claude_dir/planwright}" "$script_dir/.."; do
      [ -n "$root" ] || continue
      # Only a usable root wins: a candidate that exists but cannot be entered
      # (e.g. an unsearchable dir) is skipped so the loop falls through to the
      # next candidate rather than degrading core to absent.
      if [ -d "$root" ] && core_root=$(cd -- "$root" 2>/dev/null && pwd -P); then
        printf '%s\n' "$core_root"
        exit 0
      fi
    done
    # No usable core root exists — a broken install. Degrade to absent rather
    # than erroring; the kind resolver surfaces the missing core file.
    exit 0
    ;;

  adopter)
    # 1. Explicit override (tests, adopters): used verbatim, trusted.
    if [ -n "${PLANWRIGHT_ADOPTER_OVERLAY:-}" ]; then
      printf '%s\n' "$PLANWRIGHT_ADOPTER_OVERLAY"
      exit 0
    fi
    # 2. Plugin mode: the plugin-data dir IS the per-plugin namespace.
    if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
      printf '%s\n' "$CLAUDE_PLUGIN_DATA/overlay"
      exit 0
    fi
    # 3. Writer mode: derive the namespace from the manifest `name`.
    if [ -n "$claude_dir" ]; then
      manifest="$claude_dir/planwright/plugin.json"
      if [ -r "$manifest" ]; then
        # Read the top-level "name" string. Split on JSON structural commas and
        # braces first so each "key": value sits on its own line, then anchor
        # "name" at line start — this matches both pretty-printed and compact
        # manifests while never matching a key like "displayName". Assumes the
        # key and its value sit on one line (every JSON serializer emits this);
        # a hand-split "name":\n"value" reads as no name and degrades to absent,
        # which is safe (never a misparse). Full JSON parsing is out of scope —
        # the runtime stays dependency-free (no jq), REQ-K1.5.
        name=$(tr ',' '\n' <"$manifest" | tr '{' '\n' \
          | sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
          | head -1)
        if [ -n "$name" ]; then
          if valid_identifier "$name"; then
            printf '%s\n' "$claude_dir/planwright/$name/overlay"
            exit 0
          fi
          # A name that fails the charset is never interpolated into a path;
          # warn and degrade the adopter layer to absent (REQ-E1.2, F9).
          echo "planwright: plugin manifest name '$name' is not a valid identifier; adopter overlay treated as absent" >&2
        fi
      fi
    fi
    # No arm derivable: adopter layer absent (REQ-A1.5, REQ-A1.4).
    exit 0
    ;;

  repo-tracked | machine-local)
    # Both repo-side layers live under <repo>/.claude (D-4); the kind resolver
    # selects the tracked vs .local-suffixed file/dir within it.
    if [ -n "$repo_root" ]; then
      printf '%s\n' "$repo_root/.claude"
    fi
    exit 0
    ;;

  *)
    echo "planwright: unknown overlay layer '$layer' (expected core|adopter|repo-tracked|machine-local)" >&2
    exit 2
    ;;
esac
