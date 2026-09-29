# shellcheck shell=bash
# golden-replay.sh — the comparator behind the spec-location golden fixture
# (sourced, never executed).
#
# A record file is free-form comment text up to the first `@@ ` line, then one
# record per `@@ <probe> <vantage>` header, its body being every line up to the
# next header. A change set carries a third header field, the named correction
# the changed output belongs to. Header fields are names, `[A-Za-z0-9_.-]+`,
# never `.` or `..`, because each one becomes a file name. The baseline is never
# regenerated; a migration task that changes a probe's output declares the new
# output in its own set.
#
# Replay rules:
#   * the expected output of a probe is the baseline's, overridden by every
#     declared set that lists it, applied in numeric task-id order (6 before
#     6.5 before 10);
#   * a set entry naming a probe the baseline lacks, a correction absent from
#     the registry, or a correction owned by another task (or by the baseline)
#     is an error;
#   * every correction the registry assigns to a task whose set is declared must
#     appear in that set, so a declared set cannot silently omit its correction;
#   * the actual recording must carry exactly the baseline's probes, each equal
#     to its expected output.
#
# Usage:
#   . tests/lib/golden-replay.sh
#   golden_replay <baseline> <changes-dir> <corrections.tsv> <actual>
# Prints one line per failure (a mismatch is followed by a unified diff), with
# control bytes stripped, and returns non-zero when any failure was found.

# _gr_split <record-file> <out-dir> <fields> — write each record body to
# <out-dir>/<probe>@<vantage> and list the header fields on stdout, one record
# per line. Returns non-zero on a malformed or duplicate header.
_gr_split() {
  mkdir -p "$2" || return 1
  awk -v out="$2" -v want="$3" '
    function fail(msg) { print "golden-replay: " FILENAME ":" FNR ": " msg > "/dev/stderr"; bad = 1 }
    /^@@ / {
      if (file != "") close(file)
      file = ""
      n = split(substr($0, 4), f, " ")
      if (n != want) { fail("header needs " want " fields"); next }
      for (i = 1; i <= n; i++)
        if (f[i] !~ /^[A-Za-z0-9_.-]+$/ || f[i] == "." || f[i] == "..") { fail("header field is not a name"); next }
      key = f[1] "@" f[2]
      if (key in seen) { fail("duplicate record " f[1] " " f[2]); next }
      seen[key] = 1
      file = out "/" key
      printf "" > file
      print (want == 3) ? f[1] " " f[2] " " f[3] : f[1] " " f[2]
      next
    }
    file != "" { print > file }
    END { if (file != "") close(file); exit bad }
  ' "$1"
}

golden_replay() {
  _gr_replay "$@" 2>&1 | tr -d '\000-\010\013-\037\177\200-\237'
  return "${PIPESTATUS[0]}"
}

_gr_replay() {
  gr_baseline=$1 gr_changes=$2 gr_registry=$3 gr_actual=$4
  gr_fail=0
  for gr_in in "$gr_baseline" "$gr_registry" "$gr_actual"; do
    [ -r "$gr_in" ] || {
      echo "golden-replay: $gr_in is missing or unreadable"
      return 2
    }
  done
  gr_work=$(mktemp -d "${TMPDIR:-/tmp}/golden-replay.XXXXXX") || return 2

  _gr_split "$gr_baseline" "$gr_work/expected" 2 >"$gr_work/baseline.keys" || gr_fail=1
  _gr_split "$gr_actual" "$gr_work/actual" 2 >"$gr_work/actual.keys" || gr_fail=1
  # An empty baseline would make every recording, empty ones included, match.
  [ -s "$gr_work/baseline.keys" ] || {
    echo "golden-replay: $gr_baseline holds no records"
    gr_fail=1
  }

  # Registry rows: <correction> TAB <owner: a task id or `baseline`> TAB ...
  if ! awk -F '\t' '!/^#/ && NF >= 2 { print $1 " " $2; n++ } END { exit !n }' \
    "$gr_registry" >"$gr_work/registry"; then
    echo "golden-replay: $gr_registry holds no correction rows"
    rm -rf "$gr_work"
    return 2
  fi

  # Declared sets, in task-id order: changes/task-<id>.txt.
  # Sorted on the id's own major and minor parts, never on the path, which
  # may carry dots of its own.
  : >"$gr_work/sets"
  for gr_set in "$gr_changes"/task-*.txt; do
    [ -f "$gr_set" ] || continue
    gr_id=${gr_set##*/task-}
    gr_id=${gr_id%.txt}
    gr_minor=0
    case $gr_id in *.*) gr_minor=${gr_id#*.} ;; esac
    printf '%s %s %s %s\n' "${gr_id%%.*}" "$gr_minor" "$gr_id" "$gr_set" >>"$gr_work/sets"
  done
  sort -k1,1n -k2,2n "$gr_work/sets" | cut -d ' ' -f 3- >"$gr_work/sets.sorted"

  : >"$gr_work/used"
  while read -r gr_id gr_set; do
    _gr_split "$gr_set" "$gr_work/set-$gr_id" 3 >"$gr_work/set-$gr_id.keys" || gr_fail=1
    while read -r gr_probe gr_vantage gr_corr; do
      gr_owner=$(awk -v c="$gr_corr" '$1 == c { print $2; exit }' "$gr_work/registry")
      if [ -z "$gr_owner" ]; then
        echo "golden-replay: task $gr_id declares $gr_probe $gr_vantage under unregistered correction '$gr_corr'"
        gr_fail=1
      elif [ "$gr_owner" != "$gr_id" ]; then
        echo "golden-replay: task $gr_id declares correction '$gr_corr', which the registry assigns to $gr_owner"
        gr_fail=1
      fi
      if [ ! -f "$gr_work/expected/$gr_probe@$gr_vantage" ]; then
        echo "golden-replay: task $gr_id declares $gr_probe $gr_vantage, which the baseline does not record"
        gr_fail=1
        continue
      fi
      cp "$gr_work/set-$gr_id/$gr_probe@$gr_vantage" "$gr_work/expected/$gr_probe@$gr_vantage" || {
        echo "golden-replay: could not apply task $gr_id's $gr_probe $gr_vantage"
        gr_fail=1
        continue
      }
      printf '%s %s\n' "$gr_id" "$gr_corr" >>"$gr_work/used"
    done <"$gr_work/set-$gr_id.keys"
  done <"$gr_work/sets.sorted"

  while read -r gr_corr gr_owner; do
    [ "$gr_owner" = baseline ] && continue
    awk -v t="$gr_owner" '$1 == t { found = 1 } END { exit !found }' "$gr_work/sets.sorted" || continue
    if ! awk -v t="$gr_owner" -v c="$gr_corr" '$1 == t && $2 == c { found = 1 } END { exit !found }' "$gr_work/used"; then
      echo "golden-replay: correction '$gr_corr' is absent from task $gr_owner's declared set"
      gr_fail=1
    fi
  done <"$gr_work/registry"

  if ! diff -q "$gr_work/baseline.keys" "$gr_work/actual.keys" >/dev/null 2>&1; then
    echo "golden-replay: the recorded probes differ from the baseline's:"
    diff "$gr_work/baseline.keys" "$gr_work/actual.keys" | sed 's/^/  /'
    gr_fail=1
  fi
  # One comparison for the common all-equal case; per-probe diffs only when
  # something differs.
  if ! diff -rq "$gr_work/expected" "$gr_work/actual" >/dev/null 2>&1; then
    while read -r gr_probe gr_vantage; do
      gr_key=$gr_probe@$gr_vantage
      [ -f "$gr_work/actual/$gr_key" ] || continue
      if ! diff -q "$gr_work/expected/$gr_key" "$gr_work/actual/$gr_key" >/dev/null 2>&1; then
        echo "golden-replay: $gr_probe $gr_vantage differs from its expected output:"
        diff -u "$gr_work/expected/$gr_key" "$gr_work/actual/$gr_key" | tail -n +3 | sed 's/^/  /'
        gr_fail=1
      fi
    done <"$gr_work/baseline.keys"
  fi

  rm -rf "$gr_work"
  return "$gr_fail"
}
