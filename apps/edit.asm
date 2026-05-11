cmd_edit db "edit", 0

do_edit:
    push rbx

    call fs_ensure_ready
    test rax, rax
    jz .done

    lea rsi, [arg_buffer]
    call fs_split_args
    test rax, rax
    jz .usage

    mov rbx, rax
    xor ecx, ecx
    test rdx, rdx
    jz .save
    mov rsi, rdx
    call fs_string_length
    mov ecx, eax

.save:
    mov rsi, rbx
    mov rdi, rdx
    xor r8d, r8d
    call fs_write_file
    test rax, rax
    jz .done

    lea rsi, [msg_fs_saved]
    call fs_print_line
    jmp .done

.usage:
    lea rsi, [msg_edit_usage]
    call fs_print_line

.done:
    pop rbx
    jmp command_done

msg_edit_usage db "Usage: edit <name> <text>", 0
