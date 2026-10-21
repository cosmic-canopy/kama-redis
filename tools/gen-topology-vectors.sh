#!/bin/sh
# gen-topology-vectors.sh — write tests/unit/src/topology_vectors.kama: what a cluster's nodes and Sentinel answer a
# client, byte for byte, for the cluster's and Sentinel's tests to replay through the fake server (docs/ROADMAP.md,
# "Phase 6").
#
# Each server in the matrix (tools/redis.sh list) is asked live, in a throwaway container with no network:
#   - A server not in cluster mode (7400), for CLUSTER SLOTS's refusal there.
#   - A cluster of six nodes (7000-7005), built by hand so that it comes out the same every run: three primaries
#     with the slots in thirds, each with one replica (7003 of 7000, 7004 of 7001, 7005 of 7002). What it answers:
#     CLUSTER SLOTS, before the slots are assigned and after; a node's HELLO; the pieces of a command split by slot or sent to every primary (MGET, EXISTS,
#     MSET, DBSIZE, KEYS, PING, SCRIPT EXISTS, each at its own node); MOVED from a primary and from a replica; CROSSSLOT; a redirection while queueing in MULTI, then
#     EXEC's EXECABORT, and EXEC's own CROSSSLOT; a slot being migrated (ASK, TRYAGAIN, a transaction at its source,
#     MOVED back without ASKING, ASKING for one command, ASKING then a transaction); READONLY and READWRITE on a replica; a slot not served and
#     the map with its gap; the map and MOVED after a CLUSTER FAILOVER, and a shard channel's subscriber at the old
#     primary then (the server's own sunsubscribe); the map and MOVED with hostnames and with an
#     unknown endpoint (7.0 and later); MASTERDOWN; and the cluster down, in both words.
#   - A sentinel group: a master (7200), two replicas (7201, 7202) and four sentinels (7300-7303) monitoring "kr",
#     the last one with its default user off. What a client meets: HELLO 3; GET-MASTER-ADDR-BY-NAME, known and not
#     (and GET-PRIMARY-ADDR-BY-NAME, Valkey 8 and later); SENTINELS and REPLICAS, healthy and with a replica down;
#     ROLE on a master, a replica and a sentinel; SELECT, CLIENT SETINFO and SETNAME on a sentinel; the password a
#     sentinel wants; then a SENTINEL FAILOVER: the +switch-master message (under RESP2 and RESP3), the clients of the
#     old master and of the promoted replica let go without a byte, a BLPOP unblocked, the new master's address, and
#     the old master's READONLY and ROLE once it is a replica.
#   - Client-side caching across both failovers (phase 7b): a tracking client (RESP3, OPTIN) that read a key at each
#     node of the shard and of the Sentinel group. What the cluster's two get as the shard changes hands (nothing, and
#     they stay open), and when the new primary writes the key (its invalidation, at both); Sentinel lets its two go,
#     without a byte, as it does any client. The script requires each.
#
# Every case runs under RESP2 and RESP3 ("<case>/2", "<case>/3"), each on a connection of its own. What changes from
# run to run is made canonical, so two runs give the same file:
#   - a node's id is replaced by its port, zero-padded to the id's 40 characters ("000…7000");
#   - in a SENTINELS or REPLICAS reply, each value that moves with time (run ids, ping times, offsets, epochs) is 0
#     and the entries are sorted by address (a sentinel keeps them in a hash table seeded at random); a sentinel's
#     name, its run id, is its port padded the same way;
#   - in ROLE, the replication offsets are 0, and a master's replicas are sorted;
#   - in a sentinel's HELLO, the client id is 0 (it counts the sentinels' own connections too).
# The re-encoding keeps each value's RESP form, so only those values differ from what the server sent.
#
# A reply over TLS has the same bytes as in plaintext, but for the port it names, which tools/redis.sh's smoke and the
# integration suite check live: the containers here have no network, and their Perl no TLS.
#
# Run it, then `git diff` must be empty unless a server image moved (the header names each server's version).
# `tools/gen-topology-vectors.sh redis-8.10 …` asks only those servers, to debug a case; the file is made from all.
# Needs perl and podman or docker.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/tests/unit/src/topology_vectors.kama"
SERVERS=$("$ROOT/tools/redis.sh" list)
[ $# -gt 0 ] && SERVERS="$*"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if [ -n "${CONTAINER_RUNTIME:-}" ]; then RT=$CONTAINER_RUNTIME
elif command -v podman >/dev/null 2>&1; then RT=podman
elif command -v docker >/dev/null 2>&1; then RT=docker
else echo "gen-topology-vectors: neither podman nor docker found (set CONTAINER_RUNTIME)" >&2; exit 1
fi

# In the container: start every server, then the cases (ask.pl). The first line out is the server's version.
cat > "$tmp/run.sh" <<'SH'
set -u
cat > /tmp/ask.pl
version=$(redis-server --version | sed -n "s/.*[Ss]erver v=\([0-9.]*\) .*/\1/p")
product=redis
case "$(redis-server --version)" in Redis*) ;; *) product=valkey ;; esac
for p in 7000 7001 7002 7003 7004 7005; do
    mkdir -p /tmp/c$p
    redis-server --port $p --dir /tmp/c$p --cluster-enabled yes --cluster-config-file /tmp/c$p/nodes.conf \
        --cluster-node-timeout 2000 --save "" --appendonly no --daemonize yes --logfile /tmp/c$p/log >/dev/null 2>&1
done
redis-server --port 7200 --save "" --appendonly no --daemonize yes --logfile /tmp/d7200.log >/dev/null 2>&1
# A server not in cluster mode, for what CLUSTER SLOTS answers there.
redis-server --port 7400 --save "" --appendonly no --daemonize yes --logfile /tmp/s7400.log >/dev/null 2>&1
for p in 7201 7202; do
    redis-server --port $p --replicaof 127.0.0.1 7200 --save "" --appendonly no --daemonize yes --logfile /tmp/d$p.log >/dev/null 2>&1
done
for p in 7300 7301 7302 7303; do
    default="user default on nopass allchannels +@all"
    [ $p = 7303 ] && default="user default off"
    cat > /tmp/s$p.conf <<CONF
port $p
dir /tmp
logfile /tmp/s$p.log
sentinel monitor kr 127.0.0.1 7200 2
sentinel down-after-milliseconds kr 1000
sentinel failover-timeout kr 4000
sentinel parallel-syncs kr 1
$default
user kr_sentinel on >kr_sentinel_pw allchannels +@all
sentinel sentinel-user kr_sentinel
sentinel sentinel-pass kr_sentinel_pw
CONF
    redis-server /tmp/s$p.conf --sentinel --daemonize yes >/dev/null 2>&1
done
echo "$version"
perl /tmp/ask.pl "$product" "$version"
SH

cat > "$tmp/ask.pl" <<'PERL'
use strict; use warnings; use IO::Socket::INET; use IO::Select;
my ($product, $version) = @ARGV;
my ($major, $minor) = split /\./, $version;
my $v7 = $major >= 7;
# A server that never gets where a case waits for ends the run, rather than hanging it.
$SIG{ALRM} = sub { die "gen-topology-vectors: $product $version timed out\n"; };
alarm 300;
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
# A whole value as [type, payload]: a string's bytes (undef for a null), an aggregate's elements, a line's text.
sub tparse {
    my $c = shift;
    my $l = line($c); my $t = substr($l, 0, 1); my $n = substr($l, 1);
    if ($t =~ /[\$!=]/) {
        return [$t, undef] if $n < 0;
        more($c) while length($c->{buf}) < $c->{pos} + $n + 2;
        my $s = substr($c->{buf}, $c->{pos}, $n); $c->{pos} += $n + 2; return [$t, $s];
    }
    if ($t =~ /[*~>]/) { return [$t, undef] if $n < 0; return [$t, [map { tparse($c) } 1 .. $n]]; }
    if ($t eq '%') { return [$t, [map { tparse($c) } 1 .. 2 * $n]]; }
    die "unexpected reply line '$l'\n" unless $t =~ /[-+:,#_(]/;
    return [$t, $n];
}
# The value back as RESP, in the form it came in.
sub tenc {
    my $v = shift; my ($t, $p) = @$v;
    return defined $p ? $t . length($p) . "\r\n$p\r\n" : "$t-1\r\n" if $t =~ /[\$!=]/;
    return defined $p ? $t . scalar(@$p) . "\r\n" . join('', map { tenc($_) } @$p) : "$t-1\r\n" if $t =~ /[*~>]/;
    return '%' . (@$p / 2) . "\r\n" . join('', map { tenc($_) } @$p) if $t eq '%';
    return "$t$p\r\n";
}
sub take { my $c = shift; my $v = tparse($c); $c->{buf} = substr($c->{buf}, $c->{pos}); $c->{pos} = 0; return $v; }
sub tcall { my ($c, @cmd) = @_; print { $c->{s} } enc(@cmd); return take($c); }
sub str { my $v = shift; return $v->[0] =~ /[\$+:]/ ? $v->[1] : undef; }
# An argument with a byte outside printable ASCII is shown as <hex:…>, so every shown command is exact.
sub shown { return join(' ', map { /[^\x20-\x7e]/ ? '<hex:' . unpack('H*', $_) . '>' : /[ ']/ || $_ eq '' ? "'$_'" : $_ } @_); }
# A node's id, from CLUSTER MYID, and what it is written as: its port, zero-padded to 40 characters.
my %canonId;
sub canonical { my $b = shift; $b =~ s/$_/$canonId{$_}/g for keys %canonId; return $b; }
# <case> TAB <command> TAB <reply, hex> TAB <setup: its commands, shown, joined by " ; "; a string is taken as written>
sub record {
    my ($case, $cmd, $bytes, $setup) = @_;
    my $set = join(' ; ', map { ref $_ ? shown(@$_) : $_ } @{ $setup // [] });
    print "$case\t", shown(@$cmd), "\t", unpack('H*', canonical($bytes)), "\t$set\n";
}
sub ending { my ($case, $closed) = @_; print "ending\t$case\t", ($closed ? 'closed' : 'open'), "\n"; }
sub drain_for {   # what comes, until `$quiet` seconds of silence or the end of the stream
    my ($c, $quiet) = @_; my $got = substr($c->{buf}, $c->{pos}); my $closed = 0;
    $c->{buf} = ''; $c->{pos} = 0;
    my $sel = IO::Select->new($c->{s});
    while ($sel->can_read($quiet)) {
        my $n = sysread($c->{s}, my $chunk, 65536);
        if (!$n) { $closed = 1; last; }
        $got .= $chunk;
    }
    return ($got, $closed);
}
# A HELLO's client id counts the sentinels' own connections too, so it is 0 in what is recorded.
sub canon_hello { my $v = shift; my $it = $v->[1]; for (my $i = 0; $i + 1 < @$it; $i += 2) { $it->[$i + 1] = [':', 0] if (str($it->[$i]) // '') eq 'id'; } return $v; }
sub until_true {   # until_true <what> <seconds> <test>
    my ($what, $secs, $test) = @_;
    for (1 .. $secs * 20) { return if $test->(); select(undef, undef, undef, 0.05); }
    die "gen-topology-vectors: $product $version: $what did not happen in ${secs}s\n";
}
sub one { my ($port, @cmd) = @_; my $c = open_to($port); my $v = tcall($c, @cmd); close $c->{s}; return $v; }
sub text { my ($port, @cmd) = @_; my $v = one($port, @cmd); return str($v) // ''; }
# A case under both protocols, each on a fresh connection: HELLO 3 first for RESP3, then the setup (replies
# dropped), then the command, whose reply is `$shape`d (canonical values) and recorded.
# A case right after a failover can lose its connection to the sentinels' own CLIENT KILL, which they send again as
# they settle: it is asked again, on a new connection, a few times.
sub again { my $do = shift; for my $n (1 .. 5) { my $ok = eval { $do->(); 1 }; return if $ok; die $@ unless $@ eq "eof\n" && $n < 5; select(undef, undef, undef, 0.5); } }
sub pair {
    my ($case, $port, $setup, $cmd, $shape) = @_;
    again(sub { pair_once($case, $port, $setup, $cmd, $shape); });
}
sub pair_once {
    my ($case, $port, $setup, $cmd, $shape) = @_;
    my @out;
    for my $proto (2, 3) {
        my $c = open_to($port);
        tcall($c, 'HELLO', '3') if $proto == 3;
        tcall($c, @$_) for @$setup;
        my $v = tcall($c, @$cmd);
        $v = $shape->($v) if $shape;
        push @out, ["$case/$proto", $cmd, tenc($v), $setup];
        close $c->{s};
    }
    record(@$_) for @out;
}

# ---- The cluster, by hand ----
my @nodes = (7000 .. 7005);
my %id = map { $_ => text($_, 'CLUSTER', 'MYID') } @nodes;
%canonId = map { $id{$_} => sprintf('%040d', $_) } @nodes;
my $epoch = 1;
one($_, 'CLUSTER', 'SET-CONFIG-EPOCH', $epoch++) for @nodes;
# A node of a cluster whose slots are not yet assigned: its map serves nothing.
pair('slots-empty', 7000, [], ['CLUSTER', 'SLOTS']);
my @thirds = ([0, 5460], [5461, 10922], [10923, 16383]);
for my $i (0 .. 2) { one(7000 + $i, 'CLUSTER', 'ADDSLOTS', $thirds[$i][0] .. $thirds[$i][1]); }
one(7000, 'CLUSTER', 'MEET', '127.0.0.1', $_) for 7001 .. 7005;
until_true('the six nodes meeting', 30, sub { !grep { text($_, 'CLUSTER', 'INFO') !~ /cluster_known_nodes:6\r?\n/ } @nodes });
one(7003 + $_, 'CLUSTER', 'REPLICATE', $id{7000 + $_}) for 0 .. 2;
until_true('the cluster coming up', 60, sub {
    return 0 if grep { text($_, 'CLUSTER', 'INFO') !~ /cluster_state:ok/ } @nodes;
    return 0 if grep { text(7003 + $_, 'INFO', 'replication') !~ /master_link_status:up/ } 0 .. 2;
    # Every node's map: three shards, each with its replica (CLUSTER SLOTS leaves out a replica at offset 0).
    for my $n (@nodes) { my $m = one($n, 'CLUSTER', 'SLOTS'); return 0 unless @{ $m->[1] } == 3 && !grep { @{ $_->[1] } != 4 } @{ $m->[1] }; }
    return 1;
});
sub slot { return text(7000, 'CLUSTER', 'KEYSLOT', shift); }
sub shard { my $s = shift; for my $i (0 .. 2) { return $i if $s >= $thirds[$i][0] && $s <= $thirds[$i][1]; } }
# Keys by shard: kr:a is the first kr:N in shard 0, kr:a2 the next in shard 0 in another slot; kr:b and kr:c the
# first in shards 1 and 2. A hash tag {m…} in shard 0 gives the migrated slot's two keys.
my (%key, %taken);
for my $n (0 .. 10000) {
    my $k = "kr:$n"; my $s = slot($k); my $h = shard($s);
    if ($h == 0 && !$key{a}) { $key{a} = $k; $taken{$s} = 1; }
    elsif ($h == 0 && !$key{a2} && !$taken{$s}) { $key{a2} = $k; }
    elsif ($h == 1 && !$key{b}) { $key{b} = $k; }
    elsif ($h == 2 && !$key{c}) { $key{c} = $k; }
    last if $key{a} && $key{a2} && $key{b} && $key{c};
}
my $tag; for my $n (0 .. 10000) { my $s = slot("{m$n}"); if (shard($s) == 0 && !$taken{$s} && $s != slot($key{a2})) { $tag = "m$n"; last; } }
my ($kA, $kA2, $kB, $kC) = @key{qw(a a2 b c)};
my ($mx, $my) = ("kr:{$tag}x", "kr:{$tag}y");
my $mslot = slot($mx);
print "keys\t$kA $kA2 $kB $kC $mx $my\n";
{ my $c = open_to(7000); tcall($c, 'SET', $kA, 'va'); tcall($c, 'SET', $mx, 'vx'); tcall($c, 'WAIT', '1', '2000'); close $c->{s}; }
{ my $c = open_to(7002); tcall($c, 'SET', $kC, 'vc'); tcall($c, 'WAIT', '1', '2000'); close $c->{s}; }

pair('slots', 7000, [], ['CLUSTER', 'SLOTS']);
pair('slots-standalone', 7400, [], ['CLUSTER', 'SLOTS']);
pair('slots-at-replica', 7003, [], ['CLUSTER', 'SLOTS']);
# A node's own HELLO: what a cluster's connection to each node meets first.
{ my $c = open_to(7000); record('hello3-node', ['HELLO', '3'], tenc(canon_hello(tcall($c, 'HELLO', '3')))); close $c->{s}; }
# What the pieces of a call split by slot, or sent to every primary, meet (the commands' tips): each at its own node.
# The script's SHA1 is that of "return 1", which only 7000 has.
my $sha = 'e0e1f9fabfc9d4800c877a703b823ac0578ff8db';
pair('mget-a', 7000, [], ['MGET', $kA]);
pair('mget-b', 7001, [], ['MGET', $kB]);
pair('mget-c', 7002, [], ['MGET', $kC]);
pair('mget-tag', 7000, [], ['MGET', $mx, $my]);
pair('exists-a', 7000, [], ['EXISTS', $kA]);
pair('exists-b', 7001, [], ['EXISTS', $kB]);
pair('exists-c', 7002, [], ['EXISTS', $kC]);
pair('mset-a', 7000, [], ['MSET', $kA, 'va']);
pair('dbsize-a', 7000, [], ['DBSIZE']);
pair('dbsize-b', 7001, [], ['DBSIZE']);
pair('dbsize-c', 7002, [], ['DBSIZE']);
pair('keys-a', 7000, [], ['KEYS', $kA]);
pair('keys-b', 7001, [], ['KEYS', $kA]);
pair('ping-node', 7000, [], ['PING']);
pair('script-exists-a', 7000, [['SCRIPT', 'LOAD', 'return 1']], ['SCRIPT', 'EXISTS', $sha]);
pair('script-exists-b', 7001, [], ['SCRIPT', 'EXISTS', $sha]);
pair('moved', 7000, [], ['GET', $kB]);
pair('crossslot', 7000, [], ['MGET', $kA, $kB]);
pair('crossslot-one-node', 7000, [], ['MGET', $kA, $kA2]);
pair('multi-moved', 7000, [['MULTI']], ['GET', $kB]);
pair('exec-after-moved', 7000, [['MULTI'], ['GET', $kB]], ['EXEC']);
pair('exec-crossslot', 7000, [['MULTI'], ['SET', $kA, '1'], ['SET', $kA2, '2']], ['EXEC']);
pair('replica-get', 7003, [], ['GET', $kA]);
pair('replica-readonly', 7003, [], ['READONLY']);
pair('replica-get-readonly', 7003, [['READONLY']], ['GET', $kA]);
pair('replica-set-readonly', 7003, [['READONLY']], ['SET', $kA, 'x']);
pair('replica-readwrite', 7003, [['READONLY']], ['READWRITE']);
pair('replica-get-readwrite', 7003, [['READONLY'], ['READWRITE']], ['GET', $kA]);
pair('replica-keyless-write', 7003, [], ['FLUSHALL']);

# A slot being migrated from 7000 to 7001: $mx is still on the source, $my on neither.
one(7001, 'CLUSTER', 'SETSLOT', $mslot, 'IMPORTING', $id{7000});
one(7000, 'CLUSTER', 'SETSLOT', $mslot, 'MIGRATING', $id{7001});
pair('ask', 7000, [], ['GET', $my]);
pair('migrating-served', 7000, [], ['GET', $mx]);
pair('migrating-tryagain', 7000, [], ['MGET', $mx, $my]);
# A transaction in the migrating slot, at its source: each command redirected as it queues (QUEUED on Valkey 9.1, which
# answers at EXEC for the whole transaction), then EXEC, for a key the source lacks and for one it has beside it.
pair('multi-ask', 7000, [['MULTI']], ['GET', $my]);
pair('exec-after-ask', 7000, [['MULTI'], ['GET', $my]], ['EXEC']);
pair('exec-after-mixed', 7000, [['MULTI'], ['GET', $mx], ['GET', $my]], ['EXEC']);
pair('importing-moved', 7001, [], ['GET', $my]);
pair('asking', 7001, [], ['ASKING']);
pair('importing-asking', 7001, [['ASKING']], ['GET', $my]);
pair('importing-asking-tryagain', 7001, [['ASKING']], ['MGET', $mx, $my]);
pair('importing-asking-once', 7001, [['ASKING'], ['GET', $my]], ['GET', $my]);
pair('importing-asking-multi', 7001, [['ASKING'], ['MULTI'], ['SET', $my, 'vy']], ['EXEC']);
# The migration undone: the key the transaction wrote on the target goes first, since a node refuses to give up a slot
# it still holds keys in.
{ my $c = open_to(7001); tcall($c, 'ASKING'); tcall($c, 'DEL', $my); close $c->{s}; }
# STABLE clears both nodes' states (SETSLOT … NODE of another node leaves the importing one's).
one($_, 'CLUSTER', 'SETSLOT', $mslot, 'STABLE') for 7001, 7000;
sub first { my $v = one(@_); return $v->[0] . ($v->[1] // ''); }
until_true('the migration being undone', 30, sub { first(7001, 'GET', $my) =~ /\A-MOVED \d+ 127\.0\.0\.1:7000\z/ && first(7000, 'GET', $my) eq '$' });

# A slot not served: every node forgets 7000's slot of $kA (the cluster stays up without full coverage).
one($_, 'CONFIG', 'SET', 'cluster-require-full-coverage', 'no') for @nodes;
my $aslot = slot($kA);
one($_, 'CLUSTER', 'DELSLOTS', $aslot) for @nodes;
until_true("slot $aslot unassigned everywhere", 30, sub {
    !grep { my $m = one($_, 'CLUSTER', 'SLOTS'); grep { $_->[1][0][1] <= $aslot && $_->[1][1][1] >= $aslot } @{ $m->[1] } } @nodes });
pair('not-served', 7000, [], ['GET', $kA]);
pair('slots-gap', 7000, [], ['CLUSTER', 'SLOTS']);
one(7000, 'CLUSTER', 'ADDSLOTS', $aslot);
until_true("slot $aslot served again everywhere", 30, sub {
    !grep { my $m = one($_, 'CLUSTER', 'SLOTS'); @{ $m->[1] } != 3 } @nodes });

# Hostnames and an unknown endpoint, the asking node's choice (7.0 and later).
if ($v7) {
    one($_, 'CONFIG', 'SET', 'cluster-announce-hostname', "node-$_.kr.test") for @nodes;
    one(7000, 'CONFIG', 'SET', 'cluster-preferred-endpoint-type', 'hostname');
    until_true('every hostname known', 30, sub { my $m = tenc(one(7000, 'CLUSTER', 'SLOTS')); !grep { index($m, "node-$_.kr.test") < 0 } @nodes });
    pair('slots-hostname', 7000, [], ['CLUSTER', 'SLOTS']);
    pair('moved-hostname', 7000, [], ['GET', $kB]);
    one(7000, 'CONFIG', 'SET', 'cluster-preferred-endpoint-type', 'unknown-endpoint');
    pair('slots-unknown-endpoint', 7000, [], ['CLUSTER', 'SLOTS']);
    pair('moved-unknown-endpoint', 7000, [], ['GET', $kB]);
    one(7000, 'CONFIG', 'SET', 'cluster-preferred-endpoint-type', 'ip');
    one($_, 'CONFIG', 'SET', 'cluster-announce-hostname', '') for @nodes;
    until_true('the hostnames gone', 30, sub { index(tenc(one(7000, 'CLUSTER', 'SLOTS')), 'kr.test') < 0 });
}
# Valkey's availability zone (8.1 and later), in the map's metadata. The zones reach 7000 by gossip, so the map is
# taken once every one shows, or once none has in five seconds (a server that does not put them in the map); some but
# not all would be a race, and stops the run.
if ($product eq 'valkey' && ($major > 8 || ($major == 8 && $minor >= 1))) {
    one($_, 'CONFIG', 'SET', 'availability-zone', "az-$_") for @nodes;
    my $shown = 0;
    for (1 .. 100) {
        my $m = tenc(one(7000, 'CLUSTER', 'SLOTS'));
        $shown = grep { index($m, "az-$_") >= 0 } @nodes;
        last if $shown == @nodes;
        select(undef, undef, undef, 0.05);
    }
    die "gen-topology-vectors: $product $version: the map shows $shown of six zones\n" if $shown && $shown != @nodes;
    pair('slots-zone', 7000, [], ['CLUSTER', 'SLOTS']);
    one($_, 'CONFIG', 'SET', 'availability-zone', '') for @nodes;
    until_true('the zones gone', 30, sub { index(tenc(one(7000, 'CLUSTER', 'SLOTS')), 'az-') < 0 });
}

# A shard channel of shard 1 subscribed at 7001 under each protocol: what that connection gets once 7004 has taken the
# shard over is the server's own sunsubscribe, which a cluster's subscriber follows to the new owner.
# Sharded pub/sub came with 7.0.
my %ssub;
if ($v7) {
    for my $proto (2, 3) {
        my $s = open_to(7001); tcall($s, 'HELLO', '3') if $proto == 3;
        record("ssub-shard/$proto", ['SSUBSCRIBE', $kB], tenc(tcall($s, 'SSUBSCRIBE', $kB)));
        $ssub{$proto} = $s;
    }
}
# Client-side caching across the failover (phase 7b): a tracking client (RESP3, OPTIN) that read the shard's key at
# 7001, its primary, and one at 7004, its replica, after READONLY. What each gets as the shard changes hands, and then
# when the new primary writes the key.
my %tracker;
for my $port (7001, 7004) {
    my $t = open_to($port); tcall($t, 'HELLO', '3'); tcall($t, 'READONLY') if $port == 7004;
    tcall($t, 'CLIENT', 'TRACKING', 'ON', 'OPTIN'); tcall($t, 'CLIENT', 'CACHING', 'YES'); tcall($t, 'GET', $kB);
    $tracker{$port} = $t;
}
# A manual failover: 7004 takes shard 1 over from 7001.
one(7004, 'CLUSTER', 'FAILOVER');
until_true('7004 taking shard 1 over', 30, sub {
    return 0 unless (str(one(7004, 'ROLE')->[1][0]) // '') eq 'master';
    return 0 if text(7001, 'INFO', 'replication') !~ /master_link_status:up/;
    for my $n (@nodes) {
        my $m = one($n, 'CLUSTER', 'SLOTS');
        my ($s1) = grep { $_->[1][0][1] == 5461 } @{ $m->[1] };
        return 0 unless $s1 && @{ $s1->[1] } == 4 && $s1->[1][2][1][1][1] == 7004 && $s1->[1][3][1][1][1] == 7001;
    }
    return 1;
});
if ($v7) {
    for my $proto (2, 3) {
        my ($got, $closed) = drain_for($ssub{$proto}, 2);
        die "gen-topology-vectors: $product $version: no sunsubscribe at 7001 after the failover ($proto)\n" unless index($got, 'sunsubscribe') >= 0 && !$closed;
        record("sunsubscribe-failover/$proto", ['SSUBSCRIBE', $kB], $got, ["SSUBSCRIBE $kB at 7001, then CLUSTER FAILOVER at 7004"]);
        close $ssub{$proto}{s};
    }
    pair('ssub-shard-moved', 7004, [], ['SSUBSCRIBE', $kB]);
}
for my $step ('', '-write') {
    one(7004, 'SET', $kB, 'after') if $step;
    for my $port (7001, 7004) {
        my ($got, $closed) = drain_for($tracker{$port}, 2);
        my $name = ($port == 7001 ? 'tracked-failover-demoted' : 'tracked-failover-promoted') . $step;
        my $setup = "HELLO 3, " . ($port == 7004 ? 'READONLY, ' : '') . "CLIENT TRACKING ON OPTIN, CLIENT CACHING YES and GET $kB at $port, then CLUSTER FAILOVER at 7004";
        record($name, ['(nothing: what arrives)'], $got, [$setup . ($step ? ", then SET $kB at 7004" : '')]);
        ending($name, $closed);
    }
}
close $tracker{$_}{s} for 7001, 7004;
pair('slots-after-failover', 7000, [], ['CLUSTER', 'SLOTS']);
pair('moved-after-failover', 7000, [], ['GET', $kB]);
pair('moved-from-demoted', 7001, [], ['GET', $kB]);

# MASTERDOWN, then the cluster down: shard 2's primary stops, its replica neither serves stale data nor fails over.
one(7005, 'CONFIG', 'SET', 'cluster-replica-no-failover', 'yes');
one(7005, 'CONFIG', 'SET', 'replica-serve-stale-data', 'no');
{ my $c = open_to(7002); print { $c->{s} } enc('SHUTDOWN', 'NOSAVE'); drain_for($c, 2); close $c->{s}; }
until_true("7005's link to its primary down", 30, sub { text(7005, 'INFO', 'replication') =~ /master_link_status:down/ });
pair('masterdown', 7005, [['READONLY']], ['GET', $kC]);
one($_, 'CONFIG', 'SET', 'cluster-require-full-coverage', 'yes') for 7000, 7001, 7003, 7004, 7005;
until_true('the cluster down at 7000', 30, sub { text(7000, 'CLUSTER', 'INFO') =~ /cluster_state:fail/ });
pair('clusterdown', 7000, [], ['GET', $kA]);
one(7000, 'CONFIG', 'SET', 'cluster-allow-reads-when-down', 'yes');
pair('clusterdown-read', 7000, [], ['GET', $kA]);
pair('clusterdown-write', 7000, [], ['SET', $kA, 'x']);
%canonId = ();

# ---- Sentinel ----
my @sentinels = (7300 .. 7303);
my $kr = [['AUTH', 'kr_sentinel', 'kr_sentinel_pw']];
sub sent { my ($port, @cmd) = @_; my $c = open_to($port); tcall($c, @$_) for @$kr; my $v = tcall($c, @cmd); close $c->{s}; return $v; }
sub count_flags { my ($v, $flags) = @_; return 0 unless $v->[0] eq '*' && $v->[1]; return scalar grep { field($_, 'flags') eq $flags } @{ $v->[1] }; }
sub field {
    my ($v, $name) = @_; my $it = $v->[1] // [];
    for (my $i = 0; $i + 1 < @$it; $i += 2) { my $k = str($it->[$i]); return str($it->[$i + 1]) // '' if defined $k && $k eq $name; }
    return '';
}
until_true('the sentinels knowing the group', 60, sub {
    for my $s (@sentinels) {
        my $m = sent($s, 'SENTINEL', 'GET-MASTER-ADDR-BY-NAME', 'kr');
        return 0 unless $m->[0] eq '*' && $m->[1] && str($m->[1][1]) eq '7200';
        return 0 unless count_flags(sent($s, 'SENTINEL', 'REPLICAS', 'kr'), 'slave') == 2;
        return 0 unless count_flags(sent($s, 'SENTINEL', 'SENTINELS', 'kr'), 'sentinel') == 3;
    }
    return 1;
});
my %moves = map { $_ => 1 } qw(runid link-pending-commands link-refcount last-ping-sent last-ok-ping-reply last-ping-reply
    s-down-time o-down-time info-refresh role-reported-time master-link-down-time slave-repl-offset last-hello-message
    voted-leader-epoch config-epoch failover-state);
# One instance of a SENTINELS or REPLICAS reply, a map (RESP3) or a flat array (RESP2): what moves made canonical.
sub canon_instance {
    my $v = shift; my $it = $v->[1]; my $port = field($v, 'port');
    for (my $i = 0; $i + 1 < @$it; $i += 2) {
        my $k = str($it->[$i]) // next; my $val = $it->[$i + 1];
        if ($k eq 'runid' || ($k eq 'name' && (str($val) // '') =~ /\A[0-9a-f]{40}\z/)) { $it->[$i + 1] = [$val->[0], sprintf('%040d', $port)]; }
        elsif ($k eq 'voted-leader') { $it->[$i + 1] = [$val->[0], '?']; }
        elsif ($moves{$k}) { $it->[$i + 1] = [$val->[0], $val->[0] eq ':' ? 0 : '0']; }
    }
    return $v;
}
sub canon_list {
    my $v = shift;
    return $v unless $v->[0] eq '*' && $v->[1];
    $v->[1] = [sort { field($a, 'ip') . ':' . field($a, 'port') cmp field($b, 'ip') . ':' . field($b, 'port') } map { canon_instance($_) } @{ $v->[1] }];
    return $v;
}
sub canon_role {
    my $v = shift; my $it = $v->[1]; my $kind = str($it->[0]) // '';
    if ($kind eq 'master') {
        $it->[1] = [':', 0];
        $_->[1][2] = [$_->[1][2][0], '0'] for @{ $it->[2][1] };
        $it->[2][1] = [sort { str($a->[1][1]) cmp str($b->[1][1]) } @{ $it->[2][1] }];
    } elsif ($kind eq 'slave') { $it->[4] = [':', 0]; }
    return $v;
}
{
    my $c = open_to(7300);
    record('sentinel-hello3', ['HELLO', '3'], tenc(canon_hello(tcall($c, 'HELLO', '3'))));
    close $c->{s};
}
pair('get-master-addr', 7300, [], ['SENTINEL', 'GET-MASTER-ADDR-BY-NAME', 'kr']);
pair('get-master-addr-unknown', 7300, [], ['SENTINEL', 'GET-MASTER-ADDR-BY-NAME', 'nosuch']);
pair('get-primary-addr', 7300, [], ['SENTINEL', 'GET-PRIMARY-ADDR-BY-NAME', 'kr']) if $product eq 'valkey' && $major >= 8;
pair('sentinels', 7300, [], ['SENTINEL', 'SENTINELS', 'kr'], \&canon_list);
pair('replicas', 7300, [], ['SENTINEL', 'REPLICAS', 'kr'], \&canon_list);
# HELLO on a master and on a replica: its role is what confirms the server a sentinel named, under RESP3.
for my $at ([7200, 'hello3-master'], [7201, 'hello3-replica']) {
    my $c = open_to($at->[0]);
    record($at->[1], ['HELLO', '3'], tenc(canon_hello(tcall($c, 'HELLO', '3'))));
    close $c->{s};
}
pair('role-master', 7200, [], ['ROLE'], \&canon_role);
pair('role-replica', 7201, [], ['ROLE'], \&canon_role);
pair('role-sentinel', 7300, [], ['ROLE']);
pair('sentinel-select', 7300, [], ['SELECT', '1']);
pair('sentinel-setinfo', 7300, [], ['CLIENT', 'SETINFO', 'LIB-NAME', 'kama-redis']);
pair('sentinel-setname', 7300, [], ['CLIENT', 'SETNAME', 'kama-test']);
pair('sentinel-ping', 7300, [], ['PING']);
pair('locked-sentinel-ping', 7303, [], ['PING']);
pair('locked-sentinel-auth', 7303, [], ['AUTH', 'kr_sentinel', 'kr_sentinel_pw']);
pair('locked-sentinel-auth-wrong', 7303, [], ['AUTH', 'kr_sentinel', 'wrong']);
{
    my $c = open_to(7303);
    record('locked-sentinel-hello3-auth', ['HELLO', '3', 'AUTH', 'kr_sentinel', 'kr_sentinel_pw'], tenc(canon_hello(tcall($c, 'HELLO', '3', 'AUTH', 'kr_sentinel', 'kr_sentinel_pw'))));
    close $c->{s};
}
# A replica down: the sentinels flag it, and a failover cannot pick it.
{ my $c = open_to(7202); print { $c->{s} } enc('SHUTDOWN', 'NOSAVE'); drain_for($c, 2); close $c->{s}; }
until_true('the sentinels flagging 7202 down', 30, sub { !grep { field($_, 'port') eq '7202' && field($_, 'flags') !~ /s_down/ } @{ sent(7300, 'SENTINEL', 'REPLICAS', 'kr')->[1] } });
pair('replicas-one-down', 7300, [], ['SENTINEL', 'REPLICAS', 'kr'], \&canon_list);

# The failover. Before it: a subscriber to +switch-master under each protocol, an idle client of the master and of the
# replica to be promoted under each, and a BLPOP on the master.
my (%sub, %oldMaster, %promoted);
for my $proto (2, 3) {
    my $s = open_to(7300); tcall($s, 'HELLO', '3') if $proto == 3;
    print { $s->{s} } enc('SUBSCRIBE', '+switch-master');
    record("subscribe-switch-master/$proto", ['SUBSCRIBE', '+switch-master'], tenc(take($s)));
    $sub{$proto} = $s;
    my $m = open_to(7200); tcall($m, 'HELLO', '3') if $proto == 3; tcall($m, 'PING'); $oldMaster{$proto} = $m;
    my $p = open_to(7201); tcall($p, 'HELLO', '3') if $proto == 3; tcall($p, 'PING'); $promoted{$proto} = $p;
}
# And a tracking client (RESP3, OPTIN) that read a key, on each (phase 7b).
my %trackedNode;
for my $port (7200, 7201) {
    my $t = open_to($port); tcall($t, 'HELLO', '3');
    tcall($t, 'CLIENT', 'TRACKING', 'ON', 'OPTIN'); tcall($t, 'CLIENT', 'CACHING', 'YES'); tcall($t, 'GET', 'kr:k');
    $trackedNode{$port} = $t;
}
my $blocked = open_to(7200);
print { $blocked->{s} } enc('BLPOP', 'kr:none', '0');
select(undef, undef, undef, 0.2);
one(7301, 'SENTINEL', 'FAILOVER', 'kr');
for my $proto (2, 3) {
    my $v = take($sub{$proto});
    record("switch-master/$proto", ['SUBSCRIBE', '+switch-master'], tenc($v), ['SENTINEL FAILOVER kr, from another sentinel']);
    close $sub{$proto}{s};
}
until_true('7200 turned into a replica', 30, sub { (str(one(7200, 'ROLE')->[1][0]) // '') eq 'slave' && text(7200, 'INFO', 'replication') =~ /master_link_status:up/ });
for my $proto (2, 3) {
    my ($got, $closed) = drain_for($promoted{$proto}, 2);
    record("promoted-let-go/$proto", ['PING'], $got, ['PING, then SENTINEL FAILOVER kr, which promoted this replica']); ending("promoted-let-go/$proto", $closed);
    ($got, $closed) = drain_for($oldMaster{$proto}, 2);
    record("demoted-let-go/$proto", ['PING'], $got, ['PING, then SENTINEL FAILOVER kr, which made this master a replica']); ending("demoted-let-go/$proto", $closed);
}
{
    my ($got, $closed) = drain_for($blocked, 2);
    record('demoted-blpop', ['BLPOP', 'kr:none', '0'], $got, ['SENTINEL FAILOVER kr, which made this master a replica']); ending('demoted-blpop', $closed);
}
for my $port (7200, 7201) {
    my ($got, $closed) = drain_for($trackedNode{$port}, 2);
    my $name = $port == 7200 ? 'tracked-demoted-let-go' : 'tracked-promoted-let-go';
    record($name, ['(nothing: what arrives)'], $got, ["HELLO 3, CLIENT TRACKING ON OPTIN, CLIENT CACHING YES and GET kr:k at $port, then SENTINEL FAILOVER kr"]);
    ending($name, $closed);
}
pair('get-master-addr-after-failover', 7300, [], ['SENTINEL', 'GET-MASTER-ADDR-BY-NAME', 'kr']);
pair('demoted-write', 7200, [], ['SET', 'kr:k', 'v']);
pair('role-demoted', 7200, [], ['ROLE'], \&canon_role);
again(sub {
    my $c = open_to(7200);
    my $v = tcall($c, 'HELLO', '3');
    close $c->{s};
    record('hello3-demoted', ['HELLO', '3'], tenc(canon_hello($v)));
});
# Every replica down: 7202 was stopped before the failover, and now 7200, the demoted master, stops too, once the
# sentinels have seen it as 7201's replica (their record of it is what the reply shows).
until_true('the sentinels seeing 7200 as a replica of 7201, linked to it', 30, sub {
    !grep { field($_, 'port') eq '7200' && (field($_, 'role-reported') ne 'slave' || field($_, 'master-port') ne '7201'
                                            || field($_, 'master-link-status') ne 'ok') } @{ sent(7300, 'SENTINEL', 'REPLICAS', 'kr')->[1] // [] };
});
{ my $c = open_to(7200); print { $c->{s} } enc('SHUTDOWN', 'NOSAVE'); drain_for($c, 2); close $c->{s}; }
until_true('the sentinels flagging both replicas down', 30, sub {
    my $r = sent(7300, 'SENTINEL', 'REPLICAS', 'kr');
    return @{ $r->[1] // [] } == 2 && !grep { field($_, 'flags') !~ /s_down/ } @{ $r->[1] };
});
pair('replicas-all-down', 7300, [], ['SENTINEL', 'REPLICAS', 'kr'], \&canon_list);
pair('role-promoted', 7201, [], ['ROLE'], \&canon_role);
PERL

: > "$tmp/live.tsv"
for server in $SERVERS; do
    case "$server" in
        redis-*)  image=docker.io/library/redis:${server#redis-} ;;
        valkey-*) image=docker.io/valkey/valkey:${server#valkey-} ;;
    esac
    status=0
    "$RT" run --rm -i --network none "$image" sh -c "$(cat "$tmp/run.sh")" < "$tmp/ask.pl" > "$tmp/one.txt" || status=$?
    # A container that dies without a word (137: killed, as by a machine out of memory) says how far it got.
    [ "$status" = 0 ] || { echo "gen-topology-vectors: $server failed (exit $status), after:" >&2; tail -n 3 "$tmp/one.txt" | cut -c1-200 >&2; exit 1; }
    number=$(head -n 1 "$tmp/one.txt")
    case "$number" in [0-9]*.[0-9]*) ;; *) echo "gen-topology-vectors: $server gave no version" >&2; cat "$tmp/one.txt" >&2; exit 1 ;; esac
    tail -n +2 "$tmp/one.txt" | sed "s/^/${server%%-*}-$number	/" >> "$tmp/live.tsv"
done

cat > "$tmp/gen.pl" <<'PERL'
use strict; use warnings;
my ($tmp, $out) = @ARGV;
my (@versions, %seen, @replies, %ending, %keys);
open my $f, '<', "$tmp/live.tsv" or die;
while (<$f>) {
    chomp; my ($version, $what, @rest) = split /\t/, $_, -1;
    push @versions, $version unless $seen{$version}++;
    if ($what eq 'ending') { $ending{"$version $rest[0]"} = $rest[1]; next; }
    if ($what eq 'keys') { $keys{$version} = $rest[0]; next; }
    # Anything else is a case. A line that is not one (something a server printed) fails here.
    die "gen-topology-vectors: $version printed a line that is not a case: $what\n" unless defined $rest[1] && $rest[1] =~ /\A[0-9a-f]*\z/;
    push @replies, ["$version $what", $rest[0], $rest[1], $rest[2] // ''];
}
my %hex = map { $_->[0] => $_->[2] } @replies;
my %count; $count{(split / /, $_->[0])[1]}++ for @replies;
my @every = qw(slots slots-empty slots-standalone slots-at-replica mget-a mget-b mget-c mget-tag exists-a exists-b exists-c mset-a dbsize-a
    dbsize-b dbsize-c keys-a keys-b ping-node script-exists-a script-exists-b moved crossslot crossslot-one-node multi-moved exec-after-moved exec-crossslot
    replica-get replica-readonly replica-get-readonly replica-set-readonly replica-readwrite replica-get-readwrite
    replica-keyless-write ask migrating-served migrating-tryagain multi-ask exec-after-ask exec-after-mixed importing-moved asking importing-asking
    importing-asking-tryagain importing-asking-once importing-asking-multi not-served slots-gap slots-after-failover
    moved-after-failover moved-from-demoted masterdown clusterdown clusterdown-read clusterdown-write get-master-addr
    get-master-addr-unknown sentinels replicas role-master role-replica role-sentinel sentinel-select sentinel-setinfo
    sentinel-setname sentinel-ping locked-sentinel-ping locked-sentinel-auth locked-sentinel-auth-wrong replicas-one-down
    subscribe-switch-master switch-master promoted-let-go demoted-let-go get-master-addr-after-failover demoted-write
    role-demoted role-promoted replicas-all-down);
for my $must (@every) {
    for my $proto (2, 3) {
        die "gen-topology-vectors: case $must/$proto is not on every server\n" unless ($count{"$must/$proto"} // 0) == @versions;
    }
}
# Sharded pub/sub, on every server from 7.0.
for my $v (@versions) {
    next if $v =~ /^redis-6\./;
    for my $must (qw(ssub-shard sunsubscribe-failover ssub-shard-moved)) {
        for my $proto (2, 3) { die "gen-topology-vectors: case $must/$proto is not on $v\n" unless exists $hex{"$v $must/$proto"}; }
    }
}
for my $must (qw(hello3-node sentinel-hello3 locked-sentinel-hello3-auth demoted-blpop hello3-master hello3-replica hello3-demoted
                 tracked-failover-demoted tracked-failover-promoted tracked-failover-demoted-write tracked-failover-promoted-write
                 tracked-demoted-let-go tracked-promoted-let-go)) {
    die "gen-topology-vectors: case $must is not on every server\n" unless ($count{$must} // 0) == @versions;
}
# What the client's design rests on, checked on every server rather than taken from the docs.
sub bytes { return pack('H*', shift); }
# expect <server> <case> <pattern> <what it must say>: the reply, or the script stops, showing what came.
sub expect {
    my ($v, $case, $re, $what) = @_;
    my $h = $hex{"$v $case"}; die "gen-topology-vectors: $v has no $case\n" unless defined $h;
    my $b = bytes($h);
    return if $b =~ $re;
    (my $shown = $b) =~ s/\r\n/\\r\\n/g;
    die "gen-topology-vectors: $v: $what ($case: $shown)\n";
}
for my $v (@versions) {
    my $at = sub { my $c = shift; my $h = $hex{"$v $c"}; die "gen-topology-vectors: $v has no $c\n" unless defined $h; return bytes($h); };
    # A server's HELLO says its role: what confirms the master a sentinel named, under RESP3.
    expect($v, 'hello3-master', qr/role\r\n.6\r\nmaster\r\n/, "the master's HELLO does not say role master");
    expect($v, 'hello3-replica', qr/role\r\n.7\r\nreplica\r\n/, "a replica's HELLO does not say role replica");
    expect($v, 'hello3-demoted', qr/role\r\n.7\r\nreplica\r\n/, "the demoted master's HELLO does not say role replica");
    for my $proto (2, 3) {
        expect($v, "moved/$proto", qr/\A-MOVED \d+ 127\.0\.0\.1:7001\r\n\z/, "MOVED from a primary does not name 7001");
        expect($v, "replica-get/$proto", qr/\A-MOVED \d+ 127\.0\.0\.1:7000\r\n\z/, "a replica does not send MOVED to its primary");
        expect($v, "replica-get-readonly/$proto", qr/va/, "a replica after READONLY does not serve the read");
        expect($v, "replica-set-readonly/$proto", qr/\A-MOVED /, "a write to a replica after READONLY is not MOVED");
        expect($v, "ask/$proto", qr/\A-ASK \d+ 127\.0\.0\.1:7001\r\n\z/, "ASK does not name 7001");
        # 6.2 counts a missing key toward ASK whatever else the command holds; 7.0 answers TRYAGAIN when some are
        # there and some not (the target's TRYAGAIN after ASKING is every server's).
        expect($v, "migrating-tryagain/$proto", $v =~ /^redis-6\./ ? qr/\A-ASK \d+ 127\.0\.0\.1:7001\r\n\z/ : qr/\A-TRYAGAIN /,
               "a half-migrated MGET on the source is not ASK (6.2) or TRYAGAIN (7.0 and later)");
        expect($v, "importing-moved/$proto", qr/\A-MOVED \d+ 127\.0\.0\.1:7000\r\n\z/, "the importing node without ASKING is not MOVED");
        expect($v, "importing-asking-once/$proto", qr/\A-MOVED /, "ASKING lasted more than one command");
        expect($v, "exec-after-moved/$proto", qr/\A-EXECABORT /, "EXEC after a redirection is not EXECABORT");
        expect($v, "not-served/$proto", qr/\A-CLUSTERDOWN Hash slot not served\r\n\z/, "a slot not served is not CLUSTERDOWN");
        expect($v, "clusterdown/$proto", qr/\A-CLUSTERDOWN The cluster is down\r\n\z/, "the cluster down is not CLUSTERDOWN");
        expect($v, "moved-after-failover/$proto", qr/127\.0\.0\.1:7004\r\n\z/, "MOVED after the failover does not name 7004");
        expect($v, "get-master-addr/$proto", qr/\$4\r\n7200\r\n\z/, "the master's address is not 7200");
        expect($v, "get-master-addr-after-failover/$proto", qr/\$4\r\n7201\r\n\z/, "the address after the failover is not 7201");
        expect($v, "switch-master/$proto", qr/kr 127\.0\.0\.1 7200 127\.0\.0\.1 7201/, "+switch-master does not name 7200 then 7201");
        expect($v, "demoted-write/$proto", qr/\A-READONLY /, "the demoted master takes a write");
        for my $c ("promoted-let-go/$proto", "demoted-let-go/$proto") {
            die "gen-topology-vectors: $v sent something as Sentinel let a client go ($c)\n" unless $at->($c) eq '';
            die "gen-topology-vectors: $v: Sentinel left a client open ($c)\n" unless ($ending{"$v $c"} // '') eq 'closed';
        }
    }
    # Client-side caching across a failover (phase 7b). Sentinel lets a tracking client go as it does any other, so a
    # cache is flushed with its link. A cluster's manual failover sends a tracking client nothing and keeps it, and the
    # new primary's write of the key still invalidates it at both nodes, the demoted one through replication.
    for my $c ('tracked-demoted-let-go', 'tracked-promoted-let-go') {
        die "gen-topology-vectors: $v sent something as Sentinel let a tracking client go ($c)\n" unless $at->($c) eq '';
        die "gen-topology-vectors: $v: Sentinel left a tracking client open ($c)\n" unless ($ending{"$v $c"} // '') eq 'closed';
    }
    for my $c ('tracked-failover-demoted', 'tracked-failover-promoted') {
        die "gen-topology-vectors: $v sent a tracking client something as the shard changed hands ($c)\n" unless $at->($c) eq '';
        die "gen-topology-vectors: $v: a cluster failover closed a tracking client ($c)\n" unless ($ending{"$v $c"} // '') eq 'open';
        expect($v, "$c-write", qr/\A>2\r\n\$10\r\ninvalidate\r\n\*1\r\n\$\d+\r\n[^\r]+\r\n\z/, "the new primary's write did not invalidate the key ($c)");
    }
}

sub lit { my $s = shift; die "gen-topology-vectors: unexpected text '$s'\n" if $s =~ /[^\x20-\x7e]/ || $s =~ /[\\"]|\$\{/; return "\"$s\""; }
open my $o, '>', $out or die;
my $who = join(', ', @versions);
print $o <<"HEAD";
// GENERATED by tools/gen-topology-vectors.sh. Do not edit: change the script and run it again.
//
// What a cluster's nodes and Sentinel answer a client, byte for byte. The servers, each asked live in a container with
// no network: $who.
//   - topologyNames / topologyCommands / topologyHex / topologySetups: "<server> <case>", the command sent, the reply
//     as it came (but for what moves from run to run, below), and the commands that ran before it on the same
//     connection (joined by " ; "). A case "<case>/2" or "<case>/3" ran under that protocol.
//   - topologyKeys: for each server, the keys its cluster cases use: kr:a and kr:a2 in shard 0 (7000, 0-5460) in two
//     slots, kr:b in shard 1 (7001, then 7004 after the failover), kr:c in shard 2 (7002), and the migrated slot's
//     kr:{m…}x (on its source) and kr:{m…}y (on neither).
//   - topologyEnding: "<server> <case>" and whether the connection was closed, for the clients Sentinel let go, and for
//     the tracking clients across the cluster's failover (tracked-failover-*, which stay open).
// The cluster: 7000-7002 primaries, 7003-7005 their replicas, each node's id written as its port padded with zeros.
// Sentinel: a master 7200, replicas 7201 and 7202, sentinels 7300-7303 (7303's default user off); values that move
// with time are 0, and a list's entries are sorted by address (tools/gen-topology-vectors.sh says which).
import { std::collections::DynamicArray };
export { topologyVersions, topologyNames, topologyCommands, topologyHex, topologySetups, topologyKeyServers, topologyKeys,
         topologyEndingNames, topologyEndings };

HEAD
sub column {
    my ($fn, @items) = @_;
    print $o "fn DynamicArray<string> $fn() {\n    DynamicArray<string> v = DynamicArray.empty();\n";
    print $o "    v.add(item: $_);\n" for @items;
    print $o "    return v;\n}\n\n";
}
column('topologyVersions', map { lit($_) } @versions);
column('topologyNames', map { lit($_->[0]) } @replies);
column('topologyCommands', map { lit($_->[1]) } @replies);
column('topologyHex', map { lit($_->[2]) } @replies);
column('topologySetups', map { lit($_->[3]) } @replies);
column('topologyKeyServers', map { lit($_) } @versions);
column('topologyKeys', map { lit($keys{$_}) } @versions);
my @ends = sort keys %ending;
column('topologyEndingNames', map { lit($_) } @ends);
column('topologyEndings', map { lit($ending{$_}) } @ends);
close $o;
printf "gen-topology-vectors: %d replies from %s into %s\n", scalar(@replies), $who, $out;
PERL

perl "$tmp/gen.pl" "$tmp" "$OUT"
