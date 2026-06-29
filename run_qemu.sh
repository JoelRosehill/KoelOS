#!/bin/bash
# Build (unless told not to) and boot the KoelOS metal image in QEMU.
# QEMU emulates the same Intel 82540EM NIC as the VirtualBox target, so the
# whole network stack works, but boot is instant and serial logging is free.
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
QEMU="qemu-system-x86_64"

BUILD=1
GDB=0
HEADLESS=0
DEBUG_EXIT=0
FLOPPY=0
EXTRA=""

usage() {
    cat <<'EOF'
Usage: run_qemu.sh [options] [-- extra qemu args]

  --floppy       Boot the 1.44 MB floppy image (CHS boot, no IDE disk attached)
  --no-build     Boot the existing image without rebuilding
  --gdb          Pause at reset and expose a gdb stub (connect: target remote :1234)
  --headless     No display window; console only on the serial line
  --debug-exit   Attach isa-debug-exit so the guest can set the QEMU exit code
  -h, --help     Show this help

Examples:
  bash run_qemu.sh                 # build + boot with a window and serial on stdio
  bash run_qemu.sh --floppy        # build + boot from the floppy image
  bash run_qemu.sh --no-build      # quick reboot of the current image
  bash run_qemu.sh --gdb           # then: gdb -ex 'target remote :1234'
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --floppy)     FLOPPY=1 ;;
        --no-build)   BUILD=0 ;;
        --gdb)        GDB=1 ;;
        --headless)   HEADLESS=1 ;;
        --debug-exit) DEBUG_EXIT=1 ;;
        -h|--help)    usage; exit 0 ;;
        --)           shift; EXTRA="$*"; break ;;
        *)            echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

command -v "$QEMU" >/dev/null 2>&1 || { echo "ERROR: $QEMU not found in PATH" >&2; exit 1; }

if [ "$FLOPPY" -eq 1 ]; then
    IMG="$ROOT_DIR/dist/floppy/koelOS-floppy.img"
    [ "$BUILD" -eq 1 ] && bash "$ROOT_DIR/build_floppy.sh"
else
    IMG="$ROOT_DIR/dist/metal/koelOS-metal.img"
    [ "$BUILD" -eq 1 ] && bash "$ROOT_DIR/build_metal.sh"
fi
[ -f "$IMG" ] || { echo "ERROR: image not found: $IMG (run without --no-build)" >&2; exit 1; }

if [ "$FLOPPY" -eq 1 ]; then
    set -- \
        -m 256M \
        -drive file="$IMG",if=floppy,format=raw \
        -boot a \
        -netdev user,id=net0 \
        -device e1000,netdev=net0,mac=52:54:00:12:34:56 \
        -serial stdio \
        -no-reboot
else
    set -- \
        -m 256M \
        -drive format=raw,file="$IMG",if=ide \
        -netdev user,id=net0 \
        -device e1000,netdev=net0,mac=52:54:00:12:34:56 \
        -serial stdio \
        -no-reboot
fi

if [ "$HEADLESS" -eq 1 ]; then
    set -- "$@" -display none
fi
if [ "$GDB" -eq 1 ]; then
    set -- "$@" -s -S
fi
if [ "$DEBUG_EXIT" -eq 1 ]; then
    set -- "$@" -device isa-debug-exit,iobase=0xf4,iosize=0x04
fi

echo "Booting KoelOS in QEMU (Ctrl-A X to quit the serial console)..."
# shellcheck disable=SC2086
exec "$QEMU" "$@" $EXTRA
