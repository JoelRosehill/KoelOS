cmd_edit db "edit", 0

; Line-based text editor. Typed lines are appended to an in-RAM buffer; lines
; starting with ':' are editor commands. The text buffer lives in scratch RAM
; (EDIT_TEXT) so it does not bloat kernel.bin.
%define EDIT_TEXT 0x308000
%define EDIT_CAP  0x8000           ; 32 KB

do_edit:
    call fs_ensure_ready
    test rax, rax
    jz command_done

    lea rsi, [arg_buffer]
    call fs_split_args
    test rax, rax
    jz .usage
    mov rsi, rax
    call edit_copy_name
    call edit_load

    lea rsi, [.editing]
    call print_string
    lea rsi, [edit_name]
    call print_string
    call newline
    lea rsi, [.banner]
    call fs_print_line

.loop:
    lea rsi, [.prompt]
    call print_string
    lea rdi, [edit_line]
    call edit_read_line

    lea rsi, [edit_line]
    cmp byte [rsi], ':'
    jne .text

    lea rdi, [.cmd_wq]
    call strcmp
    cmp rax, 1
    je .savequit
    lea rdi, [.cmd_w]
    call strcmp
    cmp rax, 1
    je .save
    lea rdi, [.cmd_q]
    call strcmp
    cmp rax, 1
    je .quit
    lea rdi, [.cmd_l]
    call strcmp
    cmp rax, 1
    je .list
    lea rdi, [.cmd_d]
    call strcmp
    cmp rax, 1
    je .del
    lea rsi, [.unknown]
    call fs_print_line
    jmp .loop

.text:
    call edit_append_line
    jmp .loop

.save:
    call edit_save
    test rax, rax
    jz .loop
    lea rsi, [msg_fs_saved]
    call fs_print_line
    jmp .loop

.savequit:
    call edit_save
    test rax, rax
    jz .loop
    lea rsi, [msg_fs_saved]
    call fs_print_line
    jmp command_done

.list:
    call edit_list
    jmp .loop

.del:
    call edit_del_last
    jmp .loop

.quit:
    jmp command_done

.usage:
    lea rsi, [.usage_msg]
    call fs_print_line
    jmp command_done

.prompt    db "ed> ", 0
.editing   db "editing ", 0
.banner    db ":w save  :q quit  :wq save+quit  :l list  :d delline", 0
.unknown   db "[ed] unknown command", 0
.usage_msg db "Usage: edit <name>", 0
.cmd_w     db ":w", 0
.cmd_q     db ":q", 0
.cmd_wq    db ":wq", 0
.cmd_l     db ":l", 0
.cmd_d     db ":d", 0

; Read one line into [RDI], echoing and honoring backspace. Returns length.
edit_read_line:
    mov qword [edit_len], 0
.loop:
    in al, 0x64
    test al, 1
    jz .loop
    in al, 0x60
    cmp al, 0x1C
    je .enter
    cmp al, 0x0E
    je .bs
    call kbd_translate_scancode
    test al, al
    jz .loop
    mov rcx, [edit_len]
    cmp rcx, 255
    jge .loop
    mov [rdi + rcx], al
    inc qword [edit_len]
    call print_char
    jmp .loop
.bs:
    cmp qword [edit_len], 0
    je .loop
    dec qword [edit_len]
    mov rcx, [edit_len]
    mov byte [rdi + rcx], 0
    call do_backspace
    jmp .loop
.enter:
    mov rcx, [edit_len]
    mov byte [rdi + rcx], 0
    call newline
    mov rax, rcx
    ret

; RSI = source name -> copy (max 31 chars) into edit_name.
edit_copy_name:
    push rcx
    push rdi
    lea rdi, [edit_name]
    mov ecx, 31
.l:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rsi
    inc rdi
    loop .l
    mov byte [rdi], 0
.d:
    pop rdi
    pop rcx
    ret

; Load edit_name's contents into EDIT_TEXT (text files only).
edit_load:
    mov qword [edit_total], 0
    lea rsi, [edit_name]
    call fs_find_entry
    test rax, rax
    jz .done
    mov dl, [rax + FS_ENTRY_FLAGS_OFF]
    test dl, FS_FLAG_BINARY
    jnz .done
    mov rsi, rax
    mov rdi, EDIT_TEXT
    call fs_read_entry
    cmp rax, EDIT_CAP
    jbe .store
    mov rax, EDIT_CAP
.store:
    mov [edit_total], rax
.done:
    ret

; Append edit_line + newline to EDIT_TEXT, respecting the cap.
edit_append_line:
    push rsi
    push rdi
    mov rdi, EDIT_TEXT
    add rdi, [edit_total]
    lea rsi, [edit_line]
.l:
    mov al, [rsi]
    test al, al
    jz .nl
    mov rcx, [edit_total]
    cmp rcx, EDIT_CAP - 2
    jae .full
    mov [rdi], al
    inc rdi
    inc rsi
    inc qword [edit_total]
    jmp .l
.nl:
    mov rcx, [edit_total]
    cmp rcx, EDIT_CAP - 1
    jae .full
    mov byte [rdi], 10
    inc qword [edit_total]
.full:
    pop rdi
    pop rsi
    ret

; Print the editor buffer, turning newline bytes into real line breaks.
edit_list:
    push rbx
    push rcx
    mov rbx, EDIT_TEXT
    mov rcx, [edit_total]
    test rcx, rcx
    jz .done
.l:
    mov al, [rbx]
    cmp al, 10
    je .nl
    push rcx
    call print_char
    pop rcx
    jmp .next
.nl:
    push rcx
    call newline
    pop rcx
.next:
    inc rbx
    dec rcx
    jnz .l
.done:
    pop rcx
    pop rbx
    ret

; Save the buffer to edit_name. Returns RAX = 1 on success.
edit_save:
    lea rsi, [edit_name]
    mov rdi, EDIT_TEXT
    mov ecx, [edit_total]
    xor r8d, r8d
    call fs_write_file
    ret

; Drop the last line from the buffer.
edit_del_last:
    push rbx
    push rcx
    mov rcx, [edit_total]
    test rcx, rcx
    jz .done
    dec rcx                      ; trailing newline
.scan:
    test rcx, rcx
    jz .zero
    dec rcx
    mov rbx, EDIT_TEXT
    mov al, [rbx + rcx]
    cmp al, 10
    jne .scan
    inc rcx                      ; keep everything up to and incl. prev newline
    mov [edit_total], rcx
    jmp .done
.zero:
    mov qword [edit_total], 0
.done:
    pop rcx
    pop rbx
    ret

edit_name  times 32 db 0
edit_line  times 256 db 0
edit_len   dq 0
edit_total dq 0
