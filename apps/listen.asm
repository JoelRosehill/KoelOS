; ==========================================
; Network Sniffer / Listener App
; ==========================================

cmd_listen db "listen", 0

do_listen:
    call ensure_nic_ready
    test rax, rax
    jz command_done

    lea rsi, [msg_listen_start]
    call print_string
    call newline
    lea rsi, [msg_listen_esc]
    call print_string
    call newline

.packet_poll:
    ; [1] Check the hardware for a new packet
    ; This function is in drivers/e1000_rx.asm
    call e1000_receive_packet
    
    ; RAX = Address of packet, RCX = Length
    test rax, rax
    jz .check_keyboard      ; No packet? Check if user wants to quit

    ; [2] We have data! Send it to the Network Stack Dispatcher
    ; This function is in drivers/net_stack.asm
    ; It will automatically print "[ARP]" or "[IP]" based on the content
    call net_handle_packet

    jmp .packet_poll        ; Loop back to check for the next one

.check_keyboard:
    ; [3] Check for keyboard input without blocking
    in al, 0x64             ; Status register
    and al, 1               ; Output buffer full?
    jz .packet_poll         ; No key pressed, keep sniffing
    
    in al, 0x60             ; Read the scancode
    cmp al, 0x01            ; 0x01 is the ESC key
    je .exit_sniffer
    
    jmp .packet_poll        ; Other key pressed? Ignore it

.exit_sniffer:
    lea rsi, [msg_listen_stop]
    call print_string
    call newline
    jmp command_done

; --- Messages ---
msg_listen_start db "Listening for incoming traffic on eth0...", 0
msg_listen_esc   db "Press ESC to return to shell.", 0
msg_listen_stop  db "Sniffer stopped. Returning to KoelOS.", 0
