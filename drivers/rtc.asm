; drivers/rtc.asm
; CMOS real-time clock reader. Gives KoelOS a notion of wall-clock time and
; uptime without needing interrupts or a PIT.

%define CMOS_ADDR 0x70
%define CMOS_DATA 0x71

; Read CMOS register BL into AL.
cmos_read:
    mov al, bl
    out CMOS_ADDR, al
    in al, CMOS_DATA
    ret

; Spin until the RTC is not mid-update (status A bit 7 clear).
rtc_wait_ready:
    push rax
    push rbx
.loop:
    mov bl, 0x0A
    call cmos_read
    test al, 0x80
    jnz .loop
    pop rbx
    pop rax
    ret

; Convert a packed BCD byte in AL to binary in AL.
bcd_to_bin:
    push rcx
    mov cl, al
    and cl, 0x0F            ; low digit
    shr al, 4              ; high digit
    movzx eax, al
    lea eax, [eax + eax*4]  ; *5
    add eax, eax           ; *10
    add al, cl
    pop rcx
    ret

; Read the clock into rtc_sec/min/hour/day/month/year (all binary).
rtc_get_time:
    push rax
    push rbx

    call rtc_wait_ready

    mov bl, 0x00
    call cmos_read
    mov [rtc_sec], al
    mov bl, 0x02
    call cmos_read
    mov [rtc_min], al
    mov bl, 0x04
    call cmos_read
    mov [rtc_hour], al
    mov bl, 0x07
    call cmos_read
    mov [rtc_day], al
    mov bl, 0x08
    call cmos_read
    mov [rtc_month], al
    mov bl, 0x09
    call cmos_read
    mov [rtc_year], al

    mov bl, 0x0B
    call cmos_read
    test al, 0x04          ; status B bit 2 set => values already binary
    jnz .done

    mov al, [rtc_sec]
    call bcd_to_bin
    mov [rtc_sec], al
    mov al, [rtc_min]
    call bcd_to_bin
    mov [rtc_min], al
    mov al, [rtc_hour]
    call bcd_to_bin
    mov [rtc_hour], al
    mov al, [rtc_day]
    call bcd_to_bin
    mov [rtc_day], al
    mov al, [rtc_month]
    call bcd_to_bin
    mov [rtc_month], al
    mov al, [rtc_year]
    call bcd_to_bin
    mov [rtc_year], al

.done:
    pop rbx
    pop rax
    ret

; Seconds elapsed since midnight from the cached rtc_* values -> RAX.
rtc_seconds_of_day:
    push rcx
    push rdx
    movzx eax, byte [rtc_hour]
    mov ecx, 3600
    mul ecx                ; EAX = hour*3600
    movzx ecx, byte [rtc_min]
    imul ecx, ecx, 60
    add eax, ecx
    movzx ecx, byte [rtc_sec]
    add eax, ecx
    mov ecx, eax           ; zero-extend into RAX
    mov eax, ecx
    pop rdx
    pop rcx
    ret

; Snapshot boot time so `uptime` can diff against it.
rtc_capture_boot:
    push rax
    call rtc_get_time
    call rtc_seconds_of_day
    mov [boot_seconds], rax
    pop rax
    ret

; Print AL (0-99) as exactly two decimal digits. Preserves registers.
print_two_digits:
    push rax
    push rcx
    movzx eax, al
    mov cl, 10
    div cl                 ; AL = tens, AH = ones
    push rax
    add al, '0'
    call print_char
    pop rax
    mov al, ah
    add al, '0'
    call print_char
    pop rcx
    pop rax
    ret

; --- RTC state ---
rtc_sec       db 0
rtc_min       db 0
rtc_hour      db 0
rtc_day       db 0
rtc_month     db 0
rtc_year      db 0
boot_seconds  dq 0
