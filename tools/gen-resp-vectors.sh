#!/bin/sh
# gen-resp-vectors.sh — write tests/unit/src/resp_vectors.kama: RESP inputs, and what hiredis makes of each.
#
# Where the inputs come from:
#   - hiredis v1.4.1's own reader tests (test.c, test_reply_reader): tools/resp-dump.c compiles test.c with
#     redisReaderFeed wrapped and records every byte those tests feed, under the names they print;
#   - every example in the RESP3 specification (redis-specifications, RESP3.md) and in the protocol page of the
#     Redis docs (protocol-spec.md);
#   - the bytes each server in the matrix (tools/redis.sh list) sends for a list of commands under RESP2 and RESP3,
#     DEBUG PROTOCOL's every type included, asked live in a throwaway container with no network;
#   - a hostile list in this script: every byte as a type byte, the edges of each type's grammar, counts and
#     lengths out of range, replies cut short. These are inputs only.
#
# What each input should read as — never typed by hand:
#   - hiredis's reading of it (tools/resp-dump.c read), when it is in the part of RESP hiredis reads;
#   - for an input using what hiredis lacks (blob errors, streamed strings and aggregates, attributes attached to
#     their value), hiredis's reading of the equivalent input `canon` below derives: `!` as `-`, a streamed string
#     as its bulk, a streamed aggregate as its counted form, and an attribute and its value as a marked array whose
#     reading is turned back into `attr[…]`. Such a case's note says so;
#   - for a deliberate difference from hiredis, the rule in %DEVIATIONS, with its reason. The script dies on any
#     other difference between hiredis's reading and the expectation, so none goes unexplained.
#
# Every upstream file is pinned by SHA256, and the script dies on a mismatch. Run it, then `git diff` must be
# empty unless a server image moved (the header names each server's version). Needs a C compiler, perl, curl,
# and podman or docker.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/tests/unit/src/resp_vectors.kama"

HIREDIS_COMMIT=616f2286ba5503f74ae96e720623fa11dbc690af     # hiredis v1.4.1
SPEC_COMMIT=1252427cdbc497f66a7f8550c6b5f2f35367dc92        # redis-specifications: RESP3.md v1.6
DOCS_COMMIT=1bf86d970dc215d14aea59058fff194c10742dc9        # redis/docs: protocol-spec.md
SERVERS=$("$ROOT/tools/redis.sh" list)

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/hiredis/adapters"

fetch() {  # fetch <url> <dest> <sha256>
    curl -fsSL -o "$2" "$1"
    got=$(shasum -a 256 "$2" | cut -d' ' -f1)
    [ "$got" = "$3" ] || { echo "gen-resp-vectors: $1 sha256 $got, want $3" >&2; exit 1; }
}

H="https://raw.githubusercontent.com/redis/hiredis/$HIREDIS_COMMIT"
while read -r f sha; do
    fetch "$H/$f" "$tmp/hiredis/$f" "$sha"
done <<'EOF'
read.c 315428510a88664650036db7ff05f81869b42a6e90f914018060362fe7a1d29b
read.h bf55c9af96d2cc5afb40baae4d8e796eb382ec08741ce7750035dba61c0d18a6
test.c 06a5b4e72635a9ac58dcb069d305c4696bc918fc23c959bfb87bf59d0b1e163d
hiredis.c d0a55d5673d37304484518d5f6ea32683020177ff069510d3bd43a8cba86fc74
hiredis.h d4f82155e4a02c3cc1eab28cfe5d5719047f3e4124e0c8dfd28dd0ad9d6aa451
sds.c 52eb0d2158ac355315082e60fbe0cfd816792f404cd716f18cce0b095140be5d
sds.h eb2383c4ddb58991e3429614673b1787a8302a3465883e234f004f0d8368f7fd
sdsalloc.h 894bc4ed039c744bf701e7eb9d5954e21b4633a15bf3258a0d6231e5b12071f1
alloc.c 7c35dc4905d2d00921207f18905558bb9aff8663358ac8f4ceac30dcd1252f88
alloc.h b4b8e85d075838306560a7a9c3256afa86015269e227290dc294df7cf4d259ce
fmacros.h 2898a5dc6e80dd0514511dfa717d7a5f56dda242115f77b82930fe133db20ec7
win32.h 6c6708013b7368b1033db694169ed3235a357314b09bde08771aa80231221211
ffc.h 1df02f4a22e28ad8057c7c64a82b4bf3e9e30b405cc64252acab1fe591760868
net.c 247673c23daa3c22a0da55d97215f8cae3fcbe0a491e3b8bf81134fe0818b0ff
net.h 083e63016b5e7fc37674be8fe13b5f246a2664ae2d56b0288685609928fd3e4e
async.c ede2a8f019d3b372d16409e40c3174dc8dceaf8eb3fc0924fc84f362eee632fb
async.h d0cc2dd4a746ea12af8d74bcfff943cbec83dce3770de8d3909ce6978e53f328
async_private.h 1dab90250c9c78cc88ce9744a062e496fd4d4a507bf83387b6c9b4d6c95d2f98
dict.c 3d03513f88eca566db6f6c49b79c2b7bb20481ad1b8afda7e28903dc889f825a
dict.h 5aa2b5e4479e5578cef20b84b1dfca0d5c4fe1a866052d732458f032ed07b3e1
sockcompat.c 11c57477a67bcf66f3e3944156e72bd686e9b515134fa9b2b0c4f5121a721570
sockcompat.h dc9d2ec2c4dabcb0e464fe72454ca6e8e58ff66d9dcd7f254d9465c97707715a
adapters/poll.h c33cd0444393c52258be029fdbc6a302d9445136356823364ae403f84ffbcca5
EOF
fetch "https://raw.githubusercontent.com/redis/redis-specifications/$SPEC_COMMIT/protocol/RESP3.md" "$tmp/RESP3.md" \
    0aeda1fbed16511e8202a47424af24999ad0a3dfc6243968f2a189109d8341bf
fetch "https://raw.githubusercontent.com/redis/docs/$DOCS_COMMIT/content/develop/reference/protocol-spec.md" "$tmp/protocol-spec.md" \
    d03d9067bca09dee8e54dca221c7caf13f5c211d17ac1a4d071cf0593a373e9e

# hiredis as it ships: its own reader (ffc doubles, the 1.4.1 default), no TLS.
cp "$ROOT/tools/resp-dump.c" "$tmp/hiredis/"
( cd "$tmp/hiredis" && ${CC:-cc} -std=gnu99 -O1 -w -I. -o "$tmp/resp-dump" resp-dump.c read.c sds.c alloc.c hiredis.c \
    net.c async.c sockcompat.c -lm )
"$tmp/resp-dump" capture > "$tmp/hiredis.tsv" 2>/dev/null || { echo "gen-resp-vectors: hiredis's reader tests failed" >&2; exit 1; }

# ---- the servers, asked live ----
if [ -n "${CONTAINER_RUNTIME:-}" ]; then RT=$CONTAINER_RUNTIME
elif command -v podman >/dev/null 2>&1; then RT=podman
elif command -v docker >/dev/null 2>&1; then RT=docker
else echo "gen-resp-vectors: neither podman nor docker found (set CONTAINER_RUNTIME)" >&2; exit 1
fi

# Runs in the container, against a server it started with no network: the setup commands, then each command under
# RESP2 and under RESP3, printing <protocol> <command> TAB <the bytes the server sent, in hex>. A command's reply
# ends where the PING sent after it answers.
cat > "$tmp/ask.pl" <<'PERL'
use strict; use warnings; use IO::Socket::INET;
my $s;
for (1 .. 200) { $s = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => 7000, Proto => 'tcp'); last if $s; select(undef, undef, undef, 0.05); }
die "no server\n" unless $s;
binmode $s; $s->autoflush(1);
sub enc { my $o = '*' . scalar(@_) . "\r\n"; $o .= '$' . length($_) . "\r\n$_\r\n" for @_; return $o; }
sub ask {
    print $s enc(@_), enc('PING');
    my $buf = '';
    until ($buf =~ /\+PONG\r\n\z/) { my $n = sysread($s, my $chunk, 65536); die "eof\n" unless $n; $buf .= $chunk; }
    substr($buf, -7) = '';
    return $buf;
}
ask(@$_) for (['SET', 'k', 'v'], ['HSET', 'h', 'f1', 'v1', 'f2', 'v2'], ['SADD', 's', '1', '2', '3'],
              ['ZADD', 'z', '1.5', 'a', '2', 'b'], ['XADD', 'x', '1-1', 'f', 'v']);
for my $proto (2, 3) {
    my @cmds = (['HELLO', $proto],
        (map { ['DEBUG', 'PROTOCOL', $_] } qw(string integer double bignum null array set map attrib push verbatim true false)),
        ['GET', 'k'], ['GET', 'missing'], ['INCRBYFLOAT', 'f', '1.5'], ['HGETALL', 'h'], ['SMEMBERS', 's'],
        ['ZRANGE', 'z', '0', '-1', 'WITHSCORES'], ['ZSCORE', 'z', 'a'], ['XRANGE', 'x', '-', '+'],
        ['CONFIG', 'GET', 'maxmemory'], ['LPUSH', 'k', 'x'], ['NOSUCHCOMMAND'], ['COMMAND', 'DOCS', 'GET']);
    for my $c (@cmds) { my $r = ask(@$c); print join(' ', "RESP$proto", @$c), "\t", unpack('H*', $r), "\n"; }
}
PERL

: > "$tmp/live.tsv"
for server in $SERVERS; do
    case "$server" in
        redis-*)  image=docker.io/library/redis:${server#redis-} ;;
        valkey-*) image=docker.io/valkey/valkey:${server#valkey-} ;;
    esac
    # enable-debug-command is 7.0's; 6.2 refuses the directive and has no gate on DEBUG.
    "$RT" run --rm -i --network none "$image" sh -c 'cat > /tmp/ask.pl
        start() { redis-server --port 7000 --save "" --appendonly no --daemonize yes "$@" >/dev/null 2>&1; }
        start --enable-debug-command yes || start
        redis-server --version | sed -n "s/.*[Ss]erver v=\([0-9.]*\) .*/\1/p"
        perl /tmp/ask.pl' < "$tmp/ask.pl" > "$tmp/one.txt"
    # Valkey 7.2 prints only "Server v=…", so the product comes from the matrix's name.
    number=$(head -n 1 "$tmp/one.txt")
    case "$number" in [0-9]*.[0-9]*) ;; *) echo "gen-resp-vectors: $server gave no version" >&2; exit 1 ;; esac
    version="${server%%-*}-$number"
    tail -n +2 "$tmp/one.txt" | sed "s/^/$version	/" >> "$tmp/live.tsv"
done

cat > "$tmp/gen.pl" <<'PERL'
use strict; use warnings; no warnings 'recursion';
my ($tmp, $out, $hiredisCommit, $specCommit, $docsCommit, $wantServers) = @ARGV;
my $DEFAULT_MAX = 4294967295;

# ---- the cases: name, source, maxelements, bytes ----
my @cases;
sub add { my ($name, $source, $max, $bytes) = @_; push @cases, { name => $name, source => $source, max => $max, bytes => $bytes }; }

# hiredis's reader tests. A test that feeds several readers has a case per reader, numbered.
{
    open my $f, '<', "$tmp/hiredis.tsv" or die; my %seen;
    while (<$f>) {
        chomp; my ($name, $max, $hex) = split /\t/, $_, 3; $hex //= '';
        my $n = ++$seen{$name};
        add($n > 1 ? "$name #$n" : $name, "hiredis test.c", $max, pack('H*', $hex));
    }
    my %count; $count{$_->{name} =~ s/ #\d+$//r}++ for @cases;
    for my $c (@cases) { $c->{name} .= " #1" if $c->{name} !~ / #\d+$/ && $count{$c->{name}} > 1; }
    die "gen-resp-vectors: only " . scalar(@cases) . " hiredis cases\n" if @cases < 50;
}

# The specification's examples: indented blocks whose lines all end in <CR><LF> (RESP3.md) or \r\n
# (protocol-spec.md), and quoted C strings. A line after a length header is that many bytes, so indentation
# before a payload is dropped by length, not by stripping: protocol-spec.md's " world" keeps its space.
sub cunescape { my $s = shift; $s =~ s/\\r/\r/g; $s =~ s/\\n/\n/g; $s =~ s/\\"/"/g; $s =~ s/\\\\/\\/g; return $s; }
sub blockBytes {
    my ($eol, @lines) = @_; my $bytes = ''; my $want = -1;
    for my $line (@lines) {
        my $text = $line; $text =~ s/\Q$eol\E\s*$//;
        if ($want >= 0) { $bytes .= substr($text, length($text) - $want) . "\r\n"; $want = -1; next; }
        $text =~ s/^\s+//;
        $bytes .= "$text\r\n";
        $want = $1 if $text =~ /^[\$;!=](\d+)$/;
    }
    return $bytes;
}
sub specFile {
    my ($file, $label, $eol) = @_;
    open my $f, '<', $file or die; my @lines = <$f>; chomp @lines; my $n = 0; my %seen;
    my $i = 0; my $pending = ''; my $pendingLine = 0;
    while ($i < @lines) {
        if ($lines[$i] !~ /^    /) { $i++; next; }
        my $start = $i; my @block;
        while ($i < @lines && ($lines[$i] =~ /^    / || $lines[$i] eq '')) { push @block, $lines[$i]; $i++; }
        pop @block while @block && $block[-1] eq '';
        my $line = $start + 1;
        # RESP3.md's attribute-in-an-aggregate example drops <CR><LF> after `+ttl` and `:3600` (its lines 556-557).
        if ($label eq 'RESP3.md') { for (@block) { $_ .= '<CR><LF>' if /^\s+(\+ttl|:3600)$/; } }
        # A block of quoted C strings is one example per line.
        if (!grep { $_ ne '' && !/^\s+"(.*)"\s*$/ } @block) {
            for my $k (0 .. $#block) {
                next unless $block[$k] =~ /^\s+"(.*)"\s*$/;
                my $b = cunescape($1);
                next if $seen{$b}++;
                add(sprintf("%s line %d", $label, $line + $k), $label, $DEFAULT_MAX, $b); $n++;
            }
            next;
        }
        next if grep { $_ ne '' && !/\Q$eol\E\s*$/ } @block;
        next if grep { my $x = s/<CR><LF>//gr; $x =~ /</ || $x =~ /\.\.\./ || $x =~ /^\s+[CS]: / } @block;
        my @resp = grep { $_ ne '' } @block;
        my @parts = $eol eq '\r\n' ? map { my $l = $_; my @p = split /(?<=\\r\\n)/, $l; @p } @resp : @resp;
        my $b = blockBytes($eol, @parts);
        # RESP3.md shows its streamed array across three blocks (`*?`, the elements, `.`); they are one example.
        # A block that is only `;0` is the streamed string's end marker, shown on its own.
        if ($b eq "*?\r\n" || $pending ne '') {
            $pendingLine = $line if $pending eq '';
            $pending .= $b;
            next unless $b eq ".\r\n";
            ($b, $line, $pending) = ($pending, $pendingLine, '');
        }
        next if $b eq ";0\r\n";
        next if $seen{$b}++;
        add(sprintf("%s line %d", $label, $line), $label, $DEFAULT_MAX, $b); $n++;
    }
    die "gen-resp-vectors: only $n examples in $label\n" if $n < 20;
}
specFile("$tmp/RESP3.md", 'RESP3.md', '<CR><LF>');
specFile("$tmp/protocol-spec.md", 'protocol-spec.md', '\r\n');

# The servers. The same bytes from several servers are one case, naming them all.
my %servers; my @live;
{
    open my $f, '<', "$tmp/live.tsv" or die;
    my %byKey; my @order;
    while (<$f>) {
        chomp; my ($server, $what, $hex) = split /\t/, $_, 3; $servers{$server} = 1;
        my $key = "$what\t$hex";
        push @order, $key unless $byKey{$key};
        push @{ $byKey{$key} }, $server;
    }
    for my $key (@order) {
        my ($what, $hex) = split /\t/, $key;
        my @who = @{ $byKey{$key} };
        add("$who[0] $what", "server: " . join(' ', @who), $DEFAULT_MAX, pack('H*', $hex));
    }
    die "gen-resp-vectors: replies from " . join(', ', sort keys %servers) . ", not from $wantServers servers\n"
        unless keys %servers == $wantServers && !grep { !/^(redis|valkey)-\d+\.\d+\.\d+$/ } keys %servers;
}

# The hostile list: inputs only.
{
    my @h;
    # `!`, `.` and `;` start forms hiredis lacks; resp_test.kama has them alone.
    push @h, [sprintf("type byte 0x%02x", $_), chr($_) . "\r\n"] for grep { chr($_) !~ /[!.;]/ } 0 .. 255;
    push @h, ["integer $_", ":$_\r\n"] for ('', '0', '-0', '+1', '01', '-', '1a', ' 1', '1 ', '9223372036854775807',
        '9223372036854775808', '-9223372036854775808', '-9223372036854775809', '18446744073709551616', "1\0");
    push @h, ["double $_", ",$_\r\n"] for ('', '0', '-0', '.5', '1.', '-.5', '1e5', '1E+5', '1e-5', '1e', '1e+', '+1', '-',
        'inf', 'INF', 'Inf', '-inf', '+inf', 'infinity', 'nan', 'NaN', '-nan', '+nan', 'nan(1)', '0x10', ' 1', '1 ',
        '1e400', '-1e400', '1e-400', '4.9e-324', '2.4703282292062327e-324', '2.4703282292062328e-324', '1.5e', 'e5', '1..5');
    push @h, ["double of 325 bytes", ",0." . ('0' x 323) . "\r\n"], ["double of 326 bytes", ",0." . ('0' x 324) . "\r\n"];
    push @h, ["bool $_", "#$_\r\n"] for ('t', 'T', 'f', 'F', 'x', 'tt', '', '0', '1');
    push @h, ["bool NUL", "#\0\r\n"];
    push @h, ["nil $_", "_$_\r\n"] for ('', 'x', ' ');
    push @h, ["bignum $_", "($_\r\n"] for ('', '-', '12', '-12', '007', '+1', '1-2', '1.5', ' 1');
    push @h, ["simple $_->[0]", "+$_->[1]\r\n"], ["error $_->[0]", "-$_->[1]\r\n"] for (['OK', 'OK'], ['empty', ''],
        ['with CR', "a\rb"], ['with LF', "a\nb"], ['ending in CR', "a\r"], ['with NUL', "a\0b"], ['with 0xff', "a\xffb"]);
    push @h, ["bulk $_->[0]", $_->[1]] for (['empty', "\$0\r\n\r\n"], ['null', "\$-1\r\n"], ['-2', "\$-2\r\nab\r\n"],
        ['+5', "\$+5\r\nhello\r\n"], ['05', "\$05\r\nhello\r\n"], ['x', "\$x\r\n"], ['empty length', "\$\r\n"],
        ['with CR LF inside', "\$4\r\na\r\nb\r\n"], ['binary', "\$3\r\n\0\xff\r\r\n"], ['cut in its payload', "\$5\r\nhel"],
        ['cut before its CR LF', "\$5\r\nhello"], ['cut between CR and LF', "\$5\r\nhello\r"], ['huge, nothing sent', "\$536870912\r\n"],
        ['payload then XY', "\$3\r\nfooXY"], ['payload then LF CR', "\$3\r\nfoo\n\r"], ['payload then LF', "\$3\r\nfoo\n:1\r\n"]);
    push @h, ["verbatim $_->[0]", $_->[1]] for (['txt', "=10\r\ntxt:LOLWUT\r\n"], ['empty text', "=4\r\ntxt:\r\n"],
        ['3 bytes', "=3\r\ntxt\r\n"], ['no colon', "=4\r\ntxtx\r\n"], ['null', "=-1\r\n"], ['colons', "=5\r\n:::::\r\n"],
        ['CR LF inside', "=6\r\nmkd:\r\n\r\n"]);
    push @h, ["aggregate $_->[0]", $_->[1]] for (['empty array', "*0\r\n"], ['null array', "*-1\r\n"], ['-2', "*-2\r\n"],
        ['+1', "*+1\r\n:1\r\n"], ['01', "*01\r\n:1\r\n"], ['empty count', "*\r\n"], ['cut', "*2\r\n:1\r\n"],
        ['nested', "*2\r\n*1\r\n*0\r\n%1\r\n:1\r\n~1\r\n_\r\n"], ['empty map', "%0\r\n"], ['empty set', "~0\r\n"],
        ['empty push', ">0\r\n"], ['null map', "%-1\r\n"], ['null set', "~-1\r\n"], ['null push', ">-1\r\n"],
        ['null attribute', "|-1\r\n"], ['2^32-1 announced', "*4294967295\r\n"], ['2^32', "*4294967296\r\n"],
        ['map of 2^31 pairs', "%2147483648\r\n"], ['push in an array', "*1\r\n>1\r\n:1\r\n"]);
    push @h, ["pipeline $_->[0]", $_->[1]] for (['three', "+a\r\n:1\r\n\$1\r\nb\r\n"], ['push then reply', ">2\r\n+message\r\n+ch\r\n+OK\r\n"],
        ['reply then garbage', "+OK\r\n\@\r\n"], ['reply then a cut one', ":1\r\n:2"]);
    push @h, ["resp3 $_->[0]", $_->[1]] for (['blob error', "!3\r\nERR\r\n"], ['empty blob error', "!0\r\n\r\n"],
        ['null blob error', "!-1\r\n"], ['blob error in an array', "*2\r\n!3\r\nERR\r\n:1\r\n"],
        ['streamed string', "\$?\r\n;3\r\nabc\r\n;2\r\nde\r\n;0\r\n"], ['empty streamed string', "\$?\r\n;0\r\n"],
        ['streamed string, cut', "\$?\r\n;3\r\nabc\r\n"], ['streamed array', "*?\r\n:1\r\n\$1\r\na\r\n.\r\n"],
        ['empty streamed array', "*?\r\n.\r\n"], ['streamed map', "%?\r\n+a\r\n:1\r\n.\r\n"], ['streamed set', "~?\r\n#t\r\n.\r\n"],
        ['streamed in streamed', "*?\r\n*?\r\n:1\r\n.\r\n\$?\r\n;1\r\nz\r\n;0\r\n.\r\n"], ['streamed array, cut', "*?\r\n:1\r\n"],
        ['attribute on a value', "|1\r\n+k\r\n+v\r\n:1\r\n"], ['attribute on an element', "*2\r\n:1\r\n|1\r\n+k\r\n+v\r\n:2\r\n"],
        ['attribute on a map key', "%1\r\n|1\r\n+a\r\n+b\r\n+key\r\n:1\r\n"], ['attribute on an aggregate', "|1\r\n+a\r\n+b\r\n*1\r\n:1\r\n"],
        ['two attributes', "|1\r\n+a\r\n+b\r\n|1\r\n+c\r\n+d\r\n:1\r\n"], ['attribute on an attribute key', "|1\r\n|1\r\n+x\r\n+y\r\n+a\r\n+b\r\n:1\r\n"],
        ['empty attribute', "|0\r\n:1\r\n"], ['attribute alone', "|1\r\n+a\r\n+b\r\n"], ['attribute in a streamed array', "*?\r\n|1\r\n+a\r\n+b\r\n:1\r\n.\r\n"]);
    add("hostile: $_->[0]", "hostile", $DEFAULT_MAX, $_->[1]) for @h;
    add("hostile: 1025 elements, maxelements 1024", "hostile", 1024, "*1025\r\n");
    add("hostile: 1024 elements, maxelements 1024", "hostile", 1024, "*1024\r\n");
    add("hostile: map of 513 pairs, maxelements 1024", "hostile", 1024, "%513\r\n");
    add("hostile: map of 1025 pairs, maxelements 1024", "hostile", 1024, "%1025\r\n");
}

# ---- an equivalent input hiredis can read ----
# canon(bytes) -> (bytes of the complete replies, rewritten; whether anything was rewritten; 'end' | 'more' | 'bad';
# why it is bad: 'hiredis' (malformed where hiredis reads), 'ours' (malformed in what hiredis lacks), 'terminator'
# (a payload not followed by CR LF)). It reads only structure; scalars are passed to hiredis as they are.
my $MARK = '__kama_attribute__';
my $changed;
sub lineAt { my ($b, $p) = @_; my $i = index($b, "\r\n", $p); return $i < 0 ? () : (substr($b, $p, $i - $p), $i + 2); }
sub canonElem {
    my ($b, $p) = @_; my @attr;
    while (1) {
        return () if $p >= length $b;
        last unless substr($b, $p, 1) eq '|';
        my ($l, $q) = lineAt($b, $p + 1); return () unless defined $l;
        die "hiredis\n" unless $l =~ /^(-1|0|[1-9]\d*)$/;
        last if $l eq '-1';
        $changed = 1; $p = $q;
        for (1 .. 2 * $l) { my ($e, $np) = canonElem($b, $p); return () unless defined $e; push @attr, $e; $p = $np; }
    }
    my ($v, $np) = canonPlain($b, $p); return () unless defined $v;
    $v = "*3\r\n+$MARK\r\n%" . (@attr / 2) . "\r\n" . join('', @attr) . $v if @attr;
    return ($v, $np);
}
sub canonPlain {
    my ($b, $p) = @_;
    my $t = substr($b, $p, 1);
    die "hiredis\n" unless $t =~ /[-+:,_#(\$=!*%~>|]/ || $t eq '.' || $t eq ';';
    die "ours\n" if $t eq '.' || $t eq ';';
    my ($l, $q) = lineAt($b, $p + 1); return () unless defined $l;
    return ("$t$l\r\n", $q) if $t =~ /[-+:,_#(]/;
    if ($t eq '$' && $l eq '?') {
        $changed = 1; my $data = ''; my $pp = $q;
        while (1) {
            return () if $pp >= length $b;
            die "ours\n" unless substr($b, $pp, 1) eq ';';
            my ($n, $r) = lineAt($b, $pp + 1); return () unless defined $n;
            die "ours\n" unless $n =~ /^(0|[1-9]\d*)$/;
            if ($n == 0) { $pp = $r; last; }
            return () if length($b) < $r + $n + 2;
            die "terminator\n" unless substr($b, $r + $n, 2) eq "\r\n";
            $data .= substr($b, $r, $n); $pp = $r + $n + 2;
        }
        return ('$' . length($data) . "\r\n$data\r\n", $pp);
    }
    if ($t =~ /[\$=!]/) {
        die($t eq '!' ? "ours\n" : "hiredis\n") unless $l =~ /^(-1|0|[1-9]\d*)$/;
        if ($l eq '-1') { $changed = 1 if $t eq '!'; return ($t eq '!' ? "\$-1\r\n" : "$t$l\r\n", $q); }
        return () if length($b) < $q + $l + 2;
        die "terminator\n" unless substr($b, $q + $l, 2) eq "\r\n";
        my $data = substr($b, $q, $l);
        if ($t eq '!') { $changed = 1; die "ours\n" if $data =~ /[\r\n]/; return ("-$data\r\n", $q + $l + 2); }
        return ("$t$l\r\n$data\r\n", $q + $l + 2);
    }
    # * % ~ > |
    my @el; my $pp = $q;
    if ($l eq '?') {
        die "ours\n" unless $t =~ /[*%~]/;
        $changed = 1;
        while (1) {
            return () if $pp >= length $b;
            if (substr($b, $pp, 1) eq '.') {
                my ($z, $r) = lineAt($b, $pp + 1); return () unless defined $z;
                die "ours\n" unless $z eq ''; $pp = $r; last;
            }
            my ($e, $np) = canonElem($b, $pp); return () unless defined $e; push @el, $e; $pp = $np;
        }
        die "ours\n" if $t eq '%' && @el % 2;
        return ($t . ($t eq '%' ? @el / 2 : @el) . "\r\n" . join('', @el), $pp);
    }
    die "hiredis\n" unless $l =~ /^(-1|0|[1-9]\d*)$/;
    return ("$t$l\r\n", $q) if $l eq '-1';
    my $count = $t eq '%' || $t eq '|' ? 2 * $l : $l;
    for (1 .. $count) { my ($e, $np) = canonElem($b, $pp); return () unless defined $e; push @el, $e; $pp = $np; }
    return ("$t$l\r\n" . join('', @el), $pp);
}
sub canon {
    my ($b) = @_; my $p = 0; my $done = ''; $changed = 0;
    while ($p < length $b) {
        my @r = eval { canonElem($b, $p) };
        if ($@) { chomp(my $why = $@); return ($done, $changed, 'bad', $why); }
        return ($done, $changed, 'more', '') unless @r;
        $done .= $r[0]; $p = $r[1];
    }
    return ($done, $changed, 'end', '');
}

# Deliberate differences from hiredis, by case name: the reason, and the expected reading when it is not the one
# `canon` derives. `payload` covers every case whose string is not followed by CR LF.
my %DEVIATIONS = (
    'Multi-bulk never overflows regardless of maxelements' =>
        ["hiredis allocates an aggregate's declared count before any element arrives, and runs out of memory; this " .
         "reader never allocates from a declared count, so with no limit it waits for the elements"],
    'hostile: bool NUL' =>
        ["hiredis tests a bool's byte with strchr(\"tTfF\", c), which also finds the string's terminating NUL, so it " .
         "reads #\\0 as false; this reader refuses it", "|error:Bad bool value"],
    'payload' =>
        ["hiredis skips the two bytes after a string's payload without looking at them; this reader requires CR LF"],
);

# ---- what hiredis reads ----
my @asks;   # [maxelements, bytes]
for my $c (@cases) {
    my ($done, $ch, $state, $why) = canon($c->{bytes});
    @$c{qw(canon changed state why)} = ($done, $ch, $state, $why);
    die "gen-resp-vectors: '$c->{name}' is malformed in a RESP3 form hiredis lacks; test it in resp_test.kama instead\n"
        if $state eq 'bad' && ($why eq 'ours' || ($why eq 'hiredis' && $ch));
    $c->{askRaw} = scalar @asks; push @asks, [$c->{max}, $c->{bytes}];
    $c->{askCanon} = scalar @asks; push @asks, [$c->{max}, $done];
}
open my $q, '>', "$tmp/asks.tsv" or die;
print $q "$_->[0]\t" . unpack('H*', $_->[1]) . "\n" for @asks;
close $q;
my @read = `"$tmp/resp-dump" read < "$tmp/asks.tsv"`;
die "gen-resp-vectors: resp-dump read failed\n" if $? || @read != @asks;
chomp @read;

# A reading with the marked arrays turned back into attributes.
sub parseItems {
    my ($s, $pos) = @_; my @items;
    while ($$pos < length $s && substr($s, $$pos, 1) ne ']') {
        if (substr($s, $$pos) =~ /\A(\w+)\[/) {
            my $kind = $1; $$pos += length($kind) + 1;
            my $kids = parseItems($s, $pos); $$pos++;
            push @items, [$kind, $kids];
        } else {
            substr($s, $$pos) =~ /\A([^,\]]*)/; push @items, $1; $$pos += length $1;
        }
        $$pos++ if $$pos < length $s && substr($s, $$pos, 1) eq ',';
    }
    return \@items;
}
my $MARKHEX = 'simple:' . unpack('H*', $MARK);
sub render {
    my ($item) = @_;
    return $item unless ref $item;
    my ($kind, $kids) = @$item;
    if ($kind eq 'array' && @$kids == 3 && !ref $kids->[0] && $kids->[0] eq $MARKHEX && ref $kids->[1] && $kids->[1][0] eq 'map') {
        return 'attr[' . join(',', map { render($_) } @{ $kids->[1][1] }, $kids->[2]) . ']';
    }
    return "$kind\[" . join(',', map { render($_) } @$kids) . ']';
}
sub unmark {
    my ($line) = @_;
    my $bar = index($line, '|');
    my ($values, $tail) = (substr($line, 0, $bar), substr($line, $bar));
    my @replies = $values eq '' ? () : split / ; /, $values;
    return join(' ; ', map { my $p = 0; my $items = parseItems($_, \$p); render($items->[0]) } @replies) . $tail;
}

for my $c (@cases) {
    my $raw = $read[$c->{askRaw}];
    my $via = unmark($read[$c->{askCanon}]);
    $via =~ s/\|end$/|more/ if $c->{state} eq 'more';
    $via =~ s/\|end$/|error:Bulk string not terminated by CRLF/ if $c->{state} eq 'bad' && $c->{why} eq 'terminator';
    my $want; my @notes;
    if ($c->{changed}) {
        $want = $via;
        push @notes, "read as the equivalent input hiredis reads";
    } else {
        $want = $raw;
        my $d = $DEVIATIONS{$c->{name}};
        $d = $DEVIATIONS{payload} if !$d && $c->{state} eq 'bad' && $c->{why} eq 'terminator';
        if ($d) {
            $want = defined $d->[1] ? $d->[1] : $via;
            die "gen-resp-vectors: deviation for '$c->{name}' changes nothing\n" if $want eq $raw;
            push @notes, "deviation: $d->[0]; hiredis reads $raw";
        }
    }
    $c->{want} = $want; $c->{note} = join('; ', @notes);
}
my %named = map { $_->{name} => 1 } @cases;
for (keys %DEVIATIONS) { die "gen-resp-vectors: deviation '$_' names no case\n" unless $_ eq 'payload' || $named{$_}; }

# ---- emit ----
sub lit {
    my $s = shift;
    die "gen-resp-vectors: '\${' in a vector\n" if $s =~ /\$\{/;
    $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/\r/\\r/g; $s =~ s/\n/\\n/g; $s =~ s/\t/\\t/g; $s =~ s/\0/\\0/g;
    die "gen-resp-vectors: a non-ASCII byte in a vector string\n" if $s =~ /[^\x20-\x7e]/;
    return "\"$s\"";
}
open my $o, '>', $out or die;
my $servers = join(', ', sort keys %servers);
print $o <<"HEAD";
// GENERATED by tools/gen-resp-vectors.sh. Do not edit: change the script and run it again.
//
// RESP inputs and what each reads as, in tests/unit/src/resp_test.kama's `describe` notation (values joined by
// " ; ", then |end, |more or |error:<message>). The readings are hiredis v1.4.1's ($hiredisCommit), compiled
// from its pinned sources by tools/resp-dump.c. Sources:
//   - hiredis test.c: every input hiredis's own reader tests feed, under their names;
//   - RESP3.md (redis-specifications $specCommit) and protocol-spec.md (redis/docs $docsCommit): every example;
//   - server: what each server answered under RESP2 and RESP3, asked live: $servers;
//   - hostile: inputs listed in the script.
// A case using what hiredis lacks (blob errors, streamed forms, attributes) reads as hiredis reads its equivalent;
// a deliberate difference from hiredis says why. Both are in the case's note.
import { std::collections::DynamicArray };
export { respNames, respSources, respInputs, respMaxElements, respWant, respNotes };

HEAD
sub column {
    my ($fn, $type, $get) = @_;
    print $o "fn DynamicArray<$type> $fn() {\n    DynamicArray<$type> v = DynamicArray.empty();\n";
    print $o "    v.add(item: " . $get->($_) . ");\n" for @cases;
    print $o "    return v;\n}\n\n";
}
column('respNames', 'string', sub { lit($_[0]{name}) });
column('respSources', 'string', sub { lit($_[0]{source}) });
column('respInputs', 'string', sub { lit(unpack('H*', $_[0]{bytes})) });
column('respMaxElements', 'int64', sub { "$_[0]{max}i64" });
column('respWant', 'string', sub { lit($_[0]{want}) });
column('respNotes', 'string', sub { lit($_[0]{note}) });
close $o;
printf "gen-resp-vectors: %d cases (%d from hiredis's tests, %d server replies) into %s\n", scalar(@cases),
    scalar(grep { $_->{source} eq 'hiredis test.c' } @cases), scalar(grep { $_->{source} =~ /^server/ } @cases), $out;
PERL

perl "$tmp/gen.pl" "$tmp" "$OUT" "$HIREDIS_COMMIT" "$SPEC_COMMIT" "$DOCS_COMMIT" "$(echo $SERVERS | wc -w | tr -d ' ')"
