; helpers.asm
; High-level OS interface functions

print_prompt:
    lea rsi, [msg_prompt]
    call print_string
    ret

; Note: All VGA and String logic has been moved to the /drivers folder
; and is automatically included by your build script.