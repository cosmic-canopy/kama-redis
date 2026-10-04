#!/bin/sh
# gen-server-vectors.sh — write tests/unit/src/server_vectors.kama: what servers and proxies answer a client, byte
# for byte, for the connection's tests to replay through the fake server.
#
#   - Codes: every error code each server in the matrix (tools/redis.sh list) can send, read out of its own binary
#     in the image: each string literal "-CODE message", and MOVED and ASK, which cluster.c builds from
#     "-%s %d %s:%d".
#   - Replies: each server, asked live in a throwaway container with no network, for what a handshake meets (HELLO
#     in every form, AUTH, SELECT, CLIENT SETNAME and SETINFO, each right and wrong, on an open server and on one
#     with a password) and for every error a standalone server can be made to send. A case's reply is recorded raw,
#     exactly as it came.
#   - Proxies: Envoy's redis proxy answers HELLO itself, differently in each release. Its messages are read from its
#     source (command_splitter_impl.cc and .h at v1.32.0, v1.36.0 and v1.39.0, pinned by SHA256), and laid out in
#     the order that source checks them, which the script verifies before using it. twemproxy has no entry: it
#     closes the connection on a command it does not know (nc_redis.c), which is a hangup, not bytes.
#
# Run it, then `git diff` must be empty unless a server image moved (the header names each server's version).
# Needs perl, curl, and podman or docker.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/tests/unit/src/server_vectors.kama"
SERVERS=$("$ROOT/tools/redis.sh" list)

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

fetch() {  # fetch <url> <dest> <sha256>
    curl -fsSL -o "$2" "$1"
    got=$(shasum -a 256 "$2" | cut -d' ' -f1)
    [ "$got" = "$3" ] || { echo "gen-server-vectors: $1 sha256 $got, want $3" >&2; exit 1; }
}

E=https://raw.githubusercontent.com/envoyproxy/envoy
P=source/extensions/filters/network/redis_proxy
while read -r v cc h; do
    fetch "$E/$v/$P/command_splitter_impl.cc" "$tmp/envoy-$v.cc" "$cc"
    fetch "$E/$v/$P/command_splitter_impl.h" "$tmp/envoy-$v.h" "$h"
done <<'EOF'
v1.32.0 278561f4c67d39a6f08d5012f91cdf6e479cc0a1cfddc2f200b23ce4904c6292 996f183579eb0ae04c38be724fc51b4ac8035714651fb25e84cc790d10934e53
v1.36.0 4416adaffdb71600fb63142520268200d981c8bf0cea7380174cf99da5c7fd02 196eceba6fe6b43c05f51c98e0eca5cfec0a9fef17da2b6d0e6b4c0885bdbeff
v1.39.0 9664b89110a2592cd45a7b41972c90fc3b322c07086fb265d092263daabbe75a 484e0875ddf41254d6fae7e60516830df704b9c5078013a121c668de11dbf01c
EOF

if [ -n "${CONTAINER_RUNTIME:-}" ]; then RT=$CONTAINER_RUNTIME
elif command -v podman >/dev/null 2>&1; then RT=podman
elif command -v docker >/dev/null 2>&1; then RT=docker
else echo "gen-server-vectors: neither podman nor docker found (set CONTAINER_RUNTIME)" >&2; exit 1
fi

# The servers a container runs, one per port. The main one has the ACL users of tests/integration/server/redis.conf.
# A server whose settings this version does not have is not started, and its
# cases are left out (`up` lists the ports started).
cat > "$tmp/run.sh" <<'SH'
set -u
cat > /tmp/ask.pl
cat > /tmp/main.conf <<'CONF'
port 7000
save ""
appendonly no
user default on nopass ~* &* +@all
user kr_acl on >kr_acl_pw ~* &* +@all
user kr_ro on >kr_ro_pw ~* &* -@all +@read +@connection
user kr_off off >kr_off_pw ~* &* +@all
CONF
start() { port=$1; shift; redis-server "$@" --port "$port" --save "" --appendonly no --daemonize yes >/dev/null 2>&1 && up="$up $port"; }
up=""
redis-server /tmp/main.conf --daemonize yes >/dev/null 2>&1 && up="$up 7000"
start 7001 --requirepass kr_default_pw
start 7002 --maxmemory 1 --maxmemory-policy noeviction
start 7003 --min-replicas-to-write 1
start 7004 --replicaof 127.0.0.1 7999
# Valkey's own settings. Redis 8 passes a setting it does not know to its modules and fails only once daemonized,
# so these are started by product, not by trying.
case "$(redis-server --version)" in
    Redis*) ;;
    *) start 7005 --extended-redis-compatibility yes; start 7006 --availability-zone az-1 ;;
esac
redis-server --version | sed -n "s/.*[Ss]erver v=\([0-9.]*\) .*/\1/p"
bin=$(readlink -f "$(command -v redis-server)")
perl -0777 -ne 'my %c; $c{$1}++ while /\x00-([A-Z][A-Z0-9_]+) [\x21-\x7e]/g;
    print "codes\t", join(" ", sort keys %c), "\n";
    print "redirect\t", (/\x00-%s %d %s:%d\x00/ && /\x00MOVED\x00/ && /\x00ASK\x00/ ? "yes" : "no"), "\n";' "$bin"
perl /tmp/ask.pl $up
SH

# Runs in the container. Each case opens its own connection, sends its setup commands (their replies are read and
# dropped), then the command whose reply is recorded: <case> TAB <command> TAB <the reply's bytes, in hex>. A reply
# is read as RESP, one whole value, so nothing after it is taken with it.
cat > "$tmp/ask.pl" <<'PERL'
use strict; use warnings; use IO::Socket::INET;
my %up = map { $_ => 1 } @ARGV;
sub open_to {
    my $port = shift; my $s;
    for (1 .. 200) { $s = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Proto => 'tcp'); last if $s; select(undef, undef, undef, 0.05); }
    die "no server on $port\n" unless $s;
    binmode $s; $s->autoflush(1);
    return { s => $s, buf => '', pos => 0 };
}
sub enc { my $o = '*' . scalar(@_) . "\r\n"; $o .= '$' . length($_) . "\r\n$_\r\n" for @_; return $o; }
sub more { my $c = shift; my $n = sysread($c->{s}, my $chunk, 65536); die "eof\n" unless $n; $c->{buf} .= $chunk; }
sub line {
    my $c = shift; my $i;
    more($c) while ($i = index($c->{buf}, "\r\n", $c->{pos})) < 0;
    my $l = substr($c->{buf}, $c->{pos}, $i - $c->{pos}); $c->{pos} = $i + 2; return $l;
}
sub value {
    my $c = shift;
    my $l = line($c); my $t = substr($l, 0, 1); my $n = substr($l, 1);
    if ($t =~ /[\$!=]/) {
        return if $n < 0;
        more($c) while length($c->{buf}) < $c->{pos} + $n + 2;
        $c->{pos} += $n + 2; return;
    }
    if ($t =~ /[*~>]/) { return if $n < 0; value($c) for 1 .. $n; return; }
    if ($t =~ /[%]/) { value($c) for 1 .. 2 * $n; return; }
    if ($t eq '|') { value($c) for 1 .. 2 * $n; value($c); return; }
    die "unexpected reply line '$l'\n" unless $t =~ /[-+:,#_(]/;
}
sub reply { my $c = shift; value($c); my $r = substr($c->{buf}, 0, $c->{pos}); $c->{buf} = substr($c->{buf}, $c->{pos}); $c->{pos} = 0; return $r; }
sub call { my ($c, @cmd) = @_; print { $c->{s} } enc(@cmd); return reply($c); }
sub shown { return join(' ', map { /[ ']/ || $_ eq '' ? "'$_'" : $_ } @_); }
sub record { my ($case, $cmd, $r) = @_; print "$case\t", shown(@$cmd), "\t", unpack('H*', $r), "\n"; }

my @cases = (
    # The handshake on the main server.
    ['hello3', 7000, [], ['HELLO', '3']],
    ['hello2', 7000, [], ['HELLO', '2']],
    ['hello3-setname', 7000, [], ['HELLO', '3', 'SETNAME', 'kama-test']],
    ['hello3-setname-space', 7000, [], ['HELLO', '3', 'SETNAME', 'a b']],
    ['hello4', 7000, [], ['HELLO', '4']],
    ['hello3-auth', 7000, [], ['HELLO', '3', 'AUTH', 'kr_acl', 'kr_acl_pw']],
    ['hello2-auth', 7000, [], ['HELLO', '2', 'AUTH', 'kr_acl', 'kr_acl_pw']],
    ['hello3-auth-setname', 7000, [], ['HELLO', '3', 'AUTH', 'kr_acl', 'kr_acl_pw', 'SETNAME', 'kama-test']],
    ['hello3-auth-wrong', 7000, [], ['HELLO', '3', 'AUTH', 'kr_acl', 'wrong']],
    ['hello3-auth-off', 7000, [], ['HELLO', '3', 'AUTH', 'kr_off', 'kr_off_pw']],
    ['setinfo-name', 7000, [], ['CLIENT', 'SETINFO', 'LIB-NAME', 'kama-redis']],
    ['setinfo-ver', 7000, [], ['CLIENT', 'SETINFO', 'LIB-VER', '0.1.0']],
    ['setinfo-space', 7000, [], ['CLIENT', 'SETINFO', 'LIB-NAME', 'a b']],
    ['select1', 7000, [], ['SELECT', '1']],
    ['select-range', 7000, [], ['SELECT', '16']],
    ['auth2', 7000, [], ['AUTH', 'kr_acl', 'kr_acl_pw']],
    ['auth2-wrong', 7000, [], ['AUTH', 'kr_acl', 'wrong']],
    ['auth1-nopass', 7000, [], ['AUTH', 'anything']],
    ['setname', 7000, [], ['CLIENT', 'SETNAME', 'kama-test']],
    ['setname-space', 7000, [], ['CLIENT', 'SETNAME', 'a b']],
    ['ping', 7000, [], ['PING']],
    # The handshake on the server with a password.
    ['locked-hello3', 7001, [], ['HELLO', '3']],
    ['locked-hello2', 7001, [], ['HELLO', '2']],
    ['locked-hello3-auth', 7001, [], ['HELLO', '3', 'AUTH', 'default', 'kr_default_pw']],
    ['locked-hello3-auth-wrong', 7001, [], ['HELLO', '3', 'AUTH', 'default', 'wrong']],
    ['locked-auth1', 7001, [], ['AUTH', 'kr_default_pw']],
    ['locked-auth1-wrong', 7001, [], ['AUTH', 'wrong']],
    ['locked-ping', 7001, [], ['PING']],
    ['locked-select1', 7001, [], ['SELECT', '1']],
    ['locked-setinfo-name', 7001, [], ['CLIENT', 'SETINFO', 'LIB-NAME', 'kama-redis']],
    # Errors, each the way a standalone server can be made to send it.
    ['wrongtype', 7000, [['SET', 'kr:s', 'v']], ['LPUSH', 'kr:s', 'x']],
    ['unknown', 7000, [], ['NOSUCHCOMMAND']],
    ['noscript', 7000, [], ['EVALSHA', 'ffffffffffffffffffffffffffffffffffffffff', '0']],
    ['execabort', 7000, [['MULTI'], ['NOSUCHCOMMAND']], ['EXEC']],
    # An error inside a reply: EXEC's array, whose second command failed when it ran.
    ['exec-error', 7000, [['MULTI'], ['SET', 'kr:e', 'v'], ['LPUSH', 'kr:e', 'x']], ['EXEC']],
    ['busygroup', 7000, [['XGROUP', 'CREATE', 'kr:x', 'g', '$', 'MKSTREAM']], ['XGROUP', 'CREATE', 'kr:x', 'g', '$', 'MKSTREAM']],
    ['nogroup', 7000, [['XADD', 'kr:y', '*', 'f', 'v']], ['XREADGROUP', 'GROUP', 'nog', 'c', 'STREAMS', 'kr:y', '>']],
    ['noperm', 7000, [['AUTH', 'kr_ro', 'kr_ro_pw']], ['SET', 'kr:k', 'v']],
    ['notbusy', 7000, [], ['SCRIPT', 'KILL']],
    ['oom', 7002, [], ['SET', 'kr:k', 'v']],
    ['noreplicas', 7003, [], ['SET', 'kr:k', 'v']],
    ['readonly', 7004, [], ['SET', 'kr:k', 'v']],
    # Valkey 8 and later only: a server that says it is Redis 7.2.4, and one in an availability zone.
    ['compat-hello3', 7005, [], ['HELLO', '3']],
    ['az-hello3', 7006, [], ['HELLO', '3']],
);
for my $k (@cases) {
    my ($case, $port, $setup, $cmd) = @$k;
    next unless $up{$port};
    my $c = open_to($port);
    call($c, @$_) for @$setup;
    record($case, $cmd, call($c, @$cmd));
    close $c->{s};
}
# BUSYKEY: RESTORE over a key that exists, with the key's own DUMP.
{
    my $c = open_to(7000);
    call($c, 'SET', 'kr:b', '1');
    my $d = call($c, 'DUMP', 'kr:b');
    $d =~ /\A\$(\d+)\r\n/ or die "DUMP: $d\n";
    my $payload = substr($d, length($1) + 3, $1);
    record('busykey', ['RESTORE', 'kr:b', '0', '<the DUMP of kr:b>'], call($c, 'RESTORE', 'kr:b', '0', $payload));
}
# UNBLOCKED: a BLPOP that another connection ends with CLIENT UNBLOCK … ERROR.
{
    my $a = open_to(7000); my $b = open_to(7000);
    my $id = call($a, 'CLIENT', 'ID'); $id =~ /\A:(\d+)\r\n\z/ or die "CLIENT ID: $id\n"; $id = $1;
    print { $a->{s} } enc('BLPOP', 'kr:none', '0');
    my $unblocked;
    for (1 .. 200) { $unblocked = call($b, 'CLIENT', 'UNBLOCK', $id, 'ERROR'); last if $unblocked eq ":1\r\n"; select(undef, undef, undef, 0.05); }
    die "CLIENT UNBLOCK: $unblocked\n" unless $unblocked eq ":1\r\n";
    record('unblocked', ['BLPOP', 'kr:none', '0'], reply($a));
}
PERL

: > "$tmp/live.tsv"
for server in $SERVERS; do
    case "$server" in
        redis-*)  image=docker.io/library/redis:${server#redis-} ;;
        valkey-*) image=docker.io/valkey/valkey:${server#valkey-} ;;
    esac
    "$RT" run --rm -i --network none "$image" sh -c "$(cat "$tmp/run.sh")" < "$tmp/ask.pl" > "$tmp/one.txt"
    number=$(head -n 1 "$tmp/one.txt")
    case "$number" in [0-9]*.[0-9]*) ;; *) echo "gen-server-vectors: $server gave no version" >&2; exit 1 ;; esac
    tail -n +2 "$tmp/one.txt" | sed "s/^/${server%%-*}-$number	/" >> "$tmp/live.tsv"
done

cat > "$tmp/gen.pl" <<'PERL'
use strict; use warnings;
my ($tmp, $out) = @ARGV;

# ---- the servers ----
my (@versions, %codeServers, @replies, %seen);
open my $f, '<', "$tmp/live.tsv" or die;
while (<$f>) {
    chomp; my ($version, $what, @rest) = split /\t/, $_, -1;
    push @versions, $version unless $seen{$version}++;
    if ($what eq 'codes') { push @{ $codeServers{$_} }, $version for split / /, $rest[0]; next; }
    if ($what eq 'redirect') {
        die "gen-server-vectors: $version has no \"-%s %d %s:%d\" with MOVED and ASK\n" unless $rest[0] eq 'yes';
        push @{ $codeServers{$_} }, $version for qw(MOVED ASK);
        next;
    }
    push @replies, ["$version $what", $rest[0], $rest[1]];
}
my %count; $count{(split / /, $_->[0])[1]}++ for @replies;
for my $must (qw(hello3 hello2 hello3-auth hello3-auth-wrong locked-hello3 locked-auth1 wrongtype unblocked busykey)) {
    die "gen-server-vectors: case $must is not on every server\n" unless ($count{$must} // 0) == @versions;
}
die "gen-server-vectors: no compat-hello3 case\n" unless $count{'compat-hello3'};
for my $code (qw(ERR WRONGTYPE NOAUTH WRONGPASS NOPERM NOPROTO MOVED ASK)) {
    die "gen-server-vectors: $code is not sent by every server\n" unless @{ $codeServers{$code} // [] } == @versions;
}

# ---- Envoy, from its source ----
# Each release checks a HELLO in this order (command_splitter_impl.cc, InstanceImpl::makeRequest):
#   1.32: password required -> AuthRequiredError; then HELLO, not in the handler table -> "unsupported command '…'"
#   1.36: HELLO, not a supported command -> "ERR unknown command '…', with args beginning with: …"; the password
#         check comes after
#   1.39: HELLO is supported; password required -> AuthRequiredError; then more than one argument -> the options
#         error; then a version other than 2 -> UnsupportedProtocol
# The script finds each message and checks that the source still puts the checks in this order.
sub slurp { open my $h, '<', shift or die; local $/; return <$h>; }
sub at { my ($src, $re, $what) = @_; $src =~ $re or die "gen-server-vectors: no $what in Envoy's source\n"; return ($-[0], $1); }
sub before { my ($a, $b, $what) = @_; die "gen-server-vectors: Envoy's source no longer checks $what\n" unless $a < $b; }
my @proxy;
my @requests = (['HELLO', '3'], ['HELLO', '3', 'AUTH', 'kr_acl', 'kr_acl_pw']);
for my $v (qw(v1.32.0 v1.36.0 v1.39.0)) {
    my $cc = slurp("$tmp/envoy-$v.cc"); my $h = slurp("$tmp/envoy-$v.h");
    my (undef, $authRequired) = at($h, qr/AuthRequiredError = "([^"]+)"/, 'AuthRequiredError');
    my ($authAt) = at($cc, qr/(if \(!callbacks\.connectionAllowed\(\)\))/, 'password check');
    my $answer;
    if ($v eq 'v1.32.0') {
        my ($at, $fmt) = at($cc, qr/fmt::format\("(unsupported command '\{\}')"/, 'unsupported command');
        before($authAt, $at, 'the password before an unsupported command');
        $answer = sub { my ($req, $locked) = @_; return $authRequired if $locked; (my $m = $fmt) =~ s/\{\}/$req->[0]/; return $m; };
    } elsif ($v eq 'v1.36.0') {
        my ($at, $fmt) = at($cc, qr/"(ERR unknown command '\{\}', with args beginning with: \{\})"/, 'unknown command');
        before($at, $authAt, 'an unknown command before the password');
        $answer = sub { my ($req) = @_; my $m = $fmt; $m =~ s/\{\}/$req->[0]/; $m =~ s/\{\}/$req->[1]/; return $m; };
    } else {
        my (undef, $noproto) = at($h, qr/UnsupportedProtocol = "([^"]+)"/, 'UnsupportedProtocol');
        my ($optAt, $options) = at($cc, qr/"(ERR HELLO options like AUTH and SETNAME are not supported)"/, 'HELLO options');
        before($authAt, $optAt, 'the password before HELLO\'s options');
        $answer = sub { my ($req, $locked) = @_; return $authRequired if $locked; return @$req > 2 ? $options : $noproto; };
    }
    (my $version = $v) =~ s/^v//;
    for my $req (@requests) {
        for my $locked (0, 1) {
            my $name = "envoy-$version " . join(' ', @$req) . ($locked ? ', password required' : '');
            push @proxy, [$name, unpack('H*', '-' . $answer->($req, $locked) . "\r\n")];
        }
    }
}

sub lit { my $s = shift; die "gen-server-vectors: unexpected text '$s'\n" if $s =~ /[^\x20-\x7e]/ || $s =~ /[\\"]|\$\{/; return "\"$s\""; }
open my $o, '>', $out or die;
my $who = join(', ', @versions);
print $o <<"HEAD";
// GENERATED by tools/gen-server-vectors.sh. Do not edit: change the script and run it again.
//
// What servers and proxies answer a client, byte for byte. The servers, each asked live in a container with no
// network: $who.
//   - sentCodes: every error code a server in the matrix can send, read out of its own binary (each "-CODE "
//     literal, and MOVED and ASK from cluster.c's "-%s %d %s:%d"); codeServers names the servers that send it.
//   - replyNames / replyCommands / replyHex: "<server> <case>", the command sent, and the reply exactly as it
//     came. A case is a handshake step (hello3, locked-auth1, …) or an error a standalone server sends (wrongtype,
//     noperm, …); tools/gen-server-vectors.sh lists them.
//   - proxyNames / proxyHex: Envoy's redis proxy's answers to HELLO, read from its source (v1.32.0, v1.36.0,
//     v1.39.0), with and without a password required.
import { std::collections::DynamicArray };
export { serverVersions, sentCodes, codeServers, replyNames, replyCommands, replyHex, proxyNames, proxyHex };

HEAD
sub column {
    my ($fn, @items) = @_;
    print $o "fn DynamicArray<string> $fn() {\n    DynamicArray<string> v = DynamicArray.empty();\n";
    print $o "    v.add(item: $_);\n" for @items;
    print $o "    return v;\n}\n\n";
}
my @codes = sort keys %codeServers;
column('serverVersions', map { lit($_) } @versions);
column('sentCodes', map { lit($_) } @codes);
column('codeServers', map { lit(join(' ', @{ $codeServers{$_} })) } @codes);
column('replyNames', map { lit($_->[0]) } @replies);
column('replyCommands', map { lit($_->[1]) } @replies);
column('replyHex', map { lit($_->[2]) } @replies);
column('proxyNames', map { lit($_->[0]) } @proxy);
column('proxyHex', map { lit($_->[1]) } @proxy);
close $o;
printf "gen-server-vectors: %d codes, %d replies, %d proxy answers, from %s into %s\n", scalar(@codes), scalar(@replies), scalar(@proxy), $who, $out;
PERL

perl "$tmp/gen.pl" "$tmp" "$OUT"
