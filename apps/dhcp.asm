; ==============================================================================
; DHCP Auto-Config Application (Synced + Heartbeat + ESC Abort)
; ==============================================================================

cmd_dhcp db "dhcp", 0

do_dhcp:
    call ensure_nic_ready
    test rax, rax
    jz command_done

    lea rsi, [msg_dhcp_start]
    call print_string
    call newline

    ; [1] Prepare a clean, zeroed 300-byte buffer on the heap
    mov rdi, [heap_current]
    push rdi                
    
    push rdi
    mov rcx, 75             ; 75 dwords = 300 bytes
    xor eax, eax
    rep stosd               ; Fill with zeros to prevent garbage in payload
    pop rdi

    ; --- BUILD THE ETHERNET HEADER ---
    mov dword [rdi], 0xFFFFFFFF     ; Destination: Broadcast
    mov word [rdi + 4], 0xFFFF
    lea rsi, [my_mac]               ; Source: Us
    mov eax, [rsi]
    mov [rdi + 6], eax
    mov ax, [rsi + 4]
    mov [rdi + 10], ax
    mov word [rdi + 12], 0x0008     ; Type: IPv4 (Big Endian 0x0800)
    add rdi, 14

    ; --- BUILD THE IP HEADER ---
    mov r8, rdi                     
    mov byte [rdi], 0x45            ; Version 4, IHL 5
    mov word [rdi + 2], 0x1C01      ; Total Length: 284 bytes (Big Endian)
    mov byte [rdi + 8], 64          ; TTL
    mov byte [rdi + 9], 17          ; Protocol: UDP
    mov dword [rdi + 12], 0         ; Source: 0.0.0.0
    mov dword [rdi + 16], 0xFFFFFFFF ; Destination: 255.255.255.255
    
    mov rsi, r8
    mov rcx, 20
    call calculate_checksum         ; CRITICAL: Router drops if invalid
    mov [r8 + 10], ax
    add rdi, 20

    ; --- BUILD THE UDP HEADER ---
    mov word [rdi], 0x4400          ; Source Port: 68
    mov word [rdi + 2], 0x4300      ; Destination Port: 67
    mov word [rdi + 4], 0x0801      ; UDP Length: 264
    add rdi, 8

    ; --- BUILD THE DHCP PAYLOAD ---
    mov byte [rdi], 1               ; Message Type: Boot Request
    mov byte [rdi + 1], 1           ; HW Type: Ethernet
    mov byte [rdi + 2], 6           ; MAC Length: 6
    mov dword [rdi + 4], 0x3903F312 ; Transaction ID
    mov word [rdi + 10], 0x0080     ; Broadcast Flag (Required for VBox)
    
    ; Client MAC at offset 28
    lea rsi, [my_mac]
    mov eax, [rsi]
    mov [rdi + 28], eax
    mov ax, [rsi + 4]
    mov [rdi + 32], ax
    
    ; Magic Cookie at offset 236
    mov dword [rdi + 236], 0x63538263 
    
    ; Option 53: DHCP Discover
    mov byte [rdi + 240], 53
    mov byte [rdi + 241], 1
    mov byte [rdi + 242], 1
    
    ; Option 255: End
    mov byte [rdi + 243], 255

    ; [2] SEND THE DISCOVER
    pop rsi                         
    mov rcx, 298                    
    call e1000_send_packet

    lea rsi, [msg_dhcp_sent]
    call print_string
    call newline

    ; [3] THE SYNCED LISTEN LOOP
    lea rsi, [msg_dhcp_wait]
    call print_string

    mov dword [my_ip], 0            ; Reset our IP global
    mov rbx, 60                     ; Wait for up to 60 "dots"

.outer_loop:
    mov r12, 1500000                ; FIX: Use R12 instead of RCX!
.inner_loop:
    call e1000_receive_packet       ; If a packet arrives, RAX=Buffer, RCX=Length
    test rax, rax
    jz .no_packet
    
    ; Something arrived! Dispatcher uses RAX and RCX correctly now.
    call net_handle_packet          
    
    cmp dword [my_ip], 0
    jne .success                    ; If it's not zero, we won!

.no_packet:
    ; --- Check for ESC key to Abort ---
    in al, 0x64
    test al, 1
    jz .no_key
    in al, 0x60
    cmp al, 1                       ; ESC scan code
    je .aborted
.no_key:
    dec r12                         ; FIX: Decrement R12
    jnz .inner_loop

    ; Heartbeat
    mov al, '.'
    call print_char
    
    dec rbx
    jnz .outer_loop

    ; --- TIMEOUT ---
    call newline
    lea rsi, [msg_dhcp_timeout]
    call print_string
    call newline
    jmp .done

.aborted:
    call newline
    lea rsi, [msg_dhcp_abort]
    call print_string
    call newline
    jmp .done

.success:
    call newline
    lea rsi, [msg_dhcp_complete]
    call print_string
    mov eax, [my_ip]
    call print_ip                   
    call newline

.done:
    jmp command_done

; --- Messages ---
msg_dhcp_start    db "[DHCP] Initializing Discover...", 0
msg_dhcp_sent     db "[DHCP] Discover broadcast sent.", 0
msg_dhcp_wait     db "[DHCP] Listening for Offer (ESC to abort)", 0
msg_dhcp_timeout  db "[DHCP] Error: No response from router.", 0
msg_dhcp_abort    db "[DHCP] Aborted by user.", 0
msg_dhcp_complete db "[DHCP] Success! Network Configured. IP: ", 0
