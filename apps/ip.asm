; ==============================================================================
; KoelOS IP Checker (whatsmyip)
; ==============================================================================

cmd_ip db "ip", 0

do_ip:
    ; [1] Load the current IP address from memory
    mov eax, [my_ip]

    ; [2] Check if it is zero (not configured yet)
    test eax, eax
    jz .no_ip

    ; [3] Print the success message and the IP
    lea rsi, [msg_ip_is]
    call print_string
    
    ; EAX still contains the IP, so we call the pretty printer
    call print_ip
    call newline
    jmp .done

.no_ip:
    lea rsi, [msg_no_ip]
    call print_string
    call newline

.done:
    jmp command_done

; --- Messages ---
msg_ip_is db "Current IP Address: ", 0
msg_no_ip db "Network not configured. Please run 'dhcp' or 'netinit'.", 0