module kernel.core.sync;

import arch.cpu;
import kernel.core.kthread;
import kernel.core.idt;

struct Mutex
{
    private bool    locked;
    private KThread* owner;
    private KThread* waitHead;
    private KThread* waitTail;

    void lock() @nogc nothrow
    {
        while (true)
        {
            size_t flags = disableInterrupts();

            if (!locked)
            {
                locked = true;
                owner = currentKThread;
                restoreInterrupts(flags);
                return;
            }

            // Queue ourselves as a waiter and switch out.
            currentKThread.state = KThreadState.BLOCKED;
            currentKThread.next  = null;
            if (waitHead is null) waitHead = currentKThread;
            else                  waitTail.next = currentKThread;
            waitTail = currentKThread;

            restoreInterrupts(flags);
            schedule();

            // We've been woken by unlock().  Loop and re-acquire.
        }
    }

    void unlock() @nogc nothrow
    {
        size_t flags = disableInterrupts();

        debug assert(owner is currentKThread, "Mutex: unlock by non-owner");

        locked = false;
        owner  = null;

        if (waitHead !is null)
        {
            KThread* t = waitHead;
            waitHead  = t.next;
            if (waitHead is null) waitTail = null;
            t.next    = null;
            t.state   = KThreadState.QUEUED;
            addToRunQueue(t);
        }

        restoreInterrupts(flags);
    }
}

struct SpinLock
{
    private bool   locked;
    private size_t savedFlags;

    void lock() @nogc nothrow
    {
        savedFlags = disableInterrupts();
        // TODO: Actual SpinLock
        debug assert(!locked, "SpinLock: deadlock (lock held while IF=0)");
        locked = true;
    }

    void unlock() @nogc nothrow
    {
        locked = false;

        restoreInterrupts(savedFlags);
    }
}
