BITS 32

section .text
global ia32_context_switch

; void ia32_context_switch(Thread* from, Thread* to)
;   [esp+4]  = from
;   [esp+8]  = to
ia32_context_switch:
    push ebp
    push ebx
    push esi
    push edi

    mov eax, [esp + 20]         ; from (4 pushes + return = 20)
    test eax, eax
    jz .no_save
    mov [eax + 0], esp          ; from->esp = esp

.no_save:
    mov eax, [esp + 24]         ; to
    mov esp, [eax + 0]          ; esp = to->esp

    pop edi
    pop esi
    pop ebx
    pop ebp

    ret

global threadStartup
threadStartup:
    sti
    ret
