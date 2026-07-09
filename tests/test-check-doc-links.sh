#!/bin/bash
# Tests for scripts/check-doc-links.sh — the doctrine cross-reference
# link-check (Task 2 deliverable, wired into CI). The doctrine docs
# cross-reference each other with relative markdown links; a renamed or
# deleted target must fail CI, not rot silently.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-doc-links.sh"

failures=0
assert() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$CHECKER" ]; then
  echo "FAIL: checker script missing at $CHECKER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# 1. The real repo's default scan set passes (every doctrine/docs/README
#    cross-reference resolves).
/bin/bash "$CHECKER" >/dev/null
assert "repo cross-references all resolve" 0 $?

# 2. Fixture: a valid relative link resolves against the linking file's own
#    directory, not the invoker's cwd.
mkdir -p "$tmp/sub"
cat >"$tmp/sub/target.md" <<'EOF'
# Target
EOF
cat >"$tmp/sub/source.md" <<'EOF'
See [the target](target.md).
EOF
(cd / && /bin/bash "$CHECKER" "$tmp/sub/source.md" >/dev/null)
assert "valid relative link passes from any cwd" 0 $?

# 3. Fixture: a broken relative link fails and the output names both the
#    linking file and the missing target.
cat >"$tmp/sub/broken.md" <<'EOF'
See [gone](no-such-file.md).
EOF
out="$(/bin/bash "$CHECKER" "$tmp/sub/broken.md" 2>&1)"
assert "broken link fails" 1 $?
case "$out" in
  *broken.md*no-such-file.md* | *no-such-file.md*broken.md*)
    echo "ok: failure names source and target"
    ;;
  *)
    echo "FAIL: output does not name source and target: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 4. Fixture: external/mailto links are skipped; a same-page #anchor is now
#    verified against the file's own headings (here it resolves).
cat >"$tmp/sub/external.md" <<'EOF'
# A heading

[web](https://example.com/page) and [plain](http://example.com) and
[mail](mailto:a@b.c) and [same-page section](#a-heading).
EOF
/bin/bash "$CHECKER" "$tmp/sub/external.md" >/dev/null
assert "external/mailto skipped; valid same-page anchor resolves" 0 $?

# 5. Fixture: a fragment on a file link is verified against the target file's
#    headings; target.md (test 2) has "# Target", so #target resolves.
cat >"$tmp/sub/fragment.md" <<'EOF'
See [a section](target.md#target).
EOF
/bin/bash "$CHECKER" "$tmp/sub/fragment.md" >/dev/null
assert "file link with valid fragment resolves (anchor verified)" 0 $?

# 5b. A broken same-page #anchor fails and names the missing anchor.
cat >"$tmp/sub/badself.md" <<'EOF'
# Present Heading

See [broken](#absent-heading).
EOF
out="$(/bin/bash "$CHECKER" "$tmp/sub/badself.md" 2>&1)"
assert "broken same-page anchor fails" 1 $?
case "$out" in
  *absent-heading*) echo "ok: the missing same-page anchor is named" ;;
  *)
    echo "FAIL: missing same-page anchor not named: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 5c. A broken anchor on a file link fails and names the target file + anchor.
cat >"$tmp/sub/badxfile.md" <<'EOF'
See [broken](target.md#no-such-section).
EOF
out="$(/bin/bash "$CHECKER" "$tmp/sub/badxfile.md" 2>&1)"
assert "broken cross-file anchor fails" 1 $?
case "$out" in
  *no-such-section*target.md* | *target.md*no-such-section*)
    echo "ok: the missing cross-file anchor and target are named"
    ;;
  *)
    echo "FAIL: cross-file anchor break not named: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 5d. The GitHub slug rule: punctuation dropped, spaces -> hyphens, and internal
#     repeats kept (an em-dash flanked by spaces yields a double hyphen).
cat >"$tmp/sub/slug.md" <<'EOF'
## 6. Secrets and data hygiene — read this

[jump](#6-secrets-and-data-hygiene--read-this)
EOF
/bin/bash "$CHECKER" "$tmp/sub/slug.md" >/dev/null
assert "github slug rule (punctuation/spaces/double-hyphen) matches" 0 $?

# 5e. Documented limitation: duplicate-heading disambiguation is NOT applied.
#     GitHub gives the second "## Setup" the anchor #setup-1; this checker emits
#     the base slug for every heading, so #setup-1 is reported as missing. This
#     test pins that limitation (fail-closed) so a future fix is a conscious
#     change, not a silent regression. See the script header.
cat >"$tmp/sub/dup.md" <<'EOF'
## Setup
## Setup

[second](#setup-1)
EOF
out="$(/bin/bash "$CHECKER" "$tmp/sub/dup.md" 2>&1)"
assert "duplicate-heading -1 anchor fails (documented limitation)" 1 $?
case "$out" in
  *setup-1*) echo "ok: the unsupported disambiguated anchor is named" ;;
  *)
    echo "FAIL: disambiguated anchor not named: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 5f. Documented limitation: fragments are matched literally, not percent-decoded.
#     A URL-encoded anchor (#a%20section) will not match the decoded slug
#     (a-section). Pins the limitation fail-closed; see the script header.
cat >"$tmp/sub/encoded.md" <<'EOF'
# A Section

[encoded](#a%20section)
EOF
out="$(/bin/bash "$CHECKER" "$tmp/sub/encoded.md" 2>&1)"
assert "url-encoded fragment fails (documented limitation)" 1 $?
case "$out" in
  *'a%20section'*) echo "ok: the undecoded fragment is named verbatim" ;;
  *)
    echo "FAIL: undecoded fragment not named: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 5g. Documented leniency: heading-like lines inside fenced code blocks are
#     counted as headings, so an anchor that matches one resolves. The header
#     notes this only ever makes the check more lenient (never a false failure).
cat >"$tmp/sub/fenced.md" <<'EOF'
Below is a code sample, not a real heading:

```sh
# Fenced Pseudo Heading
echo hi
```

[jump](#fenced-pseudo-heading)
EOF
/bin/bash "$CHECKER" "$tmp/sub/fenced.md" >/dev/null
assert "fenced-code heading line is counted (documented leniency)" 0 $?

# 6. Fixture: multiple links on one line are each checked (one broken among
#    valid ones still fails).
cat >"$tmp/sub/multi.md" <<'EOF'
[ok](target.md) then [bad](missing.md) then [web](https://example.com).
EOF
out="$(/bin/bash "$CHECKER" "$tmp/sub/multi.md" 2>&1)"
assert "one broken link among several fails" 1 $?
case "$out" in
  *missing.md*) echo "ok: the broken target is named" ;;
  *)
    echo "FAIL: broken target not named: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 6b. Fixture: a NUL byte in the file does not turn grep into binary mode and
#     emit a "Binary file ... matches" pseudo-target. The link still resolves.
printf '\000[ok](target.md)\000\n' >"$tmp/sub/withnul.md"
out="$(/bin/bash "$CHECKER" "$tmp/sub/withnul.md" 2>&1)"
assert "NUL byte does not produce a binary-mode pseudo-target" 0 $?
case "$out" in
  *"Binary file"*)
    echo "FAIL: binary-mode message leaked as a target: $out" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: no binary-mode pseudo-target" ;;
esac

# 7. A directory target (e.g. a link to a folder) resolves if it exists.
cat >"$tmp/sub/dirlink.md" <<'EOF'
See [the directory](../sub).
EOF
/bin/bash "$CHECKER" "$tmp/sub/dirlink.md" >/dev/null
assert "existing directory target passes" 0 $?

# 8. A missing input file is a usage error (exit 2), distinct from a broken
#    link (exit 1).
/bin/bash "$CHECKER" "$tmp/no-such-input.md" >/dev/null 2>&1
assert "missing input file is a usage error" 2 $?

# 8b. An unreadable input file is also a usage error: a file the checker
#     could not scan must not be reported as "all targets resolve".
#     (Skipped under root, where mode 000 is still readable.)
if [ "$(id -u)" -ne 0 ]; then
  cat >"$tmp/unreadable.md" <<'EOF'
[link](target.md)
EOF
  chmod 000 "$tmp/unreadable.md"
  /bin/bash "$CHECKER" "$tmp/unreadable.md" >/dev/null 2>&1
  assert "unreadable input file is a usage error" 2 $?
  chmod 644 "$tmp/unreadable.md"
fi

# 9. A hostile CDPATH must not corrupt the default-set repo-root derivation
#    (mirrors the options-reference checker's guard).
mkdir -p "$tmp/decoy/scripts"
(CDPATH="$tmp/decoy" /bin/bash "$CHECKER" >/dev/null 2>&1)
assert "CDPATH does not corrupt root derivation" 0 $?

# 10. The default scan set covers skills/<name>/*.md: a broken link in a
#     skill doc must fail the no-arg scan, not rot silently outside it.
#     Fixture repo layout (the script derives repo root from its own path).
mkdir -p "$tmp/fixture/scripts" "$tmp/fixture/skills/demo"
cp "$CHECKER" "$tmp/fixture/scripts/check-doc-links.sh"
# README.md stays link-free on purpose: tests 10/10b/10c attribute failures
# to the skills/ files via their unique targets, so a link added here would
# let them pass or fail for the wrong reason.
cat >"$tmp/fixture/README.md" <<'EOF'
# Fixture
EOF
cat >"$tmp/fixture/skills/demo/SKILL.md" <<'EOF'
See [a doctrine doc](../../doctrine/no-such-doc.md).
EOF
out="$(/bin/bash "$tmp/fixture/scripts/check-doc-links.sh" 2>&1)"
assert "broken link in a skill doc fails the default scan" 1 $?
case "$out" in
  *no-such-doc.md*) echo "ok: the skill doc's broken target is named" ;;
  *)
    echo "FAIL: skill doc's broken target not named: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 10b. The positive arm: a skill doc whose links resolve passes the
#      default scan.
mkdir -p "$tmp/fixture/doctrine"
cat >"$tmp/fixture/doctrine/no-such-doc.md" <<'EOF'
# Now it exists
EOF
/bin/bash "$tmp/fixture/scripts/check-doc-links.sh" >/dev/null
assert "resolving skill-doc link passes the default scan" 0 $?

# 10c. A top-level skills/*.md (e.g. a future skills/README.md) is also in
#      the default scan, matching lint:md's skills/**/*.md coverage at the
#      depths the layout convention supports.
cat >"$tmp/fixture/skills/README.md" <<'EOF'
See [a missing doc](../doctrine/also-missing.md).
EOF
out="$(/bin/bash "$tmp/fixture/scripts/check-doc-links.sh" 2>&1)"
assert "broken link in skills/README.md fails the default scan" 1 $?
case "$out" in
  *also-missing.md*) echo "ok: the top-level skill doc's broken target is named" ;;
  *)
    echo "FAIL: top-level skill doc's broken target not named: $out" >&2
    failures=$((failures + 1))
    ;;
esac
# The exit 1 must be attributable to the new broken link alone: the link
# 10b resolved stays resolved.
case "$out" in
  *no-such-doc.md*)
    echo "FAIL: 10b's resolved link regressed into the 10c output: $out" >&2
    failures=$((failures + 1))
    ;;
  *) echo "ok: 10b's resolved link stays resolved in the 10c scan" ;;
esac

# 11. Doctrine delivery-restriction (D-4, output-hygiene Task 5): a file under
#     doctrine/ may relative-link only ../config/, ../scripts/, and sibling
#     doctrine docs — the trees co-located beside doctrine/ in every delivery
#     mode. A link to ../skills/ or ../docs/ resolves in-repo but is dead once
#     installed (writer-install ships neither as a doctrine sibling), so it is
#     an error even though the target exists. Reference such targets by
#     resolution path in backticks instead.
mkdir -p "$tmp/dr/doctrine" "$tmp/dr/config" "$tmp/dr/scripts" \
  "$tmp/dr/skills/demo" "$tmp/dr/docs"
cat >"$tmp/dr/skills/demo/SKILL.md" <<'EOF'
# Skill
EOF
cat >"$tmp/dr/config/x.yaml" <<'EOF'
x: 1
EOF
cat >"$tmp/dr/scripts/y.sh" <<'EOF'
echo y
EOF
cat >"$tmp/dr/docs/z.md" <<'EOF'
# Z
EOF
cat >"$tmp/dr/doctrine/sibling.md" <<'EOF'
# Sibling
EOF

# 11a. A doctrine link to ../skills/ fails even though the target resolves
#      in-repo (it is delivered-dead), and the failure names the target.
cat >"$tmp/dr/doctrine/bad-skills.md" <<'EOF'
See the [builder skill](../skills/demo/SKILL.md).
EOF
out="$(/bin/bash "$CHECKER" "$tmp/dr/doctrine/bad-skills.md" 2>&1)"
assert "doctrine link to ../skills/ fails (delivered-dead)" 1 $?
case "$out" in
  *skills/demo/SKILL.md*)
    echo "ok: the ../skills/ restriction names the target"
    ;;
  *)
    echo "FAIL: ../skills/ restriction did not name the target: $out" >&2
    failures=$((failures + 1))
    ;;
esac

# 11b. A doctrine link to ../docs/ fails for the same reason (docs/ is not
#      shipped in the writer-install layout).
cat >"$tmp/dr/doctrine/bad-docs.md" <<'EOF'
See [the guide](../docs/z.md).
EOF
/bin/bash "$CHECKER" "$tmp/dr/doctrine/bad-docs.md" >/dev/null 2>&1
assert "doctrine link to ../docs/ fails (not delivered)" 1 $?

# 11c. Permitted forms all pass: ../config/, ../scripts/, a sibling doctrine
#      doc (no ../), and an in-page #anchor.
cat >"$tmp/dr/doctrine/good.md" <<'EOF'
# Good Heading

See [config](../config/x.yaml), [script](../scripts/y.sh),
[sibling](sibling.md), and [self](#good-heading).
EOF
/bin/bash "$CHECKER" "$tmp/dr/doctrine/good.md" >/dev/null 2>&1
assert "doctrine ../config, ../scripts, sibling, and anchor links pass" 0 $?

# 11d. The restriction is scoped to doctrine/ files only: a non-doctrine file
#      (here under docs/) linking ../skills/ is unaffected — no delivery rule
#      applies to it, and the target resolves.
cat >"$tmp/dr/docs/uses-skill.md" <<'EOF'
See [the skill](../skills/demo/SKILL.md).
EOF
/bin/bash "$CHECKER" "$tmp/dr/docs/uses-skill.md" >/dev/null 2>&1
assert "non-doctrine file linking ../skills/ is not restricted" 0 $?

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all check-doc-links tests passed"
