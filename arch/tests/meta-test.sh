#!/bin/sh -e
# Pin the metadata round-trip on the host, no VM. The fragile link is
# the chain restmeta -> savemeta across a rebuild: if restmeta fails to
# reproduce a deviation in the merged view, the next savemeta can't
# tell it from canonical and drops the row for good (this happened:
# user .bashrc came back 0444 root:root). A user created in the same
# generation as the capture would pass even then, so the test chains
# two: gen A creates the user, gen B rebuilds on A with a no-op; B's
# manifest must still carry the rows and replay them.
# Needs a subuid range (multi-uid userns): single-uid chowns fail soft
# and would hollow out exactly the rows under test.
# usage: tests/meta-test.sh [store-root]   (default build/archstore)
cd "$(dirname "$0")/../.."
REPO=$PWD
P=$REPO/build/prefix
STORE=$(realpath "${1:-build/archstore}")

BASE=$(ls -td "$STORE"/nix/store/*-arch-base | head -1)
[ -d "$BASE" ] || { echo "no arch-base in $STORE (run arch/bootstrap.sh)" >&2; exit 1; }

UNSHARE="unshare --map-auto --map-root-user"
$UNSHARE true || {
	echo "FAIL: no subuid range for $(id -un); ownership rows need a multi-uid userns" >&2
	exit 1
}

[ -x build/rm-path ] || {
	g++ -std=c++23 -O2 arch/rm-path.cc -o build/rm-path \
		$(PKG_CONFIG_PATH=$P/lib/pkgconfig pkg-config --cflags --libs nix-store nix-util)
}

TMP= GENA= GENB=
cleanup() {
	if [ -n "$TMP" ]; then
		$UNSHARE rm -rf "$TMP"
	fi
	if [ -n "$GENB" ]; then
		LD_LIBRARY_PATH=$P/lib build/rm-path "$STORE" "$(basename "$GENB")"
	fi
	if [ -n "$GENA" ]; then
		LD_LIBRARY_PATH=$P/lib build/rm-path "$STORE" "$(basename "$GENA")"
	fi
}
trap cleanup EXIT

BASHRC='^f	644	1100	1100	\./home/tuser/\.bashrc$'
HOMEDIR='^d	[0-7]*	1100	1100	\./home/tuser$'

echo "--- gen A: useradd in a sandbox on $(basename "$BASE")"
arch/generation.sh "$STORE" "$BASE" meta-a 'useradd -m -u 1100 -U tuser'
GENA=$(ls -td "$STORE"/nix/store/*-meta-a | head -1)
grep -q "$BASHRC" "$GENA/etc/nixgen/perms" || {
	echo "FAIL: savemeta dropped the fresh .bashrc row; tuser rows in A:" >&2
	grep 'tuser' "$GENA/etc/nixgen/perms" >&2 || echo "(none)" >&2
	exit 1
}

echo "--- gen B: no-op rebuild on A (restmeta -> savemeta round-trip)"
arch/generation.sh "$STORE" "$GENA" meta-b 'true'
GENB=$(ls -td "$STORE"/nix/store/*-meta-b | head -1)
M=$GENB/etc/nixgen/perms

# every row typed 5-field; offenders print with line numbers
if grep -nvE '^[dfl]	[0-7]+	[0-9]+	[0-9]+	\.' "$M"; then
	echo "FAIL: rows above are not the typed 5-field format" >&2
	exit 1
fi
grep -q "$BASHRC" "$M" || {
	echo "FAIL: .bashrc row lost across the rebuild; tuser rows in B:" >&2
	grep 'tuser' "$M" >&2 || echo "(none)" >&2
	exit 1
}
grep -q "$HOMEDIR" "$M" || {
	echo "FAIL: home dir row lost across the rebuild" >&2
	exit 1
}
echo "manifest rows survived the rebuild"

echo "--- replay: restmeta over an overlay of gen B"
TMP=$(mktemp -d "$REPO/build/meta.XXXXXX")
mkdir "$TMP/upper" "$TMP/work" "$TMP/mnt"
cat > "$TMP/inner.sh" <<EOF
set -e
mount -t overlay overlay \
	-o "lowerdir=$GENB,upperdir=$TMP/upper,workdir=$TMP/work,userxattr" "$TMP/mnt"
"$REPO/arch/nixgen/nixgen-restmeta" "$TMP/mnt"
stat -c '%a %u %g' "$TMP/mnt/home/tuser/.bashrc"
EOF
OUT=$($UNSHARE -mpf --kill-child sh "$TMP/inner.sh")
echo "replayed .bashrc: $OUT"
[ "$OUT" = "644 1100 1100" ] || {
	echo "FAIL: replay left '$OUT' on .bashrc (want '644 1100 1100')" >&2
	exit 1
}

echo "PASS: user metadata survives sandbox -> manifest -> rebuild -> replay"
