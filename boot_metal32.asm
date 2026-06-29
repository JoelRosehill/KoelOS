; boot_metal32.asm
; Hard-disk (LBA / INT 13h AH=42h) boot sector for the 32-bit KoelOS kernel.
; Loads the kernel, enters 32-bit protected mode with flat 4 GB segments
; (no paging / long mode), and jumps to the kernel at 0x10000.
[bits 16]
[org 0x7c00]

%ifndef KERNEL_SECTORS
%define KERNEL_SECTORS 8
%endif

%define KERNEL_LOAD_SEG 0x1000
%define KERNEL_LOAD_OFF 0x0000
%define KERNEL_ENTRY    0x10000

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    mov [boot_drive], dl

    ; [1] Load kernel via LBA extended read
    mov si, disk_address_packet
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error

    ; [2] Enter 32-bit protected mode (flat segments, no paging)
    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:init32

disk_error:
    jmp $

[bits 32]
init32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000
    jmp KERNEL_ENTRY

; --- 32-bit flat GDT ---
gdt_start:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

boot_drive db 0

disk_address_packet:
    db 0x10, 0x00
    dw KERNEL_SECTORS
    dw KERNEL_LOAD_OFF
    dw KERNEL_LOAD_SEG
    dq 1

times 510-($-$$) db 0
dw 0xAA55
