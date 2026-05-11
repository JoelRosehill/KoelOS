cmd_ver db "ver", 0

do_ver:
    mov rsi, .msg
    call print_string
    call newline
    jmp command_done

.msg db "KoelOS v1.3.0-Snapshot", 0
