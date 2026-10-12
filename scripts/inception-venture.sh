#!/bin/sh
# inception-venture.sh — the mechanical half of the /inception skill
# (inception Task 7; REQ-A1.1, REQ-A1.3, REQ-A1.4, REQ-A1.5, REQ-A1.8,
# REQ-A1.9, REQ-B1.7, REQ-H1.1, REQ-H1.2, REQ-H1.3, REQ-H1.5 · D-5, D-19).
#
# The skill holds the conversation; everything that must behave the same on
# every run lives here as small subcommands, each data in, data out:
#
#   id <text>             derive a venture identifier from free text
#   check-id <id>         re-validate an identifier at consumption (REQ-A1.8)
#   root                  resolve ventures_root through the config layers
#   detect                probe the environment and name the ladder rung
#   create [--home local|remote] [--root <dir>] [--owner <o>] <id>
#                         make the venture home and scaffold its guards
#   bundle-init --title <title> <venture-dir>
#                         write the five-file skeleton elicitation fills in
#   mark-phase <venture-dir> <phase>
#                         record a completed elicitation phase (resume point)
#   resume-point <venture-dir>
#                         version-gate the bundle and name the next phase
#   save [--push] [--expert] <venture-dir> <message>
#                         the wrapped save: commit (git rungs), screen, push
#   add-remote [--owner <o>] <venture-dir>
#                         move a local-only venture onto a private remote
#   handoff <venture-dir> the end-of-run state, degradations repeated
#
# Output is `key<TAB>value` lines wherever a caller parses it; `degraded`
# lines name each missing capability in plain words, and the skill repeats
# them at pre-flight and in its handoff (REQ-H1.5).
#
# The ladder (REQ-H1.1, D-5): a git repository (local-only or private remote),
# then a plain folder when git is unavailable, then session-only when the
# filesystem does not outlive the session. Capability degrades; the bundle is
# always written.
#
# Ephemeral detection reads CLAUDE_CODE_REMOTE, which Claude Code documents as
# set to `true` in a cloud session; PLANWRIGHT_INCEPTION_EPHEMERAL=1|0 is the
# operator's override in either direction, for hosts the probe misreads.
#
# Exit: 0 success · 1 refused identifier (check-id, create), a proposed
#   variant (id), a save the venture's guard stopped, or a plain-folder save
#   whose screen flagged a credential (the files are written regardless)
#   · 2 usage or environment error (a broken install, an incomplete bundle
#   included) · 3 the validator refuses to read the bundle (an unsupported or
#   unparseable format-version, an unbalanced code fence; passed through)
#   · 4 a malformed repo-tracked ventures_root · 5 the target already exists,
#   or the venture already has a remote (never overwritten) · 6 the requested home or push is unavailable · 7 the remote
#   step failed.
#
# Environment: PLANWRIGHT_INCEPTION_TODAY (YYYY-MM-DD) pins today's date;
#   the config overrides resolve-config-knob.sh honors apply to `root`.
#
# Portable POSIX sh; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

self_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2

PHASES='seed opportunity disciplines reframe core registers finalize'
PENDING='_Pending: not yet elicited._'
FILES='brief.md disciplines.md assumptions.md decisions.md plan.md'

usage() {
  cat >&2 <<'EOF'
usage: inception-venture.sh id <text>
       inception-venture.sh check-id <id>
       inception-venture.sh root
       inception-venture.sh detect
       inception-venture.sh create [--home local|remote] [--root <dir>] [--owner <owner>] <id>
       inception-venture.sh bundle-init --title <title> <venture-dir>
       inception-venture.sh mark-phase <venture-dir> <phase>
       inception-venture.sh resume-point <venture-dir>
       inception-venture.sh save [--push] [--expert] <venture-dir> <message>
       inception-venture.sh add-remote [--owner <owner>] <venture-dir>
       inception-venture.sh handoff <venture-dir>
EOF
  exit 2
}

die() {
  printf 'inception-venture: %s\n' "$2" >&2
  exit "$1"
}

# The temp file or staging directory a write has in flight, removed on any
# exit so an interrupted write never leaves a stray file the next save's
# `git add -A` would commit.
tmp_path=
cleanup_tmp() {
  if [ -n "$tmp_path" ]; then rm -rf "$tmp_path"; fi
}
trap cleanup_tmp EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

today() {
  td=${PLANWRIGHT_INCEPTION_TODAY:-}
  case $td in
    [0-9][0-9][0-9][0-9]-0[1-9]-[0-3][0-9] | [0-9][0-9][0-9][0-9]-1[0-2]-[0-3][0-9])
      case ${td##*-} in
        0[1-9] | [12][0-9] | 3[01])
          printf '%s\n' "$td"
          return 0
          ;;
      esac
      ;;
  esac
  date +%Y-%m-%d
}

# single_line <text> — true when the text has a non-blank character and no
# control bytes (a newline included), so it can sit on one markdown or commit
# line.
single_line() {
  case $1 in *[![:space:]]*) ;; *) return 1 ;; esac
  [ "$1" = "$(printf '%s' "$1" | tr -d '\000-\037\177')" ]
}

# --- identifiers -----------------------------------------------------------

valid_id() {
  case $1 in
    '' | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}

valid_owner() {
  case $1 in
    '' | -* | *[!A-Za-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 39 ]
}

cmd_id() {
  [ $# -eq 1 ] || usage
  # ASCII ranges on purpose: under LC_ALL=C every non-ASCII byte folds to a
  # separator, so the identifier charset holds whatever the input script.
  # shellcheck disable=SC2018,SC2019
  v=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9' '-' | tr -s '-' \
    | sed 's/^-*//; s/-*$//' | cut -c1-64 | sed 's/-*$//')
  [ -n "$v" ] || die 2 "no identifier can be derived from that name; propose one in lowercase letters, digits, and hyphens"
  if [ "$v" = "$1" ]; then
    printf 'ok\t%s\n' "$v"
    return 0
  fi
  printf 'propose\t%s\n' "$v"
  return 1
}

cmd_check_id() {
  [ $# -eq 1 ] || usage
  valid_id "$1" && return 0
  printf 'inception-venture: invalid venture identifier (want ^[a-z0-9][a-z0-9-]*$, at most 64 characters); refused before any use\n' >&2
  return 1
}

# --- ventures_root ---------------------------------------------------------

resolve_root() {
  [ -n "${HOME:-}" ] || die 2 "HOME is unset; cannot resolve ventures_root"
  default="$HOME/ventures"
  # The literal tilde is the configured form; it is expanded below.
  # shellcheck disable=SC2088
  # The resolver's own exit 5 (broken install) folds into 2: callers read 5 as
  # "the venture path is taken".
  got=$(/bin/sh "$self_dir/resolve-config-knob.sh" --key ventures_root --type path \
    --fallback '~/ventures' --explain) || {
    rr_rc=$?
    [ "$rr_rc" -eq 4 ] && exit 4
    exit 2
  }
  layer=${got%%"	"*}
  value=${got#*"	"}
  # shellcheck disable=SC2088
  case $value in
    '~') r=$HOME ;;
    '~/'*) r=$HOME/${value#'~/'} ;;
    /*) r=$value ;;
    *)
      case $layer in
        repo-tracked) die 4 "ventures_root in the repo-tracked config must be an absolute or ~/ path" ;;
        core) die 2 "the core ventures_root default is malformed (broken install)" ;;
      esac
      printf 'inception-venture: warning: ventures_root from the %s layer is not an absolute or ~/ path; using %s\n' "$layer" "$default" >&2
      r=$default
      ;;
  esac
  while [ "$r" != / ] && [ "$r" != "${r%/}" ]; do r=${r%/}; done
  printf '%s\n' "$r"
}

cmd_root() {
  [ $# -eq 0 ] || usage
  resolve_root
}

# --- capability detection --------------------------------------------------

# probe — set has_git, ephemeral, remote_state, remote_reason, local_state.
probe() {
  has_git=no
  git --version >/dev/null 2>&1 && has_git=yes

  case ${PLANWRIGHT_INCEPTION_EPHEMERAL:-} in
    1) ephemeral=yes ;;
    0) ephemeral=no ;;
    *)
      ephemeral=no
      [ "${CLAUDE_CODE_REMOTE:-}" = true ] && ephemeral=yes
      ;;
  esac

  remote_state=available
  remote_reason=
  if [ "$has_git" = no ]; then
    remote_state=unavailable
    remote_reason='git is unavailable'
  elif ! command -v gh >/dev/null 2>&1; then
    remote_state=unavailable
    remote_reason='the GitHub CLI (gh) is not installed'
  elif ! gh auth status >/dev/null 2>&1; then
    remote_state=unavailable
    remote_reason='the GitHub CLI (gh) is not signed in'
  fi

  if [ "$ephemeral" = yes ]; then
    local_state=session-only
  elif [ "$has_git" = no ]; then
    local_state=plain
  else
    local_state=durable
  fi
}

# ladder_rung <git-usable yes|no> <home> — the venture's rung on the ladder:
# git, else a plain folder, and session-only for a local home on an ephemeral
# host. Reads the probe's ephemeral flag.
ladder_rung() {
  if [ "$2" = local ] && [ "$ephemeral" = yes ]; then
    printf 'session\n'
  elif [ "$1" = yes ]; then
    printf 'git\n'
  else
    printf 'plain\n'
  fi
}

# print_degraded [<home> <rung>] — one `degraded` line per missing capability
# after a probe. With no arguments it names the environment's; given a
# venture's home and rung it names only what that venture lacks, so a remote
# venture is not warned about the arms it did not take.
print_degraded() {
  pd_home=${1:-}
  pd_rung=${2:-}
  if [ "$has_git" = no ]; then
    printf 'degraded\t%s\n' 'git unavailable: the venture is kept as a plain folder, with no history, no hygiene hooks, and no remote home'
  elif [ "$pd_rung" = plain ]; then
    printf 'degraded\t%s\n' 'this venture is a plain folder, with no history, no hygiene hooks, and no remote home'
  fi
  if [ "$ephemeral" = yes ] && [ "$pd_home" != remote ]; then
    printf 'degraded\t%s\n' 'ephemeral environment: a local-only venture does not persist past this session; choose the private-remote home to keep it'
  fi
  if [ "$has_git" = yes ] && [ "$remote_state" = unavailable ] \
    && [ "$pd_home" != remote ] && [ "$pd_rung" != plain ]; then
    printf 'degraded\tthe private-remote home is unavailable (%s)\n' "$remote_reason"
  fi
}

cmd_detect() {
  [ $# -eq 0 ] || usage
  probe
  case $has_git in
    yes) printf 'git\tpresent\n' ;;
    *) printf 'git\tabsent\n' ;;
  esac
  printf 'ephemeral\t%s\n' "$ephemeral"
  printf 'remote\t%s\n' "$remote_state"
  printf 'local\t%s\n' "$local_state"
  print_degraded
}

# --- creation --------------------------------------------------------------

# make_private_remote <dir> <name> — create the private repository and wire it
# as origin. Nothing is pushed here; the first push is a save the operator
# asked for.
make_private_remote() {
  gh repo create "$2" --private --source "$1" --remote origin >/dev/null 2>&1
}

cmd_create() {
  home=local
  root=
  owner=
  id=
  while [ $# -gt 0 ]; do
    case $1 in
      --home)
        [ $# -ge 2 ] || usage
        home=$2
        shift 2
        ;;
      --root)
        [ $# -ge 2 ] || usage
        root=$2
        shift 2
        ;;
      --owner)
        [ $# -ge 2 ] || usage
        owner=$2
        shift 2
        ;;
      -*) usage ;;
      *)
        [ -z "$id" ] || usage
        id=$1
        shift
        ;;
    esac
  done
  case $home in local | remote) ;; *) usage ;; esac
  cmd_check_id "$id" || exit 1
  if [ -n "$owner" ]; then
    valid_owner "$owner" || die 2 "invalid GitHub owner name"
  fi
  [ -n "$root" ] || root=$(resolve_root) || exit $?

  target=$root/$id
  if [ -e "$target" ] || [ -L "$target" ]; then
    die 5 "a directory already exists at the venture path; adopt it or choose another name (nothing was changed)"
  fi

  probe
  if [ "$home" = remote ] && [ "$remote_state" != available ]; then
    die 6 "the private-remote home is unavailable ($remote_reason); nothing was created"
  fi

  rung=$(ladder_rung "$has_git" "$home")

  mkdir -p "$root" || die 2 "cannot create the ventures root"
  # not-a-lock: plain mkdir so a directory that appeared since the check above is refused, never adopted.
  mkdir "$target" 2>/dev/null || die 5 "a directory already exists at the venture path; nothing was changed"

  if [ "$has_git" = yes ]; then
    git init -q "$target" || die 2 "git init failed"
    git -C "$target" symbolic-ref HEAD refs/heads/main || die 2 "cannot name the main branch"
    if [ "$home" = remote ]; then
      if ! make_private_remote "$target" "${owner:+$owner/}$id"; then
        # Only this command's own, still-empty repository is removed.
        rm -rf "$target"
        die 7 "the private repository could not be created; nothing was kept"
      fi
      scaffold_rung=remote
    else
      scaffold_rung=local
    fi
    /bin/sh "$self_dir/inception-scaffold.sh" --rung "$scaffold_rung" --wire "$target" >/dev/null \
      || die 2 "the hygiene scaffold failed"
  fi

  printf 'venture\t%s\n' "$target"
  printf 'home\t%s\n' "$home"
  printf 'rung\t%s\n' "$rung"
  print_degraded "$home" "$rung"
}

# --- the bundle skeleton ---------------------------------------------------

require_dir() {
  [ -d "$1" ] || die 2 "not a directory: the venture path"
}

cmd_bundle_init() {
  title=
  dir=
  while [ $# -gt 0 ]; do
    case $1 in
      --title)
        [ $# -ge 2 ] || usage
        title=$2
        shift 2
        ;;
      -*) usage ;;
      *)
        [ -z "$dir" ] || usage
        dir=$1
        shift
        ;;
    esac
  done
  [ -n "$dir" ] || usage
  single_line "$title" || die 2 "--title must be one non-empty line"
  require_dir "$dir"
  for f in $FILES; do
    if [ -e "$dir/$f" ] || [ -L "$dir/$f" ]; then
      die 5 "a bundle file already exists here; nothing was written"
    fi
  done
  d=$(today)
  # All five are written to a staging directory and moved in only once every
  # write succeeded, so a failed write never leaves a partial bundle that the
  # no-overwrite check above then blocks for good.
  tmp_path=$(mktemp -d "$dir/.inception-venture.XXXXXX") || die 2 "cannot write in the venture directory"

  stage_file brief.md <<EOF
# $title — Brief

**Status:** Exploring
**Last reviewed:** $d
**Format-version:** 1.0

## Opportunity

- **Framing:** $PENDING
- **Who hurts:** $PENDING
- **No-gos & sketch:** $PENDING
- **Chain:** $PENDING

## Success metric

$PENDING

## Appetite

$PENDING

## Kill criteria

$PENDING

## Existing alternatives

$PENDING

## Business viability

$PENDING

## Strategy fit

$PENDING

## Sources

$PENDING

## Gate log

No gate has run yet.

## Changelog

- $d — Venture opened at Exploring.
EOF

  stage_file disciplines.md <<EOF
# $title — Disciplines

**Status:** Exploring
**Last reviewed:** $d
**Format-version:** 1.0

## Discipline map

| Discipline | Touches | Undecided decisions |
| --- | --- | --- |

$PENDING

## Staffing table

| Discipline | Staffing | Card / person |
| --- | --- | --- |

$PENDING

## Stakeholder map

| Decision area | Decides | Aligned | Informed |
| --- | --- | --- | --- |

$PENDING
EOF

  for pair in 'assumptions.md:Assumptions' 'decisions.md:Decisions' 'plan.md:Plan'; do
    stage_file "${pair%%:*}" <<EOF
# $title — ${pair#*:}

**Status:** Exploring
**Last reviewed:** $d
**Format-version:** 1.0

$PENDING
EOF
  done

  for f in $FILES; do
    mv "$tmp_path/$f" "$dir/$f" || die 2 "cannot write a bundle file"
  done
}

# stage_file <name> — stdin to <name> in the bundle-init staging directory,
# owner-only as the files have always been written.
stage_file() {
  (umask 077 && cat >"$tmp_path/$1") || die 2 "cannot write a bundle file"
}

# --- elicitation phases and the resume point -------------------------------

phase_index() {
  i=0
  for p in $PHASES; do
    i=$((i + 1))
    [ "$p" = "$1" ] && {
      printf '%s\n' "$i"
      return 0
    }
  done
  return 1
}

# missing_file <venture-dir> — print the first bundle file absent from the
# directory; false when all five are present. The validator refuses a missing
# file with the same exit 3 as an unsupported format-version, so this is
# checked first to keep "incomplete" apart from "unreadable".
missing_file() {
  for mf in $FILES; do
    [ -f "$1/$mf" ] || {
      printf '%s\n' "$mf"
      return 0
    }
  done
  return 1
}

version_gate() {
  if vg_missing=$(missing_file "$1"); then
    die 2 "the bundle is incomplete: $vg_missing is missing from the venture directory"
  fi
  vg_out=$(/bin/sh "$self_dir/inception-validate.sh" --version-check "$1" 2>&1)
  vg_rc=$?
  [ "$vg_rc" -eq 0 ] && return 0
  printf '%s\n' "$vg_out" >&2
  [ "$vg_rc" -eq 3 ] && exit 3
  exit 2
}

cmd_mark_phase() {
  [ $# -eq 2 ] || usage
  require_dir "$1"
  phase_index "$2" >/dev/null || die 2 "unknown phase (one of: $PHASES)"
  [ -f "$1/brief.md" ] || die 2 "no brief.md in the venture directory"
  version_gate "$1"
  line="- $(today) — Elicitation: $2 phase complete."
  tmp_path=$(mktemp "$1/.inception-venture.XXXXXX") || die 2 "cannot write in the venture directory"
  awk -v line="$line" '
    { buf[NR] = $0 }
    /^## Changelog[[:space:]]*$/ { inlog = 1; last = NR; next }
    inlog && /^## / { inlog = 0 }
    inlog && NF { last = NR }
    END {
      if (!last) exit 3
      for (i = 1; i <= NR; i++) {
        print buf[i]
        if (i == last) print line
      }
    }
  ' "$1/brief.md" >"$tmp_path" || die 2 "brief.md has no Changelog section to record the phase in"
  mv "$tmp_path" "$1/brief.md" || die 2 "cannot update brief.md"
  tmp_path=
}

cmd_resume_point() {
  [ $# -eq 1 ] || usage
  require_dir "$1"
  version_gate "$1"
  resume_state "$1"
}

# resume_state <venture-dir> — the done/next/pending lines, for a bundle the
# caller has already gated.
resume_state() {
  best=0
  phases_seen=$(sed -n 's/^- [0-9-]* — Elicitation: \([a-z]*\) phase complete\.$/\1/p' "$1/brief.md")
  while IFS= read -r p; do
    n=$(phase_index "$p") || continue
    [ "$n" -gt "$best" ] && best=$n
  done <<EOF_PHASES
$phases_seen
EOF_PHASES
  done_p=none
  next_p=complete
  i=0
  for p in $PHASES; do
    i=$((i + 1))
    [ "$i" -eq "$best" ] && done_p=$p
    if [ "$i" -eq $((best + 1)) ]; then next_p=$p; fi
  done
  pending=0
  for f in $FILES; do
    [ -f "$1/$f" ] || continue
    c=$(grep -cF -- "$PENDING" "$1/$f")
    pending=$((pending + c))
  done
  printf 'done\t%s\n' "$done_p"
  printf 'next\t%s\n' "$next_p"
  printf 'pending\t%s\n' "$pending"
}

# --- saving ----------------------------------------------------------------

is_repo_root() {
  [ -d "$1/.git" ] || [ -f "$1/.git" ]
}

cmd_save() {
  push=0
  expert=0
  dir=
  msg=
  while [ $# -gt 0 ]; do
    case $1 in
      --push)
        push=1
        shift
        ;;
      --expert)
        expert=1
        shift
        ;;
      -*) usage ;;
      *)
        if [ -z "$dir" ]; then
          dir=$1
        elif [ -z "$msg" ]; then
          msg=$1
        else
          usage
        fi
        shift
        ;;
    esac
  done
  [ -n "$dir" ] || usage
  single_line "$msg" || die 2 "the save message must be one non-empty line"
  require_dir "$dir"

  if ! is_repo_root "$dir" || ! git --version >/dev/null 2>&1; then
    [ "$push" -eq 1 ] && die 6 "this venture has no remote; nothing leaves this machine"
    save_plain "$dir"
    return
  fi

  if [ "$push" -eq 1 ] && ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    die 6 "this venture is local-only; nothing leaves this machine (add a private remote first)"
  fi

  git -C "$dir" add -A || die 2 "cannot stage the venture's changes"
  if git -C "$dir" diff --cached --quiet; then
    printf 'Nothing new to save.\n'
  else
    # A missing identity fails the commit too; told apart here so it is never
    # blamed on the guard.
    if ! git -C "$dir" var GIT_AUTHOR_IDENT >/dev/null 2>&1 \
      || ! git -C "$dir" var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
      git -C "$dir" reset -q
      die 2 "not saved: no name and email are set for saving on this machine (git config user.name and user.email); set them and save again"
    fi
    c_out=$(git -C "$dir" commit -q -m "$msg" 2>&1)
    c_rc=$?
    if [ "$c_rc" -ne 0 ]; then
      git -C "$dir" reset -q
      [ "$expert" -eq 1 ] && printf '%s\n' "$c_out" | tr -d '\000-\010\013-\037\177' >&2
      case $c_out in
        *credential*)
          die 1 "not saved: the changes look like they carry a credential (a password, key, or token); remove it and save again"
          ;;
      esac
      die 1 "not saved: the venture's guard stopped the save (run with --expert to see why)"
    fi
    if [ "$expert" -eq 1 ]; then
      git -C "$dir" log -1 --format='%h %s' | tr -d '\000-\010\013-\037\177'
    else
      printf 'Saved: %s\n' "$msg"
    fi
  fi

  if [ "$push" -eq 1 ]; then
    git -C "$dir" rev-parse -q --verify HEAD >/dev/null \
      || die 6 "nothing has been saved yet, so there is nothing to share"
    if ! git -C "$dir" push -q -u origin HEAD >/dev/null 2>&1; then
      die 7 "saved here, but not shared: the push to the private repository failed (check the connection, then save again)"
    fi
    if [ "$expert" -eq 1 ]; then
      printf 'pushed to origin\n'
    else
      printf 'Shared to your private repository.\n'
    fi
  fi
}

save_plain() {
  sp_rc=0
  /bin/sh "$self_dir/inception-secret-screen.sh" -- "$1" >/dev/null 2>&1 || sp_rc=$?
  if [ "$sp_rc" -eq 1 ]; then
    die 1 "warning: the venture's files look like they carry a credential (a password, key, or token); remove it"
  elif [ "$sp_rc" -ne 0 ]; then
    printf 'inception-venture: warning: the secret screen could not run (exit %s)\n' "$sp_rc" >&2
  fi
  if ! /bin/sh "$self_dir/inception-render.sh" "$1" >/dev/null 2>&1; then
    printf 'inception-venture: warning: the export was not regenerated; it may lag the bundle\n' >&2
  fi
  printf 'Saved (plain folder: no history is kept because git is unavailable).\n'
}

# --- remote later (REQ-H1.3) ------------------------------------------------

cmd_add_remote() {
  owner=
  dir=
  while [ $# -gt 0 ]; do
    case $1 in
      --owner)
        [ $# -ge 2 ] || usage
        owner=$2
        shift 2
        ;;
      -*) usage ;;
      *)
        [ -z "$dir" ] || usage
        dir=$1
        shift
        ;;
    esac
  done
  [ -n "$dir" ] || usage
  require_dir "$dir"
  if [ -n "$owner" ]; then
    valid_owner "$owner" || die 2 "invalid GitHub owner name"
  fi
  dir=$(cd "$dir" && pwd -P) || exit 2
  name=$(basename "$dir")
  cmd_check_id "$name" || exit 1
  is_repo_root "$dir" || die 6 "this venture has no git history to move; a plain folder cannot gain a remote"
  git -C "$dir" remote get-url origin >/dev/null 2>&1 && die 5 "this venture already has a remote"
  probe
  [ "$remote_state" = available ] || die 6 "the private-remote home is unavailable ($remote_reason)"
  make_private_remote "$dir" "${owner:+$owner/}$name" || die 7 "the private repository could not be created; the venture stays local-only"
  /bin/sh "$self_dir/inception-scaffold.sh" --rung remote "$dir" >/dev/null \
    || die 2 "the remote-rung scaffold failed"
  printf 'venture\t%s\n' "$dir"
  printf 'home\tremote\n'
}

# --- handoff ---------------------------------------------------------------

cmd_handoff() {
  [ $# -eq 1 ] || usage
  require_dir "$1"
  probe
  home=local
  git_usable=no
  if is_repo_root "$1" && [ "$has_git" = yes ]; then
    git_usable=yes
    git -C "$1" remote get-url origin >/dev/null 2>&1 && home=remote
  elif [ -f "$1/.git/config" ] && grep -q '^\[remote "origin"\]' "$1/.git/config"; then
    # Without git the home is read from the repository's own config, so a
    # remote venture is not warned to choose the home it already has.
    home=remote
  fi
  rung=$(ladder_rung "$git_usable" "$home")

  v_rc=0
  if missing_file "$1" >/dev/null; then
    v_rc=incomplete
  else
    /bin/sh "$self_dir/inception-validate.sh" "$1" >/dev/null 2>&1 || v_rc=$?
  fi
  case $v_rc in
    incomplete) bundle=incomplete ;;
    0) bundle=clean ;;
    1) bundle=findings ;;
    3) bundle=refused ;;
    *) bundle=unchecked ;;
  esac
  next=unknown
  if [ "$bundle" = clean ] || [ "$bundle" = findings ]; then
    rp=$(resume_state "$1" 2>/dev/null) || rp=
    next=$(printf '%s\n' "$rp" | sed -n 's/^next	//p')
    p=$(printf '%s\n' "$rp" | sed -n 's/^pending	//p')
    [ "$bundle" = clean ] && [ "${p:-0}" -gt 0 ] && bundle=pending
  fi

  printf 'venture\t%s\n' "$1"
  printf 'home\t%s\n' "$home"
  printf 'rung\t%s\n' "$rung"
  printf 'bundle\t%s\n' "$bundle"
  printf 'next\t%s\n' "${next:-unknown}"
  print_degraded "$home" "$rung"
}

# --- dispatch --------------------------------------------------------------

[ $# -ge 1 ] || usage
sub=$1
shift
case $sub in
  id) cmd_id "$@" ;;
  check-id) cmd_check_id "$@" ;;
  root) cmd_root "$@" ;;
  detect) cmd_detect "$@" ;;
  create) cmd_create "$@" ;;
  bundle-init) cmd_bundle_init "$@" ;;
  mark-phase) cmd_mark_phase "$@" ;;
  resume-point) cmd_resume_point "$@" ;;
  save) cmd_save "$@" ;;
  add-remote) cmd_add_remote "$@" ;;
  handoff) cmd_handoff "$@" ;;
  *) usage ;;
esac
