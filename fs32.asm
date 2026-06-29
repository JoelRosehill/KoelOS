; fs32.asm — KoelOS 32-bit filesystem (ATA PIO + KFS1) and file commands.
; Ported from the 64-bit drivers/fs.asm. The on-disk format already uses 32-bit
; fields, so this is a register/addressing port; r8-r15 are replaced with the
; ata_*/fw_* memory temporaries. Included by kernel32.asm.
; ============================================================================

%define ATA_DATA       0x1F0
%define ATA_SECCOUNT   0x1F2
%define ATA_LBA_LOW    0x1F3
%define ATA_LBA_MID    0x1F4
%define ATA_LBA_HIGH   0x1F5
%define ATA_DRIVE      0x1F6
%define ATA_STATUS     0x1F7
%define ATA_CMD        0x1F7
%define ATA_ALT_STATUS 0x3F6

%define ATA_CMD_READ   0x20
%define ATA_CMD_WRITE  0x30

%define ATA_SR_ERR     0x01
%define ATA_SR_DRQ     0x08
%define ATA_SR_DF      0x20
%define ATA_SR_BSY     0x80

%define FS_MAGIC           0x3153464B
%define FS_VERSION         1
%define FS_START_LBA       2048
%define FS_END_LBA         131072
%define FS_DIR_SECTORS     16
%define FS_MAX_ENTRIES     128
%define FS_ENTRY_SIZE      64
%define FS_NAME_LEN        32
%define FS_ENTRY_SIZE_OFF  32
%define FS_ENTRY_START_OFF 36
%define FS_ENTRY_SECT_OFF  40
%define FS_ENTRY_FLAGS_OFF 44
%define FS_FLAG_USED       1
%define FS_FLAG_BINARY     2
%define FS_DATA_START_LBA  (FS_START_LBA + 1 + FS_DIR_SECTORS)

%define EDIT_CAP 8192

; ----------------------------------------------------------------------------
; Small helpers
; ----------------------------------------------------------------------------
fs_print_line:                     ; ESI = string
    call print_string
    call newline
    ret

fs_memzero:                        ; EDI = dest, ECX = count
    push eax
    push ecx
    push edi
    xor al, al
    rep stosb
    pop edi
    pop ecx
    pop eax
    ret

fs_strlen:                         ; ESI = string -> EAX = length
    push esi
    xor eax, eax
.l:
    cmp byte [esi], 0
    je .d
    inc esi
    inc eax
    jmp .l
.d:
    pop esi
    ret

fs_skip_spaces:                    ; advance ESI past spaces
.l:
    cmp byte [esi], ' '
    jne .d
    inc esi
    jmp .l
.d:
    ret

; ESI = arg string -> EAX = first token ptr, EDX = remainder ptr (0 if none)
fs_split_args:
    call fs_skip_spaces
    mov eax, esi
    cmp byte [esi], 0
    je .none
.nameloop:
    mov cl, [esi]
    test cl, cl
    jz .norest
    cmp cl, ' '
    je .split
    inc esi
    jmp .nameloop
.split:
    mov byte [esi], 0
    inc esi
    call fs_skip_spaces
    mov edx, esi
    ret
.norest:
    xor edx, edx
    ret
.none:
    xor eax, eax
    xor edx, edx
    ret

; ----------------------------------------------------------------------------
; ATA PIO (primary channel, master, LBA28)
; ----------------------------------------------------------------------------
ata_io_delay:
    push eax
    push edx
    mov dx, ATA_ALT_STATUS
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    pop edx
    pop eax
    ret

ata_wait_not_busy:                 ; -> EAX = 1 ready, 0 timeout
    push ecx
    push edx
    mov dx, ATA_STATUS
    mov ecx, 0x100000
.l:
    in al, dx
    test al, ATA_SR_BSY
    jz .ready
    dec ecx
    jnz .l
    xor eax, eax
    jmp .out
.ready:
    mov eax, 1
.out:
    pop edx
    pop ecx
    ret

ata_wait_drq:                      ; -> EAX = 1 data-ready, 0 error/timeout
    push ecx
    push edx
    mov dx, ATA_STATUS
    mov ecx, 0x100000
.l:
    in al, dx
    test al, ATA_SR_BSY
    jnz .next
    test al, ATA_SR_ERR | ATA_SR_DF
    jnz .fail
    test al, ATA_SR_DRQ
    jnz .ready
.next:
    dec ecx
    jnz .l
.fail:
    xor eax, eax
    jmp .out
.ready:
    mov eax, 1
.out:
    pop edx
    pop ecx
    ret

; Select drive/head + program the LBA/sector-count registers for [ata_lba].
ata_setup_lba:
    push eax
    push edx
    mov eax, [ata_lba]
    shr eax, 24
    and al, 0x0F
    or al, 0xE0
    mov dx, ATA_DRIVE
    out dx, al
    call ata_io_delay
    mov dx, ATA_SECCOUNT
    mov al, 1
    out dx, al
    mov eax, [ata_lba]
    mov dx, ATA_LBA_LOW
    out dx, al
    mov eax, [ata_lba]
    shr eax, 8
    mov dx, ATA_LBA_MID
    out dx, al
    mov eax, [ata_lba]
    shr eax, 16
    mov dx, ATA_LBA_HIGH
    out dx, al
    pop edx
    pop eax
    ret

; Input: EAX = start LBA, ECX = sector count, EDI = buffer
; Output: EAX = 1 success, 0 failure
ata_read_sectors:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov [ata_lba], eax
    mov [ata_cnt], ecx
    mov [ata_buf], edi
.next:
    cmp dword [ata_cnt], 0
    je .ok
    call ata_wait_not_busy
    test eax, eax
    jz .fail
    call ata_setup_lba
    mov dx, ATA_CMD
    mov al, ATA_CMD_READ
    out dx, al
    call ata_wait_drq
    test eax, eax
    jz .fail
    mov edi, [ata_buf]
    mov dx, ATA_DATA
    mov ecx, 256
.words:
    in ax, dx
    mov [edi], ax
    add edi, 2
    dec ecx
    jnz .words
    mov [ata_buf], edi
    inc dword [ata_lba]
    dec dword [ata_cnt]
    jmp .next
.ok:
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; Input: EAX = start LBA, ECX = sector count, ESI = buffer
; Output: EAX = 1 success, 0 failure
ata_write_sectors:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov [ata_lba], eax
    mov [ata_cnt], ecx
    mov [ata_buf], esi
.next:
    cmp dword [ata_cnt], 0
    je .ok
    call ata_wait_not_busy
    test eax, eax
    jz .fail
    call ata_setup_lba
    mov dx, ATA_CMD
    mov al, ATA_CMD_WRITE
    out dx, al
    call ata_wait_drq
    test eax, eax
    jz .fail
    mov esi, [ata_buf]
    mov dx, ATA_DATA
    mov ecx, 256
.words:
    mov ax, [esi]
    out dx, ax
    add esi, 2
    dec ecx
    jnz .words
    mov [ata_buf], esi
    call ata_wait_not_busy
    test eax, eax
    jz .fail
    inc dword [ata_lba]
    dec dword [ata_cnt]
    jmp .next
.ok:
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ----------------------------------------------------------------------------
; Directory + volume
; ----------------------------------------------------------------------------
fs_sync_directory:                 ; -> EAX = 1/0
    mov eax, FS_START_LBA + 1
    mov ecx, FS_DIR_SECTORS
    mov esi, fs_dir_buffer
    call ata_write_sectors
    ret

fs_format:                         ; -> EAX = 1/0
    mov edi, fs_dir_buffer
    mov ecx, 8192
    call fs_memzero
    mov edi, fs_sector_buffer
    mov ecx, 512
    call fs_memzero
    mov dword [fs_sector_buffer + 0],  FS_MAGIC
    mov dword [fs_sector_buffer + 4],  FS_VERSION
    mov dword [fs_sector_buffer + 8],  FS_START_LBA
    mov dword [fs_sector_buffer + 12], FS_END_LBA - FS_START_LBA
    mov dword [fs_sector_buffer + 16], FS_DIR_SECTORS
    mov dword [fs_sector_buffer + 20], FS_MAX_ENTRIES
    mov dword [fs_sector_buffer + 24], FS_DATA_START_LBA
    mov eax, FS_START_LBA
    mov ecx, 1
    mov esi, fs_sector_buffer
    call ata_write_sectors
    test eax, eax
    jz .fail
    call fs_sync_directory
    test eax, eax
    jz .fail
    mov byte [fs_ready], 1
    mov eax, 1
    ret
.fail:
    mov esi, msg_fs_disk
    call fs_print_line
    xor eax, eax
    ret

fs_ensure_ready:                   ; -> EAX = 1/0
    cmp byte [fs_ready], 1
    je .ready
    mov eax, FS_START_LBA
    mov ecx, 1
    mov edi, fs_sector_buffer
    call ata_read_sectors
    test eax, eax
    jz .disk
    cmp dword [fs_sector_buffer + 0], FS_MAGIC
    jne .format
    cmp dword [fs_sector_buffer + 4], FS_VERSION
    jne .format
    mov eax, FS_START_LBA + 1
    mov ecx, FS_DIR_SECTORS
    mov edi, fs_dir_buffer
    call ata_read_sectors
    test eax, eax
    jz .disk
    mov byte [fs_ready], 1
.ready:
    mov eax, 1
    ret
.format:
    mov esi, msg_fs_format
    call fs_print_line
    call fs_format
    ret
.disk:
    mov esi, msg_fs_disk
    call fs_print_line
    xor eax, eax
    ret

; ESI vs EDI ASCIIZ -> EAX = 1 if equal
fs_name_equal:
    push esi
    push edi
    push edx
.l:
    mov al, [esi]
    mov dl, [edi]
    cmp al, dl
    jne .no
    test al, al
    jz .yes
    inc esi
    inc edi
    jmp .l
.no:
    xor eax, eax
    jmp .out
.yes:
    mov eax, 1
.out:
    pop edx
    pop edi
    pop esi
    ret

; ESI = name -> EAX = entry ptr or 0
fs_find_entry:
    push ebx
    push ecx
    mov ebx, fs_dir_buffer
    mov ecx, FS_MAX_ENTRIES
.l:
    mov al, [ebx + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_USED
    jz .next
    push esi
    push ecx
    mov edi, ebx
    call fs_name_equal
    pop ecx
    pop esi
    test eax, eax
    jnz .found
.next:
    add ebx, FS_ENTRY_SIZE
    dec ecx
    jnz .l
    xor eax, eax
    jmp .out
.found:
    mov eax, ebx
.out:
    pop ecx
    pop ebx
    ret

; -> EAX = free entry ptr or 0
fs_find_free_entry:
    push ecx
    mov eax, fs_dir_buffer
    mov ecx, FS_MAX_ENTRIES
.l:
    cmp byte [eax + FS_ENTRY_FLAGS_OFF], 0
    je .out
    add eax, FS_ENTRY_SIZE
    dec ecx
    jnz .l
    xor eax, eax
.out:
    pop ecx
    ret

; EDI = entry ptr, ESI = name -> copy up to 31 chars + NUL
fs_copy_name_to_entry:
    push ecx
    mov ecx, FS_NAME_LEN - 1
.l:
    mov al, [esi]
    mov [edi], al
    test al, al
    jz .d
    inc esi
    inc edi
    dec ecx
    jnz .l
    mov byte [edi], 0
.d:
    pop ecx
    ret

; Input: ECX = required sectors, EDX = entry ptr to ignore (0 = none)
; Output: EAX = start LBA or 0     (uses ffr_* memory temps for r8-r12)
fs_find_free_region:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov [ffr_need], ecx
    mov [ffr_ignore], edx
    test ecx, ecx
    jz .fail
    mov dword [ffr_base], FS_DATA_START_LBA
.outer:
    mov dword [ffr_best], 0xFFFFFFFF
    mov dword [ffr_bestlen], 0
    mov ebx, fs_dir_buffer
    mov ecx, FS_MAX_ENTRIES
.scan:
    cmp ebx, [ffr_ignore]
    je .scan_next
    mov al, [ebx + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_USED
    jz .scan_next
    mov eax, [ebx + FS_ENTRY_SECT_OFF]
    test eax, eax
    jz .scan_next
    mov edi, [ebx + FS_ENTRY_START_OFF]
    cmp edi, [ffr_base]
    jb .scan_next
    cmp edi, [ffr_best]
    jae .scan_next
    mov [ffr_best], edi
    mov eax, [ebx + FS_ENTRY_SECT_OFF]
    mov [ffr_bestlen], eax
.scan_next:
    add ebx, FS_ENTRY_SIZE
    dec ecx
    jnz .scan
    cmp dword [ffr_best], 0xFFFFFFFF
    jne .check_gap
    ; no allocation beyond base -> take the tail if it fits
    mov eax, FS_END_LBA
    sub eax, [ffr_base]
    cmp eax, [ffr_need]
    jb .fail
    mov eax, [ffr_base]
    jmp .out
.check_gap:
    mov eax, [ffr_base]
    add eax, [ffr_need]
    cmp eax, [ffr_best]
    jbe .found
    mov eax, [ffr_best]
    add eax, [ffr_bestlen]
    mov [ffr_base], eax
    cmp eax, FS_END_LBA
    jb .outer
.fail:
    xor eax, eax
    jmp .out
.found:
    mov eax, [ffr_base]
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ESI = name -> create empty file. EAX = 1/0
fs_create_empty_file:
    push ebx
    mov [fw_name], esi
    call fs_strlen
    test eax, eax
    jz .badname
    cmp eax, FS_NAME_LEN
    jae .badname
    mov esi, [fw_name]
    call fs_find_entry
    test eax, eax
    jnz .exists
    call fs_find_free_entry
    test eax, eax
    jz .nospace
    mov [fw_entry], eax            ; remember the entry across calls
    mov edi, eax
    mov ecx, FS_ENTRY_SIZE
    call fs_memzero
    mov edi, [fw_entry]
    mov esi, [fw_name]
    call fs_copy_name_to_entry
    mov ebx, [fw_entry]
    mov byte [ebx + FS_ENTRY_FLAGS_OFF], FS_FLAG_USED
    call fs_sync_directory
    test eax, eax
    jz .disk
    mov eax, 1
    jmp .out
.badname:
    mov esi, msg_fs_badname
    call fs_print_line
    xor eax, eax
    jmp .out
.exists:
    mov esi, msg_fs_exists
    call fs_print_line
    xor eax, eax
    jmp .out
.nospace:
    mov esi, msg_fs_nospace
    call fs_print_line
    xor eax, eax
    jmp .out
.disk:
    mov esi, msg_fs_disk
    call fs_print_line
    xor eax, eax
.out:
    pop ebx
    ret

; Input: ESI = name, EDI = data ptr, ECX = data len, AL (in [fw_flags]) extra flags
; Output: EAX = 1/0     (fw_* memory temps replace r12-r15/r8-r11)
fs_write_file:
    push ebx
    mov [fw_name], esi
    mov [fw_data], edi
    mov [fw_len], ecx
    ; (caller sets [fw_flags] before calling)
    mov esi, [fw_name]
    call fs_strlen
    test eax, eax
    jz .badname
    cmp eax, FS_NAME_LEN
    jae .badname
    mov esi, [fw_name]
    call fs_find_entry
    mov [fw_entry], eax
    test eax, eax
    jnz .have
    call fs_find_free_entry
    mov [fw_entry], eax
    test eax, eax
    jz .nospace
.have:
    mov eax, [fw_len]
    add eax, 511
    shr eax, 9
    mov [fw_sects], eax
    mov dword [fw_start], 0
    cmp dword [fw_sects], 0
    je .meta
    mov ecx, [fw_sects]
    mov edx, [fw_entry]
    call fs_find_free_region
    test eax, eax
    jz .nospace
    mov [fw_start], eax
    mov dword [fw_idx], 0
    mov eax, [fw_data]
    mov [fw_src], eax
    mov eax, [fw_len]
    mov [fw_rem], eax
.wloop:
    mov edi, fs_sector_buffer
    mov ecx, 512
    call fs_memzero
    mov ecx, [fw_rem]
    cmp ecx, 512
    jbe .chunk
    mov ecx, 512
.chunk:
    test ecx, ecx
    jz .flush
    mov edi, fs_sector_buffer
    mov esi, [fw_src]
    push ecx
    rep movsb
    pop ecx
    add [fw_src], ecx
.flush:
    mov eax, [fw_start]
    add eax, [fw_idx]
    mov ecx, 1
    mov esi, fs_sector_buffer
    call ata_write_sectors
    test eax, eax
    jz .disk
    mov eax, [fw_rem]
    cmp eax, 512
    jbe .rem0
    sub eax, 512
    mov [fw_rem], eax
    jmp .more
.rem0:
    mov dword [fw_rem], 0
.more:
    inc dword [fw_idx]
    mov eax, [fw_idx]
    cmp eax, [fw_sects]
    jl .wloop
.meta:
    mov edi, [fw_entry]
    mov ecx, FS_ENTRY_SIZE
    push edi
    call fs_memzero
    pop edi
    mov esi, [fw_name]
    call fs_copy_name_to_entry
    mov ebx, [fw_entry]
    mov eax, [fw_len]
    mov [ebx + FS_ENTRY_SIZE_OFF], eax
    mov eax, [fw_start]
    mov [ebx + FS_ENTRY_START_OFF], eax
    mov eax, [fw_sects]
    mov [ebx + FS_ENTRY_SECT_OFF], eax
    mov al, FS_FLAG_USED
    or al, [fw_flags]
    mov [ebx + FS_ENTRY_FLAGS_OFF], al
    call fs_sync_directory
    test eax, eax
    jz .disk
    mov eax, 1
    jmp .out
.badname:
    mov esi, msg_fs_badname
    call fs_print_line
    xor eax, eax
    jmp .out
.nospace:
    mov esi, msg_fs_nospace
    call fs_print_line
    xor eax, eax
    jmp .out
.disk:
    mov esi, msg_fs_disk
    call fs_print_line
    xor eax, eax
.out:
    pop ebx
    ret

; Input: ESI = entry ptr, EDI = dest buffer -> EAX = bytes read (0 on fail)
fs_read_entry:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov eax, [esi + FS_ENTRY_SIZE_OFF]
    mov [fr_rem], eax
    mov [fr_len], eax
    mov eax, [esi + FS_ENTRY_START_OFF]
    mov [fr_lba], eax
    mov [fr_dst], edi
    cmp dword [fr_rem], 0
    je .done
.loop:
    mov eax, [fr_lba]
    mov ecx, 1
    mov edi, fs_sector_buffer
    call ata_read_sectors
    test eax, eax
    jz .fail
    mov ecx, [fr_rem]
    cmp ecx, 512
    jbe .chunk
    mov ecx, 512
.chunk:
    mov esi, fs_sector_buffer
    mov edi, [fr_dst]
    push ecx
    rep movsb
    pop ecx
    add [fr_dst], ecx
    inc dword [fr_lba]
    mov eax, [fr_rem]
    cmp eax, 512
    jbe .done
    sub eax, 512
    mov [fr_rem], eax
    jmp .loop
.done:
    mov eax, [fr_len]
    jmp .out
.fail:
    xor eax, eax
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; Input: ESI = source entry ptr, EDI = dest name -> EAX = 1/0
fs_copy_entry:
    push ebx
    mov [fc_src], esi
    mov [fc_name], edi
    mov esi, edi
    call fs_strlen
    test eax, eax
    jz .badname
    cmp eax, FS_NAME_LEN
    jae .badname
    mov esi, [fc_name]
    call fs_find_entry
    mov [fc_dst], eax
    test eax, eax
    jnz .have
    call fs_find_free_entry
    mov [fc_dst], eax
    test eax, eax
    jz .nospace
.have:
    mov ebx, [fc_src]
    mov eax, [ebx + FS_ENTRY_SIZE_OFF]
    mov [fc_len], eax
    add eax, 511
    shr eax, 9
    mov [fc_sects], eax
    mov dword [fc_start], 0
    cmp dword [fc_sects], 0
    je .meta
    mov ecx, [fc_sects]
    mov edx, [fc_dst]
    call fs_find_free_region
    test eax, eax
    jz .nospace
    mov [fc_start], eax
    mov ebx, [fc_src]
    mov eax, [ebx + FS_ENTRY_START_OFF]
    mov [fc_srclba], eax
    mov dword [fc_idx], 0
.cloop:
    mov eax, [fc_srclba]
    add eax, [fc_idx]
    mov ecx, 1
    mov edi, fs_sector_buffer
    call ata_read_sectors
    test eax, eax
    jz .disk
    mov eax, [fc_start]
    add eax, [fc_idx]
    mov ecx, 1
    mov esi, fs_sector_buffer
    call ata_write_sectors
    test eax, eax
    jz .disk
    inc dword [fc_idx]
    mov eax, [fc_idx]
    cmp eax, [fc_sects]
    jl .cloop
.meta:
    mov edi, [fc_dst]
    mov ecx, FS_ENTRY_SIZE
    push edi
    call fs_memzero
    pop edi
    mov esi, [fc_name]
    call fs_copy_name_to_entry
    mov ebx, [fc_dst]
    mov eax, [fc_len]
    mov [ebx + FS_ENTRY_SIZE_OFF], eax
    mov eax, [fc_start]
    mov [ebx + FS_ENTRY_START_OFF], eax
    mov eax, [fc_sects]
    mov [ebx + FS_ENTRY_SECT_OFF], eax
    mov esi, [fc_src]
    mov al, [esi + FS_ENTRY_FLAGS_OFF]
    and al, FS_FLAG_BINARY
    or al, FS_FLAG_USED
    mov [ebx + FS_ENTRY_FLAGS_OFF], al
    call fs_sync_directory
    test eax, eax
    jz .disk
    mov eax, 1
    jmp .out
.badname:
    mov esi, msg_fs_badname
    call fs_print_line
    xor eax, eax
    jmp .out
.nospace:
    mov esi, msg_fs_nospace
    call fs_print_line
    xor eax, eax
    jmp .out
.disk:
    mov esi, msg_fs_disk
    call fs_print_line
    xor eax, eax
.out:
    pop ebx
    ret

; ESI = name -> delete. EAX = 1/0
fs_delete_file:
    push ebx
    mov ebx, esi
    call fs_strlen
    test eax, eax
    jz .badname
    mov esi, ebx
    call fs_find_entry
    test eax, eax
    jz .notfound
    mov edi, eax
    mov ecx, FS_ENTRY_SIZE
    call fs_memzero
    call fs_sync_directory
    test eax, eax
    jz .disk
    mov eax, 1
    jmp .out
.badname:
    mov esi, msg_fs_badname
    call fs_print_line
    xor eax, eax
    jmp .out
.notfound:
    mov esi, msg_fs_notfound
    call fs_print_line
    xor eax, eax
    jmp .out
.disk:
    mov esi, msg_fs_disk
    call fs_print_line
    xor eax, eax
.out:
    pop ebx
    ret

fs_list_files:
    push ebx
    push ecx
    push edx
    mov ebx, fs_dir_buffer
    mov ecx, FS_MAX_ENTRIES
    xor edx, edx                   ; count shown
.l:
    mov al, [ebx + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_USED
    jz .next
    mov esi, ebx
    call print_string
    mov esi, msg_fs_gap
    call print_string
    mov al, [ebx + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_BINARY
    jz .txt
    mov esi, msg_fs_bin
    jmp .ptype
.txt:
    mov esi, msg_fs_txt
.ptype:
    call print_string
    mov esi, msg_fs_gap
    call print_string
    push ecx
    push edx
    mov eax, [ebx + FS_ENTRY_SIZE_OFF]
    call print_dec
    pop edx
    pop ecx
    mov esi, msg_fs_bytes
    call print_string
    call newline
    inc edx
.next:
    add ebx, FS_ENTRY_SIZE
    dec ecx
    jnz .l
    test edx, edx
    jnz .out
    mov esi, msg_fs_nofiles
    call fs_print_line
.out:
    pop edx
    pop ecx
    pop ebx
    ret

; ESI = entry ptr -> print as text
fs_print_text_file:
    push ebx
    mov al, [esi + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_BINARY
    jz .start
    mov esi, msg_fs_binhint
    call fs_print_line
    jmp .out
.start:
    mov eax, [esi + FS_ENTRY_SIZE_OFF]
    mov [pt_rem], eax
    mov eax, [esi + FS_ENTRY_START_OFF]
    mov [pt_lba], eax
    cmp dword [pt_rem], 0
    je .finish
.sloop:
    mov eax, [pt_lba]
    mov ecx, 1
    mov edi, fs_sector_buffer
    call ata_read_sectors
    test eax, eax
    jz .disk
    mov ecx, [pt_rem]
    cmp ecx, 512
    jbe .chunk
    mov ecx, 512
.chunk:
    mov ebx, fs_sector_buffer
.byteloop:
    mov al, [ebx]
    cmp al, 10
    je .nl
    cmp al, 13
    je .skip
    cmp al, 9
    je .tab
    cmp al, 32
    jb .skip
    call print_char
    jmp .skip
.tab:
    mov al, ' '
    call print_char
    jmp .skip
.nl:
    call newline
.skip:
    inc ebx
    dec ecx
    jnz .byteloop
    inc dword [pt_lba]
    mov eax, [pt_rem]
    cmp eax, 512
    jbe .finish
    sub eax, 512
    mov [pt_rem], eax
    jmp .sloop
.finish:
    call newline
    jmp .out
.disk:
    mov esi, msg_fs_disk
    call fs_print_line
.out:
    pop ebx
    ret

; ESI = entry ptr -> hex dump
fs_print_hex_file:
    push ebx
    mov eax, [esi + FS_ENTRY_SIZE_OFF]
    mov [pt_rem], eax
    mov eax, [esi + FS_ENTRY_START_OFF]
    mov [pt_lba], eax
    mov dword [pt_col], 0
    cmp dword [pt_rem], 0
    je .done
.sloop:
    mov eax, [pt_lba]
    mov ecx, 1
    mov edi, fs_sector_buffer
    call ata_read_sectors
    test eax, eax
    jz .disk
    mov ecx, [pt_rem]
    cmp ecx, 512
    jbe .chunk
    mov ecx, 512
.chunk:
    mov ebx, fs_sector_buffer
.byteloop:
    mov al, [ebx]
    call print_hex_byte
    mov al, ' '
    call print_char
    inc dword [pt_col]
    cmp dword [pt_col], 16
    jne .skip
    mov dword [pt_col], 0
    call newline
.skip:
    inc ebx
    dec ecx
    jnz .byteloop
    inc dword [pt_lba]
    mov eax, [pt_rem]
    cmp eax, 512
    jbe .done
    sub eax, 512
    mov [pt_rem], eax
    jmp .sloop
.done:
    cmp dword [pt_col], 0
    je .out
    call newline
    jmp .out
.disk:
    mov esi, msg_fs_disk
    call fs_print_line
.out:
    pop ebx
    ret

; AL = byte -> print two hex digits
print_hex_byte:
    push eax
    push ebx
    mov bl, al
    shr al, 4
    call .nyb
    mov al, bl
    and al, 0x0F
    call .nyb
    pop ebx
    pop eax
    ret
.nyb:
    and al, 0x0F
    cmp al, 10
    jb .dig
    add al, 'A' - 10
    call print_char
    ret
.dig:
    add al, '0'
    call print_char
    ret

fs_hex_value:                      ; AL = char -> AL = 0..15 or 0xFF
    cmp al, '0'
    jb .bad
    cmp al, '9'
    jbe .dig
    cmp al, 'A'
    jb .bad
    cmp al, 'F'
    jbe .up
    cmp al, 'a'
    jb .bad
    cmp al, 'f'
    ja .bad
    sub al, 'a' - 10
    ret
.up:
    sub al, 'A' - 10
    ret
.dig:
    sub al, '0'
    ret
.bad:
    mov al, 0xFF
    ret

; ESI = hex string -> writes bytes to fs_parse_buffer; EAX=1/0, ECX=byte count
fs_parse_hex_input:
    push ebx
    push edx
    mov edi, fs_parse_buffer
    xor ecx, ecx
    xor edx, edx                   ; have-high-nibble flag
    xor ebx, ebx                   ; high nibble
.l:
    mov al, [esi]
    test al, al
    jz .done
    cmp al, ' '
    je .nextc
    call fs_hex_value
    cmp al, 0xFF
    je .fail
    test dl, dl
    jnz .low
    mov bl, al
    mov dl, 1
    jmp .nextc
.low:
    cmp ecx, 256
    jae .fail
    shl bl, 4
    or bl, al
    mov [edi], bl
    inc edi
    inc ecx
    xor dl, dl
.nextc:
    inc esi
    jmp .l
.done:
    test dl, dl
    jnz .fail
    mov eax, 1
    jmp .out
.fail:
    mov esi, msg_fs_badhex
    call fs_print_line
    xor eax, eax
.out:
    pop edx
    pop ebx
    ret

; ----------------------------------------------------------------------------
; File commands
; ----------------------------------------------------------------------------
do_ls:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    call fs_list_files
    jmp command_done

do_mkfile:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    mov esi, [arg_ptr]
    call fs_split_args
    test eax, eax
    jz .usage
    mov esi, eax
    call fs_create_empty_file
    test eax, eax
    jz command_done
    mov esi, msg_fs_created
    call fs_print_line
    jmp command_done
.usage:
    mov esi, msg_mkfile_usage
    call fs_print_line
    jmp command_done

do_cat:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    mov esi, [arg_ptr]
    call fs_split_args
    test eax, eax
    jz .usage
    mov esi, eax
    call fs_find_entry
    test eax, eax
    jz .notfound
    mov esi, eax
    call fs_print_text_file
    jmp command_done
.usage:
    mov esi, msg_cat_usage
    call fs_print_line
    jmp command_done
.notfound:
    mov esi, msg_fs_notfound
    call fs_print_line
    jmp command_done

do_hex:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    mov esi, [arg_ptr]
    call fs_split_args
    test eax, eax
    jz .usage
    mov esi, eax
    call fs_find_entry
    test eax, eax
    jz .notfound
    mov esi, eax
    call fs_print_hex_file
    jmp command_done
.usage:
    mov esi, msg_hex_usage
    call fs_print_line
    jmp command_done
.notfound:
    mov esi, msg_fs_notfound
    call fs_print_line
    jmp command_done

do_rm:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    mov esi, [arg_ptr]
    call fs_split_args
    test eax, eax
    jz .usage
    mov esi, eax
    call fs_delete_file
    test eax, eax
    jz command_done
    mov esi, msg_fs_deleted
    call fs_print_line
    jmp command_done
.usage:
    mov esi, msg_rm_usage
    call fs_print_line
    jmp command_done

do_format:
    mov esi, msg_format_warn
    call fs_print_line
    call fs_format
    test eax, eax
    jz command_done
    mov esi, msg_format_done
    call fs_print_line
    jmp command_done

do_binwrite:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    mov esi, [arg_ptr]
    call fs_split_args             ; EAX = name, EDX = hex remainder
    test eax, eax
    jz .usage
    mov [fc_name], eax             ; reuse fc_name as scratch for the name ptr
    test edx, edx
    jz .empty
    mov esi, edx
    call fs_parse_hex_input
    test eax, eax
    jz command_done
    mov esi, [fc_name]
    mov edi, fs_parse_buffer
    mov byte [fw_flags], FS_FLAG_BINARY
    call fs_write_file
    test eax, eax
    jz command_done
    mov esi, msg_fs_saved
    call fs_print_line
    jmp command_done
.empty:
    mov esi, [fc_name]
    xor edi, edi
    xor ecx, ecx
    mov byte [fw_flags], FS_FLAG_BINARY
    call fs_write_file
    test eax, eax
    jz command_done
    mov esi, msg_fs_saved
    call fs_print_line
    jmp command_done
.usage:
    mov esi, msg_binwrite_usage
    call fs_print_line
    jmp command_done

do_cp:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    mov esi, [arg_ptr]
    call fs_split_args             ; EAX = src, EDX = rest
    test eax, eax
    jz .usage
    test edx, edx
    jz .usage
    mov [fc_name], eax             ; stash src name
    mov esi, edx
    call fs_split_args             ; EAX = dst name
    test eax, eax
    jz .usage
    mov [cp_dst], eax
    mov esi, [fc_name]
    call fs_find_entry
    test eax, eax
    jz .notfound
    mov esi, eax
    mov edi, [cp_dst]
    call fs_copy_entry
    test eax, eax
    jz command_done
    mov esi, msg_cp_done
    call fs_print_line
    jmp command_done
.usage:
    mov esi, msg_cp_usage
    call fs_print_line
    jmp command_done
.notfound:
    mov esi, msg_fs_notfound
    call fs_print_line
    jmp command_done

do_mv:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    mov esi, [arg_ptr]
    call fs_split_args             ; EAX = old, EDX = rest
    test eax, eax
    jz .usage
    test edx, edx
    jz .usage
    mov [fc_name], eax             ; old name
    mov esi, edx
    call fs_split_args             ; EAX = new name
    test eax, eax
    jz .usage
    mov [cp_dst], eax              ; new name
    mov esi, eax
    call fs_find_entry
    test eax, eax
    jnz .exists
    mov esi, [fc_name]
    call fs_find_entry
    test eax, eax
    jz .notfound
    mov ebx, eax
    mov esi, [cp_dst]
    call fs_strlen
    test eax, eax
    jz .badname
    cmp eax, FS_NAME_LEN
    jae .badname
    mov edi, ebx
    mov ecx, FS_NAME_LEN
    call fs_memzero
    mov edi, ebx
    mov esi, [cp_dst]
    call fs_copy_name_to_entry
    call fs_sync_directory
    test eax, eax
    jz .disk
    mov esi, msg_mv_done
    call fs_print_line
    jmp command_done
.usage:
    mov esi, msg_mv_usage
    call fs_print_line
    jmp command_done
.exists:
    mov esi, msg_fs_exists
    call fs_print_line
    jmp command_done
.notfound:
    mov esi, msg_fs_notfound
    call fs_print_line
    jmp command_done
.badname:
    mov esi, msg_fs_badname
    call fs_print_line
    jmp command_done
.disk:
    mov esi, msg_fs_disk
    call fs_print_line
    jmp command_done

; ----------------------------------------------------------------------------
; Line editor: edit <name>  (:w save  :q quit  :wq save+quit  :l list  :d del)
; ----------------------------------------------------------------------------
do_edit:
    call fs_ensure_ready
    test eax, eax
    jz command_done
    mov esi, [arg_ptr]
    call fs_split_args
    test eax, eax
    jz .usage
    mov esi, eax
    call edit_copy_name
    call edit_load

    mov esi, msg_edit_editing
    call print_string
    mov esi, edit_name
    call print_string
    call newline
    mov esi, msg_edit_banner
    call fs_print_line
.loop:
    mov esi, msg_edit_prompt
    call print_string
    call edit_read_line
    mov esi, edit_line
    cmp byte [esi], ':'
    jne .text
    mov edi, ed_cmd_wq
    call strcmp
    test eax, eax
    jnz .savequit
    mov esi, edit_line
    mov edi, ed_cmd_w
    call strcmp
    test eax, eax
    jnz .save
    mov esi, edit_line
    mov edi, ed_cmd_q
    call strcmp
    test eax, eax
    jnz command_done
    mov esi, edit_line
    mov edi, ed_cmd_l
    call strcmp
    test eax, eax
    jnz .list
    mov esi, edit_line
    mov edi, ed_cmd_d
    call strcmp
    test eax, eax
    jnz .del
    mov esi, msg_edit_unknown
    call fs_print_line
    jmp .loop
.text:
    call edit_append_line
    jmp .loop
.save:
    call edit_save
    test eax, eax
    jz .loop
    mov esi, msg_fs_saved
    call fs_print_line
    jmp .loop
.savequit:
    call edit_save
    test eax, eax
    jz .loop
    mov esi, msg_fs_saved
    call fs_print_line
    jmp command_done
.list:
    call edit_list
    jmp .loop
.del:
    call edit_del_last
    jmp .loop
.usage:
    mov esi, msg_edit_usage
    call fs_print_line
    jmp command_done

edit_copy_name:                    ; ESI = name -> edit_name (max 31)
    push ecx
    push edi
    mov edi, edit_name
    mov ecx, 31
.l:
    mov al, [esi]
    mov [edi], al
    test al, al
    jz .d
    inc esi
    inc edi
    dec ecx
    jnz .l
    mov byte [edi], 0
.d:
    pop edi
    pop ecx
    ret

edit_load:
    mov dword [edit_total], 0
    mov esi, edit_name
    call fs_find_entry
    test eax, eax
    jz .done
    mov dl, [eax + FS_ENTRY_FLAGS_OFF]
    test dl, FS_FLAG_BINARY
    jnz .done
    mov esi, eax
    mov edi, edit_text
    call fs_read_entry
    cmp eax, EDIT_CAP
    jbe .store
    mov eax, EDIT_CAP
.store:
    mov [edit_total], eax
.done:
    ret

edit_read_line:                    ; reads into edit_line, echoes
    mov dword [edit_len], 0
.loop:
    in al, 0x64
    test al, 1
    jz .loop
    in al, 0x60
    cmp al, 0x1C
    je .enter
    cmp al, 0x0E
    je .bs
    call kbd_translate
    test al, al
    jz .loop
    mov ecx, [edit_len]
    cmp ecx, 255
    jge .loop
    mov [edit_line + ecx], al
    inc dword [edit_len]
    call print_char
    jmp .loop
.bs:
    cmp dword [edit_len], 0
    je .loop
    dec dword [edit_len]
    mov ecx, [edit_len]
    mov byte [edit_line + ecx], 0
    call do_backspace
    jmp .loop
.enter:
    mov ecx, [edit_len]
    mov byte [edit_line + ecx], 0
    call newline
    ret

edit_append_line:
    mov edi, edit_text
    add edi, [edit_total]
    mov esi, edit_line
.l:
    mov al, [esi]
    test al, al
    jz .nl
    mov ecx, [edit_total]
    cmp ecx, EDIT_CAP - 2
    jae .full
    mov [edi], al
    inc edi
    inc esi
    inc dword [edit_total]
    jmp .l
.nl:
    mov ecx, [edit_total]
    cmp ecx, EDIT_CAP - 1
    jae .full
    mov byte [edi], 10
    inc dword [edit_total]
.full:
    ret

edit_list:
    push ebx
    push ecx
    mov ebx, edit_text
    mov ecx, [edit_total]
    test ecx, ecx
    jz .done
.l:
    mov al, [ebx]
    cmp al, 10
    je .nl
    push ecx
    call print_char
    pop ecx
    jmp .next
.nl:
    push ecx
    call newline
    pop ecx
.next:
    inc ebx
    dec ecx
    jnz .l
.done:
    pop ecx
    pop ebx
    ret

edit_save:
    mov esi, edit_name
    mov edi, edit_text
    mov ecx, [edit_total]
    mov byte [fw_flags], 0
    call fs_write_file
    ret

edit_del_last:
    push ebx
    push ecx
    mov ecx, [edit_total]
    test ecx, ecx
    jz .done
    dec ecx
.scan:
    test ecx, ecx
    jz .zero
    dec ecx
    mov ebx, edit_text
    mov al, [ebx + ecx]
    cmp al, 10
    jne .scan
    inc ecx
    mov [edit_total], ecx
    jmp .done
.zero:
    mov dword [edit_total], 0
.done:
    pop ecx
    pop ebx
    ret

; ----------------------------------------------------------------------------
; FS data + buffers (kept below 1 MB inside the kernel image, no A20 needed)
; ----------------------------------------------------------------------------
fs_ready  db 0

; ATA loop temporaries
ata_lba   dd 0
ata_cnt   dd 0
ata_buf   dd 0

; find-free-region temporaries
ffr_need    dd 0
ffr_ignore  dd 0
ffr_base    dd 0
ffr_best    dd 0
ffr_bestlen dd 0

; write-file temporaries
fw_name  dd 0
fw_data  dd 0
fw_len   dd 0
fw_flags db 0
fw_entry dd 0
fw_sects dd 0
fw_start dd 0
fw_idx   dd 0
fw_src   dd 0
fw_rem   dd 0

; read-entry temporaries
fr_rem dd 0
fr_len dd 0
fr_lba dd 0
fr_dst dd 0

; copy-entry temporaries
fc_src    dd 0
fc_name   dd 0
fc_dst    dd 0
fc_len    dd 0
fc_sects  dd 0
fc_start  dd 0
fc_srclba dd 0
fc_idx    dd 0
cp_dst    dd 0

; print-text/hex temporaries
pt_rem dd 0
pt_lba dd 0
pt_col dd 0

; editor state
edit_name  times 32  db 0
edit_line  times 256 db 0
edit_len   dd 0
edit_total dd 0

msg_fs_format   db "[FS] Formatting storage...", 0
msg_fs_disk     db "[FS] Storage I/O error.", 0
msg_fs_badname  db "[FS] Invalid file name.", 0
msg_fs_exists   db "[FS] File already exists.", 0
msg_fs_notfound db "[FS] File not found.", 0
msg_fs_nospace  db "[FS] Not enough storage space.", 0
msg_fs_badhex   db "[FS] Invalid hex data.", 0
msg_fs_binhint  db "[FS] File is binary. Use hex.", 0
msg_fs_nofiles  db "[FS] No files.", 0
msg_fs_created  db "[FS] File created.", 0
msg_fs_saved    db "[FS] File saved.", 0
msg_fs_deleted  db "[FS] File deleted.", 0
msg_fs_txt      db "[TXT]", 0
msg_fs_bin      db "[BIN]", 0
msg_fs_bytes    db " bytes", 0
msg_fs_gap      db "  ", 0

msg_mkfile_usage   db "Usage: mkfile <name>", 0
msg_cat_usage      db "Usage: cat <name>", 0
msg_hex_usage      db "Usage: hex <name>", 0
msg_rm_usage       db "Usage: rm <name>", 0
msg_binwrite_usage db "Usage: binwrite <name> <hex bytes>", 0
msg_cp_usage       db "Usage: cp <src> <dest>", 0
msg_cp_done        db "[FS] File copied.", 0
msg_mv_usage       db "Usage: mv <old> <new>", 0
msg_mv_done        db "[FS] File renamed.", 0
msg_format_warn    db "[FS] Reformatting storage (erases all files)...", 0
msg_format_done    db "[FS] Storage formatted.", 0

msg_edit_editing db "editing ", 0
msg_edit_banner  db ":w save  :q quit  :wq save+quit  :l list  :d delline", 0
msg_edit_prompt  db "ed> ", 0
msg_edit_unknown db "[ed] unknown command", 0
msg_edit_usage   db "Usage: edit <name>", 0
ed_cmd_w  db ":w", 0
ed_cmd_q  db ":q", 0
ed_cmd_wq db ":wq", 0
ed_cmd_l  db ":l", 0
ed_cmd_d  db ":d", 0

fs_sector_buffer times 512  db 0
fs_parse_buffer  times 256  db 0
edit_text        times 8192 db 0
fs_dir_buffer    times 8192 db 0
