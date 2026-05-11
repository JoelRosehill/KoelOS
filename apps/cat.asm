cmd_cat db "cat", 0

do_cat:
    call fs_ensure_ready
    test rax, rax
    jz command_done

    lea rsi, [arg_buffer]
    call fs_split_args
    test rax, rax
    jz .usage

    mov rsi, rax
    call fs_find_entry
    test rax, rax
    jz .not_found

    mov rdi, rax
    call fs_print_text_file
    jmp command_done

.usage:
    lea rsi, [msg_cat_usage]
    call fs_print_line
    jmp command_done

.not_found:
    lea rsi, [msg_fs_not_found]
    call fs_print_line
    jmp command_done

msg_cat_usage db "Usage: cat <name>", 0
