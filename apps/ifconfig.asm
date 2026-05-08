; apps/ifconfig.asm

cmd_ifconfig db "ifconfig", 0

do_ifconfig:
    ; Print "eth0: MAC "
    mov rsi, .msg_eth
    call print_string

    ; [1] Print MAC Address (6 bytes)
    mov rsi, my_mac     ; Defined in drivers/arp_handle.asm
    mov rcx, 6
.mac_loop:
    lodsb
    call print_hex_byte
    cmp rcx, 1          ; Don't print ':' after the last byte
    je .mac_done
    mov al, ':'
    call print_char
    loop .mac_loop

.mac_done:
    call newline

    ; [2] Print IP Address
    mov rsi, .msg_inet
    call print_string

    mov rsi, my_ip      ; Defined in drivers/arp_handle.asm
    mov rcx, 4
.ip_loop:
    lodsb
    call print_dec_byte
    cmp rcx, 1          ; Don't print '.' after the last byte
    je .ip_done
    mov al, '.'
    call print_char
    loop .ip_loop

.ip_done:
    call newline
    jmp command_done

.msg_eth  db "eth0: MAC ", 0
.msg_inet db "      inet ", 0