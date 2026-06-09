#!/usr/bin/env bash
# Bootstrap a fresh git worktree when Claude Code starts in one.
# Wired from ~/.claude/settings.json as a SessionStart hook.
#
# Behavior (runs once per worktree; marker at <gitdir>/claude-bootstrap-done,
# where <gitdir> is the per-worktree gitdir resolved via `git rev-parse --git-dir`):
#   1. Exit quietly if not a git worktree or already bootstrapped. Primary
#      checkouts (where .git is a directory) are intentionally skipped.
#   2. Synchronously: `mise trust` the worktree so .mise.toml / .tool-versions
#      are accepted. This is fast and fixes the first-use friction.
#   3. In the background: run a best-effort dependency install based on
#      detected lockfile+project-file pairs (npm/pnpm/yarn, bundler, mix,
#      cargo, go mod, uv, poetry). Both files must sit at $cwd; a stray
#      root-level lockfile in a monorepo (e.g. frontend/-only project)
#      will NOT trigger an install. Logs go to
#      ~/.claude/cache/worktree-bootstrap.log.
#      A desktop notification fires when the install finishes.
#   4. If the repo ships an executable .claude/worktree-bootstrap script,
#      invoke it after the language installers so projects can layer on
#      additional steps (codegen, DB setup, etc.).
#
# Marker state machine (file: <gitdir>/claude-bootstrap-done):
#   - Absent         → run bootstrap.
#   - Empty          → bootstrap in progress (or crashed mid-run).
#                      If mtime < 30 min old, assume in-progress and skip.
#                      If mtime >= 30 min old, assume stale and retake.
#   - "ok <ts>"      → previous run succeeded. Skip.
#
# To force a re-run: rm "$(git rev-parse --git-dir)/claude-bootstrap-done"
# (the marker lives in the per-worktree gitdir, not in the worktree root,
# because .git is a pointer file in a worktree).

set -u

cwd="${CLAUDE_PROJECT_DIR:-$PWD}"

# Only interested in git worktrees. In a worktree, .git is a *file* pointing
# at the per-worktree gitdir; in the primary checkout it's a directory.
# Note: submodules also use a `.git` pointer file, so the file check alone
# is ambiguous. The gitdir vs git-common-dir comparison below is the real
# worktree predicate.
[ -f "$cwd/.git" ] || exit 0

# Resolve the real per-worktree gitdir (the .git file is a pointer).
gitdir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
[ -n "$gitdir" ] || exit 0
# In a linked worktree, --git-dir points at <main>/.git/worktrees/<name> while
# --git-common-dir points at <main>/.git (they differ). In a primary checkout
# and in submodules, the two paths resolve to the same directory. Bail if
# they match so submodules aren't mistaken for worktrees.
common_dir=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
[ -n "$common_dir" ] || exit 0
[ "$gitdir" != "$common_dir" ] || exit 0
# Make absolute so a later `cd` in the background subshell doesn't break it.
case "$gitdir" in
    /*) ;;
    *) gitdir="$cwd/$gitdir" ;;
esac

marker="$gitdir/claude-bootstrap-done"

# State check: skip if a previous run succeeded, or if another session is
# currently bootstrapping (empty marker, recent mtime). Reclaim a stale
# empty marker older than 30 min (longer than any realistic installer run).
if [ -f "$marker" ]; then
    if grep -q '^ok' "$marker" 2>/dev/null; then
        exit 0
    fi
    if [ -n "$(find "$marker" -mmin -30 -print 2>/dev/null)" ]; then
        exit 0
    fi
    rm -f "$marker"
fi

# Atomic claim via noclobber: `set -C` makes `>` fail if the target exists,
# so two concurrent SessionStart hooks can't both pass through here. Only
# the winner proceeds to the installers below. The empty marker signals
# "in progress" until the background subshell overwrites it with "ok" or
# removes it on failure.
if ! ( set -C; : > "$marker" ) 2>/dev/null; then
    exit 0
fi

log_dir="$HOME/.claude/cache"
log_file="$log_dir/worktree-bootstrap.log"
mkdir -p "$log_dir"

# Truncate log if it has grown past ~256KB. Cheap unbounded-growth guard.
if [ -f "$log_file" ]; then
    log_size=$(wc -c <"$log_file" 2>/dev/null | tr -d '[:space:]')
    [ -n "$log_size" ] && [ "$log_size" -gt 262144 ] && : > "$log_file"
fi

ts() { date '+%Y-%m-%dT%H:%M:%S'; }
log() { printf '[%s] %s\n' "$(ts)" "$*" >>"$log_file"; }

log "bootstrap start: $cwd"

# Step 1: trust mise synchronously so subsequent tool invocations work.
# mise_status: "ok" if trust succeeded, "failed" if it ran but errored, or
# empty if no mise config is present / mise isn't installed. The summary
# below uses this so it doesn't falsely claim trust on a failure.
mise_status=""
if [ -f "$cwd/.mise.toml" ] || [ -f "$cwd/mise.toml" ] || [ -f "$cwd/.tool-versions" ]; then
    if command -v mise >/dev/null 2>&1; then
        if mise trust "$cwd" >>"$log_file" 2>&1; then
            log "mise trusted"
            mise_status="ok"
        else
            log "mise trust failed (continuing)"
            mise_status="failed"
        fi
    fi
fi

# Detect package managers once. Same list drives both the background
# installer and the additionalContext summary, so adding a new language is
# a single-site change. Node package managers are mutually exclusive:
# precedence npm > pnpm > yarn.
detected_names=()
installer_cmds=()

add_installer() {
    detected_names+=("$1")
    installer_cmds+=("$2")
}

has_npm=0
has_pnpm=0
# Each installer requires BOTH the lockfile and the matching project file at $cwd.
# Lockfile alone is insufficient: e.g. paycalc-services commits a stub
# package-lock.json at the root while package.json only lives under frontend/,
# so a root-only `npm ci` would always fail with ENOENT. Same hazard applies
# to any repo that commits a lockfile without its project file at the same
# level. mix.exs and go.mod are themselves the project file, so no pairing.
# uv accepts either pyproject.toml OR uv.toml as the project file (uv.toml
# is uv's standalone alternative when there's no Python packaging metadata).
[ -f "$cwd/package.json" ] && [ -f "$cwd/package-lock.json" ] && { has_npm=1; add_installer "npm" "npm ci"; }
[ -f "$cwd/package.json" ] && [ -f "$cwd/pnpm-lock.yaml" ] && [ $has_npm -eq 0 ] && { has_pnpm=1; add_installer "pnpm" "pnpm install --frozen-lockfile"; }
[ -f "$cwd/package.json" ] && [ -f "$cwd/yarn.lock" ] && [ $has_npm -eq 0 ] && [ $has_pnpm -eq 0 ] && add_installer "yarn" "yarn install --frozen-lockfile"
[ -f "$cwd/Gemfile" ] && [ -f "$cwd/Gemfile.lock" ] && add_installer "bundler" "bundle install"
[ -f "$cwd/mix.exs" ] && add_installer "mix" "mix deps.get"
[ -f "$cwd/go.mod" ] && add_installer "go" "go mod download"
[ -f "$cwd/Cargo.toml" ] && [ -f "$cwd/Cargo.lock" ] && add_installer "cargo" "cargo fetch"
{ [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/uv.toml" ]; } && [ -f "$cwd/uv.lock" ] && add_installer "uv" "uv sync"
[ -f "$cwd/pyproject.toml" ] && [ -f "$cwd/poetry.lock" ] && add_installer "poetry" "poetry install --no-root"

has_repo_hook=0
[ -x "$cwd/.claude/worktree-bootstrap" ] && has_repo_hook=1

# Step 2: background dependency install. The subshell cd's to $cwd once, so
# the fish children inherit that working directory — no inner cd inside
# `fish -c`, which also avoids quoting pitfalls if $cwd contains odd chars.
(
    cd "$cwd" || { rm -f "$marker"; exit 0; }
    n=${#installer_cmds[@]}
    succeeded=1

    for ((i=0; i<n; i++)); do
        cmd="${installer_cmds[$i]}"
        log "run: $cmd"
        if fish -c "$cmd" >>"$log_file" 2>&1; then
            log "ok: $cmd"
        else
            log "fail: $cmd"
            succeeded=0
        fi
    done

    if [ $has_repo_hook -eq 1 ]; then
        log "run: .claude/worktree-bootstrap"
        if fish -c "./.claude/worktree-bootstrap" >>"$log_file" 2>&1; then
            log "ok: .claude/worktree-bootstrap"
        else
            log "fail: .claude/worktree-bootstrap"
            succeeded=0
        fi
    fi

    ran_any=0
    [ "$n" -gt 0 ] && ran_any=1
    [ $has_repo_hook -eq 1 ] && ran_any=1

    # Finalize the marker: "ok <ts>" on success (parent wrote empty marker),
    # or remove it on failure so the next session retries.
    if [ $succeeded -eq 1 ]; then
        printf 'ok %s\n' "$(ts)" > "$marker"
    else
        rm -f "$marker"
    fi

    if [ $ran_any -eq 1 ]; then
        if [ $succeeded -eq 1 ]; then
            fish -c "tnotify-send 'Claude worktree' 'Bootstrap complete'" >/dev/null 2>&1 || true
        else
            fish -c "tnotify-send 'Claude worktree' 'Bootstrap had failures (see log)'" >/dev/null 2>&1 || true
        fi
    fi
    log "bootstrap end (ran_any=$ran_any succeeded=$succeeded)"
) >/dev/null 2>&1 &
disown 2>/dev/null || true

# Emit additionalContext so Claude knows this happened. Build the joined
# list with an index-based loop to keep bash-3.2 + `set -u` happy on
# empty arrays.
joined=""
total=${#detected_names[@]}
for ((i=0; i<total; i++)); do
    [ -n "$joined" ] && joined="$joined,"
    joined="$joined${detected_names[$i]}"
done
if [ $has_repo_hook -eq 1 ]; then
    [ -n "$joined" ] && joined="$joined,"
    joined="${joined}repo-bootstrap"
fi

case "$mise_status" in
    ok)     mise_phrase="Trusted mise config" ;;
    failed) mise_phrase="mise trust failed (see log)" ;;
    *)      mise_phrase="No mise config to trust" ;;
esac

if [ -z "$joined" ]; then
    summary="Fresh git worktree detected. ${mise_phrase}. No package lockfiles or repo bootstrap script found."
else
    summary="Fresh git worktree detected. ${mise_phrase}; running installs in background: ${joined}. Log: ~/.claude/cache/worktree-bootstrap.log. Marker: ${marker} (delete to force re-run)."
fi

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
    "$(printf '%s' "$summary" | jq -Rs .)"

exit 0
