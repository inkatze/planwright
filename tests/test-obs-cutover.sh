#!/bin/sh
# Tree-state test for the observation-recording Tasks 5+6 cutover
# (REQ-E1.1 [test], REQ-E1.3 [test]; D-5, D-8). Unlike the fixture-based
# sibling tests, this suite asserts the *repository tree itself* holds the
# post-migration state: the legacy accumulator files are frozen, no shipped
# skill/doctrine/docs text still instructs an append to the shared log, every
# recording skill routes through the shared helper, and the standing fragment
# guard passes over the real observations directory.
#
# Properties verified (numbered to match the body's check sections):
#   1. Freeze headers (REQ-E1.1): specs/_observations/opportunities.md and
#      archive.md each open with a freeze header naming the fragment
#      substrate and specs/observation-recording.
#   2. No shipped append instruction (REQ-E1.3, Task 5 done-when): across
#      skills/, doctrine/, and docs/, no text instructs appending to
#      opportunities.md (matched as any "append…" within a sentence-sized
#      window of the filename, newline-insensitive). Mentions of the frozen
#      file as a mining source or legacy-consume surface remain legitimate.
#   3. Recording contract (REQ-E1.3, REQ-A1.6 design-level): all ten shipped
#      skills name obs-record.sh for their observation writes.
#   4. Mining contract (REQ-E1.3, REQ-C1.2): /spec-draft, the canonical
#      reader, names obs-consume.sh for consumption/archival.
#   5. Post-migration guard (REQ-E1.1): scripts/check-obs.sh exits 0 over the
#      real specs/_observations tree (null-safe while the on-demand fragment
#      directories are still absent).
#   6. Dedup invariant (REQ-E1.1): no live opportunities.md entry, once any
#      consumed-by annotation is stripped, exactly matches an already-consumed
#      archive.md entry — i.e. no resurrected duplicate survives or is
#      reintroduced. This is the standing guard over Task 6's dedup deliverable.
#
# Runs standalone under /bin/bash (the bash 3.2 floor) and /bin/sh.
set -eu

# Pin the C locale: range patterns are collation-dependent under UTF-8.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into command substitutions,
# corrupting derived paths (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# --- 1. freeze headers ------------------------------------------------------

for f in opportunities.md archive.md; do
  legacy="$root/specs/_observations/$f"
  [ -f "$legacy" ] || fail "missing frozen legacy file: specs/_observations/$f"
  # The freeze header is the first non-blank line after the H1 title; require
  # both the freeze marker and the owning spec within the file's head.
  if ! head -10 "$legacy" | grep -q 'Frozen'; then
    fail "specs/_observations/$f carries no freeze header (REQ-E1.1)"
  fi
  if ! head -10 "$legacy" | grep -q 'specs/observation-recording'; then
    fail "specs/_observations/$f freeze header does not name specs/observation-recording"
  fi
done

# --- 2. no shipped append instruction ---------------------------------------

# Sentence-scoped, newline-insensitive proximity match: an "append…" verb and
# the shared-log filename in the same period-delimited sentence, in either
# order. Legitimate mentions of the frozen file (mining source, legacy-consume
# arm) sit in sentences that carry no append verb. Implemented in awk (single
# linear pass) rather than a flattened-line regex: the `[^.]{0,140}` window form
# backtracks pathologically under some POSIX greps (ugrep measured ~47s/file),
# while the sentence split runs in constant time under any awk.
offenders=""
for f in $(find "$root/skills" "$root/doctrine" "$root/docs" -name '*.md' | sort); do
  if awk '
    { buf = buf " " tolower($0) }
    END {
      # Neutralize the filename period so the token survives the sentence split.
      gsub(/opportunities\.md/, " oppmd ", buf)
      m = split(buf, s, /\./)
      for (i = 1; i <= m; i++)
        if (s[i] ~ /oppmd/ && s[i] ~ /append/) { exit 0 }
      exit 1
    }
  ' "$f"; then
    offenders="$offenders ${f#"$root"/}"
  fi
done
[ -z "$offenders" ] || fail "shipped text still instructs appending to the shared log:$offenders"

# --- 3. every recording skill names the shared recording helper --------------

for s in spec-draft spec-kickoff execute-task self-review polish drain \
  orchestrate builder resume spec-walkthrough; do
  skill="$root/skills/$s/SKILL.md"
  [ -f "$skill" ] || fail "missing skill file: skills/$s/SKILL.md"
  grep -q 'obs-record\.sh' "$skill" \
    || fail "skills/$s/SKILL.md does not route recording through obs-record.sh (REQ-E1.3)"
done

# --- 4. the mining path names the consumption helper -------------------------

grep -q 'obs-consume\.sh' "$root/skills/spec-draft/SKILL.md" \
  || fail "skills/spec-draft/SKILL.md does not route consumption through obs-consume.sh (REQ-C1.2)"

# --- 5. the standing guard passes over the real tree -------------------------

if ! /bin/sh "$root/scripts/check-obs.sh" --obs-dir "$root/specs/_observations" >/dev/null 2>&1; then
  fail "check-obs.sh fails over the post-migration specs/_observations tree (REQ-E1.1)"
fi

# --- 6. no resurrected duplicate survives in the frozen live log -------------

# The union-of-appends merge bug resurrected already-consumed lines back into
# opportunities.md; Task 6's dedup removed them. A "resurrected duplicate" is a
# live entry whose text — with any consumed-by annotation stripped — exactly
# matches a consumed archive.md entry (its own annotation likewise stripped).
# A frozen legacy line consumed in place keeps its text and only gains an
# annotation, so it never matches an archived (moved-fragment) entry; only a
# genuine resurrection collides. LC_ALL=C is already pinned above so the
# em-dash bytes compare literally.
resurrected=$(awk '
  function norm(s) {
    sub(/[ \t]*(—|--)[ \t]*consumed-by:.*$/, "", s); sub(/[ \t]+$/, "", s); return s
  }
  FNR==NR { if ($0 ~ /^- /) archived[norm($0)] = 1; next }
  /^- /   { n = norm($0); if (n in archived) print $0 }
' "$root/specs/_observations/archive.md" "$root/specs/_observations/opportunities.md")
[ -z "$resurrected" ] || fail "resurrected duplicate(s) survive in opportunities.md (REQ-E1.1):
$resurrected"

echo "PASS: test-obs-cutover"
