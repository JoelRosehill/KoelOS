global cmd_dns, do_dns
cmd_dns db "dns", 0

do_dns:
    test rsi, rsi
    jz .done

    add rsi, 3                  
.skip_spaces:
    mov al, [rsi]
    cmp al, 0                   
    je .next_char
    cmp al, 32                  
    je .next_char
    jmp .found_arg              
.next_char:
    inc rsi
    jmp .skip_spaces

.found_arg:
    push rsi
.strip_loop:
    cmp byte [rsi], 32          
    jl .strip_end               
    inc rsi
    jmp .strip_loop
.strip_end:
    mov byte [rsi], 0           
    pop rsi

    push rsi
    lea rsi, [msg_dns_look]
    call print_string
    pop rsi                     
    
    push rsi                    
    call print_string
    call newline

    mov rdi, [heap_current]
    add rdi, 34
    mov r15, rdi                

    add rdi, 8                  
    pop rsi                     
    call dns_build_query        
    
    mov rdi, r15
    mov word [rdi], 0x4433      
    mov word [rdi+2], 0x3500    
    
    mov ax, cx
    add ax, 8                   
    xchg al, ah                 
    mov [rdi+4], ax             
    mov word [rdi+6], 0         
    
    mov rdx, [dns_server_ip]    
    mov rsi, r15                
    add rcx, 8                  
    mov bx, 53                  
    
    push rcx
    push rdx
    lea rsi, [msg_dns_wait]
    call print_string
    call newline
    pop rdx
    pop rcx
    
    mov rsi, r15                
    call ip_send_udp            
    
    mov dword [dns_resolved_ip], 0
    mov r12, 0
.wait:
    call e1000_receive_packet
    test rax, rax
    jz .no_pkt
    call net_handle_packet      
    cmp dword [dns_resolved_ip], 0
    jne .success

.no_pkt:
    in al, 0x64
    test al, 1
    jz .no_key
    in al, 0x60
    cmp al, 1
    je .timeout
.no_key:
    inc r12
    cmp r12, 8000000            
    je .timeout
    jmp .wait

.success:
    lea rsi, [msg_dns_found]
    call print_string
    mov eax, [dns_resolved_ip]
    call print_ip
    call newline
    jmp command_done            

.timeout:
    lea rsi, [msg_dns_fail]
    call print_string
    jmp command_done            

.done:
    jmp command_done