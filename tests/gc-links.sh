#!/bin/sh -e
# Link-farm reclamation, invariant ported from upstream functional
# optimise-store.sh, exercised through the real tools (import-dir,
# rm-path): deleting a store path must prune .links entries whose last
# referrer went away and keep entries other paths still hard-link.
# Guards against generation removal slowly filling the farm. TAP.
# usage: tests/gc-links.sh <tmpdir>
cd "$(dirname "$0")/.."
REPO=$PWD
P=$REPO/build/prefix

[ -n "$1" ] || { echo "usage: $0 <tmpdir>" >&2; exit 1; }
mkdir -p "$1"
ROOT=$(realpath "$1")

for t in import-dir rm-path; do
	[ -x "build/$t" ] || g++ -std=c++23 -O2 "arch/$t.cc" -o "build/$t" \
		$(PKG_CONFIG_PATH=$P/lib/pkgconfig pkg-config --cflags --libs nix-store nix-util)
done

N=0 FAIL=0
ok() {	# ok <cond-exit-status> <desc>
	N=$((N + 1))
	if [ "$1" = 0 ]; then echo "ok $N - $2"
	else echo "not ok $N - $2"; FAIL=1; fi
}

# two trees sharing one 300-byte content, one exclusive each
mkdir -p "$ROOT/a" "$ROOT/b"
awk 'BEGIN { for (i = 0; i < 300; i++) printf "s" }' > "$ROOT/a/shared"
cp "$ROOT/a/shared" "$ROOT/b/shared"
awk 'BEGIN { for (i = 0; i < 300; i++) printf "a" }' > "$ROOT/a/own"
awk 'BEGIN { for (i = 0; i < 300; i++) printf "b" }' > "$ROOT/b/own"

RUN="env LD_LIBRARY_PATH=$P/lib"
PA=$($RUN build/import-dir "$ROOT/store" gena "$ROOT/a" 2> "$ROOT/loga")
PB=$($RUN build/import-dir "$ROOT/store" genb "$ROOT/b" 2> "$ROOT/logb")
LINKS=$ROOT/store/nix/store/.links

# import-dir optimises each fresh path: farm = shared, own-a, own-b
[ "$(ls "$LINKS" | wc -l)" = 3 ]; ok $? "farm holds one entry per distinct content"
[ "$(stat -c %h "$PA/shared")" = 3 ]; ok $? "shared content on one inode (2 files + farm)"

# delete B: exclusive entry pruned, shared survives (A still links it)
$RUN build/rm-path "$ROOT/store" "$(basename "$PB")" > "$ROOT/logrm1"
[ ! -e "$PB" ]; ok $? "path B deleted from disk"
[ "$(ls "$LINKS" | wc -l)" = 2 ]; ok $? "B's exclusive farm entry pruned"
[ "$(stat -c %h "$PA/shared")" = 2 ]; ok $? "shared entry survives while A refers to it"

# delete A: farm drains to empty (optimise-store.sh invariant)
$RUN build/rm-path "$ROOT/store" "$(basename "$PA")" > "$ROOT/logrm2"
[ "$(ls "$LINKS" | wc -l)" = 0 ]; ok $? "farm empty after last referrer deleted"

echo "1..$N"
exit $FAIL
