#!/bin/sh
# check-readme.sh — build every complete program in README.md (each ```kama block with a `fn uint8 main()`) against
# this package, and run it against a live server. The only change made to an example is its URL: the test server's
# host and port take the place of 127.0.0.1:6379, its TLS port that of 127.0.0.1:6380, the test PKI's files those
# under /etc/redis/, its sentinel topology's URL that of redis-sentinel://127.0.0.1:26379?master_name=mymaster, and its
# cluster's seeds those of redis://127.0.0.1:7000,127.0.0.1:7001. A program that does not build, or exits other than
# 0, fails.
#
#   tools/check-readme.sh                    on redis-8.10
#   tools/check-readme.sh --server S         on the server named (tools/redis.sh list)
#
# `kama` is $KAMA or the PATH. The programs are built under out/readme/, inside the repository, because a path
# dependency is relative to its manifest.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KAMA=${KAMA:-kama}
SERVER=redis-8.10
while [ $# -gt 0 ]; do
    case "$1" in
        --server) SERVER=${2:?--server needs a value}; shift 2 ;;
        *) echo "check-readme.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

"$ROOT/tools/redis.sh" up --server "$SERVER" >/dev/null
# shellcheck disable=SC1090
. "$ROOT/out/redistest-$SERVER.env"
"$ROOT/tools/redis.sh" up --server "$SERVER" --topology sentinel >/dev/null
# shellcheck disable=SC1090
. "$ROOT/out/redistest-sentinel-$SERVER.env"
"$ROOT/tools/redis.sh" up --server "$SERVER" --topology cluster >/dev/null
# shellcheck disable=SC1090
. "$ROOT/out/redistest-cluster-$SERVER.env"
work="$ROOT/out/readme"
rm -rf "$work"
mkdir -p "$work"

# Each program to its own file: ex1.kama, ex2.kama, …
perl -e '
    my ($readme, $dir) = @ARGV;
    open my $f, "<", $readme or die "$readme: $!\n";
    local $/; my $text = <$f>;
    my $n = 0;
    while ($text =~ /```kama\n(.*?)```/gs) {
        my $code = $1;
        next unless $code =~ /fn uint8 main\(\)/;
        $n++;
        open my $o, ">", "$dir/ex$n.kama" or die; print $o $code; close $o;
    }
    die "check-readme: no complete program in $readme\n" unless $n;
' "$ROOT/README.md" "$work"

failed=""
for ex in "$work"/ex*.kama; do
    name=$(basename "$ex" .kama)
    project="$work/$name"
    mkdir -p "$project/src"
    sed -e "s#redis-sentinel://127\.0\.0\.1:26379?master_name=mymaster#$REDISTEST_SENTINEL_URL#g" \
        -e "s#redis://127\.0\.0\.1:7000,127\.0\.0\.1:7001#$REDISTEST_CLUSTER_URL#g" \
        -e "s#127\.0\.0\.1:6379#$REDISTEST_HOST:$REDISTEST_PORT#g" -e "s#127\.0\.0\.1:6380#$REDISTEST_HOST:$REDISTEST_TLS_PORT#g" \
        -e "s#/etc/redis/#$REDISTEST_CERTDIR/#g" "$ex" > "$project/src/main.kama"
    cat > "$project/kama.json" <<EOF
{ "name": "readme_$name", "version": "0.1.0", "kind": "executable", "kama": ">=0.9.690",
  "entry": "src/main.kama", "dependencies": { "@kama/redis": { "path": "../../.." } },
  "modules": { ".": { "visibility": "internal" } } }
EOF
    echo "== README $name on $SERVER"
    "$KAMA" pkg install "$project/kama.json" >/dev/null
    if "$KAMA" build "$project/kama.json" --debug -o "$project/run" >/dev/null && "$project/run"; then :; else failed="$failed $name"; fi
done
if [ -n "$failed" ]; then echo "check-readme.sh: FAILED:$failed" >&2; exit 1; fi
echo "check-readme.sh: OK on $SERVER"
