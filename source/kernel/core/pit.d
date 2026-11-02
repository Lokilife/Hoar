module kernel.core.pit;

import kernel.core.kthread;
import kernel.core.debugging;

__gshared uint counter = 0;

public void timerTick()
{
    // debugPrint("Tick!");
    // debugPrintUint(counter);
    // debugPrintln();
    counter++;

    debug {
        if (runQueueHead !is null && currentKThread !is null)
            schedule();
    }

    version(release)
    {
        if (runQueueHead !is null && currentKThread !is null && (counter & 7) == 0)
            schedule();
    }
}
