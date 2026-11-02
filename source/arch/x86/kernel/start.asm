BITS 32

section .text

extern __user_stack_top
extern __user_entry

global enter_user_mode
enter_user_mode:
    mov ax, 0x20 | 3
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    push dword 0x20 | 3          ; SS   (user data, RPL=3)
    push dword __user_stack_top  ; ESP
    pushfd
    or   dword [esp], 0x200      ; IF=1 so timer/keyboard work in user mode
    push dword 0x18 | 3          ; CS   (user code, RPL=3)
    push dword __user_entry      ; EIP

    iret
