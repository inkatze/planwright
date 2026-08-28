#!/bin/sh
# seed-purged-identifiers.sh — the human provisioning path for the
# purged-identifier guard (guard-coverage Task 3; D-5; REQ-B1.2).
#
# The identifiers this repo purged from its history are supplied here, by a
# human, out of band. They are hashed on the way in and never written down:
# the committed seed file holds SHA-256 over the normalized form and nothing
# else, so the plaintext exists only in the operator's head and in this
# process for the moment it takes to hash it.
#
# NON-LOGGING BY CONSTRUCTION. The plaintext is read from STDIN only. It is
# never accepted as an argument (argv is visible in `ps` and in shell
# history), never echoed back by this script, and never printed on any success
# or error path — a rejected line is reported by its position, not its content.
# What this does NOT do is turn off terminal echo: type at the prompt and your
# own terminal displays it, so treat a shared screen accordingly. Give it a
# pipe or a heredoc, or type into it interactively:
#
#     scripts/seed-purged-identifiers.sh          # then type, one per line, ^D
#     scripts/seed-purged-identifiers.sh --add    # merge into the existing seeds
#
# In an interactive shell, prefix the command with a space when your shell is
# configured to skip history for such lines; nothing typed at the prompt
# reaches history in either case, since only the command name is a command.
#
# NORMALIZATION. Identical to the scanner's, and that is the contract between
# them: an identifier is split into maximal [A-Za-z0-9] runs, lowercased, and
# concatenated with no separator. `Acme-Internal`, `acme_internal` and
# `acme.internal` therefore seed one and the same hash. See
# docs/purged-identifier-guard.md.
#
# THE FLOOR. The written file declares `min-seeds: <count>` and
# `max-words: <n>`, both derived from what was ingested. The scanner fails
# closed if the hash count ever drops below the declared floor, so deleting
# seed lines cannot quietly disarm the guard (REQ-B1.2, REQ-H1.3); lowering
# the floor is possible but is a visible diff on a tracked file.
#
# Usage: seed-purged-identifiers.sh [--add] [--seed-file <path>]
#   default   replace the seed file with exactly what stdin supplied
#   --add     merge stdin into the existing seed file, deduplicated
# Exit: 0 written · 2 usage, environment, or rejected input.
#
# Portable POSIX sh plus perl with Digest::SHA.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: seed-purged-identifiers.sh [--add] [--seed-file <path>]" >&2
  echo "  identifiers are read from stdin, one per line; never from arguments" >&2
  exit 2
}

mode=replace
seed_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --add)
      mode=add
      shift
      ;;
    --seed-file)
      [ "$#" -ge 2 ] || usage
      [ -z "$seed_file" ] || usage
      seed_file="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

if ! top=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "seed-purged-identifiers: not inside a git work tree; cannot resolve the seed file" >&2
  exit 2
fi
[ -n "$seed_file" ] || seed_file="$top/config/purged-identifiers.seed"

if ! command -v perl >/dev/null 2>&1 || ! perl -MDigest::SHA -e 1 >/dev/null 2>&1; then
  echo "seed-purged-identifiers: perl with Digest::SHA is required" >&2
  exit 2
fi

if [ -t 0 ]; then
  echo "seed-purged-identifiers: reading identifiers from stdin, one per line." >&2
  echo "  Nothing you type is printed back, stored in plaintext, taken as an" >&2
  echo "  argument, or written to shell history. Your TERMINAL still shows what" >&2
  echo "  you type -- this script does not turn echo off." >&2
  echo "  End with Ctrl-D." >&2
fi

# The whole job runs in one perl process: the plaintext is read, hashed, and
# dropped without ever reaching another program's argv or a temporary file
# holding readable text. The output file is written via a temp file in the
# same directory and renamed, so an interrupted run cannot leave a truncated
# seed file the scanner would then fail closed on.
# shellcheck disable=SC2016 # the $-sigils below are perl variables, not shell expansions
write_program='
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

my ($seed_path, $mode) = @ARGV;

sub bail {
    print STDERR "seed-purged-identifiers: $_[0]\n";
    exit 2;
}

# Existing hashes, kept only when merging. Parsed with the same grammar the
# scanner enforces, so --add cannot silently carry a malformed file forward.
my %hash;
my $prev_max_words = 0;
if ($mode eq "add") {
    open my $fh, "<", $seed_path or bail("--add needs an existing seed file at $seed_path");
    my $lineno = 0;
    while (my $line = <$fh>) {
        $lineno++;
        $line =~ s/\r?\n\z//;
        next if $line =~ /\A\s*\z/ || $line =~ /\A\s*#/;
        if ($line =~ /\Amax-words:[ ]([0-9]{1,2})\z/) { $prev_max_words = $1 + 0; next }
        next if $line =~ /\Amin-seeds:[ ][0-9]{1,4}\z/;
        bail("existing seed line $lineno is not a 64-char lowercase hex hash")
            unless $line =~ /\A[0-9a-f]{64}\z/;
        $hash{$line} = 1;
    }
    close $fh;
}

my $max_words = $prev_max_words;
my $read = 0;
my $lineno = 0;
while (my $line = <STDIN>) {
    $lineno++;
    $line =~ s/\r?\n\z//;
    next if $line =~ /\A\s*\z/;
    my @words = map { lc } ($line =~ /([A-Za-z0-9]+)/g);
    # Reported by position only: the rejected line is the plaintext.
    bail("stdin line $lineno holds no alphanumeric characters to normalize")
        unless @words;
    my $normalized = join("", @words);
    # A very short normalized form would match a common English word run
    # everywhere in the tree and turn the guard into noise. Refused rather
    # than seeded, so an overblocking guard is never the surprise.
    bail("stdin line $lineno normalizes to fewer than 4 characters; too short to seed safely")
        if length($normalized) < 4;
    bail("stdin line $lineno normalizes to more than 8 words; beyond the scanner window")
        if @words > 8;
    $max_words = @words if @words > $max_words;
    $hash{ sha256_hex($normalized) } = 1;
    $read++;
}

bail("stdin supplied no identifiers; refusing to write an empty seed file") if $read == 0;

my @sorted = sort keys %hash;
my $count  = scalar @sorted;

my $tmp = "$seed_path.tmp.$$";
open my $out, ">", $tmp or bail("cannot write $tmp: $!");
print {$out} <<"HEADER";
# planwright purged-identifier seed list (guard-coverage Task 3; D-5;
# REQ-B1.1, REQ-B1.2). Generated by scripts/seed-purged-identifiers.sh --
# do not hand-edit.
#
# Each bare line below is SHA-256 over one NORMALIZED purged identifier: its
# maximal [A-Za-z0-9] runs, lowercased and concatenated. No plaintext is
# recorded here, and the plaintext is provisioned only through that script,
# from stdin. The hashes are offline-guessable by anyone who can guess the
# names -- an accepted residual (D-5): the threat model is accidental
# reintroduction, not adversarial secrecy.
#
# min-seeds is the non-vacuity floor. scripts/check-purged-identifiers.sh
# fails closed when the hash count drops below it, when a directive is
# missing, or when any line is not a bare hash, so the guard cannot run
# green on an emptied or malformed list.
# max-words is the widest identifier in words; the scanner joins runs of up
# to that many consecutive words when building candidates.
#
# Rules and the in/out-of-scope shape tables: docs/purged-identifier-guard.md
min-seeds: $count
max-words: $max_words
HEADER
print {$out} "$_\n" for @sorted;
close $out or bail("cannot close $tmp: $!");
rename $tmp, $seed_path or bail("cannot rename $tmp to $seed_path: $!");

# Counts only. Nothing derived from the plaintext is printed.
print "seed-purged-identifiers: wrote $count seed hash(es) to $seed_path (min-seeds: $count, max-words: $max_words).\n";
print "seed-purged-identifiers: commit the seed file; the plaintext stays out of the repo.\n";
exit 0;
'

perl -e "$write_program" -- "$seed_file" "$mode"
exit
