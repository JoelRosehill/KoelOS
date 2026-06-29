# Metal Boot

`./build.sh --target metal` produces a BIOS hard-disk image.

## Output Layout

- `build/generated_apps.asm`: auto-generated command and driver manifest
- `build/build.log`: last NASM build log
- `dist/metal/boot.bin`: boot sector
- `dist/metal/kernel.bin`: unpadded kernel binary
- `dist/metal/koelOS-metal.img`: raw BIOS disk image for USB/HDD boot
- `dist/vbox/koelOS.vdi`: VirtualBox disk image

## Build

Run:

```bash
./build.sh --target metal
```

## Write To USB

On macOS, identify the target disk with `diskutil list`, then write the image:

```bash
diskutil unmountDisk /dev/diskN
sudo dd if=dist/metal/koelOS-metal.img of=/dev/rdiskN bs=1m
diskutil eject /dev/diskN
```

Replace `diskN` with the correct USB device. This overwrites the entire disk.

## Real Hardware Requirements

- x86_64 machine with legacy BIOS or CSM boot enabled
- Secure Boot disabled
- VGA text mode available
- PS/2 keyboard support, or BIOS USB legacy keyboard emulation enabled

## Current Real Hardware Limits

- Networking is still written for the Intel `82540EM` virtual NIC used by VirtualBox.
- Most real PCs use a different Ethernet controller, so `netinit` will likely fail on bare metal until a real hardware NIC driver is added.
- The image is a raw BIOS disk, not a UEFI boot image.
