; boot_floppy.asm
; 1.44 MB floppy boot sector for KoelOS. Unlike boot.asm (which uses the
; INT 13h AH=42h LBA/EDD read meant for hard disks), this loads the kernel with
; classic CHS reads (AH=02h) so it works on real floppy drives and USB-FDD.
; A FAT-style BPB header is included for BIOS/USB-FDD compatibility.
; The paging + long-mode transition mirrors boot.asm verbatim.
[bits 16]
[org 0x7c00]

%ifndef KERNEL_SECTORS
%define KERNEL_SECTORS 110
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
volume_label          db "KOELOS BOOT"
fs_type               db "FAT12   "

; --- BOOTLOADER START ---
start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00          ; Temporary 16-bit stack
    mov [boot_drive], dl    ; BIOS hands us the boot drive in DL (0x00 = A:)

    ; Reset the disk controller before the first read (real-floppy hygiene).
    xor ah, ah
    int 0x13

    ; [1] Load the kernel one CHS sector at a time into KERNEL_LOAD_SEG:0000
    mov word [lba], 1               ; kernel starts at LBA 1 (sector 0 = boot)
    mov ax, KERNEL_LOAD_SEG
    mov es, ax
    mov bx, KERNEL_LOAD_OFF
    mov cx, KERNEL_SECTORS          ; sectors still to read

.load_loop:
    push cx                         ; CHS conversion + read clobber CX
    mov di, 5                       ; retries for this sector

.try_read:
    ; Convert [lba] -> CHS using the BPB geometry.
    mov ax, [lba]
    xor dx, dx
    div word [sectors_per_track]    ; AX = lba/spt, DX = lba%spt
    mov cl, dl
    inc cl                          ; sector = (lba % spt) + 1  (1-based)
    xor dx, dx
    div word [num_heads]            ; AX = cylinder, DX = head
    mov ch, al                      ; cylinder (0-79 fits in 8 bits)
    mov dh, dl                      ; head
    mov dl, [boot_drive]            ; drive

    mov ah, 0x02                    ; read sectors
    mov al, 1                       ; one sector at a time
    int 0x13
    jnc .read_ok

    xor ah, ah                      ; reset controller, then retry
    int 0x13
    dec di
    jnz .try_read
    jmp disk_error

.read_ok:
    pop cx                          ; restore remaining count
    add bx, 512                     ; advance destination
    jnc .no_seg_bump
    mov ax, es                      ; crossed 64KB -> next segment (defensive)
    add ax, 0x1000
    mov es, ax
.no_seg_bump:
    inc word [lba]
    dec cx
    jnz .load_loop

    ; Restore ES=0 before paging: the rep stosd below uses ES:DI, and the CHS
    ; load left ES=KERNEL_LOAD_SEG. Without this it would zero 0x11000 (wiping
    ; the freshly loaded kernel) instead of the page tables at 0x1000.
    xor ax, ax
    mov es, ax

    ; [1b] Verify the CPU supports 64-bit long mode. KoelOS is a 64-bit OS;
    ; on a 32-bit CPU (common on pre-2004 boards) the long-mode switch below
    ; would triple-fault and hang, so fail loudly with a readable message.
    ; (Any Pentium-class CPU has CPUID, so we test the long-mode bit directly.)
    mov eax, 0x80000000          ; extended CPUID leaves present?
    cpuid
    cmp eax, 0x80000001
    jb no_long
    mov eax, 0x80000001          ; long-mode bit = CPUID.80000001h:EDX[29]
    cpuid
    test edx, 0x20000000
    jz no_long

    ; [2] Prepare Paging (The 4GB Identity Map - Ultra Compatible)
    cli

    mov edi, 0x1000
    xor eax, eax
    mov ecx, 6144                ; 6 pages * 1024 dwords per page
    rep stosd

    mov dword [0x1000], 0x2003   ; PML4 -> PDPT
    mov dword [0x2000], 0x3003   ; 0GB - 1GB
    mov dword [0x2008], 0x4003   ; 1GB - 2GB
    mov dword [0x2010], 0x5003   ; 2GB - 3GB
    mov dword [0x2018], 0x6003   ; 3GB - 4GB

    mov edi, 0x3000
    mov ebx, 0x00000083          ; 2MB huge page + Write + Present
    mov ecx, 2048
.map_loop:
    mov [edi], ebx
    add ebx, 0x200000
    add edi, 8
    loop .map_loop

    ; [3] Enable PAE & Long Mode
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    mov edi, 0x1000
    mov cr3, edi

    mov ecx, 0xC0000080          ; EFER MSR
    rdmsr
    or eax, 1 << 8               ; LME
    wrmsr

    mov eax, cr0
    or eax, 1 << 31 | 1 << 0     ; Paging + Protected Mode
    mov cr0, eax

    ; [4] Transition to 64-bit
    lgdt [gdt_descriptor]
    jmp 0x08:init_64

disk_error:
    mov si, msg_disk
    jmp print16_hang

no_long:
    mov si, msg_no64
    ; fall through

; Print ASCIIZ at DS:SI via BIOS teletype (INT 10h), then halt forever.
print16_hang:
    mov bx, 0x0007
.loop:
    lodsb
    test al, al
    jz .hang
    mov ah, 0x0E
    int 0x10
    jmp .loop
.hang:
    hlt
    jmp .hang

msg_disk db "KoelOS: FD read error", 13, 10, 0
msg_no64 db "KoelOS needs a 64-bit CPU", 13, 10, 0

; --- 64-BIT GDT ---
gdt_start:
    dq 0x0000000000000000    ; Null
    dq 0x00209A0000000000    ; Code: Exec/Read, 64-bit
    dq 0x0000920000000000    ; Data: Read/Write
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dq gdt_start

[bits 64]
init_64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    mov rsp, 0x80000
    mov rbp, rsp

    jmp KERNEL_ENTRY

boot_drive db 0
lba        dw 0

times 510-($-$$) db 0
dw 0xAA55
