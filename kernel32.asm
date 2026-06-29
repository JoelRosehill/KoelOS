; kernel32.asm — KoelOS 32-bit "lite" kernel
; ============================================================================
; Runs in 32-bit protected mode with flat 4 GB segments (set up by the
; boot_*32 loaders) at 0x10000. Self-contained: VGA text console, COM1 serial
; mirror, PS/2 keyboard, CMOS RTC, a polling shell, and a handful of commands.
;
; No networking / filesystem / alkan — those are the 64-bit kernel. This build
; exists so KoelOS runs on pre-2004 boards whose CPUs have no 64-bit long mode.
; ============================================================================
[bits 32]
[org 0x10000]

_start:
    mov esp, 0x90000           ; reaffirm a 32-bit stack
    mov ebp, esp
    call serial_init
    call rtc_capture_boot
    call clear_screen

    mov esi, msg_welcome
    call print_string
    call newline
    call print_prompt

; --- MAIN SHELL LOOP (polled PS/2 keyboard) ---
keyboard_loop:
    in al, 0x64
    test al, 1
    jz keyboard_loop
    in al, 0x60

    cmp al, 0x1C               ; ENTER
    je handle_enter
    cmp al, 0x0E               ; BACKSPACE
    je .backspace

    call kbd_translate
    test al, al
    jz keyboard_loop

    mov ebx, [input_length]
    cmp ebx, 255
    jge keyboard_loop
    mov [input_buffer + ebx], al
    inc dword [input_length]
    call print_char
    jmp keyboard_loop

.backspace:
    cmp dword [input_length], 0
    je keyboard_loop
    dec dword [input_length]
    mov ebx, [input_length]
    mov byte [input_buffer + ebx], 0
    call do_backspace
    jmp keyboard_loop

; --- COMMAND PARSER ---
handle_enter:
    mov ebx, [input_length]
    mov byte [input_buffer + ebx], 0
    call newline
    cmp dword [input_length], 0
    je command_done

    ; split: first token = command, remainder -> arg_ptr
    mov dword [arg_ptr], empty_str
    mov esi, input_buffer
.split:
    mov al, [esi]
    test al, al
    jz .dispatch
    cmp al, ' '
    je .space
    inc esi
    jmp .split
.space:
    mov byte [esi], 0
    inc esi
.skipsp:
    cmp byte [esi], ' '
    jne .setarg
    inc esi
    jmp .skipsp
.setarg:
    mov [arg_ptr], esi

.dispatch:
    mov ebx, command_table
.search:
    mov esi, [ebx]
    test esi, esi
    jz .unknown
    mov edi, input_buffer
    call strcmp
    test eax, eax
    jnz .found
    add ebx, 8
    jmp .search
.found:
    jmp [ebx + 4]
.unknown:
    mov esi, msg_unknown
    call print_string
    call newline

command_done:
    mov dword [input_length], 0
    call print_prompt
    jmp keyboard_loop

; ============================================================================
; Commands
; ============================================================================
do_help:
    mov ebx, command_table
.l:
    mov esi, [ebx]
    test esi, esi
    jz .done
    call print_string
    mov esi, str_gap
    call print_string
    add ebx, 8
    jmp .l
.done:
    call newline
    jmp command_done

do_ver:
    mov esi, .msg
    call print_string
    call newline
    jmp command_done
.msg db "KoelOS v1.6.0 (32-bit lite)", 0

do_clear:
    call clear_screen
    jmp command_done

do_echo:
    mov esi, [arg_ptr]
    call print_string
    call newline
    jmp command_done

do_date:
    call rtc_get_time
    mov al, '2'
    call print_char
    mov al, '0'
    call print_char
    mov al, [rtc_year]
    call print_two_digits
    mov al, '-'
    call print_char
    mov al, [rtc_month]
    call print_two_digits
    mov al, '-'
    call print_char
    mov al, [rtc_day]
    call print_two_digits
    mov al, ' '
    call print_char
    mov al, [rtc_hour]
    call print_two_digits
    mov al, ':'
    call print_char
    mov al, [rtc_min]
    call print_two_digits
    mov al, ':'
    call print_char
    mov al, [rtc_sec]
    call print_two_digits
    call newline
    jmp command_done

do_uptime:
    call rtc_get_time
    call rtc_seconds_of_day        ; EAX = seconds since midnight, now
    sub eax, [boot_seconds]
    jns .ok
    add eax, 86400
.ok:
    xor edx, edx
    mov ecx, 3600
    div ecx                        ; EAX = hours, EDX = leftover seconds
    mov [up_rem], edx
    mov esi, .msg
    call print_string
    call print_dec                 ; EAX = hours
    mov al, ':'
    call print_char
    mov eax, [up_rem]
    xor edx, edx
    mov ecx, 60
    div ecx                        ; EAX = minutes, EDX = seconds
    mov [up_rem], edx
    call print_two_digits          ; AL = minutes
    mov al, ':'
    call print_char
    mov eax, [up_rem]
    call print_two_digits          ; seconds
    call newline
    jmp command_done
.msg db "Uptime: ", 0

do_reboot:
    mov esi, .msg
    call print_string
    call newline
    mov al, 0xFE                   ; pulse the 8042 reset line
    out 0x64, al
    cli
.hang:
    hlt
    jmp .hang
.msg db "Rebooting...", 0

; ============================================================================
; VGA text console (writes to 0xB8000)
; ============================================================================
print_char:                        ; AL = character
    pushad
    call check_scroll
    mov edi, [cursor_pos]
    mov ah, [current_color]
    mov [edi], ax
    call serial_putc               ; mirror to COM1 (AL still = char)
    add dword [cursor_pos], 2
    call update_cursor
    popad
    ret

print_string:                      ; ESI = ASCIIZ
    pushad
.l:
    mov al, [esi]
    test al, al
    jz .d
    call print_char
    inc esi
    jmp .l
.d:
    popad
    ret

newline:
    pushad
    mov eax, [cursor_pos]
    sub eax, 0xb8000
    xor edx, edx
    mov ecx, 160
    div ecx
    inc eax
    mul ecx
    add eax, 0xb8000
    mov [cursor_pos], eax
    call check_scroll
    call update_cursor
    mov al, 13                     ; serial CRLF
    call serial_putc
    mov al, 10
    call serial_putc
    popad
    ret

print_prompt:
    mov esi, msg_prompt
    call print_string
    ret

clear_screen:
    pushad
    mov edi, 0xb8000
    mov ecx, 2000
    mov ah, [current_color]
    mov al, ' '
    rep stosw
    mov dword [cursor_pos], 0xb8000
    call update_cursor
    popad
    ret

do_backspace:
    pushad
    cmp dword [cursor_pos], 0xb8000
    jbe .done
    sub dword [cursor_pos], 2
    mov edi, [cursor_pos]
    mov ah, [current_color]
    mov al, ' '
    mov [edi], ax
    call update_cursor
.done:
    popad
    ret

check_scroll:
    pushad
    cmp dword [cursor_pos], 0xb8fa0     ; past row 25?
    jb .done
    ; scroll up one line
    mov edi, 0xb8000
    mov esi, 0xb8000 + 160
    mov ecx, 960                        ; 160*24/4 dwords
    rep movsd
    mov edi, 0xb8000 + 160*24           ; clear last row
    mov ah, [current_color]
    mov al, ' '
    mov ecx, 80
    rep stosw
    mov dword [cursor_pos], 0xb8000 + 160*24
.done:
    popad
    ret

update_cursor:
    pushad
    mov eax, [cursor_pos]
    sub eax, 0xb8000
    shr eax, 1
    mov ebx, eax
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    mov dx, 0x3D5
    mov al, bl
    out dx, al
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    mov dx, 0x3D5
    mov al, bh
    out dx, al
    popad
    ret

; EAX = unsigned value -> printed in decimal
print_dec:
    pushad
    mov ebx, 10
    xor ecx, ecx
.div:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .div
.pr:
    pop eax
    add al, '0'
    call print_char
    dec ecx
    jnz .pr
    popad
    ret

; AL = 0..99 -> two zero-padded digits
print_two_digits:
    pushad
    movzx eax, al
    mov bl, 10
    div bl                         ; AL = tens, AH = ones
    push eax
    add al, '0'
    call print_char
    pop eax
    mov al, ah
    add al, '0'
    call print_char
    popad
    ret

; ============================================================================
; COM1 serial (mirror of the text console)
; ============================================================================
serial_init:
    pushad
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8
    mov al, 0x03
    out dx, al
    mov dx, 0x3F9
    xor al, al
    out dx, al
    mov dx, 0x3FB
    mov al, 0x03
    out dx, al
    mov dx, 0x3FA
    mov al, 0xC7
    out dx, al
    mov dx, 0x3FC
    mov al, 0x0B
    out dx, al
    popad
    ret

serial_putc:                       ; AL = char (preserved)
    push eax
    push edx
    mov ah, al
.wait:
    mov dx, 0x3FD
    in al, dx
    test al, 0x20
    jz .wait
    mov al, ah
    mov dx, 0x3F8
    out dx, al
    pop edx
    pop eax
    ret

; ============================================================================
; PS/2 keyboard scancode translation
; ============================================================================
kbd_translate:                     ; AL = scancode -> AL = ASCII (0 = none)
    push ebx
    push ecx
    cmp al, 0x2A
    je .shift_on
    cmp al, 0x36
    je .shift_on
    cmp al, 0xAA
    je .shift_off
    cmp al, 0xB6
    je .shift_off
    test al, 0x80
    jnz .none
    movzx ebx, al
    cmp byte [shift_state], 0
    jne .shifted
    mov al, [keymap + ebx]
    jmp .done
.shifted:
    mov al, [keymap_shift + ebx]
    jmp .done
.shift_on:
    mov byte [shift_state], 1
    jmp .none
.shift_off:
    mov byte [shift_state], 0
.none:
    xor al, al
.done:
    pop ecx
    pop ebx
    ret

; ESI, EDI = strings -> EAX = 1 if equal else 0 (preserves EBX)
strcmp:
    push esi
    push edi
    push edx
.l:
    mov al, [esi]
    mov dl, [edi]
    cmp al, dl
    jne .ne
    test al, al
    jz .eq
    inc esi
    inc edi
    jmp .l
.ne:
    xor eax, eax
    jmp .out
.eq:
    mov eax, 1
.out:
    pop edx
    pop edi
    pop esi
    ret

; ============================================================================
; CMOS real-time clock
; ============================================================================
cmos_read:                         ; BL = register -> AL = value
    mov al, bl
    out 0x70, al
    in al, 0x71
    ret

bcd_to_bin:                        ; AL (packed BCD) -> AL (binary)
    push ecx
    mov cl, al
    and cl, 0x0F
    shr al, 4
    movzx eax, al
    lea eax, [eax + eax*4]
    add eax, eax
    add al, cl
    pop ecx
    ret

rtc_wait_ready:
    pushad
.l:
    mov bl, 0x0A
    call cmos_read
    test al, 0x80
    jnz .l
    popad
    ret

rtc_get_time:
    pushad
    call rtc_wait_ready
    mov bl, 0x00
    call cmos_read
    mov [rtc_sec], al
    mov bl, 0x02
    call cmos_read
    mov [rtc_min], al
    mov bl, 0x04
    call cmos_read
    mov [rtc_hour], al
    mov bl, 0x07
    call cmos_read
    mov [rtc_day], al
    mov bl, 0x08
    call cmos_read
    mov [rtc_month], al
    mov bl, 0x09
    call cmos_read
    mov [rtc_year], al
    mov bl, 0x0B
    call cmos_read
    test al, 0x04                  ; status B bit 2 set => already binary
    jnz .done
    mov al, [rtc_sec]
    call bcd_to_bin
    mov [rtc_sec], al
    mov al, [rtc_min]
    call bcd_to_bin
    mov [rtc_min], al
    mov al, [rtc_hour]
    call bcd_to_bin
    mov [rtc_hour], al
    mov al, [rtc_day]
    call bcd_to_bin
    mov [rtc_day], al
    mov al, [rtc_month]
    call bcd_to_bin
    mov [rtc_month], al
    mov al, [rtc_year]
    call bcd_to_bin
    mov [rtc_year], al
.done:
    popad
    ret

rtc_seconds_of_day:                ; -> EAX
    push ecx
    push edx
    movzx eax, byte [rtc_hour]
    mov ecx, 3600
    mul ecx
    movzx ecx, byte [rtc_min]
    imul ecx, ecx, 60
    add eax, ecx
    movzx ecx, byte [rtc_sec]
    add eax, ecx
    pop edx
    pop ecx
    ret

rtc_capture_boot:
    pushad
    call rtc_get_time
    call rtc_seconds_of_day
    mov [boot_seconds], eax
    popad
    ret

; ============================================================================
; Command table + data
; ============================================================================
command_table:
    dd cmd_help,     do_help
    dd cmd_ver,      do_ver
    dd cmd_clear,    do_clear
    dd cmd_echo,     do_echo
    dd cmd_date,     do_date
    dd cmd_uptime,   do_uptime
    dd cmd_reboot,   do_reboot
    dd cmd_ls,       do_ls
    dd cmd_cat,      do_cat
    dd cmd_mkfile,   do_mkfile
    dd cmd_rm,       do_rm
    dd cmd_cp,       do_cp
    dd cmd_mv,       do_mv
    dd cmd_hex,      do_hex
    dd cmd_binwrite, do_binwrite
    dd cmd_edit,     do_edit
    dd cmd_format,   do_format
    dd cmd_alkan,    do_alkan
    dd 0, 0

cmd_help     db "help", 0
cmd_ver      db "ver", 0
cmd_clear    db "clear", 0
cmd_echo     db "echo", 0
cmd_date     db "date", 0
cmd_uptime   db "uptime", 0
cmd_reboot   db "reboot", 0
cmd_ls       db "ls", 0
cmd_cat      db "cat", 0
cmd_mkfile   db "mkfile", 0
cmd_rm       db "rm", 0
cmd_cp       db "cp", 0
cmd_mv       db "mv", 0
cmd_hex      db "hex", 0
cmd_binwrite db "binwrite", 0
cmd_edit     db "edit", 0
cmd_format   db "format", 0
cmd_alkan    db "alkan", 0

cursor_pos    dd 0xb8000
current_color db 0x1F
shift_state   db 0
input_length  dd 0
arg_ptr       dd 0
empty_str     db 0
str_gap       db "  ", 0

rtc_sec   db 0
rtc_min   db 0
rtc_hour  db 0
rtc_day   db 0
rtc_month db 0
rtc_year  db 0
boot_seconds dd 0
up_rem       dd 0

msg_welcome db "KoelOS v1.6 (32-bit)", 0
msg_prompt  db "root@koelos> ", 0
msg_unknown db "Error: Unknown command.", 0

keymap:
    db 0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0, 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0, 0
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0, '\'
    db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' ', 0
    times 128 db 0

keymap_shift:
    db 0, 0, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 0, 0
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 0, 0
    db 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0, '|'
    db 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' ', 0
    times 128 db 0

input_buffer times 256 db 0

; --- 32-bit filesystem (ATA PIO + KFS1) and file commands ---
%include "fs32.asm"

; --- 32-bit Alkan BASIC interpreter ---
%include "alkan32.asm"
