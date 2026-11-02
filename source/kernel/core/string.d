module kernel.core.string;

extern (C) void* memset(void* dst, int c, size_t n) @nogc nothrow
{
    ubyte* p = cast(ubyte*)dst;
    ubyte  v = cast(ubyte)c;
    foreach (i; 0 .. n)
        p[i] = v;
    return dst;
}

extern (C) void* memcpy(void* dst, const void* src, size_t n) @nogc nothrow
{
    ubyte* d = cast(ubyte*)dst;
    const(ubyte)* s = cast(const(ubyte)*)src;
    foreach (i; 0 .. n)
        d[i] = s[i];
    return dst;
}

extern (C) void* memmove(void* dst, const void* src, size_t n) @nogc nothrow
{
    ubyte* d = cast(ubyte*)dst;
    const(ubyte)* s = cast(const(ubyte)*)src;
    if (d < s)
        foreach (i; 0 .. n) d[i] = s[i];
    else
        foreach_reverse (i; 0 .. n) d[i] = s[i];
    return dst;
}

extern (C) int memcmp(const void* a, const void* b, size_t n) @nogc nothrow
{
    const(ubyte)* pa = cast(const(ubyte)*)a;
    const(ubyte)* pb = cast(const(ubyte)*)b;
    foreach (i; 0 .. n)
    {
        if (pa[i] != pb[i])
            return pa[i] < pb[i] ? -1 : 1;
    }
    return 0;
}
