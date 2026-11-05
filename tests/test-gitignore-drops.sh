#!/bin/bash
# Tests for the repo .gitignore's binary-drop rules: an archive or office
# document dropped into a checkout must stay out of `git add -A`, wherever it
# lands, while ordinary source stays addable and no tracked file is shadowed.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

failures=0
ok() { echo "ok: $1"; }
bad() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

repo="$scratch/repo"
git init -q "$repo"
# Case-sensitive matching, as on Linux, so an upper-case drop is really tested.
git -C "$repo" config core.ignoreCase false
cp "$REPO_ROOT/.gitignore" "$repo/.gitignore"
mkdir -p "$repo/docs/nested"

drops="export.zip backup.tar backup.tar.gz backup.tar.xz bundle.tgz dump.gz notes.7z data.rar
report.pdf memo.docx memo.doc sheet.xlsx sheet.xls deck.pptx deck.ppt
docs/nested/export.zip docs/report.pdf REPORT.PDF Backup.Tar.Gz Deck.PPTX"
for f in $drops; do
  : >"$repo/$f"
done
: >"$repo/README.md"
: >"$repo/docs/nested/guide.md"

for f in $drops; do
  if git -C "$repo" check-ignore -q "$f"; then
    ok "binary drop is ignored: $f"
  else
    bad "binary drop is not ignored: $f"
  fi
done

git -C "$repo" add -A
staged=$(git -C "$repo" diff --cached --name-only)
for f in .gitignore README.md docs/nested/guide.md; do
  case "
$staged
" in
    *"
$f
"*) ok "ordinary file is still added by add -A: $f" ;;
    *) bad "ordinary file was not added by add -A: $f" ;;
  esac
done
for f in $drops; do
  case "
$staged
" in
    *"
$f
"*) bad "add -A staged a binary drop: $f" ;;
  esac
done

shadowed=$(git -C "$REPO_ROOT" ls-files -c -i --exclude-standard)
if [ -z "$shadowed" ]; then
  ok "no tracked file matches an ignore rule"
else
  bad "tracked files match an ignore rule: $shadowed"
fi

if [ "$failures" -eq 0 ]; then
  echo "All gitignore drop tests passed."
  exit 0
fi
echo "$failures gitignore drop test(s) failed." >&2
exit 1
