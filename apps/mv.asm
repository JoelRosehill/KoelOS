cmd_mv db "mv", 0

do_mv:
    call fs_ensure_ready
    test rax, rax
    jz command_done

    lea rsi, [arg_buffer]
    call fs_split_args          ; RAX = old name, RDX = remainder
    test rax, rax
    jz .usage
    test rdx, rdx
    jz .usage
    mov r12, rax                ; old name
    mov rsi, rdx
    call fs_split_args          ; RAX = new name
    test rax, rax
    jz .usage
    mov r13, rax                ; new name

    mov rsi, r13                ; refuse if the new name is taken
    call fs_find_entry
    test rax, rax
    jnz .exists

    mov rsi, r12                ; locate the source entry
    call fs_find_entry
    test rax, rax
    jz .not_found
    mov rbx, rax                ; entry ptr

    mov rsi, r13                ; validate the new name length
    call fs_string_length
    test eax, eax
    jz .invalid
    cmp eax, FS_NAME_LEN
    jae .invalid

    mov rdi, rbx                ; clear the old name field, then rewrite it
    mov ecx, FS_NAME_LEN
    call fs_memzero
    mov rdi, rbx
    mov rsi, r13
    call fs_copy_name_to_entry
    call fs_sync_directory
    test rax, rax
    jz .disk

    lea rsi, [.msg_done]
    call fs_print_line
    jmp command_done

.usage:
    lea rsi, [.msg_usage]
    call fs_print_line
    jmp command_done
.exists:
    lea rsi, [msg_fs_exists]
    call fs_print_line
    jmp command_done
.not_found:
    lea rsi, [msg_fs_not_found]
    call fs_print_line
    jmp command_done
.invalid:
    lea rsi, [msg_fs_invalid_name]
    call fs_print_line
    jmp command_done
.disk:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line
    jmp command_done

.msg_usage db "Usage: mv <old> <new>", 0
.msg_done  db "[FS] File renamed.", 0
