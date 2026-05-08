[bits 16]
[org 0x7c00]

%ifndef KERNEL_SECTORS
%define KERNEL_SECTORS 63
%endif

%define KERNEL_LOAD_SEG 0x1000
%define KERNEL_LOAD_OFF 0x0000
%define KERNEL_ENTRY    0x10000

; --- BOOTLOADER START ---
start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00          ; Temporary 16-bit stack
    mov [boot_drive], dl

    ; [1] Load Kernel from Disk
    mov si, disk_address_packet
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc disk_error           

    ; [2] Prepare Paging (The 4GB Identity Map - Ultra Compatible)
    cli
    
    ; Clear 6 pages of memory (0x1000 to 0x7000) for tables
    ; PML4(1) + PDPT(1) + PD(4) = 6 pages
    mov edi, 0x1000
    xor eax, eax
    mov ecx, 6144                ; 6 pages * 1024 dwords per page
    rep stosd               
    
    ; PML4 (Level 4) -> Points to PDPT at 0x2000
    mov dword [0x1000], 0x2003   ; Present + Write
    
    ; PDPT (Level 3) -> Point to 4 Page Directories (to cover 4GB)
    mov dword [0x2000], 0x3003   ; 0GB - 1GB
    mov dword [0x2008], 0x4003   ; 1GB - 2GB
    mov dword [0x2010], 0x5003   ; 2GB - 3GB
    mov dword [0x2018], 0x6003   ; 3GB - 4GB

    ; PDs (Level 2) -> Map 2048 entries of 2MB each (Total 4GB)
    mov edi, 0x3000              ; Start of first PD
    mov ebx, 0x00000083          ; Bit 7 (Huge Page 2MB) + Write + Present
    mov ecx, 2048                ; 4 tables * 512 entries = 2048

.map_loop:
    mov [edi], ebx
    add ebx, 0x200000            ; Advance physical address by 2MB
    add edi, 8                   ; Advance table entry by 8 bytes
    loop .map_loop

    ; [3] Enable PAE & Long Mode
    mov eax, cr4
    or eax, 1 << 5               ; Set Physical Address Extension bit
    mov cr4, eax

    mov edi, 0x1000
    mov cr3, edi                 ; Load PML4 address into CR3

    mov ecx, 0xC0000080          ; EFER MSR
    rdmsr
    or eax, 1 << 8               ; LME (Long Mode Enable)
    wrmsr

    mov eax, cr0
    or eax, 1 << 31 | 1 << 0     ; Paging + Protected Mode
    mov cr0, eax

    ; [4] Transition to 64-bit
    lgdt [gdt_descriptor]
    jmp 0x08:init_64

disk_error:
    jmp $

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
    ; Setup Data Segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; Setup 64-bit Stack
    ; Moving it to 0x80000 (512KB mark) to avoid collision
    mov rsp, 0x80000
    mov rbp, rsp

    ; Jump to Kernel entry point
    jmp KERNEL_ENTRY

boot_drive db 0

disk_address_packet:
    db 0x10, 0x00
    dw KERNEL_SECTORS
    dw KERNEL_LOAD_OFF
    dw KERNEL_LOAD_SEG
    dq 1

times 510-($-$$) db 0
dw 0xAA55
