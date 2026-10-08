#!/bin/sh
# config-get.sh — read planwright config values with the four-layer overlay
# precedence the customization mechanism defines (D-1, D-4, D-5; REQ-A1.1,
# REQ-B1.1). Extends the original two-layer (defaults + machine-local) model.
#
# The four layers, lowest to highest precedence (an absent layer degrades to
# the next lower; it is never an error, REQ-A1.4):
#   core          config/defaults.yml                    (tracked install base)
#   adopter       <adopter-root>/planwright.yml          (per-operator, cross-repo)
#   repo-tracked  <repo>/.claude/planwright.yml          (team-shared, committed)
#   machine-local <repo>/.claude/planwright.local.yml    (gitignored, per-machine)
# The three overlay-layer roots are resolved through the Task 2 primitive
# (scripts/resolve-overlay-root.sh), so this reader does not re-implement layer
# location logic. Config merges by last-layer-wins per key (D-5): the
# highest-precedence layer that sets the key wins; a lower layer still supplies
# any key the higher layers leave unset.
#
# The planwright config model is intentionally flat one-level `key: value`
# YAML, so a line-oriented reader is sufficient and keeps the runtime
# dependency-free (REQ-K1.5). The raw value is printed verbatim with a trailing
# comment and surrounding quotes stripped. Only a `#` led by whitespace (or
# opening the value) starts a comment, as in YAML, so `a#b` is kept whole and
# `a # c` reads as `a`; unlike YAML, quoting does not protect a whitespace-led
# `#`, so `"a #b"` still reads as `"a`. Type and range validation stay
# with the caller, since they are key-specific (the lock threshold normalizes
# `m`, a backend name is an enum, etc.).
#
# Malformed-overlay policy by layer (D-7, REQ-E1.4). "Malformed" for this kind
# means a path that exists at the overlay location but cannot serve as a flat
# `key: value` config: it is present but not a regular file (a directory or any
# non-file occupying the path), or is unreadable, or is not parseable as the
# flat `key: value` YAML the reader expects — a structural test, not a
# key-charset test: an indented (nested map/list) line, a bare list item, or
# any non-comment, non-marker line that is not an unindented `key: value` entry.
# A path that does not exist at all (including a dangling symlink, which `-e`
# reports absent) is simply an absent layer, not malformed.
# A flat entry whose key falls outside the queryable charset is simply ignored
# (like a comment), not malformed:
#   - a malformed adopter or machine-local overlay degrades to the next lower
#     layer with a loud stderr warning (blast radius is one operator/machine);
#   - a malformed repo-tracked (team-shared) overlay hard-fails with exit 4,
#     because silently degrading a broken shared config means a whole team runs
#     unintended behavior — surfaced loudly regardless of the queried key;
#   - the core defaults file is the tracked, tested install base, not a
#     user-supplied overlay, so the structural malformed test above is NOT
#     applied to it (REQ-E1.4 scopes that test to the overlay layers; D-7 keeps
#     core on the existing behavior). The broken install this reader surfaces
#     for core is a *missing or unreadable* defaults file — via the
#     broken-install diagnostic below; a readable-but-non-flat defaults file
#     simply misses keys and exits 3, the same as the original two-layer reader.
#
# Usage: config-get.sh [--explain | --layers] <key>
#        config-get.sh --layers <key> <key>...
#   <key> matches ^[a-z][a-z0-9_]*$ and is validated before it is ever
#   interpolated into a pattern (framework-script security, REQ-D1.6).
#   --explain (D-9, REQ-B1.6): instead of the bare value, print provenance —
#   the winning layer and value as a single tab-separated line on stdout:
#       <layer>\t<value>
#   where <layer> is one of core | adopter | repo-tracked | machine-local. The
#   exit codes are unchanged from the bare read. This line format is the pinned
#   provenance contract skills/humans may parse (risk R6).
#   --layers (custom-steps REQ-C1.1, D-5): the per-layer read. Print one
#   `<layer>\t<value>` line for EVERY well-formed layer that sets the key, in
#   precedence order lowest to highest (core, adopter, repo-tracked,
#   machine-local), so the last line is the merged winner and the lines above
#   it are the layers it shadows. A malformed adopter or machine-local layer is
#   skipped with the same warning the merged read emits; a malformed
#   repo-tracked layer hard-fails the same way. Exit codes as the bare read
#   (3 when no layer sets the key).
#   --layers <key> <key>...: the per-layer read of several keys in one run,
#   for a caller that would otherwise pay this reader's layer resolution once
#   per key. Each line is `<key>\t<layer>\t<value>`, the keys in argument
#   order, each key's lines exactly its own --layers read's; a key no layer
#   sets prints nothing, so absence is never an exit status (0, or 4 / 6 as
#   above, which print nothing on stdout); a key left unresolved by missing
#   core defaults is named on stderr. Only --layers takes several keys.
#
# Environment overrides (tests, adopters, worktree callers that know the
# primary checkout's paths):
#   PLANWRIGHT_CONFIG_DEFAULTS  explicit tracked-defaults (core) file
#   PLANWRIGHT_LOCAL_CONFIG     explicit machine-local file (legacy two-layer
#                               override; wins over the derived machine-local path)
#   PLANWRIGHT_CONFIG_STRICT_OVERLAYS  when 1, a malformed adopter or
#                               machine-local overlay the walk reaches exits 6
#                               instead of being skipped, for a caller whose
#                               lower layers may hold a permissive value; so
#                               does a layer setting the key as `key : v` or
#                               more than once (exit 4 when that layer is
#                               repo-tracked)
# Otherwise the core layer is config/defaults.yml under the first arm of the
# core root chain (resolve-root.sh install --all) holding one. The adopter
# and repo-side layer roots honor resolve-overlay-root.sh's own overrides
# (PLANWRIGHT_ADOPTER_OVERLAY, CLAUDE_PLUGIN_DATA, PLANWRIGHT_REPO_ROOT).
#
# Exit: 0 value printed; 3 key absent in every layer (never for several
# keys); 2 usage / invalid key;
# 4 malformed repo-tracked overlay (hard-fail); 6 malformed adopter or
# machine-local overlay, only under PLANWRIGHT_CONFIG_STRICT_OVERLAYS=1. Never
# fails opaquely.
set -u

# Pin the C locale: the [a-z] range checks below are collation-dependent and
# would otherwise admit uppercase under a UTF-8 locale.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo the destination into the command
# substitution that derives the script dir (house pattern).
unset CDPATH

# --explain and --layers are exclusive: only one leading flag is parsed.
explain=0
layers=0
case "${1:-}" in
  --explain)
    explain=1
    shift
    ;;
  --layers)
    layers=1
    shift
    ;;
esac

key="${1:-}"
if [ -z "$key" ]; then
  echo "usage: config-get.sh [--explain | --layers] <key>" >&2
  echo "       config-get.sh --layers <key> <key>..." >&2
  exit 2
fi
if [ $# -gt 1 ] && [ "$layers" -eq 0 ]; then
  echo "planwright: several config keys take --layers" >&2
  exit 2
fi
n_keys=$#
keys="$*"
for key in "$@"; do
  case "$key" in
    [a-z]*) ;;
    *)
      printf '%s\n' "planwright: invalid config key '$key' (must match ^[a-z][a-z0-9_]*\$)" >&2
      exit 2
      ;;
  esac
  case "$key" in
    *[!a-z0-9_]*)
      printf '%s\n' "planwright: invalid config key '$key' (must match ^[a-z][a-z0-9_]*\$)" >&2
      exit 2
      ;;
  esac
done

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Resolve the tracked defaults (core) file: an explicit override, else the
# first arm of the core root chain holding one. The resolver's warnings (a
# skipped content-less arm) pass through.
defaults=""
if [ -n "${PLANWRIGHT_CONFIG_DEFAULTS:-}" ]; then
  defaults="$PLANWRIGHT_CONFIG_DEFAULTS"
elif [ ! -r "$script_dir/resolve-root.sh" ]; then
  printf '%s\n' "config-get: warning: the root helper '$script_dir/resolve-root.sh' is missing or unreadable (broken install); the core defaults cannot be located" >&2
else
  while IFS= read -r root; do
    if [ -n "$root" ] && [ -f "$root/config/defaults.yml" ]; then
      defaults="$root/config/defaults.yml"
      break
    fi
  done <<ROOTS
$(/bin/sh "$script_dir/resolve-root.sh" install --all)
ROOTS
fi

# The Task 2 primitive is the single source of overlay-layer *locations* and must
# be present and executable. If it is missing or non-executable (a broken or
# partial install), warn ONCE here and treat every resolver-derived overlay layer
# as unavailable, degrading toward the core defaults — rather than emitting the
# same shell error on each of the overlay_root calls below (REQ-K1.6
# graceful degradation; mirrors the warn-once `-x` guard in resolve-rule-doc.sh).
# We test -x, not -f, so a present-but-non-executable helper takes the same
# warn-and-degrade path. Note this disables only the layers the resolver locates
# (adopter, repo-tracked, and the *derived* machine-local path); the legacy
# PLANWRIGHT_LOCAL_CONFIG override is an explicit path that never goes through the
# resolver, so a caller that sets it still gets its machine-local layer (the
# message says so, to avoid misleading an operator who relies on it).
overlay_resolver="$script_dir/resolve-overlay-root.sh"
overlay_resolver_ok=1
if [ ! -x "$overlay_resolver" ]; then
  printf '%s\n' "config-get: warning: overlay resolver '$overlay_resolver' is missing or not executable; resolver-derived overlay layers (adopter, repo-tracked, machine-local) are unavailable, resolving from core defaults (an explicit PLANWRIGHT_LOCAL_CONFIG override, if set, is still honored)" >&2
  overlay_resolver_ok=0
fi

# overlay_root <layer> -> the layer's root path (empty when the layer is absent
# or the resolver is unavailable), resolved through the Task 2 primitive. Its
# stderr is deliberately NOT suppressed: an absent layer is a normal state and
# resolves to empty stdout with a clean stderr, but the primitive can still emit
# a legitimate warning (e.g. a plugin manifest whose `name` is not a valid
# identifier degrades the adopter layer with a stderr warning). The upfront -x
# guard above means a missing/non-executable resolver is reported once, not once
# per call; a blanket 2>/dev/null would instead swallow the legitimate warnings,
# defeating this reader's "never fails opaquely" contract.
overlay_root() {
  [ "$overlay_resolver_ok" -eq 1 ] || return 0
  "$overlay_resolver" "$1"
}

# Adopter and repo-tracked config files (kind-native names under each layer
# root, D-4). An empty root means the layer is absent.
adopter_root=$(overlay_root adopter)
adopter_cfg=""
[ -n "$adopter_root" ] && adopter_cfg="$adopter_root/planwright.yml"

tracked_root=$(overlay_root repo-tracked)
tracked_cfg=""
[ -n "$tracked_root" ] && tracked_cfg="$tracked_root/planwright.yml"

# Machine-local config file: an explicit PLANWRIGHT_LOCAL_CONFIG (the legacy
# two-layer override, preserved) wins; otherwise it is derived from the
# machine-local overlay root, which the overlay resolver defines as the same
# directory as the repo-tracked one, so it is not resolved a second time.
mlocal_cfg=""
if [ -n "${PLANWRIGHT_LOCAL_CONFIG:-}" ]; then
  mlocal_cfg="$PLANWRIGHT_LOCAL_CONFIG"
else
  [ -n "$tracked_root" ] && mlocal_cfg="$tracked_root/planwright.local.yml"
fi

# malformed_config <file> -> 0 (malformed) / 1 (well-formed). The caller has
# already established something exists at the path (-e). Malformed means present
# but not a regular file (a directory, a botched mkdir, a merge artifact, any
# non-file occupying the overlay path), unreadable, or not parseable as flat
# one-level `key: value` YAML. The not-a-regular-file check comes first so the
# grep below is never handed a directory (grep without -r errors on one). The
# parse test is structural, not a key-charset test: the flat reader silently
# ignores any line it does not match (a comment, a key it is not asked for), so
# a flat entry whose key falls outside the queryable charset is still
# parseable-for-the-kind, not malformed. An offending line is one carrying
# structure the flat reader cannot represent: a non-blank, non-comment,
# non-document-marker line that is either indented (a nested map/list value) or
# has no colon (a bare list item or junk line) — i.e. not an unindented
# `key: value` entry. A document marker (--- / ...) may carry a trailing comment
# (`--- # note`), tolerated like a comment on any other line. The file's content
# is grepped against a fixed pattern — it
# is never executed, expanded, or used as a pattern itself (framework-script
# security: data is not code).
malformed_config() {
  mf="$1"
  [ -f "$mf" ] || return 0
  [ -r "$mf" ] || return 0
  # A YAML block-sequence item — a line whose first non-blank content is "- "
  # (or a bare "-") — makes the document (or a value) a sequence, not the flat
  # mapping this reader requires (REQ-E1.4: a mapping of keys to scalar or *inline*
  # list values, not a top-level or block sequence). It is malformed regardless of
  # any colon it carries, so it is checked before the structural test below (the
  # bare colon-bearing-line rule there would otherwise accept "- key: value"). An
  # inline flow list (`key: [a, b]`) is a normal key: value line and is unaffected
  # — it has no leading "- ".
  if grep -Eq '^[[:space:]]*-([[:space:]]|$)' "$mf" 2>/dev/null; then
    return 0
  fi
  if grep -Eqv \
    '^[[:space:]]*(#.*)?$|^(---|\.\.\.)[[:space:]]*(#.*)?$|^[^[:space:]].*:' \
    "$mf" 2>/dev/null; then
    return 0
  fi
  return 1
}

# get_value <file> <key>: on success set VALUE and return 0; return 1 when the
# file is absent or the key is not set. The key is pre-validated to the flat
# identifier charset, so it is regex-safe in the patterns below. One sed takes
# the first line setting the key, strips the comment, the trailing blanks, and
# one pair of surrounding quotes, and prints it behind a `=` so a key set to
# the empty value still reads as set.
VALUE=""
get_value() {
  gf="$1"
  gk="$2"
  [ -f "$gf" ] || return 1
  gv=$(sed -n "/^${gk}:/{
s/^${gk}:[[:space:]]*//
s/^#.*\$//
s/[[:space:]]#.*\$//
s/[[:space:]]*\$//
s/^\"\\(.*\\)\"\$/\\1/
s/^'\\(.*\\)'\$/\\1/
s/^/=/
p
q
}" "$gf" 2>/dev/null)
  [ -n "$gv" ] || return 1
  VALUE=${gv#=}
  return 0
}

# malformed_once <layer> <file>: malformed_config, judged once per layer, so a
# read of several keys walks the layers without re-testing each file. The
# verdicts and the skip warnings start unset whatever the environment holds.
# shellcheck disable=SC2034 # read through eval in malformed_once
malformed_mlocal=""
# shellcheck disable=SC2034 # read through eval in malformed_once
malformed_adopter=""
warned_mlocal=""
warned_adopter=""
malformed_once() {
  mo_v=""
  eval "mo_v=\${malformed_$1:-}"
  if [ -z "$mo_v" ]; then
    mo_v=1
    malformed_config "$2" && mo_v=0
    eval "malformed_$1=\$mo_v"
  fi
  return "$mo_v"
}

# strict_key_shape <file> <layer>: under PLANWRIGHT_CONFIG_STRICT_OVERLAYS=1,
# refuse a queried key that get_value would misread against YAML: `key : v`
# (YAML's key, the flat reader's no match) or a repeated key (YAML's last
# value, the flat reader's first). Exit 4 for the repo-tracked layer, 6 for
# the others, matching how a malformed file in that layer is reported.
strict_key_shape() {
  [ "${PLANWRIGHT_CONFIG_STRICT_OVERLAYS:-}" = 1 ] || return 0
  [ -f "$1" ] || return 0
  if ! grep -Eq "^${key}[[:space:]]+:" "$1" 2>/dev/null \
    && [ "$(grep -Ec "^${key}[[:space:]]*:" "$1" 2>/dev/null)" -le 1 ]; then
    return 0
  fi
  printf '%s\n' "config-get: $2 overlay '$1' sets '$key' with a space before the colon or more than once; the caller allows no skip" >&2
  [ "$2" = repo-tracked ] && exit 4
  exit 6
}

# emit <layer>: print the resolved value (bare) or its provenance (--explain),
# then exit 0. Called once a layer has supplied the key. Under --layers the
# line is collected instead (the layers are visited highest first, so the
# collected lines are prepended to come out lowest first) and the walk goes on.
layer_lines=""
emit() {
  if [ "$layers" -eq 1 ]; then
    layer_lines="$1	$VALUE
$layer_lines"
    return 0
  fi
  if [ "$explain" -eq 1 ]; then
    printf '%s\t%s\n' "$1" "$VALUE"
  else
    printf '%s\n' "$VALUE"
  fi
  exit 0
}

# Eager hard-fail: a malformed repo-tracked (team-shared) overlay is never
# silently degraded — surface it loudly regardless of which layer would win the
# queried key (D-7). Checked before resolution so a broken shared config cannot
# hide behind a higher layer happening to set the key.
if [ -n "$tracked_cfg" ] && [ -e "$tracked_cfg" ] && malformed_config "$tracked_cfg"; then
  printf '%s\n' "config-get: repo-tracked overlay '$tracked_cfg' is malformed (not flat 'key: value' YAML, or unreadable); refusing to silently degrade a shared team config" >&2
  exit 4
fi

# walk_key: resolve $key highest precedence first; the first present,
# well-formed layer that sets the key wins (last-layer-wins, D-5). A malformed
# adopter or machine-local overlay degrades to the next lower layer with a
# loud warning (D-7).
walk_key() {
  if [ -n "$mlocal_cfg" ] && [ -e "$mlocal_cfg" ]; then
    if malformed_once mlocal "$mlocal_cfg"; then
      if [ "${PLANWRIGHT_CONFIG_STRICT_OVERLAYS:-}" = 1 ]; then
        printf '%s\n' "config-get: machine-local overlay '$mlocal_cfg' is malformed (not flat 'key: value' YAML, or unreadable); the caller allows no skip" >&2
        exit 6
      fi
      [ -n "$warned_mlocal" ] \
        || printf '%s\n' "config-get: warning: machine-local overlay '$mlocal_cfg' is malformed (not flat 'key: value' YAML, or unreadable); skipping (degraded to next lower layer)" >&2
      warned_mlocal=1
    else
      strict_key_shape "$mlocal_cfg" machine-local
      if get_value "$mlocal_cfg" "$key"; then
        emit machine-local
      fi
    fi
  fi
  # repo-tracked is guaranteed well-formed here (eager-checked above if present).
  if [ -n "$tracked_cfg" ]; then
    strict_key_shape "$tracked_cfg" repo-tracked
    if get_value "$tracked_cfg" "$key"; then
      emit repo-tracked
    fi
  fi
  if [ -n "$adopter_cfg" ] && [ -e "$adopter_cfg" ]; then
    if malformed_once adopter "$adopter_cfg"; then
      if [ "${PLANWRIGHT_CONFIG_STRICT_OVERLAYS:-}" = 1 ]; then
        printf '%s\n' "config-get: adopter overlay '$adopter_cfg' is malformed (not flat 'key: value' YAML, or unreadable); the caller allows no skip" >&2
        exit 6
      fi
      [ -n "$warned_adopter" ] \
        || printf '%s\n' "config-get: warning: adopter overlay '$adopter_cfg' is malformed (not flat 'key: value' YAML, or unreadable); skipping (degraded to next lower layer)" >&2
      warned_adopter=1
    else
      strict_key_shape "$adopter_cfg" adopter
      if get_value "$adopter_cfg" "$key"; then
        emit adopter
      fi
    fi
  fi
  if [ -n "$defaults" ] && get_value "$defaults" "$key"; then
    emit core
  fi
}

# The several-key read prints only once every key has walked, so a key that
# fails the walk (exit 4 or 6) leaves nothing on stdout.
if [ "$n_keys" -gt 1 ]; then
  batch=""
  # The keys are validated identifiers, so the unquoted split is exact.
  for key in $keys; do
    layer_lines=""
    walk_key
    if [ -z "$layer_lines" ] && { [ -z "$defaults" ] || [ ! -r "$defaults" ]; }; then
      printf '%s\n' "config-get: tracked defaults not found (looked via PLANWRIGHT_CONFIG_DEFAULTS, then each arm of the core root chain: resolve-root.sh install --all --explain); '$key' unresolved" >&2
    fi
    while IFS= read -r line; do
      [ -z "$line" ] || batch="$batch$key	$line
"
    done <<EOF
$layer_lines
EOF
  done
  printf '%s' "$batch"
  exit 0
fi
walk_key

if [ "$layers" -eq 1 ] && [ -n "$layer_lines" ]; then
  printf '%s' "$layer_lines"
  exit 0
fi

# Key not found in any layer. If the tracked defaults file itself could not be
# located or read, that is a broken install (mis-set PLANWRIGHT_ROOT, partial
# delivery), not a normal absent key — surface it rather than failing opaquely.
# The exit code stays 3 so callers still pick their own fallback.
if [ -z "$defaults" ] || [ ! -r "$defaults" ]; then
  printf '%s\n' "config-get: tracked defaults not found (looked via PLANWRIGHT_CONFIG_DEFAULTS, then each arm of the core root chain: resolve-root.sh install --all --explain); '$key' unresolved" >&2
fi
exit 3
