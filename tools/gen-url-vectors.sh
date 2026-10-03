#!/bin/sh
# gen-url-vectors.sh — write tests/unit/src/url_vectors.kama: how redis-cli 8.10 reads redis:// and rediss:// URLs,
# and how valkey-cli 9.1 reads valkey:// and valkeys:// ones, asked live.
#
# Each URL is given to the CLI (`-u URL PING`) in a throwaway container with no network, beside a recorder this
# script runs there: a fake server on 127.0.0.1:7100 that answers AUTH, SELECT and PING and logs every command it
# receives. What the CLI did is its reading of the URL:
#   - it refused the URL ("Invalid URI scheme", a bad percent-encoding): `refused`;
#   - it could not connect, and said where it tried ("Could not connect to Redis at H:P"): `address host=… port=…`;
#   - it reached the recorder: `session tls=0 user=… password=… db=…`, from the AUTH and SELECT it sent (no AUTH
#     is `-`, no SELECT is db 0), or `session tls=1` when what arrived was a TLS ClientHello.
# Host and password are hex.
#
# The expectation is the CLI's reading, except where the CLI reads a URL into something other than what it says.
# There this package refuses the URL, and the case says which rule refused it (`refused` with a reason): the rules
# are in `misread` below, and src/url.kama's header says why. valkey-cli sends AUTH with an empty user for
# `:password@`, and an empty password for `@`, as redis-cli did before 8.10; this package follows redis-cli 8.10, and those cases say so.
#
# Run it, then `git diff` must be empty. Needs perl, and podman or docker.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/tests/unit/src/url_vectors.kama"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if [ -n "${CONTAINER_RUNTIME:-}" ]; then RT=$CONTAINER_RUNTIME
elif command -v podman >/dev/null 2>&1; then RT=podman
elif command -v docker >/dev/null 2>&1; then RT=docker
else echo "gen-url-vectors: neither podman nor docker found (set CONTAINER_RUNTIME)" >&2; exit 1
fi

# The URLs: inputs only. S is the recorder (127.0.0.1:7100); A is an address nothing answers.
cat > "$tmp/urls.txt" <<'EOF'
SCHEME://127.0.0.1:7100
SCHEME://user:pass@127.0.0.1:7100
SCHEME://:pass@127.0.0.1:7100
SCHEME://pass@127.0.0.1:7100
SCHEME://user:@127.0.0.1:7100
SCHEME://@127.0.0.1:7100
SCHEME://:@127.0.0.1:7100
SCHEME://u%40x:p%3Ass@127.0.0.1:7100
SCHEME://us%65r:p%41SS@127.0.0.1:7100
SCHEME://user:pa:ss@127.0.0.1:7100
SCHEME://user:p%2Fs%3F@127.0.0.1:7100
SCHEME://user:p%25@127.0.0.1:7100
SCHEME://user:p%@127.0.0.1:7100
SCHEME://user:p%4@127.0.0.1:7100
SCHEME://user:p%zz@127.0.0.1:7100
SCHEME://:%FF@127.0.0.1:7100
SCHEME://:p%C3%A9@127.0.0.1:7100
SCHEME://:p@ss@127.0.0.1:7100
SCHEME://127.0.0.1:7100/0@x
SCHEME://127.0.0.1:7100/0
SCHEME://127.0.0.1:7100/1
SCHEME://127.0.0.1:7100/15
SCHEME://127.0.0.1:7100/02
SCHEME://127.0.0.1:7100/
SCHEME://127.0.0.1:7100/abc
SCHEME://127.0.0.1:7100/1abc
SCHEME://127.0.0.1:7100/-1
SCHEME://127.0.0.1:7100/2/3
SCHEME://127.0.0.1:7100/99999999999999999999
SCHEME://127.0.0.1:7100/3?x=y
SCHEME://:pass@127.0.0.1:7100/2
SCHEME://user:pass@127.0.0.1:7100/9
SCHEME://localhost:7100
SCHEME://
SCHEME://localhost
SCHEME://127.0.0.1
SCHEME://127.0.0.1:6380
SCHEME://example.invalid:6390
SCHEME://my-host.example:1234/5
SCHEME://[::1]
SCHEME://[::1]:6390
SCHEME://[2001:db8::1]:6390
SCHEME://[::1
SCHEME://[::1]x
SCHEME://[]:6390
SCHEME://:6390
SCHEME://host:
SCHEME://host:0
SCHEME://host:65536
SCHEME://host:65535
SCHEME://host:6379x
SCHEME://host:+6379
SCHEME://host:06390
SCHEME://host/0:5
SCHEME://h%41st:6390
SCHEME://user:pass@example.invalid:6390
SCHEME:/host
SCHEME:host
nosuch://host
EOF

# Runs in the container as `perl /tmp/drive.pl <cli>`, with the URLs, one per line in hex, in its __DATA__. For
# each: <exit status> TAB <what the CLI printed, hex> TAB <what the recorder received>.
cat > "$tmp/drive.pl" <<'PERL'
use strict; use warnings; use IO::Socket::INET; use POSIX ();
my $cli = shift;
my @urls = map { chomp; pack('H*', $_) } <DATA>;
my $listener = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 7100, Listen => 16, ReuseAddr => 1, Proto => 'tcp') or die "listen: $!\n";
my $recorder = fork();
if ($recorder == 0) {
    # One connection at a time: log the commands it sends, in hex, until PING or the end; or `tls`.
    while (my $c = $listener->accept) {
        binmode $c; $c->autoflush(1);
        my $buf = ''; my @seen; my $done = 0;
        while (!$done) {
            my $n = sysread($c, my $chunk, 65536); last unless $n; $buf .= $chunk;
            if (substr($buf, 0, 1) eq "\x16") { @seen = ('tls'); last; }
            while ($buf =~ /\A\*(\d+)\r\n/) {
                my ($count, $p) = ($1, length("*$1\r\n")); my @args; my $whole = 1;
                for (1 .. $count) {
                    unless (substr($buf, $p) =~ /\A\$(\d+)\r\n/) { $whole = 0; last; }
                    my $len = $1; $p += length("\$$len\r\n");
                    if (length($buf) < $p + $len + 2) { $whole = 0; last; }
                    push @args, substr($buf, $p, $len); $p += $len + 2;
                }
                last unless $whole;
                substr($buf, 0, $p) = '';
                push @seen, join(',', map { unpack('H*', $_) } @args);
                my $name = uc $args[0];
                if ($name eq 'PING') { print $c "+PONG\r\n"; $done = 1; last; }
                print $c "+OK\r\n";
            }
        }
        open my $log, '>>', '/tmp/rec.log' or die; print $log join(' ', @seen), "\n"; close $log;
        close $c;
    }
    exit 0;
}
for my $url (@urls) {
    unlink '/tmp/rec.log';
    my $pid = fork();
    if ($pid == 0) {
        open STDOUT, '>', '/tmp/out.txt'; open STDERR, '>&', \*STDOUT;
        exec $cli, '-u', $url, 'PING'; exit 127;
    }
    my $waited = 0;
    while (waitpid($pid, POSIX::WNOHANG()) == 0) {
        select(undef, undef, undef, 0.02);
        if (++$waited > 500) { kill 'KILL', $pid; waitpid($pid, 0); last; }
    }
    my $status = $? >> 8;
    open my $o, '<', '/tmp/out.txt'; my $out = do { local $/; <$o> } // ''; close $o;
    my $rec = '';
    for (1 .. 50) { if (-s '/tmp/rec.log') { open my $l, '<', '/tmp/rec.log'; $rec = <$l> // ''; chomp $rec; close $l; last; } last if $out =~ /Could not connect|Invalid URI|URI encoding|Invalid server port/; select(undef, undef, undef, 0.02); }
    print "$status\t", unpack('H*', $out), "\t$rec\n";
}
kill 'TERM', $recorder;
PERL

ask() {  # ask <image> <cli> <scheme> <tls scheme> -> one line per URL in $tmp/<cli>.tsv
    sed -e "s#^SCHEME://#$3://#" -e "s#^SCHEME:#$3:#" "$tmp/urls.txt" > "$tmp/$2.urls"
    sed -e "s#^SCHEME://#$4://#" "$tmp/urls.txt" | grep "^$4://" | head -n 3 >> "$tmp/$2.urls"
    sed -e "s#^SCHEME://#$4://#" "$tmp/urls.txt" | grep -e "^$4://127.0.0.1:7100/2\$" -e "^$4://user:pass@127.0.0.1:7100/9\$" \
        -e "^$4://example.invalid:6390\$" >> "$tmp/$2.urls"
    { cat "$tmp/drive.pl"; echo "__DATA__"; perl -ne 'chomp; print unpack("H*", $_), "\n"' "$tmp/$2.urls"; } \
        | "$RT" run --rm -i --network none "$1" sh -c "cat > /tmp/drive.pl; $2 --version | head -n 1; perl /tmp/drive.pl $2" > "$tmp/$2.out"
}
ask docker.io/library/redis:8.10 redis-cli redis rediss
ask docker.io/valkey/valkey:9.1 valkey-cli valkey valkeys

cat > "$tmp/gen.pl" <<'PERL'
use strict; use warnings;
my ($tmp, $out) = @ARGV;
my @cases;
my %versions;
for my $cli ('redis-cli', 'valkey-cli') {
    open my $u, '<', "$tmp/$cli.urls" or die; my @urls = map { chomp; $_ } <$u>;
    open my $r, '<', "$tmp/$cli.out" or die; my @lines = map { chomp; $_ } <$r>;
    my $version = shift @lines;
    $version =~ /^(\S+) (\d+\.\d+\.\d+)/ or die "gen-url-vectors: no version from $cli: $version\n";
    $versions{$cli} = "$1 $2";
    die "gen-url-vectors: $cli answered " . scalar(@lines) . " of " . scalar(@urls) . " URLs\n" unless @lines == @urls;
    for my $i (0 .. $#urls) {
        my ($status, $hex, $rec) = split /\t/, $lines[$i], 3; $rec //= '';
        my $said = pack('H*', $hex);
        my $reading;
        if ($said =~ /Invalid URI scheme|URI encoding|Invalid server port/) { $reading = 'refused'; }
        elsif ($rec eq 'tls') { $reading = 'session tls=1'; }
        elsif ($rec ne '') {
            my ($user, $pass, $db) = ('-', '-', 0);
            for my $cmd (split / /, $rec) {
                my @a = map { pack('H*', $_) } split /,/, $cmd, -1;
                if (uc $a[0] eq 'AUTH') {
                    if (@a == 2) { $pass = unpack('H*', $a[1]); }
                    else { $user = $a[1] eq '' ? '' : unpack('H*', $a[1]); $pass = unpack('H*', $a[2]); }
                }
                $db = $a[1] if uc $a[0] eq 'SELECT';
            }
            $reading = "session tls=0 user=$user password=$pass db=$db";
        }
        elsif ($said =~ /Could not connect to (?:Redis|Valkey) at (.*):(\d+): /) { $reading = 'address host=' . unpack('H*', $1) . " port=$2"; }
        else { die "gen-url-vectors: cannot tell what $cli did with $urls[$i]: $said\n"; }
        push @cases, { url => $urls[$i], cli => $cli, reading => $reading };
    }
}

# Where a CLI reads a URL into something other than what it says, this package refuses it. Each rule names the
# misreading; src/url.kama refuses the same URLs with words that say how to write them.
# Whether the decimal `a` is larger than `b`, both digits only.
sub bigger { my ($a, $b) = @_; $a =~ s/^0+(?=.)//; return length($a) > length($b) || (length($a) == length($b) && $a gt $b); }

sub misread {
    my ($url) = @_;
    $url =~ m{^[A-Za-z]+://(.*)$}s or return undef;
    my $rest = $1;
    my $q = index($rest, '?'); my $beforeQuery = $q >= 0 ? substr($rest, 0, $q) : $rest;
    my $slash = index($beforeQuery, '/');
    my $authority = $slash >= 0 ? substr($beforeQuery, 0, $slash) : $beforeQuery;
    my $path = $slash >= 0 ? substr($beforeQuery, $slash + 1) : undef;
    my $at = index($authority, '@');
    my $ats = () = $rest =~ /@/g;
    return "the first '\@' ends the password for the CLI, even one past the host" if $ats > 1 || ($at < 0 && $ats > 0);
    my $hostport = $at >= 0 ? substr($authority, $at + 1) : $authority;
    if ($at >= 0) {
        my $info = substr($authority, 0, $at);
        return "the CLI drops a user whose password is empty" if $info =~ /^[^:]+:$/;
        for my $part (split /:/, $info, 2) {
            my $d = $part; $d =~ s/%([0-9A-Fa-f]{2})/chr(hex $1)/ge;
            return "a user or password that is not UTF-8" unless utf8::decode($d);
        }
    }
    my $port;
    if ($hostport =~ /^\[/) {
        return "an IPv6 address the CLI does not close" unless $hostport =~ /^\[([^\]]+)\](.*)$/;
        my $after = $2;
        return "the CLI ignores what follows an IPv6 address" if $after ne '' && $after !~ /^:/;
        $port = substr($after, 1) if $after ne '';
    } elsif ($hostport =~ /^([^:]*):(.*)$/) {
        return "the CLI connects to an empty host" if $1 eq '';
        $port = $2;
    }
    return "the CLI reads a port with atoi" if defined $port && ($port !~ /^\d+$/ || $port < 1 || $port > 65535);
    return "the CLI reads a database with atoi" if defined $path && $path ne '' && ($path !~ /^\d+$/ || bigger($path, '9223372036854775807'));
    return undef;
}

for my $c (@cases) {
    my $why = $c->{reading} eq 'refused' ? undef : misread($c->{url});
    $c->{want} = defined $why ? 'refused' : $c->{reading};
    my @notes;
    push @notes, "the CLI reads " . $c->{reading} . ", but $why" if defined $why;
    if ($c->{cli} eq 'valkey-cli' && $c->{want} =~ /user= |password= /) {
        # redis-cli 8.10 sends an empty user as no user (AUTH password), and an empty password as no AUTH at all.
        $c->{want} =~ s/user= /user=- /;
        $c->{want} =~ s/user=\S+ password= /user=- password=- / if $c->{want} =~ /password= /;
        push @notes, "valkey-cli sends AUTH with an empty user or password, as redis-cli did before 8.10; this package follows redis-cli 8.10";
    }
    $c->{note} = join('; ', @notes);
}

sub lit { my $s = shift; die "gen-url-vectors: unexpected text '$s'\n" if $s =~ /[^\x20-\x7e]/ || $s =~ /\$\{/; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; return "\"$s\""; }
open my $o, '>', $out or die;
print $o <<"HEAD";
// GENERATED by tools/gen-url-vectors.sh. Do not edit: change the script and run it again.
//
// How $versions{'redis-cli'} reads redis:// and rediss:// URLs, and $versions{'valkey-cli'} valkey:// and valkeys://
// ones, asked live against a recorder (`-u URL PING`): `refused`; `address host=<hex> port=<n>` (where it tried
// to connect); or `session tls=… user=<hex>|- password=<hex>|- db=<n>` (the AUTH and SELECT it sent). Where the CLI
// reads a URL into something other than what it says, the expectation is `refused`, and the note says why.
import { std::collections::DynamicArray };
export { urlInputs, urlWant, urlNotes };

HEAD
for my $col (['urlInputs', 'url'], ['urlWant', 'want'], ['urlNotes', 'note']) {
    print $o "fn DynamicArray<string> $col->[0]() {\n    DynamicArray<string> v = DynamicArray.empty();\n";
    print $o "    v.add(item: " . lit($_->{$col->[1]}) . ");\n" for @cases;
    print $o "    return v;\n}\n\n";
}
close $o;
printf "gen-url-vectors: %d URLs, from %s and %s, into %s\n", scalar(@cases), $versions{'redis-cli'}, $versions{'valkey-cli'}, $out;
PERL

perl "$tmp/gen.pl" "$tmp" "$OUT"
