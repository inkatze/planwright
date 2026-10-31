#!/bin/sh
# feat-tool.sh — a fixture whose header uses every rule of the grammar.
#
# Usage: feat-tool.sh show <the spec dir> [--json] < events.jsonl
#   feat-tool.sh send (--to <socket path> | --to-worker <worker>)
#       --message-file <path>
#   feat-tool.sh tag <id> on|off <label>
#   feat-tool.sh pick [-n|--name <v>] [<a> | <b>]
#   feat-tool.sh exec -- <cmd>...
#   feat-tool.sh rows [--tag <t>]... [-1]
#   feat-tool.sh wait (--pid <pid> |
#       --session <id>)   (exactly one)
#   scripts/feat-tool.sh peek <id>
:
