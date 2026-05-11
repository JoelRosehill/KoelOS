cmd_ls db "ls", 0

do_ls:
    call fs_ensure_ready
    test rax, rax
    jz command_done

    call fs_list_files
    jmp command_done
