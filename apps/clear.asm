cmd_clear db "clear", 0

do_clear:
    call clear_screen
    jmp command_done
