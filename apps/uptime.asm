cmd_uptime db "uptime", 0

do_uptime:
    call rtc_get_time
    call rtc_seconds_of_day    ; RAX = seconds since midnight, now
    sub rax, [boot_seconds]
    jns .ok
    add rax, 86400             ; clock rolled past midnight since boot
.ok:
    xor rdx, rdx
    mov rcx, 3600
    div rcx                    ; RAX = hours, RDX = leftover seconds
    mov [.rem], rdx

    lea rsi, [.msg]
    call print_string
    call print_dec_32          ; EAX = hours
    mov al, ':'
    call print_char

    mov rax, [.rem]
    xor rdx, rdx
    mov rcx, 60
    div rcx                    ; RAX = minutes, RDX = seconds
    mov [.rem], rdx
    call print_two_digits      ; AL = minutes
    mov al, ':'
    call print_char
    mov rax, [.rem]
    call print_two_digits      ; seconds
    call newline
    jmp command_done

.msg db "Uptime: ", 0
.rem dq 0
