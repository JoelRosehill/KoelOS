# KoelOS

> A hand-built 64-bit hobby OS written in NASM that boots straight into a shell, brings up networking, and ships with a text-only browser.

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

## Commands

Current shell commands:

- `announce`
- `browser`
- `colors`
- `dhcp`
- `diag`
- `dns`
- `fetch`
- `help`
- `ifconfig`
- `ip`
- `listen`
- `netinit`
- `ping`
- `ver`

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
├── boot.asm        # boot sector + transition to long mode
├── kernel.asm      # shell entry point and global state
├── build_metal.sh  # build a raw BIOS disk image for real hardware
└── build_vbox.sh   # build and launch the VirtualBox target
```

## Quick Start

Build the bare-metal image:

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

## Why It Exists

KoelOS is not trying to be a clone of a modern desktop OS.

It is a direct, personal OS project built to explore the whole path from boot sector to browser output with as little abstraction as possible.

## Status

Working right now:

- boots to shell
- runs in VirtualBox
- builds a raw metal image
- resolves DNS
- performs HTTP GET requests
- renders text-only pages through `browser`

In progress / future work:

- broader bare-metal NIC support
- cleaner HTML-to-text rendering
- richer browser navigation
- UEFI boot support
