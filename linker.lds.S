ENTRY(_start)

PHDRS
{
    boot   PT_LOAD FLAGS(5);   /* R + X */
    text   PT_LOAD FLAGS(5);   /* R + X */
    rodata PT_LOAD FLAGS(4);   /* R     */
    data   PT_LOAD FLAGS(6);   /* R + W */

    /* TEMP: for user-space */
    user_text PT_LOAD FLAGS(5);  /* R + X - user code + rodata */
    user_data PT_LOAD FLAGS(6);  /* R + W - user data + bss + stack */
}

SECTIONS
{
    . = 0x00100000;

    .boot : {
        KEEP(*(.multiboot))
        *(.boot)
        *(.boot.text)
        *(.boot.data)
        *(.boot.bss)
        . = ALIGN(16);
    } :boot

    __boot_end = .;

    . += 0xC0000000;

    .text : AT(ADDR(.text) - 0xC0000000) {
        *(.text)
        *(.text.*)
    } :text

    .rodata : AT(ADDR(.rodata) - 0xC0000000) {
        *(.rodata)
        *(.rodata.*)
    } :rodata

    .eh_frame : AT(ADDR(.eh_frame) - 0xC0000000) {
        *(.eh_frame)
        *(.eh_frame_hdr)
    } :rodata

    .data : AT(ADDR(.data) - 0xC0000000) {
        *(.data)
        *(.data.*)
        *(.got)
        *(.got.plt)

        #include "source/arch/x86/kernel/init.data.ldh"
    } :data

    .init_array : AT(ADDR(.init_array) - 0xC0000000) {
        __init_array_start = .;
        KEEP(*(.init_array))
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*)))
        __init_array_end = .;
    } :data

    .fini_array : AT(ADDR(.fini_array) - 0xC0000000) {
        __fini_array_start = .;
        KEEP(*(.fini_array))
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*)))
        __fini_array_end = .;
    } :data

    .bss : AT(ADDR(.bss) - 0xC0000000) {
        *(COMMON)
        *(.bss)
        *(.bss.*)
    } :data

    __kernel_end = .;
    __kernel_end_phys = . - 0xC0000000;

    . = 0x00400000;

    .user_text ALIGN(0x1000) : AT(0x00400000) {
        __user_text_start = .;
        KEEP(*(.user.entry))
        *(.user)
        *(.user.text)
        *(.user.text.*)
        *(.user.rodata)
        *(.user.rodata.*)
        . = ALIGN(0x1000);
        __user_text_end = .;
    } :user_text

    .user_data ALIGN(0x1000) : AT(0x00400000 + SIZEOF(.user_text)) {
        __user_data_start = .;
        *(.user.data)
        *(.user.data.*)
        . = ALIGN(0x1000);
        __user_data_end = .;
    } :user_data

    .user_bss (NOLOAD) : AT(0x00400000 + SIZEOF(.user_text) + SIZEOF(.user_data)) {
        __user_bss_start = .;
        *(.user.bss)
        *(.user.bss.*)
        . = ALIGN(0x1000);
        __user_bss_end = .;
    } :user_data

    __user_entry = __user_text_start;   /* or override below */

    /* Fixed user stack region. Stacks grow down, so ESP starts at the top. */
    . = 0x00800000;

    .user_stack (NOLOAD) : AT(0x00800000) {
        __user_stack_bottom = .;
        . += 0x10000;             /* 64 KiB */
        __user_stack_top = .;
    } :user_data

    ASSERT(__kernel_end_phys <= 0x00400000,
           "Kernel physical end exceeds 0x400000 - user code at 0x400000 would overwrite kernel .bss")
    ASSERT(0x00800000 >= __user_bss_end,
           "User text+data+bss run into user stack at 0x800000")
}
