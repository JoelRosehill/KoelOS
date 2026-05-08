#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
VBOXMANAGE="${VBOXMANAGE:-VBoxManage}"
STORAGE_CTL="IDE Controller"
MAC_ADDRESS="525400123456"
VM_BASE_DIR="$SCRIPT_DIR/.koelos-vm"

find_vdi() {
    local candidate

    for candidate in \
        "$SCRIPT_DIR/KoelOS.vdi" \
        "$SCRIPT_DIR/koelOS.vdi" \
        "$SCRIPT_DIR/dist/vbox/KoelOS.vdi" \
        "$SCRIPT_DIR/dist/vbox/koelOS.vdi"
    do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

attach_vdi() {
    local attach_output

    if attach_output="$("$VBOXMANAGE" storageattach "$VM_NAME" --storagectl "$STORAGE_CTL" --port 0 --device 0 --type hdd --medium "$VDI_PATH" 2>&1)"; then
        return 0
    fi

    if printf '%s' "$attach_output" | grep -q "Cannot register the hard disk"; then
        echo "Detected duplicate VirtualBox disk UUID. Reassigning a new UUID to the local VDI copy..."
        "$VBOXMANAGE" internalcommands sethduuid "$VDI_PATH" >/dev/null
        "$VBOXMANAGE" storageattach "$VM_NAME" --storagectl "$STORAGE_CTL" --port 0 --device 0 --type hdd --medium "$VDI_PATH" >/dev/null
        return 0
    fi

    printf '%s\n' "$attach_output" >&2
    return 1
}

if ! command -v "$VBOXMANAGE" >/dev/null 2>&1; then
    echo "Error: VBoxManage not found. Install VirtualBox first." >&2
    exit 1
fi

VDI_PATH="$(find_vdi || true)"
if [ -z "$VDI_PATH" ]; then
    echo "Error: KoelOS.vdi not found beside this script." >&2
    echo "Looked for:" >&2
    echo "  $SCRIPT_DIR/KoelOS.vdi" >&2
    echo "  $SCRIPT_DIR/koelOS.vdi" >&2
    echo "  $SCRIPT_DIR/dist/vbox/KoelOS.vdi" >&2
    echo "  $SCRIPT_DIR/dist/vbox/koelOS.vdi" >&2
    exit 1
fi

CKSUM_OUTPUT="$(printf '%s' "$SCRIPT_DIR" | cksum)"
VM_SUFFIX="${CKSUM_OUTPUT%% *}"
VM_NAME="KoelOS-Portable-$VM_SUFFIX"

mkdir -p "$VM_BASE_DIR"

if ! "$VBOXMANAGE" showvminfo "$VM_NAME" >/dev/null 2>&1; then
    "$VBOXMANAGE" createvm --name "$VM_NAME" --ostype "Other_64" --register --basefolder "$VM_BASE_DIR" >/dev/null
    "$VBOXMANAGE" storagectl "$VM_NAME" --name "$STORAGE_CTL" --add ide >/dev/null
fi

"$VBOXMANAGE" modifyvm "$VM_NAME" \
    --memory 512 \
    --vram 16 \
    --boot1 disk \
    --nic1 nat \
    --nictype1 82540EM \
    --nicpromisc1 allow-all \
    --macaddress1 "$MAC_ADDRESS" \
    --cableconnected1 on >/dev/null

VM_STATE="$("$VBOXMANAGE" showvminfo "$VM_NAME" --machinereadable | sed -n 's/^VMState="\([^"]*\)"/\1/p')"
if [ "$VM_STATE" = "running" ] || [ "$VM_STATE" = "starting" ] || [ "$VM_STATE" = "restoring" ] || [ "$VM_STATE" = "saving" ]; then
    echo "KoelOS is already running in VirtualBox as $VM_NAME"
    exit 0
fi

if [ "$VM_STATE" = "paused" ]; then
    "$VBOXMANAGE" controlvm "$VM_NAME" resume
    exit 0
fi

"$VBOXMANAGE" storageattach "$VM_NAME" --storagectl "$STORAGE_CTL" --port 0 --device 0 --type hdd --medium none >/dev/null 2>&1 || true
attach_vdi

echo "Launching $VM_NAME"
echo "Disk image: $VDI_PATH"
"$VBOXMANAGE" startvm "$VM_NAME" --type gui
