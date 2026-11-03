#!/bin/bash
# Tests for scripts/mc-reviews.sh, the reviews-at-a-glance snapshot the panel
# mod draws, and for the digest records scripts/mc-panel.sh reads it into:
# the snapshot from fixture gh output, its TTL, the degrade path when gh is
# missing, unauthenticated or failing, and that every gh call is a read.
#
# The forge is faked by a gh shim on PATH that logs each call and runs the
# script's own --jq program over a fixture GraphQL page.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-reviews.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-reviews.sh" ] || {
  echo "FAIL: scripts/mc-reviews.sh missing" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run the script's jq program" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
head7=7777777777777777777777777777777777777777

# The gh shim: logs every call; serves the repository name and a GraphQL
# page run through the caller's --jq program. GH_AUTH_FAIL answers as gh
# does with no login; GH_FAIL fails any other way; GH_LIMITED refuses for the
# rate limit; GH_JUNK serves a page with an unexpected field.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
# One `call <verb> <noun>` line per call, then its search variables, and
# MUTATION if any argument carries one.
printf 'call %s %s\n' "$1" "$2" >>"$GH_LOG"
for a in "$@"; do
  case $a in
    mine=* | asked=*) printf '%s\n' "$a" >>"$GH_LOG" ;;
  esac
  case $a in *mutation*) echo MUTATION >>"$GH_LOG" ;; esac
done
if [ -n "${GH_AUTH_FAIL:-}" ]; then
  printf 'To get started with GitHub CLI, please run:  gh auth login\n' >&2
  exit 4
fi
if [ -n "${GH_LIMITED:-}" ]; then
  echo "API rate limit exceeded for user" >&2
  exit 1
fi
if [ -n "${GH_FAIL:-}" ]; then
  printf 'HTTP 502: \033[2Jbad gateway\nsecond line\n' >&2
  exit 1
fi
case "$1 $2" in
  "repo view") echo "acme/widgets" ;;
  "api graphql")
    expr=""
    while [ $# -gt 0 ]; do
      [ "$1" = --jq ] && expr=$2
      shift
    done
    page=$GH_PAGE
    [ -z "${GH_JUNK:-}" ] || page=$GH_JUNK_PAGE
    jq -r "$expr" "$page"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

# #7 is mine: ready, CI red, two of three threads open, reviewed on its head
# by bob, reviewers carol and a team. #8 is mine: a draft with CI running,
# reviewed by bob only on an older head and by me on its head (a
# reply-review, which never counts), nobody requested, a title carrying a
# tab and a control byte. #12
# waits on my review, requested by dave at 1970-01-01T00:10:00Z; #13 is a
# draft whose request event is not mine, so its author and creation stand in.
cat >"$tmp/page.json" <<EOF
{"data": {"viewer": {"login": "me"},
 "mine": {"nodes": [
  {"number": 7, "title": "Add the widget", "isDraft": false, "headRefOid": "$head7",
   "repository": {"nameWithOwner": "acme/widgets"},
   "reviewRequests": {"nodes": [{"requestedReviewer": {"login": "carol"}}, {"requestedReviewer": {"slug": "core-team"}}]},
   "reviewThreads": {"nodes": [{"isResolved": false}, {"isResolved": true}, {"isResolved": false}]},
   "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]},
   "reviews": {"nodes": [{"author": {"login": "me"}, "commit": {"oid": "$head7"}}, {"author": {"login": "bob"}, "commit": {"oid": "$head7"}}]}},
  {"number": 8, "title": "Fix\tthe \u001bgadget", "isDraft": true, "headRefOid": "8888888888888888888888888888888888888888",
   "repository": {"nameWithOwner": "acme/widgets"},
   "reviewRequests": {"nodes": []},
   "reviewThreads": {"nodes": []},
   "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "PENDING"}}}]},
   "reviews": {"nodes": [{"author": {"login": "bob"}, "commit": {"oid": "0000000000000000000000000000000000000000"}}, {"author": {"login": "me"}, "commit": {"oid": "8888888888888888888888888888888888888888"}}]}},
  {}]},
 "asked": {"nodes": [
  {"number": 12, "title": "Rework the docs", "isDraft": false, "createdAt": "1970-01-01T00:00:00Z",
   "repository": {"nameWithOwner": "acme/widgets"}, "author": {"login": "erin"},
   "timelineItems": {"nodes": [{"createdAt": "1970-01-01T00:05:00Z", "actor": {"login": "erin"}, "requestedReviewer": {"login": "zed"}},
                               {"createdAt": "1970-01-01T00:10:00Z", "actor": {"login": "dave"}, "requestedReviewer": {"login": "me"}}]}},
  {"number": 13, "title": "Spike", "isDraft": true, "createdAt": "1970-01-01T00:01:40Z",
   "repository": {"nameWithOwner": "acme/widgets"}, "author": {"login": "frank"},
   "timelineItems": {"nodes": [{"createdAt": "1970-01-01T00:02:00Z", "actor": {"login": "frank"}, "requestedReviewer": {}}]}}]}}}
EOF
printf '{"data": {"viewer": {"login": "me"}, "mine": {"nodes": [{"number": "seven", "title": "x", "isDraft": false, "headRefOid": "aa", "repository": {"nameWithOwner": "acme/widgets"}, "reviewRequests": {"nodes": []}, "reviewThreads": {"nodes": []}, "commits": {"nodes": []}, "reviews": {"nodes": []}}]}, "asked": {"nodes": []}}}\n' >"$tmp/junk.json"

GH_LOG="$tmp/gh.log"
GH_PAGE="$tmp/page.json"
GH_JUNK_PAGE="$tmp/junk.json"
export GH_LOG GH_PAGE GH_JUNK_PAGE
gh_calls() { if [ -f "$GH_LOG" ]; then grep -c "^call " "$GH_LOG"; else echo 0; fi; }

runtime=$fleet/mission-control/alpha
snap=$runtime/reviews

setup() {
  unset GH_AUTH_FAIL GH_LIMITED GH_FAIL GH_JUNK
  reset_mc_fixture
  rm -rf "$fleet" "$GH_LOG"
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
EOF
}

reviews() { # reviews <args...>: mc-reviews.sh with the gh shim first on PATH
  OUT=$(PATH="$tmp/bin:$PATH" mc_env /bin/bash "$repo_root/scripts/mc-reviews.sh" "$@" 2>"$tmp/stderr")
  RC=$?
  ERR=$(cat "$tmp/stderr")
}

line_in() { # line_in <label> <file> <field>...: the file holds that line
  li_label=$1
  li_file=$2
  shift 2
  li_want=$(printf '%s\t' "$@")
  li_want=${li_want%"$tab"}
  if [ -f "$li_file" ] && grep -qxF -- "$li_want" "$li_file"; then
    ok "$li_label"
  else
    fail "$li_label: no line '$li_want' in $li_file"
    [ ! -f "$li_file" ] || sed 's/^/  | /' "$li_file" >&2
  fi
}

record() { # record <label> <field>...: stdout holds that record
  rc_label=$1
  shift
  rc_want=$(printf '%s\t' "$@")
  rc_want=${rc_want%"$tab"}
  if printf '%s\n' "$OUT" | grep -qxF -- "$rc_want"; then
    ok "$rc_label"
  else
    fail "$rc_label: no line '$rc_want'"
    printf '%s\n' "----- stdout -----" "$OUT" "----- stderr -----" "$ERR" "------------------" >&2
  fi
}

# ---------------------------------------------------------------------------
# refresh: one snapshot from the fixture gh output.
# ---------------------------------------------------------------------------
setup
reviews refresh --program alpha --now 1000
expect_rc "a refresh with gh answering" 0
expect_eq "the refresh says it wrote the snapshot" "written"
line_in "the snapshot opens with its format" "$snap" format 1
line_in "the snapshot is stamped" "$snap" taken 1000
line_in "the snapshot's state is ok" "$snap" state ok -
line_in "my ready PR: CI red, two open threads, reviewed on its head, its reviewers" "$snap" \
  mine acme/widgets 7 ready red 2 yes "carol, core-team" "Add the widget"
line_in "my draft PR: CI running, an older head's review and my own do not count, no reviewers" "$snap" \
  mine acme/widgets 8 draft running 0 no - "Fix the gadget"
line_in "a PR waiting on me names who requested me and when" "$snap" \
  waiting acme/widgets 12 ready dave 600 "Rework the docs"
line_in "with no request event of mine, the author and creation stand in" "$snap" \
  waiting acme/widgets 13 draft frank 100 Spike
if grep -q "$(printf '\033')" "$snap"; then fail "a control byte reached the snapshot"; else ok "control bytes never reach the snapshot"; fi
n=$(awk -F '\t' '$1 == "mine"' "$snap" | wc -l | tr -d ' ')
if [ "$n" = 2 ]; then ok "a search node that is not a pull request is skipped"; else fail "mine rows: $n, want 2"; fi

# Read-only: every gh call is a repository lookup or a GraphQL query.
writes=$(grep "^call " "$GH_LOG" | grep -Evc "^call (repo view|api graphql)$")
if [ "$writes" = 0 ]; then ok "every gh call is a read"; else fail "gh calls outside the read set: $(cat "$GH_LOG")"; fi
if grep -q 'mutation' "$GH_LOG"; then fail "a GraphQL mutation was sent"; else ok "no GraphQL mutation is sent"; fi
if grep -q 'repo:acme/widgets is:pr is:open author:@me' "$GH_LOG"; then
  ok "my PRs are searched in the program's repository"
else
  fail "my-PRs search not scoped: $(cat "$GH_LOG")"
fi
if grep -q 'repo:acme/widgets is:pr is:open review-requested:@me' "$GH_LOG"; then
  ok "requests are searched in the program's repository"
else
  fail "review-requested search not scoped: $(cat "$GH_LOG")"
fi

# ---------------------------------------------------------------------------
# The TTL: a snapshot younger than mission_control_reviews_ttl costs no read.
# ---------------------------------------------------------------------------
calls=$(gh_calls)
reviews refresh --program alpha --now 1299
expect_rc "a refresh inside the TTL" 0
expect_eq "inside the TTL the snapshot is fresh" "fresh"
if [ "$(gh_calls)" = "$calls" ]; then ok "inside the default 5m TTL gh is not called"; else fail "gh called inside the TTL"; fi
reviews refresh --program alpha --now 1300
expect_eq "at the TTL the snapshot is read again" "written"
line_in "the new snapshot is stamped" "$snap" taken 1300
if [ "$(gh_calls)" -gt "$calls" ]; then ok "at the TTL gh is called again"; else fail "gh not called at the TTL"; fi

printf 'mission_control_reviews_ttl: 1m\n' >>"$tracked"
calls=$(gh_calls)
reviews refresh --program alpha --now 1359
expect_eq "the TTL knob shortens the window" "fresh"
reviews refresh --program alpha --now 1360
expect_eq "past the knob's TTL the snapshot is read again" "written"
sed -i.bak "s/^mission_control_reviews_ttl: .*/mission_control_reviews_ttl: soon/" "$tracked"
reviews refresh --program alpha --now 9000
expect_rc "an invalid repo-tracked TTL fails" 1
expect_err "the invalid TTL is named" "mission_control_reviews_ttl"

# An attempt that never finished still holds the TTL: a gh that hangs past
# the panel's timeout is not called again on every redraw.
setup
printf '5000\n' >"$tmp/attempt"
mkdir -p "$runtime"
cp "$tmp/attempt" "$runtime/reviews.attempt"
reviews refresh --program alpha --now 5100
expect_eq "an unfinished attempt inside the TTL is fresh" "fresh"
if [ "$(gh_calls)" = 0 ]; then ok "an unfinished attempt costs no read"; else fail "gh called after an unfinished attempt"; fi

# ---------------------------------------------------------------------------
# The degrade path: an unavailable snapshot with its reason, never an error.
# ---------------------------------------------------------------------------
nogh=$tmp/nogh
mkdir -p "$nogh"
for t in sh bash env git awk sed grep tr cat cut head tail wc sort uniq comm date mktemp mkdir rmdir mv cp rm ln ls id uname expr basename dirname find touch stat sleep printf jq flock readlink realpath od xargs tee chmod cksum sha256sum base64 pwd; do
  b=$(command -v "$t" 2>/dev/null) || continue
  case $b in /*) ln -s "$b" "$nogh/$t" 2>/dev/null || : ;; esac
done
PATH="$nogh" command -v gh >/dev/null 2>&1 && fail "no-gh PATH: gh still resolves, the fixture is wrong"
setup
OUT=$(PATH="$nogh" mc_env /bin/bash "$repo_root/scripts/mc-reviews.sh" refresh --program alpha --now 1000 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "a refresh with no gh" 0
expect_eq "with no gh the refresh says so" "unavailable${tab}gh is not installed"
line_in "the snapshot records the reason" "$snap" state unavailable "gh is not installed"
calls=$(gh_calls)
OUT=$(PATH="$nogh" mc_env /bin/bash "$repo_root/scripts/mc-reviews.sh" refresh --program alpha --now 1100 2>"$tmp/stderr")
if [ "$OUT" = fresh ]; then ok "an unavailable snapshot is rate-limited too"; else fail "an unavailable snapshot re-read: '$OUT'"; fi

setup
GH_AUTH_FAIL=1 reviews refresh --program alpha --now 1000
expect_rc "a refresh with gh unauthenticated" 0
line_in "unauthenticated gh degrades with its reason" "$snap" state unavailable "gh is not authenticated"

setup
GH_LIMITED=1 reviews refresh --program alpha --now 1000
expect_rc "a refresh refused for the rate limit" 0
line_in "a rate-limit refusal degrades with its reason" "$snap" state unavailable "the forge refused the read for its rate limit"

setup
GH_FAIL=1 reviews refresh --program alpha --now 1000
expect_rc "a refresh whose gh read fails" 0
line_in "any other gh failure degrades, its first line cleaned" "$snap" state unavailable "the gh read failed: HTTP 502: bad gateway"

setup
GH_JUNK=1 reviews refresh --program alpha --now 1000
expect_rc "a refresh with an unexpected answer" 0
line_in "an unexpected field degrades, never drawn" "$snap" state unavailable "the forge answered with an unexpected field"
if awk -F '\t' '$1 == "mine"' "$snap" | grep -q .; then fail "a junk row reached the snapshot"; else ok "no junk row reaches the snapshot"; fi

setup
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_spec_root: $repo
EOF
reviews refresh --program alpha --now 1000
expect_rc "a program with no repository" 0
line_in "a program with no repository degrades" "$snap" state unavailable "the program names no repository"

setup
reviews refresh --program nosuch --now 1000
expect_rc "an unconfigured program" 3
reviews refresh --program alpha --now nope
expect_rc "a bad --now is a usage error" 2
reviews refresh
expect_rc "no program is a usage error" 2

# A symlinked snapshot is never written through.
setup
mkdir -p "$runtime"
ln -s "$tmp/elsewhere" "$snap"
reviews refresh --program alpha --now 1000
expect_rc "a symlinked snapshot is refused" 1
if [ ! -e "$tmp/elsewhere" ]; then ok "nothing is written through the symlink"; else fail "the snapshot was written through a symlink"; fi
rm -f "$snap"

# ---------------------------------------------------------------------------
# The digest: the panel reads the snapshot as review records.
# ---------------------------------------------------------------------------
setup
mc_run mc-panel.sh digest --program alpha --now 1000
record "with no snapshot the digest says reviews are unavailable" reviews unavailable "no snapshot yet"
reviews refresh --program alpha --now 1000
mc_run mc-panel.sh digest --program alpha --now 1090
expect_rc "the digest with a snapshot" 0
record "the digest carries the snapshot's state and age" reviews ok 90
record "the digest carries my PRs" review-mine acme/widgets 7 ready red 2 yes "carol, core-team" "Add the widget"
record "the digest carries the requests, aged from now" review-waiting acme/widgets 12 ready dave 490 "Rework the docs"
setup
GH_AUTH_FAIL=1 reviews refresh --program alpha --now 1000
mc_run mc-panel.sh digest --program alpha --now 1000
record "an unavailable snapshot reaches the digest with its reason" reviews unavailable "gh is not authenticated"
printf 'format\t9\n' >"$snap"
mc_run mc-panel.sh digest --program alpha --now 1000
record "a snapshot of an unknown format is unavailable, named" reviews unavailable "the snapshot is unreadable"
rm -f "$snap"
ln -s "$tmp/nowhere" "$snap"
mc_run mc-panel.sh digest --program alpha --now 1000
record "a symlinked snapshot is unavailable, named" reviews unavailable "the snapshot is unreadable"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mc-reviews tests passed"
