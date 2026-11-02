module kernel.core.idt;

import arch.cpu;
import arch.x86.cpu;
import gdt = kernel.core.gdt;
import kernel.core.kthread;
import kernel.core.debugging;
import kernel.core.syscall;

public struct InterruptFrame32
{
    align(1):
    uint gs, fs, es, ds;
    uint edi, esi, ebp, esp, ebx, edx, ecx, eax;
    uint int_no, error_code;
    uint eip, cs, eflags;
}

alias InterruptHandler = extern (C) int function(InterruptFrame32* frame);

extern (C)
{
    __gshared InterruptHandler[256] interruptHandlers = [
        0:   &divisionError,
        8:   &doubleFault,
        13:  &generalProtection,
        14:  &pageFault,
        128: &syscall,
    ];

    int divisionError(InterruptFrame32 *frame)
    {
        disableInterrupts();
        debugPrintln("#DE occured");
        debugPrintln("Kernel halted");

        waitForInterrupt();
        return 0;
    }

    int doubleFault(InterruptFrame32 *frame)
    {
        disableInterrupts();
        debugPrintln("#DF occured");
        debugPrint(" at eip=");
        debugPrintHex(frame.eip);
        debugPrintln();
        debugPrint(" err=");
        debugPrintHex(frame.error_code);
        debugPrintln();
        debugPrint(" cs=");
        debugPrintHex(frame.cs);
        debugPrintln();
        debugPrint(" eflags=");
        debugPrintHex(frame.eflags);
        debugPrintln();

        debugPrintln("Kernel halted");

        waitForInterrupt();
        return 0;
    }

    int generalProtection(InterruptFrame32 *frame)
    {
        disableInterrupts();
        debugPrintln("#GP occured");
        debugPrint(" at eip=");
        debugPrintHex(frame.eip);
        debugPrintln();
        debugPrint(" err=");
        debugPrintHex(frame.error_code);
        debugPrintln();
        debugPrint(" cs=");
        debugPrintHex(frame.cs);
        debugPrintln();
        debugPrint(" eflags=");
        debugPrintHex(frame.eflags);
        debugPrintln();

        threadExit();

        debugPrintln("Unreachable code reached: Kernel halted");

        waitForInterrupt();
        return 0;
    }

    int pageFault(InterruptFrame32 *frame)
    {
        disableInterrupts();
        debugPrintln("#PF occured");
        debugPrint(" at eip=");
        debugPrintHex(frame.eip);
        debugPrintln();
        debugPrint(" err=");
        debugPrintHex(frame.error_code);
        debugPrintln();
        debugPrint(" cs=");
        debugPrintHex(frame.cs);
        debugPrintln();
        debugPrint(" eflags=");
        debugPrintHex(frame.eflags);
        debugPrintln();
        debugPrint(" cr2=");
        debugPrintHex(ia32_read_cr2());
        debugPrintln();

        debugPrintln("Kernel halted");

        waitForInterrupt();
        return 0;
    }

    int syscall(InterruptFrame32 *frame)
    {
        syscallHandler(frame);
        return 0;
    }

    /// Used when exception stub failed to dispatch handler
    void fallbackInterruptHandler(InterruptFrame32 *frame)
    {
        disableInterrupts();

        debugPrint("Unhandled interrupt: ");
        debugPrintInt(frame.int_no);
        debugPrintln();
        debugPrint(" at eip=");
        debugPrintHex(frame.eip);
        debugPrintln();
        debugPrint(" err=");
        debugPrintHex(frame.error_code);
        debugPrintln();
        debugPrint(" cs=");
        debugPrintHex(frame.cs);
        debugPrintln();
        debugPrint(" eflags=");
        debugPrintHex(frame.eflags);
        debugPrintln();

        waitForInterrupt();
        return;
    }
}

public void setInterrupt(ubyte intNo, InterruptHandler handler) nothrow @nogc
{
    interruptHandlers[intNo] = handler;
}
