#!/bin/sh
# gen-command-table.sh — write src/wire/commands.kama, the cluster's table of commands, and
# tests/unit/src/command_vectors.kama, what each server says the keys of a command are (docs/ROADMAP.md, "Phase 6").
#
# Each server in the matrix (tools/redis.sh list) is asked live, in a throwaway container with no network:
#   1. COMMAND: every command and subcommand, with its flags, its legacy first/last/step, and from 7.0 its tips
#      (request_policy, response_policy) and key specifications. COMMAND DOCS, from 7.0: each one's arguments.
#   2. From the newest servers' arguments, one or two invocations of each command are built: its required arguments,
#      each multiple one once; then with each multiple one twice and each optional one that holds a key. Keys are named
#      kr:k1, kr:k2, … in order, so a key's place is plain. A `numkeys` argument counts the keys that follow it.
#   3. COMMAND GETKEYS of every invocation, on every server that has the command: the server's own reading of its keys
#      (the key specs, or the command's own procedure where a spec is incomplete), or its refusal.
#
# The table holds, for each command and subcommand the servers have (lower case, a subcommand as "object|encoding"):
# its key specs, whether it only reads, and its request and response policies. Where servers differ, the newest's
# entry is taken, in this order: redis-8.10, valkey-9.1, redis-8.2, valkey-8.1, redis-7.4, redis-7.2, valkey-7.2, then
# 6.2, which has no key specs or tips (its commands are in the newer servers' table). The unit tests check that the
# table's reading of every invocation (keysOf, src/wire/route.kama) agrees with every server's GETKEYS.
#
# Run it, then `git diff` must be empty unless a server image moved (the header names each server's version).
# Needs perl and podman or docker.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TABLE="$ROOT/src/wire/commands.kama"
VECTORS="$ROOT/tests/unit/src/command_vectors.kama"
SERVERS=$("$ROOT/tools/redis.sh" list)
tmp=${GEN_KEEP:-$(mktemp -d)}; [ -n "${GEN_KEEP:-}" ] || trap 'rm -rf "$tmp"' EXIT

if [ -n "${CONTAINER_RUNTIME:-}" ]; then RT=$CONTAINER_RUNTIME
elif command -v podman >/dev/null 2>&1; then RT=podman
elif command -v docker >/dev/null 2>&1; then RT=docker
else echo "gen-command-table: neither podman nor docker found (set CONTAINER_RUNTIME)" >&2; exit 1
fi

image() {
    case "$1" in
        redis-*)  echo "docker.io/library/redis:${1#redis-}" ;;
        valkey-*) echo "docker.io/valkey/valkey:${1#valkey-}" ;;
    esac
}

# In the container: a server, then ask.pl, given the phase and (for GETKEYS) the invocations on stdin after it.
cat > "$tmp/run.sh" <<'SH'
set -u
perl -e 'local $/ = "\n__INVOCATIONS__\n"; my $p = <STDIN>; $p =~ s/\n__INVOCATIONS__\n\z//; open my $o, ">", "/tmp/ask.pl"; print $o $p; close $o; local $/; open my $i, ">", "/tmp/invocations"; print $i (<STDIN> // ""); close $i;'
redis-server --port 7000 --save "" --appendonly no --daemonize yes >/dev/null 2>&1
redis-server --version | sed -n "s/.*[Ss]erver v=\([0-9.]*\) .*/\1/p"
perl /tmp/ask.pl "$PHASE" < /tmp/invocations
SH

cat > "$tmp/ask.pl" <<'PERL'
use strict; use warnings; use IO::Socket::INET;
my ($phase) = @ARGV;
my $s;
for (1 .. 200) { $s = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => 7000, Proto => 'tcp'); last if $s; select(undef, undef, undef, 0.05); }
die "no server\n" unless $s;
binmode $s; $s->autoflush(1);
my $buf = ''; my $pos = 0;
sub more { my $n = sysread($s, my $chunk, 1 << 20); die "eof\n" unless $n; $buf .= $chunk; }
sub line { my $i; more() while ($i = index($buf, "\r\n", $pos)) < 0; my $l = substr($buf, $pos, $i - $pos); $pos = $i + 2; return $l; }
# A whole RESP2 reply as Perl data: a string, undef for a null, an array ref, or { error => message }.
sub parsed {
    my $l = line(); my $t = substr($l, 0, 1); my $n = substr($l, 1);
    if ($t eq '$') { return undef if $n < 0; more() while length($buf) < $pos + $n + 2; my $v = substr($buf, $pos, $n); $pos += $n + 2; return $v; }
    if ($t eq '*') { return undef if $n < 0; return [map { parsed() } 1 .. $n]; }
    return { error => $n } if $t eq '-';
    die "unexpected reply line '$l'\n" unless $t =~ /[+:]/;
    return $n;
}
sub enc { my $o = '*' . scalar(@_) . "\r\n"; $o .= '$' . length($_) . "\r\n$_\r\n" for @_; return $o; }
sub ask { print $s enc(@_); my $v = parsed(); $buf = substr($buf, $pos); $pos = 0; return $v; }
sub kv { my $a = shift; my %h; return \%h unless ref $a eq 'ARRAY'; for (my $i = 0; $i + 1 < @$a; $i += 2) { $h{$a->[$i]} = $a->[$i + 1]; } return \%h; }
sub list { my $v = shift; return ref $v eq 'ARRAY' ? join(',', map { ref $_ ? '?' : $_ } @$v) : ''; }

if ($phase eq 'dump') {
    # cmd TAB name TAB arity TAB flags TAB first TAB last TAB step TAB tips TAB specs
    # A spec: begin;find;flags, where begin is index:N, keyword:WORD:FROM or unknown, and find is range:LAST:STEP:LIMIT,
    # keynum:IDX:FIRST:STEP or unknown; specs are joined by " ".
    sub spec {
        my $k = kv(shift);
        my $bs = kv($k->{begin_search}); my $fk = kv($k->{find_keys});
        my $b = 'unknown'; my $f = 'unknown';
        if (($bs->{type} // '') eq 'index') { my $sp = kv($bs->{spec}); $b = "index:$sp->{index}"; }
        elsif (($bs->{type} // '') eq 'keyword') { my $sp = kv($bs->{spec}); $b = "keyword:$sp->{keyword}:$sp->{startfrom}"; }
        if (($fk->{type} // '') eq 'range') { my $sp = kv($fk->{spec}); $f = "range:$sp->{lastkey}:$sp->{keystep}:$sp->{limit}"; }
        elsif (($fk->{type} // '') eq 'keynum') { my $sp = kv($fk->{spec}); $f = "keynum:$sp->{keynumidx}:$sp->{firstkey}:$sp->{keystep}"; }
        return join(';', $b, $f, list($k->{flags}) || '-');
    }
    sub info {
        my ($c, $parent) = @_;
        my ($name, $arity, $flags, $first, $last, $step, $acl, $tips, $specs, $subs) = @$c;
        $name = lc $name;
        my $full = $parent ? "$parent|" . (split /\|/, $name)[-1] : $name;
        my @specs = ref $specs eq 'ARRAY' ? map { spec($_) } @$specs : ();
        print join("\t", 'cmd', $full, $arity, list($flags) || '-', $first, $last, $step, list($tips) || '-', join(' ', @specs) || '-'), "\n";
        if (ref $subs eq 'ARRAY') { info($_, $full) for @$subs; }
    }
    my $all = ask('COMMAND');
    info($_, '') for sort { lc $a->[0] cmp lc $b->[0] } @$all;
    # docs TAB name TAB arguments, each (name type token flags children…), token and flags '-' when none.
    sub arg {
        my $a = kv(shift);
        my $kids = ref $a->{arguments} eq 'ARRAY' ? join(' ', map { arg($_) } @{ $a->{arguments} }) : '';
        # An empty token (MIGRATE's "" in place of a key) is written <empty>: the invocations never choose it.
        my $token = !defined $a->{token} ? '-' : $a->{token} eq '' ? '<empty>' : $a->{token};
        return '(' . join(' ', $a->{name}, $a->{type}, $token, (list($a->{flags}) || '-'), ($kids eq '' ? () : $kids)) . ')';
    }
    sub doc {
        my ($name, $d) = @_;
        my $h = kv($d);
        print "docs\t$name\t", join(' ', map { arg($_) } @{ $h->{arguments} // [] }), "\n";
        my $subs = kv($h->{subcommands});
        doc(lc $_, $subs->{$_}) for sort keys %$subs;
    }
    my $docs = ask('COMMAND', 'DOCS');
    if (ref $docs eq 'ARRAY') { my $h = kv($docs); doc(lc $_, $h->{$_}) for sort keys %$h; }
} else {
    # getkeys TAB invocation TAB keys joined by spaces, or !error, for each invocation of a command this server has.
    my %has = map { lc $_->[0] => 1 } @{ ask('COMMAND') // [] };
    while (my $inv = <STDIN>) {
        chomp $inv; next if $inv eq '';
        my @w = split / /, $inv;
        next unless $has{lc $w[0]};
        my $r = ask('COMMAND', 'GETKEYS', @w);
        my $out = ref $r eq 'HASH' ? '!' . $r->{error} : ref $r eq 'ARRAY' ? join(' ', @$r) : '?';
        print "getkeys\t$inv\t$out\n";
    }
}
PERL

run() {  # run <server> <phase> [invocations file]
    { cat "$tmp/ask.pl"; printf '\n__INVOCATIONS__\n'; [ -n "${3:-}" ] && cat "$3"; } |
        "$RT" run --rm -i --network none -e PHASE="$2" "$(image "$1")" sh -c "$(cat "$tmp/run.sh")" > "$tmp/out.txt" ||
        { echo "gen-command-table: $1 failed" >&2; exit 1; }
    number=$(head -n 1 "$tmp/out.txt")
    case "$number" in [0-9]*.[0-9]*) ;; *) echo "gen-command-table: $1 gave no version" >&2; cat "$tmp/out.txt" >&2; exit 1 ;; esac
    tail -n +2 "$tmp/out.txt" | sed "s/^/${1%%-*}-$number	/"
}

: > "$tmp/dump.tsv"
for server in $SERVERS; do run "$server" dump >> "$tmp/dump.tsv"; done

# The invocations, from the newest servers' arguments.
cat > "$tmp/invoke.pl" <<'PERL'
use strict; use warnings;
my ($dump) = @ARGV;
my @order = qw(redis-8.10 valkey-9.1 redis-8.2 valkey-8.1 redis-7.4 redis-7.2 valkey-7.2);
my (%docs);
open my $f, '<', $dump or die;
while (<$f>) {
    chomp; my ($version, $what, $name, $args) = split /\t/, $_, 4;
    next unless $what eq 'docs';
    (my $short = $version) =~ s/^(\w+-\d+\.\d+)\..*/$1/;
    $docs{$short}{$name} = $args // '';
}
# The S-expression of the arguments, back as a tree: { name, type, token, flags, kids }.
sub tree {
    my ($text) = @_; my @tokens = $text =~ /\(|\)|[^\s()]+/g; my $i = 0;
    my $one; $one = sub {
        die "invoke: not an argument at $i\n" unless $tokens[$i] eq '('; $i++;
        my %a = (name => $tokens[$i++], type => $tokens[$i++], token => $tokens[$i++], flags => $tokens[$i++], kids => []);
        push @{ $a{kids} }, $one->() while $tokens[$i] eq '(';
        die "invoke: unclosed argument\n" unless $tokens[$i] eq ')'; $i++;
        return \%a;
    };
    my @all; push @all, $one->() while $i < @tokens;
    return \@all;
}
sub has_key { my $a = shift; return 1 if $a->{type} eq 'key'; return grep { has_key($_) } @{ $a->{kids} }; }
sub flag { my ($a, $f) = @_; return grep { $_ eq $f } split /,/, $a->{flags}; }
my $key = 0;
# The words for `$args`, in `$mode` 1 (required arguments, multiples once) or 2 (multiples twice, key-holding optional
# arguments too). `$count` is how many keys the next multiple key argument gets, for a numkeys before it.
sub words {
    my ($args, $mode) = @_; my @w;
    for (my $n = 0; $n < @$args; $n++) {
        my $a = $args->[$n];
        next if flag($a, 'optional') && !($mode == 2 && has_key($a));
        my $times = flag($a, 'multiple') ? $mode : 1;
        for (1 .. $times) {
            push @w, $a->{token} if $a->{token} ne '-' && $a->{type} ne 'pure-token' && ($_ == 1 || flag($a, 'multiple_token'));
            push @w, value($a, $mode, $args, $n);
        }
    }
    return @w;
}
sub value {
    my ($a, $mode, $args, $n) = @_;
    my $t = $a->{type};
    return 'kr:k' . (++$key) if $t eq 'key';
    return $a->{token} if $t eq 'pure-token';
    return words($a->{kids}, $mode) if $t eq 'block';
    if ($t eq 'oneof') { my $k = $a->{kids}; my $c = $mode == 1 ? $k->[0] : (grep { has_key($_) } @$k)[0] // $k->[0]; return words([{ %$c, flags => '-' }], $mode); }
    if ($t eq 'integer' && $a->{name} =~ /^num(keys|fields)$/) {
        # The keys that follow: one, or two for the second invocation.
        return $mode;
    }
    return '1' if $t eq 'integer' || $t eq 'unix-time';
    return '1.5' if $t eq 'double';
    return '*' if $t eq 'pattern';
    return 'v';
}
my %done; my %seen;
for my $server (@order) {
    for my $name (sort keys %{ $docs{$server} // {} }) {
        next if $done{$name}++;
        my $args = tree($docs{$server}{$name});
        my @head = map { uc } split /\|/, $name;
        for my $mode (1, 2) {
            $key = 0;
            my $inv = join(' ', @head, words($args, $mode));
            print "$inv\n" unless $seen{$inv}++;
        }
    }
}
PERL
perl "$tmp/invoke.pl" "$tmp/dump.tsv" > "$tmp/invocations"

: > "$tmp/getkeys.tsv"
for server in $SERVERS; do run "$server" getkeys "$tmp/invocations" >> "$tmp/getkeys.tsv"; done

cat > "$tmp/gen.pl" <<'PERL'
use strict; use warnings;
my ($dump, $getkeys, $table, $vectors) = @ARGV;
my @order = qw(redis-8.10 valkey-9.1 redis-8.2 valkey-8.1 redis-7.4 redis-7.2 valkey-7.2 redis-6.2);
my (%cmd, @versions, %seen, %full);
open my $f, '<', $dump or die;
while (<$f>) {
    chomp; my ($version, $what, @r) = split /\t/, $_, -1;
    push @versions, $version unless $seen{$version}++;
    (my $short = $version) =~ s/^(\w+-\d+\.\d+)\..*/$1/;
    $full{$short} = $version;
    next unless $what eq 'cmd';
    my ($name, $arity, $flags, $first, $last, $step, $tips, $specs) = @r;
    $cmd{$name}{$short} = { flags => $flags, tips => $tips, specs => $specs, first => $first, last => $last, step => $step };
}
die "gen-command-table: not every server\n" unless @versions == @order;
# The newest server's entry for each command, and which one that is.
my (@rows, %differs);
for my $name (sort keys %cmd) {
    my ($from) = grep { $cmd{$name}{$_} } @order;
    my $e = $cmd{$name}{$from};
    for my $other (grep { $cmd{$name}{$_} && $_ ne $from && $_ ne 'redis-6.2' } @order) {
        $differs{$name}{$other} = 1 if $cmd{$name}{$other}{specs} ne $e->{specs} || $cmd{$name}{$other}{tips} ne $e->{tips};
    }
    push @rows, [$name, $from, $e];
}
my %policy = (all_nodes => 'AllNodes', all_shards => 'AllShards', multi_shard => 'MultiShard', special => 'Special');
my %response = (one_succeeded => 'OneSucceeded', all_succeeded => 'AllSucceeded', agg_logical_and => 'AggLogicalAnd',
                agg_logical_or => 'AggLogicalOr', agg_min => 'AggMin', agg_max => 'AggMax', agg_sum => 'AggSum', special => 'Special');
sub lit { my $s = shift; die "gen-command-table: unexpected text '$s'\n" if $s =~ /[^\x20-\x7e]/ || $s =~ /[\\"]|\$\{/; return "\"$s\""; }
sub tipOf {
    my ($tips, $what, $map) = @_;
    for my $t (split /,/, $tips) { return $map->{$1} // die "gen-command-table: unknown $what '$1'\n" if $t =~ /^${what}:(.*)$/; }
    return 'Default';
}
open my $o, '>', $table or die;
my $who = join(', ', @versions);
print $o <<"HEAD";
// GENERATED by tools/gen-command-table.sh. Do not edit: change the script and run it again.
//
// Every command and subcommand the servers have ($who): its key specifications, whether it only reads, and its
// request and response policies (command-tips.md), as COMMAND gives them. An entry is the newest server's (the order
// is the script's). tests/unit/src/command_vectors.kama has each server's COMMAND GETKEYS of an invocation of each,
// which keysOf (src/wire/route.kama) must agree with.
import { std::collections::DynamicArray, CommandInfo, Begin, Find, Request, Response };
export { commandTable };

fn DynamicArray<CommandInfo> commandTable() {
    DynamicArray<CommandInfo> t = DynamicArray.empty();
HEAD
for my $r (@rows) {
    my ($name, $from, $e) = @$r;
    my $ro = (grep { $_ eq 'readonly' } split /,/, $e->{flags}) ? 'true' : 'false';
    my $req = tipOf($e->{tips}, 'request_policy', \%policy);
    my $res = tipOf($e->{tips}, 'response_policy', \%response);
    print $o "    { CommandInfo c = CommandInfo.make(name: ", lit($name), ", readOnly: $ro, request: Request::$req, response: Response::$res);\n";
    if ($e->{specs} ne '-') {
        for my $sp (split / /, $e->{specs}) {
            my ($b, $fk, $fl) = split /;/, $sp;
            my $begin = $b =~ /^index:(-?\d+)$/ ? "Begin::Index(at: $1)"
                      : $b =~ /^keyword:([^:]+):(-?\d+)$/ ? "Begin::Keyword(word: " . lit($1) . ", from: $2)"
                      : 'Begin::Unknown';
            my $find = $fk =~ /^range:(-?\d+):(-?\d+):(-?\d+)$/ ? "Find::Range(last: $1, step: $2, limit: $3)"
                     : $fk =~ /^keynum:(-?\d+):(-?\d+):(-?\d+)$/ ? "Find::Keynum(at: $1, first: $2, step: $3)"
                     : 'Find::Unknown';
            my %flags = map { $_ => 1 } split /,/, $fl;
            my $incomplete = $flags{incomplete} ? 'true' : 'false';
            my $notKey = $flags{not_key} ? 'true' : 'false';
            print $o "      c.spec(begin: $begin, find: $find, incomplete: $incomplete, notKey: $notKey);\n";
        }
    } elsif ($e->{first} != 0) {
        # A server before 7.0, or a module's command, gives the legacy positions alone: first, last (negative from the
        # end) and step.
        my $last = $e->{last} < 0 ? $e->{last} : $e->{last} - $e->{first};
        print $o "      c.spec(begin: Begin::Index(at: $e->{first}), find: Find::Range(last: $last, step: $e->{step}, limit: 0), incomplete: false, notKey: false);\n";
    }
    print $o "      t.add(item: give c); }\n";
}
print $o "    return give t;\n}\n";
close $o;

# The vectors: each server's GETKEYS of each invocation.
my @cases;
open my $g, '<', $getkeys or die;
while (<$g>) { chomp; my ($version, $what, $inv, $keys) = split /\t/, $_, -1; push @cases, [$version, $inv, $keys] if $what eq 'getkeys'; }
my %kinds; $kinds{$_->[2] =~ /^!/ ? 'refused' : 'keys'}++ for @cases;
open my $v, '>', $vectors or die;
print $v <<"HEAD";
// GENERATED by tools/gen-command-table.sh. Do not edit: change the script and run it again.
//
// What each server ($who) says the keys of an invocation of each of its commands are: COMMAND GETKEYS, the server's
// own reading (its key specs, or a command's own procedure). getkeysKeys is the keys, space-separated, in the order the
// server gives them; or "!" and the server's refusal ("!ERR The command has no key arguments", or an invocation it
// will not read). The invocations come from the newest servers' COMMAND DOCS (tools/gen-command-table.sh says how).
import { std::collections::DynamicArray };
export { getkeysServers, getkeysInvocations, getkeysKeys };

HEAD
for my $col (['getkeysServers', 0], ['getkeysInvocations', 1], ['getkeysKeys', 2]) {
    print $v "fn DynamicArray<string> $col->[0]() {\n    DynamicArray<string> v = DynamicArray.empty();\n";
    print $v "    v.add(item: " . lit($_->[$col->[1]]) . ");\n" for @cases;
    print $v "    return v;\n}\n\n";
}
close $v;
my @diff = map { "$_ (" . join(', ', sort keys %{ $differs{$_} }) . ")" } sort keys %differs;
printf "gen-command-table: %d commands from %s into %s; %d GETKEYS cases (%d with keys, %d refused) into %s\n",
    scalar(@rows), $who, $table, scalar(@cases), $kinds{keys} // 0, $kinds{refused} // 0, $vectors;
print "gen-command-table: where an older server's entry differs from the one taken: ", join('; ', @diff), "\n" if @diff;
PERL
perl "$tmp/gen.pl" "$tmp/dump.tsv" "$tmp/getkeys.tsv" "$TABLE" "$VECTORS"
