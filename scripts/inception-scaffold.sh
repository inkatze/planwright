#!/bin/sh
# inception-scaffold.sh — the venture repo hygiene scaffold (inception Task 2;
# REQ-A1.9, REQ-G1.1, REQ-G1.5 · D-9, D-12).
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
# The emitted hook resolves planwright at RUN time (PLANWRIGHT_ROOT, then
# CLAUDE_PLUGIN_ROOT, then the machine-local .planwright-local.sh, then the
# plugin cache). No install path is baked into the tracked file: a venture repo
# is cloned onto other machines, and a hard-coded path would break on all of
# them. When planwright cannot be resolved, the hook warns loudly and lets the
# commit through — on the remote rung CI is the backstop.
#
# Usage:
#   inception-scaffold.sh [--rung local|remote] [--force] [--wire] <venture-dir>
#
# Output: one `wrote <path>` or `kept <path>` line per scaffold file, then a
#   one-line rung summary.
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
  echo "inception-scaffold: not a directory: $target" >&2
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
#   3. Export regeneration, staged into this same commit so the published HTML
#      never lags the bundle. Warns and lets the commit through when the render
#      or the staging fails (REQ-A1.9): neither may dead-end a commit, and
#      neither may fail in silence, or the export drifts unnoticed. The
#      export is screened before it is staged, though, and that screen blocks:
#      it is rendered from the working tree, so it can carry bundle text step 1
#      never saw.
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
pw=
for cand in "${PLANWRIGHT_ROOT:-}" "${CLAUDE_PLUGIN_ROOT:-}" \
  "$HOME/.claude/planwright" $HOME/.claude/plugins/cache/planwright/planwright/*; do
  if [ -n "$cand" ] && [ -r "$cand/scripts/inception-validate.sh" ]; then
    pw=$cand
    break
  fi
done

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

if /bin/sh "$pw/scripts/inception-render.sh" "$top" >/dev/null 2>&1; then
  # The export is rendered from the WORKING TREE, so it can carry bundle text
  # the step-1 screen never saw — an edit that is not staged still reaches the
  # HTML. Screen it BEFORE staging it, or step 3 quietly walks around the hard
  # stop in step 1 and commits the credential itself.
  src=0
  /bin/sh "$pw/scripts/inception-secret-screen.sh" -- "$top/exports/venture.html" || src=$?
  # 1 and 2 both block, but they are different facts and get different words:
  # saying "carries a credential" when the screen could not run sends the
  # operator hunting through their bundle for something that is not there.
  if [ "$src" -eq 1 ]; then
    echo "venture pre-commit: the regenerated export looks like it carries a credential; commit refused." >&2
    echo "venture pre-commit: it came from the bundle in your working tree — fix it there, then commit." >&2
    exit 1
  elif [ "$src" -ne 0 ]; then
    echo "venture pre-commit: the secret screen could not check the regenerated export (exit $src); commit refused." >&2
    echo "venture pre-commit: this is an environment problem, not a finding — see the output above." >&2
    exit 1
  fi
  # Staging failure warns, like a failed render: step 3 never dead-ends a commit.
  # It must not be SILENT, though. The contract this step exists to keep is that
  # the export rides the same commit, and a swallowed `git add` (an ignored
  # exports/, a locked index) breaks that contract while the commit still reads
  # as clean. git's own message goes to stderr unredirected, so the reason is
  # visible without this hook re-echoing repo-controlled text.
  if ! git add "$top/exports/venture.html"; then
    echo "venture pre-commit: the regenerated export could not be staged, so this commit carries a stale or absent export." >&2
    echo "venture pre-commit: committing anyway — see git's message above." >&2
  fi
else
  echo "venture pre-commit: the export was not regenerated; it may now lag the bundle." >&2
  echo "venture pre-commit: committing anyway — a broken render never blocks a commit." >&2
fi

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
     lags the bundle. **Warns and lets the commit through** if the render fails, or if the export
     cannot be staged — neither may dead-end a commit, and you are told either way, because a
     silent staging failure is how a published export starts drifting from the bundle without
     anyone noticing. The regenerated export is screened for secrets before it is
     staged, and *that* **blocks**: it is rendered from your working tree, so it can carry bundle
     text step 1 never looked at (an edit you had not staged).
$rung_ci

## One thing that looks wrong and is not

After a **partial** commit — \`git commit <path>\` or \`git commit --only <path>\`, where you name
the files instead of staging them — \`git status\` shows \`exports/venture.html\` as modified. The
export did make it into the commit. Git builds a temporary index for a partial commit and restores
your real one afterwards, and the hook's staging of the regenerated export lives in the temporary
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
