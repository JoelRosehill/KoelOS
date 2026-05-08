; drivers/vga_cursor.asm

update_cursor:
    push rax
    push rbx
    push rdx

    ; Calculate character index: (cursor_pos - 0xB8000) / 2
    mov rax, [cursor_pos]
    sub rax, 0xb8000
    shr rax, 1          
    mov rbx, rax        

    ; Send Low Byte (Index 15)
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    mov dx, 0x3D5
    mov al, bl          
    out dx, al

    ; Send High Byte (Index 14)
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    mov dx, 0x3D5
    mov al, bh          
    out dx, al

    pop rdx
    pop rbx
    pop rax
    ret