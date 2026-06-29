#!/bin/bash
# Headless boot test: launch the metal image in QEMU, capture the serial
# console, and confirm KoelOS reached its shell prompt. Used by CI and handy
# locally. No KVM required (QEMU falls back to TCG).
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
QEMU="qemu-system-x86_64"
TIMEOUT_TICKS=40        # 40 * 0.5s = 20s budget to reach the prompt
MODE="${1:-metal}"      # "metal" (IDE disk) or "floppy" (1.44 MB CHS boot)

command -v "$QEMU" >/dev/null 2>&1 || { echo "ERROR: $QEMU not found" >&2; exit 1; }

if [ "$MODE" = "floppy" ]; then
    IMG="$ROOT_DIR/dist/floppy/koelOS-floppy.img"
    [ -f "$IMG" ] || { echo "Image missing; building..."; bash "$ROOT_DIR/build_floppy.sh"; }
    set -- -drive file="$IMG",if=floppy,format=raw -boot a
else
    IMG="$ROOT_DIR/dist/metal/koelOS-metal.img"
    [ -f "$IMG" ] || { echo "Image missing; building..."; bash "$ROOT_DIR/build_metal.sh"; }
    set -- -drive format=raw,file="$IMG",if=ide
fi
echo "Smoke testing $MODE image: $IMG"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

"$QEMU" \
    -m 256M \
    "$@" \
    -netdev user,id=net0 \
    -device e1000,netdev=net0,mac=52:54:00:12:34:56 \
    -display none -monitor none \
    -serial file:"$LOG" \
    -no-reboot &
QPID=$!

ok=0
i=0
while [ "$i" -lt "$TIMEOUT_TICKS" ]; do
    if grep -q "root@koelos" "$LOG" 2>/dev/null; then ok=1; break; fi
    sleep 0.5
    i=$((i + 1))
done

kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

echo "------------------ captured serial ------------------"
cat "$LOG" 2>/dev/null || true
echo ""
echo "-----------------------------------------------------"

if [ "$ok" -ne 1 ]; then
    echo "SMOKE TEST FAILED: never saw the shell prompt on serial" >&2
    exit 1
fi
if ! grep -q "KoelOS" "$LOG"; then
    echo "SMOKE TEST FAILED: boot banner missing from serial" >&2
    exit 1
fi

echo "SMOKE TEST PASSED: KoelOS booted to shell"
