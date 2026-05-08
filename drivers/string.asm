; drivers/string.asm

strcmp:
    push rsi
    push rdi
.loop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .nomatch
    test al, al
    jz .match
    inc rsi
    inc rdi
    jmp .loop
.nomatch:
    mov rax, 0
    pop rdi
    pop rsi
    ret
.match:
    mov rax, 1
    pop rdi
    pop rsi
    ret