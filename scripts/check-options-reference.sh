#!/usr/bin/env bash
# check-options-reference.sh — D-43 drift check (REQ-K1.8).
#
# Every option in the tracked default config must have a row in the canonical
# options reference. An undocumented option is an error (exit 1). A reference
# row with no matching config option is a warning on stderr (stale docs
# surface without blocking). Task 2 wires this into planwright's CI.
#
# ## The fleet-knobs tether (guard-coverage Task 9; REQ-F1.3, REQ-H1.3, D-10)
#
# docs/fleet.md's knobs table does something the options reference does not: it
# restates each fleet knob's **default value** in prose. A restated value
# drifts silently, so this check also compares those defaults against the
# config. Every knob the table names must exist in the config with the value
# the table claims; a divergence, or a name the config does not carry, is an
# error (exit 1).
#
# Usage: check-options-reference.sh [<config> [<reference> [<fleet>]]]
#   Defaults: config/defaults.yml and docs/options-reference.md relative to
#   the repo root (the script's parent directory). The fleet doc defaults to
#   docs/fleet.md in the **zero-argument (CI) form only** — a caller
#   substituting fixture files for the config supplies the matching fleet doc
#   too, since tethering a fixture config to the shipped prose would compare
#   two unrelated things. That skip is announced on stderr, never silent.
#
# Format constraints this parser relies on: the config must be flat
# "key: value" lines (nested YAML keys are invisible to it and fail the
# zero-key guard); each reference row's first table cell must contain only the
# backticked option name; and each knobs row names its knobs as backticked
# identifiers in the first cell, with the matching defaults as the LEADING
# backticked values of the `Default…` column, `/`-separated and positionally
# paired (`a` / `b` for `knob_a` / `knob_b`). Trailing prose after those
# values is ignored.
#
# Fail-closed posture (REQ-H1.3), symmetric on both sides: a config parsing to
# zero option keys is an error, and so is a knobs table with no recognizable
# header, no rows, a row naming no knob, a row with no backticked default, or
# a row whose knob count and default count disagree. A vacuous parse must
# never read as agreement.
#
# Exit codes: 0 fully documented and tethered, 1 an undocumented option or a
# fleet-knob divergence, 2 usage error or a fail-closed parse degeneracy.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale so the bracket expressions below mean exactly their ASCII
# range on every host (defensive; mirrors resolve-rule-doc.sh).
LC_ALL=C
export LC_ALL

# A user CDPATH would make cd echo into the command substitution below and
# corrupt the repo-root derivation.
unset CDPATH

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Display sanitizer for parsed content (echo discipline,
# doctrine/security-posture.md). The fleet tether below echoes knob names,
# values, and malformed-row text lifted straight out of a markdown table, so
# an escape sequence embedded in the doc would otherwise drive the terminal of
# whoever runs the gate. A byte-identical inline fallback is defined first so a
# diagnostic is never unable to strip control bytes; the canonical shared
# helper overrides it when the sibling resolves. Mirrors the two sibling
# tethers this check ships alongside.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$repo_root/scripts/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$repo_root/scripts/echo-safety.sh"
fi

config="${1:-$repo_root/config/defaults.yml}"
reference="${2:-$repo_root/docs/options-reference.md}"
# The fleet tether engages on the CI form, or whenever a caller names the doc.
fleet="${3:-}"
if [ "$#" -eq 0 ]; then
  fleet="$repo_root/docs/fleet.md"
fi

if [ ! -f "$config" ]; then
  echo "check-options-reference: config file not found: $config" >&2
  exit 2
fi
if [ ! -f "$reference" ]; then
  echo "check-options-reference: reference file not found: $reference" >&2
  exit 2
fi
if [ -n "$fleet" ] && [ ! -f "$fleet" ]; then
  echo "check-options-reference: fleet doc not found: $fleet" >&2
  exit 2
fi

# Option keys: top-level "key:" lines in the flat default config. A config
# that parses to zero keys fails closed: a reformatted defaults.yml must not
# silently turn this CI check into a no-op.
config_keys="$(sed -n 's/^\([a-z0-9_][a-z0-9_]*\):.*/\1/p' "$config")"
if [ -z "$config_keys" ]; then
  echo "check-options-reference: no option keys parsed from $config (flat 'key: value' lines expected)" >&2
  exit 2
fi

# Documented options: table rows whose first cell is the backticked name.
# Cell padding and markdown's up-to-three-space row indentation are
# tolerated: the check is coverage, not whitespace style.
# shellcheck disable=SC2016 # the backtick is literal markdown, not expansion
documented_keys="$(sed -n 's/^[[:space:]]*|[[:space:]]*`\([a-z0-9_][a-z0-9_]*\)`[[:space:]]*|.*/\1/p' "$reference")"

status=0

for key in $config_keys; do
  found=0
  for doc in $documented_keys; do
    if [ "$key" = "$doc" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "check-options-reference: option '$key' in $config has no entry in $reference" >&2
    status=1
  fi
done

for doc in $documented_keys; do
  found=0
  for key in $config_keys; do
    if [ "$doc" = "$key" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "check-options-reference: warning: '$doc' is documented but absent from $config" >&2
  fi
done

# ---------------------------------------------------------------------------
# The fleet-knobs tether: docs/fleet.md's knobs table restates config defaults.
# ---------------------------------------------------------------------------
fleet_knob_count=0
if [ -n "$fleet" ]; then
  safe_fleet="$(sanitize_printable "$fleet" "(unprintable path)")"
  safe_config="$(sanitize_printable "$config" "(unprintable path)")"
  # Config values, keyed by option name. Trailing comments and surrounding
  # quotes are stripped so the comparison is on the value, not its spelling.
  config_values="$(awk '
    /^[a-z0-9_]+:/ {
      k = $0; sub(/:.*/, "", k)
      v = $0; sub(/^[a-z0-9_]+:[ \t]*/, "", v)
      sub(/[ \t]+#.*$/, "", v)
      sub(/[ \t]+$/, "", v)
      gsub(/^"|"$|^'"'"'|'"'"'$/, "", v)
      printf "%s\t%s\n", k, v
    }
  ' "$config")"

  # Knobs table: located by a header row whose first cell is `Knob` and which
  # carries a `Default…` column. Emits one "<knob>\t<documented default>" line
  # per knob, positionally paired within a multi-knob row.
  fleet_pairs="$(awk '
    function strip(s) {
      gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s)
      return s
    }
    # Diagnostics ride the pair stream on a sentinel line rather than stderr,
    # so the parse needs no scratch file: a predictable name under TMPDIR
    # would be a symlink-following write, and an unwritable TMPDIR would
    # silently cost the diagnostic.
    function err(m) { printf "#ERR\t%s\n", m; bad = 1 }
    {
      line = $0; sub(/^[ \t]+/, "", line)
      # The first non-row line ends the table, and ends the walk: a later
      # `Knob`-headed table is a neighbouring table, not more knobs rows, and
      # merging it would tether names this table never claimed to restate.
      # `exit` still runs the END block, so its exit codes are unaffected.
      if (line !~ /^\|/) { if (intbl) exit; next }
      n = split(line, c, "|")
      if (!intbl) {
        if (strip(c[2]) != "Knob") next
        defcol = 0
        for (i = 3; i < n; i++) if (strip(c[i]) ~ /^Default/) defcol = i
        if (!defcol) next
        intbl = 1; found = 1; next
      }
      if (line ~ /^\|[ \t]*:?-+:?[ \t]*\|/) next
      rows++

      nk = 0
      cell = c[2]
      while (match(cell, /`[a-z0-9_]+`/)) {
        names[++nk] = substr(cell, RSTART + 1, RLENGTH - 2)
        cell = substr(cell, RSTART + RLENGTH)
      }
      if (nk == 0) {
        err("knobs row names no option: " strip(c[2]))
        next
      }

      nv = 0
      cell = strip(c[defcol])
      while (match(cell, /^`[^`]*`/)) {
        vals[++nv] = substr(cell, RSTART + 1, RLENGTH - 2)
        cell = substr(cell, RSTART + RLENGTH)
        sub(/^[ \t]*/, "", cell)
        if (substr(cell, 1, 1) != "/") break
        sub(/^\/[ \t]*/, "", cell)
      }
      if (nv == 0) {
        err("knobs row for " names[1] " carries no backticked default value")
        next
      }
      if (nv != nk) {
        err("knobs row for " names[1] " names " nk " knobs but " nv " default values; they cannot be paired")
        next
      }
      for (i = 1; i <= nk; i++) printf "%s\t%s\n", names[i], vals[i]
    }
    END {
      if (bad) exit 5
      if (!found) exit 3
      if (!rows) exit 4
    }
  ' "$fleet")"
  fleet_status=$?
  fleet_err="$(sanitize_printable "$(printf '%s\n' "$fleet_pairs" | sed -n 's/^#ERR[[:space:]]*//p' | tr '\n' ';')" "(unprintable diagnostic)")"
  fleet_pairs="$(printf '%s\n' "$fleet_pairs" | grep -v '^#ERR' || true)"
  case "$fleet_status" in
    3)
      echo "check-options-reference: could not parse the knobs table in $safe_fleet (no header row whose first cell is 'Knob' with a 'Default…' column)" >&2
      exit 2
      ;;
    4)
      echo "check-options-reference: the knobs table in $safe_fleet parsed to zero rows" >&2
      exit 2
      ;;
    5)
      echo "check-options-reference: malformed knobs table in $safe_fleet: $fleet_err" >&2
      exit 2
      ;;
    0) ;;
    *)
      echo "check-options-reference: failed to parse the knobs table in $safe_fleet" >&2
      exit 2
      ;;
  esac

  while IFS="$(printf '\t')" read -r knob documented; do
    [ -n "$knob" ] || continue
    fleet_knob_count=$((fleet_knob_count + 1))
    safe_knob="$(sanitize_printable "$knob" "(unprintable knob)")"
    actual="$(printf '%s\n' "$config_values" | awk -F'\t' -v k="$knob" '$1 == k { print $2; found = 1 } END { if (!found) exit 1 }')" || {
      echo "check-options-reference: '$safe_knob' is documented in $safe_fleet but absent from $safe_config" >&2
      status=1
      continue
    }
    if [ "$documented" != "$actual" ]; then
      echo "check-options-reference: '$safe_knob' default drift: $safe_fleet says '$(sanitize_printable "$documented" "(unprintable value)")', $safe_config says '$(sanitize_printable "$actual" "(unprintable value)")'" >&2
      status=1
    fi
  done <<EOF
$fleet_pairs
EOF
else
  # Never a silent skip: a caller that substituted fixture files without a
  # fleet doc must not read the clean exit as "the tether ran".
  echo "check-options-reference: fleet-knob tether skipped (no fleet doc given; pass one as the third argument)" >&2
fi

if [ "$status" -eq 0 ]; then
  if [ "$fleet_knob_count" -gt 0 ]; then
    echo "check-options-reference: all options documented; $fleet_knob_count fleet knob defaults tethered to $config"
  else
    echo "check-options-reference: all options documented"
  fi
fi
exit "$status"
