cmd_rm db "rm", 0

do_rm:
    call fs_ensure_ready
    test rax, rax
    jz command_done

    lea rsi, [arg_buffer]
    call fs_split_args
    test rax, rax
    jz .usage

    mov rsi, rax
    call fs_delete_file
    test rax, rax
    jz command_done

    lea rsi, [msg_fs_deleted]
    call fs_print_line
    jmp command_done

.usage:
    lea rsi, [msg_rm_usage]
    call fs_print_line
    jmp command_done

msg_rm_usage db "Usage: rm <name>", 0
