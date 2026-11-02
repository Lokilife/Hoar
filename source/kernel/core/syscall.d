module kernel.core.syscall;

import arch.cpu;
import kernel.core.idt;
import kernel.core.kthread;
import kernel.core.debugging;
import vmm = kernel.core.vmm;

public void syscallHandler(InterruptFrame32* frame) @nogc nothrow
{
    // uint flags = disableInterrupts();
    // scope(exit) restoreInterrupts(flags);

    debug debugPrint("[syscall]: Syscall ");
    debug debugPrintInt(frame.eax);
    debug debugPrintln();

    switch (frame.eax)
    {
        case 1:
            debugPrintln("Kernel halted");
            waitForInterrupt();
            break;
        case 2:
            size_t buf = frame.ebx;
            size_t len = frame.ecx;

            if (!vmm.userCanAccess(buf, len))
            {
                frame.eax = cast(uint)-1;
                break;
            }

            vgaPrint(cast(const(char)[]) (cast(void*)buf)[0 .. len]);
            frame.eax = cast(uint) len;

            break;
        case 3:
            debug debugPrint("[syscall]: Thread ");
            debug debugPrintUint(currentKThread.id);
            debug debugPrintln(" exited");
            threadExit();
            break;
        default: break;
    }
}

private __gshared uint vgaCol;
private __gshared uint vgaRow;
immutable vgaWidth = 80;
immutable vgaHeight = 80;

private void vgaPutc(ubyte ch) @nogc nothrow
{
    ubyte* vidmem = cast(ubyte*)(0xB8000+0xC0000000); // Video memory address

    if (vgaCol > vgaWidth)
    {
        vgaCol = 0;
        vgaRow++;
    }

    immutable offset = (vgaCol + vgaRow * vgaHeight) * 2;

    *(vidmem + offset) = ch & 0xFF;
    *(vidmem + offset + 1) = 0x07; // Sets the colour for D to be light grey (0x07)

    vgaCol++;
}

private void vgaPrint(S)(scope S s) @nogc nothrow
    if (is(S : const(char)[]) || is(S : const(ubyte)[]))
{
    foreach (c; s) vgaPutc(c);
}
