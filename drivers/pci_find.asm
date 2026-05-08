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

    mov rbx, 0              ; Start at Bus 0
.bus_loop:
    mov rcx, 0              ; Start at Device 0
.dev_loop:
    ; Construct the PCI Address:
    ; Bit 31: Enable bit (1)
    ; Bits 16-23: Bus
    ; Bits 11-15: Device
    ; Bits 8-10: Function (we only check 0)
    ; Bits 0-7: Register (0 for Vendor/Device ID)
    
    mov eax, 0x80000000     ; Set the Enable bit
    
    mov rdx, rbx
    shl rdx, 16
    or eax, edx             ; Add Bus to address
    
    mov rdx, rcx
    shl rdx, 11
    or eax, edx             ; Add Device to address
    
    ; Send address to the PCI Address Port
    mov dx, 0xCF8
    out dx, eax
    
    ; Read the data from the PCI Data Port
    mov dx, 0xCFC
    in eax, dx              ; EAX now contains [DeviceID:VendorID]
    
    ; Check Vendor ID (Lower 16 bits)
    cmp ax, 0x8086          ; 0x8086 = Intel
    jne .next_dev
    
    ; Check Device ID (Upper 16 bits)
    shr eax, 16
    cmp ax, 0x100E          ; 0x100E = QEMU E1000 (usually)
    je .found
    
.next_dev:
    inc rcx
    cmp rcx, 32             ; 32 devices per bus
    jl .dev_loop
    
    inc rbx
    cmp rbx, 5              ; Check first 5 buses (usually enough)
    jl .bus_loop

    ; If we reach here, we found nothing
    mov qword [nic_pci_addr], 0
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
    
    mov [nic_pci_addr], rax ; Save the address for other drivers
    
    pop rdx
    pop rcx
    pop rbx
    pop rax
    mov rax, 1              ; Return success!
    ret