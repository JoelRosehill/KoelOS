cmd_cp db "cp", 0

do_cp:
    call fs_ensure_ready
    test rax, rax
    jz command_done

    lea rsi, [arg_buffer]
    call fs_split_args          ; RAX = source name, RDX = remainder
    test rax, rax
    jz .usage
    test rdx, rdx
    jz .usage
    mov r12, rax                ; source name
    mov rsi, rdx
    call fs_split_args          ; RAX = destination name
    test rax, rax
    jz .usage
    mov r13, rax                ; destination name

    mov rsi, r12
    call fs_find_entry
    test rax, rax
    jz .not_found

    mov rsi, rax                ; source entry ptr
    mov rdi, r13                ; destination name ptr
    call fs_copy_entry
    test rax, rax
    jz command_done

    lea rsi, [.msg_done]
    call fs_print_line
    jmp command_done

.usage:
    lea rsi, [.msg_usage]
    call fs_print_line
    jmp command_done
.not_found:
    lea rsi, [msg_fs_not_found]
    call fs_print_line
    jmp command_done

.msg_usage db "Usage: cp <src> <dest>", 0
.msg_done  db "[FS] File copied.", 0
