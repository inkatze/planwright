#!/bin/bash
# A suite reading a listed root variable without the clearing library: an
# operator shell's PLANWRIGHT_ROOT decides which scripts the case runs.
root=${PLANWRIGHT_ROOT:-$(pwd)}
/bin/sh "$root/scripts/resolve-root.sh" spec
