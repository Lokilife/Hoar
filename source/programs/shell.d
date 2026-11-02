module programs.shell;

import arch.x86.cpu;
import gcc.attributes;

@section(".user.rodata")
private static immutable char[6] helloMsg = "Hello!";

@section(".user.entry")
private void shell()
{
    ia32_int!0x80(2, cast(size_t)helloMsg.ptr, helloMsg.length);
    ia32_int!0x80(3, 0);
}
