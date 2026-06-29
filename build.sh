#!/bin/bash
# build.sh — the one KoelOS build tool.
# Builds a disk image and can write it straight to a floppy.
#
#   ./build.sh                       # no args -> interactive menu (GUI on macOS)
#   ./build.sh [--arch 32|64] [--target floppy|metal]
#              [--write [DEVICE]] [--run] [--test] [--vdi] [--cpu MODEL]
#
# Defaults: --arch 64 --target floppy
#
#   --write [DEV]  after building, dd the image to a floppy (auto-detects a
#                  removable 1.44 MB disk if DEV is omitted; always confirms)
#   --run          boot the built image in QEMU (serial on stdio)
#   --test         headless boot smoke test (asserts the shell prompt)
#   --vdi          also convert a metal image to a VirtualBox .vdi
#
# 64-bit needs a long-mode CPU; the 32-bit "lite" kernel runs on any 386+,
# so --run/--test default to an emulated 32-bit CPU for --arch 32.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
shopt -s nullglob

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info() { printf "${BLUE}[build]${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}[ok]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[warn]${NC} %s\n" "$1"; }
die()  { printf "${RED}[error]${NC} %s\n" "$1" >&2; exit 1; }

# --- interactive menu (used when build.sh is run with no arguments) ----------
# Native dialog GUI on macOS; plain-text menu everywhere else. Set BUILD_NOGUI=1
# to force the text menu.
osa_pick() {   # prompt opt...  -> echoes the chosen option ("" if cancelled)
    local prompt="$1"; shift
    local items="" o
    for o in "$@"; do items="$items, \"$o\""; done
    items="${items#, }"
    osascript \
        -e "set r to choose from list {$items} with prompt \"$prompt\" with title \"KoelOS build.sh\" without empty selection allowed" \
        -e 'if r is false then return ""' \
        -e 'return item 1 of r' 2>/dev/null
}

gui_menu() {
    local a t act
    a="$(osa_pick "CPU width" "64-bit  (full OS, needs a 64-bit CPU)" "32-bit  (lite shell, any 386+)")"
    [ -z "$a" ] && { info "cancelled"; exit 0; }
    case "$a" in 32*) ARCH=32 ;; *) ARCH=64 ;; esac
    t="$(osa_pick "Disk image" "floppy  (1.44 MB)" "metal  (hard disk)")"
    [ -z "$t" ] && { info "cancelled"; exit 0; }
    case "$t" in metal*) TARGET=metal ;; *) TARGET=floppy ;; esac
    act="$(osa_pick "Action" "Build only" "Build + run in QEMU" "Build + smoke test" "Build + write to floppy" "Build + VirtualBox .vdi")"
    [ -z "$act" ] && { info "cancelled"; exit 0; }
    case "$act" in
        *"run in QEMU"*) RUN=1 ;;
        *"smoke test"*)  TEST=1 ;;
        *"write to"*)    WRITE=1; TARGET=floppy ;;
        *"VirtualBox"*)  VDI=1; TARGET=metal ;;
    esac
}

text_menu() {
    local c
    printf "\n${BOLD}KoelOS build${NC}  (run with flags to skip this menu — see --help)\n"
    printf "\nCPU width:\n  1) 64-bit  (full OS, needs a 64-bit CPU)\n  2) 32-bit  (lite shell, any 386+)\n> "
    read -r c || exit 0; case "$c" in 2) ARCH=32 ;; *) ARCH=64 ;; esac
    printf "\nDisk image:\n  1) floppy  (1.44 MB)\n  2) metal   (hard disk)\n> "
    read -r c || exit 0; case "$c" in 2) TARGET=metal ;; *) TARGET=floppy ;; esac
    printf "\nAction:\n  1) Build only\n  2) Build + run in QEMU\n  3) Build + smoke test\n  4) Build + write to floppy\n  5) Build + VirtualBox .vdi\n> "
    read -r c || exit 0
    case "$c" in
        2) RUN=1 ;;
        3) TEST=1 ;;
        4) WRITE=1; TARGET=floppy ;;
        5) VDI=1; TARGET=metal ;;
    esac
    printf "\n"
}

run_menu() {
    if [ "$(uname)" = Darwin ] && command -v osascript >/dev/null 2>&1 && [ -z "${BUILD_NOGUI:-}" ]; then
        gui_menu
    else
        text_menu
    fi
    local extra=""
    [ "$RUN"   = 1 ] && extra="$extra + run"
    [ "$TEST"  = 1 ] && extra="$extra + test"
    [ "$WRITE" = 1 ] && extra="$extra + write"
    [ "$VDI"   = 1 ] && extra="$extra + vdi"
    info "building ${ARCH}-bit ${TARGET}${extra}"
}

ARCH=64; TARGET=floppy; WRITE=0; DEV=""; RUN=0; TEST=0; VDI=0; CPU=""
if [ $# -eq 0 ]; then run_menu; fi
while [ $# -gt 0 ]; do
    case "$1" in
        --arch)   ARCH="$2"; shift ;;
        --target) TARGET="$2"; shift ;;
        --write)  WRITE=1; case "${2:-}" in /dev/*) DEV="$2"; shift ;; esac ;;
        --run)    RUN=1 ;;
        --test)   TEST=1 ;;
        --vdi)    VDI=1 ;;
        --cpu)    CPU="$2"; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done
case "$ARCH"   in 32|64) ;; *) die "--arch must be 32 or 64" ;; esac
case "$TARGET" in floppy|metal) ;; *) die "--target must be floppy or metal" ;; esac
[ -z "$CPU" ] && { [ "$ARCH" = 32 ] && CPU=pentium3 || CPU=qemu64; }

FLOPPY_SECTORS=2880      # 1.44 MB
METAL_MB=64

# Output paths -------------------------------------------------------------
if [ "$ARCH" = 64 ]; then
    [ "$TARGET" = floppy ] && OUTDIR="$ROOT/dist/floppy"  || OUTDIR="$ROOT/dist/metal"
    [ "$TARGET" = floppy ] && IMG="$OUTDIR/koelOS-floppy.img" || IMG="$OUTDIR/koelOS-metal.img"
else
    [ "$TARGET" = floppy ] && OUTDIR="$ROOT/dist/floppy32" || OUTDIR="$ROOT/dist/metal32"
    [ "$TARGET" = floppy ] && IMG="$OUTDIR/koelOS32-floppy.img" || IMG="$OUTDIR/koelOS32-metal.img"
fi
BOOTBIN="$OUTDIR/boot.bin"
KBIN="$OUTDIR/kernel.bin"

# Bootloader source per arch+target ----------------------------------------
case "$ARCH-$TARGET" in
    64-floppy) BOOTSRC="$ROOT/boot_floppy.asm" ;;
    64-metal)  BOOTSRC="$ROOT/boot.asm" ;;
    32-floppy) BOOTSRC="$ROOT/boot_floppy32.asm" ;;
    32-metal)  BOOTSRC="$ROOT/boot_metal32.asm" ;;
esac

# --- build steps ----------------------------------------------------------
gen_manifest() {   # 64-bit only: auto-discover drivers + apps
    local gen="$ROOT/build/generated_apps.asm" f name
    mkdir -p "$ROOT/build"
    printf '; --- Auto-generated by build.sh ---\n\n; --- System Drivers ---\n' > "$gen"
    for f in "$ROOT"/drivers/*.asm; do
        name="$(basename "$f")"
        case "$name" in arp_handle.asm|dns.asm|tcp.asm|http.asm) continue ;; esac
        printf '%%include "drivers/%s"\n' "$name" >> "$gen"
    done
    printf '\ncommand_table:\n' >> "$gen"
    for f in "$ROOT"/apps/*.asm; do printf '    dq cmd_%s, do_%s\n' "$(basename "$f" .asm)" "$(basename "$f" .asm)" >> "$gen"; done
    printf '    dq 0, 0\n\n; --- User Applications ---\n' >> "$gen"
    for f in "$ROOT"/apps/*.asm; do printf '%%include "apps/%s"\n' "$(basename "$f")" >> "$gen"; done
}

build_kernel() {
    mkdir -p "$OUTDIR"
    if [ "$ARCH" = 64 ]; then
        info "generating component manifest"
        gen_manifest
        info "compiling 64-bit kernel"
        nasm -f bin "$ROOT/kernel.asm" -o "$KBIN" -w-label-redef-late || die "kernel.asm failed"
    else
        info "compiling 32-bit lite kernel"
        nasm -f bin "$ROOT/kernel32.asm" -o "$KBIN" || die "kernel32.asm failed"
    fi
    KSIZE=$(wc -c < "$KBIN"); KSECTORS=$(((KSIZE + 511) / 512))
    if [ "$KSECTORS" -gt 127 ]; then die "kernel needs $KSECTORS sectors (>127); grow the boot load window"; fi
}

build_boot() {
    info "assembling $(basename "$BOOTSRC") for $KSECTORS kernel sectors"
    nasm -f bin "$BOOTSRC" -o "$BOOTBIN" -d KERNEL_SECTORS="$KSECTORS" || die "$(basename "$BOOTSRC") failed"
    if [ "$(wc -c < "$BOOTBIN")" -ne 512 ]; then die "boot sector is not exactly 512 bytes"; fi
}

make_image() {
    if [ "$TARGET" = floppy ]; then
        if [ "$((1 + KSECTORS))" -gt "$FLOPPY_SECTORS" ]; then die "boot+kernel exceed a 1.44 MB floppy"; fi
        dd if=/dev/zero of="$IMG" bs=512 count="$FLOPPY_SECTORS" status=none
    else
        dd if=/dev/zero of="$IMG" bs=1m count="$METAL_MB" status=none
    fi
    dd if="$BOOTBIN" of="$IMG" conv=notrunc bs=512 count=1 status=none
    dd if="$KBIN"    of="$IMG" conv=notrunc bs=512 seek=1 status=none
    ok "built ${ARCH}-bit ${TARGET}: $IMG ($KSIZE byte kernel, $KSECTORS sectors)"
}

make_vdi() {
    [ "$TARGET" = metal ] || die "--vdi needs --target metal"
    command -v VBoxManage >/dev/null || die "VBoxManage not found"
    local vdi="$OUTDIR/KoelOS.vdi"
    rm -f "$vdi"; VBoxManage convertfromraw "$IMG" "$vdi" --format VDI >/dev/null
    ok "wrote VirtualBox image: $vdi"
}

# --- floppy writing -------------------------------------------------------
detect_floppy() {
    if [ "$(uname)" = Darwin ]; then
        local d
        for d in $(diskutil list 2>/dev/null | grep -oE '/dev/disk[0-9]+' | sort -u); do
            diskutil info "$d" 2>/dev/null | grep -q "1474560 Bytes" && { echo "$d"; return; }
        done
    else
        [ -e /dev/fd0 ] && echo /dev/fd0
    fi
}

write_floppy() {
    [ "$TARGET" = floppy ] || die "--write only makes sense with --target floppy"
    [ -f "$IMG" ] || die "no image to write: $IMG"
    local dev="$DEV"
    [ -z "$dev" ] && dev="$(detect_floppy)"
    [ -z "$dev" ] && die "no floppy found; pass it: --write /dev/diskN"

    warn "About to ERASE and overwrite: $dev"
    if [ "$(uname)" = Darwin ]; then
        diskutil info "$dev" 2>/dev/null | grep -E "Media Name|Disk Size|Removable Media" || true
    fi
    printf "Type 'yes' to write %s -> %s: " "$(basename "$IMG")" "$dev"
    local ans; read -r ans || true
    [ "$ans" = yes ] || die "aborted, nothing written"

    if [ "$(uname)" = Darwin ]; then
        diskutil unmountDisk "$dev"
        sudo dd if="$IMG" of="${dev/disk/rdisk}" bs=512
        diskutil eject "$dev"
    else
        sudo umount "$dev"* 2>/dev/null || true
        sudo dd if="$IMG" of="$dev" bs=512
        sync
    fi
    ok "wrote $IMG -> $dev"
}

# --- qemu -----------------------------------------------------------------
drive_args() {   # sets DRIVE array
    if [ "$TARGET" = floppy ]; then
        DRIVE=(-drive "file=$IMG,if=floppy,format=raw" -boot a)
    else
        DRIVE=(-drive "format=raw,file=$IMG,if=ide")
    fi
}

run_qemu() {
    command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not found"
    drive_args
    info "booting ${ARCH}-bit $TARGET on -cpu $CPU (Ctrl-A X to quit)"
    exec qemu-system-x86_64 -m 256M -cpu "$CPU" "${DRIVE[@]}" -serial stdio -no-reboot
}

smoke_test() {
    command -v qemu-system-x86_64 >/dev/null || die "qemu-system-x86_64 not found"
    drive_args
    local log; log="$(mktemp)"
    info "smoke test ${ARCH}-bit $TARGET on -cpu $CPU"
    qemu-system-x86_64 -m 256M -cpu "$CPU" "${DRIVE[@]}" \
        -display none -monitor none -serial file:"$log" -no-reboot &
    local pid=$! i=0
    while [ "$i" -lt 40 ]; do grep -q "root@koelos" "$log" 2>/dev/null && break; sleep 0.5; i=$((i+1)); done
    kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
    if grep -q "root@koelos" "$log" && grep -q "KoelOS" "$log"; then
        ok "booted to shell"; rm -f "$log"
    else
        warn "serial captured:"; cat "$log"; rm -f "$log"; die "did not reach the shell"
    fi
}

# --- main -----------------------------------------------------------------
printf "${CYAN}${BOLD}== KoelOS build: %s-bit %s ==${NC}\n" "$ARCH" "$TARGET"
build_kernel
build_boot
make_image
[ "$VDI"   = 1 ] && make_vdi
[ "$WRITE" = 1 ] && write_floppy
[ "$TEST"  = 1 ] && smoke_test
[ "$RUN"   = 1 ] && run_qemu
exit 0
