module kernel.core.kthread;

import arch.cpu;
import arch.x86.cpu;
import kernel.core.debugging;
import kernel.core.heap;
import kernel.core.sync;
import vmm = kernel.core.vmm;

struct KThread
{
    size_t   esp;
    void*    stackBase;
    size_t   stackSize;
    size_t   kernelStackTop;
    uint     pdIndex;
    ubyte    id;
    KThreadState state;
    KThread*  next;         // run queue linkage
}

enum KThreadState : ubyte
{
    RUNNING = 0,    // currently on CPU
    QUEUED  = 1,    // in run queue
    BLOCKED = 2,    // waiting for something
    DEAD    = 3     // exited
}

__gshared KThread* currentKThread;
__gshared KThread* runQueueHead;
__gshared ubyte nextKThreadId = 0;
private __gshared SpinLock kThreadsLock;

extern (C) void ia32_context_switch(KThread* old, KThread* new_) @nogc nothrow;
extern (C) void threadStartup() @nogc nothrow;
extern (C) extern __gshared uint ia32_tss_esp0;

public void contextSwitch(KThread* from, KThread* to) @nogc nothrow
{
    ia32_tss_esp0 = cast(uint)to.kernelStackTop;

    if (to.pdIndex != vmm.currentPdIndex)
        vmm.switchPageDirectory(to.pdIndex);

    ia32_context_switch(from, to);
}

KThread* threadCreate(void function() entry) @nogc nothrow
{
    kThreadsLock.lock();
    scope (exit) kThreadsLock.unlock();

    enum STACK_SIZE = 4096;

    KThread* t = cast(KThread*) kmalloc(KThread.sizeof);
    if (t is null) return null;

    // Allocate stack from the heap for now; later, use a whole page.
    ubyte* stack = cast(ubyte*) kmalloc(STACK_SIZE);
    if (stack is null) { kfree(t); return null; }

    t.stackBase = stack;
    t.stackSize = STACK_SIZE;
    t.id        = nextKThreadId++;
    t.kernelStackTop  = cast(size_t) stack + STACK_SIZE;
    t.pdIndex   = 0;
    t.state     = KThreadState.QUEUED;

    size_t top = cast(size_t) stack + STACK_SIZE;

    // Layout (from low to high): edi, esi, ebx, ebp, return-to-address
    top -= 4; *cast(size_t*) top = cast(size_t) entry;   // return addr
    top -= 4; *cast(size_t*) top = cast(size_t) &threadStartup;
    top -= 4; *cast(size_t*) top = 0;                    // ebp
    top -= 4; *cast(size_t*) top = 0;                    // ebx
    top -= 4; *cast(size_t*) top = 0;                    // esi
    top -= 4; *cast(size_t*) top = 0;                    // edi

    t.esp = top;

    addToRunQueue(t);

    return t;
}

void schedule() @nogc nothrow
{
    if (runQueueHead is null) return;

    KThread* next = runQueueHead;
    runQueueHead = next.next;
    next.next = null;

    KThread* prev = currentKThread;
    currentKThread = next;

    // Re-queue the previous thread if it's still alive.
    if (prev !is null && prev.state == KThreadState.QUEUED && prev !is next)
        addToRunQueue(prev);

    if (prev !is next)
        contextSwitch(prev, next);
}

void addToRunQueue(KThread* t) @nogc nothrow
{
    t.next = null;
    if (runQueueHead is null) runQueueHead = t;
    else
    {
        KThread* p = runQueueHead;
        while (p.next !is null) p = p.next;
        p.next = t;
    }
}

void threadYield() @nogc nothrow
{
    size_t savedFlags = disableInterrupts();
    scope (exit) restoreInterrupts(savedFlags);

    schedule();
}

void threadExit() @nogc nothrow
{
    if (currentKThread !is null)
        currentKThread.state = KThreadState.DEAD;
    schedule();
    // Not reached.
    for (;;) waitForInterrupt();
}
