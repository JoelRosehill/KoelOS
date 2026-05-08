cmd_help db "help", 0

do_help:
    mov rbx, command_table
.loop:
    mov rsi, [rbx]
    test rsi, rsi
    jz .done
    call print_string
    mov rsi, .spacer
    call print_string
    add rbx, 16
    jmp .loop
.done:
    call newline
    jmp command_done

.spacer db "  ", 0