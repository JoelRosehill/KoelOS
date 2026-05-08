cmd_colors db "colors", 0

do_colors:
    mov rsi, arg_buffer
    mov al, [rsi]           ; Get the first character of the argument

    cmp al, '1'
    je .theme1
    cmp al, '2'
    je .theme2
    cmp al, '3'
    je .theme3
    cmp al, '4'
    je .theme4
    cmp al, '5'
    je .theme5

    ; If no valid number is typed, show usage
    mov rsi, .msg_usage
    call print_string
    call newline
    jmp command_done

.theme1:
    mov byte [current_color], 0x1F  ; Blue background, White text (Default)
    jmp .apply
.theme2:
    mov byte [current_color], 0x02  ; Black background, Green text (Matrix)
    jmp .apply
.theme3:
    mov byte [current_color], 0x70  ; White background, Black text (Classic)
    jmp .apply
.theme4:
    mov byte [current_color], 0x0B  ; Black background, Cyan text (Cyberpunk)
    jmp .apply
.theme5:
    mov byte [current_color], 0x4F  ; Red background, White text (Alert)
    jmp .apply

.apply:
    call clear_screen
    mov rsi, .msg_ok
    call print_string
    call newline
    jmp command_done

.msg_usage db "Usage: colors [1-5]", 0
.msg_ok    db "Theme updated!", 0