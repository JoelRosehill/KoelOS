cmd_mem db "mem", 0

do_mem:
    lea rsi, [.msg_used]
    call print_string
    mov rax, [heap_current]
    sub rax, 0x200000          ; bytes handed out by the bump allocator
    call print_dec_32
    lea rsi, [.msg_bytes]
    call print_string
    call newline

    lea rsi, [.msg_next]
    call print_string
    mov eax, [heap_current]
    call print_hex_32
    call newline
    jmp command_done

.msg_used  db "Heap used:  ", 0
.msg_bytes db " bytes (base 0x200000)", 0
.msg_next  db "Next alloc: 0x", 0
