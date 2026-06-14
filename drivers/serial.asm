; drivers/serial.asm
; COM1 serial output. Mirrors the VGA text console so the OS can be driven
; and inspected headlessly (qemu -serial stdio, CI smoke tests, real logs).

%define COM1_BASE   0x3F8
%define COM1_DATA   (COM1_BASE + 0)
%define COM1_IER    (COM1_BASE + 1)
%define COM1_FCR    (COM1_BASE + 2)
%define COM1_LCR    (COM1_BASE + 3)
%define COM1_MCR    (COM1_BASE + 4)
%define COM1_LSR    (COM1_BASE + 5)

; Configure COM1 for 38400 baud, 8N1. Safe to call once at boot.
serial_init:
    push rax
    push rdx

    mov dx, COM1_IER
    xor al, al
    out dx, al              ; disable serial interrupts

    mov dx, COM1_LCR
    mov al, 0x80
    out dx, al              ; enable DLAB to set baud divisor

    mov dx, COM1_DATA
    mov al, 0x03
    out dx, al              ; divisor low  (115200 / 3 = 38400)
    mov dx, COM1_IER
    xor al, al
    out dx, al              ; divisor high

    mov dx, COM1_LCR
    mov al, 0x03
    out dx, al              ; 8 bits, no parity, 1 stop, clear DLAB

    mov dx, COM1_FCR
    mov al, 0xC7
    out dx, al              ; enable + clear FIFOs, 14-byte trigger

    mov dx, COM1_MCR
    mov al, 0x0B
    out dx, al              ; DTR + RTS + OUT2

    pop rdx
    pop rax
    ret

; Send the character in AL out COM1. Preserves all registers.
; If no UART is present the LSR reads 0xFF, so the "ready" bit looks set
; and this never hangs on hardware without a serial port.
serial_putc:
    push rax
    push rdx
    mov ah, al              ; stash the byte
.wait:
    mov dx, COM1_LSR
    in al, dx
    test al, 0x20           ; transmit holding register empty?
    jz .wait
    mov al, ah
    mov dx, COM1_DATA
    out dx, al
    pop rdx
    pop rax
    ret
