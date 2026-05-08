; ==============================================================================
; Intel E1000 Robust Initialization (VirtualBox & QEMU Safe)
; ==============================================================================

e1000_init:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    ; [1] PCI/MMIO Setup
    mov rax, [nic_pci_addr]
    or rax, 0x10            
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    and eax, 0xFFFFFFF0     
    mov [nic_mem_base], rax
    mov rsi, rax            ; RSI = Base of NIC Registers

    ; [2] Hardware Reset
    mov eax, [rsi]
    or eax, 0x04000000      ; Device Reset bit
    mov [rsi], eax
    
    ; Delay for reset
    mov rcx, 20000
.reset_delay:
    pause
    loop .reset_delay

    ; --- CRITICAL VIRTUALBOX FIX: Force Link Up ---
    ; VirtualBox requires the OS to explicitly power on the physical link
    mov eax, [rsi]
    or eax, 0x40            ; Bit 6 is SLU (Set Link Up)
    mov [rsi], eax
    ; ----------------------------------------------

    ; [3] PCI Command: Enable Memory, I/O, and Bus Mastering
    mov rax, [nic_pci_addr]
    mov al, 0x04            
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    or eax, 0x07            
    out dx, eax

    ; [4] CRITICAL: 128-Byte Alignment Fix
    ; Intel Manual: Descriptor Base Addresses MUST be 128-byte aligned.
    mov rax, [heap_current]
    add rax, 127
    and rax, -128           ; Align to nearest 128-byte boundary
    mov [heap_current], rax

    ; [5] Setup RX Descriptor Table
    mov rax, [heap_current]
    mov [rx_desc_base], rax
    add qword [heap_current], 4096 

    mov rdi, [rx_desc_base]
    mov rcx, 128
.pop_rx:
    mov rax, [heap_current]    
    mov [rdi], rax             
    mov dword [rdi + 8], 0     
    mov dword [rdi + 12], 0    
    add qword [heap_current], 2048 
    add rdi, 16                
    loop .pop_rx

    ; [6] Setup TX Descriptor Table (Aligned)
    mov rax, [heap_current]
    mov [tx_desc_base], rax
    add qword [heap_current], 4096

    ; [7] Set MAC Identity (RAL/RAH)
    lea rbx, [my_mac]
    mov eax, [rbx]
    mov [rsi + 0x5400], eax    ; RAL
    movzx eax, word [rbx + 4]
    or eax, 0x80000000         ; Valid Bit
    mov [rsi + 0x5404], eax    ; RAH

    ; [8] Zero out Multicast Table (MTA)
    mov rcx, 128
.zero_mta:
    mov dword [rsi + 0x5200 + rcx*4], 0
    loop .zero_mta

    ; [9] Write Queue Pointers to Hardware
    ; RX Registers
    mov rdi, [rx_desc_base]
    mov [rsi + 0x2800], edi           ; RDBAL
    mov dword [rsi + 0x2804], 0       ; RDBAH
    mov dword [rsi + 0x2808], 128*16  ; RDLEN
    mov dword [rsi + 0x2810], 0       ; RDH
    mov dword [rsi + 0x2818], 127     ; RDT

    ; TX Registers
    mov rdi, [tx_desc_base]
    mov [rsi + 0x3800], edi           ; TDBAL
    mov dword [rsi + 0x3804], 0       ; TDBAH
    mov dword [rsi + 0x3808], 128*16  ; TDLEN
    mov dword [rsi + 0x3810], 0       ; TDH
    mov dword [rsi + 0x3818], 0       ; TDT

    ; [10] Wait for Link Up (With Safety Timeout)
    mov rcx, 5000000                  ; Maximum loops to wait
.wait_link:
    mov eax, [rsi + 0x0008]           ; Read STATUS
    test eax, 0x02                    ; Bit 1 is Link Up
    jnz .link_up                      ; SUCCESS: Jump out of loop
    dec rcx                           ; Count down
    jnz .wait_link                    ; Keep waiting if not zero
.link_up:

    ; [11] Enable RX & TX with Promiscuous Mode
    ; RCTL: EN(1), SBP(2), UPE(3), MPE(4), BAM(15)
    mov dword [rsi + 0x0100], 0x801E 
    ; TCTL: EN(1), PSP(3)
    mov dword [rsi + 0x0400], 0x000A

    ; [12] Clear/Mask Interrupts (Final safety)
    mov dword [rsi + 0x00D8], 0xFFFFFFFF 
    mov eax, [rsi + 0x00C0]           ; Read ICR to clear

    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret