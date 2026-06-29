; alkan32.asm — KoelOS 32-bit port of the Alkan BASIC interpreter.
; Ported from apps/alkan.asm. Conventions for this file:
;   ESI = parse cursor (threaded through the parser, advanced by callees)
;   EBX/EDI/EBP = callee-saved locals (preserved by push/pop)
;   EAX/ECX/EDX = scratch / return
; 64-bit had 5 callee-saved regs; 32-bit has 3, so non-recursive functions
; spill extra locals into named memory temps. Only basic_parse_call_expr is
; recursive (CALL evaluates a module expression that may CALL again); it uses
; an EBP stack frame so each recursion level keeps its own locals.
;
; Reuses kernel32/fs32: print_string/print_char/newline/do_backspace/
; clear_screen/print_dec/strcmp/kbd_translate, and fs_split_args/fs_skip_spaces/
; fs_print_line/fs_strlen/fs_memzero/fs_ensure_ready/fs_find_entry/fs_write_file
; (flags via [fw_flags])/ata_read_sectors/fs_sector_buffer/FS_ENTRY_* .
; ============================================================================

%define BASIC_PROGRAM_CAP 4096
%define BASIC_FILE_CAP    6144
%define BASIC_LINE_CAP    256
%define BASIC_VAR_BYTES   104
%define BASIC_CALL_DEPTH  4
%define BASIC_CALL_FILE_CAP 4096
%define BASIC_CALL_MAX_ARGS 8
%define BASIC_CALL_NAME_CAP 32

do_alkan:
    call basic_clear_program
    call basic_clear_vars
    mov byte [basic_repl_exit], 0

    mov esi, [arg_ptr]
    call fs_split_args
    test eax, eax
    jz .repl

    mov esi, eax
    call basic_load_program
    test eax, eax
    jz .done
    call basic_run_program
    jmp .done

.repl:
    mov esi, msg_basic_banner
    call fs_print_line
    call basic_repl

.done:
    jmp command_done

basic_repl:
.loop:
    mov esi, msg_basic_prompt
    call print_string
    call basic_read_line
    mov esi, basic_line_buffer
    call basic_handle_repl_line
    cmp byte [basic_repl_exit], 1
    jne .loop
    mov byte [basic_repl_exit], 0
    ret

basic_handle_repl_line:
    push ebx
    call fs_skip_spaces
    mov ebx, esi
    cmp byte [ebx], 0
    je .done
    mov byte [basic_run_stop], 0

    call basic_parse_uint
    test edx, edx
    jz .command
    cmp eax, 1
    jb .bad_line
    cmp eax, 65535
    ja .bad_line
    movzx ebx, ax
    call fs_skip_spaces
    mov eax, ebx
    call basic_store_line
    jmp .done

.command:
    mov esi, ebx
    mov edi, kw_help
    call basic_match_keyword
    test eax, eax
    jnz .help
    mov edi, kw_list
    call basic_match_keyword
    test eax, eax
    jnz .list
    mov edi, kw_run
    call basic_match_keyword
    test eax, eax
    jnz .run
    mov edi, kw_new
    call basic_match_keyword
    test eax, eax
    jnz .new
    mov edi, kw_save
    call basic_match_keyword
    test eax, eax
    jnz .save
    mov edi, kw_load
    call basic_match_keyword
    test eax, eax
    jnz .load
    mov edi, kw_exit
    call basic_match_keyword
    test eax, eax
    jnz .exit
    mov esi, msg_basic_unknown
    call fs_print_line
    jmp .done

.help:
    call basic_print_help_command
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
    mov esi, msg_basic_cleared
    call fs_print_line
    jmp .done
.save:
    call fs_skip_spaces
    cmp byte [esi], 0
    je .save_usage
    call basic_save_program
    jmp .done
.load:
    call fs_skip_spaces
    cmp byte [esi], 0
    je .load_usage
    call basic_load_program
    jmp .done
.exit:
    mov byte [basic_repl_exit], 1
    jmp .done
.save_usage:
    mov esi, msg_basic_save_usage
    call fs_print_line
    jmp .done
.load_usage:
    mov esi, msg_basic_load_usage
    call fs_print_line
    jmp .done
.bad_line:
    mov esi, msg_basic_bad_line
    call fs_print_line
.done:
    pop ebx
    ret

; ----------------------------------------------------------------------------
; Help (paged)
; ----------------------------------------------------------------------------
basic_print_help:
    call basic_print_help_page_1
    call basic_help_wait_more
    test eax, eax
    jz .done
    call basic_print_help_page_2
    call basic_help_wait_more
    test eax, eax
    jz .done
    call basic_print_help_page_3
    call basic_help_wait_more
    test eax, eax
    jz .done
    call basic_print_help_page_4
    call basic_help_wait_done
.done:
    ret

basic_print_help_command:
    call fs_skip_spaces
    cmp byte [esi], 0
    je basic_print_help
    mov edi, kw_editor
    call basic_match_keyword
    test eax, eax
    jnz .page_1
    mov edi, kw_flow
    call basic_match_keyword
    test eax, eax
    jnz .page_2
    mov edi, kw_loops
    call basic_match_keyword
    test eax, eax
    jnz .page_3
    mov edi, kw_memory
    call basic_match_keyword
    test eax, eax
    jnz .page_4
    mov edi, kw_funcs
    call basic_match_keyword
    test eax, eax
    jnz .page_4
    mov edi, kw_functions
    call basic_match_keyword
    test eax, eax
    jnz .page_4
    mov edi, kw_func
    call basic_match_keyword
    test eax, eax
    jnz .page_4
    mov esi, msg_basic_help_topics
    call fs_print_line
    ret
.page_1:
    call basic_print_help_page_1
    call basic_help_wait_done
    ret
.page_2:
    call basic_print_help_page_2
    call basic_help_wait_done
    ret
.page_3:
    call basic_print_help_page_3
    call basic_help_wait_done
    ret
.page_4:
    call basic_print_help_page_4
    call basic_help_wait_done
    ret

basic_print_help_page_1:
    call clear_screen
    mov esi, msg_basic_help_page_1
    call fs_print_line
    mov esi, msg_basic_help_1
    call fs_print_line
    mov esi, msg_basic_help_29
    call fs_print_line
    mov esi, msg_basic_help_2
    call fs_print_line
    mov esi, msg_basic_help_3
    call fs_print_line
    mov esi, msg_basic_help_4
    call fs_print_line
    mov esi, msg_basic_help_5
    call fs_print_line
    mov esi, msg_basic_help_6
    call fs_print_line
    mov esi, msg_basic_help_7
    call fs_print_line
    ret

basic_print_help_page_2:
    call clear_screen
    mov esi, msg_basic_help_page_2
    call fs_print_line
    mov esi, msg_basic_help_8
    call fs_print_line
    mov esi, msg_basic_help_9
    call fs_print_line
    mov esi, msg_basic_help_10
    call fs_print_line
    mov esi, msg_basic_help_11
    call fs_print_line
    mov esi, msg_basic_help_12
    call fs_print_line
    mov esi, msg_basic_help_13
    call fs_print_line
    mov esi, msg_basic_help_14
    call fs_print_line
    mov esi, msg_basic_help_15
    call fs_print_line
    ret

basic_print_help_page_3:
    call clear_screen
    mov esi, msg_basic_help_page_3
    call fs_print_line
    mov esi, msg_basic_help_16
    call fs_print_line
    mov esi, msg_basic_help_17
    call fs_print_line
    mov esi, msg_basic_help_18
    call fs_print_line
    mov esi, msg_basic_help_19
    call fs_print_line
    mov esi, msg_basic_help_24
    call fs_print_line
    mov esi, msg_basic_help_26
    call fs_print_line
    ret

basic_print_help_page_4:
    call clear_screen
    mov esi, msg_basic_help_page_4
    call fs_print_line
    mov esi, msg_basic_help_20
    call fs_print_line
    mov esi, msg_basic_help_21
    call fs_print_line
    mov esi, msg_basic_help_22
    call fs_print_line
    mov esi, msg_basic_help_23
    call fs_print_line
    mov esi, msg_basic_help_25
    call fs_print_line
    mov esi, msg_basic_help_27
    call fs_print_line
    mov esi, msg_basic_help_28
    call fs_print_line
    ret

basic_help_wait_more:
    mov esi, msg_basic_help_more
    call fs_print_line
    call basic_help_read_key
    cmp al, 1
    je .exit
    mov eax, 1
    ret
.exit:
    xor eax, eax
    ret

basic_help_wait_done:
    mov esi, msg_basic_help_done
    call fs_print_line
    call basic_help_read_key
    ret

basic_help_read_key:
.wait:
    in al, 0x64
    test al, 1
    jz .wait
    in al, 0x60
    test al, 0x80
    jnz .wait
    ret

; ----------------------------------------------------------------------------
; Line input + run control
; ----------------------------------------------------------------------------
basic_read_line:
    push ebx
    mov dword [basic_line_length], 0
    mov byte [basic_line_buffer], 0
.wait_key:
    in al, 0x64
    and al, 1
    jz .wait_key
    in al, 0x60
    cmp al, 0x1C
    je .enter
    cmp al, 0x0E
    je .backspace
    call kbd_translate
    test al, al
    jz .wait_key
    mov ebx, [basic_line_length]
    cmp ebx, BASIC_LINE_CAP - 1
    jae .wait_key
    mov [basic_line_buffer + ebx], al
    inc dword [basic_line_length]
    mov ebx, [basic_line_length]
    mov byte [basic_line_buffer + ebx], 0
    call print_char
    jmp .wait_key
.backspace:
    cmp dword [basic_line_length], 0
    je .wait_key
    dec dword [basic_line_length]
    mov ebx, [basic_line_length]
    mov byte [basic_line_buffer + ebx], 0
    call do_backspace
    jmp .wait_key
.enter:
    call newline
    pop ebx
    ret

basic_poll_escape:
    in al, 0x64
    test al, 1
    jz .done
    in al, 0x60
    cmp al, 1
    jne .done
    mov byte [basic_run_stop], 1
    mov esi, msg_basic_stopped
    call fs_print_line
.done:
    ret

basic_run_program:
    push ebx
    cmp dword [basic_program_size], 0
    jne .start
    mov esi, msg_basic_no_program
    call fs_print_line
    jmp .done
.start:
    call basic_clear_vars
    mov byte [basic_run_stop], 0
    mov word [basic_current_line], 0
    mov ebx, basic_program_buffer
    mov eax, [basic_program_size]
    add eax, basic_program_buffer
    mov [br_end], eax              ; end ptr in memory (EDI is scratch for callees)
.line_loop:
    cmp ebx, [br_end]
    jae .done
    call basic_poll_escape
    cmp byte [basic_run_stop], 1
    je .stop
    mov ax, [ebx]
    mov [basic_current_line], ax
    mov edi, ebx
    call basic_record_size         ; EAX = record size
    lea eax, [ebx + eax]
    mov [basic_run_next], eax
    lea esi, [ebx + 2]
    call basic_exec_statement
    cmp byte [basic_run_stop], 1
    je .stop
    mov ebx, [basic_run_next]
    jmp .line_loop
.stop:
    mov byte [basic_run_stop], 0
.done:
    mov word [basic_current_line], 0
    pop ebx
    ret

basic_exec_statement:
    call fs_skip_spaces
    cmp byte [esi], 0
    je .done
    mov edi, kw_rem
    call basic_match_keyword
    test eax, eax
    jnz .done
    mov edi, kw_print
    call basic_match_keyword
    test eax, eax
    jnz .print
    mov edi, kw_goto
    call basic_match_keyword
    test eax, eax
    jnz .goto
    mov edi, kw_if
    call basic_match_keyword
    test eax, eax
    jnz .if_stmt
    mov edi, kw_end
    call basic_match_keyword
    test eax, eax
    jnz .end_stmt
    mov edi, kw_call
    call basic_match_keyword
    test eax, eax
    jnz .call_stmt
    mov edi, kw_intercept
    call basic_match_keyword
    test eax, eax
    jnz .intercept_stmt
    mov edi, kw_let
    call basic_match_keyword
    test eax, eax
    jnz .assign
    cmp byte [esi], 'a'
    jb .syntax
    cmp byte [esi], 'z'
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
    cmp byte [esi], 0
    jne .syntax
    mov byte [basic_run_stop], 1
    ret
.call_stmt:
    call basic_exec_call
    ret
.intercept_stmt:
    call basic_exec_intercept
    ret
.syntax:
    call basic_runtime_syntax_error
.done:
    ret

basic_exec_print:
    call basic_parse_expr
    test edx, edx
    jz .syntax
    push eax
    call fs_skip_spaces
    cmp byte [esi], 0
    jne .syntax_pop
    pop eax
    call basic_print_signed_32
    call newline
    ret
.syntax_pop:
    pop eax
.syntax:
    call basic_runtime_syntax_error
    ret

basic_exec_call:
    call basic_parse_call_expr
    test edx, edx
    jz .syntax
    call fs_skip_spaces
    cmp byte [esi], 0
    jne .syntax
    cmp byte [basic_run_stop], 1
    je .done
    call basic_print_signed_32
    call newline
.done:
    ret
.syntax:
    call basic_runtime_syntax_error
    ret

basic_exec_intercept:
    push ebx
    call basic_parse_expr
    test edx, edx
    jz .syntax
    test eax, eax
    js .range
    mov ebx, eax
    call fs_skip_spaces
    cmp byte [esi], ','
    jne .value
    inc esi
.value:
    call basic_parse_expr
    test edx, edx
    jz .syntax
    call fs_skip_spaces
    cmp byte [esi], 0
    jne .syntax
    cmp eax, 0
    jl .range
    cmp eax, 255
    jg .range
    mov [ebx], al
    pop ebx
    ret
.range:
    pop ebx
    mov esi, msg_basic_intercept_range
    call basic_runtime_set_error
    ret
.syntax:
    pop ebx
    call basic_runtime_syntax_error
    ret

basic_exec_goto:
    call basic_parse_uint
    test edx, edx
    jz .syntax
    push eax
    call fs_skip_spaces
    cmp byte [esi], 0
    jne .syntax_pop
    pop eax
    cmp eax, 1
    jb .syntax
    cmp eax, 65535
    ja .syntax
    call basic_jump_to_line
    ret
.syntax_pop:
    pop eax
.syntax:
    call basic_runtime_syntax_error
    ret

basic_exec_if:
    push ebx
    call basic_parse_condition
    test edx, edx
    jz .syntax
    mov ebx, eax
    call fs_skip_spaces
    mov edi, kw_then
    call basic_match_keyword
    test eax, eax
    jz .syntax
    call fs_skip_spaces
    mov edi, kw_goto
    call basic_match_keyword
    call basic_parse_uint
    test edx, edx
    jz .syntax
    push eax
    call fs_skip_spaces
    cmp byte [esi], 0
    jne .syntax_pop
    test ebx, ebx
    jz .done_pop
    pop eax
    cmp eax, 1
    jb .syntax
    cmp eax, 65535
    ja .syntax
    call basic_jump_to_line
    pop ebx
    ret
.done_pop:
    pop eax
    pop ebx
    ret
.syntax_pop:
    pop eax
.syntax:
    pop ebx
    call basic_runtime_syntax_error
    ret

basic_exec_assignment:
    push ebx
    call fs_skip_spaces
    mov al, [esi]
    call basic_var_char_to_index
    test eax, eax
    jz .syntax
    mov bl, dl
    inc esi
    call fs_skip_spaces
    cmp byte [esi], '='
    jne .syntax
    inc esi
    push ebx
    call basic_parse_expr
    test edx, edx
    jz .syntax_pop
    call fs_skip_spaces
    cmp byte [esi], 0
    jne .syntax_pop
    pop ebx
    movzx edx, bl
    mov [basic_vars + edx*4], eax
    pop ebx
    ret
.syntax_pop:
    pop ebx
.syntax:
    pop ebx
    call basic_runtime_syntax_error
    ret

; ----------------------------------------------------------------------------
; Expression / condition parser
; ----------------------------------------------------------------------------
basic_parse_condition:
    push ebx
    push edi
    call basic_parse_expr
    test edx, edx
    jz .fail
    mov ebx, eax
    call fs_skip_spaces
    xor edi, edi
    push edi
    mov edi, kw_eq
    call basic_match_keyword
    pop edi
    test eax, eax
    jnz .op_eq
    push edi
    mov edi, kw_lt
    call basic_match_keyword
    pop edi
    test eax, eax
    jnz .op_lt
    cmp byte [esi], '='
    je .char_eq
    cmp byte [esi], '<'
    je .char_lt
    jmp .fail
.char_eq:
    inc esi
    cmp byte [esi], '='
    jne .op_eq
    inc esi
.op_eq:
    mov dword [cond_op], 1
    jmp .right
.char_lt:
    inc esi
.op_lt:
    mov dword [cond_op], 2
.right:
    call basic_parse_expr           ; clobbers EDI, so operator lives in memory
    test edx, edx
    jz .fail
    cmp dword [cond_op], 1
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
    pop edi
    pop ebx
    ret

basic_parse_expr:
    push ebx
    call basic_parse_unary
    test edx, edx
    jz .fail
    mov ebx, eax
.loop:
    call fs_skip_spaces
    cmp byte [esi], '+'
    je .add_char
    cmp byte [esi], '-'
    je .sub_char
    mov edi, kw_add
    call basic_match_keyword
    test eax, eax
    jnz .add_word
    mov edi, kw_sub
    call basic_match_keyword
    test eax, eax
    jnz .sub_word
    mov eax, ebx
    mov edx, 1
    jmp .done
.add_char:
    inc esi
.add_word:
    call basic_parse_unary
    test edx, edx
    jz .fail
    add ebx, eax
    jmp .loop
.sub_char:
    inc esi
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
    pop ebx
    ret

basic_parse_unary:
    call fs_skip_spaces
    mov edi, kw_not
    call basic_match_keyword
    test eax, eax
    jnz .do_not
    cmp byte [esi], '-'
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
    inc esi
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
    mov edi, kw_call
    call basic_match_keyword
    test eax, eax
    jnz .call_expr
    mov al, [esi]
    cmp al, '0'
    jb .check_var
    cmp al, '9'
    jbe .number
.check_var:
    call basic_var_char_to_index
    test eax, eax
    jz .fail
    mov eax, [basic_vars + edx*4]
    inc esi
    mov edx, 1
    ret
.call_expr:
    call basic_parse_call_expr
    ret
.number:
    call basic_parse_uint
    ret
.fail:
    xor eax, eax
    xor edx, edx
    ret

; ----------------------------------------------------------------------------
; External module CALL (recursive): uses an EBP stack frame for per-level state
;   [ebp-4]  depth index      [ebp-8]  arg-stack ptr     [ebp-12] arg count
;   [ebp-16] saved-vars ptr   [ebp-20] file-buf ptr      [ebp-24] entry/expr ptr
; ----------------------------------------------------------------------------
basic_parse_call_expr:
    push ebp
    mov ebp, esp
    sub esp, 24
    push ebx
    push edi

    call fs_skip_spaces
    movzx eax, byte [basic_call_depth]
    mov [ebp-4], eax
    cmp eax, BASIC_CALL_DEPTH
    jae .depth_error
    inc byte [basic_call_depth]

    mov edi, basic_call_name_buffer
    mov ecx, BASIC_CALL_NAME_CAP
    call basic_parse_name_token
    test eax, eax
    jz .syntax_fail
    cmp byte [esi], '.'
    jne .syntax_fail
    inc esi
    mov edi, basic_call_func_buffer
    mov ecx, BASIC_CALL_NAME_CAP
    call basic_parse_name_token
    test eax, eax
    jz .syntax_fail
    call fs_skip_spaces
    cmp byte [esi], '('
    jne .syntax_fail
    inc esi

    mov eax, [ebp-4]
    imul eax, BASIC_CALL_MAX_ARGS * 4
    add eax, basic_call_arg_stack
    mov [ebp-8], eax
    mov dword [ebp-12], 0
.arg_loop:
    call fs_skip_spaces
    cmp byte [esi], ')'
    je .args_done
    mov eax, [ebp-12]
    cmp eax, BASIC_CALL_MAX_ARGS
    jae .arg_limit
    call basic_parse_expr
    test edx, edx
    jz .syntax_fail
    mov ecx, [ebp-12]
    mov edx, [ebp-8]
    mov [edx + ecx*4], eax
    inc dword [ebp-12]
    call fs_skip_spaces
    cmp byte [esi], ','
    jne .arg_loop
    inc esi
    jmp .arg_loop
.args_done:
    inc esi

    mov edi, basic_call_name_buffer
    call basic_append_alk_extension
    test eax, eax
    jz .name_too_long
    call fs_ensure_ready
    test eax, eax
    jz .reported_fail
    mov esi, basic_call_name_buffer
    call fs_find_entry
    test eax, eax
    jz .file_missing
    mov [ebp-24], eax              ; entry ptr

    mov eax, [ebp-4]
    imul eax, BASIC_CALL_FILE_CAP
    add eax, basic_call_file_stack
    mov [ebp-20], eax             ; file buffer ptr
    mov edi, [ebp-24]             ; entry
    mov esi, eax                  ; dest buffer
    mov ecx, BASIC_CALL_FILE_CAP
    call basic_read_file_into_buffer
    test eax, eax
    jz .reported_fail

    mov ecx, [ebp-12]             ; arg count
    mov esi, [ebp-20]             ; file text
    mov edi, basic_call_func_buffer
    call basic_find_external_function
    cmp edx, 1
    je .have_expr
    cmp edx, 2
    je .arg_mismatch
    cmp edx, 3
    je .bad_function
    jmp .func_missing

.have_expr:
    mov [ebp-24], eax             ; expr ptr (function body)
    mov eax, [ebp-4]
    imul eax, BASIC_VAR_BYTES
    add eax, basic_call_saved_vars
    mov [ebp-16], eax             ; saved-vars ptr
    mov edi, eax
    mov esi, basic_vars
    mov ecx, BASIC_VAR_BYTES
    rep movsb
    call basic_clear_vars

    xor ecx, ecx
.bind_loop:
    cmp ecx, [ebp-12]
    jae .eval
    push ecx
    mov al, [basic_call_param_names + ecx]
    call basic_var_char_to_index   ; EDX = var index
    pop ecx
    mov eax, [ebp-8]               ; arg stack
    mov eax, [eax + ecx*4]
    mov [basic_vars + edx*4], eax
    inc ecx
    jmp .bind_loop

.eval:
    mov esi, [ebp-24]             ; function body expr
    call basic_parse_expr
    push eax
    push edx
    call fs_skip_spaces
    mov bl, [esi]
    pop edx
    pop eax
    cmp bl, 0
    je .restore_success
    cmp bl, 13
    je .restore_success
    cmp bl, 10
    je .restore_success
    jmp .restore_syntax

.restore_success:
    push eax
    push edx
    mov edi, basic_vars
    mov esi, [ebp-16]
    mov ecx, BASIC_VAR_BYTES
    rep movsb
    pop edx
    pop eax
    test edx, edx
    jz .syntax_fail
    jmp .success

.restore_syntax:
    mov edi, basic_vars
    mov esi, [ebp-16]
    mov ecx, BASIC_VAR_BYTES
    rep movsb
    jmp .syntax_fail

.depth_error:
    mov esi, msg_basic_call_depth
    call basic_runtime_set_error
    xor eax, eax
    mov edx, 1
    jmp .done
.arg_limit:
    mov esi, msg_basic_call_args
    call basic_runtime_set_error
    jmp .reported_fail
.name_too_long:
    mov esi, msg_basic_invalid_module
    call basic_runtime_set_error
    jmp .reported_fail
.file_missing:
    mov esi, msg_basic_call_file
    call basic_runtime_set_error
    jmp .reported_fail
.func_missing:
    mov esi, msg_basic_call_func
    call basic_runtime_set_error
    jmp .reported_fail
.arg_mismatch:
    mov esi, msg_basic_call_args
    call basic_runtime_set_error
    jmp .reported_fail
.bad_function:
    mov esi, msg_basic_call_bad_func
    call basic_runtime_set_error
    jmp .reported_fail
.reported_fail:
    dec byte [basic_call_depth]
    xor eax, eax
    mov edx, 1
    jmp .done
.syntax_fail:
    dec byte [basic_call_depth]
    xor eax, eax
    xor edx, edx
    jmp .done
.success:
    dec byte [basic_call_depth]
.done:
    pop edi
    pop ebx
    mov esp, ebp
    pop ebp
    ret

basic_runtime_set_error:
    mov byte [basic_run_stop], 1
    call fs_print_line
    ret

; ESI = file text, EDI = wanted func name, ECX = arg count
; -> EDX=1 EAX=expr ptr; EDX=2 arg mismatch; EDX=3 invalid; EDX=0 not found
basic_find_external_function:
    push ebx
    push edi
    mov [fef_argc], ecx
    mov [fef_name], edi
.line_loop:
    cmp byte [esi], 0
    je .not_found
    cmp byte [esi], 13
    je .next_line
    cmp byte [esi], 10
    je .next_line
    call fs_skip_spaces
    cmp byte [esi], 0
    je .not_found
    call basic_parse_uint
    test edx, edx
    jz .after_line_no
    call fs_skip_spaces
.after_line_no:
    mov edi, kw_func
    call basic_match_keyword
    test eax, eax
    jz .parse_name
    call fs_skip_spaces
.parse_name:
    mov edi, basic_call_scan_name
    mov ecx, BASIC_CALL_NAME_CAP
    call basic_parse_name_token
    test eax, eax
    jz .next_line
    push esi
    mov esi, basic_call_scan_name
    mov edi, [fef_name]
    call strcmp
    pop esi
    test eax, eax
    jz .next_line
    call fs_skip_spaces
    cmp byte [esi], '('
    jne .invalid
    inc esi
    call basic_parse_param_names
    test eax, eax
    jz .invalid
    cmp ecx, [fef_argc]
    jne .arg_mismatch_found
    call fs_skip_spaces
    cmp byte [esi], '='
    jne .invalid
    inc esi
    call fs_skip_spaces
    mov eax, esi
    mov edx, 1
    jmp .done
.next_line:
    call basic_skip_to_next_line
    jmp .line_loop
.arg_mismatch_found:
    xor eax, eax
    mov edx, 2
    jmp .done
.invalid:
    xor eax, eax
    mov edx, 3
    jmp .done
.not_found:
    xor eax, eax
    xor edx, edx
.done:
    pop edi
    pop ebx
    ret

basic_parse_param_names:
    xor ecx, ecx
.loop:
    call fs_skip_spaces
    cmp byte [esi], ')'
    je .done
    cmp ecx, BASIC_CALL_MAX_ARGS
    jae .fail
    mov al, [esi]
    push ecx
    call basic_var_char_to_index
    pop ecx
    test eax, eax
    jz .fail
    mov al, [esi]
    call basic_char_to_lower
    mov [basic_call_param_names + ecx], al
    inc ecx
    inc esi
    call fs_skip_spaces
    cmp byte [esi], ','
    jne .loop
    inc esi
    jmp .loop
.done:
    inc esi
    mov eax, 1
    ret
.fail:
    xor eax, eax
    ret

; EDI = name buffer -> append ".alk". EAX=1/0
basic_append_alk_extension:
    push esi
    mov esi, edi
    call fs_strlen
    cmp eax, BASIC_CALL_NAME_CAP - 5
    ja .fail
    add edi, eax
    mov byte [edi], '.'
    mov byte [edi + 1], 'a'
    mov byte [edi + 2], 'l'
    mov byte [edi + 3], 'k'
    mov byte [edi + 4], 0
    mov eax, 1
    pop esi
    ret
.fail:
    xor eax, eax
    pop esi
    ret

; ESI = src name, ECX = len cap, EDI = dest -> normalize, append/replace .alk
basic_normalize_program_name:
    push ebx
    push edi
    cmp ecx, 5
    jb .fail
    mov [nn_start], edi
    mov [nn_len], ecx
    mov dword [nn_dot], 0
.copy_loop:
    cmp dword [nn_len], 1
    jbe .fail
    mov al, [esi]
    mov [edi], al
    cmp al, '.'
    jne .check_end
    mov [nn_dot], edi
.check_end:
    inc esi
    inc edi
    dec dword [nn_len]
    test al, al
    jnz .copy_loop
    lea eax, [edi - 1]
    sub eax, [nn_start]
    test eax, eax
    jz .fail
    cmp eax, 4
    jb .append
    lea ebx, [edi - 5]
    cmp byte [ebx], '.'
    jne .append
    mov al, [ebx + 1]
    call basic_char_to_lower
    cmp al, 'a'
    jne .replace
    mov al, [ebx + 2]
    call basic_char_to_lower
    cmp al, 'l'
    jne .replace
    mov al, [ebx + 3]
    call basic_char_to_lower
    cmp al, 'k'
    jne .replace
    mov byte [ebx], '.'
    mov byte [ebx + 1], 'a'
    mov byte [ebx + 2], 'l'
    mov byte [ebx + 3], 'k'
    mov byte [ebx + 4], 0
    mov eax, 1
    jmp .done
.replace:
    cmp dword [nn_dot], 0
    je .append
    mov eax, [nn_dot]
    mov byte [eax], 0
.append:
    mov edi, [nn_start]
    call basic_append_alk_extension
    jmp .done
.fail:
    xor eax, eax
.done:
    pop edi
    pop ebx
    ret

; ESI = src, EDI = dest, ECX = cap -> copy a name token. EAX=1/0
basic_parse_name_token:
    push ebx
    push edx
    cmp ecx, 2
    jb .fail
    dec ecx
    xor edx, edx
.loop:
    mov al, [esi]
    call basic_char_to_lower
    cmp al, '_'
    je .store
    cmp al, 'a'
    jb .digit_check
    cmp al, 'z'
    jbe .store
.digit_check:
    cmp edx, 0
    je .end
    cmp al, '0'
    jb .end
    cmp al, '9'
    ja .end
.store:
    test ecx, ecx
    jz .fail
    mov [edi], al
    inc edi
    inc esi
    dec ecx
    inc edx
    jmp .loop
.end:
    test edx, edx
    jz .fail
    mov byte [edi], 0
    mov eax, 1
    pop edx
    pop ebx
    ret
.fail:
    xor eax, eax
    pop edx
    pop ebx
    ret

basic_skip_to_next_line:
.loop:
    mov al, [esi]
    test al, al
    jz .done
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    inc esi
    jmp .loop
.cr:
    inc esi
    cmp byte [esi], 10
    jne .done
    inc esi
    ret
.lf:
    inc esi
.done:
    ret

basic_var_char_to_index:               ; AL -> EAX=1 valid, EDX=index
    call basic_char_to_lower
    cmp al, 'a'
    jb .fail
    cmp al, 'z'
    ja .fail
    movzx edx, al
    sub edx, 'a'
    mov eax, 1
    ret
.fail:
    xor eax, eax
    xor edx, edx
    ret

basic_char_to_lower:
    cmp al, 'A'
    jb .done
    cmp al, 'Z'
    ja .done
    add al, 32
.done:
    ret

basic_parse_uint:                      ; ESI -> EAX value, EDX=1 if any digit
    push ebx
    push ecx
    call fs_skip_spaces
    xor eax, eax
    xor edx, edx
.loop:
    mov bl, [esi]
    cmp bl, '0'
    jb .done
    cmp bl, '9'
    ja .done
    imul eax, eax, 10
    movzx ecx, bl
    sub ecx, '0'
    add eax, ecx
    inc esi
    mov edx, 1
    jmp .loop
.done:
    pop ecx
    pop ebx
    ret

basic_jump_to_line:                    ; EAX = line number
    push ebx
    mov ebx, eax
    call basic_find_line_slot          ; AX in
    test edx, edx
    jz .missing
    mov [basic_run_next], eax
    pop ebx
    ret
.missing:
    mov eax, ebx
    pop ebx
    call basic_runtime_missing_line
    ret

basic_runtime_syntax_error:
    mov byte [basic_run_stop], 1
    mov esi, msg_basic_syntax
    call print_string
    movzx eax, word [basic_current_line]
    call print_dec
    call newline
    ret

basic_runtime_missing_line:
    push eax
    mov byte [basic_run_stop], 1
    mov esi, msg_basic_missing_line
    call print_string
    pop eax
    call print_dec
    call newline
    ret

; ----------------------------------------------------------------------------
; Program storage (records: [u16 line][text NUL])
; ----------------------------------------------------------------------------
basic_list_program:
    push ebx
    push edi
    cmp dword [basic_program_size], 0
    jne .start
    mov esi, msg_basic_no_program
    call fs_print_line
    jmp .done
.start:
    mov ebx, basic_program_buffer
    mov edi, [basic_program_size]
    add edi, basic_program_buffer
.loop:
    cmp ebx, edi
    jae .done
    movzx eax, word [ebx]
    call print_dec
    mov al, ' '
    call print_char
    lea esi, [ebx + 2]
    call fs_print_line
    push edi
    mov edi, ebx
    call basic_record_size
    pop edi
    add ebx, eax
    jmp .loop
.done:
    pop edi
    pop ebx
    ret

basic_save_program:
    push ebx
    push edi
    mov edi, basic_call_name_buffer
    mov ecx, BASIC_CALL_NAME_CAP
    call basic_normalize_program_name
    test eax, eax
    jnz .name_ready
    mov esi, msg_fs_badname
    call fs_print_line
    jmp .fail
.name_ready:
    mov dword [sp_name], basic_call_name_buffer
    call fs_ensure_ready
    test eax, eax
    jz .fail
    mov ebx, basic_program_buffer
    mov eax, [basic_program_size]
    add eax, basic_program_buffer
    mov [sp_progend], eax
    mov edi, basic_file_buffer
    mov dword [sp_remain], BASIC_FILE_CAP - 1
.line_loop:
    cmp ebx, [sp_progend]
    jae .finish
    movzx eax, word [ebx]
    call basic_u32_to_string           ; ESI=str, ECX=len
    cmp ecx, [sp_remain]
    ja .too_large
    mov edx, ecx
    rep movsb                           ; ESI->EDI, ECX bytes
    sub [sp_remain], edx
    cmp dword [sp_remain], 1
    jb .too_large
    mov byte [edi], ' '
    inc edi
    dec dword [sp_remain]
    lea esi, [ebx + 2]
    call fs_strlen
    mov ecx, eax
    cmp ecx, [sp_remain]
    ja .too_large
    lea esi, [ebx + 2]
    mov edx, ecx
    rep movsb
    sub [sp_remain], edx
    cmp dword [sp_remain], 1
    jb .too_large
    mov byte [edi], 10
    inc edi
    dec dword [sp_remain]
    push edi
    mov edi, ebx
    call basic_record_size
    pop edi
    add ebx, eax
    jmp .line_loop
.finish:
    mov byte [edi], 0
    mov ecx, edi
    sub ecx, basic_file_buffer
    mov esi, [sp_name]
    mov edi, basic_file_buffer
    mov byte [fw_flags], 0
    call fs_write_file
    test eax, eax
    jz .fail
    mov esi, msg_basic_saved
    call fs_print_line
    mov eax, 1
    jmp .done
.too_large:
    mov esi, msg_basic_too_large
    call fs_print_line
.fail:
    xor eax, eax
.done:
    pop edi
    pop ebx
    ret

basic_load_program:
    push ebx
    push edi
    mov [lp_orig], esi
    mov edi, basic_call_name_buffer
    mov ecx, BASIC_CALL_NAME_CAP
    call basic_normalize_program_name
    test eax, eax
    jnz .name_ready
    mov esi, msg_fs_badname
    call fs_print_line
    jmp .fail
.name_ready:
    call fs_ensure_ready
    test eax, eax
    jz .fail
    mov esi, basic_call_name_buffer
    call fs_find_entry
    test eax, eax
    jnz .have_entry
    mov esi, [lp_orig]
    mov edi, basic_call_name_buffer
    call strcmp
    test eax, eax
    jnz .not_found
    mov esi, [lp_orig]
    call fs_find_entry
    test eax, eax
    jz .not_found
.have_entry:
    mov edi, eax                        ; entry
    mov esi, basic_file_buffer
    mov ecx, BASIC_FILE_CAP
    call basic_read_file_into_buffer
    test eax, eax
    jz .fail
    call basic_clear_program
    mov esi, basic_file_buffer
.line_loop:
    call fs_skip_spaces
    cmp byte [esi], 13
    je .skip_newline
    cmp byte [esi], 10
    je .skip_newline
    cmp byte [esi], 0
    je .loaded
    call basic_parse_uint
    test edx, edx
    jz .bad_file
    cmp eax, 1
    jb .bad_file
    cmp eax, 65535
    ja .bad_file
    mov [lp_lineno], eax
    call fs_skip_spaces
    mov [lp_textstart], esi
    mov edi, esi                        ; scan to end of line
.scan_line:
    mov al, [edi]
    cmp al, 0
    je .end_of_line
    cmp al, 13
    je .end_of_line
    cmp al, 10
    je .end_of_line
    inc edi
    jmp .scan_line
.end_of_line:
    mov ebx, edi                        ; ebx = next-line start
    mov al, [edi]
    cmp al, 13
    jne .check_lf
    inc ebx
    cmp byte [ebx], 10
    jne .next_ready
    inc ebx
    jmp .next_ready
.check_lf:
    cmp al, 10
    jne .next_ready
    inc ebx
.next_ready:
    mov [lp_termch], al                 ; the terminator char at edi
    mov byte [edi], 0
    mov eax, [lp_lineno]
    mov esi, [lp_textstart]
    call basic_store_line
    test eax, eax
    jz .bad_file
    mov al, [lp_termch]
    cmp al, 0
    je .loaded
    mov esi, ebx
.skip_newline:
    cmp byte [esi], 13
    jne .skip_lf
    inc esi
.skip_lf:
    cmp byte [esi], 10
    jne .line_loop
    inc esi
    jmp .line_loop
.loaded:
    mov esi, msg_basic_loaded
    call fs_print_line
    mov eax, 1
    jmp .done
.not_found:
    mov esi, msg_fs_notfound
    call fs_print_line
    jmp .fail
.bad_file:
    call basic_clear_program
    mov esi, msg_basic_bad_file
    call fs_print_line
.fail:
    xor eax, eax
.done:
    pop edi
    pop ebx
    ret

; EDI = entry ptr, ESI = dest buffer, ECX = cap -> read text file. EAX=1/0
basic_read_file_into_buffer:
    push ebx
    push edi
    mov al, [edi + FS_ENTRY_FLAGS_OFF]
    test al, FS_FLAG_BINARY
    jz .text_ok
    push esi
    mov esi, msg_basic_text_only
    call fs_print_line
    pop esi
    jmp .fail
.text_ok:
    mov [rf_dst], esi
    mov eax, [edi + FS_ENTRY_SIZE_OFF]
    mov [rf_rem], eax
    mov ebx, ecx
    dec ebx                             ; cap-1
    cmp eax, ebx
    ja .too_large
    mov eax, [edi + FS_ENTRY_START_OFF]
    mov [rf_lba], eax
    cmp dword [rf_rem], 0
    jz .empty
.sector_loop:
    mov eax, [rf_lba]
    mov ecx, 1
    mov edi, fs_sector_buffer
    call ata_read_sectors
    test eax, eax
    jz .disk_error
    mov ecx, [rf_rem]
    cmp ecx, 512
    jbe .copy_chunk
    mov ecx, 512
.copy_chunk:
    mov esi, fs_sector_buffer
    mov edi, [rf_dst]
    mov edx, ecx
    rep movsb
    mov [rf_dst], edi
    sub [rf_rem], edx
    inc dword [rf_lba]
    cmp dword [rf_rem], 0
    jnz .sector_loop
.empty:
    mov edi, [rf_dst]
    mov byte [edi], 0
    mov eax, 1
    jmp .done
.too_large:
    mov esi, msg_basic_file_too_large
    call fs_print_line
    jmp .fail
.disk_error:
    mov esi, msg_fs_disk
    call fs_print_line
.fail:
    xor eax, eax
.done:
    pop edi
    pop ebx
    ret

; EAX = line number, ESI = text -> store/replace a program line. EAX=1/0
basic_store_line:
    push ebx
    push edi
    mov [sl_lineno], eax
    mov [sl_text], esi
    call fs_strlen                      ; ESI in -> EAX len
    mov [sl_textlen], eax
    mov eax, [sl_lineno]
    call basic_find_line_slot           ; EAX=slot, EDX=exact?
    mov [sl_slot], eax
    test edx, edx
    jz .insert
    mov edi, eax
    call basic_record_size              ; EAX = old record size
    mov ecx, eax
    mov edi, [sl_slot]
    call basic_shift_left
.insert:
    cmp dword [sl_textlen], 0
    jz .success
    mov eax, [sl_textlen]
    add eax, 3
    mov ecx, eax
    mov edi, [sl_slot]
    call basic_shift_right
    test eax, eax
    jz .fail
    mov edi, [sl_slot]
    mov eax, [sl_lineno]
    mov [edi], ax
    add edi, 2
    mov esi, [sl_text]
    mov ecx, [sl_textlen]
    rep movsb
    mov byte [edi], 0
.success:
    mov eax, 1
    jmp .done
.fail:
    xor eax, eax
.done:
    pop edi
    pop ebx
    ret

; EAX = line number -> EAX = slot ptr, EDX=1 if exact match
basic_find_line_slot:
    push ebx
    movzx ebx, ax
    mov edx, [basic_program_size]
    add edx, basic_program_buffer
    mov [fls_end], edx
    mov eax, basic_program_buffer
.loop:
    cmp eax, [fls_end]
    jae .insert_here
    movzx ecx, word [eax]
    cmp ecx, ebx
    je .exact
    ja .insert_here
    push eax
    mov edi, eax
    call basic_record_size
    pop edi
    add eax, edi                        ; eax = slot + size
    jmp .loop
.exact:
    mov edx, 1
    pop ebx
    ret
.insert_here:
    xor edx, edx
    pop ebx
    ret

basic_record_size:                      ; EDI = record -> EAX = size
    push esi
    lea esi, [edi + 2]
    call fs_strlen
    add eax, 3
    pop esi
    ret

; EDI = slot, ECX = bytes -> open a gap. EAX=1/0
basic_shift_right:
    push ebx
    push ecx
    push edx
    mov edx, [basic_program_size]
    mov [sr_count], ecx
    mov eax, BASIC_PROGRAM_CAP
    sub eax, edx
    cmp eax, ecx
    jb .too_large
    mov ebx, basic_program_buffer
    add ebx, edx                        ; ebx = end
    mov eax, ebx
    add eax, [sr_count]                 ; eax = new end
.copy_loop:
    cmp ebx, edi
    jbe .done_copy
    dec ebx
    dec eax
    mov dl, [ebx]
    mov [eax], dl
    jmp .copy_loop
.done_copy:
    mov eax, [sr_count]
    add [basic_program_size], eax
    mov eax, 1
    jmp .done
.too_large:
    mov esi, msg_basic_too_large
    call fs_print_line
    xor eax, eax
.done:
    pop edx
    pop ecx
    pop ebx
    ret

; EDI = slot, ECX = bytes -> close a gap.
basic_shift_left:
    push ebx
    push ecx
    push esi
    push edx
    mov edx, ecx
    lea esi, [edi + edx]
    mov ebx, [basic_program_size]
    add ebx, basic_program_buffer
.copy_loop:
    cmp esi, ebx
    jae .done_copy
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    jmp .copy_loop
.done_copy:
    sub [basic_program_size], edx
    pop edx
    pop esi
    pop ecx
    pop ebx
    ret

basic_clear_program:
    mov dword [basic_program_size], 0
    ret

basic_clear_vars:
    mov edi, basic_vars
    mov ecx, BASIC_VAR_BYTES
    call fs_memzero
    ret

; EDI = keyword, ESI = cursor -> EAX=1 match (ESI advanced) / 0 (ESI restored)
basic_match_keyword:
    push ebx
    mov ebx, esi
.cmp_loop:
    mov al, [edi]
    test al, al
    jz .end_kw
    mov dl, [esi]
    cmp dl, 'A'
    jb .cmp_ready
    cmp dl, 'Z'
    ja .cmp_ready
    add dl, 32
.cmp_ready:
    cmp al, dl
    jne .fail
    inc edi
    inc esi
    jmp .cmp_loop
.end_kw:
    mov al, [esi]
    test al, al
    jz .success
    cmp al, ' '
    je .success
    cmp al, 13
    je .success
    cmp al, 10
    je .success
    jmp .fail
.success:
    mov eax, 1
    pop ebx
    ret
.fail:
    mov esi, ebx
    xor eax, eax
    pop ebx
    ret

basic_print_signed_32:                  ; EAX = signed value
    push eax
    cmp eax, 0
    jge .positive
    mov al, '-'
    call print_char
    pop eax
    neg eax
    call print_dec
    ret
.positive:
    pop eax
    call print_dec
    ret

; EAX = value -> ESI = string ptr, ECX = length (in basic_num_buffer)
basic_u32_to_string:
    push ebx
    push edx
    push edi
    mov edi, basic_num_buffer + 11
    mov ebx, 10
    cmp eax, 0
    jne .convert
    dec edi
    mov byte [edi], '0'
    mov esi, edi
    mov ecx, 1
    jmp .done
.convert:
.loop:
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .loop
    mov esi, edi
    mov eax, basic_num_buffer + 11
    sub eax, edi
    mov ecx, eax
.done:
    pop edi
    pop edx
    pop ebx
    ret

; ----------------------------------------------------------------------------
; Keywords, messages, state
; ----------------------------------------------------------------------------
kw_help  db "help", 0
kw_list  db "list", 0
kw_run   db "run", 0
kw_new   db "new", 0
kw_save  db "save", 0
kw_load  db "load", 0
kw_exit  db "exit", 0
kw_editor db "editor", 0
kw_flow  db "flow", 0
kw_loops db "loops", 0
kw_memory db "memory", 0
kw_funcs db "funcs", 0
kw_functions db "functions", 0
kw_print db "print", 0
kw_call  db "call", 0
kw_goto  db "goto", 0
kw_if    db "if", 0
kw_then  db "then", 0
kw_end   db "end", 0
kw_let   db "let", 0
kw_intercept db "intercept", 0
kw_func  db "func", 0
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
msg_basic_call_depth    db "[alkan 1.0] call stack too deep.", 0
msg_basic_call_file     db "[alkan 1.0] call file not found.", 0
msg_basic_call_func     db "[alkan 1.0] function not found.", 0
msg_basic_call_args     db "[alkan 1.0] function arg mismatch.", 0
msg_basic_call_bad_func db "[alkan 1.0] invalid function definition.", 0
msg_basic_invalid_module db "[alkan 1.0] invalid module name.", 0
msg_basic_intercept_range db "[alkan 1.0] intercept needs address >= 0 and value 0..255.", 0
msg_basic_stopped       db "[alkan 1.0] stopped.", 0
msg_basic_help_page_1   db "[alkan 1.0] guide 1/4: editor", 0
msg_basic_help_page_2   db "[alkan 1.0] guide 2/4: flow", 0
msg_basic_help_page_3   db "[alkan 1.0] guide 3/4: loops", 0
msg_basic_help_page_4   db "[alkan 1.0] guide 4/4: funcs and memory", 0
msg_basic_help_more     db "next: any key   exit: ESC", 0
msg_basic_help_done     db "press any key to return", 0
msg_basic_help_topics   db "[alkan 1.0] topics: editor  flow  loops  funcs  memory", 0
msg_basic_help_1        db "quick guide", 0
msg_basic_help_29       db "jump to a page: help editor  help flow  help loops  help memory", 0
msg_basic_help_2        db "editor commands: help  list  run  save <file>  load <file>  new  exit", 0
msg_basic_help_3        db "shell run: alkan demo.alk", 0
msg_basic_help_4        db "line format: <number> <code>", 0
msg_basic_help_5        db "set variable: 10 a = 5", 0
msg_basic_help_6        db "delete line: 10", 0
msg_basic_help_7        db "variables: single letters a to z", 0
msg_basic_help_8        db "math: 20 a = a + 1", 0
msg_basic_help_9        db "math: 30 a = a - 1", 0
msg_basic_help_10       db "logic words also work: add  sub  eq  lt  not", 0
msg_basic_help_11       db "print value: 40 print a", 0
msg_basic_help_12       db "jump: 50 goto 20", 0
msg_basic_help_13       db "if less: 60 if a lt 10 then 20", 0
msg_basic_help_14       db "if equal: 70 if a = 10 then goto 90", 0
msg_basic_help_15       db "stop: 90 end", 0
msg_basic_help_16       db "example loop: 10 a = 1", 0
msg_basic_help_17       db "example loop: 20 print a", 0
msg_basic_help_18       db "example loop: 30 a = a + 1", 0
msg_basic_help_19       db "example loop: 40 if a lt 6 then 20", 0
msg_basic_help_20       db "function file calc.alk: 10 func plus(a b) = a + b", 0
msg_basic_help_21       db "use function: 10 x = call calc.plus(2 4)", 0
msg_basic_help_22       db "direct call: 20 print call calc.plus(2 4)", 0
msg_basic_help_23       db "call line: 30 call calc.plus(2 4)", 0
msg_basic_help_24       db "save/load: save demo  load demo  (.alk auto)", 0
msg_basic_help_25       db "shift keys work for +  _  :  ", 34, "  |  <  >  ?", 0
msg_basic_help_26       db "run control: press ESC to stop a running loop", 0
msg_basic_help_27       db "memory write: 80 intercept 753664, 65", 0
msg_basic_help_28       db "screen RAM starts at 753664 and uses char/color bytes", 0

basic_line_length  dd 0
basic_program_size dd 0
basic_run_next     dd 0
basic_current_line dw 0
basic_run_stop     db 0
basic_repl_exit    db 0
basic_call_depth   db 0

; non-recursive function spill temps
sp_name dd 0
sp_progend dd 0
sp_remain dd 0
lp_orig dd 0
lp_lineno dd 0
lp_textstart dd 0
lp_termch dd 0
sl_lineno dd 0
sl_text dd 0
sl_textlen dd 0
sl_slot dd 0
fls_end dd 0
br_end  dd 0
cond_op dd 0
sr_count dd 0
rf_dst dd 0
rf_rem dd 0
rf_lba dd 0
fef_argc dd 0
fef_name dd 0
nn_start dd 0
nn_len dd 0
nn_dot dd 0

basic_num_buffer       times 12 db 0
basic_line_buffer      times BASIC_LINE_CAP db 0
basic_program_buffer   times BASIC_PROGRAM_CAP db 0
basic_file_buffer      times BASIC_FILE_CAP db 0
basic_vars             times 26 dd 0
basic_call_name_buffer times BASIC_CALL_NAME_CAP db 0
basic_call_func_buffer times BASIC_CALL_NAME_CAP db 0
basic_call_scan_name   times BASIC_CALL_NAME_CAP db 0
basic_call_param_names times BASIC_CALL_MAX_ARGS db 0
basic_call_arg_stack   times BASIC_CALL_DEPTH * BASIC_CALL_MAX_ARGS dd 0
basic_call_saved_vars  times BASIC_CALL_DEPTH * BASIC_VAR_BYTES db 0
basic_call_file_stack  times BASIC_CALL_DEPTH * BASIC_CALL_FILE_CAP db 0
