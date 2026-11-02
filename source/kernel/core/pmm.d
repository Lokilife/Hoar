module kernel.core.pmm;

import arch.cpu;
import arch.x86.cpu;
import kernel.core.debugging;
import kernel.core.sync;
import kernel.core.utils;

import vmm = kernel.core.vmm;

private enum BLOCK_SIZE = 4096;

public extern (C) extern __gshared ubyte __kernel_end_phys;

private __gshared ubyte[] pmmBitmap;
private __gshared size_t  totalBlocks;
private __gshared size_t  highestAddr;   // from the multiboot memory map
private __gshared SpinLock pmmAllocLock;

public struct MmapEntry
{
    uint size;
    long base;
    long length;
    uint type;

    enum AVAILABLE = 1;
    enum RESERVED = 2;
    enum APCI_RECLAIMABLE = 3;
    enum NVS = 4;
    enum BADRAM = 5;
}

/// PMM - Physical Memory Manager
public void setup(size_t highestPhys, MmapEntry[] mmap) nothrow @nogc
{
    highestAddr = highestPhys;
    totalBlocks = (highestPhys + BLOCK_SIZE - 1) / BLOCK_SIZE;

    immutable neededBytes = (totalBlocks + 7) / 8;
    ubyte* bitmapBase = cast(ubyte*) alignUp(cast(size_t)&__kernel_end_phys, BLOCK_SIZE);
    pmmBitmap = (bitmapBase+vmm.KERNEL_BASE)[0 .. neededBytes];

    size_t kernelEndAddr = alignUp(bitmapBase + neededBytes - bitmapBase + cast(size_t)bitmapBase, BLOCK_SIZE);
    size_t kernelBlocks = kernelEndAddr / BLOCK_SIZE;

    pmmBitmap[] = 0xFF; // start all-used

    debug debugPrintln("[PMM]: Memory map:");
    foreach (i, entry; mmap) {
        debug debugPrint(" - [");
        debug debugPrintUint(cast(uint)i);
        debug debugPrint("] base: ");
        debug debugPrintUint(cast(uint)entry.base);
        debug debugPrint("; length: ");
        debug debugPrintUint(cast(uint)entry.length);
        debug debugPrint("; size: ");
        debug debugPrintUint(entry.size);
        debug debugPrint("; type: ");
        debug debugPrintUint(entry.type);
        debug debugPrintln();

        if (entry.type != MmapEntry.AVAILABLE) continue;

        size_t lo = cast(uint)entry.base / BLOCK_SIZE;
        size_t hi = (cast(uint)entry.base + cast(uint)entry.length + BLOCK_SIZE - 1) / BLOCK_SIZE;
        if (lo >= totalBlocks) continue;
        if (hi >  totalBlocks) hi = totalBlocks;

        foreach (b; lo .. hi)
            markFree(b);
    }

    debug if (kernelBlocks > totalBlocks)
    {
        disableInterrupts();
        debugPrintln("[PMM]: FATAL: kernel+bitmap larger than reported RAM\nKernel halted");
        waitForInterrupt();
    }

    // Re-mark kernel + bitmap as used.
    foreach (b; 0 .. kernelBlocks)
        markUsed(b);

    debug debugPrintln("[PMM]: Set up");
    debug debugPrint("[PMM]: Free blocks count: ");
    debug debugPrintUint(freeBlockCount);
    debug debugPrintln();
}

private __gshared size_t lastAllocHint = 0;
__gshared size_t freeBlockCount;

public size_t allocBlock() @nogc nothrow
{
    pmmAllocLock.lock();
    scope (exit) pmmAllocLock.unlock();

    if (freeBlockCount == 0) return 0;

    immutable n = totalBlocks;

    // Two-pass scan: from hint to end, then from 0 to hint.
    foreach (pass; 0 .. 2)
    {
        size_t start = (pass == 0) ? lastAllocHint : 0;
        size_t end   = (pass == 0) ? n             : lastAllocHint;

        for (size_t b = start; b < end; ++b)
        {
            immutable index = b >> 3;
            immutable bit   = b & 7;

            if ((pmmBitmap[index] & (1 << bit)) == 0)
            {
                pmmBitmap[index] |= cast(ubyte)(1 << bit);
                --freeBlockCount;
                lastAllocHint = b + 1;
                return b * BLOCK_SIZE;
            }
        }
    }
    return 0;
}

public void freeBlock(size_t addr) @nogc nothrow
{
    pmmAllocLock.lock();
    scope (exit) pmmAllocLock.unlock();

    if ((addr & (BLOCK_SIZE - 1)) != 0) return;   // not block-aligned

    immutable b = addr / BLOCK_SIZE;
    if (b >= totalBlocks) return;

    immutable index = b >> 3;
    immutable bit   = b & 7;

    if ((pmmBitmap[index] & (1 << bit)) != 0)
    {
        pmmBitmap[index] &= cast(ubyte)~(1 << bit);
        ++freeBlockCount;
        if (b < lastAllocHint) lastAllocHint = b;
    }
}

public bool isFree(size_t addr) @nogc nothrow
{
    immutable b = addr / BLOCK_SIZE;
    if (b >= totalBlocks) return false;
    return (pmmBitmap[b >> 3] & (1 << (b & 7))) == 0;
}

/// Allocates `count` contiguous blocks, returns the base physical address,
/// or 0 on failure.
public size_t allocBlocks(size_t count) @nogc nothrow
{
    if (count == 0 || count > freeBlockCount) return 0;
    if (count == 1) return allocBlock();

    size_t runStart = 0;
    size_t runLen   = 0;

    for (size_t b = 0; b < totalBlocks; ++b)
    {
        if (isBlockUsed(b))
        {
            runLen = 0;
            continue;
        }
        if (runLen == 0) runStart = b;
        ++runLen;

        if (runLen == count)
        {
            foreach (i; runStart .. runStart + count)
                setBlockUsed(i, true);
            freeBlockCount -= count;
            return runStart * BLOCK_SIZE;
        }
    }
    return 0;
}

public void freeBlocks(size_t addr, size_t count) @nogc nothrow
{
    pmmAllocLock.lock();
    scope (exit) pmmAllocLock.unlock();

    if ((addr & (BLOCK_SIZE - 1)) != 0) return;
    immutable base = addr / BLOCK_SIZE;
    if (base + count > totalBlocks) return;

    foreach (b; base .. base + count)
        setBlockUsed(b, false);
    freeBlockCount += count;
}

public void reserveBlock(size_t addr) @nogc nothrow
{
    pmmAllocLock.lock();
    scope (exit) pmmAllocLock.unlock();

    size_t alignedAddr = alignDown(addr, BLOCK_SIZE);

    immutable b = alignedAddr / BLOCK_SIZE;
    if (b >= totalBlocks) return;

    markUsed(b);
}

public void reserveBlocks(size_t start, size_t end) @nogc nothrow
{
    pmmAllocLock.lock();
    scope (exit) pmmAllocLock.unlock();

    size_t alignedStart = alignDown(start, BLOCK_SIZE);
    size_t alignedEnd = alignUp(end, BLOCK_SIZE);

    immutable bStart = alignedStart / BLOCK_SIZE;
    immutable bEnd = alignedEnd / BLOCK_SIZE;

    debug assert(bStart < bEnd, "Start block must be before end block");
    debug assert(bEnd <= totalBlocks, "End blocks cannot exceed total blocks");

    immutable count = bEnd-bStart;

    for (size_t i = 0; i < count; i++)
        markUsed(bStart+i);
}

private bool isBlockUsed(size_t block) @nogc nothrow
{
    return (pmmBitmap[block >> 3] & (1 << (block & 7))) != 0;
}

private void setBlockUsed(size_t block, bool used) @nogc nothrow
{
    if (used) pmmBitmap[block >> 3] |=  cast(ubyte)(1 << (block & 7));
    else      pmmBitmap[block >> 3] &= cast(ubyte)~(1 << (block & 7));
}

private void markUsed(size_t block) @nogc nothrow
{
    immutable index = block >> 3;
    immutable mask  = cast(ubyte)(1 << (block & 7));
    if ((pmmBitmap[index] & mask) == 0)
    {
        pmmBitmap[index] |= mask;
        --freeBlockCount;
    }
}

private void markFree(size_t block) @nogc nothrow
{
    immutable index = block >> 3;
    immutable mask  = cast(ubyte)(1 << (block & 7));
    if ((pmmBitmap[index] & mask) != 0)
    {
        pmmBitmap[index] &= cast(ubyte)~mask;
        ++freeBlockCount;
    }
}

public size_t totalMemory() @nogc nothrow
{
    return highestAddr;
}
