; ==============================================================================
; ARP Protocol Handler (Universal & Padded)
; ==============================================================================

; Input: RSI = Pointer to ARP data (past Ethernet header), RCX = Length
arp_handle:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; [1] Basic ARP Validation
    ; Check if Opcode is REQUEST (0x0100 on x86)
    cmp word [rsi + 6], 0x0100
    jne .done

    ; [2] Is the Target IP (Offset 24) our IP?
    mov eax, [rsi + 24]
    mov ebx, [my_ip]        
    cmp eax, ebx
    jne .done

    ; [3] It's for us! Log the event.
    push rsi
    mov rsi, msg_arp_log
    call print_string
    call newline
    pop rsi

    ; [4] CONSTRUCT THE REPLY PACKET
    mov rdi, [heap_current]
    push rdi                ; Save start of packet for the send call

    ; --- VIRTUALBOX/HARDWARE FIX: Zero-Pad to 64 Bytes ---
    ; We must send at least 60 bytes to prevent "Runt Packet" hardware crashes
    push rcx
    push rdi
    push rax
    mov rcx, 16             ; 16 dwords = 64 bytes
    xor eax, eax
    rep stosd               ; Fill packet buffer with zeros
    pop rax
    pop rdi
    pop rcx
    ; -----------------------------------------------------

    ; --- Ethernet Header (14 bytes) ---
    ; Dest MAC (Sender MAC from ARP offset 8)
    mov eax, [rsi + 8]      ; First 4 bytes
    mov [rdi], eax
    mov ax, [rsi + 12]      ; Last 2 bytes
    mov [rdi + 4], ax
    
    ; Source MAC (Us)
    mov eax, [my_mac]
    mov [rdi + 6], eax
    mov ax, [my_mac + 4]
    mov [rdi + 10], ax
    
    ; EtherType (ARP = 0x0608)
    mov word [rdi + 12], 0x0608

    ; --- ARP Header (28 bytes) ---
    add rdi, 14
    mov word [rdi], 0x0100      ; HW Type: Ethernet (1)
    mov word [rdi + 2], 0x0008  ; Protocol: IPv4 (0x0800)
    mov byte [rdi + 4], 6       ; HW Size: 6
    mov byte [rdi + 5], 4       ; Protocol Size: 4
    mov word [rdi + 6], 0x0200  ; Opcode: REPLY (2)

    ; Sender MAC (Us)
    mov eax, [my_mac]
    mov [rdi + 8], eax
    mov ax, [my_mac + 4]
    mov [rdi + 12], ax

    ; Sender IP (Us)
    mov eax, [my_ip]
    mov [rdi + 14], eax

    ; Target MAC (The router's MAC from ARP offset 8)
    mov eax, [rsi + 8]
    mov [rdi + 18], eax
    mov ax, [rsi + 12]
    mov [rdi + 22], ax
    
    ; Target IP (The router's IP from ARP offset 14)
    mov eax, [rsi + 14]
    mov [rdi + 24], eax

    ; [5] SEND THE REPLY
    pop rsi                 ; RSI = Start of the new packet
    mov rcx, 60             ; CRITICAL: Send exactly 60 bytes!
    call e1000_send_packet

.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; Move the message to the bottom so it isn't accidentally executed as code
msg_arp_log db "[ARP] Request for my IP. Sending reply...", 0