; ==============================================================================
; KoelOS TCP Protocol Driver (The Web Engine)
; ==============================================================================

tcp_target_ip   dd 0
tcp_target_port dw 0
tcp_local_port  dw 0xABCD       
tcp_seq_num     dd 0x11223344   
tcp_ack_num     dd 0            
tcp_state       db 0            ; 0=Closed, 1=SYN Sent, 2=Established, 3=Data
tcp_payload_ptr dq 0            
tcp_payload_len dq 0            

msg_tcp_syn         db "[TCP] Sending SYN packet...", 0
msg_tcp_synack      db "[TCP] SYN-ACK received! Connection established.", 0
msg_tcp_ack_sent    db "[TCP] Final ACK sent. Handshake complete!", 0
msg_tcp_drop        db "[TCP] Dropping unknown TCP packet.", 0

; ------------------------------------------------------------------------------
tcp_connect:
    push rax
    push rcx
    push rsi
    push rdi

    mov [tcp_target_ip], edx
    mov [tcp_target_port], bx
    mov byte [tcp_state], 1     

    lea rsi, [msg_tcp_syn]
    call print_string
    call newline

    mov rdi, [heap_current]
    push rdi
    push rcx
    mov rcx, 20
    xor eax, eax
    rep stosd
    pop rcx
    pop rdi
    
    add rdi, 34                 
    mov r15, rdi                

    mov ax, [tcp_local_port]
    xchg al, ah                 
    mov [rdi], ax               
    
    mov ax, [tcp_target_port]
    xchg al, ah                 
    mov [rdi+2], ax             

    mov eax, [tcp_seq_num]
    bswap eax                   
    mov [rdi+4], eax            

    mov dword [rdi+8], 0        
    mov word [rdi+12], 0x0250   
    mov word [rdi+14], 0xFFFF   
    mov word [rdi+16], 0        
    mov word [rdi+18], 0        

    push rax
    push rcx
    push rsi
    
    mov eax, [my_ip]
    mov [r15 - 12], eax         
    mov eax, [tcp_target_ip]
    mov [r15 - 8], eax          
    mov word [r15 - 4], 0x0600  
    mov word [r15 - 2], 0x1400  
    
    mov rsi, r15
    sub rsi, 12                 
    mov rcx, 32                 
    call calculate_checksum
    mov [r15 + 16], ax          
    
    pop rsi
    pop rcx
    pop rax

    mov rsi, r15                
    mov rcx, 20                 
    mov rdx, [tcp_target_ip]
    call ip_send_tcp

    ; === FIX: SYN consumes 1 sequence number. Update it here! ===
    inc dword [tcp_seq_num]

    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; ------------------------------------------------------------------------------
tcp_handle_packet:
    push rax
    push rbx
    push rcx

    mov al, [rsi+13]            
    cmp al, 0x12                
    je .handle_syn_ack

    cmp byte [tcp_state], 2
    jne .done

    mov ax, [rdx+2]
    xchg al, ah                 
    movzx rcx, ax
    sub rcx, 20                 
    
    movzx eax, byte [rsi+12]
    shr al, 4
    shl al, 2                   
    sub rcx, rax                
    
    cmp rcx, 0
    jle .done                   

    add rsi, rax                
    mov [tcp_payload_ptr], rsi
    mov [tcp_payload_len], rcx
    mov byte [tcp_state], 3     

    mov eax, [tcp_ack_num]
    bswap eax
    add eax, ecx                
    bswap eax
    mov [tcp_ack_num], eax
    call tcp_send_ack           
    
    jmp .done

.handle_syn_ack:
    cmp byte [tcp_state], 1
    jne .done
    mov eax, [rsi+4]
    bswap eax                   
    inc eax
    mov [tcp_ack_num], eax
    mov byte [tcp_state], 2     
    call tcp_send_ack           

    push rsi
    lea rsi, [msg_tcp_synack]
    call print_string
    call newline
    lea rsi, [msg_tcp_ack_sent]
    call print_string
    call newline
    pop rsi

.done:
    pop rcx
    pop rbx
    pop rax
    ret

; ------------------------------------------------------------------------------
tcp_send_data:
    push rax
    push rcx
    push rsi
    push rdi
    push r8
    push r9

    mov r8, rsi                 
    mov r9, rcx                 

    mov rdi, [heap_current]
    push rdi
    push rcx
    mov rcx, 100                
    xor eax, eax
    rep stosd
    pop rcx
    pop rdi
    
    add rdi, 34                 
    mov r15, rdi                

    mov ax, [tcp_local_port]
    xchg al, ah
    mov [rdi], ax               
    
    mov ax, [tcp_target_port]
    xchg al, ah
    mov [rdi+2], ax             

    mov eax, [tcp_seq_num]
    bswap eax
    mov [rdi+4], eax            

    mov eax, [tcp_ack_num]
    bswap eax
    mov [rdi+8], eax            

    mov word [rdi+12], 0x1850   
    mov word [rdi+14], 0xFFFF   
    mov word [rdi+16], 0        
    mov word [rdi+18], 0        

    add rdi, 20                 
    mov rsi, r8                 
    mov rcx, r9                 
    rep movsb

    push rax
    push rcx
    push rsi
    mov eax, [my_ip]
    mov [r15 - 12], eax         
    mov eax, [tcp_target_ip]
    mov [r15 - 8], eax          
    mov word [r15 - 4], 0x0600  
    
    mov ax, r9w                 
    add ax, 20                  
    xchg al, ah                 
    mov [r15 - 2], ax           
    
    mov rsi, r15
    sub rsi, 12                 
    mov rcx, r9                 
    add rcx, 32                 
    call calculate_checksum
    mov [r15 + 16], ax          
    pop rsi
    pop rcx
    pop rax

    mov eax, [tcp_seq_num]
    add eax, r9d
    mov [tcp_seq_num], eax

    mov rsi, r15                
    mov rcx, r9                 
    add rcx, 20                 
    mov rdx, [tcp_target_ip]
    call ip_send_tcp

    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; ------------------------------------------------------------------------------
tcp_send_ack:
    push rax
    push rcx
    push rsi
    push rdi

    mov rdi, [heap_current]
    push rdi
    push rcx
    mov rcx, 20
    xor eax, eax
    rep stosd
    pop rcx
    pop rdi
    
    add rdi, 34                 
    mov r15, rdi                

    mov ax, [tcp_local_port]
    xchg al, ah
    mov [rdi], ax               
    
    mov ax, [tcp_target_port]
    xchg al, ah
    mov [rdi+2], ax             

    ; === FIX: Just use the current Sequence Number ===
    mov eax, [tcp_seq_num]
    bswap eax
    mov [rdi+4], eax            

    mov eax, [tcp_ack_num]
    bswap eax
    mov [rdi+8], eax            

    mov word [rdi+12], 0x1050   
    mov word [rdi+14], 0xFFFF   
    mov word [rdi+16], 0        
    mov word [rdi+18], 0        

    push rax
    push rcx
    push rsi
    
    mov eax, [my_ip]
    mov [r15 - 12], eax         
    mov eax, [tcp_target_ip]
    mov [r15 - 8], eax          
    mov word [r15 - 4], 0x0600  
    mov word [r15 - 2], 0x1400  
    
    mov rsi, r15
    sub rsi, 12                 
    mov rcx, 32                 
    call calculate_checksum
    mov [r15 + 16], ax          
    
    pop rsi
    pop rcx
    pop rax

    mov rsi, r15                
    mov rcx, 20                 
    mov rdx, [tcp_target_ip]
    call ip_send_tcp

    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret