#!/bin/sh -e
# Pin the import-dir output contract: stdout is exactly the imported
# store path. Callers must capture it; selecting the "newest" path by
# name glob + ls -t is void because canonicalisation sets every store
# path's mtime to 1 (the tie this test asserts). TAP output.
# usage: tests/import-select.sh <store-root-parent-tmpdir>
cd "$(dirname "$0")/.."
REPO=$PWD
P=$REPO/build/prefix

[ -n "$1" ] || { echo "usage: $0 <tmpdir>" >&2; exit 1; }
mkdir -p "$1"
ROOT=$(realpath "$1")	# import-dir absolutises; compare like with like

[ -x build/import-dir ] || {
	g++ -std=c++23 -O2 arch/import-dir.cc -o build/import-dir \
		$(PKG_CONFIG_PATH=$P/lib/pkgconfig pkg-config --cflags --libs nix-store nix-util)
}

N=0 FAIL=0
ok() {	# ok <cond-exit-status> <desc>
	N=$((N + 1))
	if [ "$1" = 0 ]; then echo "ok $N - $2"
	else echo "not ok $N - $2"; FAIL=1; fi
}

mkdir -p "$ROOT/a" "$ROOT/b"
echo "content one" > "$ROOT/a/f"
echo "content two" > "$ROOT/b/f"

P1=$(LD_LIBRARY_PATH=$P/lib build/import-dir "$ROOT/store" gen "$ROOT/a" 2> "$ROOT/log1")
P2=$(LD_LIBRARY_PATH=$P/lib build/import-dir "$ROOT/store" gen "$ROOT/b" 2> "$ROOT/log2")

[ -d "$P1" ]; ok $? "captured stdout of first import is a directory"
[ -d "$P2" ]; ok $? "captured stdout of second import is a directory"
[ "$P1" != "$P2" ]; ok $? "same name, different content: distinct paths"
case $P1 in "$ROOT"/store/nix/store/*-gen) s=0;; *) s=1;; esac
ok $s "path is inside the store and carries the name"

# both paths now match the *-gen glob with identical mtimes: this is
# why ls -t selection can return either one
M1=$(stat -c %Y "$P1") M2=$(stat -c %Y "$P2")
[ "$M1" = 1 ] && [ "$M2" = 1 ]; ok $? "store mtimes canonicalised to 1 (ls -t tie)"

# re-import identical content: content-addressed, same path back
P3=$(LD_LIBRARY_PATH=$P/lib build/import-dir "$ROOT/store" gen "$ROOT/b" 2> "$ROOT/log3")
[ "$P3" = "$P2" ]; ok $? "re-import of identical content is idempotent"

echo "1..$N"
exit $FAIL
