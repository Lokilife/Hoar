module kernel.core.vmm;

import arch.cpu;
import arch.x86.cpu;
import kernel.core.debugging;
import pmm = kernel.core.pmm;

/// Constant representing 4 Mbytes
enum MB_4 = 4 * 1024 * 1024;
enum KERNEL_BASE = 0xC0000000;
enum PAGE_SIZE   = 4096;

private __gshared Pde* kernelPd;
private __gshared Pde** pds;
private __gshared uint lastPdIndex = 0;
public  __gshared uint currentPdIndex = 0; // Index of currently loaded PD into CR3
alias currentPd = () => pds[currentPdIndex];

public void setup() nothrow @nogc
{
    size_t pdsPhys = pmm.allocBlock();
    pds = cast(Pde**) physToVirt(pdsPhys);
    // note: 4kb can store 1024 Pde pointers
    pds[0..1024] = cast(Pde*)0;
    uint kernelPdIndex = allocPageDirectory(); // Pure Kernel Directory, always will be 0
    kernelPd = pds[kernelPdIndex];

    switchPageDirectory(kernelPdIndex);
    ia32_enable_paging();

    debug debugPrintln("[VMM]: Paging enabled");

    debug {
        debugPrintln("[VMM]: Self-test");
        // The direct map should still see physical memory.
        size_t probePhys = pmm.allocBlock();
        assert(probePhys != 0);

        ubyte* viaDirect = cast(ubyte*) physToVirt(probePhys);
        viaDirect[0] = 0xAB;
        assert(viaDirect[0] == 0xAB);

        // And the same page mapped through a fresh virtual address.
        size_t testVirt = 0x40000000;
        bool mapped = map4K(testVirt, probePhys, 1 << P_BIT_RW);
        if (!mapped)
        {
            debugPrintln("PANIC: map4K failed");
            for (;;) waitForInterrupt();
        }

        ubyte* viaNew = cast(ubyte*) testVirt;

        ubyte readBack = viaNew[0];
        if (readBack != 0xAB)
        {
            debugPrintln("PANIC: read via fresh mapping returned wrong byte");
            for (;;) waitForInterrupt();
        }

        viaNew[0] = 0xCD;

        if (viaDirect[0] != 0xCD)
        {
            debugPrintln("PANIC: write not visible through direct map");
            for (;;) waitForInterrupt();
        }

        unmap4K(testVirt);
        pmm.freeBlock(probePhys);

        debugPrintln("[VMM]: Self-test passed");
    }
}

/// Allocates page directory
/// Params:
///   omitDirectMap = (default: false) when true doesn't adds direct map for kernel address space
/// Returns:
///   Page Directory Index in VMM
public uint allocPageDirectory(bool omitDirectMap = false) nothrow @nogc
{
    if (lastPdIndex > 1024 || pds[lastPdIndex] != null)
    {
        for (uint i = 0; i < 1024; i++)
        {
            if (pds[i] == null) lastPdIndex = i;
        }

        assert(pds[lastPdIndex] == null, "No free PD found");
    }
    uint usedIndex = lastPdIndex;
    lastPdIndex++;

    size_t pdPhys = pmm.allocBlock();
    Pde* pd = cast(Pde*) physToVirt(pdPhys);
    pds[usedIndex] = pd;
    pd[0..1024] = Pde();

    debug debugPrint("[VMM]: Allocated page directory ");
    debug debugPrintUint(usedIndex);
    debug debugPrint("; dmap = ");
    debug debugPrint(omitDirectMap ? "0" : "1");
    debug debugPrintln(";");

    if (omitDirectMap) return usedIndex;

    const size_t ramSize = pmm.totalMemory();
    const uint   pages = (ramSize + MB_4 - 1) / MB_4;

    for(ubyte i = 0; i < pages && i < 255; i++)
    {
        pd[768 + i] = Pde()
            .page4M(i * MB_4)
            .present(true)
            .pageSize4M(true)
            .rw(true);
    }

    return usedIndex;
}

public void switchPageDirectory(uint index) @nogc nothrow
{
    debug assert(pds[index] != null, "Switch to invalid PD index");

    debug debugPrint("[VMM]: Page Directory switching to ");
    debug debugPrintUint(index);
    debug debugPrintln();

    size_t pd = cast(size_t)pds[index];
    ia32_load_cr3(virtToPhys(pd));
    currentPdIndex = index;
}

public size_t physToVirt(size_t phys) @nogc nothrow pure
{
    return phys + KERNEL_BASE;
}

public size_t virtToPhys(size_t virt) @nogc nothrow pure
{
    return virt - KERNEL_BASE;
}

/// Page-table allocation: get a zeroed 4 KiB page via the PMM,
/// returned as a *virtual* pointer (ready to write through).
public void* allocPageTable() @nogc nothrow
{
    size_t phys = pmm.allocBlock();
    if (phys == 0) return null;
    return cast(void*) physToVirt(phys);
}

/// Walk the page tables for `virt`, creating intermediate PTs
/// on demand when `create` is true. Returns a pointer to the
/// final PTE, or null.
private Pte* walkPte(size_t virt, bool create, uint flags = 0) @nogc nothrow
{
    immutable pdi = (virt >> 22) & 0x3FF;
    immutable pti = (virt >> 12) & 0x3FF;

    Pde* pde = &currentPd()[pdi];

    if (!pde.present())
    {
        if (!create) return null;
        void* pt = allocPageTable();
        if (pt is null) return null;
        *pde = Pde()
            .pageTable(cast(uint)virtToPhys(cast(size_t)pt))
            .present(true)
            .rw((flags & (1 << P_BIT_RW)) != 0)
            .user((flags & (1 << P_BIT_USER)) != 0);
    }

    // Direct-map editing means 4 MiB pages would break this walk.
    // Bail out cleanly rather than misinterpret the PDE.
    if (pde.isPageSize4M()) return null;

    Pte* pt = cast(Pte*) physToVirt(pde.pageTable());
    return &pt[pti];
}

/// Map a 4 KiB page. Returns true on success.
public bool map4K(size_t virt, size_t phys, uint flags = 0) @nogc nothrow
{
    if ((virt & (PAGE_SIZE - 1)) != 0) return false;
    if ((phys & (PAGE_SIZE - 1)) != 0) return false;

    Pte* pte = walkPte(virt, true, flags);
    if (pte is null) return false;

    *pte = Pte().page(cast(uint)phys).withFlags(flags, PTE_FLAGS_MASK);
    *pte = (*pte).present(true);
    ia32_invlpg(virt);
    return true;
}

/// Unmap a 4 KiB page. Returns the physical address that was
/// mapped, or 0 if nothing was there.
public size_t unmap4K(size_t virt) @nogc nothrow
{
    Pte* pte = walkPte(virt, false);
    if (pte is null) return 0;
    if (!pte.present()) return 0;

    immutable phys = cast(size_t)pte.page();
    *pte = Pte();      // also clears present
    ia32_invlpg(virt);
    return phys;
}

public size_t getMapping(size_t virt) @nogc nothrow
{
    Pte* pte = walkPte(virt, false);
    if (pte is null || !pte.present()) return 0;
    return cast(size_t)pte.page();
}

public bool userCanAccess(size_t ptr, size_t len) @nogc nothrow
{
    if (ptr >= KERNEL_BASE) return false;   // must be user address
    if (ptr + len < ptr)    return false;   // overflow
    size_t end = ptr + len;
    for (size_t a = ptr & ~(PAGE_SIZE - 1); a < end; a += PAGE_SIZE)
    {
        Pte* pte = walkPte(ptr, false);
        if (pte is null || !pte.present() || !pte.user()) return false;
    }
    return true;
}