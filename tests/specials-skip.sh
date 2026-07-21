#!/bin/sh -e
# Sockets and fifos are skipped by dumpPath itself (NAR cannot
# represent them; live roots always carry some, e.g. gpg-agent's
# under /etc/pacman.d/gnupg). This pins the behavior since the
# mechanism moved from an import-dir PathFilter into archive.cc:
# an import of a tree holding specials must succeed, keep the real
# files, and land none of the specials.
# usage: specials-skip.sh <root>   (from tests/run.sh)
ROOT=$1

TREE=$ROOT/tree
mkdir -p "$TREE/sub"
echo hello > "$TREE/file"
echo nested > "$TREE/sub/inner"
mkfifo "$TREE/pipe" "$TREE/sub/pipe2"
python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
" "$TREE/sock"

n=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
fail() { n=$((n + 1)); echo "not ok $n - $1"; exit 1; }

P=$(build/import-dir "$ROOT/store" specials "$TREE" 2> /dev/null) \
	&& ok "import of tree with fifo+socket succeeds" \
	|| fail "import of tree with fifo+socket succeeds"

[ "$(cat "$P/file")" = hello ] && [ "$(cat "$P/sub/inner")" = nested ] \
	&& ok "regular files survive" || fail "regular files survive"

if find "$P" \( -type p -o -type s \) | grep -q .; then
	fail "no fifo or socket in the imported path"
else
	ok "no fifo or socket in the imported path"
fi

echo "1..$n"
