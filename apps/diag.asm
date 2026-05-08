; ==========================================
; KoelOS Unified Diagnostics Tool
; ==========================================

global cmd_diag, do_diag
cmd_diag db "diag", 0

do_diag:
    ; 1. Run Network Hardware Diagnostics
    call diag_network_func
    call newline
    
    ; 2. Run HTTP Payload Diagnostics
    call http_debug
    
    jmp command_done

; ------------------------------------------------------------------------------
; diag_network_func: Runs the E1000 NIC hardware tests
; ------------------------------------------------------------------------------
diag_network_func:
    push rax
    push rbx
    push rsi
    push rdi

    lea rsi, [msg_diag_header]
    call print_string
    call newline

    ; --- TEST 1: PCI Presence ---
    lea rsi, [msg_test_pci]
    call print_string
    mov rax, [nic_pci_addr]
    test rax, rax
    jz .pci_fail
    lea rsi, [msg_ok]
    call print_string
    call newline

    ; --- TEST 2: MMIO Accessibility ---
    lea rsi, [msg_test_mmio]
    call print_string
    mov rsi, [nic_mem_base]
    
    mov eax, [rsi + 0x0008]
    push rax
    lea rsi, [msg_val]
    call print_string
    pop rax
    call print_hex_32
    call newline

    ; --- TEST 3: Link Status ---
    lea rsi, [msg_test_link]
    call print_string
    test eax, 0x02
    jz .link_down
    lea rsi, [msg_ok]
    call print_string
    call newline
    jmp .test_rx

.link_down:
    lea rsi, [msg_fail]
    call print_string
    call newline

.test_rx:
    ; --- TEST 4: RX Queue Health ---
    lea rsi, [msg_test_rx]
    call print_string
    mov rsi, [nic_mem_base]
    
    mov eax, [rsi + 0x2810] ; Head
    push rax
    mov eax, [rsi + 0x2818] ; Tail
    mov ebx, eax
    pop rax
    
    lea rsi, [msg_queue_stat]
    call print_string
    call print_hex_32
    mov al, '/'
    call print_char
    mov eax, ebx
    call print_hex_32
    call newline

    ; --- TEST 5: Descriptor Done (DD) Check ---
    lea rsi, [msg_test_dd]
    call print_string
    mov rdi, [rx_desc_base]
    mov al, [rdi + 12]       
    call print_hex_byte
    call newline

    ; --- TEST 6: TX Queue Health ---
    lea rsi, [msg_test_tx]
    call print_string
    mov rsi, [nic_mem_base]
    
    mov eax, [rsi + 0x3810] ; Transmit Head
    push rax
    mov eax, [rsi + 0x3818] ; Transmit Tail
    mov ebx, eax
    pop rax
    
    lea rsi, [msg_queue_stat]
    call print_string
    call print_hex_32
    mov al, '/'
    call print_char
    mov eax, ebx
    call print_hex_32
    call newline
    jmp .done

.pci_fail:
    lea rsi, [msg_fail_pci]
    call print_string
    call newline

.done:
    lea rsi, [msg_diag_done]
    call print_string
    call newline

    pop rdi
    pop rsi
    pop rbx
    pop rax
    ret

; --- Messages ---
msg_diag_header  db "==== KOELOS HARDWARE DIAGNOSTICS ====", 0
msg_test_pci     db "[1] PCI NIC Address: ", 0
msg_test_mmio    db "[2] MMIO Heartbeat:  ", 0
msg_test_link    db "[3] Network Link:    ", 0
msg_test_rx      db "[4] RX Queue Ptrs:   ", 0
msg_test_dd      db "[5] First RX Status: ", 0
msg_test_tx      db "[6] TX Queue Ptrs:   ", 0
msg_val          db "Value 0x", 0
msg_ok           db " PASS", 0
msg_fail         db " FAIL (Check Hardware)", 0
msg_fail_pci     db " FAIL (NIC not initialized. Run netinit first!)", 0
msg_queue_stat   db " H/T: ", 0
msg_diag_done    db "=====================================", 0