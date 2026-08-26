#!/bin/sh
# inception-secret-screen.sh — commit-time secret screening for venture repos
# (inception Task 2; REQ-A1.9 · D-12).
#
# The scaffolded pre-commit hook calls this before anything else, so it must
# work on a machine that has never heard of planwright's toolchain. It prefers
# gitleaks when the venture host has it and falls back to a small, deliberately
# conservative pattern set otherwise: the fallback aims at credential shapes
# that are unambiguous on sight (key blocks, provider-prefixed tokens, long
# opaque assignments), not at catching everything. A venture repo that needs
# real coverage installs gitleaks and gets it automatically; the built-in
# screen is the floor, not the ceiling.
#
# It reports `<file>:<line>: <rule>` and NEVER the matched text. A hook that
# echoes the secret it caught has moved the secret from the diff into terminal
# scrollback and the CI log, which is the failure this guard exists to prevent
# (doctrine/security-posture.md, echo discipline).
#
# Usage:
#   inception-secret-screen.sh --staged            screen the git index
#   inception-secret-screen.sh <path>...           screen files and directories
#
# Exit: 0 nothing found · 1 a candidate secret was found · 2 usage or
#   environment error.
#
# Environment:
#   PLANWRIGHT_SECRET_SCREEN_TOOL   auto (default) | gitleaks | none
#
# Portable POSIX sh + grep -E; bash 3.2 / BSD tooling floor (REQ-K1.5).
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

# Canonical echo-discipline sanitizer (doctrine/security-posture.md). A path
# this screen reports is repo-controlled input: a filename carrying an escape
# sequence would otherwise drive the terminal of whoever ran the commit, which
# is a poor trade for a guard whose whole point is that hostile content in a
# repo does not get to act on the person reading the output.
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

usage() {
  echo "usage: inception-secret-screen.sh --staged" >&2
  echo "       inception-secret-screen.sh <path>..." >&2
  exit 2
}

staged=0
paths=
npaths=0
while [ $# -gt 0 ]; do
  case $1 in
    --staged)
      staged=1
      shift
      ;;
    -*) usage ;;
    *)
      paths="$paths
$1"
      npaths=$((npaths + 1))
      shift
      ;;
  esac
done

if [ "$staged" -eq 1 ]; then
  [ "$npaths" -eq 0 ] || usage
else
  [ "$npaths" -gt 0 ] || usage
fi

tool=${PLANWRIGHT_SECRET_SCREEN_TOOL:-auto}
case $tool in
  auto | gitleaks | none) ;;
  *)
    echo "inception-secret-screen: PLANWRIGHT_SECRET_SCREEN_TOOL must be auto, gitleaks, or none" >&2
    exit 2
    ;;
esac

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

# --- gitleaks, when it is available and not opted out ----------------------
#
# gitleaks 8.19 renamed `detect`/`protect` to `git`/`dir`; both spellings ship
# in current 8.x, so probe for the new one and fall back to the old rather than
# pinning a version a venture host has no reason to match.
if [ "$tool" != none ] && command -v gitleaks >/dev/null 2>&1; then
  # Two variables for the directory spelling, not one string: the path loop
  # below runs under IFS=<newline>, where `detect --source` would not split on
  # its space and would reach gitleaks as a single unknown subcommand.
  if gitleaks git --help >/dev/null 2>&1; then
    gl_git="git"
    gl_dir_cmd="dir"
    gl_dir_flag=""
  else
    gl_git="protect"
    gl_dir_cmd="detect"
    gl_dir_flag="--source"
  fi
  if [ "$staged" -eq 1 ]; then
    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
      echo "inception-secret-screen: --staged needs a git work tree" >&2
      exit 2
    fi
    # shellcheck disable=SC2086 # gl_git is a fixed subcommand word, not input
    if gitleaks $gl_git --staged --no-banner --redact >"$work/gl.out" 2>&1; then
      exit 0
    fi
    cat "$work/gl.out" >&2
    echo "inception-secret-screen: gitleaks flagged staged content (output redacted above)" >&2
    exit 1
  fi
  rc=0
  oIFS=$IFS
  IFS='
'
  for p in $paths; do
    [ -n "$p" ] || continue
    # Per-path status, not the accumulated one: a shared flag would make every
    # clean path after the first hit re-print the previous path's output, so one
    # leak across several arguments would read as several.
    prc=0
    if [ -n "$gl_dir_flag" ]; then
      gitleaks "$gl_dir_cmd" "$gl_dir_flag" "$p" --no-banner --redact >"$work/gl.out" 2>&1 || prc=1
    else
      gitleaks "$gl_dir_cmd" "$p" --no-banner --redact >"$work/gl.out" 2>&1 || prc=1
    fi
    if [ "$prc" -ne 0 ]; then
      cat "$work/gl.out" >&2
      rc=1
    fi
  done
  IFS=$oIFS
  exit "$rc"
fi

# --- built-in screen -------------------------------------------------------
#
# One `<rule><TAB><ERE>` line per shape. grep -E is the engine because POSIX
# requires interval expressions there and not in awk, and because grep -n gives
# the line number without ever handing the matched text back to the caller.
rules=$(
  cat <<'RULES'
private-key-block	-----BEGIN ([A-Z]+ )?PRIVATE KEY-----
aws-access-key-id	(AKIA|ASIA)[0-9A-Z]{16}
github-token	gh[pousr]_[A-Za-z0-9]{36,}
slack-token	xox[abpsr]-[A-Za-z0-9-]{16,}
provider-api-key	sk-[A-Za-z0-9_-]{24,}
opaque-assignment	(api[_-]?key|secret|token|password|passwd)['\"]?[ 	]*[:=][ 	]*['\"]?[A-Za-z0-9/+=_-]{20,}
RULES
)

found=0
tab=$(printf '\t')

screen_file() {
  # screen_file <path-to-read> <name-to-report>
  oIFS2=$IFS
  IFS='
'
  for rule in $rules; do
    [ -n "$rule" ] || continue
    rname=${rule%%"$tab"*}
    rpat=${rule#*"$tab"}
    # -a because grep decides for itself what is binary and SKIPS it entirely
    # rather than matching it differently. A venture repo picks such files up
    # routinely (a UTF-16 note, an exported keystore), and a screen that steps
    # over a whole class of file while reporting clean is the failure this
    # guard exists to prevent.
    lines=$(grep -a -n -E -e "$rpat" -- "$1" 2>/dev/null | cut -d: -f1)
    for ln in $lines; do
      [ -n "$ln" ] || continue
      printf '%s:%s: %s (value redacted)\n' \
        "$(sanitize_printable "$2" '(unprintable path)')" "$ln" "$rname" >&2
      found=1
    done
  done
  IFS=$oIFS2
}

if [ "$staged" -eq 1 ]; then
  if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "inception-secret-screen: --staged needs a git work tree" >&2
    exit 2
  fi
  # Read the INDEX, not the working tree: the hook screens what is about to be
  # committed, which is not necessarily what is on disk.
  #
  # `core.quotePath=false` and `-z` because the default spelling of this command
  # C-quotes any non-ASCII path, and the blob then does not resolve under that
  # literal name.
  git -c core.quotePath=false diff --cached --name-only -z --diff-filter=ACM \
    >"$work/staged.z" || exit 2

  # The read below is line-oriented, and POSIX sh cannot split on NUL, so a path
  # carrying a newline would break into pieces. That is not merely lossy: pick
  # the pieces to match other staged names and every one of them resolves, so
  # the crafted path is screened zero times and the walk still reports clean.
  # Refuse the whole run instead. Nothing here may turn "unexamined" into
  # "clean", and a name nobody needs is not worth a partial guarantee.
  if [ "$(tr -d '\0' <"$work/staged.z" | tr -dc '\n' | wc -c)" -ne 0 ]; then
    echo "inception-secret-screen: a staged path contains a newline, which this screen cannot read unambiguously; commit refused" >&2
    echo "inception-secret-screen: rename it, or bypass deliberately with --no-verify" >&2
    exit 2
  fi
  tr '\0' '\n' <"$work/staged.z" >"$work/staged.txt" || exit 2
  n=0
  unreadable=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    n=$((n + 1))
    if git show ":$rel" >"$work/blob.$n" 2>/dev/null; then
      screen_file "$work/blob.$n" "$rel"
    else
      printf '%s\n' "inception-secret-screen: cannot read the staged blob for $(sanitize_printable "$rel" '(unprintable path)'); refusing to pass it unscreened" >&2
      unreadable=1
    fi
  done <"$work/staged.txt"
  if [ "$unreadable" -ne 0 ]; then
    echo "inception-secret-screen: some staged content could not be screened; commit refused" >&2
    exit 2
  fi
else
  oIFS=$IFS
  IFS='
'
  for p in $paths; do
    [ -n "$p" ] || continue
    if [ -d "$p" ]; then
      # Prune .git: object files are compressed blobs the pattern screen cannot
      # read anyway, and walking them turns a repo-root screen into a crawl.
      find "$p" -name .git -prune -o -type f -print >"$work/files.txt" 2>/dev/null || true
      IFS=$oIFS
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        screen_file "$f" "$f"
      done <"$work/files.txt"
      IFS='
'
    elif [ -f "$p" ]; then
      screen_file "$p" "$p"
    else
      printf '%s\n' "inception-secret-screen: no such file or directory: $(sanitize_printable "$p" '(unprintable path)')" >&2
      IFS=$oIFS
      exit 2
    fi
  done
  IFS=$oIFS
fi

if [ "$found" -ne 0 ]; then
  echo "inception-secret-screen: candidate secrets found (values redacted above)" >&2
  exit 1
fi
exit 0
