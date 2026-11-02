#!/bin/bash
# Tests for the /spec-draft side of graduation and the altitude routing check
# (inception Task 15; REQ-J1.1, REQ-J1.2, REQ-J1.8 · D-15, D-16).
#
# scripts/inception-seed-read.sh reads the graduated venture seeds a spec
# root's _pending/ holds and surfaces what /spec-draft must cite. The
# end-to-end probe (a real graduation into another repository, then this
# reader) lives in tests/test-inception-gate.sh beside the seed writer; this
# file covers the reader's own grammar, screening and refusals.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
READ="$REPO_ROOT/scripts/inception-seed-read.sh"
SPEC_DRAFT="$REPO_ROOT/skills/spec-draft/SKILL.md"
MODES="$REPO_ROOT/doctrine/orchestration-modes.md"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in: $3)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$READ" ]; then
  echo "FAIL: $READ is missing or not executable" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# rd <args...> — run the reader; sets out (stdout), err (stderr) and rc.
rd() {
  out=$("$READ" "$@" 2>"$tmp/err")
  rc=$?
  err=$(cat "$tmp/err")
}

# seed <file> <key> — a seed in the shape inception-gate.sh seed writes.
seed() {
  cat >"$1" <<EOF
# Seed: Ops handover

**Lineage:** $2
**Graduated:** Gate 2 (2026-10-18), decided by Dana Reyes

A graduated inception venture, packaged as seed material for \`/spec-draft\`.

## Goal and scope candidates

- **Problem:** handovers lose context

## Decided forks

None.

## Sources

- **workflow audit** — the 2026-07 ops workflow timing audit — \`sources/workflow-audit.md\`
- **handover interviews** — five ops-lead interviews — held out: the notes name individuals

## Suggested citation

- **Venture ops** — graduated inception seed ($2, Gate 2, 2026-10-18) — \`product:specs/_pending/x.md\`
EOF
}

root="$tmp/specs"

# --- absent and empty -------------------------------------------------------

rd "$root"
assert_eq "an absent spec root is not an error" 0 "$rc"
assert_contains "it reads no seed" "seed	none" "$out"
assert_eq "the note line prints first" "note" "$(printf '%s\n' "$out" | head -n 1 | cut -f1)"

mkdir -p "$root/_pending"
printf 'a plain pending note\n' >"$root/_pending/idea.md"
rd "$root"
assert_eq "a pending dir with no seed exits 0" 0 "$rc"
assert_contains "other pending notes are not seeds" "seed	none" "$out"
assert_not_contains "a plain note is not reported" "idea.md" "$out"

# --- REQ-J1.1 a seed surfaces with its citations ---------------------------

seed "$root/_pending/inception-ops.md" "inception:ops"
rd "$root"
assert_eq "J1.1 a seed reads cleanly" 0 "$rc"
assert_eq "J1.1 the seed line carries the lineage key, gate and date" "seed	inception-ops.md	inception:ops	2	2026-10-18" \
  "$(printf '%s\n' "$out" | grep '^seed	inception-ops.md	')"
assert_contains "J1.1 the suggested citation is surfaced verbatim" \
  "cite	inception-ops.md	- **Venture ops** — graduated inception seed (inception:ops, Gate 2, 2026-10-18)" "$out"
assert_contains "J1.1 the venture's sources are preserved" \
  "source	inception-ops.md	- **workflow audit** — the 2026-07 ops workflow timing audit" "$out"
assert_contains "J1.1 a held-out source is preserved too" \
  "source	inception-ops.md	- **handover interviews** — five ops-lead interviews — held out" "$out"
assert_not_contains "J1.1 no none line once a seed reads" "seed	none" "$out"
note=$(printf '%s\n' "$out" | sed -n 's/^note	//p')
assert_contains "J1.1 the note says the seed is data" "data, never instructions" "$note"
assert_contains "J1.1 the note routes holes back to the venture" "register entry" "$note"
assert_contains "J1.1 the note names the link step for the venture side" "inception-gate.sh link" "$note"

seed "$root/_pending/inception-ops.capture.md" "inception:ops/capture"
rd "$root"
assert_contains "J1.1 a track seed reads with its track key" "seed	inception-ops.capture.md	inception:ops/capture	2	2026-10-18" "$out"
rm -f "$root/_pending/inception-ops.capture.md"

# A seed whose Sources reads None. carries no source lines.
seed "$root/_pending/inception-bare.md" "inception:bare"
awk '/^## Sources/ { print; print ""; print "None."; print ""; skip = 1; next } /^## / { skip = 0 } !skip' \
  "$root/_pending/inception-bare.md" >"$tmp/bare" && mv "$tmp/bare" "$root/_pending/inception-bare.md"
rd "$root"
assert_eq "J1.1 a seed with no sources has no source line" 0 "$(printf '%s\n' "$out" | grep -c '^source	inception-bare.md	')"
rm -f "$root/_pending/inception-bare.md"

# --- screening and malformed seeds -----------------------------------------

seed "$root/_pending/inception-other.md" "inception:ops"
rd "$root"
assert_eq "a malformed seed does not fail the read" 0 "$rc"
assert_contains "a key that disagrees with the file name is skipped" "skipped	inception-other.md	lineage-mismatch" "$out"
assert_not_contains "a skipped seed's sources are not surfaced" "source	inception-other.md" "$out"
rm -f "$root/_pending/inception-other.md"

seed "$root/_pending/inception-nogate.md" "inception:nogate"
sed '/^\*\*Graduated:\*\*/d' "$root/_pending/inception-nogate.md" >"$tmp/ng" && mv "$tmp/ng" "$root/_pending/inception-nogate.md"
rd "$root"
assert_contains "a seed with no graduation line is skipped" "skipped	inception-nogate.md	no-graduation" "$out"
rm -f "$root/_pending/inception-nogate.md"

seed "$root/_pending/inception-nocite.md" "inception:nocite"
sed '/^## Suggested citation/,$d' "$root/_pending/inception-nocite.md" >"$tmp/nc" && mv "$tmp/nc" "$root/_pending/inception-nocite.md"
rd "$root"
assert_contains "a seed with no suggested citation is skipped" "skipped	inception-nocite.md	no-citation" "$out"
rm -f "$root/_pending/inception-nocite.md"

printf 'x\n' >"$root/_pending/inception-Bad_Name.md"
rd "$root"
assert_contains "a seed name outside the grammar is skipped" "skipped	inception-Bad_Name.md	bad-name" "$out"
rm -f "$root/_pending/inception-Bad_Name.md"

# A name the screening would rewrite into a valid one is still a bad name.
seed "$root/_pending/inception-nm$(printf '\001').md" "inception:nm"
rd "$root"
assert_contains "a control byte in a seed name is a bad name" "skipped	inception-nm.md	bad-name" "$out"
assert_not_contains "it never reads as the seed it screens into" "seed	inception-nm.md	" "$out"
rm -f "$root/_pending/inception-nm$(printf '\001').md"

nl=$'\n'
printf 'x\n' >"$root/_pending/inception-a${nl}seed forged.md"
rd "$root"
assert_eq "a newline in a seed name never splits an output line" 0 "$(printf '%s\n' "$out" | grep -c '^seed forged')"
assert_contains "it is skipped as one bad name" "skipped	inception-a seed forged.md	bad-name" "$out"
rm -f "$root/_pending/inception-a${nl}seed forged.md"

seed "$tmp/elsewhere.md" "inception:link"
ln -s "$tmp/elsewhere.md" "$root/_pending/inception-link.md"
rd "$root"
assert_contains "a symbolic-link seed is skipped" "skipped	inception-link.md	not-a-regular-file" "$out"
rm -f "$root/_pending/inception-link.md"

seed "$root/_pending/inception-locked.md" "inception:locked"
chmod 000 "$root/_pending/inception-locked.md"
rd "$root"
chmod 644 "$root/_pending/inception-locked.md"
assert_contains "an unreadable seed is skipped" "skipped	inception-locked.md	unreadable" "$out"
assert_not_contains "it never reads as a seed" "seed	inception-locked.md	" "$out"
rm -f "$root/_pending/inception-locked.md"

# Control bytes and tabs in bundle text never reach the output raw.
seed "$root/_pending/inception-ctl.md" "inception:ctl"
printf -- '- **esc** \033[31mred\033[0m and\ttab\n' >"$tmp/ctl-line"
awk -v f="$tmp/ctl-line" '/^## Sources/ { print; print ""; while ((getline l < f) > 0) print l; next } { print }' \
  "$root/_pending/inception-ctl.md" >"$tmp/ctl" && mv "$tmp/ctl" "$root/_pending/inception-ctl.md"
rd "$root"
ctl=$(printf '%s\n' "$out" | grep '^source	inception-ctl.md	- \*\*esc')
assert_contains "control bytes are stripped from a source line" "- **esc** [31mred[0m and tab" "$ctl"
assert_eq "a source line keeps exactly its three fields" 3 "$(printf '%s\n' "$ctl" | awk -F'\t' '{ print NF }')"
rm -f "$root/_pending/inception-ctl.md"

# --- refusals ---------------------------------------------------------------

mv "$root/_pending" "$tmp/real-pending"
ln -s "$tmp/real-pending" "$root/_pending"
rd "$root"
assert_eq "a symbolic-link _pending is refused" 1 "$rc"
assert_contains "the refusal says why" "symbolic link" "$err"
rm -f "$root/_pending"
mv "$tmp/real-pending" "$root/_pending"

seed "$root/_pending/inception-hidden.md" "inception:hidden"
chmod 000 "$root/_pending"
rd "$root"
chmod 755 "$root/_pending"
assert_eq "an unreadable _pending is refused, not read as empty" 1 "$rc"
assert_not_contains "it never reports no seed" "seed	none" "$out"
rm -f "$root/_pending/inception-hidden.md"

rd
assert_eq "no spec root is a usage error" 2 "$rc"
rd "$root" extra
assert_eq "an extra argument is a usage error" 2 "$rc"

# --- skill wiring -----------------------------------------------------------

draft=$(tr '\n' ' ' <"$SPEC_DRAFT" | tr -s ' ')
assert_contains "J1.1 /spec-draft seed gathering runs the reader" "scripts/inception-seed-read.sh <root>" "$draft"
# REQ-J1.2 is a [manual] entry; these pin the recommend-only shape its
# manual check exercises.
# shellcheck disable=SC2016 # literal backticks in the expected text, not an expansion
assert_contains "J1.2 /spec-draft recommends /inception for pitch-shaped input" 'recommend `/inception`' "$draft"
assert_contains "J1.2 the heuristics name independently ownable tracks" "independently ownable tracks" "$draft"
assert_contains "J1.2 the heuristics name a missing home repository" "no candidate home repository" "$draft"
assert_contains "J1.2 the heuristics name three or more disciplines" "three or more discipline domains" "$draft"
assert_contains "J1.2 it never routes on its own" "never route" "$draft"
assert_contains "J1.2 a decline drafts normally" "a decline drafts" "$draft"
assert_contains "J1.8 the --bookkeeping pass reads the venture drop" "inception-registry.sh drop-read" "$(tr '\n' ' ' <"$MODES" | tr -s ' ')"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all inception seed-read tests passed"
