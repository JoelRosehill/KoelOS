; apps/announce.asm
cmd_announce db "announce", 0

do_announce:
    lea rsi, [msg_ann]
    call print_string
    call newline

    mov rdi, [heap_current]
    push rdi

    ; --- ARP ANNOUNCEMENT PACKET ---
    ; Dest: Broadcast (FF:FF:FF:FF:FF:FF)
    mov dword [rdi], 0xFFFFFFFF
    mov word [rdi+4], 0xFFFF
    ; Source: My MAC
    lea rsi, [my_mac]
    mov eax, [rsi]
    mov [rdi+6], eax
    mov ax, [rsi+4]
    mov [rdi+10], ax
    ; Type: ARP (0x0806)
    mov word [rdi+12], 0x0608
    add rdi, 14

    ; ARP Data (28 bytes)
    mov word [rdi], 0x0100      ; HW Type: Ethernet (1)
    mov word [rdi+2], 0x0008    ; Proto: IPv4 (0x0800)
    mov byte [rdi+4], 6         ; HW Len
    mov byte [rdi+5], 4         ; Proto Len
    mov word [rdi+6], 0x0100    ; Opcode: Request (1)
    ; Sender MAC & IP
    lea rsi, [my_mac]
    mov eax, [rsi]
    mov [rdi+8], eax
    mov ax, [rsi+4]
    mov [rdi+12], ax
    mov dword [rdi+14], 0x0F02000A ; 10.0.2.15
    ; Target MAC (0) & Target IP (10.0.2.15)
    mov qword [rdi+18], 0
    mov dword [rdi+24], 0x0F02000A

    pop rsi
    mov rcx, 14 + 28
    call e1000_send_packet
    
    lea rsi, [msg_done]
    call print_string
    call newline
    jmp command_done

msg_ann  db "Sending ARP Announcement (Gratuitous ARP)...", 0
msg_done db "Identity broadcasted to virtual switch.", 0