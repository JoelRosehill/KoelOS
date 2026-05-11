; ==============================================================================
; KoelOS Storage + Filesystem Driver
; ==============================================================================

%define ATA_DATA_PORT      0x1F0
%define ATA_SECTOR_COUNT   0x1F2
%define ATA_LBA_LOW        0x1F3
%define ATA_LBA_MID        0x1F4
%define ATA_LBA_HIGH       0x1F5
%define ATA_DRIVE_HEAD     0x1F6
%define ATA_STATUS_PORT    0x1F7
%define ATA_COMMAND_PORT   0x1F7
%define ATA_ALT_STATUS     0x3F6

%define ATA_CMD_READ       0x20
%define ATA_CMD_WRITE      0x30
%define ATA_CMD_FLUSH      0xE7

%define ATA_SR_ERR         0x01
%define ATA_SR_DRQ         0x08
%define ATA_SR_DF          0x20
%define ATA_SR_BSY         0x80

%define FS_MAGIC           0x3153464B    ; "KFS1"
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

fs_print_line:
    call print_string
    call newline
    ret

fs_memzero:
    push rax
    xor eax, eax
    rep stosb
    pop rax
    ret

fs_string_length:
    xor eax, eax
.len_loop:
    cmp byte [rsi + rax], 0
    je .done
    inc eax
    jmp .len_loop
.done:
    ret

fs_skip_spaces:
.skip_loop:
    cmp byte [rsi], ' '
    jne .done
    inc rsi
    jmp .skip_loop
.done:
    ret

; Input: RSI = arg string
; Output: RAX = filename ptr, RDX = remainder ptr or 0
fs_split_args:
    call fs_skip_spaces
    mov rax, rsi
    cmp byte [rsi], 0
    je .none

.name_loop:
    mov cl, [rsi]
    test cl, cl
    jz .no_rest
    cmp cl, ' '
    je .split
    inc rsi
    jmp .name_loop

.split:
    mov byte [rsi], 0
    inc rsi
    call fs_skip_spaces
    mov rdx, rsi
    ret

.no_rest:
    xor rdx, rdx
    ret

.none:
    xor rax, rax
    xor rdx, rdx
    ret

ata_io_delay:
    push rax
    push rdx
    mov dx, ATA_ALT_STATUS
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    pop rdx
    pop rax
    ret

ata_wait_not_busy:
    push rcx
    push rdx
    mov dx, ATA_STATUS_PORT
    mov ecx, 0x100000
.busy_loop:
    in al, dx
    test al, ATA_SR_BSY
    jz .ready
    loop .busy_loop
    xor eax, eax
    jmp .done
.ready:
    mov eax, 1
.done:
    pop rdx
    pop rcx
    ret

ata_wait_drq:
    push rcx
    push rdx
    mov dx, ATA_STATUS_PORT
    mov ecx, 0x100000
.drq_loop:
    in al, dx
    test al, ATA_SR_BSY
    jnz .next
    test al, ATA_SR_ERR | ATA_SR_DF
    jnz .fail
    test al, ATA_SR_DRQ
    jnz .ready
.next:
    loop .drq_loop
.fail:
    xor eax, eax
    jmp .done
.ready:
    mov eax, 1
.done:
    pop rdx
    pop rcx
    ret

; Input: EAX = start LBA, ECX = sector count, RDI = buffer
; Output: RAX = 1 on success, 0 on failure
ata_read_sectors:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10

    mov r8d, eax
    mov r9d, ecx
    mov r10, rdi

.read_loop:
    test r9d, r9d
    jz .success

    call ata_wait_not_busy
    test rax, rax
    jz .fail

    mov ebx, r8d
    shr ebx, 24
    and bl, 0x0F
    mov dx, ATA_DRIVE_HEAD
    mov al, 0xE0
    or al, bl
    out dx, al
    call ata_io_delay

    mov dx, ATA_SECTOR_COUNT
    mov al, 1
    out dx, al

    mov ebx, r8d
    mov dx, ATA_LBA_LOW
    mov al, bl
    out dx, al

    mov eax, r8d
    shr eax, 8
    mov dx, ATA_LBA_MID
    out dx, al

    mov eax, r8d
    shr eax, 16
    mov dx, ATA_LBA_HIGH
    out dx, al

    mov dx, ATA_COMMAND_PORT
    mov al, ATA_CMD_READ
    out dx, al

    call ata_wait_drq
    test rax, rax
    jz .fail

    mov dx, ATA_DATA_PORT
    mov ecx, 256
.read_words:
    in ax, dx
    mov [r10], ax
    add r10, 2
    loop .read_words

    inc r8d
    dec r9d
    jmp .read_loop

.success:
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax

.done:
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; Input: EAX = start LBA, ECX = sector count, RDI = buffer
; Output: RAX = 1 on success, 0 on failure
ata_write_sectors:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10

    mov r8d, eax
    mov r9d, ecx
    mov r10, rdi

.write_loop:
    test r9d, r9d
    jz .success

    call ata_wait_not_busy
    test rax, rax
    jz .fail

    mov ebx, r8d
    shr ebx, 24
    and bl, 0x0F
    mov dx, ATA_DRIVE_HEAD
    mov al, 0xE0
    or al, bl
    out dx, al
    call ata_io_delay

    mov dx, ATA_SECTOR_COUNT
    mov al, 1
    out dx, al

    mov ebx, r8d
    mov dx, ATA_LBA_LOW
    mov al, bl
    out dx, al

    mov eax, r8d
    shr eax, 8
    mov dx, ATA_LBA_MID
    out dx, al

    mov eax, r8d
    shr eax, 16
    mov dx, ATA_LBA_HIGH
    out dx, al

    mov dx, ATA_COMMAND_PORT
    mov al, ATA_CMD_WRITE
    out dx, al

    call ata_wait_drq
    test rax, rax
    jz .fail

    mov dx, ATA_DATA_PORT
    mov ecx, 256
.write_words:
    mov ax, [r10]
    out dx, ax
    add r10, 2
    loop .write_words

    mov dx, ATA_COMMAND_PORT
    mov al, ATA_CMD_FLUSH
    out dx, al

    call ata_wait_not_busy
    test rax, rax
    jz .fail

    inc r8d
    dec r9d
    jmp .write_loop

.success:
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax

.done:
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

fs_sync_directory:
    mov eax, FS_START_LBA + 1
    mov ecx, FS_DIR_SECTORS
    lea rdi, [fs_dir_buffer]
    call ata_write_sectors
    ret

fs_format:
    lea rdi, [fs_dir_buffer]
    mov ecx, 8192
    call fs_memzero

    lea rdi, [fs_sector_buffer]
    mov ecx, 512
    call fs_memzero

    mov dword [fs_sector_buffer], FS_MAGIC
    mov dword [fs_sector_buffer + 4], FS_VERSION
    mov dword [fs_sector_buffer + 8], FS_START_LBA
    mov dword [fs_sector_buffer + 12], FS_END_LBA - FS_START_LBA
    mov dword [fs_sector_buffer + 16], FS_DIR_SECTORS
    mov dword [fs_sector_buffer + 20], FS_MAX_ENTRIES
    mov dword [fs_sector_buffer + 24], FS_DATA_START_LBA

    mov eax, FS_START_LBA
    mov ecx, 1
    lea rdi, [fs_sector_buffer]
    call ata_write_sectors
    test rax, rax
    jz .fail

    call fs_sync_directory
    test rax, rax
    jz .fail

    mov byte [fs_ready], 1
    mov eax, 1
    ret

.fail:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line
    xor eax, eax
    ret

fs_ensure_ready:
    cmp byte [fs_ready], 1
    je .ready

    mov eax, FS_START_LBA
    mov ecx, 1
    lea rdi, [fs_sector_buffer]
    call ata_read_sectors
    test rax, rax
    jz .disk_error

    cmp dword [fs_sector_buffer], FS_MAGIC
    jne .format
    cmp dword [fs_sector_buffer + 4], FS_VERSION
    jne .format

    mov eax, FS_START_LBA + 1
    mov ecx, FS_DIR_SECTORS
    lea rdi, [fs_dir_buffer]
    call ata_read_sectors
    test rax, rax
    jz .disk_error

    mov byte [fs_ready], 1
.ready:
    mov eax, 1
    ret

.format:
    lea rsi, [msg_fs_format]
    call fs_print_line
    call fs_format
    ret

.disk_error:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line
    xor eax, eax
    ret

fs_name_equal:
    push rbx
.cmp_loop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .no
    test al, al
    jz .yes
    inc rsi
    inc rdi
    jmp .cmp_loop
.no:
    xor eax, eax
    pop rbx
    ret
.yes:
    mov eax, 1
    pop rbx
    ret

; Input: RSI = file name ptr
; Output: RAX = entry ptr or 0
fs_find_entry:
    push rbx
    push rcx
    lea rbx, [fs_dir_buffer]
    mov ecx, FS_MAX_ENTRIES
.find_loop:
    mov al, [rbx + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_USED
    jz .next
    push rsi
    push rcx
    mov rdi, rbx
    call fs_name_equal
    pop rcx
    pop rsi
    test rax, rax
    jnz .found
.next:
    add rbx, FS_ENTRY_SIZE
    loop .find_loop
    xor rax, rax
    jmp .done
.found:
    mov rax, rbx
.done:
    pop rcx
    pop rbx
    ret

; Output: RAX = free entry ptr or 0
fs_find_free_entry:
    push rcx
    lea rax, [fs_dir_buffer]
    mov ecx, FS_MAX_ENTRIES
.free_loop:
    cmp byte [rax + FS_ENTRY_FLAGS_OFF], 0
    je .done
    add rax, FS_ENTRY_SIZE
    loop .free_loop
    xor rax, rax
.done:
    pop rcx
    ret

; Input: RDI = entry ptr, RSI = name ptr
fs_copy_name_to_entry:
    push rcx
    mov ecx, FS_NAME_LEN - 1
.copy_loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rsi
    inc rdi
    loop .copy_loop
    mov byte [rdi], 0
.done:
    pop rcx
    ret

; Input: ECX = required sectors, RDX = entry ptr to ignore or 0
; Output: EAX = start LBA or 0
fs_find_free_region:
    push rbx
    push r8
    push r9
    push r10
    push r11
    push r12

    test ecx, ecx
    jz .fail
    mov r8d, FS_DATA_START_LBA

.outer:
    mov r9d, 0xFFFFFFFF
    xor r10d, r10d
    lea rbx, [fs_dir_buffer]
    mov r11d, FS_MAX_ENTRIES

.scan:
    cmp rbx, rdx
    je .scan_next
    mov al, [rbx + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_USED
    jz .scan_next
    mov eax, [rbx + FS_ENTRY_SECT_OFF]
    test eax, eax
    jz .scan_next
    mov r12d, [rbx + FS_ENTRY_START_OFF]
    cmp r12d, r8d
    jb .scan_next
    cmp r12d, r9d
    jae .scan_next
    mov r9d, r12d
    mov r10d, [rbx + FS_ENTRY_SECT_OFF]

.scan_next:
    add rbx, FS_ENTRY_SIZE
    dec r11d
    jnz .scan

    cmp r9d, 0xFFFFFFFF
    jne .check_gap

    mov eax, FS_END_LBA
    sub eax, r8d
    cmp eax, ecx
    jb .fail
    mov eax, r8d
    jmp .done

.check_gap:
    mov eax, r8d
    add eax, ecx
    cmp eax, r9d
    jbe .found
    mov r8d, r9d
    add r8d, r10d
    cmp r8d, FS_END_LBA
    jb .outer

.fail:
    xor eax, eax
    jmp .done

.found:
    mov eax, r8d

.done:
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbx
    ret

fs_create_empty_file:
    push rbx
    mov rbx, rsi

    call fs_string_length
    test eax, eax
    jz .invalid_name
    cmp eax, FS_NAME_LEN
    jae .invalid_name

    mov rsi, rbx
    call fs_find_entry
    test rax, rax
    jnz .exists

    call fs_find_free_entry
    test rax, rax
    jz .no_space

    mov rdx, rax
    mov rdi, rdx
    mov ecx, FS_ENTRY_SIZE
    call fs_memzero
    mov rdi, rdx
    mov rsi, rbx
    call fs_copy_name_to_entry
    mov byte [rdx + FS_ENTRY_FLAGS_OFF], FS_FLAG_USED

    call fs_sync_directory
    test rax, rax
    jz .disk_error

    mov eax, 1
    jmp .done

.invalid_name:
    lea rsi, [msg_fs_invalid_name]
    call fs_print_line
    xor eax, eax
    jmp .done

.exists:
    lea rsi, [msg_fs_exists]
    call fs_print_line
    xor eax, eax
    jmp .done

.no_space:
    lea rsi, [msg_fs_no_space]
    call fs_print_line
    xor eax, eax
    jmp .done

.disk_error:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line
    xor eax, eax

.done:
    pop rbx
    ret

; Input: RSI = name, RDI = data ptr, ECX = data len, R8B = extra flags
; Output: RAX = 1 on success, 0 on failure
fs_write_file:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi
    mov r13, rdi
    mov r14d, ecx
    mov r15b, r8b

    mov rsi, r12
    call fs_string_length
    test eax, eax
    jz .invalid_name
    cmp eax, FS_NAME_LEN
    jae .invalid_name

    mov rsi, r12
    call fs_find_entry
    mov rbx, rax
    test rbx, rbx
    jnz .have_entry

    call fs_find_free_entry
    mov rbx, rax
    test rbx, rbx
    jz .no_space

.have_entry:
    mov eax, r14d
    add eax, 511
    shr eax, 9
    mov r9d, eax               ; needed sectors

    xor r10d, r10d             ; start LBA
    test r9d, r9d
    jz .write_metadata

    mov ecx, r9d
    mov rdx, rbx
    call fs_find_free_region
    test eax, eax
    jz .no_space
    mov r10d, eax

    mov r11d, 0                ; sector index
    mov r8, r13                ; source pointer
    mov edx, r14d              ; bytes remaining

.write_loop:
    lea rdi, [fs_sector_buffer]
    mov ecx, 512
    call fs_memzero

    mov eax, edx
    cmp eax, 512
    jbe .chunk_ready
    mov eax, 512
.chunk_ready:
    mov ecx, eax
    test ecx, ecx
    jz .flush_sector
    lea rdi, [fs_sector_buffer]
    mov rsi, r8
    rep movsb
    mov r8, rsi

.flush_sector:
    mov eax, r10d
    add eax, r11d
    mov ecx, 1
    lea rdi, [fs_sector_buffer]
    call ata_write_sectors
    test rax, rax
    jz .disk_error

    sub edx, 512
    jg .more_bytes
    xor edx, edx
.more_bytes:
    inc r11d
    cmp r11d, r9d
    jl .write_loop

.write_metadata:
    mov rdi, rbx
    mov ecx, FS_ENTRY_SIZE
    call fs_memzero
    mov rdi, rbx
    mov rsi, r12
    call fs_copy_name_to_entry
    mov dword [rbx + FS_ENTRY_SIZE_OFF], r14d
    mov dword [rbx + FS_ENTRY_START_OFF], r10d
    mov dword [rbx + FS_ENTRY_SECT_OFF], r9d
    mov al, FS_FLAG_USED
    or al, r15b
    mov [rbx + FS_ENTRY_FLAGS_OFF], al

    call fs_sync_directory
    test rax, rax
    jz .disk_error

    mov eax, 1
    jmp .done

.invalid_name:
    lea rsi, [msg_fs_invalid_name]
    call fs_print_line
    xor eax, eax
    jmp .done

.no_space:
    lea rsi, [msg_fs_no_space]
    call fs_print_line
    xor eax, eax
    jmp .done

.disk_error:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line
    xor eax, eax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

fs_delete_file:
    push rbx
    mov rbx, rsi

    mov rsi, rbx
    call fs_string_length
    test eax, eax
    jz .invalid_name

    mov rsi, rbx
    call fs_find_entry
    test rax, rax
    jz .not_found

    mov rdi, rax
    mov ecx, FS_ENTRY_SIZE
    call fs_memzero
    call fs_sync_directory
    test rax, rax
    jz .disk_error

    mov eax, 1
    jmp .done

.invalid_name:
    lea rsi, [msg_fs_invalid_name]
    call fs_print_line
    xor eax, eax
    jmp .done

.not_found:
    lea rsi, [msg_fs_not_found]
    call fs_print_line
    xor eax, eax
    jmp .done

.disk_error:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line
    xor eax, eax

.done:
    pop rbx
    ret

fs_list_files:
    push rbx
    push rcx
    push r12

    lea rbx, [fs_dir_buffer]
    mov ecx, FS_MAX_ENTRIES
    xor r12d, r12d

.list_loop:
    mov al, [rbx + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_USED
    jz .next

    mov rsi, rbx
    call print_string
    mov rsi, msg_fs_gap
    call print_string

    mov al, [rbx + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_BINARY
    jz .text_file
    mov rsi, msg_fs_type_bin
    jmp .print_type

.text_file:
    mov rsi, msg_fs_type_txt

.print_type:
    call print_string
    mov rsi, msg_fs_gap
    call print_string
    mov eax, [rbx + FS_ENTRY_SIZE_OFF]
    call print_dec_32
    mov rsi, msg_fs_bytes
    call print_string
    call newline
    inc r12d

.next:
    add rbx, FS_ENTRY_SIZE
    loop .list_loop

    test r12d, r12d
    jnz .done
    lea rsi, [msg_fs_no_files]
    call fs_print_line

.done:
    pop r12
    pop rcx
    pop rbx
    ret

; Input: RDI = entry ptr
fs_print_text_file:
    push rbx
    push rcx
    push rdx
    push r8

    mov al, [rdi + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_BINARY
    jz .start
    lea rsi, [msg_fs_binary_hint]
    call fs_print_line
    jmp .done

.start:
    mov edx, [rdi + FS_ENTRY_SIZE_OFF]
    mov r8d, [rdi + FS_ENTRY_START_OFF]
    test edx, edx
    jz .finish_line

.sector_loop:
    mov eax, r8d
    mov ecx, 1
    lea rdi, [fs_sector_buffer]
    call ata_read_sectors
    test rax, rax
    jz .disk_error

    mov ecx, edx
    cmp ecx, 512
    jbe .chunk_ready
    mov ecx, 512

.chunk_ready:
    lea rbx, [fs_sector_buffer]

.byte_loop:
    mov al, [rbx]
    cmp al, 10
    je .do_newline
    cmp al, 13
    je .skip_byte
    cmp al, 9
    je .do_space
    cmp al, 32
    jb .skip_byte
    call print_char
    jmp .skip_byte

.do_space:
    mov al, ' '
    call print_char
    jmp .skip_byte

.do_newline:
    call newline

.skip_byte:
    inc rbx
    loop .byte_loop

    sub edx, 512
    jg .more_text
    xor edx, edx
.more_text:
    inc r8d
    test edx, edx
    jnz .sector_loop

.finish_line:
    call newline
    jmp .done

.disk_error:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line

.done:
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; Input: RDI = entry ptr
fs_print_hex_file:
    push rbx
    push rcx
    push rdx
    push r8
    push r9

    mov edx, [rdi + FS_ENTRY_SIZE_OFF]
    mov r8d, [rdi + FS_ENTRY_START_OFF]
    xor r9d, r9d
    test edx, edx
    jz .done_line

.hex_sector_loop:
    mov eax, r8d
    mov ecx, 1
    lea rdi, [fs_sector_buffer]
    call ata_read_sectors
    test rax, rax
    jz .disk_error

    mov ecx, edx
    cmp ecx, 512
    jbe .hex_chunk_ready
    mov ecx, 512

.hex_chunk_ready:
    lea rbx, [fs_sector_buffer]

.hex_byte_loop:
    mov al, [rbx]
    call print_hex_byte
    mov al, ' '
    call print_char
    inc r9d
    cmp r9d, 16
    jne .hex_next
    xor r9d, r9d
    call newline

.hex_next:
    inc rbx
    loop .hex_byte_loop

    sub edx, 512
    jg .hex_more
    xor edx, edx
.hex_more:
    inc r8d
    test edx, edx
    jnz .hex_sector_loop

.done_line:
    cmp r9d, 0
    je .done
    call newline
    jmp .done

.disk_error:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line

.done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

fs_hex_value:
    cmp al, '0'
    jb .invalid
    cmp al, '9'
    jbe .digit
    cmp al, 'A'
    jb .check_lower
    cmp al, 'F'
    jbe .upper
.check_lower:
    cmp al, 'a'
    jb .invalid
    cmp al, 'f'
    ja .invalid
    sub al, 'a' - 10
    ret
.upper:
    sub al, 'A' - 10
    ret
.digit:
    sub al, '0'
    ret
.invalid:
    mov al, 0xFF
    ret

; Input: RSI = hex string
; Output: RAX = 1 on success, 0 on failure; RCX = byte count
fs_parse_hex_input:
    push rbx
    push rdi
    push r8

    lea rdi, [fs_parse_buffer]
    xor ecx, ecx
    xor r8d, r8d
    xor ebx, ebx

.parse_loop:
    mov al, [rsi]
    test al, al
    jz .done
    cmp al, ' '
    je .next_char

    call fs_hex_value
    cmp al, 0xFF
    je .fail

    cmp r8b, 0
    je .save_high

    cmp ecx, 256
    jae .fail
    shl bl, 4
    or bl, al
    mov [rdi], bl
    inc rdi
    inc ecx
    xor r8d, r8d
    jmp .next_char

.save_high:
    mov bl, al
    mov r8b, 1

.next_char:
    inc rsi
    jmp .parse_loop

.done:
    cmp r8b, 0
    jne .fail
    mov eax, 1
    jmp .exit

.fail:
    lea rsi, [msg_fs_invalid_hex]
    call fs_print_line
    xor eax, eax

.exit:
    pop r8
    pop rdi
    pop rbx
    ret

msg_fs_format       db "[FS] Formatting storage...", 0
msg_fs_disk_error   db "[FS] Storage I/O error.", 0
msg_fs_invalid_name db "[FS] Invalid file name.", 0
msg_fs_exists       db "[FS] File already exists.", 0
msg_fs_not_found    db "[FS] File not found.", 0
msg_fs_no_space     db "[FS] Not enough storage space.", 0
msg_fs_invalid_hex  db "[FS] Invalid hex data.", 0
msg_fs_binary_hint  db "[FS] File is binary. Use hex.", 0
msg_fs_no_files     db "[FS] No files.", 0
msg_fs_created      db "[FS] File created.", 0
msg_fs_saved        db "[FS] File saved.", 0
msg_fs_deleted      db "[FS] File deleted.", 0
msg_fs_type_txt     db "[TXT]", 0
msg_fs_type_bin     db "[BIN]", 0
msg_fs_bytes        db " bytes", 0
msg_fs_gap          db "  ", 0
