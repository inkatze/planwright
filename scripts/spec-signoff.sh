# shellcheck shell=bash
# shellcheck disable=SC2154 # script_dir is the sourcing script's
# spec-signoff.sh — the sign-off reads mission control's readiness check and
# the step audit share (sourced, never executed). The sourcing script sets
# `script_dir` and has sourced echo-safety.sh, mc-lib.sh and spec-parse.sh
# first. Portable bash 3.2 / BSD tooling.

unset CDPATH

# spec_scope_bundles <root rel> <changes>: <changes> lists one change per
# line, `path<TAB><path><TAB>ADDED|MODIFIED|DELETED|<other>` (a path column
# first; any other first column is ignored). Succeeds, printing the bundles
# touched, one per line, when every path sits strictly under <root rel>, with
# no `.`, `..` or empty component, is prose (`.md`), and was added, modified
# or deleted: a rename or copy names no source path. The bundles are the
# directories directly under the root, those opening with `_` (the reserved
# accumulators) aside. Fails otherwise.
spec_scope_bundles() {
  SPEC_REL=$1 awk -F '\t' '
    $1 != "path" { next }
    {
      if ($3 != "ADDED" && $3 != "MODIFIED" && $3 != "DELETED") { out = 1; exit }
      p = $2; n = length(ENVIRON["SPEC_REL"])
      if (substr(p, 1, n + 1) != ENVIRON["SPEC_REL"] "/" || p !~ /\.md$/) { out = 1; exit }
      p = substr(p, n + 2)
      if (p == "" || ("/" p "/") ~ /\/(\.|\.\.)?\//) { out = 1; exit }
      if (index(p, "/") && substr(p, 1, 1) != "_") { b = substr(p, 1, index(p, "/") - 1); if (!(b in seen)) { seen[b] = 1; bs[++nb] = b } }
    }
    END { if (out) exit 1; for (i = 1; i <= nb; i++) print bs[i] }' "$2"
}

# bundle_signoff <repo> <head> <root rel> <bundle> <scratch dir>: print why
# <bundle> is not signed off at <head>, read from <repo>'s objects, or
# nothing when it is.
bundle_signoff() {
  local repo=$1 head=$2 rel=$3 b=$4 d=$5 st f entry rc got gd
  if ! [[ $b =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    printf 'not a spec identifier'
    return 0
  fi
  mkdir -p "$d" || mc_fail "cannot create a scratch directory"
  # cat-file blob refuses a tree or a missing path, so a partial file is removed.
  mc_untrusted_git -C "$repo" cat-file blob "$head:$rel/$b/requirements.md" >"$d/requirements.md" 2>/dev/null || rm -f "$d/requirements.md"
  if ! st=$(spec_parse_header_value "$d/requirements.md" Status 2>/dev/null) || [ -z "$st" ]; then
    printf 'its requirements.md status cannot be read at the head'
    return 0
  fi
  case $st in
    Ready | Active | Done) ;;
    *)
      printf 'its status at the head is %s' "$(sanitize_printable "$st")"
      return 0
      ;;
  esac
  for f in design.md tasks.md test-spec.md kickoff-brief.md; do
    mc_untrusted_git -C "$repo" cat-file blob "$head:$rel/$b/$f" >"$d/$f" 2>/dev/null || rm -f "$d/$f"
  done
  if ! [ -f "$d/kickoff-brief.md" ]; then
    printf 'it has no kickoff brief at the head'
    return 0
  fi
  # The sign-off stands only for the content it anchored: the brief's latest
  # anchor must recompute, by the sanctioned form it records, over the bundle
  # at the head, hashed in the bundle's own repository.
  rc=0
  entry=$(spec_parse_latest_anchor_entry "$d/kickoff-brief.md" 2>/dev/null) || rc=$?
  if [ "$rc" = 2 ]; then
    printf "its kickoff brief's latest anchor entry does not parse"
    return 0
  fi
  [ "$rc" = 0 ] || entry=''
  if [ -z "$entry" ]; then
    printf 'its kickoff brief records no anchor'
    return 0
  fi
  got=''
  case ${entry#*	} in
    "scripts/spec-anchor.sh $rel/$b" | "spec-anchor.sh $rel/$b")
      # Both script forms run only the shipped spec-anchor.sh, never the path
      # the brief names.
      got=$(cd "$repo" && mc_untrusted_git_env && /bin/sh "$script_dir/spec-anchor.sh" "$d" 2>/dev/null) || got=''
      ;;
    'git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin')
      gd=$(mc_untrusted_git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null) || gd=''
      [ -z "$gd" ] || got=$(cd "$d" && mc_untrusted_git_env && export GIT_DIR="$gd" \
        && git hash-object requirements.md design.md tasks.md test-spec.md | git hash-object --stdin) 2>/dev/null || got=''
      ;;
    *)
      printf "its kickoff brief's anchor uses a form this check does not recompute"
      return 0
      ;;
  esac
  if [ -z "$got" ]; then
    printf 'its anchor cannot be recomputed at the head'
  elif [ "${entry%%	*}" != "$got" ]; then
    printf 'its content at the head is not what the kickoff signed off (the anchor differs)'
  fi
}

