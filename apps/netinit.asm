; ==========================================
; Network Initialization App (Pre-fixed Version)
; ==========================================

cmd_netinit db "netinit", 0

do_netinit:
    ; [1] Start Search
    lea rsi, [net_msg_searching]
    call print_string
    call newline
    
    ; [2] Find the card on the PCI Bus
    call find_nic           
    test rax, rax
    jz .not_found
    
    ; [3] Hardware found! Display BAR0 (MMIO Address)
    lea rsi, [net_msg_debug_bar]
    call print_string

    mov rax, [nic_pci_addr]
    or rax, 0x10            ; Offset 0x10 is BAR0
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    and eax, 0xFFFFFFF0     
    
    call print_hex_32
    call newline

    ; [4] Initialize the hardware
    lea rsi, [net_msg_found]
    call print_string
    call newline

    call e1000_init         
    
    lea rsi, [net_msg_done]
    call print_string
    call newline
    
    jmp command_done

.not_found:
    lea rsi, [net_msg_err]
    call print_string
    call newline
    jmp command_done

; --- Messages (Unique Prefixes) ---
net_msg_searching db "Searching PCI bus for Intel E1000...", 0
net_msg_debug_bar db "NIC BAR0 Address Found: 0x", 0
net_msg_found     db "Setting up DMA Buffers & RAL/RAH...", 0
net_msg_done      db "Network Interface (eth0) is now UP.", 0
net_msg_err       db "Fatal: No supported network hardware found.", 0
