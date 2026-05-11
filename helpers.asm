; helpers.asm
; High-level OS interface functions

print_prompt:
    lea rsi, [msg_prompt]
    call print_string
    ret

kbd_translate_scancode:
    push rbx
    push rcx

    cmp al, 0x2A
    je .shift_on
    cmp al, 0x36
    je .shift_on
    cmp al, 0xAA
    je .shift_off
    cmp al, 0xB6
    je .shift_off
    test al, 0x80
    jnz .none

    xor rbx, rbx
    mov bl, al
    cmp byte [shift_state], 0
    jne .shifted

    lea rcx, [keymap]
    mov al, [rcx + rbx]
    jmp .done

.shifted:
    lea rcx, [keymap_shift]
    mov al, [rcx + rbx]
    jmp .done

.shift_on:
    mov byte [shift_state], 1
    jmp .none

.shift_off:
    mov byte [shift_state], 0

.none:
    xor eax, eax

.done:
    pop rcx
    pop rbx
    ret

; Note: All VGA and String logic has been moved to the /drivers folder
; and is automatically included by your build script.
