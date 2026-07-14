#!/bin/sh -e
# Smoke-boot build/nixarch.iso headless: default GRUB entry, serial
# console captured to build/serial.log, pass = autologin marker appears.
# qemu has no reason to exit on success, so the log is polled and qemu
# killed as soon as the marker lands (or after 180s, the fail case).
cd "$(dirname "$0")/../.."

ACCEL=
[ -w /dev/kvm ] && ACCEL="-accel kvm"
DISK=
[ -f build/nixstore.img ] && \
	DISK="-drive file=build/nixstore.img,format=raw,if=virtio"

rm -f build/serial.log
qemu-system-x86_64 $ACCEL -m 1536 $DISK \
	-cdrom build/nixarch.iso -boot d \
	-display none -no-reboot -serial file:build/serial.log &
QPID=$!

WAITED=0
while [ "$WAITED" -lt 180 ]; do
	grep -aq "NIXARCH BOOT OK" build/serial.log 2>/dev/null && break
	kill -0 "$QPID" 2>/dev/null || break
	sleep 1
	WAITED=$((WAITED + 1))
done
kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

grep -a "NIXARCH BOOT OK" build/serial.log && echo "PASS (${WAITED}s)" || {
	echo "FAIL: marker not in build/serial.log"; exit 1;
}
