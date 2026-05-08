; drivers/print_hex.asm

; Input: AL = Byte to print in hex
print_hex_byte:
    push rax
    push rbx

    mov bl, al          ; Save original byte
    
    ; High nibble
    shr al, 4
    call .to_ascii
    call print_char
    
    ; Low nibble
    mov al, bl
    and al, 0x0F
    call .to_ascii
    call print_char

    pop rbx
    pop rax
    ret

.to_ascii:
    cmp al, 10
    jl .is_digit
    add al, 'A' - 10
    ret
.is_digit:
    add al, '0'
    ret