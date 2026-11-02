# Usage-header skill

Mention `scripts/nohdr-tool.sh` by name, source a library with
`. scripts/lib-tool.sh --any` or `source scripts/nohdr-tool.sh`, and name
scripts/nohdr-tool.sh --any in plain prose: none of them is checked. Nor is
`git add scripts/nohdr-tool.sh`, where the path is an argument.

Run `scripts/sub-tool.sh run --spec <dir> <task>...` for a unit, or
`<root>/scripts/sub-tool.sh run --spec <dir> --mode slow 5 6` across a
wrapped span, or `scripts/sub-tool.sh --help`.

```sh
scripts/sub-tool.sh list --all
"$ROOT"/scripts/sub-tool.sh run --spec=specs/x --dry-run 5 6 >/dev/null 2>&1
out="$(<root>/scripts/sub-tool.sh run --spec "$(pwd)" 7)"
$ scripts/sub-tool.sh -h
scripts/sub-tool.sh run --spec <dir> \
  --dry-run <task>
```
