[bits 64]
[org 0x10000]
default rel             ; Use RIP-relative addressing for stability

_start:
    call clear_screen
    lea rsi, [msg_welcome] ; Use LEA for rip-relative addressing
    call print_string
    call newline
    call print_prompt

; --- THE MAIN OS LOOP ---
keyboard_loop:
    in al, 0x64            
    and al, 1
    jz keyboard_loop       

    in al, 0x60            
    test al, 0x80          
    jnz keyboard_loop      

    cmp al, 0x1C        ; ENTER
    je handle_enter

    cmp al, 0x0E        ; BACKSPACE
    je .handle_backspace

    xor rbx, rbx
    mov bl, al             
    lea rcx, [keymap]
    mov al, [rcx + rbx] 
    test al, al            
    jz keyboard_loop       

    mov rbx, [input_length]
    cmp rbx, 255           
    jge keyboard_loop
    
    lea rdi, [input_buffer]
    mov [rdi + rbx], al
    inc qword [input_length]
    
    call print_char        
    jmp keyboard_loop

.handle_backspace:
    cmp qword [input_length], 0
    je keyboard_loop       
    
    dec qword [input_length]
    mov rbx, [input_length]
    lea rdi, [input_buffer]
    mov byte [rdi + rbx], 0 
    
    call do_backspace      
    jmp keyboard_loop

; --- COMMAND PARSER ---
handle_enter:
    mov rbx, [input_length]
    lea rdi, [input_buffer]
    mov byte [rdi + rbx], 0 
    call newline

    cmp qword [input_length], 0
    je command_done

    ; --- ARGUMENT SPLITTER ---
    lea rsi, [input_buffer]
    lea rdi, [arg_buffer]
    mov byte [rdi], 0      
.split_loop:
    mov al, [rsi]
    test al, al
    jz .search             
    cmp al, ' '
    je .found_space
    inc rsi
    jmp .split_loop
.found_space:
    mov byte [rsi], 0      
    inc rsi                
.copy_args:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .search
    inc rsi
    inc rdi
    jmp .copy_args

.search:
    lea rbx, [command_table]
.search_loop:
    mov rdi, [rbx]      
    test rdi, rdi       
    jz .unknown_cmd

    push rbx            
    lea rsi, [input_buffer]
    call strcmp
    pop rbx             

    cmp rax, 1
    je .found_cmd

    add rbx, 16         
    jmp .search_loop

.found_cmd:
    jmp [rbx + 8]       

.unknown_cmd:
    lea rsi, [msg_unknown]
    call print_string
    call newline

command_done:
    mov qword [input_length], 0
    call print_prompt
    jmp keyboard_loop

; --- EXTERNAL FILES ---
%include "helpers.asm"

; --- GLOBAL DATA SECTION ---
; This is the "Central Registry" for all system variables
cursor_pos    dq 0xb8000
input_buffer  times 256 db 0  
arg_buffer    times 256 db 0
input_length  dq 0            
current_color db 0x1F         

; --- MEMORY MANAGEMENT ---
heap_current  dq 0x200000     ; Start allocating memory at the 2MB mark

; --- NETWORK DRIVER VARIABLES ---
nic_pci_addr  dq 0            ; Found by pci_find.asm
nic_mem_base  dq 0            ; Memory address (BAR0)
rx_desc_base  dq 0            ; Receive Descriptor start
tx_desc_base  dq 0            ; Transmit Descriptor start
rx_curr       dq 0            ; Current RX pointer
tx_tail       dq 0            ; Current TX pointer

; --- NETWORK IDENTITY ---
my_mac        db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 ; Default QEMU MAC
my_ip         db 10, 0, 2, 15                       ; Default QEMU IP

; --- SYSTEM MESSAGES ---
msg_welcome   db "KoelOS v1.2 [Automated Shell]", 0
msg_prompt    db "root@koelos> ", 0
msg_unknown   db "Error: Unknown command.", 0

keymap:
    db 0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0, 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0, 0
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0, '\'
    db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' ', 0
    times 128 db 0

; --- AUTO-GENERATED APP TABLE ---
%include "build/generated_apps.asm"
