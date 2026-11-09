#!/bin/bash
# The shipped model tier for the review steps (polish, self-review) is Sonnet.
# Read the real config/defaults.yml: the default is the contract, not a fixture.
set -u

here=$(cd "$(dirname "$0")" && pwd)
cfg="$here/../config/defaults.yml"
fail=0

for key in allocation_model_step_polish allocation_model_step_self_review; do
  val=$(sed -n "s/^$key: *//p" "$cfg")
  if [ "$val" != "sonnet" ]; then
    echo "FAIL: $key ships '$val', want 'sonnet'" >&2
    fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "ok: review step models ship sonnet"
exit "$fail"
