#!/bin/sh
# gen-slot-vectors.sh — write tests/unit/src/slot_vectors.kama: CRC16 and hash slots, from the cluster
# specification and from the servers themselves.
#
#   - The cluster specification (redis/docs, cluster-spec.md, pinned by SHA256): CRC16's check value ("Output for
#     "123456789": 31C3"), the crc16tab of its Appendix A, and each hash-tag example with the substring it says is
#     hashed.
#   - Every server in the matrix (tools/redis.sh list), started with cluster mode on in a throwaway container with
#     no network, asked CLUSTER KEYSLOT for: the specification's keys, brace edge cases, and 1000 keys of seeded
#     random bytes biased towards `{` and `}`. A server that answers any key differently from the others stops the
#     script.
#
# Run it, then `git diff` must be empty. Needs perl, curl, and podman or docker.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/tests/unit/src/slot_vectors.kama"
DOCS_COMMIT=eeff9cc955632aa199d1b1eabccd096d69b57878   # redis/docs: cluster-spec.md
SERVERS=$("$ROOT/tools/redis.sh" list)

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/cluster-spec.md" \
    "https://raw.githubusercontent.com/redis/docs/$DOCS_COMMIT/content/operate/oss_and_stack/reference/cluster-spec.md"
got=$(shasum -a 256 "$tmp/cluster-spec.md" | cut -d' ' -f1)
want=c2630e8a57a52d451f780afaaaee45f2a5018f15f18555d163e1c5aa0dbc84c2
[ "$got" = "$want" ] || { echo "gen-slot-vectors: cluster-spec.md sha256 $got, want $want" >&2; exit 1; }

# The keys, one per line in hex: the specification's, the edge cases, then the random ones.
perl -e '
    my @keys = ("123456789", "{user1000}.following", "{user1000}.followers", "user1000", "foo{}{bar}", "foo{{bar}}zap",
        "{bar", "foo{bar}{zap}", "bar", "", "{", "}", "{}", "}{", "{{}}", "{a", "a}", "{a}", "a", "a{b}c", "{}{a}", "a{}b",
        "{{a}}", "{a}{b}", "a{b{c}d}", "{\0}", "{ }", "{\xff}", "\xff\xfe", "{}}", "{{}");
    # A fixed LCG, so the keys are the same on every machine.
    my $s = 20261003;
    sub rnd { $s = ($s * 1103515245 + 12345) & 0x7fffffff; return $s >> 8; }
    for (1 .. 1000) {
        my $n = rnd() % 41; my $k = "";
        for (1 .. $n) { my $r = rnd() % 8; $k .= $r == 0 ? "{" : $r == 1 ? "}" : chr(rnd() % 256); }
        push @keys, $k;
    }
    print unpack("H*", $_), "\n" for @keys;
' > "$tmp/keys.hex"

if [ -n "${CONTAINER_RUNTIME:-}" ]; then RT=$CONTAINER_RUNTIME
elif command -v podman >/dev/null 2>&1; then RT=podman
elif command -v docker >/dev/null 2>&1; then RT=docker
else echo "gen-slot-vectors: neither podman nor docker found (set CONTAINER_RUNTIME)" >&2; exit 1
fi

# Runs in the container: CLUSTER KEYSLOT for every key in its __DATA__, pipelined, one slot per line out.
cat > "$tmp/ask.pl" <<'PERL'
use strict; use warnings; use IO::Socket::INET;
my $s;
for (1 .. 200) { $s = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => 7000, Proto => 'tcp'); last if $s; select(undef, undef, undef, 0.05); }
die "no server\n" unless $s;
binmode $s; $s->autoflush(1);
my @keys = map { chomp; pack('H*', $_) } <DATA>;
sub enc { my $o = '*' . scalar(@_) . "\r\n"; $o .= '$' . length($_) . "\r\n$_\r\n" for @_; return $o; }
print $s join('', map { enc('CLUSTER', 'KEYSLOT', $_) } @keys);
my $buf = ''; my @slots;
while (@slots < @keys) {
    if ($buf =~ s/\A:(\d+)\r\n//) { push @slots, $1; next; }
    die "unexpected reply: " . substr($buf, 0, 60) . "\n" if $buf =~ /\A[^:]/ || $buf =~ /\A:\d*[^\d\r]/;
    my $n = sysread($s, my $chunk, 65536); die "eof\n" unless $n; $buf .= $chunk;
}
print "$_\n" for @slots;
PERL

for server in $SERVERS; do
    case "$server" in
        redis-*)  image=docker.io/library/redis:${server#redis-} ;;
        valkey-*) image=docker.io/valkey/valkey:${server#valkey-} ;;
    esac
    { cat "$tmp/ask.pl"; echo "__DATA__"; cat "$tmp/keys.hex"; } | "$RT" run --rm -i --network none "$image" sh -c '
        cat > /tmp/ask.pl
        redis-server --port 7000 --cluster-enabled yes --cluster-config-file /tmp/nodes.conf --save "" --appendonly no \
            --daemonize yes >/dev/null
        redis-server --version | sed -n "s/.*[Ss]erver v=\([0-9.]*\) .*/\1/p"
        perl /tmp/ask.pl' > "$tmp/$server.slots"
done

cat > "$tmp/gen.pl" <<'PERL'
use strict; use warnings;
my ($tmp, $out, $docsCommit, @servers) = @ARGV;
open my $f, '<', "$tmp/cluster-spec.md" or die; my $spec = do { local $/; <$f> };

$spec =~ /^\* Output for "123456789": ([0-9A-F]{4})$/m or die "gen-slot-vectors: no CRC16 check value\n";
my $check = hex $1;
$spec =~ /crc16tab\[256\]\s*=\s*\{(.*?)\};/s or die "gen-slot-vectors: no crc16tab\n";
my @table = map { hex } ($1 =~ /0x([0-9a-fA-F]{4})/g);
die "gen-slot-vectors: crc16tab has " . scalar(@table) . " entries\n" unless @table == 256;

# Each hash-tag example: the key, and the bytes the specification says are hashed.
my @tags;
while ($spec =~ /^\* The two keys `([^`]+)` and `([^`]+)` will hash to the same hash slot since only the substring `([^`]+)` will be hashed/mg) {
    push @tags, [$1, $3], [$2, $3];
}
while ($spec =~ /^\* For the key `([^`]+)` the whole key will be hashed/mg) { push @tags, [$1, $1]; }
while ($spec =~ /^\* For the key `([^`]+)` the substring `([^`]+)` will be hashed/mg) { push @tags, [$1, $2]; }
die "gen-slot-vectors: only " . scalar(@tags) . " hash-tag examples\n" unless @tags == 5;

open my $k, '<', "$tmp/keys.hex" or die; my @keys = map { chomp; $_ } <$k>;
my (@slots, @versions);
for my $server (@servers) {
    open my $s, '<', "$tmp/$server.slots" or die; my @got = map { chomp; $_ } <$s>;
    my $number = shift @got;
    die "gen-slot-vectors: $server gave no version\n" unless defined $number && $number =~ /^\d+\.\d+\.\d+$/;
    push @versions, ($server =~ s/-.*//r) . "-$number";
    die "gen-slot-vectors: $server answered " . scalar(@got) . " of " . scalar(@keys) . " keys\n" unless @got == @keys;
    if (!@slots) { @slots = @got; next; }
    for my $i (0 .. $#keys) {
        die "gen-slot-vectors: key $keys[$i] is slot $slots[$i] on $servers[0] and $got[$i] on $server\n" unless $got[$i] == $slots[$i];
    }
}

sub lit { my $s = shift; die "gen-slot-vectors: unexpected text '$s'\n" if $s =~ /[^\x20-\x7e]/ || $s =~ /[\\"]|\$\{/; return "\"$s\""; }
open my $o, '>', $out or die;
my $who = join(', ', @versions);
print $o <<"HEAD";
// GENERATED by tools/gen-slot-vectors.sh. Do not edit: change the script and run it again.
//
// CRC16 and hash slots. From the cluster specification (redis/docs $docsCommit, cluster-spec.md): the CRC16
// check value, the crc16tab of its Appendix A, and its hash-tag examples (a key and the substring it says is
// hashed). From the servers, asked CLUSTER KEYSLOT live with cluster mode on, all answering alike: $who.
import { std::collections::DynamicArray };
export { crcCheckValue, crcSpecTable, tagKeys, tagHashed, slotKeys, slotWant };

fn int64 crcCheckValue() { return ${check}i64; }

HEAD
sub column {
    my ($fn, $type, @items) = @_;
    print $o "fn DynamicArray<$type> $fn() {\n    DynamicArray<$type> v = DynamicArray.empty();\n";
    print $o "    v.add(item: $_);\n" for @items;
    print $o "    return v;\n}\n\n";
}
column('crcSpecTable', 'int64', map { "${_}i64" } @table);
column('tagKeys', 'string', map { lit($_->[0]) } @tags);
column('tagHashed', 'string', map { lit($_->[1]) } @tags);
column('slotKeys', 'string', map { "\"$_\"" } @keys);
column('slotWant', 'int64', map { "${_}i64" } @slots);
close $o;
printf "gen-slot-vectors: %d keys, %d tag examples, from %s into %s\n", scalar(@keys), scalar(@tags), $who, $out;
PERL

# shellcheck disable=SC2086
perl "$tmp/gen.pl" "$tmp" "$OUT" "$DOCS_COMMIT" $SERVERS
