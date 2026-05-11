cmd_alkan db "alkan", 0

%define BASIC_PROGRAM_CAP 4096
%define BASIC_FILE_CAP    6144
%define BASIC_LINE_CAP    256
%define BASIC_VAR_BYTES   104

do_alkan:
    push rbx

    call basic_clear_program
    call basic_clear_vars
    mov byte [basic_repl_exit], 0

    lea rsi, [arg_buffer]
    call fs_split_args
    test rax, rax
    jz .repl

    mov rsi, rax
    call basic_load_program
    test rax, rax
    jz .done

    call basic_run_program
    jmp .done

.repl:
    call basic_print_banner
    call basic_repl

.done:
    pop rbx
    jmp command_done

basic_print_banner:
    lea rsi, [msg_basic_banner]
    call fs_print_line
    ret

basic_repl:
.loop:
    lea rsi, [msg_basic_prompt]
    call print_string
    call basic_read_line

    lea rsi, [basic_line_buffer]
    call basic_handle_repl_line
    cmp byte [basic_repl_exit], 1
    jne .loop

    mov byte [basic_repl_exit], 0
    ret

basic_handle_repl_line:
    push rbx

    call fs_skip_spaces
    mov rbx, rsi
    cmp byte [rbx], 0
    je .done

    call basic_parse_uint
    test edx, edx
    jz .command

    cmp eax, 1
    jb .bad_line
    cmp eax, 65535
    ja .bad_line

    movzx ebx, ax
    call fs_skip_spaces
    mov ax, bx
    call basic_store_line
    jmp .done

.command:
    mov rsi, rbx

    lea rdi, [kw_help]
    call basic_match_keyword
    test rax, rax
    jnz .help

    lea rdi, [kw_list]
    call basic_match_keyword
    test rax, rax
    jnz .list

    lea rdi, [kw_run]
    call basic_match_keyword
    test rax, rax
    jnz .run

    lea rdi, [kw_new]
    call basic_match_keyword
    test rax, rax
    jnz .new

    lea rdi, [kw_save]
    call basic_match_keyword
    test rax, rax
    jnz .save

    lea rdi, [kw_load]
    call basic_match_keyword
    test rax, rax
    jnz .load

    lea rdi, [kw_exit]
    call basic_match_keyword
    test rax, rax
    jnz .exit

    lea rsi, [msg_basic_unknown]
    call fs_print_line
    jmp .done

.help:
    call basic_print_help
    jmp .done

.list:
    call basic_list_program
    jmp .done

.run:
    call basic_run_program
    jmp .done

.new:
    call basic_clear_program
    call basic_clear_vars
    lea rsi, [msg_basic_cleared]
    call fs_print_line
    jmp .done

.save:
    call fs_skip_spaces
    cmp byte [rsi], 0
    je .save_usage
    call basic_save_program
    jmp .done

.load:
    call fs_skip_spaces
    cmp byte [rsi], 0
    je .load_usage
    call basic_load_program
    jmp .done

.exit:
    mov byte [basic_repl_exit], 1
    jmp .done

.save_usage:
    lea rsi, [msg_basic_save_usage]
    call fs_print_line
    jmp .done

.load_usage:
    lea rsi, [msg_basic_load_usage]
    call fs_print_line
    jmp .done

.bad_line:
    lea rsi, [msg_basic_bad_line]
    call fs_print_line

.done:
    pop rbx
    ret

basic_print_help:
    lea rsi, [msg_basic_help_1]
    call fs_print_line
    lea rsi, [msg_basic_help_2]
    call fs_print_line
    lea rsi, [msg_basic_help_3]
    call fs_print_line
    lea rsi, [msg_basic_help_4]
    call fs_print_line
    lea rsi, [msg_basic_help_5]
    call fs_print_line
    lea rsi, [msg_basic_help_6]
    call fs_print_line
    lea rsi, [msg_basic_help_7]
    call fs_print_line
    ret

basic_read_line:
    push rbx
    push rcx
    push rdi

    mov qword [basic_line_length], 0
    mov byte [basic_line_buffer], 0

.wait_key:
    in al, 0x64
    and al, 1
    jz .wait_key

    in al, 0x60
    test al, 0x80
    jnz .wait_key

    cmp al, 0x1C
    je .enter
    cmp al, 0x0E
    je .backspace

    xor rbx, rbx
    mov bl, al
    lea rcx, [keymap]
    mov al, [rcx + rbx]
    test al, al
    jz .wait_key

    mov rbx, [basic_line_length]
    cmp rbx, BASIC_LINE_CAP - 1
    jae .wait_key

    lea rdi, [basic_line_buffer]
    mov [rdi + rbx], al
    inc qword [basic_line_length]
    mov rbx, [basic_line_length]
    mov byte [rdi + rbx], 0
    call print_char
    jmp .wait_key

.backspace:
    cmp qword [basic_line_length], 0
    je .wait_key

    dec qword [basic_line_length]
    mov rbx, [basic_line_length]
    lea rdi, [basic_line_buffer]
    mov byte [rdi + rbx], 0
    call do_backspace
    jmp .wait_key

.enter:
    call newline
    pop rdi
    pop rcx
    pop rbx
    ret

basic_run_program:
    push rbx
    push r12

    cmp qword [basic_program_size], 0
    jne .start
    lea rsi, [msg_basic_no_program]
    call fs_print_line
    jmp .done

.start:
    call basic_clear_vars
    mov byte [basic_run_stop], 0
    mov word [basic_current_line], 0

    lea rbx, [basic_program_buffer]
    mov r12, [basic_program_size]
    lea r12, [basic_program_buffer + r12]

.line_loop:
    cmp rbx, r12
    jae .done

    mov ax, [rbx]
    mov [basic_current_line], ax

    mov rdi, rbx
    call basic_record_size
    lea rax, [rbx + rax]
    mov [basic_run_next], rax

    lea rsi, [rbx + 2]
    call basic_exec_statement
    cmp byte [basic_run_stop], 1
    je .stop

    mov rbx, [basic_run_next]
    jmp .line_loop

.stop:
    mov byte [basic_run_stop], 0

.done:
    mov word [basic_current_line], 0
    pop r12
    pop rbx
    ret

basic_exec_statement:
    call fs_skip_spaces
    cmp byte [rsi], 0
    je .done

    lea rdi, [kw_rem]
    call basic_match_keyword
    test rax, rax
    jnz .done

    lea rdi, [kw_print]
    call basic_match_keyword
    test rax, rax
    jnz .print

    lea rdi, [kw_goto]
    call basic_match_keyword
    test rax, rax
    jnz .goto

    lea rdi, [kw_if]
    call basic_match_keyword
    test rax, rax
    jnz .if_stmt

    lea rdi, [kw_end]
    call basic_match_keyword
    test rax, rax
    jnz .end_stmt

    lea rdi, [kw_let]
    call basic_match_keyword
    test rax, rax
    jnz .assign

    cmp byte [rsi], 'a'
    jb .syntax
    cmp byte [rsi], 'z'
    ja .syntax

.assign:
    call basic_exec_assignment
    ret

.print:
    call basic_exec_print
    ret

.goto:
    call basic_exec_goto
    ret

.if_stmt:
    call basic_exec_if
    ret

.end_stmt:
    call fs_skip_spaces
    cmp byte [rsi], 0
    jne .syntax
    mov byte [basic_run_stop], 1
    ret

.syntax:
    call basic_runtime_syntax_error

.done:
    ret

basic_exec_print:
    call basic_parse_expr
    test edx, edx
    jz .syntax
    push rax
    call fs_skip_spaces
    cmp byte [rsi], 0
    jne .syntax_pop
    pop rax
    call basic_print_signed_32
    call newline
    ret

.syntax_pop:
    pop rax
.syntax:
    call basic_runtime_syntax_error
    ret

basic_exec_goto:
    call basic_parse_uint
    test edx, edx
    jz .syntax
    push rax
    call fs_skip_spaces
    cmp byte [rsi], 0
    jne .syntax_pop
    pop rax
    cmp eax, 1
    jb .syntax
    cmp eax, 65535
    ja .syntax
    call basic_jump_to_line
    ret

.syntax_pop:
    pop rax
.syntax:
    call basic_runtime_syntax_error
    ret

basic_exec_if:
    push rbx

    call basic_parse_condition
    test edx, edx
    jz .syntax
    mov ebx, eax

    call fs_skip_spaces
    lea rdi, [kw_then]
    call basic_match_keyword
    test rax, rax
    jz .syntax

    call fs_skip_spaces
    lea rdi, [kw_goto]
    call basic_match_keyword

    call basic_parse_uint
    test edx, edx
    jz .syntax
    push rax
    call fs_skip_spaces
    cmp byte [rsi], 0
    jne .syntax_pop

    test ebx, ebx
    jz .done_pop

    pop rax
    cmp eax, 1
    jb .syntax
    cmp eax, 65535
    ja .syntax
    call basic_jump_to_line
    pop rbx
    ret

.done_pop:
    pop rax
    pop rbx
    ret

.syntax_pop:
    pop rax
.syntax:
    pop rbx
    call basic_runtime_syntax_error
    ret

basic_exec_assignment:
    push rbx

    call fs_skip_spaces
    mov bl, [rsi]
    cmp bl, 'a'
    jb .syntax
    cmp bl, 'z'
    ja .syntax
    inc rsi

    call fs_skip_spaces
    cmp byte [rsi], '='
    jne .syntax
    inc rsi

    push rbx
    call basic_parse_expr
    test edx, edx
    jz .syntax_pop

    call fs_skip_spaces
    cmp byte [rsi], 0
    jne .syntax_pop

    pop rbx
    movzx edx, bl
    sub edx, 'a'
    lea rdi, [basic_vars + rdx * 4]
    mov [rdi], eax
    pop rbx
    ret

.syntax_pop:
    pop rbx
.syntax:
    pop rbx
    call basic_runtime_syntax_error
    ret

basic_parse_condition:
    push rbx
    push r12

    call basic_parse_expr
    test edx, edx
    jz .fail
    mov ebx, eax

    call fs_skip_spaces
    xor r12d, r12d

    lea rdi, [kw_eq]
    call basic_match_keyword
    test rax, rax
    jnz .op_eq

    lea rdi, [kw_lt]
    call basic_match_keyword
    test rax, rax
    jnz .op_lt

    cmp byte [rsi], '='
    je .char_eq
    cmp byte [rsi], '<'
    je .char_lt
    jmp .fail

.char_eq:
    inc rsi
    cmp byte [rsi], '='
    jne .op_eq
    inc rsi

.op_eq:
    mov r12d, 1
    jmp .right

.char_lt:
    inc rsi

.op_lt:
    mov r12d, 2

.right:
    call basic_parse_expr
    test edx, edx
    jz .fail

    cmp r12d, 1
    je .do_eq

    cmp ebx, eax
    setl al
    movzx eax, al
    mov edx, 1
    jmp .done

.do_eq:
    cmp ebx, eax
    sete al
    movzx eax, al
    mov edx, 1
    jmp .done

.fail:
    xor eax, eax
    xor edx, edx

.done:
    pop r12
    pop rbx
    ret

basic_parse_expr:
    push rbx

    call basic_parse_unary
    test edx, edx
    jz .fail
    mov ebx, eax

.loop:
    call fs_skip_spaces
    cmp byte [rsi], '+'
    je .add_char
    cmp byte [rsi], '-'
    je .sub_char

    lea rdi, [kw_add]
    call basic_match_keyword
    test rax, rax
    jnz .add_word

    lea rdi, [kw_sub]
    call basic_match_keyword
    test rax, rax
    jnz .sub_word

    mov eax, ebx
    mov edx, 1
    jmp .done

.add_char:
    inc rsi

.add_word:
    call basic_parse_unary
    test edx, edx
    jz .fail
    add ebx, eax
    jmp .loop

.sub_char:
    inc rsi

.sub_word:
    call basic_parse_unary
    test edx, edx
    jz .fail
    sub ebx, eax
    jmp .loop

.fail:
    xor eax, eax
    xor edx, edx

.done:
    pop rbx
    ret

basic_parse_unary:
    call fs_skip_spaces

    lea rdi, [kw_not]
    call basic_match_keyword
    test rax, rax
    jnz .do_not

    cmp byte [rsi], '-'
    je .do_neg
    jmp basic_parse_primary

.do_not:
    call basic_parse_unary
    test edx, edx
    jz .fail
    test eax, eax
    setz al
    movzx eax, al
    mov edx, 1
    ret

.do_neg:
    inc rsi
    call basic_parse_unary
    test edx, edx
    jz .fail
    neg eax
    mov edx, 1
    ret

.fail:
    xor eax, eax
    xor edx, edx
    ret

basic_parse_primary:
    call fs_skip_spaces

    mov al, [rsi]
    cmp al, '0'
    jb .check_var
    cmp al, '9'
    jbe .number

.check_var:
    cmp al, 'a'
    jb .fail
    cmp al, 'z'
    ja .fail

    movzx edx, al
    sub edx, 'a'
    lea rdi, [basic_vars + rdx * 4]
    mov eax, [rdi]
    inc rsi
    mov edx, 1
    ret

.number:
    call basic_parse_uint
    ret

.fail:
    xor eax, eax
    xor edx, edx
    ret

basic_parse_uint:
    push rbx
    push rcx

    call fs_skip_spaces
    xor eax, eax
    xor edx, edx

.loop:
    mov bl, [rsi]
    cmp bl, '0'
    jb .done
    cmp bl, '9'
    ja .done
    imul eax, eax, 10
    movzx ecx, bl
    sub ecx, '0'
    add eax, ecx
    inc rsi
    mov edx, 1
    jmp .loop

.done:
    pop rcx
    pop rbx
    ret

basic_jump_to_line:
    push rbx

    mov bx, ax
    mov ax, bx
    call basic_find_line_slot
    test edx, edx
    jz .missing
    mov [basic_run_next], rax
    pop rbx
    ret

.missing:
    movzx eax, bx
    pop rbx
    call basic_runtime_missing_line
    ret

basic_runtime_syntax_error:
    mov byte [basic_run_stop], 1
    lea rsi, [msg_basic_syntax]
    call print_string
    movzx eax, word [basic_current_line]
    call print_dec_32
    call newline
    ret

basic_runtime_missing_line:
    push rax
    mov byte [basic_run_stop], 1
    lea rsi, [msg_basic_missing_line]
    call print_string
    pop rax
    call print_dec_32
    call newline
    ret

basic_list_program:
    push rbx
    push r12

    cmp qword [basic_program_size], 0
    jne .start
    lea rsi, [msg_basic_no_program]
    call fs_print_line
    jmp .done

.start:
    lea rbx, [basic_program_buffer]
    mov r12, [basic_program_size]
    lea r12, [basic_program_buffer + r12]

.loop:
    cmp rbx, r12
    jae .done

    movzx eax, word [rbx]
    call print_dec_32
    mov al, ' '
    call print_char
    lea rsi, [rbx + 2]
    call fs_print_line

    mov rdi, rbx
    call basic_record_size
    add rbx, rax
    jmp .loop

.done:
    pop r12
    pop rbx
    ret

basic_save_program:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi
    call fs_ensure_ready
    test rax, rax
    jz .fail

    lea rbx, [basic_program_buffer]
    mov r13, [basic_program_size]
    lea r13, [basic_program_buffer + r13]
    lea r14, [basic_file_buffer]
    mov r15d, BASIC_FILE_CAP - 1

.line_loop:
    cmp rbx, r13
    jae .finish

    movzx eax, word [rbx]
    call basic_u32_to_string
    cmp ecx, r15d
    ja .too_large
    mov edx, ecx
    mov rdi, r14
    rep movsb
    mov r14, rdi
    sub r15d, edx

    cmp r15d, 1
    jb .too_large
    mov byte [r14], ' '
    inc r14
    dec r15d

    lea rsi, [rbx + 2]
    call fs_string_length
    mov edx, eax
    cmp edx, r15d
    ja .too_large
    mov ecx, edx
    mov rdi, r14
    rep movsb
    mov r14, rdi
    sub r15d, edx

    cmp r15d, 1
    jb .too_large
    mov byte [r14], 10
    inc r14
    dec r15d

    mov rdi, rbx
    call basic_record_size
    add rbx, rax
    jmp .line_loop

.finish:
    mov byte [r14], 0
    lea rax, [basic_file_buffer]
    mov ecx, r14d
    sub ecx, eax

    mov rsi, r12
    lea rdi, [basic_file_buffer]
    xor r8d, r8d
    call fs_write_file
    test rax, rax
    jz .fail

    lea rsi, [msg_basic_saved]
    call fs_print_line
    mov eax, 1
    jmp .done

.too_large:
    lea rsi, [msg_basic_too_large]
    call fs_print_line

.fail:
    xor eax, eax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

basic_load_program:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rsi
    call fs_ensure_ready
    test rax, rax
    jz .fail

    mov rsi, r12
    call fs_find_entry
    test rax, rax
    jz .not_found

    mov rdi, rax
    call basic_read_file_into_buffer
    test rax, rax
    jz .fail

    call basic_clear_program
    lea rsi, [basic_file_buffer]

.line_loop:
    call fs_skip_spaces
    cmp byte [rsi], 13
    je .skip_newline
    cmp byte [rsi], 10
    je .skip_newline
    cmp byte [rsi], 0
    je .loaded

    call basic_parse_uint
    test edx, edx
    jz .bad_file
    cmp eax, 1
    jb .bad_file
    cmp eax, 65535
    ja .bad_file
    mov r13d, eax

    call fs_skip_spaces
    mov rbx, rsi
    mov r14, rsi

.scan_line:
    mov al, [r14]
    cmp al, 0
    je .end_of_line
    cmp al, 13
    je .end_of_line
    cmp al, 10
    je .end_of_line
    inc r14
    jmp .scan_line

.end_of_line:
    mov r12, r14
    mov al, [r14]
    cmp al, 13
    jne .check_lf
    inc r12
    cmp byte [r12], 10
    jne .next_ready
    inc r12
    jmp .next_ready

.check_lf:
    cmp al, 10
    jne .next_ready
    inc r12

.next_ready:
    push rax
    mov byte [r14], 0
    mov ax, r13w
    mov rsi, rbx
    call basic_store_line
    test rax, rax
    jz .bad_file_pop

    pop rax
    cmp al, 0
    je .loaded
    mov rsi, r12

.skip_newline:
    cmp byte [rsi], 13
    jne .skip_lf
    inc rsi
.skip_lf:
    cmp byte [rsi], 10
    jne .line_loop
    inc rsi
    jmp .line_loop

.loaded:
    lea rsi, [msg_basic_loaded]
    call fs_print_line
    mov eax, 1
    jmp .done

.not_found:
    lea rsi, [msg_fs_not_found]
    call fs_print_line
    jmp .fail

.bad_file_pop:
    pop rax

.bad_file:
    call basic_clear_program
    lea rsi, [msg_basic_bad_file]
    call fs_print_line

.fail:
    xor eax, eax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

basic_read_file_into_buffer:
    push rbx
    push rcx
    push rdx
    push r8
    push r9

    mov al, [rdi + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_BINARY
    jz .text_ok
    lea rsi, [msg_basic_text_only]
    call fs_print_line
    jmp .fail

.text_ok:
    mov edx, [rdi + FS_ENTRY_SIZE_OFF]
    cmp edx, BASIC_FILE_CAP - 1
    jae .too_large

    mov r8d, [rdi + FS_ENTRY_START_OFF]
    lea r9, [basic_file_buffer]
    test edx, edx
    jz .empty

.sector_loop:
    mov eax, r8d
    mov ecx, 1
    lea rdi, [fs_sector_buffer]
    call ata_read_sectors
    test rax, rax
    jz .disk_error

    mov ecx, edx
    cmp ecx, 512
    jbe .copy_chunk
    mov ecx, 512

.copy_chunk:
    mov ebx, ecx
    lea rsi, [fs_sector_buffer]
    mov rdi, r9
    rep movsb
    mov r9, rdi
    sub edx, ebx
    inc r8d
    test edx, edx
    jnz .sector_loop

.empty:
    mov byte [r9], 0
    mov eax, 1
    jmp .done

.too_large:
    lea rsi, [msg_basic_file_too_large]
    call fs_print_line
    jmp .fail

.disk_error:
    lea rsi, [msg_fs_disk_error]
    call fs_print_line

.fail:
    xor eax, eax

.done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

basic_store_line:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12w, ax
    mov r13, rsi
    call fs_string_length
    mov r14d, eax

    mov ax, r12w
    call basic_find_line_slot
    mov r15, rax

    test edx, edx
    jz .insert

    mov rdi, r15
    call basic_record_size
    mov ecx, eax
    mov rdi, r15
    call basic_shift_left

.insert:
    test r14d, r14d
    jz .success

    mov eax, r14d
    add eax, 3
    mov ecx, eax
    mov rdi, r15
    call basic_shift_right
    test rax, rax
    jz .fail

    mov word [r15], r12w
    lea rdi, [r15 + 2]
    mov rsi, r13
    mov ecx, r14d
    rep movsb
    mov byte [rdi], 0

.success:
    mov eax, 1
    jmp .done

.fail:
    xor eax, eax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

basic_find_line_slot:
    push rbx
    push r8
    push r9

    movzx r8d, ax
    lea rbx, [basic_program_buffer]
    mov r9, [basic_program_size]
    lea r9, [basic_program_buffer + r9]

.loop:
    cmp rbx, r9
    jae .insert_here

    movzx eax, word [rbx]
    cmp eax, r8d
    je .exact
    ja .insert_here

    mov rdi, rbx
    call basic_record_size
    add rbx, rax
    jmp .loop

.exact:
    mov rax, rbx
    mov edx, 1
    jmp .done

.insert_here:
    mov rax, rbx
    xor edx, edx

.done:
    pop r9
    pop r8
    pop rbx
    ret

basic_record_size:
    lea rsi, [rdi + 2]
    call fs_string_length
    add eax, 3
    ret

basic_shift_right:
    push rbx
    push rcx
    push rdx
    push r8

    mov rdx, [basic_program_size]
    mov r8d, ecx
    mov eax, BASIC_PROGRAM_CAP
    sub eax, edx
    cmp eax, r8d
    jb .too_large

    lea rbx, [basic_program_buffer + rdx]
    mov rax, rbx
    add rax, r8

.copy_loop:
    cmp rbx, rdi
    jbe .done_copy
    dec rbx
    dec rax
    mov dl, [rbx]
    mov [rax], dl
    jmp .copy_loop

.done_copy:
    add qword [basic_program_size], r8
    mov eax, 1
    jmp .done

.too_large:
    lea rsi, [msg_basic_too_large]
    call fs_print_line
    xor eax, eax

.done:
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

basic_shift_left:
    push rbx
    push rcx
    push rsi
    push rdx

    mov rdx, rcx
    lea rsi, [rdi + rdx]
    mov rbx, [basic_program_size]
    lea rbx, [basic_program_buffer + rbx]

.copy_loop:
    cmp rsi, rbx
    jae .done_copy
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .copy_loop

.done_copy:
    sub qword [basic_program_size], rdx
    pop rdx
    pop rsi
    pop rcx
    pop rbx
    ret

basic_clear_program:
    mov qword [basic_program_size], 0
    ret

basic_clear_vars:
    lea rdi, [basic_vars]
    mov ecx, BASIC_VAR_BYTES
    call fs_memzero
    ret

basic_match_keyword:
    push rbx
    mov rbx, rsi

.cmp_loop:
    mov al, [rdi]
    test al, al
    jz .end_kw
    cmp al, [rsi]
    jne .fail
    inc rdi
    inc rsi
    jmp .cmp_loop

.end_kw:
    mov al, [rsi]
    test al, al
    jz .success
    cmp al, ' '
    je .success
    jmp .fail

.success:
    mov eax, 1
    pop rbx
    ret

.fail:
    mov rsi, rbx
    xor eax, eax
    pop rbx
    ret

basic_print_signed_32:
    push rax
    cmp eax, 0
    jge .positive
    mov al, '-'
    call print_char
    pop rax
    neg eax
    call print_dec_32
    ret

.positive:
    pop rax
    call print_dec_32
    ret

basic_u32_to_string:
    push rax
    push rbx
    push rdx
    push r8

    lea r8, [basic_num_buffer + 11]
    mov ebx, 10

    cmp eax, 0
    jne .convert
    dec r8
    mov byte [r8], '0'
    mov rsi, r8
    mov ecx, 1
    jmp .done

.convert:
    mov eax, eax

.loop:
    xor edx, edx
    div ebx
    add dl, '0'
    dec r8
    mov [r8], dl
    test eax, eax
    jnz .loop

    mov rsi, r8
    lea rax, [basic_num_buffer + 11]
    sub rax, r8
    mov ecx, eax

.done:
    pop r8
    pop rdx
    pop rbx
    pop rax
    ret

kw_help  db "help", 0
kw_list  db "list", 0
kw_run   db "run", 0
kw_new   db "new", 0
kw_save  db "save", 0
kw_load  db "load", 0
kw_exit  db "exit", 0
kw_print db "print", 0
kw_goto  db "goto", 0
kw_if    db "if", 0
kw_then  db "then", 0
kw_end   db "end", 0
kw_let   db "let", 0
kw_rem   db "rem", 0
kw_not   db "not", 0
kw_add   db "add", 0
kw_sub   db "sub", 0
kw_eq    db "eq", 0
kw_lt    db "lt", 0

msg_basic_banner        db "[alkan 1.0] line editor ready. type help.", 0
msg_basic_prompt        db "alkan> ", 0
msg_basic_unknown       db "[alkan 1.0] unknown command.", 0
msg_basic_cleared       db "[alkan 1.0] program cleared.", 0
msg_basic_saved         db "[alkan 1.0] program saved.", 0
msg_basic_loaded        db "[alkan 1.0] program loaded.", 0
msg_basic_no_program    db "[alkan 1.0] no program.", 0
msg_basic_bad_line      db "[alkan 1.0] line numbers are 1 to 65535.", 0
msg_basic_save_usage    db "[alkan 1.0] usage: save <name>", 0
msg_basic_load_usage    db "[alkan 1.0] usage: load <name>", 0
msg_basic_too_large     db "[alkan 1.0] program is too large.", 0
msg_basic_file_too_large db "[alkan 1.0] file is too large for alkan.", 0
msg_basic_text_only     db "[alkan 1.0] alkan only loads text files.", 0
msg_basic_bad_file      db "[alkan 1.0] invalid alkan file.", 0
msg_basic_syntax        db "[alkan 1.0] syntax error on line ", 0
msg_basic_missing_line  db "[alkan 1.0] missing target line ", 0
msg_basic_help_1        db "line form: 10 a = 5", 0
msg_basic_help_2        db "math: a = a add 1   or   a = a - 1", 0
msg_basic_help_3        db "print: 20 print a", 0
msg_basic_help_4        db "branch: 30 if a lt 10 then 20", 0
msg_basic_help_5        db "equal: 40 if a = 10 then goto 60", 0
msg_basic_help_6        db "editor: list  run  save demo  load demo  new  exit", 0
msg_basic_help_7        db "shell run: alkan demo", 0

basic_line_length dq 0
basic_program_size dq 0
basic_run_next dq 0
basic_current_line dw 0
basic_run_stop db 0
basic_repl_exit db 0
basic_num_buffer times 12 db 0
basic_line_buffer times BASIC_LINE_CAP db 0
basic_program_buffer times BASIC_PROGRAM_CAP db 0
basic_file_buffer times BASIC_FILE_CAP db 0
basic_vars times 26 dd 0
