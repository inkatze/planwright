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
#   5. The no-remote arm (`land`) commits exactly one record file,
#      `specs/_flights/<id>.md`, on the flight's own branch, and refuses a
#      second record, the wrong branch, or an index holding other changes.
#   6. A PR-home record over GitHub's body limit is refused, not truncated.
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

# run_render / run_land <home> [overrides...] — OUT, ERR, RC. A later flag
# overrides an earlier one, so a case names only what it changes.
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
done

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
printf '  Plawnright\n' >"$in/verification-restated.md"
run_render file --verification-file "$in/verification-restated.md" --summary-file "$in/summary-restated.md"
[ "$RC" -eq 2 ] || fail "the file home must refuse a restated prompt too (got $RC)"

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

printf 'Rotated the key %s.\n' "$TOKEN" >"$in/verification-secret.md"
run_render pr --verification-file "$in/verification-secret.md"
[ "$RC" -eq 2 ] || fail "a token-shaped secret in a worker input must be refused with 2 (got $RC)"
case $ERR in *"$TOKEN"*) fail "the secret refusal must not echo the secret" ;; esac

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
run_render elsewhere
[ "$RC" -eq 2 ] || fail "an unknown home must be refused with 2 (got $RC)"
run_render none
[ "$RC" -eq 2 ] || fail "render without --home must be refused with 2 (got $RC)"

# --- 6: the PR body limit -----------------------------------------------------

{
  cat "$in/audit.md"
  for _i in $(seq 1 1000); do
    printf '| %s | a declined finding with enough words to take up a row of the log |\n' "$_i"
  done
} >"$in/audit-big.md"
run_render pr --audit-file "$in/audit-big.md"
[ "$RC" -eq 3 ] || fail "a PR-home record over the body limit must be refused with 3 (got $RC)"
[ -z "$OUT" ] || fail "an over-limit record must print nothing"
run_render file --audit-file "$in/audit-big.md"
[ "$RC" -eq 0 ] || fail "the file home carries no body limit (got $RC: $ERR)"

# --- 5: the no-remote arm commits exactly one record file ---------------------

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

if [ "$fails" -gt 0 ]; then
  echo "test-flight-record: $fails failure(s)" >&2
  exit 1
fi
echo "test-flight-record: ok"
