cmd_echo db "echo", 0

do_echo:
    lea rsi, [arg_buffer]
    call print_string
    call newline
    jmp command_done
