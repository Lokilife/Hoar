module kernel.core.init;

import arch.cpu;
import arch.x86.cpu;

import kernel.core.debugging;
import kernel.core.utils;
import kernel.core.heap;
import kernel.core.kthread;
import kernel.core.string;
import kernel.core.sync;

import kernel.fs.initrd;

import gdt = kernel.core.gdt;
import pmm = kernel.core.pmm;
import vmm = kernel.core.vmm;
import idt = kernel.core.idt;
import pic = kernel.core.pic;

public struct KernelInitOptions
{
    size_t highestAddr;
    pmm.MmapEntry[] mmap;
    size_t initrdAddrStart;
    size_t initrdAddrEnd;
}

extern (C) void enter_user_mode() nothrow @nogc;
extern (C) extern __gshared size_t kernel_stack_top;

public void kernelInit(KernelInitOptions opts) nothrow @nogc
{
    pmm.setup(opts.highestAddr, opts.mmap);
    vmm.setup();
    initHeap();

    debug debugPrintln("[init]: Memory set up");

    debug debugPrint("[init]: Kernel stack top = ");
    debug debugPrintHex(cast(size_t)&kernel_stack_top);
    debug debugPrintln();

    pic.setup();
    enableInterrupts();

    debug debugPrintln("[init]: Interrupts set up");

    initrdInit(opts.initrdAddrStart);
    pmm.reserveBlocks(opts.initrdAddrStart, opts.initrdAddrEnd);

    helloWorld();

    KThread* idle = threadCreate(&idleLoop);
    KThread* kmain = threadCreate(&kernelMain);

    KThread* heap1 = threadCreate(&heapHammer);
    KThread* heap2 = threadCreate(&heapHammer);
    KThread* heap3 = threadCreate(&heapHammer);
    KThread* heap4 = threadCreate(&heapHammer);

    KThread* pmm1 = threadCreate(&pmmHammer);
    KThread* pmm2 = threadCreate(&pmmHammer);
    KThread* pmm3 = threadCreate(&pmmHammer);
    KThread* pmm4 = threadCreate(&pmmHammer);

    KThread* u1 = threadCreate(&userProgram);
    KThread* u2 = threadCreate(&userProgram);

    // schedule();
    KThread* first = runQueueHead;
    runQueueHead = first.next;
    first.next = null;

    currentKThread = first;

    contextSwitch(null, first);

    debug debugPrintln("\nKernel init end reached\nKernel halted");
    for (;;) waitForInterrupt();
}

private void heapHammer() @nogc nothrow
{
    immutable id = currentKThread.id;

    foreach (i; 0 .. 5_000)
    {
        size_t sz = 8 + (i % 256);
        void* p = kmalloc(sz);
        if (p is null)
        {
            debugPrint("[hammer ");
            debugPrintUint(id);
            debugPrintln("] kmalloc returned null");
            threadExit();
        }

        // Touch the memory to force any latent aliasing to fault or
        // corrupt visible state.
        memset(p, cast(ubyte)(id + i), sz);

        // Verify it stuck.
        ubyte* q = cast(ubyte*)p;
        foreach (j; 0 .. sz)
        {
            if (q[j] != cast(ubyte)(id + i))
            {
                debugPrint("[hammer ");
                debugPrintUint(id);
                debugPrintln("] heap corruption detected");
                threadExit();
            }
        }

        kfree(p);
    }

    debugPrint("[hammer ");
    debugPrintUint(id);
    debugPrintln("] done");
    threadExit();
}

private void pmmHammer() @nogc nothrow
{
    immutable id = currentKThread.id;

    foreach (i; 0 .. 2_000)
    {
        size_t a = pmm.allocBlock();
        size_t b = pmm.allocBlock();
        if (a == 0 || b == 0 || a == b)
        {
            debugPrint("[pmm ");
            debugPrintUint(id);
            debugPrintln("] alloc/free mismatch");
            threadExit();
        }
        pmm.freeBlock(a);
        pmm.freeBlock(b);
    }

    debugPrint("[pmm ");
    debugPrintUint(id);
    debugPrintln("] done");
    threadExit();
}

extern (C) extern __gshared ubyte __user_text_start, __user_text_end;
extern (C) extern __gshared ubyte __user_data_start, __user_data_end;
extern (C) extern __gshared ubyte __user_bss_start,   __user_bss_end;
extern (C) extern __gshared ubyte __user_stack_bottom, __user_stack_top;

void identityMapRange(size_t start, size_t end, uint flags) @nogc nothrow
{
    start &= ~(PAGE_SIZE - 1);
    for (size_t a = start; a < end; a += PAGE_SIZE)
        vmm.map4K(a, a, flags);      // identity: virt == phys here
}

private void userProgram() @nogc nothrow
{
    immutable id = currentKThread.id;
    debug debugPrint("[thread ");
    debug debugPrintUint(id);
    debug debugPrintln("]: entering ring 3");
    uint pd = vmm.allocPageDirectory();
    vmm.switchPageDirectory(pd);
    currentKThread.pdIndex = pd;

    identityMapRange(cast(size_t)&__user_text_start,
                    cast(size_t)&__user_text_end,  1 << P_BIT_USER);
    identityMapRange(cast(size_t)&__user_data_start,
                    cast(size_t)&__user_data_end,  1 << P_BIT_USER | 1 << P_BIT_RW);
    identityMapRange(cast(size_t)&__user_bss_start,
                    cast(size_t)&__user_bss_end,   1 << P_BIT_USER | 1 << P_BIT_RW);
    identityMapRange(cast(size_t)&__user_stack_bottom,
                    cast(size_t)&__user_stack_top, 1 << P_BIT_USER | 1 << P_BIT_RW);

    enter_user_mode();
}

private void kernelMain() @nogc nothrow
{
    for (;;) threadYield();
}

private void idleLoop() @nogc nothrow
{
    for (;;) waitForInterrupt();
}

private void helloWorld() nothrow @nogc
{
    // FFFF8000000B8000 for long mode
    ubyte* vidmem = cast(ubyte*)(0xB8000+0xC0000000); // Video memory address

    for (int i = 0; i < 80*25*2; i++) { // Loops through the screen and clears it
        *(vidmem + i) = 0;
    }

    *(vidmem) = 'D' & 0xFF; // Prints the letter D
    *(vidmem + 1) = 0x07; // Sets the colour for D to be light grey (0x07)
}
