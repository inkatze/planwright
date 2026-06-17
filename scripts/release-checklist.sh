#!/usr/bin/env bash
# release-checklist.sh — the public-release readiness gate (Task 19; REQ-J1.5,
# REQ-J1.4, D-27). planwright starts private; this checklist is what makes the
# private→public flip a verified decision instead of a remembered one.
#
# It VERIFIES; it never PERFORMS. In particular the `reference/` history purge
# is a human-reserved action (REQ-J1.4: a deliberate history rewrite); this
# script only confirms it happened. Nothing here mutates the repository.
#
# What it checks:
#   REQ-J1.5 gate (a) — the framework intelligence (formerly the dotfiles
#                       CLAUDE.md rules) is inlined into planwright's own
#                       doctrine docs. Mechanical proxy: the core rule docs
#                       exist under doctrine/.
#   REQ-J1.5 gate (b) — the four-file format meta-spec exists
#                       (doctrine/spec-format.md).
#   REQ-J1.5 gate (c) — at least one clean end-to-end run on a real
#                       multi-contributor work repo has completed. This cannot
#                       be detected from this repository; it is a HUMAN
#                       ATTESTATION, confirmed with --confirm-workrepo-run (or
#                       RELEASE_WORKREPO_RUN_CONFIRMED=1). The release-checklist
#                       doc (docs/release-checklist.md) tells the human what to
#                       confirm before passing it.
#   Release-blocking gated Deferred entry — the `reference/` history purge:
#                       reference/ is absent from the working tree AND from all
#                       git history. A plain `git rm` is NOT enough; the purge
#                       requires a history rewrite, so the history check is the
#                       one with teeth.
#
# Future release-blocking gated Deferred entries are added here as they appear
# (the checklist's scope is "the three gate conditions PLUS every
# release-blocking gated Deferred entry", brief Amendment 6).
#
# Usage: release-checklist.sh [--confirm-workrepo-run] [<repo-dir>]
#   <repo-dir> defaults to the repo this script ships in. The flag attests
#   REQ-J1.5 condition (c). RELEASE_WORKREPO_RUN_CONFIRMED=1 is equivalent.
#
# Exit codes: 0 ready for public release; 1 not ready (some gate outstanding,
# or the target is not a git repo so the purge cannot be verified); 2 usage
# error.
#
# Deliberately NOT part of `mise run check`: this is a release-time gate, and
# it correctly fails while the repo is pre-release (reference/ is still
# tracked so worktrees can reach the migration sources). Its unit test
# (tests/test-release-checklist.sh) does run in CI.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

confirm_workrepo_run="${RELEASE_WORKREPO_RUN_CONFIRMED:-}"
repo_arg=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --confirm-workrepo-run)
      confirm_workrepo_run=1
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "release-checklist: unknown option: $1" >&2
      echo "usage: release-checklist.sh [--confirm-workrepo-run] [<repo-dir>]" >&2
      exit 2
      ;;
    *)
      if [ -n "$repo_arg" ]; then
        echo "release-checklist: unexpected extra argument: $1" >&2
        exit 2
      fi
      repo_arg="$1"
      ;;
  esac
  shift
done
# Consume any positionals that followed a `--` separator under the same
# one-repo-dir contract the in-loop arm enforces: the first sets repo_arg, a
# second is a usage error (never silently dropped).
while [ "$#" -gt 0 ]; do
  if [ -n "$repo_arg" ]; then
    echo "release-checklist: unexpected extra argument: $1" >&2
    exit 2
  fi
  repo_arg="$1"
  shift
done

if [ -n "$repo_arg" ]; then
  if [ ! -d "$repo_arg" ]; then
    echo "release-checklist: no such directory: $repo_arg" >&2
    exit 2
  fi
  repo_root="$(cd "$repo_arg" && pwd -P)" || exit 2
else
  repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
fi

# Accumulators: each check appends one table row and flips not_ready on a block.
not_ready=0
rows=""

add_row() {
  # add_row <status> <item> <detail>; status one of PASS / BLOCK / MANUAL.
  rows="${rows}$(printf '%-7s | %-46s | %s' "$1" "$2" "$3")
"
  case "$1" in
    PASS) : ;;
    *) not_ready=1 ;;
  esac
}

# --- REQ-J1.5 gate (a): rules inlined into planwright's own doctrine ---
# The migration (Task 3) landed the framework intelligence as standalone
# doctrine docs. Require the load-bearing rule docs to be present and
# non-empty; their absence means the intelligence was never inlined.
missing_doctrine=""
for doc in validation-rigor finding-categorization engineering-decisions; do
  f="$repo_root/doctrine/$doc.md"
  if [ ! -s "$f" ]; then
    missing_doctrine="$missing_doctrine $doc.md"
  fi
done
if [ -z "$missing_doctrine" ]; then
  add_row PASS "(a) CLAUDE.md rules inlined into doctrine" "doctrine/ rule docs present"
else
  add_row BLOCK "(a) CLAUDE.md rules inlined into doctrine" "missing/empty:$missing_doctrine"
fi

# --- REQ-J1.5 gate (b): the four-file format meta-spec exists ---
if [ -s "$repo_root/doctrine/spec-format.md" ]; then
  add_row PASS "(b) four-file format meta-spec exists" "doctrine/spec-format.md present"
else
  add_row BLOCK "(b) four-file format meta-spec exists" "doctrine/spec-format.md missing/empty"
fi

# --- REQ-J1.5 gate (c): clean multi-contributor work-repo E2E run ---
# Not detectable from this repo; human attestation per the doc.
if [ "$confirm_workrepo_run" = "1" ]; then
  add_row PASS "(c) clean multi-contributor work-repo run" "attested (--confirm-workrepo-run)"
else
  add_row MANUAL "(c) clean multi-contributor work-repo run" \
    "HUMAN ATTESTATION REQUIRED — re-run with --confirm-workrepo-run once the work-repo E2E run + findings doc exist"
fi

# --- Release-blocking gated Deferred entry: reference/ history purge ---
# Working-tree absence.
if [ -e "$repo_root/reference" ]; then
  add_row BLOCK "reference/ purge — working tree" "reference/ still present in the working tree"
else
  add_row PASS "reference/ purge — working tree" "reference/ absent from the working tree"
fi

# History absence. Requires a git repo; if the target is not one, the purge
# cannot be verified, so the release is not ready (degrade clearly, REQ-K1.7).
if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
  # Capture the full log and the command's own status: a git failure must
  # fail closed (BLOCK), never read as an empty result that PASSes blind —
  # this is a release gate, so an unverifiable history is not a clean one.
  if hist="$(git -C "$repo_root" log --all --oneline -- reference 'reference/*' 2>/dev/null)"; then
    if [ -n "$hist" ]; then
      add_row BLOCK "reference/ purge — git history" \
        "reference/ survives in history (a history rewrite, e.g. git filter-repo, is required — git rm is not enough)"
    else
      add_row PASS "reference/ purge — git history" "no reachable history touches reference/"
    fi
  else
    add_row BLOCK "reference/ purge — git history" \
      "cannot verify: git log failed in $repo_root"
  fi
else
  add_row BLOCK "reference/ purge — git history" \
    "cannot verify: $repo_root is not a git repository"
fi

# --- Report ---
echo "planwright public-release readiness checklist"
echo "target: $repo_root"
echo
printf '%-7s | %-46s | %s\n' "STATUS" "GATE" "DETAIL"
printf '%s\n' "$rows" | sed '/^$/d'
echo

if [ "$not_ready" -eq 0 ]; then
  echo "READY FOR PUBLIC RELEASE — all gate conditions and release-blocking"
  echo "Deferred entries are satisfied. The private→public flip and any version"
  echo "bump remain human actions."
  exit 0
fi

echo "NOT READY — one or more gates are outstanding (BLOCK) or awaiting human"
echo "attestation (MANUAL). See docs/release-checklist.md for how to clear each."
exit 1
