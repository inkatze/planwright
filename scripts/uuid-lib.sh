# shellcheck shell=sh
# uuid-lib.sh — a random version-4 uuid (sourced, never executed).

# uuid_v4 — print a fresh v4 uuid from /dev/urandom, lowercase; 1 with nothing
# printed when no randomness could be read.
uuid_v4() {
  uv_hex=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
  case $uv_hex in
    '' | *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#uv_hex}" -eq 32 ] || return 1
  printf '%s\n' "$uv_hex" | awk '{
    v = substr("89ab", (index("0123456789abcdef", substr($0, 17, 1)) - 1) % 4 + 1, 1)
    printf "%s-%s-4%s-%s%s-%s\n", substr($0, 1, 8), substr($0, 9, 4), substr($0, 14, 3), v, substr($0, 18, 3), substr($0, 21, 12)
  }'
}
