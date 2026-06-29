[bits 64]
[org 0x10000]
default rel             ; Use RIP-relative addressing for stability

_start:
    call serial_init       ; bring up COM1 so console output is mirrored
    call rtc_capture_boot  ; snapshot boot time for `uptime`
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

    cmp al, 0xE0        ; EXTENDED-KEY PREFIX (arrows, etc.)
    je .set_extended
    cmp byte [kbd_extended], 0
    jne .handle_extended

    cmp al, 0x1C        ; ENTER
    je handle_enter

    cmp al, 0x0E        ; BACKSPACE
    je .handle_backspace

    call kbd_translate_scancode
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

.set_extended:
    mov byte [kbd_extended], 1
    jmp keyboard_loop

.handle_extended:
    mov byte [kbd_extended], 0
    cmp al, 0x48           ; UP ARROW -> previous history entry
    je .history_up
    cmp al, 0x50           ; DOWN ARROW -> next history entry
    je .history_down
    jmp keyboard_loop

.history_up:
    call history_prev
    jmp keyboard_loop

.history_down:
    call history_next
    jmp keyboard_loop

; --- COMMAND PARSER ---
handle_enter:
    mov rbx, [input_length]
    lea rdi, [input_buffer]
    mov byte [rdi + rbx], 0 
    call newline

    cmp qword [input_length], 0
    je command_done

    call history_add        ; remember the raw command before it is split

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

; --- COMMAND HISTORY ---
; Ring buffer of recent command lines, browsed with the up/down arrows.
; The backing store lives in free RAM (HISTORY_BASE) to keep kernel.bin small.
%define HISTORY_SIZE  8                 ; entries (must stay a power of two)
%define HISTORY_STRIDE 256             ; bytes per entry
%define HISTORY_BASE  0x300000         ; identity-mapped scratch RAM

; Copy the current input line into the ring and reset the browse cursor.
history_add:
    push rax
    push rcx
    push rsi
    push rdi

    mov rax, [history_write]
    shl rax, 8                  ; * HISTORY_STRIDE
    mov rdi, HISTORY_BASE
    add rdi, rax
    lea rsi, [input_buffer]
.copy:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .copied
    inc rsi
    inc rdi
    jmp .copy
.copied:
    mov rax, [history_write]
    inc rax
    and rax, HISTORY_SIZE - 1
    mov [history_write], rax

    mov rax, [history_count]
    cmp rax, HISTORY_SIZE
    jae .pos
    inc rax
    mov [history_count], rax
.pos:
    mov rax, [history_count]    ; park cursor past the newest entry
    mov [history_pos], rax

    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; Erase the visible input line and clear the input buffer state.
history_clear_line:
    push rax
.loop:
    cmp qword [input_length], 0
    je .done
    call do_backspace
    dec qword [input_length]
    jmp .loop
.done:
    mov byte [input_buffer], 0
    pop rax
    ret

; Load the entry at the logical [history_pos] into the input line and echo it.
history_load:
    push rax
    push rcx
    push rsi
    push rdi

    call history_clear_line

    mov rax, [history_write]    ; slot = (write - count + pos) mod SIZE
    sub rax, [history_count]
    add rax, [history_pos]
    add rax, HISTORY_SIZE * 2   ; bias positive before masking
    and rax, HISTORY_SIZE - 1
    shl rax, 8                  ; * HISTORY_STRIDE
    mov rsi, HISTORY_BASE
    add rsi, rax

    lea rdi, [input_buffer]
    xor rcx, rcx
.copy:
    mov al, [rsi + rcx]
    test al, al
    jz .copied
    mov [rdi + rcx], al
    inc rcx
    cmp rcx, 255
    jb .copy
.copied:
    mov byte [rdi + rcx], 0
    mov [input_length], rcx

    mov rsi, rdi
    call print_string

    pop rdi
    pop rsi
    pop rcx
    pop rax
    ret

; Up arrow: step back toward older commands.
history_prev:
    cmp qword [history_count], 0
    je .done
    cmp qword [history_pos], 0
    je .done
    dec qword [history_pos]
    call history_load
.done:
    ret

; Down arrow: step toward newer commands, ending on a blank line.
history_next:
    mov rax, [history_pos]
    cmp rax, [history_count]
    jae .done
    inc rax
    mov [history_pos], rax
    cmp rax, [history_count]
    je .blank
    call history_load
    ret
.blank:
    call history_clear_line
.done:
    ret

; --- EXTERNAL FILES ---
%include "helpers.asm"

; --- GLOBAL DATA SECTION ---
; This is the "Central Registry" for all system variables
cursor_pos    dq 0xb8000
input_buffer  times 256 db 0  
arg_buffer    times 256 db 0
input_length  dq 0
current_color db 0x1F
shift_state   db 0
kbd_extended  db 0            ; set after an 0xE0 scancode prefix

; --- COMMAND HISTORY STATE (ring metadata; data lives at HISTORY_BASE) ---
history_count dq 0            ; number of stored entries (caps at HISTORY_SIZE)
history_write dq 0            ; next ring slot to write
history_pos   dq 0            ; browse cursor (== history_count means blank line)

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

; --- STORAGE ---
fs_ready         db 0
fs_sector_buffer times 512 db 0
fs_dir_buffer    equ 0x301000   ; 8KB directory cache in scratch RAM (kept out of kernel.bin)
fs_parse_buffer  times 256 db 0

; --- SYSTEM MESSAGES ---
msg_welcome   db "KoelOS v1.6", 0
msg_prompt    db "root@koelos> ", 0
msg_unknown   db "Error: Unknown command.", 0

keymap:
    db 0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 0, 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 0, 0
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0, '\'
    db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' ', 0
    times 128 db 0

keymap_shift:
    db 0, 0, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 0, 0
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 0, 0
    db 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0, '|'
    db 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' ', 0
    times 128 db 0

; --- AUTO-GENERATED APP TABLE ---
%include "build/generated_apps.asm"
