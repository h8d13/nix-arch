#!/bin/sh -e
# Build + run dedup benchmark against build/prefix libs.
# usage: bench/run.sh [npaths] [files-per-path] [content-pool]
cd "$(dirname "$0")/.."
P=$PWD/build/prefix
export PKG_CONFIG_PATH="$P/lib/pkgconfig"

g++ -std=c++23 -O2 bench/bench-optimise.cc -o build/bench-optimise \
	$(pkg-config --cflags --libs nix-store nix-util)

# disk-backed, not /tmp: 1M-file runs overflow tmpfs
ROOT=$(mktemp -d "$PWD/build/bench-root.XXXXXX")
# store paths are made read-only, restore write perm before cleanup
trap 'chmod -R u+w "$ROOT" && rm -rf "$ROOT"' EXIT
# PERF="perf record -g -o file.data" to profile
LD_LIBRARY_PATH=$P/lib $PERF build/bench-optimise "$ROOT" "${1:-200}" "${2:-500}" "${3:-5000}" "${4:-1}"
