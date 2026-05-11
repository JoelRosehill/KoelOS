#!/bin/bash
set -euo pipefail

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# --- Helper Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
METAL_SCRIPT="$ROOT_DIR/build_metal.sh"
LAUNCH_SCRIPT="$ROOT_DIR/launch_koelos_vdi.sh"
METAL_IMG="$ROOT_DIR/dist/metal/koelOS-metal.img"
VBOX_DIR="$ROOT_DIR/dist/vbox"
VDI_FILE="$VBOX_DIR/KoelOS.vdi"
VBOXMANAGE="${VBOXMANAGE:-VBoxManage}"
STORAGE_CTL="IDE Controller"

portable_vm_name() {
    local cksum_output

    cksum_output="$(printf '%s' "$ROOT_DIR" | cksum)"
    printf 'KoelOS-Portable-%s\n' "${cksum_output%% *}"
}

detach_existing_vdi() {
    local vm_name="$1"

    "$VBOXMANAGE" storageattach "$vm_name" --storagectl "$STORAGE_CTL" --port 0 --device 0 --type hdd --medium none >/dev/null 2>&1 || true
}

require_stopped_vm() {
    local vm_name="$1"
    local vm_state

    if ! "$VBOXMANAGE" showvminfo "$vm_name" >/dev/null 2>&1; then
        return 0
    fi

    vm_state="$("$VBOXMANAGE" showvminfo "$vm_name" --machinereadable | sed -n 's/^VMState="\([^"]*\)"/\1/p')"
    case "$vm_state" in
        running|starting|restoring|saving|paused)
            log_error "VirtualBox VM '$vm_name' is $vm_state. Stop it before rebuilding the disk image."
            ;;
    esac
}

echo -e "${CYAN}${BOLD}========================================="
echo -e " KoelOS Advanced Build Engine (VirtualBox)"
echo -e "=========================================${NC}"

command -v "$VBOXMANAGE" >/dev/null 2>&1 || log_error "VBoxManage not found. Install VirtualBox first."
[ ! -f "$LAUNCH_SCRIPT" ] && log_error "Launcher script missing: $LAUNCH_SCRIPT"

mkdir -p "$VBOX_DIR"

log_info "Building shared metal image..."
bash "$METAL_SCRIPT"
[ ! -f "$METAL_IMG" ] && log_error "Metal image missing after build: $METAL_IMG"

VM_NAME="$(portable_vm_name)"

log_info "Preparing VirtualBox drive..."
require_stopped_vm "$VM_NAME"
detach_existing_vdi "$VM_NAME"
"$VBOXMANAGE" closemedium disk "$VDI_FILE" --delete >/dev/null 2>&1 || true
rm -f "$VDI_FILE"

log_info "Converting metal image to VirtualBox VDI..."
"$VBOXMANAGE" convertfromraw "$METAL_IMG" "$VDI_FILE" --format VDI >/dev/null
[ ! -f "$VDI_FILE" ] && log_error "VirtualBox VDI missing after conversion: $VDI_FILE"

echo -e "\n${GREEN}${BOLD}BUILD COMPLETE! Launching VirtualBox...${NC}\n"
echo "Metal image: $METAL_IMG"
echo "VirtualBox VDI: $VDI_FILE"
bash "$LAUNCH_SCRIPT"
