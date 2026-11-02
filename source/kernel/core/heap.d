// Got really bored at this point so just took a
// heap implementation in C from some of my old abandoned projects
// Put it into an AI and pasted here

// Maybe somewhen later I'll rewrite it in a good way
// But its not today
module kernel.core.heap;

import arch.cpu;
import kernel.core.debugging;
import kernel.core.sync;
import kernel.core.string   : memset;
import kernel.core.utils    : alignUp;
import kernel.core.vmm      : physToVirt, KERNEL_BASE;
import pmm = kernel.core.pmm;

enum PAGE_SIZE       = 4096;
enum HEADER_SIZE     = BlockHeader.sizeof;   // 8 on i386
enum MIN_BLOCK_SIZE  = 16;
enum ALIGN           = 8;

enum KHEAP_MAX_SIZE  = 16 * 1024 * 1024;
enum KHEAP_INIT_PAGES = 1;                    // start with one 4 KiB page

struct BlockHeader
{
    size_t size;
    BlockHeader* next;
}

private enum SIZE_MASK = ~cast(size_t)(ALIGN - 1);
private enum USED_BIT  = cast(size_t)1;

private size_t blockSize(BlockHeader* b) @nogc nothrow { return b.size & SIZE_MASK; }
private bool   blockUsed(BlockHeader* b) @nogc nothrow { return (b.size & USED_BIT) != 0; }
private void   setUsed  (BlockHeader* b) @nogc nothrow { b.size |= USED_BIT; }
private void   setFree  (BlockHeader* b) @nogc nothrow { b.size &= ~USED_BIT; }

private __gshared BlockHeader* freeList;
private __gshared size_t heapStartVirt;
private __gshared size_t heapCurrentVirt;   // end of the last extend
private __gshared size_t heapEndVirt;

extern (C) __gshared size_t idt_start, idt_end, gdt_start, gdt_end;

// -------------------------------------------------------------------
// Init — heap starts immediately after the kernel image in physical
// memory, addressed through the direct map.
// -------------------------------------------------------------------
void initHeap() @nogc nothrow
{
    immutable physBase = alignUp(cast(size_t)&pmm.__kernel_end_phys, PAGE_SIZE);

    heapStartVirt   = physToVirt(physBase);
    heapCurrentVirt = heapStartVirt;
    heapEndVirt     = heapStartVirt + KHEAP_MAX_SIZE;
    freeList        = null;

    if (!heapExtend(KHEAP_INIT_PAGES))
    {
        debugPrintln("[heap]: initial extend failed");
        debugPrintln("Kernel halted");

        disableInterrupts();
        for (;;) waitForInterrupt();
    }

    debug debugPrint("[heap] virt base = ");
    debug debugPrintHex(heapStartVirt);
    debug debugPrint(", phys base = ");
    debug debugPrintHex(physBase);
    debug debugPrintln();

    debug {
        debugPrintln("[heap] Self-test");

        void* a = kmalloc(32);
        void* b = kmalloc(64);
        void* c = kmalloc(16);
        if (a is null || b is null || c is null) { debugPrintln("alloc failed"); return; }

        // Should be distinct and 8-aligned.
        if (a == b || b == c || a == c) { debugPrintln("aliasing"); return; }
        if ((cast(size_t) a & 7) != 0)  { debugPrintln("misaligned a"); return; }
        if ((cast(size_t) b & 7) != 0)  { debugPrintln("misaligned b"); return; }

        kfree(b);
        kfree(a);
        kfree(c);

        // After freeing everything, a big allocation should succeed and,
        // if coalescing works, land on the same base as `a` did.
        void* d = kmalloc(100);
        if (d != a) debugPrintln("[heap] WARNING: no coalescing (not fatal)");
        kfree(d);

        debugPrintln("[heap] Self-test passed");
    }
}

// -------------------------------------------------------------------
// Extend — allocate a contiguous physical run and expose it through
// the direct map. No page tables are touched: they already cover
// physical RAM via the 4 MiB PDEs installed at boot.
// -------------------------------------------------------------------
private bool heapExtend(size_t numPages) @nogc nothrow
{
    immutable bytes = numPages * PAGE_SIZE;

    if (heapCurrentVirt + bytes > heapEndVirt)
        return false;

    // Ask the PMM for a contiguous physical run.
    immutable physBase = pmm.allocBlocks(numPages);
    if (physBase == 0)
    {
        debugPrintln("[heap] PMM has no contiguous run of that size");
        return false;
    }

    // The direct map already maps this physical range; just compute
    // the virtual address we'll use for it.
    immutable virtBase = physToVirt(physBase);

    // allocBlocks doesn't zero; fresh pages must be zeroed so the
    // first kmalloc doesn't hand back stale bytes.
    memset(cast(void*) virtBase, 0, bytes);

    BlockHeader* block = cast(BlockHeader*) virtBase;
    block.size = bytes - HEADER_SIZE;
    block.next = null;

    // Insert in address order and coalesce if adjacent to the previous
    // extension.  Because both physical and virtual memory are laid
    // out by the PMM hint, consecutive extends are usually adjacent,
    // but we don't rely on it.
    insertFreeBlock(block);

    heapCurrentVirt += bytes;
    return true;
}

// -------------------------------------------------------------------
// Sorted insertion + coalescing. Shared by heapExtend and kfree.
// -------------------------------------------------------------------
private void insertFreeBlock(BlockHeader* block) @nogc nothrow
{
    BlockHeader* prev = null;
    BlockHeader* curr = freeList;
    while (curr !is null && curr < block)
    {
        prev = curr;
        curr = curr.next;
    }

    block.next = curr;
    if (prev !is null) prev.next = block;
    else               freeList  = block;

    // Merge with successor.
    if (curr !is null &&
        cast(ubyte*) block + HEADER_SIZE + blockSize(block) == cast(ubyte*) curr)
    {
        block.size = blockSize(block) + HEADER_SIZE + blockSize(curr);
        block.next = curr.next;
    }

    // Merge with predecessor.
    if (prev !is null &&
        cast(ubyte*) prev + HEADER_SIZE + blockSize(prev) == cast(ubyte*) block)
    {
        prev.size = blockSize(prev) + HEADER_SIZE + blockSize(block);
        prev.next = block.next;
    }
}

private __gshared SpinLock heapLock;

// -------------------------------------------------------------------
// kmalloc
// -------------------------------------------------------------------
void* kmalloc(size_t size) @nogc nothrow
{
    if (size == 0) return null;

    size = (size + (ALIGN - 1)) & ~cast(size_t)(ALIGN - 1);
    if (size < MIN_BLOCK_SIZE) size = MIN_BLOCK_SIZE;

    heapLock.lock();
    scope (exit) heapLock.unlock();

    while (true) {
        BlockHeader* prev = null;
        BlockHeader* curr = freeList;
        while (curr !is null) {
            if (blockSize(curr) >= size) {
                immutable remaining = blockSize(curr) - size;

                if (remaining >= HEADER_SIZE + MIN_BLOCK_SIZE)
                {
                    // Split off the tail of this block.
                    BlockHeader* tail = cast(BlockHeader*)
                        (cast(ubyte*)(curr + 1) + size);

                    tail.size = remaining - HEADER_SIZE;
                    tail.next = curr.next;

                    curr.size = size;
                    curr.next = tail;
                }

                // Unlink from free list.
                if (prev !is null) prev.next = curr.next;
                else               freeList = curr.next;

                setUsed(curr);
                return curr + 1;
            }
            prev = curr; curr = curr.next;
        }

        // no fit; extend by one attempt, loop to retry
        immutable neededBytes = size + HEADER_SIZE;
        immutable pages = (neededBytes + PAGE_SIZE - 1) / PAGE_SIZE;
        if (!heapExtend(pages)) return null;
    }
}

// -------------------------------------------------------------------
// kfree  —  re-insert into the sorted free list and coalesce both ways.
// -------------------------------------------------------------------
void kfree(void* ptr) @nogc nothrow
{
    if (ptr is null) return;

    BlockHeader* block = cast(BlockHeader*) ptr - 1;

    if (!blockUsed(block))
    {
        debug debugPrintln("[heap] kfree: double free detected");
        return;
    }

    heapLock.lock();
    scope (exit) heapLock.unlock();

    setFree(block);

    // Find insertion point in address order.
    BlockHeader* prev = null;
    BlockHeader* curr = freeList;
    while (curr !is null && curr < block)
    {
        prev = curr;
        curr = curr.next;
    }

    block.next = curr;
    if (prev !is null) prev.next = block;
    else               freeList  = block;

    // Coalesce with successor.
    if (curr !is null &&
        cast(ubyte*) block + HEADER_SIZE + blockSize(block) == cast(ubyte*) curr)
    {
        block.size = blockSize(block) + HEADER_SIZE + blockSize(curr);
        block.next = curr.next;
    }

    // Coalesce with predecessor.
    if (prev !is null &&
        cast(ubyte*) prev + HEADER_SIZE + blockSize(prev) == cast(ubyte*) block)
    {
        prev.size = blockSize(prev) + HEADER_SIZE + blockSize(block);
        prev.next = block.next;
    }
}

// -------------------------------------------------------------------
// Convenience
// -------------------------------------------------------------------
void* kcalloc(size_t n, size_t size) @nogc nothrow
{
    immutable total = n * size;
    if (total / size != n) return null;   // overflow check

    void* p = kmalloc(total);
    if (p is null) return null;
    memset(p, 0, total);
    return p;
}

// -------------------------------------------------------------------
// Diagnostics
// -------------------------------------------------------------------
void heapDump() @nogc nothrow
{
    size_t total, freeBytes;
    BlockHeader* b = freeList;
    while (b !is null)
    {
        total += blockSize(b) + HEADER_SIZE;
        freeBytes += blockSize(b);
        b = b.next;
    }

    debugPrint("[heap] free blocks total="); debugPrintUint(cast(uint) freeBytes);
    debugPrint(", heap used up to=");        debugPrintHex(heapCurrentVirt);
    debugPrintln();
}
