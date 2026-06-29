#!/bin/bash
set -euo pipefail

# Builds a bootable 1.44 MB floppy image of KoelOS. The kernel is identical to
# the metal/vbox builds; only the boot sector differs (CHS loader, see
# boot_floppy.asm). Reuses build_metal.sh to compile the kernel and enforce the
# 127-sector single-segment cap.

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DIST_DIR="$ROOT_DIR/dist/floppy"
BUILD_LOG="$ROOT_DIR/build/build.log"
KERNEL_BIN="$ROOT_DIR/dist/metal/kernel.bin"
BOOT_BIN="$DIST_DIR/boot_floppy.bin"
FLOPPY_IMG="$DIST_DIR/koelOS-floppy.img"

# 1.44 MB floppy = 2880 sectors of 512 bytes
FLOPPY_SECTORS=2880

echo -e "${CYAN}${BOLD}========================================="
echo -e " KoelOS Advanced Build Engine (Floppy)"
echo -e "=========================================${NC}"

# [1] Build the shared kernel (regenerates manifest, enforces the sector cap).
log_info "Building shared kernel via build_metal.sh..."
bash "$ROOT_DIR/build_metal.sh" >/dev/null
[ ! -f "$KERNEL_BIN" ] && log_error "kernel.bin missing after build: $KERNEL_BIN"

mkdir -p "$DIST_DIR"

# [2] Size the kernel and assemble the CHS boot sector for it.
KERNEL_SIZE=$(wc -c < "$KERNEL_BIN")
KERNEL_SECTORS=$(((KERNEL_SIZE + 511) / 512))
log_info "Kernel is $KERNEL_SIZE bytes ($KERNEL_SECTORS sectors)."

if [ "$((1 + KERNEL_SECTORS))" -gt "$FLOPPY_SECTORS" ]; then
    log_error "Boot + kernel need $((1 + KERNEL_SECTORS)) sectors but a floppy holds $FLOPPY_SECTORS."
fi

log_info "Assembling floppy bootloader for $KERNEL_SECTORS kernel sectors..."
if ! nasm -f bin "$ROOT_DIR/boot_floppy.asm" -o "$BOOT_BIN" -d KERNEL_SECTORS="$KERNEL_SECTORS" 2>"$BUILD_LOG"; then
    grep -i "error" "$BUILD_LOG" | sed "s/^/  /" || true
    log_error "Floppy bootloader failed to assemble!"
fi

BOOT_SIZE=$(wc -c < "$BOOT_BIN")
if [ "$BOOT_SIZE" -ne 512 ]; then
    log_error "boot_floppy.bin must be exactly 512 bytes (currently $BOOT_SIZE)"
fi

# [3] Lay out the floppy image: boot sector at LBA 0, kernel at LBA 1+.
log_info "Creating 1.44 MB floppy image..."
dd if=/dev/zero of="$FLOPPY_IMG" bs=512 count="$FLOPPY_SECTORS" status=none
dd if="$BOOT_BIN" of="$FLOPPY_IMG" conv=notrunc bs=512 count=1 status=none
dd if="$KERNEL_BIN" of="$FLOPPY_IMG" conv=notrunc bs=512 seek=1 status=none

IMG_SIZE=$(wc -c < "$FLOPPY_IMG")
log_success "Floppy image created: $FLOPPY_IMG ($IMG_SIZE bytes)"

echo -e "\n${GREEN}${BOLD}BUILD COMPLETE!${NC}"
echo "Kernel size:  $KERNEL_SIZE bytes ($KERNEL_SECTORS sectors)"
echo "Bootloader:   $BOOT_BIN"
echo "Floppy image: $FLOPPY_IMG"
echo ""
echo "Run it:   bash run_qemu.sh --floppy"
echo "Flash it: sudo dd if=$FLOPPY_IMG of=/dev/diskN bs=512"
