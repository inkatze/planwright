#!/usr/bin/env bash
# resolve-catalog.sh — the catalog discovery path: union a data catalog's core
# seed with the adopter / repo-tracked / machine-local overlay catalogs and
# print the merged catalog (Task 5; D-2, D-4, D-5, D-7, D-9). The third
# per-kind resolver alongside config-get.sh (config values, last-layer-wins)
# and resolve-rule-doc.sh (doctrine, whole-doc shadow); this one merges data
# catalogs by append/union with supersede-by-id, the merge contract the
# engineering-builder guard catalog (bootstrap Task 16) consumes.
#
# planwright's four overlay layers, lowest to highest (REQ-A1.1): core defaults
# < adopter overlay < repo-tracked overlay < machine-local overlay. Layer roots
# are resolved by the shared primitive scripts/resolve-overlay-root.sh (Task 2);
# this script never rolls its own layer-location logic (D-2).
#
# Per-layer catalog file locations (D-4), <name> a kebab catalog identifier:
#   core           <core-root>/config/<name>.yaml   (the shipped seed; this is
#                  where config/guard-catalog.yaml and config/decision-domains.yaml
#                  live, so an overlay never has to restate the seed)
#   adopter        <adopter-root>/catalogs/<name>.yaml
#   repo-tracked   <repo>/.claude/catalogs/<name>.yaml
#   machine-local  <repo>/.claude/catalogs.local/<name>.yaml
#
# Usage:
#   resolve-catalog.sh <name> [--explain]
#     <name>      a catalog identifier matching the overlay charset
#                 (^[a-z0-9][a-z0-9-]*$, <=64 chars), validated before it is
#                 interpolated into any path (REQ-E1.2).
#     (no flag)   prints the merged catalog as constrained YAML on stdout: the
#                 union of all present layers, supersede markers resolved and
#                 stripped. A consumer (e.g. scripts/builder-guards.sh) reads
#                 this exactly as it reads the raw seed.
#     --explain   prints one `<id><TAB><layer>` line per merged entry naming the
#                 layer that supplied it (D-9, REQ-B1.6), in merged order.
#
# Merge contract (the pinned overlay-catalog merge semantics, D-5, REQ-B1.3):
#   * Append/union. An overlay entry whose id is new is appended. Layers merge
#     in fixed precedence order, never by filesystem enumeration order
#     (REQ-B1.5), so resolution is deterministic.
#   * Supersede-by-id. An overlay entry carrying the field `supersede: true`
#     whose id matches an entry already contributed by a lower-precedence layer
#     REPLACES that entry in place (its other fields become the entry's payload;
#     the marker itself is stripped from the output). This is the only way to
#     override a seed entry — additive otherwise.
#   * Supersede of a non-existent target is an error, handled under the
#     malformed-by-layer policy (D-7, REQ-E1.4): in a repo-tracked (team-shared)
#     overlay it HARD-FAILS (nonzero exit), because a broken shared catalog must
#     never silently mis-merge across a team; in an adopter or machine-local
#     overlay it emits a loud stderr warning and SKIPS the offending entry
#     (degrade), so one operator's typo never blocks their run.
#   * A duplicate id WITHOUT a supersede marker is a slip: warn and skip the
#     duplicate (the established entry wins); use `supersede: true` to replace.
#   * A malformed overlay file — unreadable, or present but parsing to zero
#     entries — follows the same by-layer policy: adopter/machine-local degrade
#     to the next lower layer with a warning; repo-tracked hard-fails. An absent
#     layer is normal and degrades silently (REQ-A1.4). A malformed CORE seed is
#     a broken install and hard-fails.
#
# Entry format (the constrained reader, R5; matches config/guard-catalog.yaml):
# one or more top-level sequence sections (`<section>:` alone on a line); each
# entry a `  - id: <id>` list item at two-space indent followed by fields at
# four-space indent; values unquoted or double-quoted single-line scalars (no
# single quotes, no inline `# ...` comments, no block scalars). The reader is
# not full YAML — it stays dependency-free under the bash 3.2 floor (REQ-K1.5).
#
# Exit codes: 0 merged (or empty/absent catalog); 1 hard-fail (malformed
# repo-tracked/core overlay, or a repo-tracked supersede of a non-existent
# target); 2 usage / invalid catalog name.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

# Pin the C locale: the [a-z] range checks below are collation-dependent and
# would otherwise admit uppercase under a UTF-8 locale (mirrors the siblings).
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo the destination into the command
# substitution that derives the script dir (house pattern).
unset CDPATH

usage() {
  echo "usage: resolve-catalog.sh <name> [--explain]" >&2
  exit 2
}

mode="yaml"
name=""
name_set=0
while [ $# -gt 0 ]; do
  case "$1" in
    --explain) mode="explain" ;;
    -h | --help)
      awk 'NR>=2 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else exit }' "$0"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "resolve-catalog: unknown option '$1'" >&2
      usage
      ;;
    *)
      [ "$name_set" -eq 0 ] || {
        echo "resolve-catalog: unexpected extra argument '$1'" >&2
        usage
      }
      name="$1"
      name_set=1
      ;;
  esac
  shift
done
# Any trailing positional after `--`.
if [ "$name_set" -eq 0 ] && [ $# -gt 0 ]; then
  name="$1"
  name_set=1
  shift
fi

[ "$name_set" -eq 1 ] || usage

# Validate the catalog name against the overlay identifier charset BEFORE it is
# interpolated into any path (REQ-E1.2): a kebab token, no uppercase, no leading
# dash, no traversal segments (no '/', '.'), at most 64 chars.
case "$name" in
  "" | -* | *[!a-z0-9-]*)
    echo "resolve-catalog: invalid catalog name '$name' (must match ^[a-z0-9][a-z0-9-]*\$)" >&2
    exit 2
    ;;
esac
[ "${#name}" -le 64 ] || {
  echo "resolve-catalog: catalog name '$name' exceeds 64 characters" >&2
  exit 2
}

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
overlay_root="$script_dir/resolve-overlay-root.sh"
if [ ! -x "$overlay_root" ] && [ ! -r "$overlay_root" ]; then
  echo "resolve-catalog: overlay-root primitive not found at $overlay_root" >&2
  exit 1
fi
root_of() { /bin/sh "$overlay_root" "$1" 2>/dev/null; }

core_root=$(root_of core)
adopter_root=$(root_of adopter)
repo_root=$(root_of repo-tracked)
local_root=$(root_of machine-local)

# Per-layer catalog file path (empty when the layer root is absent).
core_file="${core_root:+$core_root/config/$name.yaml}"
adopter_file="${adopter_root:+$adopter_root/catalogs/$name.yaml}"
repo_file="${repo_root:+$repo_root/catalogs/$name.yaml}"
local_file="${local_root:+$local_root/catalogs.local/$name.yaml}"

# Build the ordered list of present+readable layer files with their labels and
# malformed-policy. A present-but-unreadable file is malformed: degrade (warn)
# for adopter/machine-local, hard-fail for core/repo-tracked.
files=()
labels=""
policies=""
add_layer() {
  al_file="$1"
  al_label="$2"
  al_policy="$3"
  [ -n "$al_file" ] || return 0
  [ -e "$al_file" ] || return 0
  if [ -r "$al_file" ] && [ ! -d "$al_file" ]; then
    files+=("$al_file")
    labels="${labels:+$labels,}$al_label"
    policies="${policies:+$policies,}$al_policy"
    return 0
  fi
  # Present but unreadable (or a directory where a file is expected): malformed.
  if [ "$al_policy" = "hardfail" ]; then
    echo "resolve-catalog: $name: $al_label catalog '$al_file' is unreadable (hard-fail)" >&2
    exit 1
  fi
  echo "resolve-catalog: $name: $al_label overlay '$al_file' is unreadable (malformed); degrading to the next lower layer" >&2
}

add_layer "$core_file" core hardfail
add_layer "$adopter_file" adopter degrade
add_layer "$repo_file" repo-tracked hardfail
add_layer "$local_file" machine-local degrade

# No layer present → an absent catalog is a normal empty result (REQ-A1.4).
if [ "${#files[@]}" -eq 0 ]; then
  exit 0
fi

# Fast path: yaml mode with only the core seed present (no overlays) → emit the
# seed verbatim. Guarantees byte-identical output to the raw seed for the common
# no-overlay case, so existing single-layer consumers see no change.
if [ "$mode" = "yaml" ] && [ "${#files[@]}" -eq 1 ] && [ "$labels" = "core" ]; then
  cat "${files[0]}"
  exit 0
fi

awk -v name="$name" -v mode="$mode" -v labels="$labels" -v policies="$policies" '
  BEGIN {
    nl = split(labels, lab, ",")
    np = split(policies, pol, ",")
    fileidx = 0
    have_entry = 0
    err = 0
    n = 0     # number of merged entries (order[])
    sn = 0    # number of sections seen (sec_order[])
  }

  function warn(msg) { print "resolve-catalog: " name ": " msg > "/dev/stderr" }

  # A present file that parsed zero entries is malformed for its layer.
  function finalize(idx,   p) {
    if (idx < 1) return
    if (parsed[idx] > 0) return
    p = pol[idx]
    if (p == "hardfail") {
      warn(lab[idx] " catalog parsed no entries (malformed): " fname[idx] " (hard-fail)")
      err = 1
      exit 1
    }
    warn(lab[idx] " overlay parsed no entries (malformed): " fname[idx] "; degrading to the next lower layer")
  }

  # Merge the pending entry per the append/union + supersede-by-id contract.
  function flush_entry(   id) {
    if (!have_entry) return
    have_entry = 0
    id = cur_id
    if (id == "") return                 # entry without an id: skip (lenient)
    if (cur_supersede) {
      if (id in seen) {                  # replace the payload in place, keeping
        fields_of[id] = cur_fields       # the original section and position
        layer_of[id] = cur_label
        return
      }
      # Supersede of a non-existent target: by-layer policy.
      if (cur_policy == "hardfail") {
        warn(cur_label " entry \"" id "\" supersedes a non-existent target (hard-fail)")
        err = 1
        exit 1
      }
      warn(cur_label " entry \"" id "\" supersedes a non-existent target; skipping entry")
      return
    }
    if (id in seen) {                    # unmarked duplicate: established wins
      warn(cur_label " entry \"" id "\" duplicates an existing id without a supersede marker; skipping (use \"supersede: true\" to replace)")
      return
    }
    seen[id] = 1
    order[++n] = id
    section_of[id] = cur_section
    fields_of[id] = cur_fields
    layer_of[id] = cur_label
    if (!(cur_section in sec_seen)) {
      sec_seen[cur_section] = 1
      sec_order[++sn] = cur_section
    }
  }

  # New file boundary: flush the previous file pending entry (still under the
  # previous label), finalize its zero-entry check, then advance the layer.
  FNR == 1 {
    flush_entry()
    if (fileidx > 0) finalize(fileidx)
    fileidx++
    fname[fileidx] = FILENAME
    cur_label = lab[fileidx]
    cur_policy = pol[fileidx]
    section = ""
  }

  /^[ \t]*#/ { next }                    # comment

  # A column-0 line is either a section header or the end of a sequence.
  /^[^ \t]/ {
    flush_entry()
    if ($0 ~ /^[A-Za-z][A-Za-z0-9_-]*:[ \t]*$/) {
      section = $0
      sub(/:[ \t]*$/, "", section)
    } else {
      section = ""
    }
    next
  }

  # A new entry: `  - id: <id>` at two-space indent, inside a section.
  section != "" && /^  -[ \t]+id:/ {
    flush_entry()
    parsed[fileidx]++
    raw = $0
    sub(/^  -[ \t]+id:[ \t]*/, "", raw)
    sub(/[ \t]*$/, "", raw)
    sub(/^"/, "", raw)
    sub(/"$/, "", raw)
    cur_id = raw
    cur_supersede = 0
    cur_fields = ""
    cur_section = section
    have_entry = 1
    next
  }

  # An entry field at four-space indent. `supersede:` is a merge directive, not
  # catalog data — captured as the marker, kept out of the emitted payload.
  have_entry && /^    [A-Za-z]/ {
    raw = $0
    sub(/^    /, "", raw)
    key = raw
    sub(/:.*/, "", key)
    if (key == "supersede") {
      # `supersede: true` is the merge directive (value-equality, like the guard
      # catalog reader treats `core: true`). Any other value (false, empty, ...)
      # is NOT a supersede; either way the directive is never re-emitted as
      # catalog data.
      val = raw
      sub(/^[^:]*:[ \t]*/, "", val)
      sub(/[ \t]*$/, "", val)
      sub(/^"/, "", val)
      sub(/"$/, "", val)
      if (val == "true") cur_supersede = 1
    } else {
      cur_fields = cur_fields (cur_fields == "" ? "" : "\n") raw
    }
    next
  }

  END {
    if (!err) flush_entry()
    if (!err && fileidx > 0) finalize(fileidx)
    if (err) exit 1

    if (mode == "explain") {
      for (i = 1; i <= n; i++) print order[i] "\t" layer_of[order[i]]
      exit 0
    }

    # yaml mode: re-emit the merged catalog, grouped by first-seen section.
    for (s = 1; s <= sn; s++) {
      sec = sec_order[s]
      print sec ":"
      for (i = 1; i <= n; i++) {
        id = order[i]
        if (section_of[id] != sec) continue
        print "  - id: " id
        m = split(fields_of[id], farr, "\n")
        for (j = 1; j <= m; j++) if (farr[j] != "") print "    " farr[j]
      }
    }
  }
' "${files[@]}"
exit $?
