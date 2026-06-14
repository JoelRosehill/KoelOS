cmd_reboot db "reboot", 0

do_reboot:
    lea rsi, [.msg]
    call fs_print_line

    ; Pulse the 8042 keyboard controller reset line.
    mov al, 0xFE
    out 0x64, al

    ; If that did nothing, fall back to halting forever.
    cli
.hang:
    hlt
    jmp .hang

.msg db "Rebooting...", 0
