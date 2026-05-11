# AGENTS.md

## Trust These Sources First
- Trust the shell scripts and assembly sources over prose docs. `README.md` and `docs/metal-boot.md` still mention `dist/vbox/koelOS.vdi`, but the current build writes `dist/vbox/KoelOS.vdi`.
- The README command list is incomplete. The real shell command set is whatever exists in `apps/*.asm`; `apps/help.asm` prints the generated `command_table`.

## Build And Verify
- `bash build_metal.sh` is the fastest full compile check. It regenerates `build/generated_apps.asm`, writes NASM errors to `build/build.log`, and produces `dist/metal/boot.bin`, `dist/metal/kernel.bin`, and `dist/metal/koelOS-metal.img`.
- `bash build_vbox.sh` is the end-to-end verification path. It rebuilds the metal image, converts it to `dist/vbox/KoelOS.vdi`, then launches through `launch_koelos_vdi.sh`.
- `bash launch_koelos_vdi.sh` relaunches an existing VDI without rebuilding. Use it when debugging VirtualBox behavior rather than the OS build itself.
- There is no repo-local test, lint, typecheck, package-manager, or CI config. Verification here is build success plus manual boot.
- All produced images are BIOS-only. There is no UEFI build flow in this repo.

## Assembly Wiring
- `boot.asm` is a 16-bit BIOS boot sector. `build_metal.sh` compiles it with `-d KERNEL_SECTORS=...` based on the current `kernel.bin` size; do not compile `boot.asm` separately with a guessed sector count.
- `boot.bin` must stay exactly 512 bytes.
- `build_metal.sh` hard-fails once `kernel.bin` exceeds `MAX_KERNEL_SECTORS=127`; increasing kernel size past that requires expanding the bootloader load window, not just retrying the build.
- `kernel.asm` is the 64-bit entrypoint at `0x10000`. It includes `helpers.asm` plus the generated `build/generated_apps.asm`.

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
