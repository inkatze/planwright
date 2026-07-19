# shellcheck shell=bash
# release-lib.sh — shared primitives for the release-tagging scripts (autopilot-
# reflex Task 4; D-4, D-6, D-8, D-13; REQ-D1.1, REQ-D1.2, REQ-D1.6, REQ-D1.8,
# REQ-D1.9) plus the shared CI-verdict primitive rl_ci_state (release-hardening
# Task 3; REQ-C1.1, REQ-C1.2, REQ-C1.3, REQ-C1.4). Sourced, never executed, by
# scripts/release-pending.sh and scripts/release-publish.sh so the two agree
# byte-for-byte on what a version is, which version is greater, and where the
# version of truth lives; and by scripts/release-arm.sh, which shares
# rl_ci_state with release-publish.sh so the two never drift on what counts as
# release-gating CI (REQ-C1.2).
#
# The comparator (release-pending.sh) is the reusable definition of "pending"
# the untagged-window lock and the bookkeeping surface both read (REQ-D1.8);
# this lib is the layer below it, the definition of a version those two scripts
# share. Kept dependency-light per the repo's portability conventions (bash 3.2
# / BSD tooling, LC_ALL=C, no fish/mise/tmux dependency — REQ-D1.9): git; jq (for
# a JSON `version_file` selector, and the rl_ci_state verdict fold); and gh —
# used ONLY by rl_ci_state when it is CALLED (the CI-verdict primitive), never at
# source time, so a non-gh caller that sources the lib but does not call
# rl_ci_state (release-pending.sh) is not forced onto gh. Both are already repo
# tool dependencies.
#
# Security posture (doctrine/security-posture.md, framework-script rules,
# REQ-D1.6): a version string is validated against the SemVer grammar before it
# is compared or used to build a tag; the `version_file` selector is treated as
# DATA — parsed against a fixed grammar and the key handed to jq via `--arg`,
# never interpolated into an executed jq program or a shell command. Untrusted
# values echoed on an error path are stripped of terminal-control bytes first
# (`_rl_safe`, the sourced-lib inline of scripts/echo-safety.sh's discipline).
#
# Locale contract: callers MUST have `LC_ALL=C` in effect before sourcing this
# lib (both release-pending.sh and release-publish.sh set and export it). The
# SemVer regex bracket classes and the ASCII string comparison in rl_version_gt
# are only correct under the C locale; a non-C collation would mis-rank
# prerelease identifiers.

# _rl_safe <value> — strip C0/DEL/C1 control bytes so an error-path echo of an
# untrusted (invalid) version/selector value cannot drive the terminal. The
# doctrine's canonical sanitizer is scripts/echo-safety.sh; this is the
# sanctioned self-contained inline copy for the sourced lib (same posture as
# spec-assemble.sh's inline copy).
_rl_safe() {
  printf '%s' "${1-}" | tr -d '\000-\037\177\200-\237'
}

# The SemVer core+prerelease+build grammar (semver.org 2.0.0), as a POSIX ERE.
# Kept in one place so validation and the tag/label paths cannot drift.
RL_SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

# rl_valid_semver <version> — exit 0 when <version> is a well-formed SemVer
# string (no leading `v`), non-zero otherwise. The single validation boundary.
# Uses bash `[[ =~ ]]` (whole-string match), not `grep -Eq` (which matches any
# LINE): a multi-line value — e.g. a JSON `.version` carrying an embedded
# newline — must be rejected, not validated on its first line.
#
# The regex enforces no-leading-zero on the numeric version core, but its
# prerelease and build classes (`[0-9A-Za-z.-]+`) cannot express the SemVer 2.0.0
# "identifiers MUST NOT be empty" rule (they permit dots anywhere), so a second
# pass enforces it for BOTH the prerelease (§9) and the build metadata (§10):
#   - Prerelease (§9): "Identifiers MUST NOT be empty" — a leading dot, a trailing
#     dot, or two consecutive dots yields an empty identifier (`1.0.0-.1`,
#     `1.0.0-a.`, `1.0.0-a..b`); checked on the raw prerelease string, not the
#     split fields, because `IFS=. read` drops a trailing empty field and would
#     miss `a.`. Plus "Numeric identifiers MUST NOT include leading zeroes": any
#     numeric identifier of length > 1 with a leading zero (`1.0.0-01`).
#   - Build metadata (§10): "Identifiers MUST NOT be empty" applies here too, so
#     `1.2.3+build..1`, `1.2.3+.foo`, and `1.2.3+foo.` are invalid. §10 imposes NO
#     numeric/leading-zero rule (build metadata carries no precedence), so only
#     the empty-identifier check runs on the build part.
# Without the prerelease numeric rule, `1.0.0-01` and `1.0.0-1` both validate yet
# compare equal (rl_version_gt), so one spelling can mask a pending release;
# without the empty rules, a malformed empty identifier validates and then, for a
# prerelease, mis-ranks (an empty field is rl_version_gt's "fewer fields → lower"
# sentinel).
rl_valid_semver() {
  [[ ${1-} =~ $RL_SEMVER_RE ]] || return 1
  local v="${1-}" rest pre build

  # Split build metadata (§10) off at the first '+', then the prerelease (§9) off
  # the remainder at its first '-'. A version may carry build metadata with no
  # prerelease (`1.2.3+build`), so the build part is validated independently and
  # is NOT reachable through the prerelease branch.
  build=""
  [[ "$v" == *+* ]] && build="${v#*+}"
  rest="${v%%+*}"
  pre=""
  [[ "$rest" == *-* ]] && pre="${rest#*-}"

  if [[ -n "$pre" ]]; then
    case "$pre" in
      .* | *. | *..*) return 1 ;; # empty identifier (leading/trailing/double dot)
    esac
    local -a ids
    IFS=. read -ra ids <<<"$pre"
    local id
    for id in "${ids[@]}"; do
      case "$id" in
        *[!0-9]*) : ;;   # alphanumeric identifier — the numeric rule is N/A
        0?*) return 1 ;; # numeric, length > 1, leading zero → invalid
      esac
    done
  fi

  if [[ -n "$build" ]]; then
    case "$build" in
      .* | *. | *..*) return 1 ;; # empty build identifier (§10)
    esac
  fi

  return 0
}

# rl_version_gt <a> <b> — exit 0 when SemVer <a> is strictly greater than <b> by
# precedence (semver.org §11): numeric major/minor/patch, then a version with a
# prerelease ranks lower than the same without, then prerelease identifiers
# compared field-by-field (numeric numerically, alphanumeric by ASCII order,
# numeric below alphanumeric, more fields above fewer). Build metadata is
# ignored.
#
# Tri-state result (D-2, REQ-A1.1): exit 0 = strictly greater, exit 1 = not
# strictly greater (equal or lower), exit 2 = comparator error — a malformed or
# unusable operand reached the comparator. Both operands are validated against
# rl_valid_semver at entry, so a caller can tell a comparator failure from a
# negative comparison and fail closed on it, rather than reading an undefined
# arithmetic result as "not greater". Every caller pre-validates its operands
# today (rl_latest_release_tag filters tags through rl_valid_semver; the
# release-pending / window-check readers validate their version of truth), so the
# error status is unreachable via real inputs: this is deliberate
# defense-in-depth for a future non-validating caller, at the cost of one
# validation branch, not the closing of a live fail-open.
#
# 64-bit numeric-identifier overflow limit (D-6, REQ-E1.2): every numeric
# comparison here — the major/minor/patch core and any all-digit prerelease
# identifier — uses bash arithmetic (`((10#$x > 10#$y))`), which is signed
# 64-bit. A numeric identifier at or above 2^63 (9223372036854775808, 19+
# digits) overflows and ranks unreliably. This is a KNOWN, DELIBERATELY
# UNGUARDED limit, not a live risk: a ~19-20+ digit numeric SemVer identifier
# is not a realistic version string. D-6 rejected an arithmetic guard
# (length-then-lexical) as hot-path cost for a pathological input; the
# documented limit plus a boundary test at a safe, non-overflowing width
# (tests/test-release-lib.sh) make the behavior explicit and honest instead.
rl_version_gt() {
  # Validate both operands at entry: a malformed/unusable input is a distinct
  # error status (2), not a silent "not greater". This is the tri-state's spine.
  rl_valid_semver "${1-}" || return 2
  rl_valid_semver "${2-}" || return 2
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

# _rl_resolve_leaf_symlink <path> — resolve a symlink at the FINAL path
# component, iterating until the leaf is no longer a symlink, so a leaf
# `version_file` that is itself a symlink is de-referenced (the parent-dir-only
# `cd; pwd -P` recipe misses exactly this). Intermediate directory components
# are left for `pwd -P` to canonicalize. Prints the de-symlinked path; returns
# non-zero on a symlink loop or an unreadable link (a failing `readlink`).
# Portable to the BSD/macOS floor: one-level
# `readlink` in a bounded loop, never `readlink -f`/`realpath` (absent there —
# D-5, REQ-D1.2). Every path-util call is `--`-guarded (as the `cd --` calls in
# rl_canonical_contained_path are) so a `version_file` value beginning with `-`
# is treated as an operand, not misparsed as a flag.
_rl_resolve_leaf_symlink() {
  local target="$1" link count=0
  while [ -L "$target" ]; do
    count=$((count + 1))
    if [ "$count" -gt 40 ]; then
      return 1 # symlink loop (bound sits above the BSD/macOS floor's 32-link ELOOP)
    fi
    link=$(readlink -- "$target") || return 1
    case "$link" in
      /*) target="$link" ;;                        # absolute target
      *) target="$(dirname -- "$target")/$link" ;; # relative to the link's dir
    esac
  done
  printf '%s\n' "$target"
}

# rl_canonical_contained_path <path> — canonicalize <path> and confirm it sits
# within the repository root, printing the canonical real path on success. The
# reusable version_file containment guard (REQ-D1.1, REQ-D1.2, D-5): it resolves
# symlinks in EVERY component including the leaf itself, then requires the result
# to be inside the repo root. Callers read the printed path, never the original
# value, so a resolved path cannot be re-defeated by re-following the original
# symlink. Returns non-zero with no output on a symlink loop, an unresolvable
# directory component (a dangling or looping parent), an unresolvable repo root,
# or a path escaping the root — each a caller-side clean exit-2 refusal. A
# dangling *leaf* whose parent directory does resolve in-tree instead returns 0
# with the canonical (non-existent) path, leaving the caller's own existence
# check to reject it (still a clean exit-2). Portable to the
# bash 3.2 / BSD / `LC_ALL=C` floor; any future filesystem reader of a
# config-specified path reuses it rather than re-implementing the guard.
rl_canonical_contained_path() {
  local path="$1" resolved dir base canon top root
  resolved=$(_rl_resolve_leaf_symlink "$path") || return 1 # symlink loop
  # `pwd -P` resolves symlinks in every remaining (directory) component; a
  # dangling/unresolvable parent or a loop in a parent makes the cd fail → clean
  # refusal. `unset CDPATH` in the subshell neutralizes a hostile CDPATH.
  if [ -d "$resolved" ]; then
    # A leaf that resolves to a directory (including a `.`/`..` target, or the
    # filesystem root) is canonicalized WHOLESALE, so a parent-denoting leaf
    # cannot yield a path that textually sits under the root while denoting its
    # parent (e.g. `<root>/..`) and slip past the containment check below.
    canon=$(
      unset CDPATH
      cd -- "$resolved" 2>/dev/null && pwd -P
    ) || return 1
  else
    dir=$(dirname -- "$resolved")
    base=$(basename -- "$resolved")
    canon=$(
      unset CDPATH
      cd -- "$dir" 2>/dev/null && pwd -P
    ) || return 1
    canon="${canon%/}/$base"
  fi
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  root=$(
    unset CDPATH
    cd -- "$top" 2>/dev/null && pwd -P
  ) || return 1
  case "$canon/" in
    "$root/"*) printf '%s\n' "$canon" ;;
    *) return 1 ;; # escapes the repository root
  esac
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
      echo "release-lib: jq is required to read a JSON version_file selector ($(_rl_safe "$sel"))" >&2
      return 2
    fi
    # Capture jq's exit status: on malformed JSON, jq exits non-zero and writes a
    # parse error to stderr. The prior code ignored that and returned 0 with empty
    # stdout, so a corrupt version_file surfaced downstream as a generic "no
    # version found" / "not valid SemVer" (with jq's raw stderr leaking through).
    # Fail closed with a specific message instead, matching the jq-missing branch
    # above. `.[$k] // empty` still yields empty (exit 0) when the KEY is absent
    # from well-formed JSON, so a missing key is unchanged, not treated as a parse
    # failure. Output has no trailing newline, consistent with whole-file mode.
    local out
    if ! out=$(jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null); then
      echo "release-lib: could not parse JSON version_file (jq failed on selector $(_rl_safe "$sel"))" >&2
      return 2
    fi
    printf '%s' "$out"
    return 0
  fi
  echo "release-lib: unsupported version_file selector (expected \$.<key> or whole-file): $(_rl_safe "$sel")" >&2
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

# The untagged-window lock check, EXCLUDED from the release-gating CI verdict,
# SCOPED to its owning workflow (D-4, D-8; REQ-C1.3). The lock (release-window.yml,
# check-run name `window-lock`) is RED BY DESIGN on `main` throughout the untagged
# window — from the moment a release PR merges until publish tags it. It is a
# MERGE gate, never a PUBLISH gate (autopilot-reflex REQ-D1.3, restated by
# citation in REQ-C1.4): gating publish on it would deadlock, since publishing the
# tag is the only thing that closes the window. A check is the lock ONLY when it is
# a CheckRun named `window-lock` AND its owning Actions workflow is `release-window`
# (checkSuite.workflowRun.workflow.name); a same-named check-run from any OTHER
# workflow — and a null-workflowRun namesake (a non-Actions app check) — fails the
# workflow test and is JUDGED by the gate, never silently dropped. Keying off the
# workflow `name` is an improvement over a bare check-run-name match though not
# spoof-proof within the merge-capable trust model (REQ-C1.3).
RL_CI_WINDOW_LOCK_NAME="window-lock"
RL_CI_WINDOW_LOCK_WORKFLOW="release-window"

# rl_ci_state <sha> — print the release-gating CI verdict for commit <sha> to
# stdout and return 0; on a gh/query failure print nothing and return 2, so a
# caller distinguishes an infra outage from a red verdict (an outage is never
# misreported as red CI). The SINGLE CI-verdict primitive both release-publish.sh
# (its ci gate) and release-arm.sh (its release-gating verdict) call, so the two
# never drift on what counts as release-gating CI (D-4; REQ-C1.1, REQ-C1.2). The
# duplicated inline evaluators the two scripts carried are retired in favor of it.
#
# Canonical verdict vocabulary (REQ-C1.1), used by name across this bundle:
#   green     at least one non-excluded check succeeded and none failed or is
#             pending (NEUTRAL/SKIPPED checks neither confirm nor block)
#   failing   a non-excluded check failed — it will not self-heal
#   pending   a non-excluded check is still running
#   none      no positive confirmation — no checks, only the excluded lock, or
#             only NEUTRAL/SKIPPED remain. A release gate requires a positive
#             SUCCESS, so "no CI" folds to none (fail-closed by design; an adopter
#             without CI adds it, or opts out via the planned require_ci knob
#             (REQ-G1.3, not yet built))
#   too-many  more than one page of checks (>100) — the read is incomplete, so a
#             failing/pending check could hide unread; fail closed
#
# The GraphQL statusCheckRollup's per-check `contexts` (check-runs AND commit
# statuses) is judged individually, NOT the single aggregated rollup `state`: the
# aggregate folds in the release-window lock, which is red BY DESIGN during the
# untagged window, so a gate on the aggregate would deadlock (REQ-C1.4). The
# window lock is excluded workflow-scoped (RL_CI_WINDOW_LOCK_* above). A CheckRun
# is PENDING until COMPLETED; SUCCESS is the only positive confirmation;
# NEUTRAL/SKIPPED neither confirm nor fail. Legacy StatusContexts map
# SUCCESS/PENDING/EXPECTED/other the same way (commit statuses carry no
# NEUTRAL/SKIPPED and no workflow, so a StatusContext is never the excluded lock).
# Any jq error (malformed response, missing field) fails closed via `|| return 2`,
# as does an abnormal exit-0 gh success with an empty body (guarded before jq, so
# an empty body is the query-failure status, never an empty rc-0 verdict).
#
# Uses gh (only when CALLED — sourcing this lib does not require gh; the fs reader
# release-pending.sh sources the lib but never calls rl_ci_state) and jq.
rl_ci_state() {
  local sha="$1" nwo owner repo raw
  nwo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || return 2
  # An abnormal exit-0 success with an empty body is a query failure, not a
  # verdict: an empty nameWithOwner would parse to empty owner/repo and fold the
  # rollup to a spurious "none" (REQ-C1.1's rc-0⟺non-empty-verdict contract).
  [ -n "$nwo" ] || return 2
  owner=${nwo%%/*}
  repo=${nwo#*/}
  # shellcheck disable=SC2016 # $o/$r/$sha are GraphQL variables, not shell expansions
  raw=$(gh api graphql \
    -f query='query($o:String!,$r:String!,$sha:GitObjectID!){repository(owner:$o,name:$r){object(oid:$sha){... on Commit{statusCheckRollup{contexts(first:100){pageInfo{hasNextPage} nodes{__typename ... on CheckRun{name status conclusion checkSuite{workflowRun{workflow{name}}}} ... on StatusContext{context state}}}}}}}}' \
    -f o="$owner" -f r="$repo" -f sha="$sha" 2>/dev/null) || return 2
  # jq exits 0 with no output on empty input, so an empty response body would
  # otherwise return rc 0 with an empty verdict — the query-failure status (2),
  # not a verdict (REQ-C1.1's rc-0⟺non-empty-verdict contract).
  [ -n "$raw" ] || return 2
  printf '%s' "$raw" | jq -r \
    --arg nm "$RL_CI_WINDOW_LOCK_NAME" --arg wf "$RL_CI_WINDOW_LOCK_WORKFLOW" '
    .data.repository.object.statusCheckRollup as $roll
    | if $roll == null then "none"
      elif ($roll.contexts.pageInfo.hasNextPage // false) then "too-many"
      else
        [ ($roll.contexts.nodes // [])[]
          | if .__typename == "CheckRun" then
              { excl: ( (.name // "") == $nm
                        and ((.checkSuite.workflowRun.workflow.name // "") == $wf) ),
                v: ( if .status != "COMPLETED" then "pending"
                     elif .conclusion == "SUCCESS" then "green"
                     elif (.conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "neutral"
                     else "failing" end ) }
            else
              { excl: false,
                v: ( if .state == "SUCCESS" then "green"
                     elif (.state == "PENDING" or .state == "EXPECTED") then "pending"
                     else "failing" end ) }
            end
        ]
        | map(select(.excl | not)) | map(.v) as $vs
        | if ($vs | length) == 0 then "none"
          elif any($vs[]; . == "failing") then "failing"
          elif any($vs[]; . == "pending") then "pending"
          elif any($vs[]; . == "green") then "green"
          else "none" end
      end
  ' 2>/dev/null || return 2
}
