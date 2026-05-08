; ==============================================================================
; Intel E1000 Transmit Driver (MMIO Fixed)
; ==============================================================================

; Input: RSI = Packet Address, RCX = Packet Length
e1000_send_packet:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi

    ; [1] Calculate Physical Address of current TX Descriptor
    mov rax, [tx_tail]
    shl rax, 4              ; Multiply by 16 (size of one descriptor)
    add rax, [tx_desc_base] 

    ; [2] Populate the Descriptor
    mov [rax], rsi          ; Bytes 0-7: 64-bit Buffer Address
    mov [rax + 8], cx       ; Bytes 8-9: 16-bit Packet Length
    mov byte [rax + 10], 0  ; Byte 10: CSO (Checksum Offset)
    
    ; Byte 11: CMD (Command Field)
    ; 0x01 (EOP - End of Packet)
    ; 0x02 (IFCS - Insert Frame Checksum)
    ; 0x08 (RS - Report Status, tells hardware to set DD bit when done)
    ; Total = 0x0B
    mov byte [rax + 11], 0x0B 

    ; Byte 12: STA (Status Field)
    ; CRITICAL: Must clear the old status so we don't read a "stale" Done signal!
    mov byte [rax + 12], 0

    ; [3] Advance Software Tail Pointer
    mov rbx, [tx_tail]
    inc rbx
    and rbx, 127            ; Wrap at 128
    mov [tx_tail], rbx

    ; [4] THE DOORBELL FIX (Write to MMIO, not I/O Port!)
    mov rdx, [nic_mem_base]
    mov dword [rdx + 0x3818], ebx ; Write directly to memory to ring the doorbell!

    ; [5] Wait for Transmit to Complete (With Safety Timeout)
    ; We check the "DD" (Descriptor Done) bit (Bit 0 of STA byte at offset 12)
    mov rcx, 1000000        ; Timeout counter to prevent freezing
.wait_tx:
    test byte [rax + 12], 0x01
    jnz .tx_done            ; Hardware set the DD bit! It successfully sent!
    dec rcx
    jnz .wait_tx            ; Keep polling

.tx_done:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret