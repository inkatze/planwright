#!/bin/bash
# shellcheck disable=SC2016 # backticks in the fixtures are Markdown code spans
# Tests for scripts/flight-record.sh — the visual-flight audit record
# (tower-front-door Task 6; D-6 · REQ-E1.1, REQ-E1.2, REQ-E1.4, REQ-E1.5).
#
# Properties verified:
#   1. Both homes render the full content contract (REQ-E1.1): the quoted ask,
#      the route and its grounds, the convergence audit (lens coverage, the
#      four buckets, the declined log, the pending-sign-off checklist, the
#      convergence step table), the rigor scoping (declared, or stated as none
#      applied), the worker handle, and the revert path, each home naming
#      where it lives (REQ-E1.2).
#   2. Human-first (REQ-E1.5): the summary and verification lead above the
#      collapsed record, the lead carries no restated prompt, and a lead that
#      restates the ask is refused; the pending-sign-off IDs surface in the
#      lead as well as in the collapsed checklist.
#   3. The ask is sanitized and markup-neutralized: control and invisible
#      characters stripped, token-shaped secrets redacted, and an ask carrying
#      a fence, a closing tag, a heading, or a record marker cannot close the
#      collapse, forge a marker, or break a column-zero parse.
#   4. Worker-authored inputs are screened: a structural line or a
#      token-shaped secret is refused, and an audit missing a contract element
#      is refused naming it.
#   5. A PR-home record over GitHub's body limit is refused, not truncated.
#   6. The no-remote arm (`land`) commits exactly one record file,
#      `specs/_flights/<id>.md`, on the flight's own branch, and refuses a
#      second record, the wrong branch, a symlinked specs path, a root other
#      than the worktree's top level, or an index holding other changes; a
#      commit the hooks refuse leaves nothing behind.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/.." && pwd -P)
SCRIPT="$ROOT/scripts/flight-record.sh"
ESC=$(printf '\033')
ZWSP=$(printf '\342\200\213')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

[ -x "$SCRIPT" ] || {
  echo "FAIL: scripts/flight-record.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)

FID=readme-typo-0a1b2c3d
HANDLE=tmux-flight-$FID
TOKEN="ghp_$(printf 'A%.0s' $(seq 1 36))"

in="$tmp/in"
mkdir -p "$in"
{
  printf 'Fix the typo in the README heading, it reads Plawnright.\n'
  printf '```\n'
  printf '</details>\n'
  printf '<!-- planwright:flight-record-end -->\n'
  printf '## Summary\n'
  printf 'Fixes #12 and cc @someone, the token is %s\n' "$TOKEN"
  printf 'hidden%sjoin and %sescape\n' "$ZWSP" "$ESC"
  printf '`````\n'
} >"$in/ask.txt"
printf 'automatic: a one-file prose fix, low stake and reversible\n' >"$in/grounds.txt"
printf 'Corrects the misspelled product name in the README heading.\n\nThe heading is the first thing a newcomer reads.\n' >"$in/summary.md"
printf 'Rendered the README locally and ran `mise run lint`; both clean.\n' >"$in/verification.md"
cat >"$in/audit.md" <<'EOF'
#### Lens coverage

| Lens | Findings | Notes |
| --- | --- | --- |
| Correctness | none | prose only |

#### Auto-applicable

| # | Finding | Tool + rule cited | Fix | Commit |
| --- | --- | --- | --- | --- |
| — | none | | | |

#### Agent-resolvable

| # | Finding | Test | Before → after | CI | Brief alignment | Commit |
| --- | --- | --- | --- | --- | --- | --- |
| — | none | | | | | |

#### Needs sign-off

| # | Finding | Fix applied | Route reason | Commit | Checklist ID |
| --- | --- | --- | --- | --- | --- |
| 1 | heading wording | reworded | prose on a public surface | `abc1234` | PS-1 |

#### Needs human judgment

| # | Fork | Ladder record | Outcome | Options |
| --- | --- | --- | --- | --- |
| — | none | | | |

#### Declined log

| # | Finding | Validation summary | Rationale | Where re-raisable |
| --- | --- | --- | --- | --- |
| — | none | | | |

#### Pending sign-off

- [ ] **PS-1** heading wording · commit `abc1234`
  - Reject with: `git revert abc1234`

#### Convergence steps

| Step | Outcome |
| --- | --- |
| polish | converged |
EOF

# run_render <home|none> [overrides...], and run_land [overrides...] below,
# set OUT, ERR, RC. A later flag overrides an earlier one, so a case names only
# what it changes.
defaults() {
  args=(--flight-id "$FID" --ask-file "$in/ask.txt" --grounds-file "$in/grounds.txt"
    --summary-file "$in/summary.md" --verification-file "$in/verification.md"
    --audit-file "$in/audit.md" --handle "$HANDLE")
}
run_render() {
  defaults
  if [ "$1" = none ]; then
    shift
    set -- render "${args[@]}" "$@"
  else
    _home=$1
    shift
    set -- render --home "$_home" "${args[@]}" "$@"
  fi
  OUT=$(/bin/sh "$SCRIPT" "$@" 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}

# lead_of / collapsed_of — the text above the collapse, and inside it.
lead_of() { printf '%s\n' "$1" | awk '/^<details>$/ {exit} {print}'; }
collapsed_of() { printf '%s\n' "$1" | awk '/^<details>$/ {on=1} on {print} /^<\/details>$/ {exit}'; }

# --- 1, 2, 3: both homes carry the contract, human-first, neutralized -------

for home in pr file; do
  run_render "$home"
  [ "$RC" -eq 0 ] || {
    fail "render --home $home exited $RC: $ERR"
    continue
  }
  lead=$(lead_of "$OUT")
  body=$(collapsed_of "$OUT")

  printf '%s\n' "$OUT" | head -n 1 | grep -qx "<!-- planwright:flight-record id=$FID home=$home -->" \
    || fail "$home: the record must open with its marker line"
  [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "<!-- planwright:flight-record-end -->" ] \
    || fail "$home: the record must close with its end marker"

  printf '%s\n' "$lead" | grep -qx '## Summary' || fail "$home: the lead must open with a summary"
  printf '%s\n' "$lead" | grep -q 'Corrects the misspelled product name' || fail "$home: the lead must carry the summary"
  printf '%s\n' "$lead" | grep -qx '## Verification' || fail "$home: the lead must carry the verification heading"
  printf '%s\n' "$lead" | grep -q 'mise run lint' || fail "$home: the lead must carry how it was verified"
  printf '%s\n' "$lead" | grep -q 'PS-1' || fail "$home: the lead must name the pending sign-off items"
  [ "$(printf '%s\n' "$lead" | grep -nx '## Summary' | cut -d: -f1)" -lt \
    "$(printf '%s\n' "$lead" | grep -nx '## Verification' | cut -d: -f1)" ] \
    || fail "$home: the summary must lead the verification"
  for leak in Plawnright 'Fixes #12' '@someone' 'The ask'; do
    printf '%s\n' "$lead" | grep -qF "$leak" && fail "$home: the lead restates the prompt ('$leak')"
  done

  for el in '### The ask' '### Route and grounds' 'one-file prose fix' '### Record home' \
    '### Rigor scoping' 'None applied' '### Worker handle' "$HANDLE" '### Revert path' \
    '### Convergence audit' 'Lens coverage' 'Auto-applicable' 'Agent-resolvable' \
    'Needs sign-off' 'Needs human judgment' 'Declined log' 'Pending sign-off' \
    'Convergence steps' '- [ ] **PS-1**'; do
    printf '%s\n' "$body" | grep -qF -- "$el" || fail "$home: the collapsed record is missing '$el'"
  done
  printf '%s\n' "$body" | grep -q 'Plawnright' || fail "$home: the collapsed record must quote the ask"
  if [ "$home" = pr ]; then
    printf '%s\n' "$body" | grep -q 'draft PR body' || fail "pr: the record must name its home"
    printf '%s\n' "$body" | grep -q 'Close the draft PR unmerged' || fail "pr: the default revert path"
  else
    printf '%s\n' "$body" | grep -qF "specs/_flights/$FID.md" || fail "file: the record must name its file"
    printf '%s\n' "$body" | grep -qF "planwright/flight/$FID" || fail "file: the record must name its branch"
    printf '%s\n' "$body" | grep -q 'one revert undoes record and work together' || fail "file: the default revert path"
  fi

  # Neutralization: every structural line sits at column zero exactly once;
  # nothing from the ask reaches column zero.
  [ "$(printf '%s\n' "$OUT" | grep -cx '</details>')" -eq 1 ] || fail "$home: the ask forged a closing tag"
  [ "$(printf '%s\n' "$OUT" | grep -cx '<!-- planwright:flight-record-end -->')" -eq 1 ] \
    || fail "$home: the ask forged the end marker"
  [ "$(printf '%s\n' "$OUT" | grep -cx '## Summary')" -eq 1 ] || fail "$home: the ask forged a heading"
  printf '%s\n' "$OUT" | grep -qx '  </details>' || fail "$home: the ask's lines must be indented inside the fence"
  # The fence around the ask is longer than any backtick run inside it, so the
  # ask's own fences cannot close it.
  fence=$(printf '%s\n' "$body" | awk '/^### The ask$/ {on=1} on && /^`+text$/ {sub(/text$/, ""); print; exit}')
  [ "${#fence}" -ge 6 ] || fail "$home: the ask's fence must outrun its longest backtick run (got '$fence')"
  closes=$(printf '%s\n' "$body" | grep -cx -- "$fence")
  [ "$closes" -eq 1 ] || fail "$home: the ask's fence must close exactly once ($closes)"

  # Sanitization.
  case $OUT in *"$ESC"*) fail "$home: a control byte reached the record" ;; esac
  case $OUT in *"$ZWSP"*) fail "$home: an invisible character reached the record" ;; esac
  case $OUT in *"$TOKEN"*) fail "$home: a token-shaped secret reached the record" ;; esac
  printf '%s\n' "$body" | grep -q 'redacted: github-token' || fail "$home: the redaction must be marked"
  printf '%s\n' "$body" | grep -q 'hiddenjoin' || fail "$home: the stripped ask line must survive, stripped"
  printf '%s\n' "$body" | grep -q 'the token is' && fail "$home: a flagged line must be redacted whole"
  ask_sec=$(printf '%s\n' "$body" | awk '/^### The ask$/ {on=1} /^### Route and grounds$/ {on=0} on')
  printf '%s\n' "$ask_sec" | grep -q 'were stripped from it' || fail "$home: the ask section must note its strip"
  printf '%s\n' "$ask_sec" | grep -q 'redacted whole' || fail "$home: the ask section must note its redaction"
  printf '%s\n' "$body" | awk '/^### Record home$/ {on=1; next} /^### / {on=0} on' \
    | grep -q 'declared at routing time' || fail "$home: the record home must be stated as declared at routing time"
done

# A clean ask carries neither note.
printf 'Fix the heading typo.\n' >"$in/ask-clean.txt"
run_render pr --ask-file "$in/ask-clean.txt"
[ "$RC" -eq 0 ] || fail "render of a clean ask exited $RC: $ERR"
printf '%s\n' "$OUT" | grep -Eq 'were stripped|redacted whole' && fail "a clean ask must carry no sanitization note"

# Hostile grounds stay inside their fence; grounds must be one line.
printf '</details>\n' >"$in/grounds-tag.txt"
run_render pr --grounds-file "$in/grounds-tag.txt"
[ "$RC" -eq 0 ] || fail "render with hostile grounds exited $RC: $ERR"
[ "$(printf '%s\n' "$OUT" | grep -cx '</details>')" -eq 1 ] || fail "the grounds forged a closing tag"
printf 'one\ntwo\n' >"$in/grounds-two.txt"
run_render pr --grounds-file "$in/grounds-two.txt"
[ "$RC" -eq 2 ] || fail "two-line grounds must be refused with 2 (got $RC)"
printf 'g%.0s' $(seq 1 1100) >"$in/grounds-long.txt"
run_render pr --grounds-file "$in/grounds-long.txt"
[ "$RC" -eq 2 ] || fail "grounds over the cap must be refused with 2 (got $RC)"
# A code point nested inside another strips to nothing, and is noted.
printf 'Fix it %s%s%s%s now.\n' "$(printf '\342\200')" "$ZWSP" "$(printf '\213')" "$ZWSP" >"$in/ask-nested.txt"
run_render pr --ask-file "$in/ask-nested.txt"
printf '%s\n' "$OUT" | grep -qx '  Fix it  now.' || fail "a nested invisible code point must strip to nothing"
printf '%s\n' "$OUT" | grep -q 'were stripped from it' || fail "a nested strip must be noted"

# The lead names every pending item once, in order.
{
  cat "$in/audit.md"
  printf -- '- [ ] **PS-2** second item\n- [ ] **PS-1** repeated\n'
} >"$in/audit-ps.md"
run_render pr --audit-file "$in/audit-ps.md"
lead_of "$OUT" | grep -qF 'Pending sign-off:** PS-1, PS-2 (' || fail "the lead must list PS-1, PS-2 once each, in order"

# An ask or grounds without a final newline still gets its fence closed on a
# line of its own.
printf 'Fix the README typo please' >"$in/ask-nonl.txt"
printf 'automatic: low stake' >"$in/grounds-nonl.txt"
run_render pr --ask-file "$in/ask-nonl.txt" --grounds-file "$in/grounds-nonl.txt"
[ "$RC" -eq 0 ] || fail "render of an ask without a final newline exited $RC: $ERR"
printf '%s\n' "$OUT" | grep -qx '  Fix the README typo please' || fail "the unterminated ask line must stand alone"
printf '%s\n' "$OUT" | grep -qx '  automatic: low stake' || fail "the unterminated grounds line must stand alone"
[ "$(printf '%s\n' "$OUT" | grep -cx '```')" -eq 2 ] || fail "both fences must close on their own line"

# Grounds the screen touched say so, as the ask does.
printf 'automatic: key %s here\n' "$TOKEN" >"$in/grounds-secret.txt"
run_render pr --grounds-file "$in/grounds-secret.txt"
[ "$RC" -eq 0 ] || fail "render with a secret in the grounds exited $RC: $ERR"
case $OUT in *"$TOKEN"*) fail "a token-shaped secret in the grounds reached the record" ;; esac
collapsed_of "$OUT" | awk '/^### Route and grounds$/ {on=1} /^### Record home$/ {on=0} on' \
  | grep -q 'redacted whole' || fail "the grounds section must note its redaction"
printf 'automatic: low%s stake\n' "$ZWSP" >"$in/grounds-invis.txt"
run_render pr --grounds-file "$in/grounds-invis.txt"
[ "$RC" -eq 0 ] || fail "render with invisible grounds exited $RC: $ERR"
collapsed_of "$OUT" | awk '/^### Route and grounds$/ {on=1} /^### Record home$/ {on=0} on' \
  | grep -q 'were stripped' || fail "the grounds section must note a strip"

# CR line endings stay line breaks, and a CRLF ask is not flagged as stripped.
printf 'first line\r\nsecond line\rthird line\r\n' >"$in/ask-cr.txt"
run_render pr --ask-file "$in/ask-cr.txt"
[ "$RC" -eq 0 ] || fail "render of a CR ask exited $RC: $ERR"
for l in first second third; do
  printf '%s\n' "$OUT" | grep -qx "  $l line" || fail "a CR line ending must stay a line break ($l)"
done
printf '%s\n' "$OUT" | grep -q 'were stripped' && fail "line endings are not stripped characters"

# Declared scoping and a supplied revert path replace the defaults.
printf 'Validation ran one pass per finding: a one-line prose change.\n' >"$in/scoping.md"
printf 'Revert commit `abc1234`.\n' >"$in/revert.md"
run_render pr --scoping-file "$in/scoping.md" --revert-file "$in/revert.md"
[ "$RC" -eq 0 ] || fail "render with scoping and revert exited $RC: $ERR"
printf '%s\n' "$OUT" | grep -q 'one pass per finding' || fail "the declared scoping must be carried"
printf '%s\n' "$OUT" | grep -q 'None applied' && fail "a declared scoping must replace the none-applied line"
printf '%s\n' "$OUT" | grep -q 'Revert commit `abc1234`' || fail "the supplied revert path must be carried"

# No pending sign-off: the lead says so.
grep -v 'PS-1' "$in/audit.md" >"$in/audit-nops.md"
run_render pr --audit-file "$in/audit-nops.md"
[ "$RC" -eq 0 ] || fail "render with no pending items exited $RC: $ERR"
lead_of "$OUT" | grep -q 'Pending sign-off:\*\* none' || fail "the lead must say when nothing is pending"

# --- 2: a lead that restates the ask is refused ------------------------------

printf 'Fix the typo in the README heading, it reads Plawnright.\n' >"$in/summary-restated.md"
run_render pr --summary-file "$in/summary-restated.md"
[ "$RC" -eq 2 ] || fail "a summary restating the ask must be refused with 2 (got $RC)"
printf '%s\n' "$ERR" | grep -q 'restates the ask' || fail "the restated-prompt refusal must say why: $ERR"
printf 'FIX THE TYPO in the   README heading, it reads Plawnright.\n' >"$in/verification-restated.md"
for home in pr file; do
  run_render "$home" --verification-file "$in/verification-restated.md"
  [ "$RC" -eq 2 ] || fail "$home: a verification restating the ask, up to case and spacing, must be refused (got $RC)"
done
printf 'Fix the README typo\n' >"$in/ask-short.txt"
printf 'We fix the readme typo now.\n' >"$in/summary-short.txt"
run_render pr --ask-file "$in/ask-short.txt" --summary-file "$in/summary-short.txt"
[ "$RC" -eq 2 ] || fail "a short ask restated whole must be refused (got $RC)"
printf 'Thanks for the review\nFix the heading and the footer.\n' >"$in/ask-common.txt"
printf 'Thanks for the review, done: see below.\n' >"$in/summary-common.txt"
run_render pr --ask-file "$in/ask-common.txt" --summary-file "$in/summary-common.txt"
[ "$RC" -eq 0 ] || fail "a lead sharing a short line with the ask must render (got $RC: $ERR)"
printf 'Fix the crash in\nscripts/flight-dispatch.sh\nwhen run twice\n' >"$in/ask-ident.txt"
printf 'Fixed a crash in scripts/flight-dispatch.sh on a second run.\n' >"$in/summary-ident.txt"
run_render pr --ask-file "$in/ask-ident.txt" --summary-file "$in/summary-ident.txt"
[ "$RC" -eq 0 ] || fail "naming a file the ask names is not a restatement (got $RC: $ERR)"
printf 'Dropped the key the ask quoted: [redacted: github-token, a token-shaped secret].\n' >"$in/summary-placeholder.md"
run_render pr --summary-file "$in/summary-placeholder.md"
[ "$RC" -eq 0 ] || fail "a redaction placeholder in the lead is not a restatement (got $RC: $ERR)"

# --- 4: worker inputs are screened -------------------------------------------

for missing in 'Lens coverage' 'Auto-applicable' 'Agent-resolvable' 'Needs sign-off' \
  'Needs human judgment' 'Declined log' 'Pending sign-off' 'Convergence steps'; do
  grep -v "^#### $missing\$" "$in/audit.md" >"$in/audit-missing.md"
  run_render pr --audit-file "$in/audit-missing.md"
  [ "$RC" -eq 2 ] || fail "an audit missing '$missing' must be refused with 2 (got $RC)"
  printf '%s\n' "$ERR" | grep -qF "$missing" || fail "the missing-element refusal must name '$missing'"
done

for tag in '</details>' '<details>' '  <summary>x</summary>' '<!-- planwright:flight-record-end -->'; do
  {
    cat "$in/audit.md"
    printf '%s\n' "$tag"
  } >"$in/audit-tag.md"
  run_render pr --audit-file "$in/audit-tag.md"
  [ "$RC" -eq 2 ] || fail "a structural line ('$tag') in the audit must be refused with 2 (got $RC)"
done

# Markup that would swallow the rest of the record: an unclosed comment, an
# HTML block opener, an inline collapse tag, an unbalanced fence.
for bad in '<!-- a note' '<pre>' '  <script>' '<![CDATA[' 'see x </details> here' \
  'open <details><summary>y' '```sh' '~~~~' '<div>' '<span>' '<!-- x --> <!-- y' '<!-->' \
  '> <!-- a note' '- <!-- a note' '1. <!-- note' 'See a <b>bold</b> word.' '#### Detail' '## Summary' \
  '> ## Verification' '- # Top' '[^1]: a note'; do
  printf 'Corrects the name.\n%s\n' "$bad" >"$in/summary-markup.md"
  run_render pr --summary-file "$in/summary-markup.md"
  [ "$RC" -eq 2 ] || fail "a summary carrying '$bad' must be refused with 2 (got $RC)"
done
# A collapse tag or a record marker at column zero is refused even inside a
# fence, and an HTML block, a comment, or a list-indented fence shelters
# nothing, since their ends cannot be tracked line by line.
for bad in '```\n</details>\n```' '<div>\n```\n</details>\n```' '- a\n  ```\n</details>\n  ```' \
  '<!-- a\n--> </details>' '```\n<!-- planwright:flight-record-end -->\n```' \
  '- a\n  ```\n<pre>\n  ```' '- a\n  ```\n```' '- a\n  ```\n<!-- hidden\n  ```'; do
  # shellcheck disable=SC2059 # the case carries its own \n escapes
  printf "Corrects the name.\n$bad\n" >"$in/audit-shelter.md"
  cat "$in/audit.md" "$in/audit-shelter.md" >"$in/audit-sheltered.md"
  run_render pr --audit-file "$in/audit-sheltered.md"
  [ "$RC" -eq 2 ] || fail "a sheltered collapse tag or marker must be refused ($bad, got $RC)"
done
# Multi-line shapes: a balanced tilde fence, and setext headings that would
# forge the record's own sections.
for bad in '~~~\nx\n~~~' 'Verification\n---\n\nForged.' 'Top\n===' '> Top\n> ---' '- a\n  - Top\n    ---' \
  '10. Top\n    ===' '``` `x`\n---' '```\nx\n  ```\n  </details>\n```' \
  '```\nx\n   ```\n   <!-- planwright:flight-record-end -->\n```'; do
  # shellcheck disable=SC2059 # the case carries its own \n escapes
  printf "Corrects the name.\n\n$bad\n" >"$in/summary-multi.md"
  run_render pr --summary-file "$in/summary-multi.md"
  [ "$RC" -eq 2 ] || fail "a summary carrying '$bad' must be refused with 2 (got $RC)"
done
# Inside a column-zero fence, HTML is code: allowed off column zero.
printf 'Ran the checks.\n\n```sh\n  cat <<EOF\n  sort <in.txt\n  EOF\n```\n' >"$in/verification-code.md"
run_render pr --verification-file "$in/verification-code.md"
[ "$RC" -eq 0 ] || fail "HTML-shaped code inside a fence must render (got $RC: $ERR)"
printf 'Ran the checks.\n\n```\n</details>\n```\n' >"$in/verification-col0.md"
run_render pr --verification-file "$in/verification-col0.md"
[ "$RC" -eq 2 ] || fail "a fenced line starting with < at column zero must be refused (got $RC)"

# The audit's headings nest under the record's own, so none may outrank it.
{
  cat "$in/audit.md"
  printf '## Extra\n'
} >"$in/audit-h2.md"
run_render pr --audit-file "$in/audit-h2.md"
[ "$RC" -eq 2 ] || fail "an audit heading above #### must be refused (got $RC)"
# Balanced column-zero fences and Markdown emphasis are fine.
printf 'Corrects the name.\n\n```sh\nmise run lint\n```\n\n````\nx\n`````\n\nSee a **bold** word.\n' >"$in/verification-ok.md"
run_render pr --verification-file "$in/verification-ok.md"
[ "$RC" -eq 0 ] || fail "balanced fences and emphasis must render (got $RC: $ERR)"
# Blank runs collapse, trailing whitespace and edge blank lines go, and an
# interior blank line stays.
printf '\n\nFirst paragraph.   \n\n\n\nSecond paragraph.\n\n\n' >"$in/summary-blanks.md"
run_render pr --summary-file "$in/summary-blanks.md"
[ "$RC" -eq 0 ] || fail "render of a blank-heavy summary exited $RC: $ERR"
lead=$(lead_of "$OUT")
printf '%s\n' "$lead" | awk '/^## Summary$/ {on=1; next} /^## Verification$/ {exit} on' >"$tmp/sum.sec"
[ "$(cat "$tmp/sum.sec")" = "$(printf '\nFirst paragraph.\n\nSecond paragraph.\n')" ] \
  || fail "the summary must be normalized: $(od -c "$tmp/sum.sec" | head -4)"

printf 'Rotated the key %s.\n' "$TOKEN" >"$in/secret.md"
for flag in --summary-file --verification-file --scoping-file --revert-file; do
  run_render pr "$flag" "$in/secret.md"
  [ "$RC" -eq 2 ] || fail "a token-shaped secret in $flag must be refused with 2 (got $RC)"
  case $ERR in *"$TOKEN"*) fail "the $flag secret refusal must not echo the secret" ;; esac
done
{
  cat "$in/audit.md"
  cat "$in/secret.md"
} >"$in/audit-secret.md"
run_render pr --audit-file "$in/audit-secret.md"
[ "$RC" -eq 2 ] || fail "a token-shaped secret in the audit must be refused with 2 (got $RC)"

printf 'Corrects the name.\n</DETAILS>\n' >"$in/summary-upper.md"
run_render pr --summary-file "$in/summary-upper.md"
[ "$RC" -eq 2 ] || fail "an uppercase collapse tag must be refused (got $RC)"
printf '<!-- planwright:flight-record id=x home=pr -->\n' >"$in/verification-marker.md"
run_render pr --verification-file "$in/verification-marker.md"
[ "$RC" -eq 2 ] || fail "a record start marker in the verification must be refused (got $RC)"
printf 'Scoped.\n</details>\n' >"$in/tag.md"
for flag in --scoping-file --revert-file; do
  run_render pr "$flag" "$in/tag.md"
  [ "$RC" -eq 2 ] || fail "a collapse tag in $flag must be refused (got $RC)"
done
printf 'Scoped%s to one pass.\n' "$ZWSP" >"$in/scoping-invis.md"
run_render pr --scoping-file "$in/scoping-invis.md"
case $OUT in *"$ZWSP"*) fail "an invisible character in the scoping reached the record" ;; esac

sed 's/^#### Declined log$/See the Declined log above./' "$in/audit.md" >"$in/audit-prose.md"
run_render pr --audit-file "$in/audit-prose.md"
[ "$RC" -eq 2 ] || fail "a contract element named only in prose must be refused (got $RC)"

: >"$in/empty.md"
run_render pr --summary-file "$in/empty.md"
[ "$RC" -eq 2 ] || fail "an empty summary must be refused with 2 (got $RC)"
run_render pr --audit-file "$in/nonexistent.md"
[ "$RC" -eq 2 ] || fail "a missing input file must be refused with 2 (got $RC)"

for bad in 'Bad_Id' '../escape-0a1b2c3d' 'no-uid'; do
  run_render pr --flight-id "$bad"
  [ "$RC" -eq 2 ] || fail "a malformed flight id must be refused with 2 (got $RC for $bad)"
done
run_render pr --handle 'bad handle'
[ "$RC" -eq 2 ] || fail "a malformed worker handle must be refused with 2 (got $RC)"
for h in '-leading' '.leading' "$(printf 'h%.0s' $(seq 1 129))"; do
  run_render pr --handle "$h"
  [ "$RC" -eq 2 ] || fail "the worker handle '${h:0:12}' must be refused with 2 (got $RC)"
done
run_render pr --handle ''
[ "$RC" -eq 2 ] || fail "a missing worker handle must be refused with 2 (got $RC)"
run_render pr --repo-root "$tmp"
[ "$RC" -eq 2 ] || fail "render must refuse --repo-root with 2 (got $RC)"
run_render elsewhere
[ "$RC" -eq 2 ] || fail "an unknown home must be refused with 2 (got $RC)"
run_render none
[ "$RC" -eq 2 ] || fail "render without --home must be refused with 2 (got $RC)"

# --- 5: the PR body limit -----------------------------------------------------

{
  cat "$in/audit.md"
  for _i in $(seq 1 1000); do
    printf '| %s | a declined finding with enough words to take up a row of the log |\n' "$_i"
  done
} >"$in/audit-big.md"
run_render pr --audit-file "$in/audit-big.md"
[ "$RC" -eq 3 ] || fail "a PR-home record over the body limit must be refused with 3 (got $RC)"
[ -z "$OUT" ] || fail "an over-limit record must print nothing"
printf '%s\n' "$ERR" | grep -q 'the ask alone is' || fail "the body-limit refusal must say how much of it is the ask: $ERR"
run_render file --audit-file "$in/audit-big.md"
[ "$RC" -eq 0 ] || fail "the file home carries no body limit (got $RC: $ERR)"

# --- 6: the no-remote arm commits exactly one record file ---------------------

gitc() {
  _r=$1
  shift
  git -C "$_r" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}
repo="$tmp/repo"
git -c init.defaultBranch=main init -q "$repo"
printf 'Plawnright\n' >"$repo/README.md"
gitc "$repo" add -A
gitc "$repo" commit -q -m init
gitc "$repo" checkout -q -b "planwright/flight/$FID"
printf 'Planwright\n' >"$repo/README.md"
gitc "$repo" commit -q -am 'docs: fix the heading'
work_head=$(git -C "$repo" rev-parse HEAD)

run_land() {
  defaults
  OUT=$(cd "$repo" && GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid \
    /bin/sh "$SCRIPT" land "${args[@]}" "$@" 2>"$tmp/err")
  RC=$?
  ERR=$(cat "$tmp/err")
}

run_land
[ "$RC" -eq 0 ] || fail "land exited $RC: $ERR"
[ "$(git -C "$repo" rev-parse HEAD~1)" = "$work_head" ] || fail "land must add exactly one commit"
changed=$(git -C "$repo" show --name-only --format= HEAD)
[ "$changed" = "specs/_flights/$FID.md" ] || fail "land must commit exactly the record file (got: $changed)"
[ "$(git -C "$repo" log -1 --format=%s)" = "docs(flight): record flight $FID" ] \
  || fail "land's commit subject: $(git -C "$repo" log -1 --format=%s)"
[ "$(git -C "$repo" rev-parse --abbrev-ref HEAD)" = "planwright/flight/$FID" ] || fail "land must stay on the flight branch"
[ -z "$(git -C "$repo" status --porcelain)" ] || fail "land must leave the tree clean"
landed=$OUT
run_render file
[ "$(git -C "$repo" show "HEAD:specs/_flights/$FID.md")" = "$OUT" ] \
  || fail "the landed record must be the file-home render"
printf '%s\n' "$landed" | grep -qx "record	specs/_flights/$FID.md" || fail "land must report the record path"
printf '%s\n' "$landed" | grep -qx "commit	$(git -C "$repo" rev-parse HEAD)" || fail "land must report the commit"

before=$(git -C "$repo" rev-parse HEAD)
run_land
[ "$RC" -eq 3 ] || fail "a second record for one flight must be refused with 3 (got $RC)"
[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ] || fail "a refused land must commit nothing"

run_land --home pr
[ "$RC" -eq 2 ] || fail "land is the file home only: --home must be refused with 2 (got $RC)"

# Each existing-record guard holds on its own: in HEAD only, on disk only.
rm "$repo/specs/_flights/$FID.md"
run_land
[ "$RC" -eq 3 ] || fail "a record already in HEAD must be refused with 3 (got $RC)"
[ "$(git -C "$repo" rev-parse HEAD)" = "$before" ] || fail "a refused land must commit nothing (in HEAD)"
gitc "$repo" checkout -q -- "specs/_flights/$FID.md"
UNTR=untracked-0a1b2c3d
gitc "$repo" checkout -q -b "planwright/flight/$UNTR" main
mkdir -p "$repo/specs/_flights"
printf 'stray\n' >"$repo/specs/_flights/$UNTR.md"
run_land --flight-id "$UNTR"
[ "$RC" -eq 3 ] || fail "an untracked record on disk must be refused with 3 (got $RC)"
[ "$(cat "$repo/specs/_flights/$UNTR.md")" = stray ] || fail "a refused land must leave the stray file alone"
rm -rf "$repo/specs"

# A commit the hooks refuse rolls the record back out.
HOOK=hooked-0a1b2c3d
gitc "$repo" checkout -q -b "planwright/flight/$HOOK" main
mkdir -p "$repo/.git/hooks"
printf '#!/bin/sh\nexit 1\n' >"$repo/.git/hooks/pre-commit"
chmod +x "$repo/.git/hooks/pre-commit"
hook_head=$(git -C "$repo" rev-parse HEAD)
run_land --flight-id "$HOOK"
[ "$RC" -eq 4 ] || fail "a refused commit must fail with 4 (got $RC)"
[ -e "$repo/specs/_flights/$HOOK.md" ] && fail "a refused commit must leave no record file"
[ -z "$(git -C "$repo" diff --cached --name-only)" ] || fail "a refused commit must leave nothing staged"
[ "$(git -C "$repo" rev-parse HEAD)" = "$hook_head" ] || fail "a refused commit must not move HEAD"
rm -f "$repo/.git/hooks/pre-commit"
rm -rf "$repo/specs"

gitc "$repo" checkout -q main
run_land
[ "$RC" -eq 3 ] || fail "land off the flight branch must be refused with 3 (got $RC)"
[ -e "$repo/specs/_flights/$FID.md" ] && fail "a refused land must write no file"

OTHER=other-0a1b2c3d
gitc "$repo" checkout -q -b "planwright/flight/$OTHER" main
printf 'staged\n' >"$repo/extra.txt"
gitc "$repo" add extra.txt
run_land --flight-id "$OTHER"
[ "$RC" -eq 3 ] || fail "land over an index holding other changes must be refused with 3 (got $RC)"
git -C "$repo" diff --cached --name-only | grep -qx extra.txt || fail "a refused land must leave the index as it was"
[ -e "$repo/specs/_flights/$OTHER.md" ] && fail "a refused land must write no record"

git -C "$repo" reset -q
rm -f "$repo/extra.txt"

# A symlinked specs/ or specs/_flights/ would carry the write outside the
# checkout; land refuses before writing anything.
outside="$tmp/outside"
for link in specs specs/_flights; do
  SYM=sym-0a1b2c3d
  rm -rf "$outside" "$repo/specs"
  mkdir -p "$outside"
  if [ "$link" = specs ]; then
    ln -s "$outside" "$repo/specs"
  else
    mkdir -p "$repo/specs"
    ln -s "$outside" "$repo/specs/_flights"
  fi
  gitc "$repo" checkout -q -B "planwright/flight/$SYM" main
  run_land --flight-id "$SYM"
  [ "$RC" -eq 3 ] || fail "land through a symlinked $link must be refused with 3 (got $RC)"
  [ -z "$(ls -A "$outside")" ] || fail "land through a symlinked $link wrote outside the checkout"
  rm -rf "$repo/specs"
done

# A regular file where specs/ belongs is refused as a symlink is.
NDIR=nodir-0a1b2c3d
gitc "$repo" checkout -q -b "planwright/flight/$NDIR" main
printf 'x\n' >"$repo/specs"
run_land --flight-id "$NDIR"
[ "$RC" -eq 3 ] || fail "a regular file at specs must be refused with 3 (got $RC)"
rm -f "$repo/specs"

# A landed record passes the repository's own markdown lint.
ML=$(command -v markdownlint-cli2 2>/dev/null || :)
if [ -n "$ML" ] && "$ML" --version >/dev/null 2>&1; then
  lr="$tmp/lintroot"
  mkdir -p "$lr/specs/_flights"
  cp "$ROOT/.markdownlint.jsonc" "$lr/"
  cp "$ROOT/specs/.markdownlint.jsonc" "$lr/specs/"
  cp "$ROOT/specs/_flights/.markdownlint.jsonc" "$lr/specs/_flights/" 2>/dev/null || :
  run_render file --verification-file "$in/verification-ok.md" --summary-file "$in/summary-blanks.md"
  printf '%s\n' "$OUT" >"$lr/specs/_flights/$FID.md"
  (cd "$lr" && "$ML" "specs/_flights/$FID.md") >"$tmp/ml.out" 2>&1 \
    || fail "a landed record must pass markdownlint: $(grep error "$tmp/ml.out" | head -3)"
else
  echo "test-flight-record: markdownlint-cli2 unavailable; record lint check skipped" >&2
fi

# land runs at the worktree's top level, inside a git worktree.
mkdir -p "$repo/sub"
run_land --repo-root "$repo/sub"
[ "$RC" -eq 2 ] || fail "a --repo-root below the top level must be refused with 2 (got $RC)"
mkdir -p "$tmp/not-git"
run_land --repo-root "$tmp/not-git"
[ "$RC" -eq 4 ] || fail "a --repo-root outside git must fail with 4 (got $RC)"

# A missing helper is an environment failure, not a bad input.
mkdir -p "$tmp/partial/scripts"
cp "$ROOT/scripts/flight-record.sh" "$ROOT/scripts/flight-text.sh" "$ROOT/scripts/inception-secret-screen.sh" \
  "$ROOT/scripts/echo-safety.sh" "$tmp/partial/scripts/"
defaults
/bin/sh "$tmp/partial/scripts/flight-record.sh" render --home pr "${args[@]}" >/dev/null 2>"$tmp/err"
RC=$?
[ "$RC" -eq 4 ] || fail "a missing flight-id helper must fail with 4 (got $RC)"
grep -q 'required helper missing' "$tmp/err" || fail "the missing-helper failure must say so: $(cat "$tmp/err")"

if [ "$fails" -gt 0 ]; then
  echo "test-flight-record: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-record: ok"
