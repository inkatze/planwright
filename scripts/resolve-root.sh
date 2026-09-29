#!/bin/sh
# resolve-root.sh — print one of planwright's roots.
#
# Usage:
#   resolve-root.sh [--explain] install [--all]
#   resolve-root.sh [--explain] repo --primary | --checkout
#   resolve-root.sh [--explain] spec [--primary] [--posture] [--init]
#   (flags may appear anywhere among the arguments)
#
# install   which planwright copy runs: the first surviving arm of the core
#           root chain (PLANWRIGHT_ROOT, CLAUDE_PLUGIN_ROOT, writer-mode,
#           self-location), defined in doctrine/spec-format.md under "The core
#           root chain", which also states which arms are skipped. This script
#           is that definition's only implementation.
#   --all       print every content-bearing arm, one per line in chain order,
#               instead of the first: for a consumer that looks a file up arm
#               by arm, and for a command guard composing its trust set.
# repo      which repository the session belongs to.
#   --primary   the primary working tree of the repository owning the common
#               git directory, so every linked worktree answers with the
#               primary checkout (a submodule answers with its own working
#               tree). PLANWRIGHT_REPO_ROOT, when non-empty, is used instead, but
#               only if it is an absolute path naming a git toplevel; any
#               other value is refused, never ignored.
#   --checkout  the current toplevel; PLANWRIGHT_REPO_ROOT never affects it.
#   Both views discover from the working directory: an inherited GIT_DIR,
#   GIT_WORK_TREE, or command-line config (a git hook exports them) is
#   ignored, and --primary reads core.worktree and core.bare from the
#   repository's own config only, as git does.
# spec      where bundles and the reserved accumulators live: the spec_root
#           option, read through the config overlay as resolved from the
#           primary checkout, else <checkout>/specs. A value is absolute,
#           ~/-prefixed (~ alone is HOME; ~user is refused), or relative to
#           the primary checkout; a ~ value needs an absolute HOME. Empty is
#           unset in its layer. A value that names no directory, escapes the
#           primary checkout when relative, or names a directory other than
#           <primary>/specs without a valid planwright-spec-root.yml marker
#           (a regular file, not a symlink, whose project: matches the
#           identifier grammar and whose layout: is 1) is refused, whichever
#           layer set it, and never falls back to the default. So is a root
#           whose canonical path carries a control byte or tab.
#   (default)   the checkout-local view: a same-repo root inside the primary
#               checkout is re-based onto the current checkout of the same repository.
#               A re-based path the current checkout does not hold (an
#               untracked or gitignored root) is still printed, with a
#               warning on stderr.
#   --primary   the primary view: the configured directory itself, except
#               that a same-repo root inside another linked worktree maps
#               onto the primary checkout's copy at the same relative path
#               (warned about, as above, when the primary does not hold it);
#               the checkout-local view re-bases from that copy.
#   --posture   print only the posture: same-repo when the root's repository
#               shares the work repository's common git directory, separate-
#               repo when it is another repository, plain when it is in none.
#               The default root is always same-repo.
#   --init      write the ignore rules for the local-only entries (in a git
#               repository) and then the marker into the configured
#               directory, which must already exist, and print the root. It
#               never writes through a symlinked marker or .gitignore, never
#               replaces an existing marker, and validates the marker it
#               leaves as any run does. A repo-tracked value is initialized
#               only when it resolves inside the primary checkout. The
#               default root needs no marker and is left untouched.
#   --explain takes precedence over --posture.
#
# --explain prints "<source>\t<path>": the arm (PLANWRIGHT_ROOT,
# CLAUDE_PLUGIN_ROOT, writer-mode, self-location) or the repo source
# (PLANWRIGHT_REPO_ROOT; git-common-dir when --primary derived the tree from
# the common git directory; show-toplevel when git named it directly). For
# spec it prints "<source>\t<path>\t<posture>\t<view>", the source being the
# config layer that set spec_root, or default when it is unset or an empty
# value cancelled it, the view checkout-local or primary. Printed paths are
# canonical (symlinks resolved), except that the default root is printed as
# <checkout>/specs whether or not it exists or is a symlink, and a re-based
# or mapped path is composed, not resolved.
#
# Exit: 0 printed · 1 no install root resolved · 2 usage · 3 no repository
#   root (git missing, not inside a working tree, a bare repository, or a
#   primary that cannot be named from here: a linked worktree of a separate
#   git dir, or a core.worktree that is gone; --primary still answers from
#   inside a repository's git directory, and a separate git dir named .git
#   answers with the directory holding it) · 4 PLANWRIGHT_REPO_ROOT
#   refused · 5 spec_root refused (bad value, missing or invalid marker, a ~
#   value without an absolute HOME, a control byte or tab in the canonical
#   path; --init could not derive a project identifier or write, or was
#   given a repo-tracked value outside the primary checkout) · 6
#   spec_root unreadable (a malformed repo-tracked config file, or a
#   repo-tracked value carrying a control byte; or a broken install).
#   Callers treat 3 as "no repository" and degrade; they never compose a
#   path from an empty root.
#
# POSIX sh with no dependency beyond git and tr, plus, for the spec kind,
# sed, cut, grep, head, tail, mktemp, ln, rm, and the config resolvers: guards
# and hooks exec it through /bin/sh, which is dash on Linux.
set -u
# Pin the C locale so tr's byte ranges below mean bytes.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo the destination into the command
# substitutions that capture directories.
unset CDPATH

# say <message>: one diagnostic line on stderr. Values in it come from the
# environment or from git, so control bytes are stripped and printf is used
# rather than echo, which dash lets expand backslash escapes. C0 and DEL
# only: under the C locale a C1 byte range would also delete UTF-8
# continuation bytes and mangle non-ASCII paths.
say() {
  printf 'planwright: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')" >&2
}

usage() {
  say "usage: resolve-root.sh [--explain] install [--all] | repo --primary|--checkout | spec [--primary] [--posture] [--init]"
  exit 2
}

kind=""
view=""
explain=0
posture_only=0
init=0
all=0
for arg in "$@"; do
  case $arg in
    --explain) explain=1 ;;
    --all) all=1 ;;
    --posture) posture_only=1 ;;
    --init) init=1 ;;
    --primary | --checkout)
      [ -z "$view" ] || usage
      view=${arg#--}
      ;;
    -* | "") usage ;;
    *)
      [ -z "$kind" ] || usage
      kind=$arg
      ;;
  esac
done

# emit <source> <path>: print the result and exit 0; never returns.
emit() {
  if [ "$explain" -eq 1 ]; then
    printf '%s\t%s\n' "$1" "$2"
  else
    printf '%s\n' "$2"
  fi
  exit 0
}

# canon <dir>: the physical path of <dir>. A relative operand gets a ./ so a
# directory named "-" is never cd's previous-directory shorthand.
canon() {
  case $1 in
    /*) cn_dir=$1 ;;
    *) cn_dir=./$1 ;;
  esac
  (cd -P -- "$cn_dir" 2>/dev/null && pwd -P)
}

# skip_warn <arm> <dir> <reason>: warn about a skipped arm, unless --all has
# already found the install root, when the skip changes nothing the caller
# relies on and the warning would only be noise.
skip_warn() {
  [ "$found" -eq 0 ] || return 0
  say "WARNING skipping the $1 root '$2': $3"
}

# try_arm <arm> <dir>: emit on a content-bearing directory, else warn and
# return so the next arm is tried; an unset arm and an absent writer-mode
# directory return silently. Under --all a content-bearing arm is printed and
# the walk goes on.
try_arm() {
  [ -n "$2" ] || return 0
  if [ "$1" = writer-mode ] && [ ! -e "$2" ] && [ ! -L "$2" ]; then
    return 0
  fi
  if [ -d "$2" ] && ! ta_canon=$(canon "$2"); then
    skip_warn "$1" "$2" "the directory cannot be entered"
    return 0
  fi
  if [ ! -d "$2" ] || { [ ! -d "$2/doctrine" ] && [ ! -d "$2/scripts" ]; }; then
    skip_warn "$1" "$2" "not a directory holding doctrine/ or scripts/"
    return 0
  fi
  if [ "$all" -eq 1 ]; then
    found=1
    if [ "$explain" -eq 1 ]; then
      printf '%s\t%s\n' "$1" "$ta_canon"
    else
      printf '%s\n' "$ta_canon"
    fi
    return 0
  fi
  emit "$1" "$ta_canon"
}

resolve_install() {
  found=0
  writer_root=""
  if [ -n "${CLAUDE_DIR:-}" ]; then
    writer_root="$CLAUDE_DIR/planwright"
  elif [ -n "${HOME:-}" ]; then
    writer_root="$HOME/.claude/planwright"
  fi

  try_arm PLANWRIGHT_ROOT "${PLANWRIGHT_ROOT:-}"
  try_arm CLAUDE_PLUGIN_ROOT "${CLAUDE_PLUGIN_ROOT:-}"
  try_arm writer-mode "$writer_root"
  try_arm self-location "$script_dir/.."
  [ "$found" -eq 0 ] || exit 0
  say "no install root resolved (every arm of the core root chain was unset or skipped)"
  exit 1
}

# toplevel_of <dir>: the canonical toplevel of the working tree at <dir>.
toplevel_of() {
  to_top=$(cd -P -- "$1" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$to_top" ] || return 1
  canon "$to_top"
}

no_repo() {
  if [ "$(git rev-parse --is-bare-repository 2>/dev/null)" = true ]; then
    say "no repository root: inside a bare repository, which has no working tree"
  elif [ "$(git rev-parse --is-inside-git-dir 2>/dev/null)" = true ]; then
    say "no repository root: inside a git directory, which has no working tree ($(pwd))"
  else
    say "no repository root: not inside a git repository ($(pwd))"
  fi
  exit 3
}

# repo_config <args...>: read the common git directory's own config. git takes
# core.worktree and core.bare from the repository alone, so the global and
# system files are shut out here, as the inherited -c channels are at entry.
repo_config() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git --git-dir="$rp_common" config "$@"
}

no_primary() {
  say "no repository root: this repository has no primary working tree${1:+ ($1)}"
  exit 3
}

# resolve_primary: set rp_src and rp_path, the canonical primary toplevel,
# and rp_common on the git path; prints nothing, and exits 3 or 4 instead.
resolve_primary() {
  rp_common=""
  if [ -n "${PLANWRIGHT_REPO_ROOT:-}" ]; then
    case $PLANWRIGHT_REPO_ROOT in
      /*) ;;
      *)
        say "refusing PLANWRIGHT_REPO_ROOT='$PLANWRIGHT_REPO_ROOT': it must be an absolute path"
        exit 4
        ;;
    esac
    rp_want=$(canon "$PLANWRIGHT_REPO_ROOT") || rp_want=""
    rp_top=""
    [ -z "$rp_want" ] || rp_top=$(toplevel_of "$rp_want") || rp_top=""
    if [ -z "$rp_top" ] || [ "$rp_top" != "$rp_want" ]; then
      say "refusing PLANWRIGHT_REPO_ROOT='$PLANWRIGHT_REPO_ROOT': it does not name the toplevel of a git working tree"
      exit 4
    fi
    rp_src=PLANWRIGHT_REPO_ROOT
    rp_path=$rp_top
    return 0
  fi

  rp_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || no_repo
  [ "$(git rev-parse --is-bare-repository 2>/dev/null)" != true ] || no_repo
  case $rp_common in
    /*) ;;
    *)
      # git before 2.31 has no --path-format and prints a relative path.
      rp_common=$(git rev-parse --git-common-dir 2>/dev/null) || no_repo
      case $rp_common in
        /*) ;;
        *) rp_common=$(pwd -P)/$rp_common ;;
      esac
      ;;
  esac
  rp_common=$(canon "$rp_common") || no_primary "'$rp_common' is not reachable"
  [ "$(repo_config --bool core.bare 2>/dev/null)" != true ] || no_primary

  # The primary, in order: the configured core.worktree; the tree we are in,
  # when our own git directory is the common one (the only way to name the
  # tree of a separate git dir); the directory holding a .git. A linked
  # worktree of a separate git dir has none of these to go on. A separate
  # git dir that is itself named .git is indistinguishable from an ordinary
  # one, so from inside it or from one of its linked worktrees it answers
  # with the directory holding it.
  rp_src=git-common-dir
  rp_cand=$(repo_config core.worktree 2>/dev/null) || rp_cand=""
  case $rp_cand in
    "" | /*) ;;
    *) rp_cand=$rp_common/$rp_cand ;;
  esac
  if [ -z "$rp_cand" ] && [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    rp_own=$(git rev-parse --absolute-git-dir 2>/dev/null) || rp_own=""
    if [ -n "$rp_own" ] && [ "$(canon "$rp_own")" = "$rp_common" ]; then
      rp_cand=$(git rev-parse --show-toplevel 2>/dev/null) || rp_cand=""
      rp_src=show-toplevel
    fi
  fi
  if [ -z "$rp_cand" ]; then
    case $rp_common in
      */.git) rp_cand=${rp_common%/.git} ;;
      *) no_primary "the git directory '$rp_common' is separate from its working tree and records no primary path" ;;
    esac
  fi
  rp_path=$(toplevel_of "$rp_cand") || no_primary "'$rp_cand' is not reachable"
  [ "$rp_path" = "$(canon "$rp_cand")" ] || no_primary "'$rp_cand' is not a working tree toplevel"
}

# checkout_top: the canonical current toplevel, or nothing outside a tree.
checkout_top() {
  rc_top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$rc_top" ] || return 1
  canon "$rc_top"
}

# common_dir_of <dir>: the canonical common git directory of the repository
# holding <dir>; fails when <dir> is in none.
common_dir_of() {
  (
    cd -P -- "$1" 2>/dev/null || exit 1
    cd_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 1
    case $cd_dir in
      /*) ;;
      *) cd_dir=$(pwd -P)/$(git rev-parse --git-common-dir 2>/dev/null) || exit 1 ;;
    esac
    cd -P -- "$cd_dir" 2>/dev/null && pwd -P
  )
}

# refuse_spec <reason>: refuse the configured spec_root, naming its layer.
refuse_spec() {
  say "refusing spec_root '$sr_value' from the $sr_layer layer: $1"
  exit 5
}

# read_spec_root: set sr_layer and sr_value from the config overlay, read as
# the primary checkout sees it; an unset option leaves sr_value empty.
read_spec_root() {
  sr_knob=$script_dir/resolve-config-knob.sh
  [ -x "$sr_knob" ] || {
    say "spec_root unreadable: the config resolver '$sr_knob' is missing or not executable"
    exit 6
  }
  sr_rc=0
  sr_line=$(PLANWRIGHT_REPO_ROOT=$rp_path "$sr_knob" --explain --key spec_root \
    --type path --fallback '') || sr_rc=$?
  [ "$sr_rc" -eq 0 ] || {
    say "spec_root unreadable: the config overlay could not be read (exit $sr_rc)"
    exit 6
  }
  sr_layer=${sr_line%%"$TAB"*}
  sr_value=${sr_line#*"$TAB"}
}

# spec_root_primary: validate sr_value and set sr_primary, its canonical
# directory; sr_default is 1 when that is <primary>/specs.
spec_root_primary() {
  case $sr_value in
    \~) sr_path=${HOME:-} ;;
    \~/*) sr_path=${HOME:-}/${sr_value#??} ;;
    \~*) refuse_spec "a ~user form is not supported; write the path out, or use ~/" ;;
    /*) sr_path=$sr_value ;;
    *) sr_path=$rp_path/$sr_value ;;
  esac
  case $sr_value in
    \~ | \~/*)
      case ${HOME:-} in
        "") refuse_spec "HOME is not set, so ~ cannot be expanded" ;;
        /*) ;;
        *) refuse_spec "HOME ('$HOME') is not an absolute path, so ~ cannot be expanded" ;;
      esac
      ;;
  esac
  [ -e "$sr_path" ] || refuse_spec "no such directory"
  [ -d "$sr_path" ] || refuse_spec "not a directory"
  sr_primary=$(canon "$sr_path") || refuse_spec "the directory cannot be entered"
  # The default root is decided by the resolved path, and then behaves
  # exactly as unset, even when specs/ is a symlink out of the checkout.
  sr_specs=$(canon "$rp_path/specs") || sr_specs=""
  if [ "$sr_primary" = "$sr_specs" ]; then
    sr_primary=$rp_path/specs
    sr_default=1
    return 0
  fi
  sr_default=0
  case $sr_value in
    \~ | \~/* | /*) ;;
    *)
      case $sr_primary in
        "$rp_path" | "$rp_path"/*) ;;
        *) refuse_spec "a relative value must stay inside the primary checkout ($rp_path), and this one resolves to $sr_primary" ;;
      esac
      ;;
  esac
}

# spec_posture: classify sr_primary against the work repository.
spec_posture() {
  sp_common=$(common_dir_of "$sr_primary") || {
    sr_posture=plain
    return 0
  }
  if [ "$sp_common" = "$work_common" ]; then
    sr_posture=same-repo
  else
    sr_posture=separate-repo
  fi
}

# project_id: the work repository's directory name, folded into the spec
# identifier grammar for the marker's project field.
project_id() {
  printf '%s' "${rp_path##*/}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' \
    | sed -e 's/^-*//' | cut -c1-64
}

# check_marker: refuse unless the root's marker is a regular file, not a
# symlink, whose project field matches the identifier grammar and whose
# layout is 1.
check_marker() {
  cm_file=$sr_primary/planwright-spec-root.yml
  [ ! -L "$cm_file" ] || refuse_spec "$cm_file is a symlink; the marker must be a regular file"
  [ -e "$cm_file" ] \
    || refuse_spec "$sr_primary carries no planwright-spec-root.yml marker (a root other than the default needs one; resolve-root.sh spec --init writes it)"
  [ -f "$cm_file" ] || refuse_spec "$cm_file exists and is not a regular file"
  [ -r "$cm_file" ] || refuse_spec "$cm_file cannot be read"
  cm_project=$(sed -n 's/^project:[[:space:]]*//p' "$cm_file" | head -1 | sed 's/[[:space:]]*$//')
  cm_layout=$(sed -n 's/^layout:[[:space:]]*//p' "$cm_file" | head -1 | sed 's/[[:space:]]*$//')
  case $cm_project in
    "" | *[!a-z0-9-]* | [!a-z0-9]*)
      refuse_spec "$cm_file has no valid project field (the ^[a-z0-9][a-z0-9-]*\$ identifier grammar, at most 64 characters)"
      ;;
  esac
  [ "${#cm_project}" -le 64 ] \
    || refuse_spec "$cm_file has no valid project field (the ^[a-z0-9][a-z0-9-]*\$ identifier grammar, at most 64 characters)"
  [ "$cm_layout" = 1 ] || refuse_spec "$cm_file does not carry layout: 1"
}

# init_spec_root: write the marker and, in a git repository, the ignore
# rules for the entries that never leave the machine.
init_spec_root() {
  # A team-shared value may name any directory, but it only gets written
  # into when it stays inside the primary checkout.
  if [ "$sr_layer" = repo-tracked ]; then
    case $sr_primary in
      "$rp_path" | "$rp_path"/*) ;;
      *) refuse_spec "--init writes where a repo-tracked value points only inside the primary checkout ($rp_path); set the value in the machine-local or adopter layer to initialize $sr_primary" ;;
    esac
  fi
  is_marker=$sr_primary/planwright-spec-root.yml
  [ ! -L "$is_marker" ] || refuse_spec "$is_marker is a symlink; --init never writes through one"
  if [ -e "$is_marker" ] && [ ! -f "$is_marker" ]; then
    refuse_spec "$is_marker exists and is not a file"
  fi
  # The ignore rules land before the marker, so a root is never marked
  # without them.
  if [ "$sr_posture" != plain ]; then
    is_ignore=$sr_primary/.gitignore
    [ ! -L "$is_ignore" ] || refuse_spec "$is_ignore is a symlink; --init never writes through one"
    if [ -s "$is_ignore" ] && [ -f "$is_ignore" ] && [ -n "$(tail -c 1 "$is_ignore" | tr -d '\n')" ]; then
      { printf '\n' >>"$is_ignore"; } 2>/dev/null \
        || refuse_spec "--init could not write the ignore rules"
    fi
    for is_rule in /_pending/notes.md '/*/.orchestrate.lock' '/*/.tasks-pr-sync.*' '/*/.orchestrate/'; do
      if [ -f "$is_ignore" ] && grep -Fqx -- "$is_rule" "$is_ignore"; then
        continue
      fi
      { printf '%s\n' "$is_rule" >>"$is_ignore"; } 2>/dev/null \
        || refuse_spec "--init could not write the ignore rules"
    done
  fi
  if [ ! -e "$is_marker" ]; then
    is_id=$(project_id)
    [ -n "$is_id" ] || refuse_spec "--init cannot derive a project identifier from '$rp_path'"
    # A fresh temp file and a hard link that fails when the marker exists:
    # nothing planted in the root redirects the write, and a racing --init
    # never clobbers a marker already published.
    is_tmp=$(mktemp "$sr_primary/.planwright-spec-root.yml.XXXXXX" 2>/dev/null) \
      || refuse_spec "--init could not write the marker"
    if ! { printf 'project: %s\nlayout: 1\n' "$is_id" >"$is_tmp"; } 2>/dev/null; then
      rm -f "$is_tmp"
      refuse_spec "--init could not write the marker"
    fi
    ln "$is_tmp" "$is_marker" 2>/dev/null || [ -e "$is_marker" ] || [ -L "$is_marker" ] || {
      rm -f "$is_tmp"
      refuse_spec "--init could not write the marker"
    }
    rm -f "$is_tmp"
  fi
}

resolve_spec() {
  resolve_primary
  work_common=$rp_common
  [ -n "$work_common" ] || work_common=$(common_dir_of "$rp_path") \
    || no_primary "'$rp_path' has no common git directory"
  # The checkout to re-base onto: the current tree when it belongs to the
  # work repository, else the primary itself.
  sc_top=$(checkout_top) || sc_top=""
  if [ -z "$sc_top" ] || [ "$(common_dir_of "$sc_top")" != "$work_common" ]; then
    sc_top=$rp_path
  fi
  read_spec_root
  if [ -z "$sr_value" ]; then
    [ "$init" -eq 0 ] || say "spec_root is unset, and the default root needs no marker; nothing to initialize"
    sr_layer=default
    sr_primary=$rp_path/specs
    sr_default=1
  else
    spec_root_primary
    [ "$init" -eq 0 ] || [ "$sr_default" -eq 0 ] \
      || say "spec_root names the default root, which needs no marker; nothing to initialize"
  fi
  if [ "$sr_default" -eq 1 ]; then
    sr_posture=same-repo
  else
    spec_posture
    [ "$init" -eq 0 ] || init_spec_root
    check_marker
  fi
  sr_conf=$sr_primary
  sr_local=$sr_primary
  if [ "$sr_posture" = same-repo ]; then
    # A root inside another linked worktree maps onto the primary checkout's
    # copy at the same relative path, and is re-based from there.
    sm_top=""
    [ "$sr_default" -eq 1 ] || sm_top=$(toplevel_of "$sr_primary") || sm_top=""
    if [ -n "$sm_top" ] && [ "$sm_top" != "$rp_path" ]; then
      case $sr_primary in
        "$sm_top") sr_primary=$rp_path ;;
        "$sm_top"/*) sr_primary=$rp_path/${sr_primary#"$sm_top"/} ;;
      esac
    fi
    case $sr_primary in
      "$rp_path") sr_local=$sc_top ;;
      "$rp_path"/*) sr_local=$sc_top/${sr_primary#"$rp_path"/} ;;
    esac
  fi
  if [ "$view" = primary ]; then
    ss_view=primary
    ss_path=$sr_primary
  else
    ss_view=checkout-local
    ss_path=$sr_local
  fi
  for ss_check in "$sr_primary" "$sr_local"; do
    [ "$(printf '%s' "$ss_check" | tr -d '\000-\037\177')" = "$ss_check" ] || {
      say "refusing the spec root '$ss_check' from the $sr_layer layer: its canonical path carries a control byte or tab"
      exit 5
    }
  done
  if [ "$sr_default" -eq 0 ] && { [ "$explain" -eq 1 ] || [ "$posture_only" -eq 0 ]; } \
    && [ ! -d "$ss_path" ]; then
    say "WARNING the $ss_view spec root '$ss_path' is not present: this checkout does not hold the copy of '$sr_conf' (untracked or gitignored there)"
  fi
  if [ "$explain" -eq 1 ]; then
    printf '%s\t%s\t%s\t%s\n' "$sr_layer" "$ss_path" "$sr_posture" "$ss_view"
  elif [ "$posture_only" -eq 1 ]; then
    printf '%s\n' "$sr_posture"
  else
    printf '%s\n' "$ss_path"
  fi
  exit 0
}

TAB=$(printf '\t')
case $0 in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac

[ "$all" -eq 0 ] || [ "$kind" = install ] || usage
case $kind in
  install | repo)
    [ "$posture_only" -eq 0 ] && [ "$init" -eq 0 ] || usage
    ;;
  spec)
    [ "$view" != checkout ] || usage
    ;;
esac

case $kind in
  install)
    [ -z "$view" ] || usage
    resolve_install
    ;;
  repo | spec)
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
    command -v git >/dev/null 2>&1 || {
      say "no repository root: git is not installed (not on PATH)"
      exit 3
    }
    case $kind:$view in
      repo:primary)
        resolve_primary
        emit "$rp_src" "$rp_path"
        ;;
      repo:checkout)
        rc_top=$(checkout_top) || no_repo
        emit show-toplevel "$rc_top"
        ;;
      spec:*) resolve_spec ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
