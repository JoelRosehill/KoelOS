; drivers/vga_text.asm

print_char:
    push rax
    push rdi
    call check_scroll
    mov rdi, [cursor_pos]
    mov ah, [current_color]
    mov [rdi], ax
    call serial_putc        ; mirror the glyph to COM1 (AL still = char)
    add qword [cursor_pos], 2
    call update_cursor
    pop rdi
    pop rax
    ret

print_string:
    push rax
    push rsi
.loop:
    lodsb
    test al, al
    jz .done
    call print_char
    jmp .loop
.done:
    pop rsi
    pop rax
    ret

newline:
    push rax
    push rcx
    push rdx
    mov rax, [cursor_pos]
    sub rax, 0xb8000
    xor rdx, rdx
    mov rcx, 160        
    div rcx
    inc rax
    mul rcx
    add rax, 0xb8000
    mov [cursor_pos], rax
    call check_scroll
    call update_cursor
    mov al, 13              ; mirror the line break to COM1 as CRLF
    call serial_putc
    mov al, 10
    call serial_putc
    pop rdx
    pop rcx
    pop rax
    ret

clear_screen:
    mov rdi, 0xb8000
    mov rcx, 2000
    mov ah, [current_color]
    mov al, ' '
    rep stosw
    mov qword [cursor_pos], 0xb8000
    call update_cursor
    ret

do_backspace:
    push rax
    push rdi
    mov rax, [cursor_pos]
    sub rax, 0xb8000
    test rax, rax
    jz .done
    sub qword [cursor_pos], 2     
    mov rdi, [cursor_pos]
    mov ah, [current_color]       
    mov al, ' '                   
    mov [rdi], ax
    call update_cursor            
.done:
    pop rdi
    pop rax
    ret