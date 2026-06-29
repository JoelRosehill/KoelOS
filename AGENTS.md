# AGENTS.md

## Trust These Sources First
- Trust the shell scripts and assembly sources over prose docs. `README.md` and `docs/metal-boot.md` still mention `dist/vbox/koelOS.vdi`, but the current build writes `dist/vbox/KoelOS.vdi`.
- The README command list is incomplete. The real shell command set is whatever exists in `apps/*.asm`; `apps/help.asm` prints the generated `command_table`.

## Build And Verify
- `bash build_metal.sh` is the fastest full compile check. It regenerates `build/generated_apps.asm`, writes NASM errors to `build/build.log`, and produces `dist/metal/boot.bin`, `dist/metal/kernel.bin`, and `dist/metal/koelOS-metal.img`.
- `bash build_vbox.sh` is the end-to-end verification path. It rebuilds the metal image, converts it to `dist/vbox/KoelOS.vdi`, then launches through `launch_koelos_vdi.sh`.
- `./koel` is the unified build tool: `./koel build|run|test [--arch 32|64] [--target floppy|metal|all]`, plus `clean`/`list`. It builds, boots, and smoke-tests every arch × target combination. For `--arch 32` it defaults `run`/`test` to an emulated 32-bit CPU (`-cpu pentium3`) so the lite kernel is exercised the way real pre-2004 hardware would; `--arch 64` defaults to `qemu64`. For 64-bit it delegates to `build_metal.sh`/`build_floppy.sh`; for 32-bit it builds natively.
- `bash run_qemu.sh` is the fastest end-to-end check: it rebuilds the metal image and boots it in QEMU with the console mirrored to `-serial stdio`. Flags: `--floppy` (boot the 1.44 MB floppy image), `--no-build`, `--gdb` (gdb stub on :1234), `--headless`, `--debug-exit`.
- `bash build_floppy.sh` builds a floppy-bootable image (`dist/floppy/koelOS-floppy.img`). It reuses `build_metal.sh` to compile the kernel, then assembles `boot_floppy.asm` and lays out a 2880-sector image.
- `bash scripts/smoke_test.sh [metal|floppy]` boots the image headless in QEMU and asserts the serial log reaches the `root@koelos>` shell prompt. `.github/workflows/ci.yml` runs both modes on every push/PR.
- `bash launch_koelos_vdi.sh` relaunches an existing VDI without rebuilding. Use it when debugging VirtualBox behavior rather than the OS build itself.
- Verification here is build success plus a boot check (the QEMU smoke test, or a manual boot). There is no lint/typecheck/package-manager step.
- The console is mirrored to COM1 by `drivers/serial.asm` (via `print_char`/`newline`), so serial logs reflect on-screen output. KoelOS does not read input from serial; drive the shell via the keyboard (or QEMU monitor `sendkey`).
- All produced images are BIOS-only. There is no UEFI build flow in this repo.

## Assembly Wiring
- `boot.asm` is a 16-bit BIOS boot sector. `build_metal.sh` compiles it with `-d KERNEL_SECTORS=...` based on the current `kernel.bin` size; do not compile `boot.asm` separately with a guessed sector count.
- `boot_floppy.asm` is the floppy boot sector (`build_floppy.sh`). It loads the kernel via CHS (INT 13h AH=02h, 1.44 MB geometry: 18 spt, 2 heads) with retries + controller reset, and has a FAT BPB header so `start:` lives at offset `0x3E`. It mirrors `boot.asm`'s paging/long-mode/GDT block — if you change that block in `boot.asm`, mirror it here. Critical: it sets `ES=KERNEL_LOAD_SEG` for the CHS reads and **must reset `ES=0` before the `rep stosd`** page-table zero (that string op uses ES:DI in 16-bit mode; otherwise it wipes the loaded kernel at `0x11000`).
- Both `boot.bin` and `boot_floppy.bin` must stay exactly 512 bytes (the build scripts assert this).
- The floppy build is boot-only: `drivers/fs.asm` uses the IDE/ATA controller, which a floppy-only machine lacks, so storage commands report `[FS] Storage I/O error`. This is expected, not a regression.
- `build_metal.sh` hard-fails once `kernel.bin` exceeds `MAX_KERNEL_SECTORS=127`; increasing kernel size past that requires expanding the bootloader load window, not just retrying the build.
- This is a flat `-f bin` image, so every `times N db 0` buffer is written into `kernel.bin` and costs sectors. Large scratch buffers therefore live in identity-mapped RAM instead of the binary: `fs_dir_buffer` (`equ 0x301000`), command history (`HISTORY_BASE 0x300000`), and the editor text (`EDIT_TEXT 0x308000`). Boot paging maps the low 4GB, and the bump heap only reaches ~`0x210000`, so `0x300000+` is free. Add new big buffers the same way rather than reserving them in-image.
- `kernel.asm` is the 64-bit entrypoint at `0x10000`. It includes `helpers.asm` plus the generated `build/generated_apps.asm`.
- `kernel32.asm` is a separate, self-contained **32-bit** "lite" kernel (also at `0x10000`) for CPUs without long mode. It is NOT generated from `apps/`/`drivers/` (those are 64-bit) — it has its own inline VGA/serial/keyboard/RTC/shell and a small static `command_table` (`dd` entries, not `dq`). `boot_floppy32.asm` (CHS) and `boot_metal32.asm` (LBA) enter 32-bit protected mode with flat 4 GB segments (no paging/long mode) and jump to it. Keep it lean; it is built by `./koel ... --arch 32`, not the `build_*.sh` scripts.

## Adding Commands Or Drivers
- Every `apps/*.asm` file is auto-added to `command_table`. A new command file must define both `cmd_<name>` and `do_<name>` labels or the generated manifest will not match the kernel's dispatch expectations.
- `build/generated_apps.asm` is regenerated on every `build_metal.sh` run. Do not hand-edit it.
- `apps/*.asm` and `drivers/*.asm` are discovered by shell glob order. If include order matters, filename prefixes matter.
- `drivers/00_net_stack.asm` is the manual network stack hub. `build_metal.sh` skips auto-including `arp_handle.asm`, `dns.asm`, `tcp.asm`, and `http.asm`, so networking changes often need to be checked against both the skip list and `00_net_stack.asm`.

## VirtualBox Contract
- The supported VM profile is NAT with Intel `82540EM` and MAC `525400123456`; that configuration is enforced by `launch_koelos_vdi.sh`.
- `kernel.asm` hardcodes the same MAC in `my_mac`. If you change the VirtualBox MAC in the launcher, update the kernel default too or networking will drift.
- Repo-local VirtualBox state lives under `.koelos-vm/` and is ignored by git.
- `build_vbox.sh` expects the portable VM to be stopped before rebuilding the disk image. `launch_koelos_vdi.sh` is where saved-state and stale/duplicate VDI UUID cleanup is handled.

## Shell Script Edits
- This repo is being used on macOS with `/bin/bash` 3.2. Keep repo scripts compatible with Bash 3.2; avoid Bash 4-only features.
