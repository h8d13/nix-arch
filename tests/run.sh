#!/bin/sh -e
# Build + run regression tests against build/prefix libs. TAP output.
cd "$(dirname "$0")/.."
P=$PWD/build/prefix
export PKG_CONFIG_PATH="$P/lib/pkgconfig"

for t in parallel-optimise import-hashes nar-parse; do
	g++ -std=c++23 -O2 "tests/$t.cc" -o "build/$t" \
		$(pkg-config --cflags --libs nix-store nix-util)
done
for t in import-dir rm-path export-path import-path; do
	g++ -std=c++23 -O2 "arch/$t.cc" -o "build/$t" \
		$(pkg-config --cflags --libs nix-store nix-util)
done
# C ABI consumer: build.sh proves the C wrappers link, this proves they
# run. pkg-config drags -std=c++23 in via Requires.private cflags (only
# correct for C++ consumers), strip it; the wrapper .so's resolve their
# nix::* symbols against the C++ libs, so link those explicitly too.
CAPI_CFLAGS=$(pkg-config --cflags nix-store-c nix-util-c | sed 's/-std=c++23//g')
gcc -std=c11 -O2 tests/c-api.c -o build/c-api $CAPI_CFLAGS \
	$(pkg-config --libs nix-store-c nix-util-c nix-store nix-util)

FAIL=0
run() {	# run <name> <command...>: fresh root, restore perms, cleanup
	echo "# $1"; shift
	ROOT=$(mktemp -d "$PWD/build/test-root.XXXXXX")
	# store paths are made read-only, restore write perm before cleanup
	LD_LIBRARY_PATH=$P/lib "$@" "$ROOT" || FAIL=1
	chmod -R u+w "$ROOT" && rm -rf "$ROOT"
}

run needed-drift sh -e tests/needed-drift.sh
run c-api build/c-api
run parallel-optimise build/parallel-optimise
run import-hashes build/import-hashes
run nar-parse build/nar-parse
run import-select sh -e tests/import-select.sh
run gc-links sh -e tests/gc-links.sh
run export-roundtrip sh -e tests/export-roundtrip.sh

exit $FAIL
