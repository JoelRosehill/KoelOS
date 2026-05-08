; apps/fetch.asm

global cmd_fetch, do_fetch
cmd_fetch db "fetch", 0

fetch_domain dq 0
fetch_path   dq 0
default_path db "/", 0

msg_fetch_start db "[FETCH] Connecting to: ", 0
msg_fetch_err   db "[FETCH] DNS Error: Could not resolve domain.", 0
msg_tcp_fail    db "[TCP] Error: Server did not respond to SYN.", 0
msg_http_send   db "[HTTP] Connected! Sending Dynamic Request...", 0
msg_http_wait   db "[HTTP] Waiting for Data... (Press ESC to stop)", 0
msg_http_fail   db "[HTTP] Error: Timeout (Server didn't send data).", 0
msg_http_rx_head db "==== HTTP RECEIVED DATA (Parsed) ====", 13, 10, 0
msg_http_fin    db "[HTTP] Final Data received. Stream Complete.", 0

do_fetch:
    test rsi, rsi
    jz .done

    add rsi, 5                  
.skip_spaces:
    mov al, [rsi]
    test al, al
    jz .done
    cmp al, 32
    je .next_char
    jmp .found_arg
.next_char:
    inc rsi
    jmp .skip_spaces

.found_arg:
    ; Save domain pointer safely to memory
    mov [fetch_domain], rsi
    
    ; Setup default path "/"
    lea rbx, [default_path]
    mov [fetch_path], rbx

    ; Sanitize domain for trailing spaces
.strip_loop:
    cmp byte [rsi], 32
    jl .strip_end
    inc rsi
    jmp .strip_loop
.strip_end:
    mov byte [rsi], 0

    ; Print Status (Using variables, no dangerous stack pops!)
    lea rsi, [msg_fetch_start]
    call print_string
    mov rsi, [fetch_domain]
    call print_string
    call newline

    ; Trigger DNS resolution
    mov rdi, [heap_current]
    add rdi, 34                 
    mov r15, rdi
    add rdi, 8
    mov rsi, [fetch_domain]     ; <--- THE FIX: Explicitly load the domain pointer!
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
    mov rsi, r15
    call ip_send_udp

    mov dword [dns_resolved_ip], 0
    mov r12, 0
.dns_wait:
    call e1000_receive_packet
    test rax, rax
    jz .dns_no_pkt
    call net_handle_packet
    cmp dword [dns_resolved_ip], 0
    jne .dns_success
.dns_no_pkt:
    in al, 0x64
    test al, 1
    jz .dns_no_key
    in al, 0x60
    cmp al, 1
    je .dns_timeout
.dns_no_key:
    inc r12
    cmp r12, 8000000
    je .dns_timeout
    jmp .dns_wait

.dns_timeout:
    lea rsi, [msg_fetch_err]
    call print_string
    call newline
    jmp command_done

.dns_success:
    mov edx, [dns_resolved_ip]
    mov bx, 80                  
    call tcp_connect

    mov r12, 0
.tcp_wait:
    call e1000_receive_packet
    test rax, rax
    jz .tcp_no_pkt
    call net_handle_packet
    
    cmp byte [tcp_state], 2
    je .tcp_success

.tcp_no_pkt:
    in al, 0x64
    test al, 1
    jz .tcp_no_key
    in al, 0x60
    cmp al, 1
    je .tcp_timeout
.tcp_no_key:
    inc r12
    cmp r12, 8000000            
    je .tcp_timeout
    jmp .tcp_wait

.tcp_timeout:
    lea rsi, [msg_tcp_fail]
    call print_string
    call newline
    jmp command_done

.tcp_success:
    lea rsi, [msg_http_send]
    call print_string
    call newline

    mov rsi, [fetch_domain]
    mov rdx, [fetch_path]
    call http_send_get

    lea rsi, [msg_http_wait]
    call print_string
    call newline

    lea rsi, [msg_http_rx_head]
    call print_string
    call newline

    mov r12, 0
.data_wait:
    call e1000_receive_packet
    test rax, rax
    jz .data_no_pkt
    call net_handle_packet
    
    cmp byte [tcp_state], 3
    je .data_success

.data_no_pkt:
    in al, 0x64
    test al, 1
    jz .no_key
    in al, 0x60
    cmp al, 1
    je .complete
.no_key:
    inc r12
    cmp r12, 2000000000         ; ~2 seconds timeout so AWS has time to reply!
    je .data_timeout
    jmp .data_wait

.data_timeout:
    lea rsi, [msg_http_fail]
    call print_string
    call newline
    jmp command_done

.data_success:
    call http_parse_and_print
    
    mov byte [tcp_state], 2
    mov r12, 0                  
    jmp .data_wait

.complete:
    call newline
    lea rsi, [msg_http_fin]
    call print_string
    call newline
    jmp command_done

.done:
    jmp command_done