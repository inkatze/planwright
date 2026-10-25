#!/bin/sh
# inception-scaffold.sh — the venture repo hygiene scaffold (inception Task 2;
# REQ-A1.9, REQ-G1.1, REQ-G1.5, REQ-G1.8 · D-9, D-11, D-12).
#
# `/inception` calls this at venture-repo creation. It EMITS the guard files
# rather than copying static ones out of the plugin, so the emitted content is
# a tested code path and the rung scaling lives in one place.
#
# What lands, scaled to the rung (REQ-A1.9):
#
#   every rung   .gitignore              machine-local files, derived clutter
#                githooks/pre-commit     secret screen, bundle validation,
#                                        export regeneration (REQ-G1.1)
#                hygiene-wiring.md       what was wired, what the operator
#                                        still has to do, and how to bypass
#                sync-protocol.md        the editing ritual for sessions outside
#                                        planwright, Cowork's included (REQ-G1.8)
#                CLAUDE.md               imports the protocol; an existing one
#                                        gains the import line, never replaced
#   remote only  .github/workflows/venture-guard.yml
#                                        secret scan plus the stakeholder-commit
#                                        guard (REQ-G1.5): a web-UI edit that
#                                        mangles an id, breaks structure, or
#                                        rewrites a gate record fails CI
#
# The rung is detected from the target (a git remote means remote) and can be
# forced with --rung. Existing files are kept, never clobbered, unless --force
# says otherwise: the operator owns their repo, and a scaffold that silently
# rewrites an edited hook is a scaffold nobody edits.
#
# The emitted hook resolves planwright at RUN time: it sources the machine-local
# .planwright-local.sh, finds a copy (PLANWRIGHT_ROOT, CLAUDE_PLUGIN_ROOT,
# ~/.claude/planwright, the plugin cache), then lets a copy that ships the root
# helper name the install root through the core root chain. No install path is baked into the tracked file: a venture repo
# is cloned onto other machines, and a hard-coded path would break on all of
# them. When planwright cannot be resolved, the hook warns loudly and lets the
# commit through — on the remote rung CI is the backstop.
#
# Usage:
#   inception-scaffold.sh [--rung local|remote] [--force] [--wire] <venture-dir>
#
# Output: one `wrote <path>` or `kept <path>` line per scaffold file
#   (`updated CLAUDE.md` when the import is appended to an existing one), then
#   a one-line rung summary. A CLAUDE.md the scaffold will not write (a
#   symbolic link, not a regular file, not readable, or an append that fails)
#   gets a warning on stderr instead of a line.
#
# Exit: 0 emitted · 2 usage or environment error.
#
# Portable POSIX sh; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: inception-scaffold.sh [--rung local|remote] [--force] [--wire] <venture-dir>" >&2
  exit 2
}

rung=
force=0
wire=0
target=

while [ $# -gt 0 ]; do
  case $1 in
    --rung)
      [ $# -ge 2 ] || usage
      rung=$2
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --wire)
      wire=1
      shift
      ;;
    -*) usage ;;
    *)
      [ -z "$target" ] || usage
      target=$1
      shift
      ;;
  esac
done

[ -n "$target" ] || usage
while [ "$target" != "${target%/}" ]; do target=${target%/}; done
[ -n "$target" ] || target=/
[ -d "$target" ] || {
  printf '%s\n' "inception-scaffold: not a directory: $target" >&2
  exit 2
}

case ${rung:-} in
  '' | local | remote) ;;
  *)
    echo "inception-scaffold: --rung must be local or remote" >&2
    exit 2
    ;;
esac

if [ -z "$rung" ]; then
  rung=local
  if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git -C "$target" remote 2>/dev/null)" ]; then
      rung=remote
    fi
  fi
fi

# emit <relative-path> <mode> — write the file the caller has just staged into
# $stage, unless one is already there and --force was not given.
# Explicit template (the house pattern, see scripts/builder-guards.sh): a bare
# `mktemp` relies on a default template BSD mktemp does not supply, so it fails
# on the macOS/BSD half of the floor this file's header claims — and it fails
# before a single scaffold file is emitted.
stage=$(mktemp "${TMPDIR:-/tmp}/inception-scaffold.XXXXXX") || exit 2
trap 'rm -f "$stage"' EXIT

emit() {
  dest="$target/$1"
  if [ -e "$dest" ] && [ "$force" -eq 0 ]; then
    printf 'kept %s\n' "$1"
    return 0
  fi
  mkdir -p "$(dirname "$dest")" || exit 2
  cp "$stage" "$dest" || exit 2
  chmod "$2" "$dest" || exit 2
  printf 'wrote %s\n' "$1"
}

# --- .gitignore ------------------------------------------------------------

cat >"$stage" <<'GITIGNORE'
# Venture repo ignores. Machine-local plumbing and editor droppings only:
# everything the venture is ABOUT is tracked, including the derived export,
# which stakeholders read straight off the forge.

# Machine-local environment layer: paths and session plumbing that differ per
# machine. The pre-commit hook sources it when present. Never secrets.
.planwright-local.sh

# Editor and OS
.DS_Store
Thumbs.db
*.swp
*~
.idea/
.vscode/

# Scratch
*.log
*.tmp
tmp/

# A render writes each page to a dotted temp file beside it first; one is left
# only when a render is killed mid-write, and is never a page to commit.
exports/.*.html.*
GITIGNORE
emit .gitignore 644

# --- githooks/pre-commit ---------------------------------------------------

cat >"$stage" <<'HOOK'
#!/bin/sh
# Venture repo pre-commit guard, scaffolded by planwright /inception
# (inception REQ-A1.9, REQ-G1.1 · D-9, D-12).
#
# Three steps, in this order and with these blocking semantics:
#
#   1. Secret screen over the STAGED content. Blocks. A credential that reaches
#      a commit is in history forever, so this is the one hard stop.
#   2. Bundle validation. Warns. A bundle is written incrementally, and a hook
#      that refuses every half-finished elicitation is a hook the operator
#      disables. Set PLANWRIGHT_VENTURE_STRICT=1 to make findings block; on a
#      repo with a remote, CI blocks regardless.
#   3. Export regeneration (the dashboard and the pitch), staged into this same
#      commit so the published HTML never lags the bundle. Warns and lets the
#      commit through when the render or the staging fails (REQ-A1.9): neither
#      may dead-end a commit, and neither may fail in silence, or the exports
#      drift unnoticed. The pages and the bundle files they come from are
#      screened before anything is staged, though, and that screen blocks:
#      they are rendered from the working tree, so they can carry bundle text
#      step 1 never saw.
#
# Bypass the whole hook with `git commit --no-verify`.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Machine-local environment layer: the place to set PLANWRIGHT_ROOT on a
# machine where the plugin lives somewhere unusual. Gitignored by design.
if [ -f "$top/.planwright-local.sh" ]; then
  # shellcheck disable=SC1091 # machine-local, not present in the repo
  . "$top/.planwright-local.sh"
fi

# Resolve planwright at run time; never bake an install path into a tracked
# file, because this repo gets cloned onto other machines.
#
# Readable, not executable. A plugin tree reaches a venture host by whatever
# copied it there, and an archive, a container layer or a sync tool can drop the
# +x bit without dropping the file. Probing for -x made that lost bit mean
# "planwright is not installed", and every guard below then skipped itself. So
# nothing here tests the executable bit, and everything runs through /bin/sh —
# the scripts all declare #!/bin/sh, so this is what the kernel would have done
# with the bit set anyway.
#
# The cache entry quotes the VARIABLE and leaves the `*` bare, so the glob still
# expands while a $HOME carrying a space stays one word. Unquoted, such a HOME
# splits into candidate fragments that resolve to nothing, planwright reads as
# not installed, and every guard below skips itself (shellcheck SC2231).
pw=
for cand in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" \
  "$HOME/.claude/planwright" "$HOME"/.claude/plugins/cache/planwright/planwright/*; do
  if [ -n "$cand" ] && [ -r "$cand/scripts/inception-validate.sh" ]; then
    pw=$cand
    break
  fi
done

# A copy that ships the root helper decides the install root itself, so the
# hook follows the same core root chain every planwright script does; an older
# copy without the helper, or an answer holding no validator, keeps the copy
# found above. The helper runs as a child, so the values the loop read are
# handed to it: .planwright-local.sh sets PLANWRIGHT_ROOT without exporting it.
if [ -n "$pw" ] && [ -r "$pw/scripts/resolve-root.sh" ]; then
  if pw_root=$(PLANWRIGHT_ROOT=${PLANWRIGHT_ROOT:-} CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-} \
    /bin/sh "$pw/scripts/resolve-root.sh" install 2>/dev/null) &&
    [ -r "$pw_root/scripts/inception-validate.sh" ]; then
    pw=$pw_root
  fi
fi

if [ -z "$pw" ]; then
  echo "venture pre-commit: planwright not found; skipping the venture guards." >&2
  echo "venture pre-commit: set PLANWRIGHT_ROOT in .planwright-local.sh to enable them." >&2
  exit 0
fi

# 1. Secrets — the hard stop.
#
# Its absence is an environment failure, never a reason to carry on quietly.
# This step is the one hard stop in the whole scaffold, so a commit that skipped
# it has had no secret screening at all; saying nothing would make that
# indistinguishable from a commit that passed.
if [ ! -r "$pw/scripts/inception-secret-screen.sh" ]; then
  echo "venture pre-commit: the secret screen is missing or unreadable at $pw; commit refused." >&2
  echo "venture pre-commit: this is an environment problem — reinstall planwright, or bypass deliberately with --no-verify." >&2
  exit 1
fi
ssc=0
/bin/sh "$pw/scripts/inception-secret-screen.sh" --staged || ssc=$?
# 1 and 2 both refuse the commit, but they are different facts and get
# different words. Saying "carries a credential" when the screen could not RUN
# sends the operator hunting through their bundle for something that is not
# there — the same distinction step 3 draws below.
if [ "$ssc" -eq 1 ]; then
  echo "venture pre-commit: staged content looks like it carries a credential; commit refused." >&2
  echo "venture pre-commit: remove it, or bypass deliberately with --no-verify." >&2
  exit 1
elif [ "$ssc" -ne 0 ]; then
  echo "venture pre-commit: the secret screen could not check the staged content (exit $ssc); commit refused." >&2
  echo "venture pre-commit: this is an environment problem, not a finding — see the output above." >&2
  exit 1
fi

# 2 and 3 apply only to a repo that actually holds a bundle.
[ -f "$top/brief.md" ] || exit 0

if ! /bin/sh "$pw/scripts/inception-validate.sh" "$top"; then
  if [ "${PLANWRIGHT_VENTURE_STRICT:-0}" = "1" ]; then
    echo "venture pre-commit: bundle findings above, and strict mode is on; commit refused." >&2
    exit 1
  fi
  echo "venture pre-commit: bundle findings above (not blocking; set PLANWRIGHT_VENTURE_STRICT=1 to block)." >&2
fi

# 3. Export regeneration.
#
# Each page is rendered into a private directory inside the git directory, not
# straight into exports/: the bytes screened are then the bytes staged, and a
# render of the work tree running meanwhile (another commit, a publish offer)
# cannot swap a page in between the screen and the stage. The screened page is
# staged by its blob, then moved into exports/ so the work tree matches the
# commit. The renderer's stderr stays visible: its refusal names the cause,
# which the warning below cannot.
not_regenerated() {
  echo "venture pre-commit: the exports were not regenerated; they may now lag the bundle." >&2
  echo "venture pre-commit: committing anyway — a broken render never blocks a commit." >&2
  exit 0
}
git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || not_regenerated
# The pages are rendered by separate processes, so "today" is fixed once: a
# commit that crosses midnight must not classify kill criteria differently on
# each page.
PLANWRIGHT_INCEPTION_TODAY=${PLANWRIGHT_INCEPTION_TODAY:-$(date +%Y-%m-%d)}
export PLANWRIGHT_INCEPTION_TODAY
priv=$(mktemp -d "$git_dir/planwright-render.XXXXXX") || not_regenerated
# dash runs no EXIT trap when a signal kills it, so each signal exits through it.
trap 'rm -rf "$priv"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
# One snapshot of the bundle is both rendered and screened, so an edit to the
# work tree in between cannot clean the sources the screen reads while the
# escaped page still carries the credential. Links are refused before the
# copy, which would follow them, and so is a linked exports/.
if [ -h "$top/exports" ]; then
  echo "venture pre-commit: exports/ is a symbolic link; refusing to write the pages through it." >&2
  not_regenerated
fi
snap="$priv/bundle"
mkdir "$snap" || not_regenerated
for f in brief.md disciplines.md assumptions.md decisions.md plan.md; do
  if [ -h "$top/$f" ]; then
    echo "venture pre-commit: $f is a symbolic link; refusing to render through it." >&2
    not_regenerated
  fi
  # Only a regular file is copied: a FIFO would block cp waiting for a writer.
  if [ -e "$top/$f" ] && [ ! -f "$top/$f" ]; then
    echo "venture pre-commit: $f is not a regular file; refusing to render from it." >&2
    not_regenerated
  fi
  [ ! -e "$top/$f" ] || cp "$top/$f" "$snap/$f" || not_regenerated
done
for page in venture pitch; do
  if [ "$page" = pitch ]; then mode=pitch; else mode=dashboard; fi
  /bin/sh "$pw/scripts/inception-render.sh" --mode "$mode" --output "$priv/$page.html" "$snap" >/dev/null ||
    not_regenerated
done

# The working-tree bundle files are screened with the pages, in one call:
# escaping turns a quoted assignment's quotes into entities no credential
# pattern matches, so the pages alone can hide what their source shows.
src=0
/bin/sh "$pw/scripts/inception-secret-screen.sh" -- \
  "$snap/brief.md" "$snap/disciplines.md" "$snap/assumptions.md" \
  "$snap/decisions.md" "$snap/plan.md" "$priv/venture.html" "$priv/pitch.html" || src=$?
# 1 and 2 both block, but they are different facts and get different words:
# saying "carries a credential" when the screen could not run sends the
# operator hunting through their bundle for something that is not there.
if [ "$src" -eq 1 ]; then
  echo "venture pre-commit: the bundle in your working tree, or a page regenerated from it, looks like it carries a credential; commit refused." >&2
  echo "venture pre-commit: fix it in the bundle file the screen names above, then commit." >&2
  exit 1
elif [ "$src" -ne 0 ]; then
  echo "venture pre-commit: the secret screen could not check the bundle and its regenerated pages (exit $src); commit refused." >&2
  echo "venture pre-commit: this is an environment problem, not a finding — see the output above." >&2
  exit 1
fi

# Staging failure warns, like a failed render: step 3 never dead-ends a commit.
# It must not be SILENT, though. The contract this step exists to keep is that
# the exports ride the same commit, and a swallowed stage (an ignored exports/,
# a locked index) breaks that contract while the commit still reads as clean.
# git's own message goes to stderr unredirected, so the reason is visible
# without this hook re-echoing repo-controlled text. Only the export paths are
# staged, never the tree, so a partial commit stays partial. update-index does
# not consult .gitignore, so an ignored page is refused here, as `git add` would.
#
# Each page is hashed through its path's filters, as `git add` would, and that
# filtered blob is screened before anything is staged: a clean filter can add
# bytes the screen of the unfiltered page never saw.
blob_venture=
blob_pitch=
set --
for page in venture pitch; do
  rel="exports/$page.html"
  git check-ignore -q "$rel" && continue
  if b=$(git hash-object -w --path="$rel" "$priv/$page.html") &&
    git cat-file blob "$b" >"$priv/$page.staged"; then
    if [ "$page" = pitch ]; then blob_pitch=$b; else blob_venture=$b; fi
    set -- "$@" "$priv/$page.staged"
  fi
done
if [ $# -gt 0 ]; then
  src=0
  /bin/sh "$pw/scripts/inception-secret-screen.sh" -- "$@" || src=$?
  if [ "$src" -eq 1 ]; then
    echo "venture pre-commit: a regenerated page, as its path's clean filter stages it, looks like it carries a credential; commit refused." >&2
    echo "venture pre-commit: check the filter configured for exports/ in .gitattributes and your git config." >&2
    exit 1
  elif [ "$src" -ne 0 ]; then
    echo "venture pre-commit: the secret screen could not check the pages as they would be staged (exit $src); commit refused." >&2
    exit 1
  fi
fi
for page in venture pitch; do
  rel="exports/$page.html"
  if [ "$page" = pitch ]; then blob=$blob_pitch; else blob=$blob_venture; fi
  if git check-ignore -q "$rel"; then
    echo "venture pre-commit: the regenerated $rel could not be staged (it is gitignored), so this commit carries a stale or absent export." >&2
  elif [ -z "$blob" ] || ! git update-index --add --cacheinfo "100644,$blob,$rel"; then
    echo "venture pre-commit: the regenerated $rel could not be staged, so this commit carries a stale or absent export." >&2
    echo "venture pre-commit: committing anyway — see git's message above." >&2
  fi
  # Checked again at the write itself, not only before rendering: exports/
  # swapped for a link in between would send the page outside the checkout.
  # This narrows the window; no portable primitive closes it.
  if [ -h "$top/exports" ]; then
    echo "venture pre-commit: exports/ became a symbolic link; $rel is not written to the work tree, though the commit still carries it." >&2
    continue
  fi
  if ! mkdir -p "$top/exports" || ! mv -f "$priv/$page.html" "$top/$rel"; then
    echo "venture pre-commit: the regenerated $rel could not be written to the work tree; the commit still carries it." >&2
  fi
done

exit 0
HOOK
emit githooks/pre-commit 755

# --- .github/workflows/venture-guard.yml (remote rung only) ----------------

if [ "$rung" = remote ]; then
  cat >"$stage" <<'WORKFLOW'
---
# Venture guard, scaffolded by planwright /inception (inception REQ-A1.9,
# REQ-G1.5 · D-12). Two jobs, both read-only:
#
#   secrets    a full-history scan, so a credential cannot ride in through the
#              web UI or a clone that skipped the pre-commit hook.
#   bundle     the inception-format validator, run against the merge base so a
#              stakeholder edit that mangles an id, breaks structure, or
#              rewrites a recorded gate run fails the check while an ordinary
#              prose edit passes.
#
# "on" is quoted because a bare `on:` is YAML 1.1 true.
name: venture-guard

"on":
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Scan history for secrets
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  bundle:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Check out planwright
        uses: actions/checkout@v4
        with:
          repository: inkatze/planwright
          path: .planwright
      - name: Validate the inception bundle
        run: |
          # The baseline differs by event, and a push is the one that matters
          # most here: an edit made in the GitHub web UI straight to main is a
          # push, not a pull request, and that is exactly the channel the
          # append-only guard exists to police. Reading only the pull-request
          # expression left it empty on push and silently downgraded the run to
          # plain validation.
          base="${{ github.event.pull_request.base.sha }}"
          [ -n "$base" ] || base="${{ github.event.before }}"
          # The first push to a branch reports an all-zero "before", and a
          # force-push can name a commit this clone no longer has.
          case "$base" in
            *[!0]*) ;;
            *) base= ;;
          esac
          if [ -n "$base" ] && git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
            .planwright/scripts/inception-validate.sh --baseline "$base" .
          else
            # Say it. A guard that did not run must never look like one that ran
            # and found nothing.
            echo "venture-guard: no usable baseline for this event;" >&2
            echo "venture-guard: the stakeholder-commit guard did NOT run" >&2
            .planwright/scripts/inception-validate.sh .
          fi
WORKFLOW
  emit .github/workflows/venture-guard.yml 644
fi

# --- sync-protocol.md and its CLAUDE.md import ----------------------------

# Written for an agent that is not planwright (Cowork's, a stakeholder's
# Claude) and for the person beside it. It is advisory: nothing here can stop
# an agent that ignores it, which is why the protocol says the validator and
# CI are the enforcement.
cat >"$stage" <<'PROTOCOL'
# Sync protocol for this venture

This folder is a venture repository kept by planwright's `/inception`. Its files are the venture's
record, shared through git. Anyone working here, a person or an agent (a Cowork session included),
follows this protocol. The one exception is a session running planwright's `/inception`, which
keeps the bookkeeping below for the venture's operator.

## Reading

Read anything, freely. `exports/venture.html` and `exports/pitch.html` are generated from the
bundle files; read them, never edit them.

## Editing

1. **Pull first.** Run `git pull --no-rebase` before changing anything, so you edit the latest
   copy.
2. **Edit the bundle files** (`brief.md`, `disciplines.md`, `assumptions.md`, `decisions.md`,
   `plan.md`) in plain prose. Wording, evidence, context and new notes are all fine.
3. **Commit each change** with `git commit` and a short plain-language message that says what
   changed and why, for a reader who was not in the conversation.
4. **Push after committing** with `git push`.

Never force-push, rewrite history, or commit with `--no-verify`.

## What not to change

These are the venture's bookkeeping, and a wrong edit to them is hard to undo:

- **IDs**: `A-<n>`, `DEC-<n>`, `T-<n>`, `KC-<n>`, and the venture identifier. Never renumber,
  rename, reuse, or delete one. A changed meaning is a new entry, which the operator adds.
- **Statuses**: every `**Status:**` line, the venture's and each register entry's.
- **Gate records**: everything under `## Gate log` in `brief.md`.
- **This protocol and `CLAUDE.md`**: every agent opened in this folder reads them as instructions.

To change any of these, propose it instead: tell the person you are working with, and add a short
file under `proposals/`, named with today's date and a topic, saying what should change and
why. Commit and push it like any other edit. The venture's operator decides and makes the change.

## When the network is blocked

Some sessions cannot reach the remote (a Cowork network allowlist, for example), so `git pull` or
`git push` fails.

- **Pull blocked**: say so before editing. The copy here may be behind, so edit only if the person
  accepts that, and keep the change small.
- **Push blocked**: keep the commit. Tell the person the change is saved in this folder but not
  shared, and that it reaches everyone once someone with access pushes it. Never retry with force.
- **No remote at all** (`git remote` prints nothing): the repository lives only on this machine.
  Skip the pull and the push; nothing is behind and nothing is shared, by design.

## When someone else pushed first

If `git push` is rejected because the remote has changes you do not have, run
`git pull --no-rebase`, then push again. If the pull stops on a conflict:

- In a bundle file, keep both sides' wording. If the conflict touches an ID, a `**Status:**`
  line or the gate log, stop and tell the person instead of choosing.
- In `exports/`, take either side (`git checkout --theirs exports/`): the pages are regenerated
  from the bundle by the next commit in a clone with planwright's venture hook wired.

Then `git add` the resolved files, commit, and push. Never force.

## Why this is safe

This protocol is guidance, not a lock. The venture's validator flags a broken structure and a
status that breaks its rules; where the repository has a remote, its CI check also fails on a
removed or renumbered ID, an edited gate record, and a closed venture reopened, once the change has
landed. A status moved to another allowed value can pass every check: git history keeps every
earlier version, and the operator sees the change there.
PROTOCOL
emit sync-protocol.md 644

# CLAUDE.md is the file Claude-based agents read today, so it carries the
# protocol by import: a hedge against Cowork reading some other name. The
# operator's own CLAUDE.md is theirs, so it is never replaced, --force
# included; the import is appended once instead.
import_line='@sync-protocol.md'
claude_md="$target/CLAUDE.md"
if [ -h "$claude_md" ]; then
  printf '%s\n' "inception-scaffold: CLAUDE.md is a symbolic link; not writing through it. Add the line $import_line to the file it names." >&2
elif [ ! -e "$claude_md" ]; then
  cat >"$stage" <<CLAUDEMD
# Working in this venture repository

This folder is a planwright venture. Every session working here follows its sync protocol:

$import_line
CLAUDEMD
  emit CLAUDE.md 644
elif [ ! -f "$claude_md" ]; then
  printf '%s\n' "inception-scaffold: CLAUDE.md is not a regular file; add the line $import_line to it by hand." >&2
elif [ ! -r "$claude_md" ]; then
  # The import is advisory, so a file the scaffold cannot check or extend is
  # said, never fatal: exiting here would leave hygiene-wiring.md unwritten,
  # and add-remote, which deletes it first, could never finish. Appending
  # unread would add the import again on every run.
  printf '%s\n' "inception-scaffold: CLAUDE.md is not readable; add the line $import_line to it by hand." >&2
elif grep -q '^[[:space:]]*@sync-protocol\.md[[:space:]]*$' "$claude_md"; then
  # [[:space:]] takes a CRLF file's trailing CR, so an import already there in
  # another line-ending style is not appended a second time.
  printf 'kept %s\n' CLAUDE.md
else
  last=$(tail -c 1 "$claude_md")
  if {
    [ -z "$last" ] || printf '\n'
    printf '\n%s\n' "$import_line"
  } >>"$claude_md"; then
    printf 'updated %s\n' CLAUDE.md
  else
    printf '%s\n' "inception-scaffold: could not append to CLAUDE.md; add the line $import_line to it by hand." >&2
  fi
fi

# --- hygiene-wiring.md -----------------------------------------------------

# The prose below is markdown, so its backticks are code spans, not command
# substitution — hence the single quotes and the directive.
# shellcheck disable=SC2016
if [ "$rung" = remote ]; then
  rung_line='This venture is on the **remote** rung: it has a git remote, so the CI guard is wired too.'
  rung_ci='- `.github/workflows/venture-guard.yml` — the CI guard. It scans history for secrets and
  runs the bundle validator against the merge base, so a stakeholder edit arriving through the
  GitHub web UI cannot mangle an id, break the structure, or rewrite a recorded gate run. Ordinary
  prose edits pass.

  **One thing to decide.** The workflow ships pinned to action tags and to the default branch of
  planwright, so a venture picks up guard improvements without maintenance. That also means three
  third-party sources can change under you. If this venture wants the stricter posture, pin each
  `uses:` to a full commit SHA and give the planwright checkout an explicit `ref:`; you then own
  moving them.'
else
  rung_line='This venture is on the **local** rung: no remote, so no CI guard. The pre-commit hook is
the whole enforcement surface. Add a remote later and re-run the scaffold to pick up the CI guard.'
  rung_ci='- _No CI guard._ Nothing runs off this machine. Re-run the scaffold after adding a remote.'
fi

cat >"$stage" <<WIRING
# Venture hygiene wiring

Scaffolded by planwright's \`/inception\`. This file records what was wired, what still needs a
human step, and how to get out of the way when you have to.

$rung_line

## One manual step

Git will not run the tracked hooks until the clone is pointed at them. Once per clone:

\`\`\`sh
git config core.hooksPath githooks
\`\`\`

This is clone-global, so one wiring covers every worktree of the clone. Every person who clones
this venture repo runs it once.

## What is wired

- \`githooks/pre-commit\` — three steps on every commit:
  1. **Secret screen** over the staged content. **Blocks.** A credential that reaches a commit is
     in the history forever, so this is the one hard stop.
  2. **Bundle validation.** **Warns.** A bundle is written incrementally, and a hook that refuses
     every half-finished elicitation is a hook you would turn off. Set
     \`PLANWRIGHT_VENTURE_STRICT=1\` to make findings block.
  3. **Export regeneration**, staged into the same commit, so the HTML stakeholders read never
     lags the bundle. **Warns and lets the commit through** if the render fails, or if an export
     cannot be staged — neither may dead-end a commit, and you are told either way, because a
     silent staging failure is how a published export starts drifting from the bundle without
     anyone noticing. Each regenerated export, with the bundle files it comes from, is screened
     for secrets before it is staged, and *that* **blocks**: it is rendered from your working
     tree, so it can carry bundle text step 1 never looked at (an edit you had not staged). The
     page staged is exactly the page screened.
$rung_ci

## The sync protocol

\`sync-protocol.md\` tells anyone editing this repository outside planwright, a Cowork session
or a stakeholder's own agent, how to do it safely: pull first, commit with plain-language
messages, push after, and propose rather than make any change to an ID, a status, or a gate
record. \`CLAUDE.md\` imports it, so a Claude-based agent opening this folder reads it. It is
advice the agent may ignore. The validator flags a broken structure and a status that breaks its
rules; CI on the remote rung also fails on a changed ID or gate record once it has landed; anything
else, such as a status moved to another allowed value, can show only in git history.

## The exports

Two pages, both derived from the bundle and regenerated by every commit that changes it. Never
edit them by hand.

- \`exports/venture.html\` — the dashboard: where the venture stands (gate readiness, blocking
  assumptions, kill criteria, open forks, blockers), then the record behind it: registers, plan,
  discipline and stakeholder tables, sources, and the gate log.
- \`exports/pitch.html\` — the pitch narrative: the problem, the idea, the landscape, what has to
  be true, how it will be tested, and what would stop it, for someone deciding whether to back
  the venture.

To render by hand, run \`<planwright>/scripts/inception-render.sh .\` from the venture root, where
\`<planwright>\` is the copy the hook resolves (see *Where planwright comes from*). With no
\`--mode\` it writes both pages; \`--mode dashboard\` or \`--mode pitch\` writes one.

## Publishing

Publishing a page as an Artifact sends it off this machine, so a first publish is never automatic:
each page's first publish is offered and confirmed. After that, this machine may opt into
auto-republish (off by default), and a refreshed copy then replaces the published page without
asking again. The opt-in is per machine, so every other machine starts at off. The knob and the
publish record live in the clone's git directory (\`.git/planwright-publish.local\`), outside the
work tree: it is this machine's operator's call, and nothing a commit carries can switch it on. Set
it from the venture root with \`<planwright>/scripts/inception-publish.sh auto on .\` (or
\`off\`).

## One thing that looks wrong and is not

After a **partial** commit — \`git commit <path>\` or \`git commit --only <path>\`, where you name
the files instead of staging them — \`git status\` shows the exports as modified. They did make
it into the commit. Git builds a temporary index for a partial commit and restores
your real one afterwards, and the hook's staging of the regenerated exports lives in the temporary
one. The next \`git add\` clears it. Staging your changes first (\`git add\` then \`git commit\`)
avoids it entirely.

## Where planwright comes from

The hook resolves planwright at run time: \`PLANWRIGHT_ROOT\`, then \`CLAUDE_PLUGIN_ROOT\`, then
the plugin cache under \`~/.claude\`. No install path is baked into the tracked hook, because this
repo gets cloned onto machines where that path does not exist. If planwright lives somewhere
unusual on your machine, set it in \`.planwright-local.sh\` (gitignored, machine-local, never
secrets):

\`\`\`sh
PLANWRIGHT_ROOT=/path/to/planwright
\`\`\`

When planwright cannot be resolved at all, the hook says so and lets the commit through. On the
remote rung CI is the backstop; on the local rung there is none, which is the honest cost of a
laptop-only venture.

## Bypass

\`git commit --no-verify\` skips the whole hook. It is the deliberate escape hatch, not the
default: use it when you know what you are committing and the guard is wrong.
WIRING
emit hygiene-wiring.md 644

# --- optional wire step ----------------------------------------------------

if [ "$wire" -eq 1 ]; then
  if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$target" config --local core.hooksPath githooks; then
      echo "wired core.hooksPath=githooks"
    else
      echo "inception-scaffold: could not set core.hooksPath; wire it by hand (see hygiene-wiring.md)" >&2
    fi
  else
    echo "inception-scaffold: --wire needs a git work tree; skipping the wire step" >&2
  fi
fi

printf 'inception-scaffold: %s rung\n' "$rung"
