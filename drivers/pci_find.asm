; ==========================================
; PCI Bus Scanner - Finding the E1000
; ==========================================

; This will store the PCI address of the NIC once found
; Format: 0x80BB DDFR (B=Bus, D=Device, F=Function, R=Register)

find_nic:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    mov rbx, 0              ; Start at Bus 0
.bus_loop:
    mov rcx, 0              ; Start at Device 0
.dev_loop:
    mov rsi, 0              ; Start at Function 0
.func_loop:
    ; Construct the PCI Address:
    ; Bit 31: Enable bit (1)
    ; Bits 16-23: Bus
    ; Bits 11-15: Device
    ; Bits 8-10: Function
    ; Bits 0-7: Register (0 for Vendor/Device ID)
    mov eax, 0x80000000

    mov rdx, rbx
    shl rdx, 16
    or eax, edx

    mov rdx, rcx
    shl rdx, 11
    or eax, edx

    mov rdx, rsi
    shl rdx, 8
    or eax, edx

    mov dx, 0xCF8
    out dx, eax

    mov dx, 0xCFC
    in eax, dx              ; EAX now contains [DeviceID:VendorID]

    cmp ax, 0x8086          ; 0x8086 = Intel
    jne .next_func

    ; Common VirtualBox Intel PRO/1000 device IDs
    shr eax, 16
    cmp ax, 0x100E          ; 82540EM
    je .found
    cmp ax, 0x100F          ; 82545EM
    je .found
    cmp ax, 0x1004          ; 82543GC
    je .found

.next_func:
    inc rsi
    cmp rsi, 8
    jl .func_loop

    inc rcx
    cmp rcx, 32             ; 32 devices per bus
    jl .dev_loop
    
    inc rbx
    cmp rbx, 16             ; Check more buses for safety
    jl .bus_loop

    ; If we reach here, we found nothing
    mov qword [nic_pci_addr], 0
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    mov rax, 0              ; Return failure
    ret

.found:
    ; Reconstruct the address one last time to save it
    mov eax, 0x80000000
    mov rdx, rbx
    shl rdx, 16
    or eax, edx
    mov rdx, rcx
    shl rdx, 11
    or eax, edx
    mov rdx, rsi
    shl rdx, 8
    or eax, edx
    
    mov [nic_pci_addr], rax ; Save the address for other drivers
    
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    mov rax, 1              ; Return success!
    ret
