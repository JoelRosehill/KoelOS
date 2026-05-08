; ==============================================================================
; Intel E1000 Receive Driver (Production Ready - RSI Fixed)
; ==============================================================================

; Output: 
;   RAX = Memory Address of packet (0 if empty), RCX = Length
e1000_receive_packet:
    push rbx
    push rdx
    push rsi                    ; CRITICAL FIX: Save RSI so we don't break string printing!

    ; [1] Calculate Descriptor Address
    mov rax, [rx_curr]
    shl rax, 4                  
    add rax, [rx_desc_base]     

    ; [2] Check DD (Descriptor Done) Bit
    test byte [rax + 12], 0x01
    jz .no_packet               

    ; [3] Packet Arrived! Extract Info
    mov rsi, [rax]              ; RSI temporarily holds the packet buffer address
    movzx rcx, word [rax + 8]   ; RCX holds length

    ; [4] Clean up descriptor for reuse
    mov byte [rax + 12], 0      

    ; [5] Update Hardware Tail (RDT)
    mov rdx, [nic_mem_base]
    mov ebx, dword [rx_curr]
    mov dword [rdx + 0x2818], ebx     

    ; [6] Increment & Wrap software pointer
    inc qword [rx_curr]
    and qword [rx_curr], 127    

    mov rax, rsi                ; Put the packet address into RAX for the caller
    jmp .done

.no_packet:
    xor rax, rax                ; Return 0 to indicate no new data
    xor rcx, rcx

.done:
    pop rsi                     ; CRITICAL FIX: Restore RSI to its original state
    pop rdx
    pop rbx
    ret