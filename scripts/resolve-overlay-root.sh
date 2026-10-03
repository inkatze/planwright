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
#     Prints the resolved root path on stdout and exits 0. The core and
#     repo-side roots come from resolve-root.sh and are canonical. An explicit
#     adopter override ($PLANWRIGHT_ADOPTER_OVERLAY, $CLAUDE_PLUGIN_DATA) is
#     used verbatim and trusted: it is echoed as given (joined to the layer's
#     suffix), so a caller that needs an absolute result must pass an absolute
#     override. $PLANWRIGHT_REPO_ROOT is honoured only when it names a git
#     toplevel (resolve-root.sh validates it); any other value is refused on
#     stderr and the repo-side layers are absent. Callers set it to none to
#     read no repo-side layer at all. Two cases skip that validation and use
#     a value other than none as given: $PLANWRIGHT_REPO_ROOT_CHECKED holding
#     the same absolute value (set only by planwright's own scripts, for a
#     root they have just validated), and a broken install with no root
#     helper to validate it.
#     When the layer is legitimately absent (adopter namespace underivable;
#     no repo for the repo-side layers), prints nothing and exits 0 — an
#     absent overlay layer is a normal state, never an error (REQ-A1.4).
#
#   resolve-overlay-root.sh --contain <root> <relpath>
#     Join <relpath> (a path relative to <root>) onto <root>, canonicalize, and
#     confirm it resolves under <root> (D-8, REQ-E1.5). Prints the canonical path
#     and exits 0 when contained; rejects an escaping path — an absolute <relpath>,
#     a ../ traversal, or a symlink that escapes after canonicalization — with a
#     clear message and exit 2. An absolute candidate is rejected up front (it
#     bypasses the root join entirely) even when it would resolve inside the root.
#     The shared canonicalize-then-contain helper the doctrine resolver (Task 4)
#     calls before any overlay read.
#
# Layer roots (D-3, D-4):
#   core           the planwright install root holding config/, doctrine/,
#                  catalogs/: `resolve-root.sh install`, the core root chain.
#   adopter        per-operator, cross-repo, per-plugin namespace. Chain (first
#                  derivable wins): $PLANWRIGHT_ADOPTER_OVERLAY (explicit
#                  override) → $CLAUDE_PLUGIN_DATA/overlay (plugin mode; the
#                  plugin-data id IS the namespace, update-stable) →
#                  <claude-dir>/planwright/<name>/overlay (writer mode, where
#                  <name> is the plugin manifest `name`, charset-validated).
#   repo-tracked   <repo>/.claude (the tracked team overlay root).
#   machine-local  <repo>/.claude (same root; the gitignored .local-suffixed
#                  files/dirs the kind resolver selects distinguish it, D-4).
#                  <repo> is `resolve-root.sh repo --primary`: the primary
#                  checkout, so a linked worktree reads the primary's layers,
#                  or a PLANWRIGHT_REPO_ROOT naming a git toplevel. No
#                  repository (or PLANWRIGHT_REPO_ROOT=none) → layer absent.
#
# <claude-dir> is $CLAUDE_DIR when set, else $HOME/.claude; the writer arm is
# skipped when neither is set.
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
      *)
        # Resolve a relative target against the link's directory. Strip a
        # trailing slash from that directory so a link directly under "/"
        # (dirname "/") joins to "/target", not "//target" — a leading "//" is
        # implementation-defined in POSIX and some platforms preserve it
        # through pwd -P (e.g. /bin -> usr/bin on usr-merged Linux yielded
        # "//usr/bin"). Mirrors the %/-strip the file-fallback and repo arms use.
        cp_d=$(dirname -- "$cp_p")
        cp_p="${cp_d%/}/$cp_t"
        ;;
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
    echo "usage: resolve-overlay-root.sh --contain <root> <relpath>" >&2
    exit 2
  fi
  if [ ! -d "$root" ]; then
    echo "planwright: overlay root '$root' is not a directory" >&2
    exit 2
  fi
  # An override path is relative to the overlay root by contract (D-8,
  # REQ-E1.5): the helper owns the root join so a caller cannot supply a path
  # that bypasses confinement. An absolute candidate ignores the root entirely,
  # so it is rejected up front as a path-escape — even one that would happen to
  # resolve inside the root.
  case $cand in
    /*)
      echo "planwright: path '$cand' is absolute; --contain requires a path relative to overlay root '$root'" >&2
      exit 2
      ;;
  esac
  canon_root=$(canon_path "$root") || {
    echo "planwright: cannot resolve overlay root '$root'" >&2
    exit 2
  }
  # Join the relative candidate onto the root before canonicalizing, so a ../
  # traversal or an escaping symlink resolves against the root and is caught by
  # the containment check below. Strip a trailing slash from the root so a root
  # of "/" joins to "/leaf", not "//leaf" (a leading "//" is implementation-
  # defined in POSIX), mirroring canon_path's own join.
  canon_cand=$(canon_path "${root%/}/$cand") || {
    echo "planwright: cannot resolve path '$cand' under overlay root '$root' (its parent directory could not be resolved, or a symlink chain ran away)" >&2
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
  echo "       resolve-overlay-root.sh --contain <root> <relpath>" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
root_helper="$script_dir/resolve-root.sh"

# Writer-mode claude dir: derivable only when CLAUDE_DIR or HOME is present.
claude_dir=""
if [ -n "${CLAUDE_DIR:-}" ]; then
  claude_dir="$CLAUDE_DIR"
elif [ -n "${HOME:-}" ]; then
  claude_dir="$HOME/.claude"
fi

# A missing helper is a broken install: every layer it locates degrades to
# absent, said once, and the kind resolver surfaces what went missing. An
# explicit repo root is not located by it, so the repo-side layers keep it,
# unvalidated, since validating it is the helper's job. Readable is enough: it
# runs through /bin/sh, so a copy that lost the execute bit still resolves.
if [ ! -r "$root_helper" ]; then
  case ${PLANWRIGHT_REPO_ROOT:-} in
    none) rr_pin=none ;;
    "") rr_pin="" ;;
    *) rr_pin=pinned ;;
  esac
  case $layer:$rr_pin in
    repo-tracked:none | machine-local:none) exit 0 ;;
    repo-tracked:pinned | machine-local:pinned)
      printf '%s\n' "${PLANWRIGHT_REPO_ROOT%/}/.claude"
      exit 0
      ;;
    core:* | repo-tracked: | machine-local:)
      echo "planwright: WARNING root helper '$root_helper' is missing or unreadable; the $layer overlay layer is treated as absent" >&2
      exit 0
      ;;
  esac
fi

case $layer in
  core)
    # The helper's own warnings (a skipped content-less arm) pass through. No
    # arm resolving is a broken install: degrade to absent rather than erroring.
    core_root=$(/bin/sh "$root_helper" install) || exit 0
    printf '%s\n' "$core_root"
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
        # Read the TOP-LEVEL "name" string. Scan the manifest tracking brace
        # depth and take the first `"name": "value"` that sits at depth 1, so a
        # nested object's name (e.g. author.name) is never mistaken for the
        # plugin name even when it appears earlier in the file. Matches both
        # pretty-printed and compact manifests and never matches a key like
        # "displayName" (the `"name"` token is quote-anchored). Assumes the key
        # and its value sit on one line (every JSON serializer emits this) and
        # that string values carry no literal braces — true for this manifest;
        # full JSON parsing stays out of scope, the runtime is dependency-free
        # (no jq), REQ-K1.5.
        name=$(awk '
          {
            line = $0
            while (match(line, /[{}]|"name"[ \t]*:[ \t]*"[^"]*"/)) {
              tok = substr(line, RSTART, RLENGTH)
              if (tok == "{") depth++
              else if (tok == "}") depth--
              else if (depth == 1 && val == "") {
                val = tok
                sub(/^"name"[ \t]*:[ \t]*"/, "", val)
                sub(/".*$/, "", val)
              }
              line = substr(line, RSTART + RLENGTH)
            }
          }
          END { if (val != "") print val }
        ' "$manifest")
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

  # scripts/worker-command-guard.sh's step_name_cataloged reads the
  # machine-local catalog under the repo-tracked root on the strength of this
  # shared arm; they change together.
  repo-tracked | machine-local)
    # Both repo-side layers live under <repo>/.claude (D-4); the kind resolver
    # selects the tracked vs .local-suffixed file/dir within it. No repository
    # (exit 3 outside any git directory, or asked for with none) is the normal
    # absent state and stays quiet; any other failure, a refused override and
    # a bare repository's worktree included, is re-run so its diagnostic
    # reaches stderr.
    # none needs no lookup: answered here, before any process is spawned.
    [ "${PLANWRIGHT_REPO_ROOT:-}" != none ] || exit 0
    # A pin a resolver has already validated arrives with
    # PLANWRIGHT_REPO_ROOT_CHECKED set to the same value (an internal
    # handshake between planwright's own scripts): taken as given, so a
    # chain of child lookups validates the root once, not once per layer.
    case ${PLANWRIGHT_REPO_ROOT:-} in
      /*)
        if [ "$PLANWRIGHT_REPO_ROOT" = "${PLANWRIGHT_REPO_ROOT_CHECKED:-}" ]; then
          printf '%s\n' "${PLANWRIGHT_REPO_ROOT%/}/.claude"
          exit 0
        fi
        ;;
    esac
    rr_rc=0
    repo_root=$(/bin/sh "$root_helper" repo --primary 2>/dev/null) || rr_rc=$?
    if [ "$rr_rc" -ne 0 ]; then
      if [ "$rr_rc" -ne 3 ] || git rev-parse --git-dir >/dev/null 2>&1; then
        /bin/sh "$root_helper" repo --primary >/dev/null
      fi
      exit 0
    fi
    # Strip a trailing slash so a repo root of "/" yields "/.claude", not
    # "//.claude" (a leading "//" is implementation-defined in POSIX).
    printf '%s\n' "${repo_root%/}/.claude"
    exit 0
    ;;

  *)
    echo "planwright: unknown overlay layer '$layer' (expected core|adopter|repo-tracked|machine-local)" >&2
    exit 2
    ;;
esac
