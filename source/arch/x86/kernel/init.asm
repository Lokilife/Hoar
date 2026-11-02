BITS 32

extern kernel_stack_top

section .data

; Here is described IA32 early kernel init
; - Load GDT and far jump
; - Load IDT
; - Describe TSS

global ia32_tss_segment
global ia32_tss_segment_end
global ia32_tss_esp0

ia32_tss_segment:
    dw 0 ; Previous Task Link
    dw 0 ; Reserved 2
ia32_tss_esp0:
    dd kernel_stack_top ; ESP0
    dw 0x10 ; SS0
    dw 0 ; Reserved 10
    dd 0 ; ESP1
    dw 0 ; SS1
    dw 0 ; Reserved 18
    dd 0 ; ESP2
    dw 0 ; SS2
    dw 0 ; Reserved 26
    dd 0 ; CR3
    dd 0 ; EIP
    dd 0 ; EFLAGS
    dd 0 ; EAX
    dd 0 ; ECX
    dd 0 ; EDX
    dd 0 ; EBX
    dd 0 ; ESP
    dd 0 ; EBP
    dd 0 ; ESI
    dd 0 ; EDI
    dw 0 ; ES
    dw 0 ; Reserved
    dw 0 ; CS
    dw 0 ; Reserved
    dw 0 ; SS
    dw 0 ; Reserved
    dw 0 ; DS
    dw 0 ; Reserved
    dw 0 ; FS
    dw 0 ; Reserved
    dw 0 ; GS
    dw 0 ; Reserved
    dw 0 ; LDT Segment Selector
    dw 0
    dw 0
    dw 0x6C ; IO Map Base Address
    dd 0 ; Shadow Stack Pointer
ia32_tss_segment_end:

extern gdtr
extern idtr

section .text

global ia32_early_kernel_init
ia32_early_kernel_init:
    lgdt [gdtr]

    ; Reload CS (Code Segment) register using an absolute far jump
    jmp 0x08:.1

.1:
    ; Reload Data Segment selectors
    mov ax, 0x10            ; Load DS into AX
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    lidt [idtr]

    mov ax, 0x28
    ltr ax

    ret

%include "source/arch/x86/kernel/interrupts.inc"
