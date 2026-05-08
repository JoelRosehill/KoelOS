; ==============================================================================
; KoelOS HTTP Web Engine (ULTRA CLEAN VERSION)
; ==============================================================================

http_last_built dq 0
http_last_len   dq 0

; --- THE MISSING VARIABLES ARE RIGHT HERE ---
http_msg1 db "GET ", 0
http_msg2 db " HTTP/1.0", 13, 10, "Host: ", 0
http_msg3 db 13, 10, 13, 10, 0
; --------------------------------------------

msg_http_debug_head db "==== HTTP DEBUGPAD ====", 13, 10, "[PAYLOAD_BYTES] ", 0
msg_diag_sep        db "---------------------------------------", 0

; ------------------------------------------------------------------------------
; http_send_get: Fires the HTTP GET via TCP
; ------------------------------------------------------------------------------
http_send_get:
    push rax
    push rbx
    push rcx
    push rsi
    push rdi
    push rdx
    push r9

    mov rbx, rsi                ; Domain
    mov r9, rdx                 ; Path

    ; [1] Allocate dynamic buffer & ZERO IT
    mov rdi, [heap_current]
    push rdi
    push rcx
    mov rcx, 100
    xor eax, eax
    rep stosd
    pop rcx
    pop rdi
    
    push rdi                    ; Save start address

    ; [2] Build the string
    lea rsi, [http_msg1]
    call .copy_stack
    mov rsi, r9
    call .copy_stack
    lea rsi, [http_msg2]
    call .copy_stack
    mov rsi, rbx
    call .copy_stack
    lea rsi, [http_msg3]
    call .copy_stack

    ; [3] Calculate EXACT length
    pop rsi                     ; RSI = Start
    mov rcx, rdi
    sub rcx, rsi                ; RCX = EXACT Length

    ; Save for debugging
    mov [http_last_built], rsi
    mov [http_last_len], rcx

    ; [4] Send it! 
    call tcp_send_data

    pop r9
    pop rdx
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    pop rax
    ret

.copy_stack:
    lodsb
    test al, al
    jz .copy_done
    stosb
    jmp .copy_stack
.copy_done:
    ret

; ------------------------------------------------------------------------------
; http_debug: Dumps the raw bytes of the last built L7 GET request
; ------------------------------------------------------------------------------
http_debug:
    push rax
    push rsi
    push rcx
    push rdx
    push rdi

    mov rsi, [http_last_built]
    test rsi, rsi
    jz .done

    push rsi
    lea rsi, [msg_http_debug_head]
    call print_string
    pop rsi

    mov rdx, [http_last_len]
    mov rcx, 1

.loop:
    mov al, [rsi]
    movzx eax, al
    call print_hex_byte
    call print_space

    test rcx, 15
    jnz .no_newline
    call newline
.no_newline:
    inc rsi
    inc rcx
    dec rdx
    jnz .loop

    call newline
    lea rsi, [msg_diag_sep]
    call print_string
    call newline

.done:
    pop rdi
    pop rdx
    pop rcx
    pop rsi
    pop rax
    ret

; ------------------------------------------------------------------------------
; http_parse_and_print: Strips headers & HTML tags
; ------------------------------------------------------------------------------
http_parse_and_print:
    push rax
    push rcx
    push rsi

    mov rsi, [tcp_payload_ptr]
    mov rcx, [tcp_payload_len]

    test rsi, rsi
    jz .done
    test rcx, rcx
    jz .done

.search_headers:
    cmp rcx, 4
    jl .print_raw

    cmp byte [rsi], 0x0D
    jne .next_char
    cmp byte [rsi+1], 0x0A
    jne .next_char
    cmp byte [rsi+2], 0x0D
    jne .next_char
    cmp byte [rsi+3], 0x0A
    je .found_body

.next_char:
    inc rsi
    dec rcx
    jmp .search_headers

.found_body:
    add rsi, 4
    sub rcx, 4

.print_raw:
    mov r8, 0                   ; State 0=Text, 1=In <tag>

.print_loop:
    mov al, [rsi]
    cmp al, '<'
    je .enter_tag
    cmp al, '>'
    je .exit_tag

    cmp r8, 1
    je .skip_char

    cmp al, 32
    jl .special_check
    
    call print_char
    jmp .skip_char

.special_check:
    cmp al, 10
    je .do_nl
    cmp al, 13
    jne .skip_char
.do_nl:
    call print_char

    jmp .skip_char

.enter_tag:
    mov r8, 1
    jmp .skip_char
.exit_tag:
    mov r8, 0

.skip_char:
    inc rsi
    dec rcx
    jnz .print_loop

    call newline

.done:
    pop rsi
    pop rcx
    pop rax
    ret

; ------------------------------------------------------------------------------
; print_space
; ------------------------------------------------------------------------------
print_space:
    push rax
    mov al, ' '
    call print_char
    pop rax
    ret