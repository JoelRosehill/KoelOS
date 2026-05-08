; ==============================================================================
; Universal Decimal Printer (64-bit)
; ==============================================================================
; Input: AL = Byte to print (0-255)
; This function preserves all registers to be compatible with any caller.
; ==============================================================================

print_dec_byte:
    push rax
    push rbx
    push rcx
    push rdx

    ; [1] Prepare for 64-bit division
    movzx rax, al       ; Move the input byte to RAX and clear all upper bits
    mov rbx, 10         ; We want to divide by 10 (Decimal Base)
    xor rcx, rcx        ; Clear our digit counter

.div_loop:
    ; [2] Perform Division
    ; To divide in 64-bit, we must ensure RDX (the top half) is zeroed.
    xor rdx, rdx        
    div rbx             ; RDX:RAX / RBX -> RAX (Quotient), RDX (Remainder)
    
    ; [3] Save the remainder (this is our digit: 0-9)
    push rdx            ; Push the digit onto the stack
    inc rcx             ; Increment our digit counter
    
    ; [4] Check if we have more digits to process
    test rax, rax       ; Is the quotient 0?
    jnz .div_loop       ; If not, there are more digits, keep dividing

.print_loop:
    ; [5] Pop digits off the stack (they come off in the correct order)
    pop rax             ; Get the last remainder back
    add al, '0'         ; Convert number (0-9) to ASCII character ('0'-'9')
    
    ; [6] Print the character
    ; We push/pop RCX here just in case your print_char function 
    ; clobbers the RCX register, which would break our loop.
    push rcx
    call print_char
    pop rcx
    
    loop .print_loop    ; Decrement RCX and jump if not zero

    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret