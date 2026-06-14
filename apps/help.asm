cmd_help db "help", 0

; Walk the auto-generated command_table so every installed command is listed,
; and print a short description for the ones we have text for.
do_help:
    lea rbx, [command_table]
.loop:
    mov rsi, [rbx]
    test rsi, rsi
    jz .done

    push rbx
    call print_string          ; command name

    mov rsi, [rbx]             ; pad the name out to a fixed column
    call help_strlen
    mov ecx, 12
    sub ecx, eax
    jle .desc
.pad:
    push rcx
    mov al, ' '
    call print_char
    pop rcx
    dec ecx
    jnz .pad

.desc:
    mov rsi, [rbx]
    call help_find_desc
    test rax, rax
    jz .nl
    mov rsi, rax
    call print_string
.nl:
    call newline
    pop rbx
    add rbx, 16
    jmp .loop
.done:
    jmp command_done

; RSI = string -> EAX = length (preserves RSI)
help_strlen:
    push rsi
    xor eax, eax
.l:
    cmp byte [rsi], 0
    je .d
    inc rsi
    inc eax
    jmp .l
.d:
    pop rsi
    ret

; RSI = command-name ptr -> RAX = description ptr or 0 (preserves RBX, RSI)
help_find_desc:
    push rbx
    push rsi
    lea rbx, [help_desc]
.l:
    mov rax, [rbx]
    test rax, rax
    jz .none
    cmp rax, rsi
    je .found
    add rbx, 16
    jmp .l
.found:
    mov rax, [rbx + 8]
    pop rsi
    pop rbx
    ret
.none:
    xor eax, eax
    pop rsi
    pop rbx
    ret

help_desc:
    dq cmd_alkan,    hd_alkan
    dq cmd_announce, hd_announce
    dq cmd_binwrite, hd_binwrite
    dq cmd_browser,  hd_browser
    dq cmd_cat,      hd_cat
    dq cmd_clear,    hd_clear
    dq cmd_colors,   hd_colors
    dq cmd_cp,       hd_cp
    dq cmd_date,     hd_date
    dq cmd_dhcp,     hd_dhcp
    dq cmd_diag,     hd_diag
    dq cmd_dns,      hd_dns
    dq cmd_echo,     hd_echo
    dq cmd_edit,     hd_edit
    dq cmd_fetch,    hd_fetch
    dq cmd_format,   hd_format
    dq cmd_help,     hd_help
    dq cmd_hex,      hd_hex
    dq cmd_ifconfig, hd_ifconfig
    dq cmd_ip,       hd_ip
    dq cmd_listen,   hd_listen
    dq cmd_ls,       hd_ls
    dq cmd_mem,      hd_mem
    dq cmd_mkfile,   hd_mkfile
    dq cmd_mv,       hd_mv
    dq cmd_netinit,  hd_netinit
    dq cmd_ping,     hd_ping
    dq cmd_reboot,   hd_reboot
    dq cmd_rm,       hd_rm
    dq cmd_shutdown, hd_shutdown
    dq cmd_uptime,   hd_uptime
    dq cmd_ver,      hd_ver
    dq 0, 0

hd_alkan    db "run the Alkan language (REPL or file)", 0
hd_announce db "broadcast a hello packet on the LAN", 0
hd_binwrite db "write hex bytes into a binary file", 0
hd_browser  db "fetch and render a web page as text", 0
hd_cat      db "print a text file", 0
hd_clear    db "clear the screen", 0
hd_colors   db "show the VGA color palette", 0
hd_cp       db "copy a file", 0
hd_date     db "show the current date and time", 0
hd_dhcp     db "request an IP lease over DHCP", 0
hd_diag     db "run network diagnostics", 0
hd_dns      db "resolve a hostname to an IP", 0
hd_echo     db "print the given text", 0
hd_edit     db "line editor for text files", 0
hd_fetch    db "HTTP GET a URL", 0
hd_format   db "reformat the storage volume", 0
hd_help     db "list commands", 0
hd_hex      db "hex-dump a file", 0
hd_ifconfig db "show interface configuration", 0
hd_ip       db "show or set the IPv4 address", 0
hd_listen   db "listen for incoming packets", 0
hd_ls       db "list files", 0
hd_mem      db "show heap usage", 0
hd_mkfile   db "create an empty file", 0
hd_mv       db "rename a file", 0
hd_netinit  db "bring up the network card", 0
hd_ping     db "send an ICMP echo request", 0
hd_reboot   db "restart the machine", 0
hd_rm       db "delete a file", 0
hd_shutdown db "power off the machine", 0
hd_uptime   db "show time since boot", 0
hd_ver      db "show the OS version", 0
