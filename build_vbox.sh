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
METAL_IMG="$ROOT_DIR/dist/metal/koelOS-metal.img"
VBOX_DIR="$ROOT_DIR/dist/vbox"
VDI_FILE="$VBOX_DIR/koelOS.vdi"
VM_NAME="KoelOS"

echo -e "${CYAN}${BOLD}========================================="
echo -e " KoelOS Advanced Build Engine (VirtualBox)"
echo -e "=========================================${NC}"

mkdir -p "$VBOX_DIR"

log_info "Building shared metal image..."
bash "$METAL_SCRIPT"
[ ! -f "$METAL_IMG" ] && log_error "Metal image missing after build: $METAL_IMG"

# [5] VirtualBox Deployment
log_info "Preparing VirtualBox Drive..."
VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type hdd --medium none >/dev/null 2>&1 || true
VBoxManage closemedium disk "$VDI_FILE" --delete >/dev/null 2>&1 || true
VBoxManage convertfromraw "$METAL_IMG" "$VDI_FILE" --format VDI >/dev/null 2>&1

if ! VBoxManage showvminfo "$VM_NAME" >/dev/null 2>&1; then
    log_info "First run detected! Creating VM '$VM_NAME'..."
    VBoxManage createvm --name "$VM_NAME" --ostype "Other_64" --register >/dev/null
    VBoxManage modifyvm "$VM_NAME" --memory 512 --vram 16 --boot1 disk
    VBoxManage storagectl "$VM_NAME" --name "IDE Controller" --add ide
fi

log_info "Applying KoelOS VM network profile..."
VBoxManage modifyvm "$VM_NAME" --nic1 nat --nictype1 82540EM --nicpromisc1 allow-all --macaddress1 525400123456 --cableconnected1 on

log_info "Attaching drive to VM..."
VBoxManage storageattach "$VM_NAME" --storagectl "IDE Controller" --port 0 --device 0 --type hdd --medium "$VDI_FILE"

echo -e "\n${GREEN}${BOLD}BUILD COMPLETE! Launching VirtualBox...${NC}\n"
echo "Metal image: $METAL_IMG"
echo "VirtualBox VDI: $VDI_FILE"
VBoxManage startvm "$VM_NAME" --type gui
