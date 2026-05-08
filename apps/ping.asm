; ==========================================
; KoelOS ICMP Ping (Universal/Broadcast)
; ==========================================

cmd_ping db "ping", 0

do_ping:
    lea rsi, [msg_pinging]
    call print_string
    call newline

    mov rdi, [heap_current]
    push rdi

    ; --- ETHERNET HEADER (14 bytes) ---
    ; Target the VirtualBox NAT Router directly (52:54:00:12:35:02)
    mov dword [rdi], 0x12005452      
    mov word [rdi+4], 0x0235         
    
    ; Source MAC (Us)
    lea rsi, [my_mac]
    mov eax, [rsi]
    mov [rdi+6], eax
    mov ax, [rsi+4]
    mov [rdi+10], ax
    mov word [rdi+12], 0x0008       ; Protocol: IPv4
    add rdi, 14

    ; --- IP HEADER (20 bytes) ---
    mov r8, rdi                     ; Save IP start for checksum
    
    mov byte [rdi], 0x45            ; Version 4, IHL 5
    mov byte [rdi+1], 0             ; TOS
    mov word [rdi+2], 0x1C00        ; Total Len: 28 bytes
    mov word [rdi+4], 0             ; ID
    mov word [rdi+6], 0             ; Flags/Fragment Offset
    mov byte [rdi+8], 64            ; TTL
    mov byte [rdi+9], 1             ; Protocol: ICMP
    mov word [rdi+10], 0            ; Checksum must be 0 before calculating
    mov dword [rdi+12], 0x0F02000A  ; Source IP: 10.0.2.15
    mov dword [rdi+16], 0x0202000A  ; Target IP: 10.0.2.2
    
    ; Calculate IP Checksum
    mov rsi, r8
    mov rcx, 20
    call calculate_checksum
    mov [r8+10], ax                 ; Store it back
    add rdi, 20

    ; --- ICMP HEADER (8 bytes) ---
    mov r9, rdi                     ; Save ICMP start
    mov byte [rdi], 8               ; Type: Echo Request
    mov byte [rdi+1], 0             ; Code: 0
    mov word [rdi+2], 0             ; Zero Checksum
    mov word [rdi+4], 0x0100        ; Identifier
    mov word [rdi+6], 0x0100        ; Sequence Number
    
    ; Calculate ICMP Checksum
    mov rsi, r9
    mov rcx, 8
    call calculate_checksum
    mov [r9+2], ax
    
    ; [2] Final Send
    pop rsi
    mov rcx, 42                     ; 14 (Eth) + 20 (IP) + 8 (ICMP)
    call e1000_send_packet

    ; [3] Continuous Listen Loop
    lea rsi, [msg_waiting]
    call print_string
    call newline
.wait:
    call e1000_receive_packet
    test rax, rax
    jz .check_esc
    
    ; A packet arrived! Hand it to the stack to print.
    call net_handle_packet
    
    ; CRITICAL FIX: Go back and listen for the NEXT packet!
    jmp .wait

.check_esc:
    ; Check if ESC key (0x01) was pressed to exit loop
    in al, 0x64
    and al, 1
    jz .wait
    in al, 0x60
    cmp al, 1
    jne .wait

.done:
    jmp command_done

msg_pinging db "Pinging 10.0.2.2 (Broadcast) with strict checksums...", 0
msg_waiting db "Waiting for replies (Press ESC to stop)...", 0