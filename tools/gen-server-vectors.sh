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
#   - Typed pairs (phase 3): what a command's reply is under RESP2 and under RESP3, from the same setup on a fresh
#     connection after FLUSHALL each time, so a typed read of either must give the same values. The setup is written
#     beside each reply, so a test derives its expected values from it rather than from memory. Transactions (MULTI,
#     QUEUED, EXEC, EXEC's null after a broken WATCH), scripts (SCRIPT LOAD and an EVALSHA hit), SCAN pages and
#     BLPOP's replies are captured the same way.
#   - Pub/sub (phase 4): under RESP2 and RESP3, what a subscribing connection reads: confirmations, messages from a
#     second connection, PING's two shapes, refusals, and invalidations another connection's tracking redirects to
#     it. An unsubscribe-all's order follows a hash Redis seeds at random in each process, so it is checked and then
#     recorded in one order (canonical()). On two cluster nodes joined by hand (7.0 and later): CROSSSLOT, MOVED, and
#     the server's own sunsubscribe when a slot leaves the node.
#   - Blocking commands: each server's `ACL CAT blocking`, sorted (the server lists them in hash order), and for each
#     blocking command the server documents (7.0 and later), its arguments as COMMAND DOCS gives them, so the
#     client's table of where each one's timeout is can be checked against every server.
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
# Two cluster nodes, for sharded pub/sub's MOVED, CROSSSLOT and the server's own sunsubscribe (ask.pl joins them).
for p in 7100 7101; do start $p --cluster-enabled yes --cluster-config-file /tmp/nodes-$p.conf --cluster-require-full-coverage no; done
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
# An argument with a byte outside printable ASCII is shown as <hex:…>, so every shown command is exact.
sub shown { return join(' ', map { /[^\x20-\x7e]/ ? '<hex:' . unpack('H*', $_) . '>' : /[ ']/ || $_ eq '' ? "'$_'" : $_ } @_); }
# <case> TAB <command> TAB <reply, hex> TAB <setup: its commands, shown, joined by " ; "; a string is taken as written>
sub record {
    my ($case, $cmd, $r, $setup) = @_;
    my $set = join(' ; ', map { ref $_ ? shown(@$_) : $_ } @{ $setup // [] });
    print "$case\t", shown(@$cmd), "\t", unpack('H*', $r), "\t$set\n";
}
# A whole RESP2 reply as Perl data: a string, undef for a null, an array ref, or { error => message }.
sub parsed {
    my $c = shift;
    my $l = line($c); my $t = substr($l, 0, 1); my $n = substr($l, 1);
    if ($t eq '$') {
        return undef if $n < 0;
        more($c) while length($c->{buf}) < $c->{pos} + $n + 2;
        my $s = substr($c->{buf}, $c->{pos}, $n); $c->{pos} += $n + 2; return $s;
    }
    if ($t eq '*') { return undef if $n < 0; return [map { parsed($c) } 1 .. $n]; }
    return { error => $n } if $t eq '-';
    die "unexpected reply line '$l'\n" unless $t =~ /[+:]/;
    return $n;
}
sub ask { my ($c, @cmd) = @_; print { $c->{s} } enc(@cmd); my $v = parsed($c); $c->{buf} = substr($c->{buf}, $c->{pos}); $c->{pos} = 0; return $v; }

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
    # Reported, never refused: CLIENT TRACKING and CACHING are, since nothing here reads invalidations yet.
    ['trackinginfo', 7000, [], ['CLIENT', 'TRACKINGINFO']],
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
    record($case, $cmd, call($c, @$cmd), $setup);
    close $c->{s};
}
# BUSYKEY: RESTORE over a key that exists, with the key's own DUMP.
{
    my $c = open_to(7000);
    call($c, 'SET', 'kr:b', '1');
    my $d = call($c, 'DUMP', 'kr:b');
    $d =~ /\A\$(\d+)\r\n/ or die "DUMP: $d\n";
    my $payload = substr($d, length($1) + 3, $1);
    record('busykey', ['RESTORE', 'kr:b', '0', '<the DUMP of kr:b>'], call($c, 'RESTORE', 'kr:b', '0', $payload), [['SET', 'kr:b', '1']]);
}
# UNBLOCKED: a BLPOP that another connection ends with CLIENT UNBLOCK … ERROR.
{
    my $a = open_to(7000); my $b = open_to(7000);
    my $id = call($a, 'CLIENT', 'ID'); $id =~ /\A:(\d+)\r\n\z/ or die "CLIENT ID: $id\n"; $id = $1;
    print { $a->{s} } enc('BLPOP', 'kr:none', '0');
    my $unblocked;
    for (1 .. 200) { $unblocked = call($b, 'CLIENT', 'UNBLOCK', $id, 'ERROR'); last if $unblocked eq ":1\r\n"; select(undef, undef, undef, 0.05); }
    die "CLIENT UNBLOCK: $unblocked\n" unless $unblocked eq ":1\r\n";
    record('unblocked', ['BLPOP', 'kr:none', '0'], reply($a), ['CLIENT UNBLOCK <its id> ERROR, from another connection']);
}

# ---- Phase 3: typed pairs, each under RESP2 and RESP3 ----
# Every case runs on a fresh connection, after FLUSHALL, so the two protocols see the same data. Its name is
# "<case>/2" or "<case>/3". Sets hold integers (an intset, in order: a hashtable's order follows a per-process seed),
# stream IDs are explicit, and SCAN runs on one key, so every capture is the same on every run.
my $big = '0123456789abcdef' x 64;
my $bin = join('', map { chr } 0 .. 255);
my @stream = (['XADD', 'kr:x', '1-1', 'f', 'v'], ['XADD', 'kr:x', '2-1', 'g', 'w', 'h', 'u']);
my @typed = (
    ['get-hit', [['SET', 'kr:k', 'hello']], ['GET', 'kr:k']],
    ['get-missing', [], ['GET', 'kr:none']],
    ['get-big', [['SET', 'kr:big', $big]], ['GET', 'kr:big']],
    ['get-binary', [['SET', 'kr:bin', $bin]], ['GET', 'kr:bin']],
    ['mget', [['MSET', 'kr:a', '1', 'kr:b', '2']], ['MGET', 'kr:a', 'kr:none', 'kr:b']],
    ['incrbyfloat', [['SET', 'kr:f', '10.5']], ['INCRBYFLOAT', 'kr:f', '0.1']],
    ['hgetall', [['HSET', 'kr:h', 'f1', 'v1', 'f2', 'v2']], ['HGETALL', 'kr:h']],
    ['hmget', [['HSET', 'kr:h', 'f1', 'v1', 'f2', 'v2']], ['HMGET', 'kr:h', 'f1', 'nofield', 'f2']],
    ['smembers', [['SADD', 'kr:set', '3', '1', '2']], ['SMEMBERS', 'kr:set']],
    ['smismember', [['SADD', 'kr:set', '3', '1', '2']], ['SMISMEMBER', 'kr:set', '1', '9']],
    ['zrange-withscores', [['ZADD', 'kr:z', '1.5', 'a', '2', 'b']], ['ZRANGE', 'kr:z', '0', '-1', 'WITHSCORES']],
    ['zscore', [['ZADD', 'kr:z', '1.5', 'a', '2', 'b']], ['ZSCORE', 'kr:z', 'a']],
    ['xrange', [@stream], ['XRANGE', 'kr:x', '-', '+']],
    ['xread', [@stream], ['XREAD', 'STREAMS', 'kr:x', '0']],
    ['lpos', [['RPUSH', 'kr:l', 'a', 'b', 'c', 'b']], ['LPOS', 'kr:l', 'b', 'COUNT', '0']],
    ['config-get', [], ['CONFIG', 'GET', 'maxmemory-policy']],
    ['exists', [['SET', 'kr:k', 'hello']], ['EXISTS', 'kr:k', 'kr:none']],
    ['type', [['SET', 'kr:k', 'hello']], ['TYPE', 'kr:k']],
    ['eval', [], ['EVAL', "return {1, 'two', {3, 4}}", '0']],
    # An error inside a reply that is not EXEC's: redis.pcall's error, returned inside an array.
    ['eval-error-inside', [['SET', 'kr:s', 'v']], ['EVAL', "return {1, redis.pcall('LPUSH', KEYS[1], 'x')}", '1', 'kr:s']],
    ['eval-ro', [], ['EVAL_RO', 'return 1', '0']],
    # Transactions: MULTI's reply, a command's while queued, a command refused while queued, and EXEC's array.
    ['multi', [], ['MULTI']],
    ['queued', [['MULTI']], ['SET', 'kr:q', 'v']],
    ['queued-error', [['MULTI']], ['NOSUCHCOMMAND']],
    ['watch', [], ['WATCH', 'kr:w']],
    ['unwatch', [['WATCH', 'kr:w']], ['UNWATCH']],
    ['exec-ok', [['MULTI'], ['SET', 'kr:t', '1'], ['INCR', 'kr:t']], ['EXEC']],
    # SCAN pages: each is the whole collection on one page.
    ['scan', [['SET', 'kr:only', '1']], ['SCAN', '0']],
    ['sscan', [['SADD', 'kr:ss', '3', '1', '2']], ['SSCAN', 'kr:ss', '0']],
    ['hscan', [['HSET', 'kr:hs', 'a', '1', 'b', '2']], ['HSCAN', 'kr:hs', '0']],
    ['hscan-novalues', [['HSET', 'kr:hs', 'a', '1', 'b', '2']], ['HSCAN', 'kr:hs', '0', 'NOVALUES']],
    ['zscan', [['ZADD', 'kr:zs', '1', 'a', '2', 'b']], ['ZSCAN', 'kr:zs', '0']],
    # BLPOP: timing out, popping, and the timeouts the server refuses.
    ['blpop-null', [], ['BLPOP', 'kr:none', '0.01']],
    ['blpop-hit', [['RPUSH', 'kr:bl', 'a']], ['BLPOP', 'kr:bl', '1']],
    ['blpop-not-float', [], ['BLPOP', 'kr:none', 'abc']],
    ['blpop-negative', [], ['BLPOP', 'kr:none', '-1']],
);
for my $proto (2, 3) {
    for my $k (@typed) {
        my ($case, $setup, $cmd) = @$k;
        my $c = open_to(7000);
        call($c, 'HELLO', '3') if $proto == 3;
        call($c, 'FLUSHALL');
        call($c, @$_) for @$setup;
        record("$case/$proto", $cmd, call($c, @$cmd), $setup);
        close $c->{s};
    }
    # EXEC's null: another connection writes a key this one WATCHes.
    my $a = open_to(7000); my $b = open_to(7000);
    call($a, 'HELLO', '3') if $proto == 3;
    call($a, 'FLUSHALL');
    call($a, 'WATCH', 'kr:w'); call($b, 'SET', 'kr:w', 'x'); call($a, 'MULTI'); call($a, 'SET', 'kr:w', 'y');
    record("exec-null/$proto", ['EXEC'], call($a, 'EXEC'), [['WATCH', 'kr:w'], 'SET kr:w x, from another connection', ['MULTI'], ['SET', 'kr:w', 'y']]);
    close $a->{s}; close $b->{s};
}
# Scripts: SCRIPT LOAD's SHA-1, and EVALSHA by it.
{
    my $c = open_to(7000);
    call($c, 'FLUSHALL');
    my $src = "return redis.call('GET', KEYS[1])";
    my $r = call($c, 'SCRIPT', 'LOAD', $src);
    record('script-load', ['SCRIPT', 'LOAD', $src], $r);
    $r =~ /\A\$40\r\n([0-9a-f]{40})\r\n\z/ or die "SCRIPT LOAD: $r\n";
    my $sha = $1;
    call($c, 'SET', 'kr:k', 'hello');
    record('evalsha-hit', ['EVALSHA', $sha, '1', 'kr:k'], call($c, 'EVALSHA', $sha, '1', 'kr:k'), [['SCRIPT', 'LOAD', $src], ['SET', 'kr:k', 'hello']]);
    close $c->{s};
}
# Blocking commands: the category, sorted, and the arguments of each blocking command the server documents. The
# names asked about are the category's and those the client's table knows, since WAIT and WAITAOF block without being
# in the category before 8.0.
{
    sub kv { my $a = shift; my %h; for (my $i = 0; $i + 1 < @$a; $i += 2) { $h{$a->[$i]} = $a->[$i + 1]; } return \%h; }
    # name:type:token:flags:children, flags sorted and joined by commas.
    sub argument {
        my $a = kv(shift);
        my $kids = ref $a->{arguments} eq 'ARRAY' ? scalar(@{ $a->{arguments} }) : 0;
        return join(':', $a->{name}, $a->{type}, $a->{token} // '', join(',', sort @{ $a->{flags} // [] }), $kids);
    }
    my $c = open_to(7000);
    my $cat = ask($c, 'ACL', 'CAT', 'blocking');
    my %ask = map { $_ => 1 } qw(blpop brpop brpoplpush blmove blmovem blmpop bzpopmin bzpopmax bzmpop xread xreadgroup wait waitaof);
    if (ref $cat eq 'ARRAY') { print "blocking\t", join(' ', sort @$cat), "\n"; $ask{$_} = 1 for @$cat; }
    else { print "blocking\t-\n"; }
    for my $name (sort keys %ask) {
        my $d = ask($c, 'COMMAND', 'DOCS', $name);
        next unless ref $d eq 'ARRAY' && @$d == 2;   # a server before 7.0 has no COMMAND DOCS; one without the command, no entry
        my $doc = kv($d->[1]);
        print "docs\t$name\t", join(' ', map { argument($_) } @{ $doc->{arguments} // [] }), "\n";
    }
    close $c->{s};
}

# ---- Phase 4: pub/sub, under RESP2 and RESP3 ----
# A scene runs on a fresh pair of connections to one port: `a`, the subscriber, and `b`, another client. Its actions,
# in order:
#   ['a', n, @cmd]           send @cmd on a and read its next n values;
#   ['b', n, @cmd]           the same, on b;
#   ['send', @cmd]           send @cmd on a, and read nothing;
#   ['id']                   read a's CLIENT ID: "<id>" in a later command is replaced by it;
#   ['rec', case, n, @cmd]   send @cmd on a (nothing, when @cmd is empty), and record a's next n values as
#                            "<case>/<protocol>";
#   ['recb', case, n, @cmd]  the same, on b;
#   ['all', case, n, @cmd]   'rec', for an unsubscribe-all (canonical(), below).
# A read of n values stops after an error: the server refused the whole command, so nothing else is coming for it. A
# recorded case's setup is the scene's actions before it, b's marked "from another connection".
#
# An unsubscribe-all confirms each name in the order of the server's hash table. Redis seeds that hash at random in each
# process (Valkey 9.1 keeps the order of subscribing), so the bytes would differ from one run to the next. canonical()
# checks that the server confirmed exactly the names subscribed, each once, with counts falling by one, and records
# them in one order: sorted by name, the counts falling from the first. That is the order Valkey 9.1 sends, for names
# subscribed in sorted order, as every scene here subscribes them.
sub reads {
    my ($c, $n) = @_; my @got;
    for (1 .. $n) { my $r = reply($c); push @got, $r; last if $r =~ /\A[-!]/; }
    return @got;
}
sub canonical {
    my ($want, @frames) = @_;
    my @parts;
    for my $f (@frames) {
        $f =~ /\A([*>])3\r\n\$(\d+)\r\n([a-z]+)\r\n\$(\d+)\r\n(.*)\r\n:(\d+)\r\n\z/s && length($3) == $2 && length($5) == $4
            or die "canonical: not a confirmation: " . unpack('H*', $f) . "\n";
        push @parts, [$1, $3, $5, $6];
    }
    my @names = sort map { $_->[2] } @parts;
    die "canonical: confirmed [@names], subscribed [@$want]\n" unless "@names" eq join(' ', sort @$want);
    my @counts = sort { $b <=> $a } map { $_->[3] } @parts;
    for my $i (0 .. $#counts) { die "canonical: counts [@counts] do not fall by one\n" unless $counts[$i] == $counts[0] - $i; }
    my @sorted = sort { $a->[2] cmp $b->[2] } @parts;
    return join('', map { my ($t, $kind, $name) = @{ $sorted[$_] }; "${t}3\r\n\$" . length($kind) . "\r\n$kind\r\n\$" . length($name) . "\r\n$name\r\n:$counts[$_]\r\n" } 0 .. $#sorted);
}
sub scene {
    my ($proto, $port, @actions) = @_;
    my $a = open_to($port); my $b = open_to($port);
    call($a, 'HELLO', '3') if $proto == 3;
    my ($id, @setup) = ('');
    for my $act (@actions) {
        my ($what, @rest) = @$act;
        local $SIG{ALRM} = sub { die "scene: no answer to [$what @rest] on $port under RESP$proto\n" };
        alarm 10;
        if ($what eq 'id') {
            my $r = call($a, 'CLIENT', 'ID'); $r =~ /\A:(\d+)\r\n\z/ or die "CLIENT ID: $r\n"; $id = $1;
            push @setup, ['CLIENT', 'ID'];
        } elsif ($what eq 'send') {
            print { $a->{s} } enc(map { s/<id>/$id/r } @rest);
            push @setup, shown(@rest) . ', unanswered yet';
        } elsif ($what eq 'a' || $what eq 'b') {
            my ($n, @cmd) = @rest;
            my $c = $what eq 'a' ? $a : $b;
            print { $c->{s} } enc(map { s/<id>/$id/r } @cmd);
            reads($c, $n);
            push @setup, $what eq 'a' ? [@cmd] : shown(@cmd) . ', from another connection';
        } else {
            my ($case, $n, @cmd) = @rest;
            my $want = $what eq q(all) ? $n : undef;
            $n = @$want if $want;
            my $c = $what eq q(recb) ? $b : $a;
            print { $c->{s} } enc(map { s/<id>/$id/r } @cmd) if @cmd;
            my @got = reads($c, $n);
            my $r = $want ? canonical($want, @got) : join(q(), @got);
            my @shown = @cmd ? @cmd : ('(nothing: what arrives)');
            @shown = ('(from another connection)', @shown) if $what eq 'recb';
            record("$case/$proto", [@shown], $r, [@setup]);
            push @setup, $what eq 'recb' ? shown(@cmd) . ', from another connection' : [@cmd];
        }
        alarm 0;
    }
    close $a->{s}; close $b->{s};
}
{
    my $c = open_to(7000);
    my $sharded = ask($c, 'COMMAND', 'INFO', 'ssubscribe');
    $sharded = ref $sharded eq 'ARRAY' && defined $sharded->[0];
    close $c->{s};
    my $all = sub { my ($case, $want, @cmd) = @_; return [q(all), $case, $want, @cmd]; };
    for my $proto (2, 3) {
        # Confirmations: one per name, a name subscribed twice confirmed twice with the count unchanged.
        scene($proto, 7000, ['rec', 'sub-one', 1, 'SUBSCRIBE', 'kr:c1']);
        scene($proto, 7000, ['rec', 'sub-two', 2, 'SUBSCRIBE', 'kr:c1', 'kr:c2']);
        scene($proto, 7000, ['rec', 'sub-twice', 2, 'SUBSCRIBE', 'kr:c1', 'kr:c1']);
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'sub-again', 1, 'SUBSCRIBE', 'kr:c1']);
        scene($proto, 7000, ['rec', 'psub-two', 2, 'PSUBSCRIBE', 'kr:p*', 'kr:q*']);
        # On a standalone server, shard channels in different slots are accepted together. 6.2 refuses the command.
        scene($proto, 7000, ['rec', 'ssub-two', 2, 'SSUBSCRIBE', 'kr:s1', 'kr:s2']);
        # Unsubscribing by name, a name never subscribed included.
        scene($proto, 7000, ['a', 2, 'SUBSCRIBE', 'kr:c1', 'kr:c2'], ['rec', 'unsub-one', 1, 'UNSUBSCRIBE', 'kr:c1']);
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'unsub-never', 1, 'UNSUBSCRIBE', 'kr:nope']);
        scene($proto, 7000, ['a', 2, 'PSUBSCRIBE', 'kr:p*', 'kr:q*'], ['rec', 'punsub-one', 1, 'PUNSUBSCRIBE', 'kr:q*']);
        # Unsubscribing from all: one confirmation per name, the other kinds' counts included; with none, one with
        # a null name.
        scene($proto, 7000, ['rec', 'sub-three', 3, 'SUBSCRIBE', 'kr:c1', 'kr:c2', 'kr:c3'], ['rec', 'psub-after-three', 1, 'PSUBSCRIBE', 'kr:p*'],
              $all->('unsub-all', ['kr:c1', 'kr:c2', 'kr:c3'], 'UNSUBSCRIBE'));
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'psub-two-after-one', 2, 'PSUBSCRIBE', 'kr:p*', 'kr:q*'],
              $all->('punsub-all', ['kr:p*', 'kr:q*'], 'PUNSUBSCRIBE'));
        scene($proto, 7000, ['rec', 'unsub-none', 1, 'UNSUBSCRIBE']);
        scene($proto, 7000, ['rec', 'punsub-none', 1, 'PUNSUBSCRIBE']);
        scene($proto, 7000, ['rec', 'psub-one', 1, 'PSUBSCRIBE', 'kr:p*'], ['rec', 'unsub-none-pattern', 1, 'UNSUBSCRIBE']);
        if ($sharded) {
            scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'ssub-two-after-one', 2, 'SSUBSCRIBE', 'kr:s1', 'kr:s2'],
                  $all->('sunsub-all', ['kr:s1', 'kr:s2'], 'SUNSUBSCRIBE'));
            scene($proto, 7000, ['rec', 'sunsub-none', 1, 'SUNSUBSCRIBE']);
        }
        # Messages, from another connection: message, pmessage and smessage; binary and empty payloads; a message both
        # a channel and a pattern match, which comes twice.
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['recb', 'publish-one', 1, 'PUBLISH', 'kr:c1', 'hello'],
              ['rec', 'message', 1]);
        scene($proto, 7000, ['rec', 'sub-binary', 1, 'SUBSCRIBE', "kr:\x00\xff"], ['b', 1, 'PUBLISH', "kr:\x00\xff", $bin],
              ['rec', 'message-binary', 1]);
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['b', 1, 'PUBLISH', 'kr:c1', ''], ['rec', 'message-empty', 1]);
        scene($proto, 7000, ['a', 1, 'PSUBSCRIBE', 'kr:p*'], ['b', 1, 'PUBLISH', 'kr:p1', 'hello'], ['rec', 'pmessage', 1]);
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'psub-after-one', 1, 'PSUBSCRIBE', 'kr:c*'],
              ['recb', 'publish-two', 1, 'PUBLISH', 'kr:c1', 'hello'], ['rec', 'message-twice', 2]);
        if ($sharded) {
            scene($proto, 7000, ['rec', 'ssub-one', 1, 'SSUBSCRIBE', 'kr:s1'], ['recb', 'spublish-one', 1, 'SPUBLISH', 'kr:s1', 'hello'],
                  ['rec', 'smessage', 1]);
            # A plain PUBLISH does not reach a shard subscriber: the PING's answer is the next thing to come.
            scene($proto, 7000, ['a', 1, 'SSUBSCRIBE', 'kr:s1'], ['recb', 'publish-shard', 1, 'PUBLISH', 'kr:s1', 'hello'],
                  ['rec', 'shard-ping', 1, 'PING']);
        }
        # PING while subscribed (RESP2's ["pong", ""], RESP3's +PONG), and once every count is back to 0.
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'ping-subscribed', 1, 'PING']);
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'ping-subscribed-text', 1, 'PING', 'hello']);
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'unsub-last', 1, 'UNSUBSCRIBE', 'kr:c1'], ['rec', 'ping-left', 1, 'PING']);
        # What else a subscribed connection is told: RESP2 refuses other commands; RESP3 runs them.
        scene($proto, 7000, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'subscribed-get', 1, 'GET', 'kr:k']);
        # A user who may not subscribe (kr_ro has no @pubsub): one error, and no confirmation.
        scene($proto, 7000, ['a', 1, 'AUTH', 'kr_ro', 'kr_ro_pw'], ['rec', 'sub-noperm', 2, 'SUBSCRIBE', 'kr:c1', 'kr:c2']);
        # Invalidations another connection's tracking sends here (REDIRECT): RESP3's invalidate push, and RESP2's message
        # on __redis__:invalidate, whose payload is an array of keys, or a null for a flush.
        scene($proto, 7000, ['id'], ['a', 1, 'SUBSCRIBE', '__redis__:invalidate'],
              ['b', 1, 'CLIENT', 'TRACKING', 'on', 'REDIRECT', '<id>'], ['b', 1, 'GET', 'kr:t'], ['b', 1, 'SET', 'kr:t', '1'],
              ['rec', 'tracking-redirect', 1], ['b', 1, 'GET', 'kr:t'], ['b', 1, 'FLUSHALL'], ['rec', 'tracking-flush', 1]);
    }
    # A cluster of two nodes (7.0 and later): MOVED and CROSSSLOT in place of confirmations, and the server's own
    # sunsubscribe when a slot leaves the node. redis-cli --cluster create wants three primaries, so the two are joined
    # by hand. A slot taken away does not fail the cluster (cluster-require-full-coverage no).
    if ($sharded && $up{7100} && $up{7101}) {
        my $x = open_to(7100); my $y = open_to(7101);
        ask($x, 'CLUSTER', 'ADDSLOTSRANGE', '0', '8191');
        ask($y, 'CLUSTER', 'ADDSLOTSRANGE', '8192', '16383');
        ask($x, 'CLUSTER', 'MEET', '127.0.0.1', '7101');
        my $ready = 0;
        for (1 .. 400) {
            my $i = ask($x, 'CLUSTER', 'INFO'); my $j = ask($y, 'CLUSTER', 'INFO');
            if ("$i$j" !~ /cluster_state:(?!ok)/ && $i =~ /cluster_slots_assigned:16384/ && $j =~ /cluster_slots_assigned:16384/) { $ready = 1; last; }
            select(undef, undef, undef, 0.05);
        }
        die "the two-node cluster never came up\n" unless $ready;
        # Shard channels: two in the first node's slots, in different slots, and one in the second node's.
        my (@mine, $theirs);
        for my $k (map { "kr:s$_" } 1 .. 200) {
            my $slot = ask($x, 'CLUSTER', 'KEYSLOT', $k);
            if ($slot < 8192) { push @mine, [$k, $slot] if @mine < 4 && !grep { $_->[1] == $slot } @mine; }
            else { $theirs //= $k; }
            last if @mine == 4 && defined $theirs;
        }
        die "no shard channels for the cluster\n" unless @mine == 4 && defined $theirs;
        close $x->{s}; close $y->{s};
        for my $proto (2, 3) {
            my ($one, $other) = $proto == 2 ? @mine[0, 1] : @mine[2, 3];
            scene($proto, 7100, ['rec', 'cluster-crossslot', 2, 'SSUBSCRIBE', $one->[0], $other->[0]]);
            scene($proto, 7100, ['rec', 'cluster-moved', 1, 'SSUBSCRIBE', $theirs]);
            scene($proto, 7100, ['a', 1, 'SUBSCRIBE', 'kr:c1'], ['rec', 'cluster-ssub-one', 1, 'SSUBSCRIBE', $one->[0]],
                  ['b', 1, 'CLUSTER', 'DELSLOTS', $one->[1]], ['rec', 'cluster-sunsubscribe', 1], ['rec', 'cluster-sunsubscribe-ping', 1, 'PING']);
            scene($proto, 7100, ['rec', 'cluster-ssub-last', 1, 'SSUBSCRIBE', $other->[0]], ['b', 1, 'CLUSTER', 'DELSLOTS', $other->[1]],
                  ['rec', 'cluster-sunsubscribe-last', 1], ['rec', 'cluster-sunsubscribe-last-ping', 1, 'PING']);
        }
    }
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
my (@versions, %codeServers, @replies, %seen, @blocking, @docs);
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
    if ($what eq 'blocking') { push @blocking, [$version, $rest[0]]; next; }
    if ($what eq 'docs') { push @docs, ["$version $rest[0]", $rest[1]]; next; }
    push @replies, ["$version $what", $rest[0], $rest[1], $rest[2] // ''];
}
my %count; $count{(split / /, $_->[0])[1]}++ for @replies;
for my $must (qw(hello3 hello2 hello3-auth hello3-auth-wrong locked-hello3 locked-auth1 wrongtype unblocked busykey
                 get-hit/2 get-hit/3 exec-null/2 exec-null/3 exec-ok/3 queued/2 script-load evalsha-hit blpop-null/3)) {
    die "gen-server-vectors: case $must is not on every server\n" unless ($count{$must} // 0) == @versions;
}
die "gen-server-vectors: no compat-hello3 case\n" unless $count{'compat-hello3'};
for my $proto (2, 3) {
    for my $must (qw(sub-two sub-twice unsub-all punsub-all unsub-none message message-twice pmessage ping-subscribed ping-left
                     sub-noperm tracking-redirect tracking-flush)) {
        die "gen-server-vectors: case $must/$proto is not on every server\n" unless ($count{"$must/$proto"} // 0) == @versions;
    }
    # Sharded pub/sub is 7.0's: a server that answers SSUBSCRIBE has every sharded case, the cluster's included.
    my $sharded = grep { $_->[0] =~ / ssub-two\/$proto$/ && $_->[2] !~ /^2d/ } @replies;
    die "gen-server-vectors: no server answered SSUBSCRIBE\n" unless $sharded;
    for my $must (qw(sunsub-all smessage shard-ping cluster-crossslot cluster-moved cluster-sunsubscribe cluster-sunsubscribe-ping
                     cluster-sunsubscribe-last cluster-sunsubscribe-last-ping)) {
        die "gen-server-vectors: case $must/$proto is not on every server with sharded pub/sub\n" unless ($count{"$must/$proto"} // 0) == $sharded;
    }
}
die "gen-server-vectors: a server gave no blocking category\n" unless @blocking == @versions;
my %docServers; $docServers{(split / /, $_->[0])[0]}++ for @docs;
die "gen-server-vectors: no COMMAND DOCS from any server\n" unless %docServers;
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
//   - replySetups: the commands that ran before each case's command, on the same connection (joined by " ; "). The
//     typed pairs ("<case>/2", "<case>/3") ran on a fresh connection after FLUSHALL, under that protocol.
//   - Pub/sub (sub-two/2, message/3, cluster-moved/2, …): what a subscribing connection reads after its command, or
//     after another connection's (its setup says which), under each protocol; several values in one case are each
//     whole. An unsubscribe-all is recorded with its names sorted and its counts falling by one, the order Valkey
//     9.1 sends: Redis's order follows a hash seeded at random in each process. The cluster cases ran on two nodes
//     joined by hand (7.0 and later).
//   - blockingServers / blockingNames: each server's `ACL CAT blocking`, sorted.
//   - docsNames / docsArgs: "<server> <command>" for each blocking command a server documents (7.0 and later), and
//     its arguments from COMMAND DOCS, each name:type:token:flags:children.
//   - proxyNames / proxyHex: Envoy's redis proxy's answers to HELLO, read from its source (v1.32.0, v1.36.0,
//     v1.39.0), with and without a password required.
import { std::collections::DynamicArray };
export { serverVersions, sentCodes, codeServers, replyNames, replyCommands, replyHex, replySetups, blockingServers,
         blockingNames, docsNames, docsArgs, proxyNames, proxyHex };

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
column('replySetups', map { lit($_->[3]) } @replies);
column('blockingServers', map { lit($_->[0]) } @blocking);
column('blockingNames', map { lit($_->[1]) } @blocking);
column('docsNames', map { lit($_->[0]) } @docs);
column('docsArgs', map { lit($_->[1]) } @docs);
column('proxyNames', map { lit($_->[0]) } @proxy);
column('proxyHex', map { lit($_->[1]) } @proxy);
close $o;
printf "gen-server-vectors: %d codes, %d replies, %d blocking commands documented, %d proxy answers, from %s into %s\n", scalar(@codes), scalar(@replies), scalar(@docs), scalar(@proxy), $who, $out;
PERL

perl "$tmp/gen.pl" "$tmp" "$OUT"
