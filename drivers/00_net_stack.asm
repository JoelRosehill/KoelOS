; ==============================================================================
; KoelOS Network Stack Dispatcher - THE DEFINITIVE VERSION
; ==============================================================================

%include "drivers/arp_handle.asm"
%include "drivers/tcp.asm"
%include "drivers/http.asm"

net_handle_packet:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rsi, rax            
    
    ; [1] LAYER 1: ETHERNET
    cmp rcx, 14
    jl .done

    mov bx, [rsi + 12]      
    
    add rsi, 14             
    sub rcx, 14             

    cmp bx, 0x0608          
    je .handle_arp
    cmp bx, 0x0806          
    je .handle_arp
    cmp bx, 0x0008          
    je .handle_ip
    cmp bx, 0x0800          
    je .handle_ip
    jmp .done

; --- ARP HANDLER ---
.handle_arp:
    call arp_handle         
    jmp .done

; --- IP HANDLER ---
.handle_ip:
    cmp rcx, 20
    jl .done

    mov rdx, rsi            

    ; Protocol ID
    mov al, [rsi + 9]       
    
    ; SAFE DISPATCH (Your original working logic)
    cmp al, 1               
    je .handle_icmp
    cmp al, 6
    je .handle_tcp
    cmp al, 17              
    je .handle_udp
    jmp .done

; --- ICMP HANDLER ---
.handle_icmp:
    movzx eax, byte [rsi]   
    and eax, 0x0F           
    shl eax, 2              
    
    add rsi, rax            
    
    mov al, [rsi]           
    cmp al, 0               
    jne .done

    lea rsi, [msg_icmp_reply]
    call print_string
    call newline
    jmp .done

.handle_tcp:
    movzx eax, byte [rsi]   ; Calculate IP header length
    and eax, 0x0F           
    shl eax, 2              
    add rsi, rax            ; RSI now points to TCP Header
    call tcp_handle_packet  ; Hand off to our new driver!
    jmp .done

; --- UDP HANDLER ---
.handle_udp:
    movzx eax, byte [rsi]   
    and eax, 0x0F           
    shl eax, 2              
    add rsi, rax            

    mov bx, [rsi + 2]       ; Destination Port
    mov cx, [rsi]           ; Source Port (NEW for DNS replies)

    ; Check DHCP (Destination Port 68)
    cmp bx, 0x4400          
    je .is_dhcp
    cmp bx, 0x0044          
    je .is_dhcp

    ; === FIX: Check DNS (Source Port 53) ===
    cmp cx, 0x3500          
    je .is_dns
    cmp cx, 0x0035          
    je .is_dns

    ; Unknown UDP Port
    push rsi
    lea rsi, [msg_udp_found]
    call print_string
    movzx eax, bx
    call print_hex_32       
    call newline
    pop rsi
    jmp .done               ; <--- FIXED: Jump to .done, not net_done_exit

.is_dhcp:
    add rsi, 8              ; Skip UDP header
    cmp byte [rsi], 2       ; BOOTP Reply?
    jne .done

    mov eax, [rsi + 16]     
    mov [my_ip], eax        

    lea rsi, [msg_dhcp_success]
    call print_string
    mov eax, [my_ip]
    call print_ip           
    call newline
    jmp .done

.is_dns:
    add rsi, 8              ; Skip UDP header
    call dns_handle_reply   ; Parse the DNS data
    jmp .done

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ==============================================================================
; GLOBAL DATA
; ==============================================================================
msg_icmp_reply   db "[ICMP] Echo Reply received! (SUCCESS)", 0
msg_dhcp_success db "[DHCP] Success! IP Assigned: ", 0
msg_udp_found    db "[NET] UDP Packet to unknown port: 0x", 0

dns_server_ip    dd 0x0302000A   ; 10.0.2.3
dns_resolved_ip  dd 0
msg_dns_look     db "[DNS] Looking up: ", 0
msg_dns_wait     db "[DNS] Query sent. Waiting...", 0
msg_dns_found    db "[DNS] Resolved IP: ", 0
msg_dns_fail     db "[DNS] Error: Request timed out.", 10, 0

; ------------------------------------------------------------------------------
; ip_send_udp
; Input: RDX = Dest IP, RSI = Start of UDP Header, RCX = UDP Length, BX = Dest Port
; ------------------------------------------------------------------------------
ip_send_udp:
    push rsi
    push rcx
    push rax
    push rdi

    ; We need to move back 34 bytes (14 Eth + 20 IP) to build the headers
    sub rsi, 34
    mov rdi, rsi

    ; --- [1] ETHERNET HEADER (14 bytes) ---
    ; Dest MAC: 52:54:00:12:35:02 (Standard VirtualBox Router MAC)
    mov dword [rdi], 0x12005452     ; First 4 bytes (52:54:00:12)
    mov word [rdi+4], 0x0235        ; Last 2 bytes (35:02)
    
    ; Source MAC (Us)
    mov eax, [my_mac]
    mov [rdi+6], eax
    mov ax, [my_mac+4]
    mov [rdi+10], ax
    
    ; EtherType: IPv4 (0x0800 in Big Endian -> 0x0008 in Little Endian)
    mov word [rdi+12], 0x0008
    
    add rdi, 14                     ; Advance to IP Header space

    ; --- [2] IP HEADER (20 bytes) ---
    mov byte [rdi], 0x45            ; Version 4, IHL 5
    mov byte [rdi+1], 0             ; TOS
    
    mov ax, cx                      ; CX = UDP Length
    add ax, 20                      ; Add IP Length
    push rax                        ; Save total IP length for later
    xchg al, ah                     ; Big Endian
    mov [rdi+2], ax                 ; Total Length
    
    mov word [rdi+4], 0xABCD        ; ID
    mov word [rdi+6], 0x0040        ; Flags: Don't Fragment
    mov byte [rdi+8], 64            ; TTL
    mov byte [rdi+9], 17            ; Protocol: UDP
    mov word [rdi+10], 0            ; Clear checksum for calculation
    
    mov eax, [my_ip]                ; Source IP
    mov [rdi+12], eax
    mov [rdi+16], edx               ; Dest IP

    ; Calculate IP Checksum
    push rax
    push rcx
    push rsi
    mov rsi, rdi
    mov rcx, 20
    call calculate_checksum
    mov [rdi+10], ax
    pop rsi
    pop rcx
    pop rax

    ; --- [3] SEND TO E1000 ---
    pop rax                         ; Get back the IP Length
    add rax, 14                     ; Add Ethernet header length
    mov rcx, rax                    ; RCX = Total size of Ethernet Frame

    sub rdi, 14                     ; Move pointer back to start of Ethernet Frame
    mov rsi, rdi                    ; RSI = Start of packet
    call e1000_send_packet          ; Ship it!

    pop rdi
    pop rax
    pop rcx
    pop rsi
    ret

ip_send_tcp:
    push rsi
    push rcx
    push rax
    push rdi

    ; We need to move back 34 bytes (14 Eth + 20 IP) to build the headers
    sub rsi, 34
    mov rdi, rsi

    ; --- [1] ETHERNET HEADER (14 bytes) ---
    ; Dest MAC: 52:54:00:12:35:02 (Standard VirtualBox Router MAC)
    mov dword [rdi], 0x12005452     ; First 4 bytes (52:54:00:12)
    mov word [rdi+4], 0x0235        ; Last 2 bytes (35:02)
    
    ; Source MAC (Us)
    mov eax, [my_mac]
    mov [rdi+6], eax
    mov ax, [my_mac+4]
    mov [rdi+10], ax
    
    ; EtherType: IPv4 (0x0800 in Big Endian -> 0x0008 in Little Endian)
    mov word [rdi+12], 0x0008
    
    add rdi, 14                     ; Advance to IP Header space

    ; --- [2] IP HEADER (20 bytes) ---
    mov byte [rdi], 0x45            ; Version 4, IHL 5
    mov byte [rdi+1], 0             ; TOS
    
    mov ax, cx                      ; CX = UDP Length
    add ax, 20                      ; Add IP Length
    push rax                        ; Save total IP length for later
    xchg al, ah                     ; Big Endian
    mov [rdi+2], ax                 ; Total Length
    
    mov word [rdi+4], 0xABCD        ; ID
    mov word [rdi+6], 0x0040        ; Flags: Don't Fragment
    mov byte [rdi+8], 64            ; TTL
    mov byte [rdi+9], 6             ; Protocol: TCP
    mov word [rdi+10], 0            ; Clear checksum for calculation
    
    mov eax, [my_ip]                ; Source IP
    mov [rdi+12], eax
    mov [rdi+16], edx               ; Dest IP

    ; Calculate IP Checksum
    push rax
    push rcx
    push rsi
    mov rsi, rdi
    mov rcx, 20
    call calculate_checksum
    mov [rdi+10], ax
    pop rsi
    pop rcx
    pop rax

    ; --- [3] SEND TO E1000 (Inside ip_send_tcp) ---
    pop rax                         
    add rax, 14                     
    mov rcx, rax                    

    sub rdi, 14                     
    mov rsi, rdi                    
    
    ; === NEW: PREVENT RUNT PACKETS ===
    cmp rcx, 60
    jge .send_it
    mov rcx, 60                     ; Pad to minimum 60 bytes!
.send_it:
    call e1000_send_packet          

    pop rdi
    pop rax
    pop rcx
    pop rsi
    ret

dns_build_query:
    push rdi
    push rsi
    mov r8, rdi

    mov word [rdi], 0x3912      ; Transaction ID
    
    ; === FIX: 0x0001 puts '01 00' on the wire (Recursion Desired) ===
    mov word [rdi+2], 0x0001    
    
    mov word [rdi+4], 0x0100    ; Questions: 1
    mov word [rdi+6], 0
    mov word [rdi+8], 0
    mov word [rdi+10], 0
    add rdi, 12

    ; ... (rest of the encode loop stays exactly the same)

.encode_loop:
    push rdi
    inc rdi
    xor rcx, rcx

.char_loop:
    lodsb
    cmp al, '.'
    je .label_done
    cmp al, 0
    je .label_done
    stosb
    inc rcx
    jmp .char_loop

.label_done:
    mov rdx, rax
    mov rax, rcx
    pop rbx
    mov [rbx], al
    cmp rdx, 0
    jne .encode_loop

    mov byte [rdi], 0
    inc rdi

    mov word [rdi], 0x0100
    mov word [rdi+2], 0x0100
    add rdi, 4

    mov rax, rdi
    sub rax, r8
    mov rcx, rax

    pop rsi
    pop rdi
    ret

dns_handle_reply:
    push rax
    push rsi

    add rsi, 12

.skip_name:
    movzx rax, byte [rsi]
    test al, al
    jz .name_done
    inc rsi
    add rsi, rax
    jmp .skip_name

.name_done:
    add rsi, 5
    cmp byte [rsi], 0xC0
    jne .done_dns
    add rsi, 2
    add rsi, 8
    
    lodsw 
    cmp ax, 0x0400
    jne .done_dns

    mov eax, [rsi]
    mov [dns_resolved_ip], eax

.done_dns:
    pop rsi
    pop rax
    ret