cmd_browser db "browser", 0

do_browser:
    cmp byte [arg_buffer], 0
    jne .open

    lea rsi, [msg_browser_usage]
    call print_string
    call newline
    jmp command_done

.open:
    lea rsi, [msg_browser_start]
    call print_string
    call newline
    jmp do_fetch

msg_browser_start db "[BROWSER] Text-only mode.", 0
msg_browser_usage db "Usage: browser <domain-or-ip>", 0
