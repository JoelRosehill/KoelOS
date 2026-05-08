; ==============================================================================
; Print IP address in dotted-decimal format (e.g., 10.0.2.15)
; Input: EAX = IP Address (32-bit Big Endian from packet)
; ==============================================================================
print_ip:
    push rax
    push rbx
    push rcx
    push rdx

    mov ebx, eax            ; Copy IP to EBX for shifting/extraction
    
    ; [Part 1] Extract Byte 1 (e.g., 10)
    movzx eax, bl           ; BL is the lowest byte in x86 register
    call print_dec_byte     
    mov al, '.'
    call print_char

    ; [Part 2] Extract Byte 2 (e.g., 0)
    movzx eax, bh           ; BH is the second byte
    call print_dec_byte
    mov al, '.'
    call print_char

    ; [Part 3] Move the upper 16 bits down
    shr ebx, 16             ; Shift EBX right by 16 bits
    
    ; [Part 4] Extract Byte 3 (e.g., 2)
    movzx eax, bl           ; Now BL contains what used to be Byte 3
    call print_dec_byte
    mov al, '.'
    call print_char

    ; [Part 5] Extract Byte 4 (e.g., 15)
    movzx eax, bh           ; BH contains what used to be Byte 4
    call print_dec_byte

    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

ensure_nic_ready:
    push rsi

    cmp qword [nic_mem_base], 0
    jne .ready

    call find_nic
    test rax, rax
    jz .not_found

    call e1000_init

.ready:
    mov rax, 1
    pop rsi
    ret

.not_found:
    lea rsi, [msg_net_missing]
    call print_string
    call newline
    xor rax, rax
    pop rsi
    ret

msg_net_missing db "[NET] Error: No supported network hardware found.", 0
