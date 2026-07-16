#!/bin/sh
# migrate-format-version.sh [specs-root | spec-dir]
#
# The one-shot v1→v2 spec-bundle migration (invariant-tasks Task 6;
# REQ-D1.2, REQ-D1.3, REQ-A1.4, REQ-C1.8, REQ-C1.9 · D-10, D-3). Converts a
# live (Draft/Ready/Active) format-version 1 bundle to format-version 2:
#
#   - the placement sections (## Forward plan / ## In progress /
#     ## Completed) collapse into a single `## Tasks` section, task blocks
#     sorted by task id (numeric, component-wise);
#   - the state annotation bullets (Status, Last activity, Dispatch) are
#     stripped, with task definition lines preserved byte-for-byte, so the
#     canonical tasks.md extraction digest — and therefore that file's
#     contribution to the content anchor — is unchanged (verified before
#     any write; a mismatch refuses the bundle);
#   - a parked task block found under any human-payload section (Awaiting
#     input / Deferred / Out of scope) moves to `## Tasks` and leaves a
#     reference bullet in its section, carrying the block's v1 Status
#     annotation text as the human payload when one exists (D-3);
#   - the stored header restricts to the human-gated set (Active → Ready),
#     `Format-version:` bumps to 2, and the static pointer line
#     `**Execution:** derived — see the status render` is inserted, on all
#     four files;
#   - a signed bundle (stored Ready or Active, so a kickoff brief exists)
#     additionally gains a dated `## Changelog` entry in requirements.md
#     and the machine-written expression-only self-re-anchor entry in the
#     kickoff brief that cites it (the meta-spec's execution-validity rule);
#     a Draft takes neither (REQ-D1.3).
#
# Done and terminal (Retired/Superseded) bundles are never rewritten; an
# already-v2 bundle is a clean no-op. Idempotent and re-runnable after a
# partial run: requirements.md (whose migration Changelog entry marks a
# signed migration) is written last of the four files, so a re-run over an
# interrupted bundle re-applies the per-file idempotent transforms and
# completes a missing changelog line or re-anchor entry rather than
# no-oping past a file that already reads v2 (D-10). A v2 bundle with no
# migration changelog marker is treated as born-v2 and left untouched —
# completing a "missing" re-anchor there would forge a migration that never
# happened.
#
# Fail-closed version keying (REQ-C1.8): a missing or unparseable
# `Format-version:` refuses the bundle with no write. Hostile identifiers,
# symlinked bundle directories or spec files, and out-of-containment paths
# are refused with a clean error; every echoed untrusted value is routed
# through sanitize_printable (REQ-C1.9).
#
# Exit codes: 0 sweep/bundle completed with no refusals; 1 one or more
# bundles refused (reported on stderr, nothing written to them); 2 usage or
# environment error.
#
# Portable: POSIX sh + awk + git (bash 3.2 / BSD compatible, no eval, input
# treated as data only).
set -eu

# Pin the C locale: charset checks and awk ranges must not vary by host
# locale collation, and anchor bytes must be host-independent.
LC_ALL=C
export LC_ALL
unset CDPATH 2>/dev/null || true

here=$(cd "$(dirname "$0")" && pwd -P) || exit 2
repo_root=$(cd "$here/.." && pwd -P) || exit 2
anchor_sh="$here/spec-anchor.sh"

# Canonical echo-discipline sanitizer (doctrine/security-posture.md).
# shellcheck source=scripts/echo-safety.sh
. "$here/echo-safety.sh"

if [ ! -x "$anchor_sh" ]; then
  echo "migrate-format-version: spec-anchor.sh missing or not executable: $anchor_sh" >&2
  exit 2
fi

if [ $# -gt 1 ]; then
  echo "usage: migrate-format-version.sh [specs-root | spec-dir]" >&2
  exit 2
fi
target=${1:-$repo_root/specs}
while [ "$target" != "${target%/}" ]; do target=${target%/}; done
if [ ! -d "$target" ]; then
  echo "migrate-format-version: not a directory: $target" >&2
  exit 2
fi

today=$(date +%Y-%m-%d)
gtmp=$(mktemp -d)
trap 'rm -rf "$gtmp"' EXIT

migrated=0
completed=0
unchanged=0
refused=0

# Full-string spec-identifier check (REQ-A1.8): ^[a-z0-9][a-z0-9-]*$, max 64.
check_spec_id() {
  cid=$1
  [ -n "$cid" ] || return 1
  [ "${#cid}" -le 64 ] || return 1
  case $cid in
    [a-z0-9]*) ;;
    *) return 1 ;;
  esac
  case $cid in
    *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

# refuse <name> <reason> — report a refused bundle (sanitized) and count it.
refuse() {
  rn=$(sanitize_printable "$1" "(unprintable name)")
  echo "refused: $rn — $2" >&2
  refused=$((refused + 1))
}

# header_value <file> <key> — first "**<key>:** value" line's value, with
# non-printables stripped (the value is compared and echoed; hostile bytes
# must reach neither the logic nor the terminal raw).
header_value() {
  awk -v key="$2" '
    index($0, "**" key ":**") == 1 {
      sub(/^\*\*[^*]*:\*\*[ \t]*/, "")
      gsub(/[^[:print:]]/, "")
      sub(/[ \t]+$/, "")
      print
      exit
    }
  ' "$1"
}

# extract_tasks <tasks.md> — the canonical definition-content extraction
# (doctrine/spec-format.md), byte-identical to scripts/spec-anchor.sh's:
# the migration's self-check hashes this stream before and after the
# transform and refuses on any difference (REQ-A1.4, REQ-D1.2).
extract_tasks() {
  awk '
    function sortkey(id,    parts, n, major, minor) {
      n = split(id, parts, "\\.")
      major = parts[1] + 0
      minor = (n > 1) ? parts[2] + 0 : 0
      return sprintf("%08d.%08d", major, minor)
    }
    /^## /  { in_task = 0; keep = 0; next }
    /^### Task [0-9]/ {
      in_task = 1
      keep = 0
      key = sortkey($3)
      if (key in buf) {
        print "duplicate task id " $3 > "/dev/stderr"
        dup = 1
        exit 1
      }
      nkeys++
      keys[nkeys] = key
      buf[key] = $0 "\n"
      cur = key
      next
    }
    /^### / { in_task = 0; keep = 0; next }
    !in_task { next }
    /^- \*\*(Deliverables|Done when|Dependencies|Citations|Estimated effort):\*\*/ {
      keep = 1
      buf[cur] = buf[cur] $0 "\n"
      next
    }
    /^- /      { keep = 0; next }
    /^[ \t]+[^ \t]/ {
      if (keep) buf[cur] = buf[cur] $0 "\n"
      next
    }
    { keep = 0 }
    END {
      if (dup) exit 1
      for (i = 2; i <= nkeys; i++) {
        v = keys[i]
        j = i - 1
        while (j >= 1 && keys[j] > v) { keys[j + 1] = keys[j]; j-- }
        keys[j + 1] = v
      }
      for (i = 1; i <= nkeys; i++) printf "%s", buf[keys[i]]
    }
  ' "$1"
}

# restructure_tasks <tasks.md> — emit the v2 body: head (title, header
# block, intro prose) verbatim, one `## Tasks` section holding every task
# block id-sorted with the three state-annotation bullets (and their
# continuations) removed, then the three human-payload sections with their
# non-task content preserved and a reference bullet per parked block.
# Fails (non-zero, message on stderr) on an unknown H2 section, a non-task
# H3, a malformed or duplicate task id — the transform must be mechanical
# or refuse (D-10).
restructure_tasks() {
  awk '
    function sortkey(id,    parts, n, major, minor) {
      n = split(id, parts, "\\.")
      major = parts[1] + 0
      minor = (n > 1) ? parts[2] + 0 : 0
      return sprintf("%08d.%08d", major, minor)
    }
    # trimchunk: strip leading/trailing blank lines; result ends with one
    # newline (or is empty).
    function trimchunk(s,    n, arr, i, first, last, out) {
      n = split(s, arr, "\n")
      # split leaves a trailing empty field for a newline-terminated s
      if (n > 0 && arr[n] == "") n--
      first = 1
      while (first <= n && arr[first] ~ /^[ \t]*$/) first++
      last = n
      while (last >= first && arr[last] ~ /^[ \t]*$/) last--
      out = ""
      for (i = first; i <= last; i++) out = out arr[i] "\n"
      return out
    }
    function payload_out(content, bullets,    c) {
      c = trimchunk(content)
      if (c == "(none yet)\n" && bullets != "") c = ""
      if (c != "" && bullets != "") return c "\n" bullets
      if (c != "") return c
      if (bullets != "") return bullets
      return "(none yet)\n"
    }
    BEGIN { sec = "" }
    !started && /^## / { started = 1 }
    !started { head = head $0 "\n"; next }
    /^## Forward plan[ \t]*$/   { sec = "FP"; in_blk = 0; next }
    /^## In progress[ \t]*$/    { sec = "IP"; in_blk = 0; next }
    /^## Completed[ \t]*$/      { sec = "CO"; in_blk = 0; next }
    /^## Tasks[ \t]*$/          { sec = "TK"; in_blk = 0; next }
    /^## Awaiting input[ \t]*$/ { sec = "AI"; in_blk = 0; next }
    /^## Deferred[ \t]*$/       { sec = "DF"; in_blk = 0; next }
    /^## Out of scope[ \t]*$/   { sec = "OS"; in_blk = 0; next }
    /^## / {
      print "unrecognized H2 section at tasks.md:" NR " (the migration is mechanical over the six v1 sections and refuses anything else)" > "/dev/stderr"
      bad = 1
      exit 1
    }
    /^### Task / {
      id = $3
      if (id !~ /^[0-9]+(\.[0-9]+)?$/) {
        print "malformed task id at tasks.md:" NR > "/dev/stderr"
        bad = 1
        exit 1
      }
      key = sortkey(id)
      if (key in blk) {
        print "duplicate task id: Task " id > "/dev/stderr"
        bad = 1
        exit 1
      }
      nkeys++
      keys[nkeys] = key
      blk[key] = $0 "\n"
      blkid[key] = id
      blksec[key] = sec
      in_blk = 1
      cur = key
      skip = 0
      skip_stat = 0
      next
    }
    /^### / {
      print "unexpected non-task H3 at tasks.md:" NR " (cannot migrate mechanically)" > "/dev/stderr"
      bad = 1
      exit 1
    }
    in_blk {
      if (/^- \*\*(Status|Last activity|Dispatch):\*\*/) {
        skip = 1
        skip_stat = 0
        if (/^- \*\*Status:\*\*/) {
          t = $0
          sub(/^- \*\*Status:\*\*[ \t]*/, "", t)
          stat[cur] = t
          skip_stat = 1
        }
        next
      }
      if (/^- /) {
        skip = 0
        blk[cur] = blk[cur] $0 "\n"
        next
      }
      if (/^[ \t]+[^ \t]/) {
        if (skip) {
          if (skip_stat) {
            t = $0
            sub(/^[ \t]+/, "", t)
            stat[cur] = stat[cur] " " t
          }
          next
        }
        blk[cur] = blk[cur] $0 "\n"
        next
      }
      skip = 0
      blk[cur] = blk[cur] $0 "\n"
      next
    }
    sec == "AI" { ai = ai $0 "\n"; next }
    sec == "DF" { df = df $0 "\n"; next }
    sec == "OS" { os = os $0 "\n"; next }
    { next }
    END {
      if (bad) exit 1
      for (i = 2; i <= nkeys; i++) {
        v = keys[i]
        j = i - 1
        while (j >= 1 && keys[j] > v) { keys[j + 1] = keys[j]; j-- }
        keys[j + 1] = v
      }
      # Reference bullets for parked blocks (D-3): the v1 Status annotation
      # text is the human payload when one exists; the block itself moves
      # to ## Tasks.
      aib = ""; dfb = ""; osb = ""
      for (i = 1; i <= nkeys; i++) {
        k = keys[i]
        s = blksec[k]
        if (s != "AI" && s != "DF" && s != "OS") continue
        if (s == "AI") secname = "Awaiting input"
        else if (s == "DF") secname = "Deferred"
        else secname = "Out of scope"
        if (k in stat && stat[k] != "")
          b = "- **Task " blkid[k] "** — " stat[k] " *(converted from a relocated v1 task block at the format-version 2 migration.)*\n"
        else
          b = "- **Task " blkid[k] "** — parked in the v1 \"## " secname "\" section. *(converted from a relocated v1 task block at the format-version 2 migration.)*\n"
        if (s == "AI") aib = aib b
        else if (s == "DF") dfb = dfb b
        else osb = osb b
      }
      out = trimchunk(head)
      out = out "\n## Tasks\n"
      for (i = 1; i <= nkeys; i++) out = out "\n" trimchunk(blk[keys[i]])
      out = out "\n## Awaiting input\n\n" payload_out(ai, aib)
      out = out "\n## Deferred\n\n" payload_out(df, dfb)
      out = out "\n## Out of scope\n\n" payload_out(os, osb)
      printf "%s", out
    }
  ' "$1"
}

# transform_header <file> — bump the header block: Active → Ready on the
# first Status line, Format-version → 2, and the static pointer line
# inserted after it when absent. Idempotent per file.
transform_header() {
  th_ptr=0
  grep -qxF '**Execution:** derived — see the status render' "$1" && th_ptr=1
  awk -v haveptr="$th_ptr" '
    !done_status && /^\*\*Status:\*\* / {
      if ($0 == "**Status:** Active") print "**Status:** Ready"
      else print
      done_status = 1
      next
    }
    !done_fv && /^\*\*Format-version:\*\*/ {
      print "**Format-version:** 2"
      if (!haveptr) print "**Execution:** derived — see the status render"
      done_fv = 1
      next
    }
    { print }
  ' "$1"
}

# process_bundle <dir> <name> — migrate one screened bundle in place.
# Returns 0 (outcome counted) or 1 (refused, counted by the caller via
# refuse()). Everything is computed and self-checked before the first write
# (per-bundle atomic up to the write sequence; a partial write sequence is
# recovered by re-running, D-10).
process_bundle() {
  bdir=$1
  bname=$2

  req="$bdir/requirements.md"
  if [ ! -f "$req" ]; then
    refuse "$bname" "missing requirements.md (the authoritative Status and Format-version home)"
    return 0
  fi
  for bf in requirements.md design.md tasks.md test-spec.md kickoff-brief.md; do
    if [ -L "$bdir/$bf" ]; then
      refuse "$bname" "symlinked spec file: $bf (refusing to rewrite through a link)"
      return 0
    fi
  done

  fver=$(header_value "$req" Format-version)
  status=$(header_value "$req" Status)
  brief="$bdir/kickoff-brief.md"
  clog_marker='Migrated to format-version 2'
  entry_marker='self-re-anchor (format-version 2 migration)'

  # Fail-closed version keying (REQ-C1.8): no parsed version, no write path.
  case $fver in
    1 | 2) ;;
    '')
      refuse "$bname" "missing or empty Format-version: declaration (fail closed; REQ-C1.8)"
      return 0
      ;;
    *[!0-9]*)
      refuse "$bname" "unparseable Format-version: $(sanitize_printable "$fver" "(unprintable)") (fail closed; REQ-C1.8)"
      return 0
      ;;
    *)
      refuse "$bname" "unsupported Format-version: $(sanitize_printable "$fver" "(unprintable)") (this migration implements 1 → 2)"
      return 0
      ;;
  esac

  if [ "$fver" = "2" ]; then
    # Already v2. A migration changelog marker means a signed migration ran
    # here: complete a missing re-anchor entry (an interrupted run's last
    # step) rather than no-oping past it (REQ-D1.2). No marker means the
    # bundle was born v2 (or is a migrated Draft): leave it untouched.
    if grep -qF "$clog_marker" "$req"; then
      if [ ! -f "$brief" ]; then
        refuse "$bname" "migration changelog entry present but kickoff-brief.md is missing (cannot complete the re-anchor)"
        return 0
      fi
      if grep -qF "$entry_marker" "$brief"; then
        echo "unchanged (already format-version 2): $bname"
        unchanged=$((unchanged + 1))
      else
        append_reanchor "$bdir" || {
          refuse "$bname" "re-anchor completion failed"
          return 0
        }
        echo "completed: $bname (missing re-anchor entry appended)"
        completed=$((completed + 1))
      fi
    else
      echo "unchanged (already format-version 2): $bname"
      unchanged=$((unchanged + 1))
    fi
    return 0
  fi

  # v1: only live bundles migrate; Done and terminal records are never
  # rewritten (D-10).
  case $status in
    Done | Retired | Superseded)
      echo "unchanged (not live): $bname ($status)"
      unchanged=$((unchanged + 1))
      return 0
      ;;
    Draft) signed=0 ;;
    Ready | Active) signed=1 ;;
    '')
      refuse "$bname" "missing bundle **Status:** header in requirements.md"
      return 0
      ;;
    *)
      refuse "$bname" "unknown status: $(sanitize_printable "$status" "(unprintable)")"
      return 0
      ;;
  esac
  if [ "$signed" = 1 ] && [ ! -f "$brief" ]; then
    refuse "$bname" "signed bundle ($status) has no kickoff-brief.md (the re-anchor entry has no home)"
    return 0
  fi
  for bf in design.md tasks.md test-spec.md; do
    if [ ! -f "$bdir/$bf" ]; then
      refuse "$bname" "missing spec file: $bf"
      return 0
    fi
  done

  # Compute every new file content first; refuse before any write.
  if ! restructure_tasks "$bdir/tasks.md" >"$gtmp/tasks.new" 2>"$gtmp/tasks.err"; then
    refuse "$bname" "tasks.md restructure failed: $(sanitize_printable "$(cat "$gtmp/tasks.err")" "(no diagnostic)")"
    return 0
  fi
  transform_header "$gtmp/tasks.new" >"$gtmp/tasks.new2"
  mv "$gtmp/tasks.new2" "$gtmp/tasks.new"
  transform_header "$bdir/design.md" >"$gtmp/design.new"
  transform_header "$bdir/test-spec.md" >"$gtmp/test-spec.new"
  transform_header "$req" >"$gtmp/requirements.new"

  if [ "$signed" = 1 ] && ! grep -qF "$clog_marker" "$gtmp/requirements.new"; then
    if ! grep -q '^## Changelog[ \t]*$' "$gtmp/requirements.new"; then
      refuse "$bname" "requirements.md has no ## Changelog section (the migration entry has no home)"
      return 0
    fi
    cat >"$gtmp/clog.entry" <<EOF
- $today — Migrated to format-version 2 (invariant-tasks D-10, REQ-D1.3;
  one-shot \`scripts/migrate-format-version.sh\` run): placement sections
  collapsed into a single \`## Tasks\` section, state annotation bullets
  stripped, stored header restricted to the human-gated set, the
  \`**Execution:**\` pointer line added, \`Format-version:\` bumped to 2 on
  all four files. Task definition lines are preserved byte-for-byte (the
  canonical \`tasks.md\` extraction digest is unchanged), so the required
  re-anchor rides as expression-only: the kickoff brief's self-re-anchor
  entry cites this entry.
EOF
    awk -v ins="$gtmp/clog.entry" '
      { print }
      /^## Changelog[ \t]*$/ && !done {
        print ""
        while ((getline l < ins) > 0) print l
        done = 1
      }
    ' "$gtmp/requirements.new" >"$gtmp/requirements.new2"
    mv "$gtmp/requirements.new2" "$gtmp/requirements.new"
  fi

  # Self-check (REQ-A1.4): the canonical extraction must be byte-identical
  # across the transform. A difference means the transform is not the
  # mechanical one it claims to be — refuse, write nothing.
  if ! extract_tasks "$bdir/tasks.md" >"$gtmp/extract.old" 2>/dev/null; then
    refuse "$bname" "canonical extraction failed on the v1 tasks.md (duplicate or malformed task ids)"
    return 0
  fi
  if ! extract_tasks "$gtmp/tasks.new" >"$gtmp/extract.new" 2>/dev/null; then
    refuse "$bname" "canonical extraction failed on the migrated tasks.md"
    return 0
  fi
  if ! cmp -s "$gtmp/extract.old" "$gtmp/extract.new"; then
    refuse "$bname" "task definition lines would not survive byte-for-byte (extraction digest moved); nothing written"
    return 0
  fi

  # Write sequence: requirements.md last — its migration changelog marker is
  # the completion key a re-run checks, so an interruption anywhere earlier
  # re-runs the idempotent per-file transforms (D-10).
  for pair in design.md test-spec.md tasks.md requirements.md; do
    src="$gtmp/${pair%.md}.new"
    cp "$src" "$bdir/$pair.migrate.tmp"
    mv "$bdir/$pair.migrate.tmp" "$bdir/$pair"
  done

  if [ "$signed" = 1 ]; then
    append_reanchor "$bdir" || {
      refuse "$bname" "files migrated but the re-anchor entry failed; re-run to complete (D-10)"
      return 0
    }
  fi

  echo "migrated: $bname"
  migrated=$((migrated + 1))
  return 0
}

# append_reanchor <dir> — compute the post-migration anchor and
# append the machine-written expression-only self-re-anchor entry to the
# kickoff brief (the one anchor entry an execution-side script may write:
# explicitly marked and citing its changelog line, REQ-F1.10). A stale
# "(none yet …)" placeholder paragraph in the amendment-log section is
# dropped when the first real entry lands.
append_reanchor() {
  ab_dir=$1
  ab_brief="$ab_dir/kickoff-brief.md"

  ab_anchor=$("$anchor_sh" "$ab_dir") || return 1

  # Record the bundle path relative to its own repository root when it has
  # one (the sanctioned command form is reproducible from the repo root);
  # fall back to the path as invoked.
  ab_rel=$ab_dir
  if ab_top=$(git -C "$ab_dir" rev-parse --show-toplevel 2>/dev/null); then
    ab_top_phys=$(cd "$ab_top" && pwd -P)
    ab_dir_phys=$(cd "$ab_dir" && pwd -P)
    case $ab_dir_phys in
      "$ab_top_phys"/*) ab_rel=${ab_dir_phys#"$ab_top_phys"/} ;;
    esac
  fi

  cat >"$gtmp/reanchor.entry" <<EOF
### $today — Expression-only self-re-anchor (format-version 2 migration)

Machine-written entry per REQ-F1.10's expression-only lane, recorded by
\`scripts/migrate-format-version.sh\` (invariant-tasks D-10, REQ-D1.2).

**Trigger:** the one-shot v1→v2 migration converted this bundle to
format-version 2: placement sections collapsed into \`## Tasks\`, state
annotation bullets stripped, any parked task blocks converted to reference
bullets, the stored header restricted to the human-gated set, the
\`**Execution:**\` pointer line added, and \`Format-version:\` bumped on all
four files. Task definition lines are byte-for-byte unchanged (the
canonical \`tasks.md\` extraction digest was verified equal before
writing), so no requirement, design decision, task definition, or test
semantics changed — the required re-anchor rides the migration as
expression-only (REQ-A3.3, REQ-D1.2).

**Cites the changelog line:** the $today \`## Changelog\` entry in
\`requirements.md\` ("Migrated to format-version 2").

Class: expression-only
Anchor: \`$ab_anchor\` — computed as
\`scripts/spec-anchor.sh $ab_rel\`
EOF

  # Drop a "(none yet …)" placeholder paragraph inside the amendment-log
  # section, trim trailing blank lines, and append the entry after one
  # separating blank line.
  awk '
    /^## / { in_log = (index($0, "Amendment log") > 0) }
    in_log && /^\(none yet/ { skipping = 1; next }
    skipping { if ($0 ~ /^[ \t]*$/) skipping = 0; next }
    { lines[++n] = $0 }
    END {
      while (n > 0 && lines[n] ~ /^[ \t]*$/) n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' "$ab_brief" >"$gtmp/brief.new" || return 1
  printf '\n' >>"$gtmp/brief.new"
  cat "$gtmp/reanchor.entry" >>"$gtmp/brief.new"
  cp "$gtmp/brief.new" "$ab_brief.migrate.tmp"
  mv "$ab_brief.migrate.tmp" "$ab_brief"
  return 0
}

# screen_and_process <dir> <root_phys or ""> — hostile-name and containment
# screening before any content is read (REQ-C1.9).
screen_and_process() {
  sdir=$1
  sroot=$2
  snm=$(basename "$sdir")
  case $snm in
    _*)
      # Reserved non-spec accumulators are never bundles.
      return 0
      ;;
  esac
  if ! check_spec_id "$snm"; then
    refuse "$snm" "spec identifier fails ^[a-z0-9][a-z0-9-]*\$ (max 64); not migrated"
    return 0
  fi
  if [ -L "$sdir" ]; then
    refuse "$snm" "symlinked bundle directory (out of containment); bundles must be real directories"
    return 0
  fi
  if [ -n "$sroot" ]; then
    sdir_phys=$(cd "$sdir" 2>/dev/null && pwd -P) || {
      refuse "$snm" "bundle directory is unreadable"
      return 0
    }
    case $sdir_phys in
      "$sroot"/*) ;;
      *)
        refuse "$snm" "bundle resolves outside the specs root (out of containment)"
        return 0
        ;;
    esac
  fi
  process_bundle "$sdir" "$snm"
}

if [ -f "$target/requirements.md" ] || [ -f "$target/design.md" ] \
  || [ -f "$target/tasks.md" ] || [ -f "$target/test-spec.md" ]; then
  screen_and_process "$target" ""
else
  root_phys=$(cd "$target" && pwd -P) || exit 2
  for d in "$target"/*; do
    { [ -e "$d" ] || [ -L "$d" ]; } || continue # unmatched-glob literal
    if [ -L "$d" ]; then
      if [ -d "$d" ]; then
        refuse "$(basename "$d")" "symlinked bundle directory (out of containment); bundles must be real directories"
      fi
      continue
    fi
    [ -d "$d" ] || continue
    screen_and_process "$d" "$root_phys"
  done
fi

echo "migrate-format-version: $migrated migrated, $completed completed, $unchanged unchanged, $refused refused"
[ "$refused" -eq 0 ]
