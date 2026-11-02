module kernel.core.gdt;

import kernel.core.debugging;
import arch.x86.cpu;

pragma(mangle, "IA32_TSS_SEGMENT")
extern (C) TssSegment tss;
