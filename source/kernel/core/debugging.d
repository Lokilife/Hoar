module kernel.core.debugging;

import arch.x86.cpu;

// debugPrint family for QEMU/Bochs port 0xE9 debug console.

private enum DEBUG_PORT = 0xE9;

/// Emit a single character to the debug console.
pragma(inline, true)
public void debugPutc(char c) @nogc nothrow
{
    ia32_outb(DEBUG_PORT, cast(ubyte)c);
}

pragma(inline, true)
public void debugPrint(S)(scope S s) @nogc nothrow
    if (is(S : const(char)[]) || is(S : const(ubyte)[]))
{
    foreach (c; s)
        ia32_outb(0xE9, cast(ubyte)c);
}

/// Print an unsigned integer in the given base (2..16).
pragma(inline, true)
public void debugPrintUint(size_t value, uint base = 10, bool pad = false,
                      size_t width = 0) @nogc nothrow
{
    assert(base >= 2 && base <= 16);
    enum hex = "0123456789abcdef";

    char[64] buf;
    size_t i = buf.length;

    if (value == 0)
        buf[--i] = '0';
    else
        while (value != 0)
        {
            buf[--i] = hex[cast(size_t)(value % base)];
            value /= base;
        }

    if (pad && width > 0)
        while (buf.length - i < width)
            buf[--i] = '0';

    debugPrint(buf[i .. $]);
}

/// Print a signed integer in base 10.
pragma(inline, true)
public void debugPrintInt(size_t value, bool pad = false, size_t width = 0)
 @nogc nothrow
{
    if (value < 0)
    {
        debugPutc('-');
        // Careful with int.min — negate in unsigned space.
        debugPrintUint(cast(size_t)(-value), 10, pad, width);
    }
    else
        debugPrintUint(cast(size_t)value, 10, pad, width);
}

/// Print a value as hexadecimal, optionally zero-padded (e.g. 0xDEADBEEF).
pragma(inline, true)
public void debugPrintHex(size_t value, size_t width = 0) @nogc nothrow
{
    debugPrint("0x");
    debugPrintUint(value, 16, true, width);
}

/// Print with a trailing newline.
pragma(inline, true)
extern (C) public void debugPrintln(scope const(char)[] s) @nogc nothrow
{
    debugPrint(s);
    debugPutc('\r');
    debugPutc('\n');
}

pragma(inline, true)
public void debugPrintln() @nogc nothrow
{
    debugPutc('\r');
    debugPutc('\n');
}

// Functions that can cause CPU exceptions for testing purposes

void triggerDivideError() @nogc nothrow
{
    debugPrintln("Triggering #DE...");

    asm @nogc nothrow {
        "xorl   %%edx,  %%edx;"~    // Clear EDX for the dividend (EDX:EAX).
        "movl   $1,     %%eax;"~    // Set EAX to 1.
        "xorl   %%ecx,  %%ecx;"~    // Set ECX (the divisor) to 0.
        "idivl  %%ecx;  "          // EDX:EAX / ECX -> Division by zero #DE.
        :
        :
        : "eax", "ecx", "edx";
    }

    debugPrintln("This should not be reached.");
}

public void triggerGeneralProtection() @nogc nothrow
{
    debugPrintln("Triggering #GP...");

    // Attempt to load a known-invalid selector into DS.
    // 0x28 is the kernel's TSS selector, which is not a data segment.
    // Loading it into DS violates the segment's type and raises #GP.
    asm @nogc nothrow {
        "movw   $0x28,  %%ax;"~
        "movw   %%ax,   %%ds;"
        :
        :
        : "ax", "memory";
    }

    debugPrintln("This should not be reached.");
}
