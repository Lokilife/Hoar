module kernel.core.utils;

public size_t alignUp(size_t value, size_t alignment) @nogc nothrow pure
{
    return (value + alignment - 1) & ~(alignment - 1);
}

public size_t alignDown(size_t value, size_t alignment) @nogc nothrow pure
{
    return value & ~(alignment - 1);
}
