module arch.x86_64.cpu;

import arch.x86.cpu;

public struct GdtEntry64 {
    align(1):
    ushort limit_low;
    ushort base_low;
    ubyte  base_middle;
    ubyte  access;
    ubyte  granularity_limit;
    ubyte  base_high;
    uint   base_highest;
    uint   reserved;
}
