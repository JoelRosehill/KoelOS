cmd_date db "date", 0

do_date:
    call rtc_get_time

    mov al, '2'                ; assume the 21st century
    call print_char
    mov al, '0'
    call print_char
    mov al, [rtc_year]
    call print_two_digits
    mov al, '-'
    call print_char
    mov al, [rtc_month]
    call print_two_digits
    mov al, '-'
    call print_char
    mov al, [rtc_day]
    call print_two_digits
    mov al, ' '
    call print_char
    mov al, [rtc_hour]
    call print_two_digits
    mov al, ':'
    call print_char
    mov al, [rtc_min]
    call print_two_digits
    mov al, ':'
    call print_char
    mov al, [rtc_sec]
    call print_two_digits
    call newline
    jmp command_done
