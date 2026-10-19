#!/bin/sh
# mutate.sh — the gate's last check, that a test is good: each mutation of the source must make the case it targets
# fail. A test that passes on broken code proves nothing, so every step of a phase runs its mutations before it commits
# (@kama/postgres's rule, and its tool).
#
#   tools/mutate.sh tools/mutations/7a-s0.json                    every unit mutation in the file
#   tools/mutate.sh tools/mutations/7a-s0.json M3 M7              only those
#   tools/mutate.sh tools/mutations/7a-s0.json --server redis-8.10   the integration mutations too, against that server
#
# A mutation file is a JSON list. Each entry is
#   {"id": "M1", "suite": "unit" | "integration", "file": "src/…", "old": "…", "new": "…", "expect": "…"}
# and `old` must occur exactly once in `file`. `expect` is part of the check's name (what `check` prints after FAIL).
#
# The tree is copied to a scratch directory (without .git and out/), so the working tree is never touched. For each
# mutation, the copy's file is changed, the suite is built in debug and run, and the file is put back. The verdict:
#   CAUGHT            the targeted case failed;
#   FAILED-ELSEWHERE  other cases failed, not that one (strengthen the targeted case);
#   PANICKED          the run died before any case could fail;
#   SURVIVED          nothing failed;
#   BAD-PATTERN       `old` is not in the file exactly once (the source moved on: update the mutation);
#   BUILD-FAILED      the mutation does not compile.
# It exits 1 unless every mutation run is CAUGHT. `kama` is $KAMA or the PATH; an integration run needs the server up
# (tools/redis.sh up --server S) and reads its out/redistest-S.env. Run the integration mutations after the matrix,
# not beside it: both use the same servers.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KAMA=${KAMA:-kama}
[ $# -ge 1 ] || { echo "usage: tools/mutate.sh <mutations.json> [--server S] [id …]" >&2; exit 2; }
FILE=$1; shift
SERVER=""
IDS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --server) SERVER=${2:?--server needs a value}; shift 2 ;;
        *) IDS="$IDS $1"; shift ;;
    esac
done
tmp=$(mktemp -d)
# The socket test's sockets get a short directory of their own: a socket path is at most 103 bytes on macOS.
sockets=$(mktemp -d /tmp/krdm.XXXXXX)
trap 'rm -rf "$tmp" "$sockets"' EXIT

"$ROOT/tools/gen-test-certs.sh" >/dev/null
rsync -a --exclude .git --exclude out "$ROOT/" "$tmp/tree/"
"$KAMA" pkg install "$tmp/tree/tests/unit/kama.json" >/dev/null
[ -z "$SERVER" ] || "$KAMA" pkg install "$tmp/tree/tests/integration/kama.json" >/dev/null
envfile=""
if [ -n "$SERVER" ]; then
    envfile="$ROOT/out/redistest-$SERVER.env"
    [ -f "$envfile" ] || { echo "mutate.sh: no $envfile: start the server with tools/redis.sh up --server $SERVER" >&2; exit 2; }
fi

python3 -I - "$tmp" "$KAMA" "$ROOT/$FILE" "$ROOT/out/test-certs" "$envfile" "$sockets" $IDS <<'PY'
import json, os, subprocess, sys, tempfile
tmp, kama, path, certs, envfile, sockets = sys.argv[1:7]
only = set(sys.argv[7:])
tree = os.path.join(tmp, "tree")
env = dict(os.environ, REDISTEST_CERTDIR=certs)
if envfile:
    for line in open(envfile):
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k] = v
missed = 0
for m in json.load(open(path)):
    if only and m["id"] not in only:
        continue
    if m["suite"] == "integration" and not envfile:
        continue
    target = os.path.join(tree, m["file"])
    src = open(target).read()
    n = src.count(m["old"])
    if n != 1:
        print(f"{m['id']}: BAD-PATTERN ({n} matches in {m['file']})", flush=True)
        missed += 1
        continue
    open(target, "w").write(src.replace(m["old"], m["new"]))
    try:
        exe = os.path.join(tmp, "mutant")
        manifest = os.path.join(tree, "tests", m["suite"], "kama.json")
        b = subprocess.run([kama, "build", manifest, "--debug", "-o", exe], capture_output=True, text=True)
        if b.returncode != 0:
            print(f"{m['id']}: BUILD-FAILED\n{(b.stdout + b.stderr)[-600:]}", flush=True)
            missed += 1
            continue
        work = tempfile.mkdtemp(dir=sockets)
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=900,
                               env=dict(env, REDISTEST_SOCKDIR=work, **m.get("env", {})))
            fails = [l.strip()[5:] for l in r.stdout.splitlines() if l.strip().startswith("FAIL ")]
            # A run that ends badly with no case failed died before one could: a panic, or a signal.
            if not fails and r.returncode != 0:
                fails = ["PANICKED: " + (r.stderr.strip().splitlines() or ["exit %d" % r.returncode])[-1]]
        except subprocess.TimeoutExpired:
            fails = ["(timed out)"]
        hits = [f for f in fails if m["expect"] in f]
        if hits:
            verdict, shown = "CAUGHT", hits[0]
        elif fails and fails[0].startswith("PANICKED"):
            verdict, shown = "PANICKED", fails[0]
            missed += 1
        else:
            verdict, shown = ("FAILED-ELSEWHERE", fails[0]) if fails else ("SURVIVED", "")
            missed += 1
        print(f"{m['id']}: {verdict}" + (f" — {shown}" if shown else ""), flush=True)
    finally:
        open(target, "w").write(src)
sys.exit(1 if missed else 0)
PY
