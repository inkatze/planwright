# shellcheck shell=sh
# spec-id-lib.sh — the spec-addressing alias mapper for the identity seams
# (sourced, never executed).
#
# A seam that names a spec (a dispatch, fetch, fence, marker, trailer, or
# consume argument) takes the bare identifier as its canonical form and
# `specs/<id>` as an alias for it, either one carrying at most one trailing
# slash, as shell completion leaves it. In the alias, `specs/` is a namespace,
# not a directory: the mapper reads no filesystem and never depends on where
# the spec root lies. A script that operates on a bundle directory takes the
# directory instead and does not source this.
#
# Each seam keeps its own identifier grammar and message: the mappers only
# reshape, and anything outside the accepted forms passes through unchanged so
# that grammar refuses it (a bundle-file path, a deeper path, a second
# trailing slash). The result is assigned rather than printed: a command
# substitution would strip a trailing newline and hand the grammar a value
# it should have refused.

# spec_id_canon <value> — set SPEC_ID to the identifier <value> names when it
# is <id>, <id>/, specs/<id>, or specs/<id>/, else to <value> unchanged. A
# bare `specs/` is the alias with its identifier missing, never the
# identifier `specs`.
spec_id_canon() {
  SPEC_ID=$1
  case $1 in
    specs/) return 0 ;;
  esac
  _sic=${1%/}
  case $_sic in
    specs/*) _sic=${_sic#specs/} ;;
  esac
  case $_sic in
    '' | */*) ;;
    *) SPEC_ID=$_sic ;;
  esac
}

# spec_ref_canon <value> — set SPEC_REF to a `<spec>/<id>` task ref whose spec
# segment may be given as the alias (`specs/<spec>/<id>`), else to <value>
# unchanged.
spec_ref_canon() {
  SPEC_REF=$1
  case $1 in
    specs/*/*) SPEC_REF=${1#specs/} ;;
  esac
}
