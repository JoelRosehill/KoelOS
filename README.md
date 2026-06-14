# KoelOS

> A hand-built 64-bit hobby OS written in NASM that boots straight into a shell, brings up networking, and ships with a text-only browser and a serial console.

![KoelOS browser demo](docs/media/browser-demo.gif)

KoelOS is a solo-built operating system project focused on direct control over the full stack:

- BIOS boot sector
- long mode switch
- VGA text shell
- keyboard input
- Intel E1000 networking
- DHCP, DNS, ping, packet listening
- HTTP fetch + a text browser inspired by sites like `frogfind.com`

## Screenshots

| Boot | Text Browser |
| --- | --- |
| ![KoelOS boot screen](docs/media/boot-screen.png) | ![KoelOS browser on FrogFind](docs/media/browser-frogfind.png) |

## Highlights

- Pure NASM codebase
- Custom BIOS bootloader that enters 64-bit long mode
- Shell-first UX with one command per file in `apps/`
- Small network stack with ARP, IPv4, ICMP, UDP, DNS, TCP, and HTTP pieces
- `browser <domain>` command that renders text-only pages in the terminal
- Metal and VirtualBox build targets with separate output directories
- Linux-tested VirtualBox support with a portable `.vdi` launcher script

## Commands

The authoritative list is whatever lives in `apps/*.asm`; `help` prints it with a
short description for each command. Current set:

- System: `help`, `ver`, `clear`, `echo`, `mem`, `date`, `uptime`, `reboot`, `shutdown`
- Files: `ls`, `cat`, `hex`, `edit`, `mkfile`, `cp`, `mv`, `rm`, `binwrite`, `format`
- Network: `netinit`, `ifconfig`, `ip`, `dhcp`, `dns`, `ping`, `listen`, `announce`, `diag`, `fetch`, `browser`
- Language: `alkan` (REPL or run a program)

Good demo commands:

```text
browser frogfind.com
browser example.com
dns example.com
ping
ifconfig
```

## Project Layout

```text
.
├── apps/           # shell commands, one command per file
├── drivers/        # low-level runtime, VGA, NIC, TCP/IP, HTTP helpers
├── build/          # generated manifests and build logs
├── dist/
│   ├── metal/      # raw BIOS disk image and binaries
│   └── vbox/       # VirtualBox disk image
├── docs/
├── launch_koelos_vdi.sh  # portable VirtualBox launcher for a local VDI copy
├── boot.asm        # boot sector + transition to long mode
├── kernel.asm      # shell entry point and global state
├── build_metal.sh  # build a raw BIOS disk image for real hardware
└── build_vbox.sh   # build and launch the VirtualBox target
```

## Quick Start

### Run in QEMU (fastest dev loop)

```bash
bash run_qemu.sh
```

This builds the metal image and boots it in QEMU with the console mirrored to
the serial line (`-serial stdio`). No VDI conversion, instant boot, and the same
Intel 82540EM NIC as VirtualBox so the network stack still works. Useful flags:

```bash
bash run_qemu.sh --no-build     # reboot the current image
bash run_qemu.sh --gdb          # pause at reset, then: gdb -ex 'target remote :1234'
bash run_qemu.sh --headless     # no window, console only on serial
```

A headless boot smoke test (used by CI) lives at `scripts/smoke_test.sh`.

### Build the bare-metal image

```bash
bash build_metal.sh
```

Output:

```text
dist/metal/koelOS-metal.img
```

Build and launch the VirtualBox target:

```bash
bash build_vbox.sh
```

Output:

```text
dist/vbox/koelOS.vdi
```

## Portable VDI Launch

If you just want to run a downloaded `KoelOS.vdi`, use the portable launcher:

```bash
bash launch_koelos_vdi.sh
```

It looks for:

- `./KoelOS.vdi`
- `./koelOS.vdi`
- `./dist/vbox/KoelOS.vdi`
- `./dist/vbox/koelOS.vdi`

This means you can drop both files into a folder like `Downloads/` and launch KoelOS directly from there.

The launcher also:

- creates a local VirtualBox VM profile automatically
- forces the KoelOS-compatible NIC settings
- uses `NAT`
- fixes duplicate copied-VDI UUID conflicts automatically

On Linux, VirtualBox `NAT` not showing a host adapter dropdown is normal. That dropdown only appears for `Bridged Adapter` mode.

Recommended pair:

```text
Downloads/
├── KoelOS.vdi
└── launch_koelos_vdi.sh
```

## Real Hardware

KoelOS now builds into a BIOS-bootable raw disk image for USB/HDD boot on a real machine.

See `docs/metal-boot.md` for:

- flashing instructions
- expected firmware settings
- current bare-metal limitations

Short version:

```bash
diskutil unmountDisk /dev/diskN
sudo dd if=dist/metal/koelOS-metal.img of=/dev/rdiskN bs=1m
diskutil eject /dev/diskN
```

## Current Hardware Reality

The OS boots on a BIOS-style PC image now, but networking is still tuned for the Intel `82540EM` NIC used by VirtualBox.

That means:

- shell boot on real hardware is the target
- networking on real hardware is not universal yet
- VirtualBox `NAT` is currently the best-supported environment for the browser and network stack
- VirtualBox on Linux is now supported with the bundled `launch_koelos_vdi.sh` flow

## Why It Exists

KoelOS is not trying to be a clone of a modern desktop OS.

It is a direct, personal OS project built to explore the whole path from boot sector to browser output with as little abstraction as possible.

## Status

Working right now:

- boots to shell
- runs in VirtualBox
- launches from a copied `.vdi` on Linux through the portable launcher
- builds a raw metal image
- resolves DNS
- performs HTTP GET requests
- renders text-only pages through `browser`

In progress / future work:

- broader bare-metal NIC support
- cleaner HTML-to-text rendering
- richer browser navigation
- UEFI boot support
