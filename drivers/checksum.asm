; drivers/checksum.asm
; Input: RSI = Data Start, RCX = Length (in bytes)
; Output: AX = 16-bit Checksum

calculate_checksum:
    push rsi
    push rcx
    push rdx
    
    xor rax, rax            ; Clear accumulator
    shr rcx, 1              ; Convert byte count to word count (16-bit)
    jz .done_odd            ; Handle 0 length

.loop:
    movzx rdx, word [rsi]   ; Get 16-bit word
    add rax, rdx            ; Add to total
    add rsi, 2
    loop .loop

.done_odd:
    ; If there was an odd byte left over, add it (not common in our headers)
    ; ... (skipping for simplicity as our headers are always even)

    ; Fold 32-bit sum into 16-bits
    mov rdx, rax
    shr rdx, 16
    and rax, 0xFFFF
    add rax, rdx
    
    ; Add carry one last time
    mov rdx, rax
    shr rdx, 16
    add rax, rdx
    
    not ax                  ; One's complement
    pop rdx
    pop rcx
    pop rsi
    ret