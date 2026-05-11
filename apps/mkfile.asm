cmd_mkfile db "mkfile", 0

do_mkfile:
    call fs_ensure_ready
    test rax, rax
    jz command_done

    lea rsi, [arg_buffer]
    call fs_split_args
    test rax, rax
    jz .usage

    mov rsi, rax
    call fs_create_empty_file
    test rax, rax
    jz command_done

    lea rsi, [msg_fs_created]
    call fs_print_line
    jmp command_done

.usage:
    lea rsi, [msg_mkfile_usage]
    call fs_print_line
    jmp command_done

msg_mkfile_usage db "Usage: mkfile <name>", 0
