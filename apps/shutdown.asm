cmd_shutdown db "shutdown", 0

do_shutdown:
    lea rsi, [.msg]
    call fs_print_line

    ; Try the well-known ACPI power-off ports for common hypervisors.
    mov dx, 0x604              ; QEMU >= 1.0
    mov ax, 0x2000
    out dx, ax
    mov dx, 0xB004             ; Bochs / older QEMU
    mov ax, 0x2000
    out dx, ax
    mov dx, 0x4004             ; VirtualBox
    mov ax, 0x3400
    out dx, ax

    ; If we are still alive, just stop.
    cli
.hang:
    hlt
    jmp .hang

.msg db "Shutting down...", 0
