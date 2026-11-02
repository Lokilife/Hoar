BITS 32

section .multiboot align=4
    dd 0x1BADB002
    dd 1 << 0 | 1 << 1
    dd -(0x1BADB002 + (1 << 0 | 1 << 1))

section .boot

global _start:function (_start.end - _start)

PAGE_OFFSET equ 0xC0000000

extern multiboot1Entry

_start:
    cli
    ; EAX = magic, EBX = info
    mov esp, boot_stack_top

    mov [0x00007000], eax
    mov [0x00007004], ebx

    ; PD: static page
    mov edi, pd_area
    xor eax, eax
    mov ecx, 1024
    rep stosd

    ; PDE[0] = identity map of first 4 MB
    mov dword [pd_area], 0x00000083

    ; PDE[768..1023] = direct map
    mov ecx, 768
    xor eax, eax
.fill:
    mov edx, eax
    or  edx, 0x00000083
    mov [pd_area + ecx*4], edx
    add eax, 0x00400000
    inc ecx
    cmp ecx, 1024
    jl  .fill

    ; Enable PSE (4 MB pages)
    mov eax, cr4
    or  eax, 0x00000010       ; CR4.PSE
    mov cr4, eax

    ; CR3 = pd_area physical address (low-end)
    mov eax, pd_area
    mov cr3, eax

    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax

    add esp, PAGE_OFFSET
    mov eax, multiboot1Entry
    jmp eax
.end:

section .boot.bss nobits
align 16
boot_stack_bottom:
    resb 4096
boot_stack_top:
alignb 4096
pd_area:
    resb 4096

section .data
global kernel_stack_top
kernel_stack_top equ boot_stack_top + PAGE_OFFSET
