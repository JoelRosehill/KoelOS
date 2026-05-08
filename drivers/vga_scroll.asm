; drivers/vga_scroll.asm

check_scroll:
    cmp qword [cursor_pos], 0xb8fa0
    jl .no_scroll
    call scroll_screen
.no_scroll:
    ret

scroll_screen:
    push rax
    push rcx
    push rsi
    push rdi

    ; Move lines 2-25 up to lines 1-24
    mov rdi, 0xb8000            ; Destination: Top
    mov rsi, 0xb80a0            ; Source: Line 2 (160 bytes in)
    mov rcx, 480                ; (80 chars * 24 lines * 2 bytes) / 8 bytes
    rep movsq

    ; Clear the bottom line (Line 25)
    mov rdi, 0xb8f00            
    mov ax, [current_color]
    shl ax, 8
    mov al, ' '                 
    mov rcx, 80
    rep stosw

    ; Set cursor to the start of the last line
    mov qword [cursor_pos], 0xb8f00

    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret