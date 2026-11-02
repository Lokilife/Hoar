module arch.cpu;

import arch.x86.cpu;
// import arch.arm.cpu;
// import arch.riscv32.cpu;

/// Calls processor instruction that will leave processor on hanging state 'till the next interrupt
pragma(inline, true)
public void waitForInterrupt() @nogc nothrow
{
    version (X86_64) ia32_hlt();
    else version (X86) ia32_hlt();
    // else version (AArch64) __arm_wfi();
    // else version (ARM) __arm_wfi();
    // else version (RISCV64) __riscv32_wfi();
}

pragma(inline, true)
public void enableInterrupts() @nogc nothrow
{
    ia32_sti();
}

pragma(inline, true)
public size_t disableInterrupts() @nogc nothrow
{
    size_t flags = ia32_save_if();
    ia32_cli();
    return flags;
}

pragma(inline, true)
public void restoreInterrupts(size_t flags) @nogc nothrow
{
    ia32_restore_if(flags);
}

pragma(inline, true)
public void ioWait() @nogc nothrow
{
    // Write a zero byte to the unused port 0x80 to create a short delay.
    ia32_outb(0x80, 0);
}
