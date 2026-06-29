; boot_floppy32.asm
; 1.44 MB floppy boot sector for the 32-bit KoelOS kernel. Loads the kernel via
; classic CHS reads (INT 13h AH=02h), then enters 32-bit protected mode with
; flat 4 GB segments (no paging / long mode) and jumps to the kernel at 0x10000.
; This is what runs on pre-2004 boards whose CPUs have no 64-bit long mode.
[bits 16]
[org 0x7c00]

%ifndef KERNEL_SECTORS
%define KERNEL_SECTORS 8
%endif

%define KERNEL_LOAD_SEG 0x1000
%define KERNEL_LOAD_OFF 0x0000
%define KERNEL_ENTRY    0x10000

    jmp short start
    nop

; --- BIOS Parameter Block (1.44 MB floppy geometry) ---
oem_name              db "KOELOS  "
bytes_per_sector      dw 512
sectors_per_cluster   db 1
reserved_sectors      dw 1
num_fats              db 2
root_entries          dw 224
total_sectors_16      dw 2880
media_descriptor      db 0xF0
sectors_per_fat       dw 9
sectors_per_track     dw 18
num_heads             dw 2
hidden_sectors        dd 0
total_sectors_32      dd 0
drive_number          db 0x00
reserved_flags        db 0
ext_boot_signature    db 0x29
volume_id             dd 0x4B4F454C
volume_label          db "KOELOS32 B"
fs_type               db "FAT12   "

start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    mov [boot_drive], dl

    xor ah, ah                  ; reset disk controller
    int 0x13

    ; --- Load kernel one CHS sector at a time into KERNEL_LOAD_SEG:0000 ---
    mov word [lba], 1
    mov ax, KERNEL_LOAD_SEG
    mov es, ax
    mov bx, KERNEL_LOAD_OFF
    mov cx, KERNEL_SECTORS

.load_loop:
    push cx
    mov di, 5
.try_read:
    mov ax, [lba]
    xor dx, dx
    div word [sectors_per_track]
    mov cl, dl
    inc cl
    xor dx, dx
    div word [num_heads]
    mov ch, al
    mov dh, dl
    mov dl, [boot_drive]
    mov ah, 0x02
    mov al, 1
    int 0x13
    jnc .read_ok
    xor ah, ah
    int 0x13
    dec di
    jnz .try_read
    jmp disk_error
.read_ok:
    pop cx
    add bx, 512
    jnc .no_seg_bump
    mov ax, es
    add ax, 0x1000
    mov es, ax
.no_seg_bump:
    inc word [lba]
    dec cx
    jnz .load_loop

    ; --- Enter 32-bit protected mode (flat segments, no paging) ---
    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1                   ; set PE
    mov cr0, eax
    jmp 0x08:init32

disk_error:
    mov si, msg_disk
.derr:
    lodsb
    test al, al
    jz .hang
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp .derr
.hang:
    hlt
    jmp .hang

msg_disk db "KoelOS32: FD read error", 13, 10, 0

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
    dq 0x0000000000000000       ; null
    dq 0x00CF9A000000FFFF       ; code: base 0, limit 4G, 32-bit, exec/read
    dq 0x00CF92000000FFFF       ; data: base 0, limit 4G, 32-bit, read/write
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

boot_drive db 0
lba        dw 0

times 510-($-$$) db 0
dw 0xAA55
