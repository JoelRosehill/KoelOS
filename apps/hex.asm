cmd_hex db "hex", 0

do_hex:
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
    call fs_print_hex_file
    jmp command_done

.usage:
    lea rsi, [msg_hex_usage]
    call fs_print_line
    jmp command_done

.not_found:
    lea rsi, [msg_fs_not_found]
    call fs_print_line
    jmp command_done

msg_hex_usage db "Usage: hex <name>", 0
