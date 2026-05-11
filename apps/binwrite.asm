cmd_binwrite db "binwrite", 0

do_binwrite:
    push rbx

    call fs_ensure_ready
    test rax, rax
    jz .done

    lea rsi, [arg_buffer]
    call fs_split_args
    test rax, rax
    jz .usage

    mov rbx, rax
    test rdx, rdx
    jz .save_empty

    mov rsi, rdx
    call fs_parse_hex_input
    test rax, rax
    jz .done

    mov rsi, rbx
    lea rdi, [fs_parse_buffer]
    mov r8b, FS_FLAG_BINARY
    call fs_write_file
    test rax, rax
    jz .done

    lea rsi, [msg_fs_saved]
    call fs_print_line
    jmp .done

.save_empty:
    mov rsi, rbx
    xor rdi, rdi
    xor ecx, ecx
    mov r8b, FS_FLAG_BINARY
    call fs_write_file
    test rax, rax
    jz .done

    lea rsi, [msg_fs_saved]
    call fs_print_line
    jmp .done

.usage:
    lea rsi, [msg_binwrite_usage]
    call fs_print_line

.done:
    pop rbx
    jmp command_done

msg_binwrite_usage db "Usage: binwrite <name> <hex bytes>", 0
