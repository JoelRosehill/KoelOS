# AGENTS.md

## Trust These Sources First
- Trust the shell scripts and assembly sources over prose docs. `README.md` and `docs/metal-boot.md` still mention `dist/vbox/koelOS.vdi`, but the current build writes `dist/vbox/KoelOS.vdi`.
- The README command list is incomplete. The real shell command set is whatever exists in `apps/*.asm`; `apps/help.asm` prints the generated `command_table`.

## Build And Verify
- `./build.sh` is the one build tool. `./build.sh [--arch 32|64] [--target floppy|metal] [--write [DEV]] [--run] [--test] [--vdi] [--cpu MODEL]`. Defaults: `--arch 64 --target floppy`.
- For 64-bit it regenerates `build/generated_apps.asm` (driver/app manifest, with the `arp_handle/dns/tcp/http` skip list), compiles `kernel.asm`, and hard-fails past 127 sectors. For 32-bit it compiles `kernel32.asm`. Then it assembles the matching boot sector (`boot.asm`/`boot_floppy.asm`/`boot_metal32.asm`/`boot_floppy32.asm`), asserts it is 512 bytes, and lays out the image under `dist/{metal,floppy,metal32,floppy32}/`.
- `--test` boots headless in QEMU and asserts the serial log reaches `root@koelos>`; for `--arch 32` it uses `-cpu pentium3` so the lite kernel is exercised on a 32-bit CPU. `--run` boots interactively with serial on stdio. `--write [DEV]` `dd`s a floppy image to a removable disk (auto-detects a 1.44 MB device on macOS/Linux, always confirms, uses sudo). `--vdi` converts a metal image to a VirtualBox `.vdi`.
- `.github/workflows/ci.yml` runs `./build.sh --test` for all four arch × target combinations on every push/PR.
- Verification here is build success plus a boot check (`--test`, or a manual boot). There is no lint/typecheck/package-manager step.
- The console is mirrored to COM1 by `drivers/serial.asm` (via `print_char`/`newline`), so serial logs reflect on-screen output. KoelOS does not read input from serial; drive the shell via the keyboard (or QEMU monitor `sendkey`).
- All produced images are BIOS-only. There is no UEFI build flow in this repo.

## Assembly Wiring
- `boot.asm` is a 16-bit BIOS boot sector. `build.sh` compiles it with `-d KERNEL_SECTORS=...` based on the current `kernel.bin` size; do not compile `boot.asm` separately with a guessed sector count.
- `boot_floppy.asm` is the floppy boot sector (`build.sh --target floppy`). It loads the kernel via CHS (INT 13h AH=02h, 1.44 MB geometry: 18 spt, 2 heads) with retries + controller reset, and has a FAT BPB header so `start:` lives at offset `0x3E`. It mirrors `boot.asm`'s paging/long-mode/GDT block — if you change that block in `boot.asm`, mirror it here. Critical: it sets `ES=KERNEL_LOAD_SEG` for the CHS reads and **must reset `ES=0` before the `rep stosd`** page-table zero (that string op uses ES:DI in 16-bit mode; otherwise it wipes the loaded kernel at `0x11000`).
- Both `boot.bin` and `boot_floppy.bin` must stay exactly 512 bytes (the build scripts assert this).
- The floppy build is boot-only: `drivers/fs.asm` uses the IDE/ATA controller, which a floppy-only machine lacks, so storage commands report `[FS] Storage I/O error`. This is expected, not a regression.
- `build.sh` hard-fails once `kernel.bin` exceeds 127 sectors; increasing kernel size past that requires expanding the bootloader load window, not just retrying the build.
- This is a flat `-f bin` image, so every `times N db 0` buffer is written into `kernel.bin` and costs sectors. Large scratch buffers therefore live in identity-mapped RAM instead of the binary: `fs_dir_buffer` (`equ 0x301000`), command history (`HISTORY_BASE 0x300000`), and the editor text (`EDIT_TEXT 0x308000`). Boot paging maps the low 4GB, and the bump heap only reaches ~`0x210000`, so `0x300000+` is free. Add new big buffers the same way rather than reserving them in-image.
- `kernel.asm` is the 64-bit entrypoint at `0x10000`. It includes `helpers.asm` plus the generated `build/generated_apps.asm`.
- `kernel32.asm` is a separate, self-contained **32-bit** kernel (also at `0x10000`) for CPUs without long mode. It is NOT generated from `apps/`/`drivers/` (those are 64-bit); it has its own inline VGA/serial/keyboard/RTC/shell and a static `command_table` (`dd` entries, not `dq`), and `%include`s `fs32.asm` (KFS1 filesystem + file commands) and `alkan32.asm` (the Alkan language). `boot_floppy32.asm` (CHS) and `boot_metal32.asm` (LBA) enter 32-bit protected mode with flat 4 GB segments (no paging/long mode) and jump to it. It is built by `./build.sh --arch 32`.
- `fs32.asm` / `alkan32.asm` are hand-ports of `drivers/fs.asm` / `apps/alkan.asm` to 32-bit. The port discipline: `ESI` is the parse/cursor register, `EDI` is scratch (keyword pointers), `EBX`/`EBP` are the only reliably callee-saved GP regs — so the 64-bit `r8`–`r15` locals become named memory temps (`fw_*`, `fc_*`, `sl_*`, `br_end`, `cond_op`, …) for non-recursive functions, and `basic_parse_call_expr` (recursive) uses an `EBP` stack frame. Common bug class when extending these: holding a value in `EDI` across a call that uses keywords — don't.
- The 32-bit build has no networking by design (the stack is hardcoded for the VirtualBox/QEMU 82540EM and would not run on real pre-2004 NICs); all 32-bit FS buffers live below 1 MB inside the kernel image so no A20 line handling is needed.

## Adding Commands Or Drivers
- Every `apps/*.asm` file is auto-added to `command_table`. A new command file must define both `cmd_<name>` and `do_<name>` labels or the generated manifest will not match the kernel's dispatch expectations.
- `build/generated_apps.asm` is regenerated on every 64-bit `build.sh` run. Do not hand-edit it.
- `apps/*.asm` and `drivers/*.asm` are discovered by shell glob order. If include order matters, filename prefixes matter.
- `drivers/00_net_stack.asm` is the manual network stack hub. `build.sh` skips auto-including `arp_handle.asm`, `dns.asm`, `tcp.asm`, and `http.asm`, so networking changes often need to be checked against both the skip list and `00_net_stack.asm`.

## VirtualBox Contract
- A `.vdi` is produced by `./build.sh --arch 64 --target metal --vdi` (a `VBoxManage convertfromraw` of the metal image). The old `build_vbox.sh`/`launch_koelos_vdi.sh` helpers were removed; set up the VM manually.
- The supported VM profile is NAT with Intel `82540EM` and MAC `525400123456`.
- `kernel.asm` hardcodes the same MAC in `my_mac`. If you change the VirtualBox MAC, update the kernel default too or networking will drift.
- Repo-local VirtualBox state lives under `.koelos-vm/` and is ignored by git.

## Shell Script Edits
- This repo is being used on macOS with `/bin/bash` 3.2. Keep repo scripts compatible with Bash 3.2; avoid Bash 4-only features.
