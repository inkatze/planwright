# shellcheck shell=bash
# release-lib.sh — shared primitives for the release-tagging scripts (autopilot-
# reflex Task 4; D-4, D-6, D-8, D-13; REQ-D1.1, REQ-D1.2, REQ-D1.6, REQ-D1.8,
# REQ-D1.9). Sourced, never executed, by scripts/release-pending.sh and
# scripts/release-publish.sh so the two agree byte-for-byte on what a version
# is, which version is greater, and where the version of truth lives.
#
# The comparator (release-pending.sh) is the reusable definition of "pending"
# the untagged-window lock and the bookkeeping surface both read (REQ-D1.8);
# this lib is the layer below it, the definition of a version those two scripts
# share. Kept dependency-light per the repo's portability conventions (bash 3.2
# / BSD tooling, LC_ALL=C, no fish/mise/tmux dependency — REQ-D1.9): only git
# and, for a JSON `version_file` selector, jq (already a repo tool dependency).
#
# Security posture (doctrine/security-posture.md, framework-script rules,
# REQ-D1.6): a version string is validated against the SemVer grammar before it
# is compared or used to build a tag; the `version_file` selector is treated as
# DATA — parsed against a fixed grammar and the key handed to jq via `--arg`,
# never interpolated into an executed jq program or a shell command.

# The SemVer core+prerelease+build grammar (semver.org 2.0.0), as a POSIX ERE.
# Kept in one place so validation and the tag/label paths cannot drift.
RL_SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

# rl_valid_semver <version> — exit 0 when <version> is a well-formed SemVer
# string (no leading `v`), non-zero otherwise. The single validation boundary.
rl_valid_semver() {
  printf '%s' "${1-}" | grep -Eq "$RL_SEMVER_RE"
}

# rl_version_gt <a> <b> — exit 0 when SemVer <a> is strictly greater than <b> by
# precedence (semver.org §11): numeric major/minor/patch, then a version with a
# prerelease ranks lower than the same without, then prerelease identifiers
# compared field-by-field (numeric numerically, alphanumeric by ASCII order,
# numeric below alphanumeric, more fields above fewer). Build metadata is
# ignored. Callers validate both inputs first; this assumes well-formed SemVer.
rl_version_gt() {
  local a="${1%%+*}" b="${2%%+*}" # drop build metadata
  local amain="${a%%-*}" bmain="${b%%-*}"
  local apre="" bpre=""
  [[ "$a" == *-* ]] && apre="${a#*-}"
  [[ "$b" == *-* ]] && bpre="${b#*-}"

  local -a af bf
  IFS=. read -ra af <<<"$amain"
  IFS=. read -ra bf <<<"$bmain"
  local i x y
  for i in 0 1 2; do
    x="${af[i]:-0}"
    y="${bf[i]:-0}"
    if ((10#$x > 10#$y)); then return 0; fi
    if ((10#$x < 10#$y)); then return 1; fi
  done

  # major.minor.patch equal — apply the prerelease precedence rules.
  if [[ -z "$apre" && -z "$bpre" ]]; then return 1; fi # equal, not greater
  if [[ -z "$apre" ]]; then return 0; fi               # a is a release, b is pre
  if [[ -z "$bpre" ]]; then return 1; fi               # a is pre, b is a release

  local -a ap bp
  IFS=. read -ra ap <<<"$apre"
  IFS=. read -ra bp <<<"$bpre"
  local n=$((${#ap[@]} > ${#bp[@]} ? ${#ap[@]} : ${#bp[@]}))
  local j ai bi anum bnum
  local num_re='^[0-9]+$'
  for ((j = 0; j < n; j++)); do
    ai="${ap[j]-}"
    bi="${bp[j]-}"
    if [[ -z "$ai" ]]; then return 1; fi # a has fewer fields → lower
    if [[ -z "$bi" ]]; then return 0; fi # b has fewer fields → a higher
    if [[ "$ai" == "$bi" ]]; then continue; fi
    anum=0
    bnum=0
    [[ "$ai" =~ $num_re ]] && anum=1
    [[ "$bi" =~ $num_re ]] && bnum=1
    if ((anum && bnum)); then
      if ((10#$ai > 10#$bi)); then return 0; else return 1; fi
    elif ((anum)); then
      return 1 # numeric identifier ranks below alphanumeric
    elif ((bnum)); then
      return 0
    else
      if [[ "$ai" > "$bi" ]]; then return 0; else return 1; fi
    fi
  done
  return 1
}

# rl_resolve_version_file <script_dir> — print `path<TAB>selector` for the
# version of truth, reading the `version_file` knob through the config overlay
# and falling back to the plugin-manifest default. The knob value is
# `<path>[::<selector>]`; an absent `::<selector>` means whole-file mode. The
# separator is `::`, not `#`: config-get strips a trailing `#comment` (YAML), so
# a `#` in the value would be truncated.
rl_resolve_version_file() {
  local script_dir="$1" raw path selector
  raw=$("$script_dir/config-get.sh" version_file 2>/dev/null) || raw=""
  [[ -n "$raw" ]] || raw='.claude-plugin/plugin.json::$.version'
  if [[ "$raw" == *"::"* ]]; then
    path="${raw%%::*}"
    selector="${raw#*::}"
  else
    path="$raw"
    selector=""
  fi
  printf '%s\t%s\n' "$path" "$selector"
}

# rl_extract_version <selector> — read a version-file blob on stdin and print
# the version it holds. Whole-file mode (empty or `-` selector) trims all
# whitespace and prints the remainder (a plain VERSION file). A `$.<key>`
# selector extracts that top-level JSON string field with jq, passing the key
# as DATA (`--arg`) against a fixed program so the selector is never executed.
# Any other selector shape is rejected (exit 2) rather than run.
rl_extract_version() {
  local sel="${1-}" key
  if [[ -z "$sel" || "$sel" == "-" ]]; then
    tr -d '[:space:]'
    return 0
  fi
  local sel_re='^\$\.([A-Za-z0-9_-]+)$'
  if [[ "$sel" =~ $sel_re ]]; then
    key="${BASH_REMATCH[1]}"
    if ! command -v jq >/dev/null 2>&1; then
      echo "release: jq is required to read a JSON version_file selector ($sel)" >&2
      return 2
    fi
    jq -r --arg k "$key" '.[$k] // empty'
    return 0
  fi
  echo "release: unsupported version_file selector (expected \$.<key> or whole-file): $sel" >&2
  return 2
}

# rl_version_at <ref> <path> <selector> — print the version recorded in <path>
# as of git <ref> (a commit SHA, branch, or `:` for the index). Empty output
# when the file is absent at that ref.
rl_version_at() {
  local ref="$1" path="$2" selector="$3"
  git show "$ref:$path" 2>/dev/null | rl_extract_version "$selector"
}

# rl_latest_release_tag — print the highest `v<semver>` tag by SemVer
# precedence, or nothing when the repo has no release tags. Uses an explicit
# precedence fold rather than `sort -V` (absent on the BSD sort of the macOS
# floor, REQ-D1.9).
rl_latest_release_tag() {
  local best="" best_ver="" tag ver
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    ver="${tag#v}"
    rl_valid_semver "$ver" || continue
    if [[ -z "$best" ]] || rl_version_gt "$ver" "$best_ver"; then
      best="$tag"
      best_ver="$ver"
    fi
  done < <(git tag -l 'v*')
  [[ -n "$best" ]] && printf '%s\n' "$best"
}
