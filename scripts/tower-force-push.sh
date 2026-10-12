#!/bin/bash
# tower-force-push.sh — the tower's operator-requested rewrite of a pushed
# branch, and the preparation of a secret purge it never runs
# (doctrine/human-gates.md, the force-push and secret-purge rows).
#
# Usage, run in a checkout of the repository:
#   tower-force-push.sh reword  --branch <b> --commit <c> --message-file <f>
#                               [--remote <r>]
#   tower-force-push.sh confirm --branch <b> --to <c> [--remote <r>]
#   tower-force-push.sh push    --branch <b> --to <c> --lease <c> [--remote <r>]
#   tower-force-push.sh purge   (--path <p> | --replace-text <f>)...
#
#   reword   build the branch's history with <c>'s message replaced by <f>,
#            every later commit replayed onto it with its tree, author, and
#            message unchanged, and print tab-separated `reworded <c> <new c>`,
#            `lease <remote tip>`, and `to <new tip>` lines. It writes commit
#            objects and refreshes remote-tracking refs only: no branch,
#            index, or working tree changes.
#   confirm  print the confirmation (below) for replacing <r>/<b> with <c>.
#   push     force-push <c> to <r>/<b>, only while <r>/<b> still sits at
#            <lease>, the tip the confirmation named; then print what it
#            dropped and every legacy checklist id the rewrite changed.
#   purge    print a history-purge command and the rotation checklist. It
#            runs nothing.
#
# Every verb but purge refuses where a dispatch exported a worker identity
# (PLANWRIGHT_WORKER_HANDLE or PLANWRIGHT_WORKER_SCOPE) and a branch in the
# protected set (scripts/protected-branch.sh: main, master, a
# spec branch, and the protected_branches additions), and refreshes <r>/<b>
# (default remote `origin`) first. confirm and push refuse a <c> whose tip
# contains the remote tip (nothing would be dropped: a plain push suffices).
# reword refreshes every remote branch and refuses a commit a protected one
# contains, since rewording it would fork that history.
#
# The confirmation is one JSON object that scripts/check-confirmation.sh
# accepts (this script checks it before printing): `question` and `options`
# (the force-push, and the reject that pushes nothing) name the remote
# commits the push drops, and `remote`, `branch`, `lease`, `to`, `dropped`,
# `legacy`, and `push` (the argv of the push verb for this exact lease) carry
# the data. The tower puts the question and options to the operator as they
# stand and runs `push` only on the yes, in the turn the operator asked.
#
# A legacy checklist item (a subject ending in ` [pending-sign-off]` with no
# Planwright-Sign-Off trailer) takes its id from its own hash, so a rewrite
# changes it: `legacy` pairs each dropped legacy commit with its replacement
# by author identity and date (which reword keeps), or with nothing. A
# Planwright-Sign-Off-Rejected trailer naming an old id must be re-stamped.
#
# Exit: 0 done (a push the remote took though it reported a failure
# included, with a note); 1 refused (a dispatched worker, protected, moved
# since the confirmation or deleted or moved while pushing, nothing dropped,
# not on the branch); 2 usage; 3 a git or remote failure.
#
# Untrusted text (subjects, names) reaches the terminal only through
# sanitize_printable or as jq-encoded JSON. Portable bash 3.2.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=tower-force-push
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -f "$script_dir/echo-safety.sh" ] || [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "$prog: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 3
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

TAB=$(printf '\t')
LEGACY_SUFFIX=' [pending-sign-off]'

usage() {
  printf '%s\n' "$prog: $1" >&2
  echo "usage: tower-force-push.sh reword|confirm|push|purge ... (see the header)" >&2
  exit 2
}
refuse() {
  printf '%s\n' "$prog: $1" >&2
  exit 1
}
broken() {
  printf '%s\n' "$prog: $1" >&2
  exit 3
}
safe() { sanitize_printable "$1" '(unprintable)'; }

# --- purge: printing only -----------------------------------------------------

# shq <word> — the word single-quoted for a POSIX shell.
shq() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

purge() {
  local args='' n=0 paths=0
  while [ "$#" -gt 0 ]; do
    case $1 in
      --path | --replace-text)
        [ "$#" -ge 2 ] || usage "$(safe "$1") needs a value"
        case $2 in
          '' | -*) usage "$(safe "$1") needs a value that does not start with a dash" ;;
        esac
        [ "$(safe "$2")" = "$2" ] || usage "$1 carries a control character"
        if [ "$1" = --path ]; then
          args="$args --path $(shq "$2")"
          paths=$((paths + 1))
        else
          args="$args --replace-text $(shq "$2")"
        fi
        n=$((n + 1))
        shift 2
        ;;
      *) usage "purge takes --path or --replace-text" ;;
    esac
  done
  [ "$n" -gt 0 ] || usage "purge needs at least one --path or --replace-text"
  [ "$paths" = 0 ] || args=" --invert-paths$args"
  cat <<EOF
Prepared only: the purge is the operator's to run; nothing here was executed.

Rotation checklist (before the purge, which does not un-leak a secret):
1. Revoke or rotate the leaked credential at its issuer.
2. Check the issuer's access logs for use since the leak.
3. Install git-filter-repo 2.47 or newer (it adds --sensitive-data-removal).
4. In a fresh mirror clone (git clone --mirror <url>), never a working checkout, run:

   git filter-repo --sensitive-data-removal$args

EOF
  case $args in
    *--replace-text*) echo "   --replace-text reads a file of literals to replace; keep that file out of the repository." ;;
  esac
  cat <<EOF
5. Force-push every rewritten ref from that clone yourself.
6. Ask the host to drop cached views and pull-request refs that still reach the secret (on GitHub, Support with the affected commit SHAs).
7. Have every collaborator re-clone, and every fork owner delete the data or the fork; an old clone pushing again restores it.
8. Re-run the secret scan over the rewritten history.
EOF
}

# --- the git verbs ------------------------------------------------------------

REMOTE=origin
BRANCH=''
TO=''
LEASE=''
COMMIT=''
MSG_FILE=''

parse() { # <verb> <args>...
  local verb=$1
  shift
  while [ "$#" -gt 0 ]; do
    [ "$#" -ge 2 ] || usage "$(safe "$1") needs a value"
    case $2 in
      '' | -*) usage "$(safe "$1") needs a value that does not start with a dash" ;;
    esac
    case "$verb:$1" in
      *:--remote) REMOTE=$2 ;;
      *:--branch) BRANCH=$2 ;;
      confirm:--to | push:--to) TO=$2 ;;
      push:--lease) LEASE=$2 ;;
      reword:--commit) COMMIT=$2 ;;
      reword:--message-file) MSG_FILE=$2 ;;
      *) usage "$verb does not take $(safe "$1")" ;;
    esac
    shift 2
  done
  [ -n "$BRANCH" ] || usage "$verb needs --branch"
  case $REMOTE in
    *[!A-Za-z0-9._-]* | .*) usage "invalid remote name" ;;
  esac
  case $BRANCH in
    refs/heads/*) BRANCH=${BRANCH#refs/heads/} ;;
  esac
  git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || usage "invalid branch name '$(safe "$BRANCH")'"
  git rev-parse --git-dir >/dev/null 2>&1 || broken "not inside a git repository"
  git remote | grep -qxF -- "$REMOTE" || refuse "no remote named '$(safe "$REMOTE")'"
}

# commit_of <rev> — the full commit id, or exit 2. It runs in a command
# substitution, so every caller must propagate that exit: an empty id leaves
# the push with no source, and a push of `:<branch>` deletes the branch.
commit_of() {
  local oid
  oid=$(git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null) || usage "'$(safe "$1")' is not a commit"
  printf '%s' "$oid"
}

protected_or_refuse() { # <branch>
  local rc=0
  "$script_dir/protected-branch.sh" "$1" >/dev/null || rc=$?
  case $rc in
    0) ;;
    1) refuse "'$(safe "$1")' is main, a protected branch, or a spec branch; no tier rewrites it" ;;
    *) refuse "the protected set could not be read (protected-branch.sh exit $rc); refusing (fail closed)" ;;
  esac
}

# refresh — fetch the remote branch and set LEASE_NOW to its tip.
refresh() {
  local tracking="refs/remotes/$REMOTE/$BRANCH"
  git fetch --quiet --no-tags "$REMOTE" "+refs/heads/$BRANCH:$tracking" 2>/dev/null \
    || broken "fetching $(safe "$REMOTE")/$(safe "$BRANCH") failed; the remote tip is unknown"
  LEASE_NOW=$(git rev-parse --verify --quiet "$tracking^{commit}") \
    || broken "$(safe "$REMOTE")/$(safe "$BRANCH") does not resolve after the fetch"
}

# dropped <from> <to> — `<sha>TAB<subject>` per commit the tip <from> reaches
# and <to> does not, newest first.
dropped() {
  git log --no-show-signature --format='%H%x09%s' "$2..$1" -- 2>/dev/null
}

# legacy_lines <range> — `<sha>TAB<author ident and date>` per legacy commit.
legacy_lines() {
  local sha subj
  git log --no-show-signature --format='%H%x09%s' "$1" -- 2>/dev/null | while IFS="$TAB" read -r sha subj; do
    case $subj in
      *"$LEGACY_SUFFIX") ;;
      *) continue ;;
    esac
    [ -z "$(git log --no-show-signature -1 --format='%(trailers:key=Planwright-Sign-Off,valueonly)' "$sha" | tr -d '[:space:]')" ] || continue
    printf '%s\t%s\n' "$sha" "$(git log --no-show-signature -1 --format='%an <%ae> %ad' --date=raw "$sha")"
  done
}

# legacy_changes <old tip> <new tip> — `PS-legacy-<old>TAB<PS-legacy-new or ->`
# per legacy commit the rewrite drops.
legacy_changes() {
  local old new o_sha o_id hit
  old=$(legacy_lines "$2..$1")
  [ -n "$old" ] || return 0
  new=$(legacy_lines "$1..$2")
  printf '%s\n' "$old" | while IFS="$TAB" read -r o_sha o_id; do
    hit=$(printf '%s\n' "$new" | awk -F '\t' -v id="$o_id" '$2 == id { print substr($1, 1, 7); exit }')
    printf 'PS-legacy-%s\t%s\n' "$(printf '%s' "$o_sha" | cut -c1-7)" "${hit:+PS-legacy-$hit}"
  done | sed "s/$TAB\$/$TAB-/"
}

# shellcheck disable=SC2016 # a jq program: the $ names are jq's
CONFIRM_JQ='
      def short: .[0:7];
      def names: map((.commit | short) + " " + (.subject | tojson)) | join("; ");
      . as $d
      | ($leg | split("\n") | map(select(length > 0) | split("\t") | {from: .[0], to: (if .[1] == "-" then null else .[1] end)})) as $lg
      | {
          question: "Force-push \($b) on \($r), replacing \($l | short) with \($t | short) and dropping \($d | length) remote commit(s): \($d | names)?",
          options: [
            {label: "Force-push \($b)",
             description: "Rewrites \($r)/\($b) from \($l | short) to \($t | short); the remote loses \($d | map(.commit | short) | join(", ")), and every clone holding them must reset to the new tip."
               + (if ($lg | length) > 0 then " Legacy checklist ids change: " + ($lg | map(.from + " -> " + (.to // "none")) | join(", ")) + "." else "" end)},
            {label: "Keep \($b) as it is", reject: true,
             description: "Pushes nothing; \($r)/\($b) stays at \($l | short) with every commit it has."}
          ],
          remote: $r, branch: $b, lease: $l, to: $t, dropped: $d, legacy: $lg,
          push: [$self, "push", "--remote", $r, "--branch", $b, "--to", $t, "--lease", $l]
        }'

not_a_force_or_refuse() { # <to> <remote tip>
  if git merge-base --is-ancestor "$2" "$1" 2>/dev/null; then
    refuse "$(safe "$REMOTE")/$(safe "$BRANCH") is already contained in the new tip; nothing is dropped, so a plain push suffices"
  fi
}

# confirmation_doc <dropped lines> <legacy lines> — the confirmation JSON.
confirmation_doc() {
  local sha subj
  printf '%s\n' "$1" | while IFS="$TAB" read -r sha subj; do
    jq -n --arg c "$sha" --arg s "$(safe "$subj" | cut -c1-72)" '{commit: $c, subject: $s}'
  done | jq -s --arg r "$REMOTE" --arg b "$BRANCH" --arg l "$LEASE_NOW" --arg t "$TO" \
    --arg leg "$2" --arg self "$script_dir/tower-force-push.sh" "$CONFIRM_JQ"
}

confirm() {
  parse confirm "$@"
  [ -n "$TO" ] || usage "confirm needs --to"
  protected_or_refuse "$BRANCH"
  TO=$(commit_of "$TO") || exit 2
  refresh
  not_a_force_or_refuse "$TO" "$LEASE_NOW"
  local drops legacy doc
  drops=$(dropped "$LEASE_NOW" "$TO")
  [ -n "$drops" ] || broken "no dropped commit could be listed"
  legacy=$(legacy_changes "$LEASE_NOW" "$TO")
  doc=$(confirmation_doc "$drops" "$legacy") || broken "the confirmation could not be built"
  printf '%s\n' "$doc" | "$script_dir/check-confirmation.sh" >/dev/null \
    || broken "the confirmation failed check-confirmation.sh; not printing it"
  printf '%s\n' "$doc"
}

push() {
  parse push "$@"
  [ -n "$TO" ] || usage "push needs --to"
  [ -n "$LEASE" ] || usage "push needs --lease (the tip the confirmation named)"
  protected_or_refuse "$BRANCH"
  TO=$(commit_of "$TO") || exit 2
  case $LEASE in
    *[!0-9a-f]*) usage "--lease must be the full commit id the confirmation printed" ;;
  esac
  [ "${#LEASE}" = 40 ] || [ "${#LEASE}" = 64 ] || usage "--lease must be the full commit id the confirmation printed"
  refresh
  [ "$LEASE_NOW" = "$LEASE" ] \
    || refuse "$(safe "$REMOTE")/$(safe "$BRANCH") moved since the confirmation ($(printf '%s' "$LEASE" | cut -c1-7) -> $(printf '%s' "$LEASE_NOW" | cut -c1-7)); confirm again"
  not_a_force_or_refuse "$TO" "$LEASE"
  local drops legacy landed_note=''
  drops=$(dropped "$LEASE" "$TO")
  legacy=$(legacy_changes "$LEASE" "$TO")
  [ -n "$TO" ] || usage "push has no commit to push"
  if ! git push --quiet --force-with-lease="refs/heads/$BRANCH:$LEASE" --force-if-includes \
    "$REMOTE" "$TO:refs/heads/$BRANCH"; then
    # A lease lost to a push or a deletion that landed in between is a
    # refusal, not a failure to retry: someone else works from the branch now.
    # A remote already at <to> took this push and only the report was lost.
    local now
    now=$(git ls-remote --heads "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null) \
      || broken "the push failed and $(safe "$REMOTE")/$(safe "$BRANCH") could not be read; its tip is unknown"
    now=$(printf '%s\n' "$now" | awk -v r="refs/heads/$BRANCH" '$2 == r { print $1; exit }')
    if [ "$now" = "$TO" ]; then
      # The failed push left the tracking ref at the old tip, which the reset
      # note below points a checkout at.
      git update-ref "refs/remotes/$REMOTE/$BRANCH" "$TO" 2>/dev/null \
        || broken "$(safe "$REMOTE")/$(safe "$BRANCH") holds the new tip, but its tracking ref could not be updated"
      landed_note="note	the push reported a failure, but $(safe "$REMOTE")/$(safe "$BRANCH") holds the new tip"
    elif [ -z "$now" ]; then
      refuse "$(safe "$REMOTE")/$(safe "$BRANCH") was deleted while pushing; someone else works from it, so treat it as shared and do not retry"
    elif [ "$now" != "$LEASE" ]; then
      refuse "$(safe "$REMOTE")/$(safe "$BRANCH") moved while pushing ($(printf '%s' "$LEASE" | cut -c1-7) -> $(printf '%s' "$now" | cut -c1-7)); someone else works from it, so treat it as shared and do not retry"
    else
      broken "the push failed; $(safe "$REMOTE")/$(safe "$BRANCH") reads unchanged, unless its push URL differs from the one read"
    fi
  fi
  printf 'pushed\t%s\t%s\t%s\t%s\n' "$(safe "$REMOTE")" "$(safe "$BRANCH")" "$LEASE" "$TO"
  [ -z "$landed_note" ] || printf '%s\n' "$landed_note"
  printf '%s\n' "$drops" | while IFS="$TAB" read -r sha subj; do
    printf 'dropped\t%s\t%s\n' "$sha" "$(safe "$subj")"
  done
  if [ -n "$legacy" ]; then
    printf '%s\n' "$legacy" | while IFS="$TAB" read -r from to; do
      printf 'legacy\t%s\t%s\n' "$from" "$to"
    done
    echo "note	re-stamp any Planwright-Sign-Off-Rejected trailer naming an old legacy id with its new id, in a new commit"
  fi
  echo "note	a checkout of $(safe "$BRANCH") still holding the dropped commits must reset to $(safe "$REMOTE")/$(safe "$BRANCH") before its next commit"
}

reword() {
  parse reword "$@"
  [ -n "$COMMIT" ] || usage "reword needs --commit"
  [ -n "$MSG_FILE" ] || usage "reword needs --message-file"
  [ -f "$MSG_FILE" ] && [ -r "$MSG_FILE" ] || usage "the message file is not a readable file"
  [ -n "$(grep -v '^[[:space:]]*$' "$MSG_FILE" | head -1)" ] || usage "the message file is empty"
  protected_or_refuse "$BRANCH"
  COMMIT=$(commit_of "$COMMIT") || exit 2
  refresh
  git merge-base --is-ancestor "$COMMIT" "$LEASE_NOW" 2>/dev/null \
    || refuse "that commit is not on $(safe "$REMOTE")/$(safe "$BRANCH")"
  # Every remote branch, refreshed: a stale or missing tracking ref would read
  # a commit main now holds as safe to reword.
  git fetch --quiet --no-tags "$REMOTE" "+refs/heads/*:refs/remotes/$REMOTE/*" 2>/dev/null \
    || broken "fetching $(safe "$REMOTE")'s branches failed; which protected branches hold the commit is unknown"
  local ref name rc
  for ref in $(git for-each-ref --format='%(refname)' --contains "$COMMIT" "refs/remotes/$REMOTE/"); do
    name=${ref#refs/remotes/"$REMOTE"/}
    [ "$name" != "$BRANCH" ] && [ "$name" != HEAD ] || continue
    rc=0
    "$script_dir/protected-branch.sh" "$name" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 0 ] || refuse "that commit is also on $(safe "$REMOTE")/$(safe "$name"), which is protected; rewording it would fork that history"
  done

  local map work c p parents np new tree
  work=$(mktemp -d) || broken "mktemp failed"
  # shellcheck disable=SC2064 # the path is fixed now
  trap "rm -rf '$work'" EXIT
  map="$work/map"
  : >"$map"
  {
    printf '%s\n' "$COMMIT"
    git rev-list --topo-order --reverse --ancestry-path "$COMMIT..$LEASE_NOW"
  } >"$work/list" \
    || broken "the commits to replay could not be listed"
  while read -r c; do
    tree=$(git rev-parse "$c^{tree}") || broken "a tree did not resolve"
    parents=''
    for p in $(git rev-list --parents -n 1 "$c" | cut -s -d' ' -f2-); do
      np=$(awk -v k="$p" '$1 == k { print $2; exit }' "$map")
      parents="$parents -p ${np:-$p}"
    done
    if [ "$c" = "$COMMIT" ]; then
      cp "$MSG_FILE" "$work/msg"
    else
      git cat-file commit "$c" | sed '1,/^$/d' >"$work/msg"
    fi
    # shellcheck disable=SC2086 # $parents is a list of -p <oid> pairs
    new=$(
      GIT_AUTHOR_NAME=$(git log --no-show-signature -1 --format=%an "$c") \
      GIT_AUTHOR_EMAIL=$(git log --no-show-signature -1 --format=%ae "$c") \
      GIT_AUTHOR_DATE=$(git log --no-show-signature -1 --format=%ad --date=raw "$c") \
        git commit-tree "$tree" $parents -F "$work/msg"
    ) || broken "replaying $(printf '%s' "$c" | cut -c1-7) failed"
    printf '%s %s\n' "$c" "$new" >>"$map"
  done <"$work/list"
  new=$(awk -v k="$LEASE_NOW" '$1 == k { print $2; exit }' "$map")
  [ -n "$new" ] || broken "the replay did not reach the remote tip"
  printf 'reworded\t%s\t%s\n' "$COMMIT" "$(awk -v k="$COMMIT" '$1 == k { print $2; exit }' "$map")"
  printf 'lease\t%s\n' "$LEASE_NOW"
  printf 'to\t%s\n' "$new"
}

[ "$#" -ge 1 ] || usage "a verb is required"
verb=$1
shift
case $verb in
  confirm | push | reword)
    # The helper's own last line behind the worker deny, for a wrapper or copy
    # the policy guard cannot read. It reaches only workers launched with an
    # identity; a launch that exports none (stream-json, a flight) is not seen.
    [ -z "${PLANWRIGHT_WORKER_HANDLE:-}" ] && [ -z "${PLANWRIGHT_WORKER_SCOPE:-}" ] \
      || refuse "a dispatched worker runs no verb of the force-push path; it is the tower's, on the operator's request. Name the reword or force-push in your handoff instead."
    command -v jq >/dev/null 2>&1 || broken "jq is required"
    "$verb" "$@"
    ;;
  purge) purge "$@" ;;
  -h | --help) sed -n '2,/^[^#]/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' ;;
  *) usage "unknown verb '$(safe "$verb")'" ;;
esac
