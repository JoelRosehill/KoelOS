cmd_format db "format", 0

do_format:
    lea rsi, [.msg_warn]
    call fs_print_line
    call fs_format
    test rax, rax
    jz command_done
    lea rsi, [.msg_done]
    call fs_print_line
    jmp command_done

.msg_warn db "[FS] Reformatting storage (erases all files)...", 0
.msg_done db "[FS] Storage formatted.", 0
