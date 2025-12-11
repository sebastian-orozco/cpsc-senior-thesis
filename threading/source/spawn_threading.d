import std.concurrency;
import core.exception;
import core.stdc.stdio : printf;

// A CPU-heavy dummy function that also prevents compiler optimization
ulong heavyComputation(size_t iterations)
{
    ulong x = 0x123456789ABCDEF0UL;
    foreach (i; 0 .. iterations)
    {
        // Nonlinear bitshifts that force dependence on previous iterations
        x = (x ^ (x << 13)) ^ (x >> 7);
        x = (x ^ (x << 17)) ^ (x >> 5);
        x = x + cast(ulong)i;
        x = x * 1103515245UL + 12345UL; // pseudo rng (LCG)
    }
    return x;
}

// Example worker function that performs CPU-intensive computation
// Receives parent Tid and sends completion message when done
void worker(Tid parentTid)
{
    // Perform heavy computation
    ulong result = heavyComputation(50_000_000);
    // Prevent compiler from optimizing away the computation
    if (result == 0) printf("unexpected zero result\n");
    
    // Send completion message to parent
    send(parentTid, "done");
}

// Program entry
void main()
{
    int N = 8;
    Tid parentTid = thisTid; // Get current thread ID (parent)
    
    // Array to store thread IDs (Tid)
    Tid[] threads;
    threads.length = N;
    
    // Spawn N threads, passing parent Tid to each
    foreach (i; 0 .. N) {
        try {
            threads[i] = spawn(&worker, parentTid);
        } catch (Exception e) {
            printf("Failed to spawn thread %d: %s\n", i, e.msg.ptr);
            return;
        }
    }
    
    // Wait for all threads to complete by receiving messages
    foreach (i; 0 .. N) {
        receiveOnly!string(); // Wait for "done" message from each thread
    }
    
    printf("All threads completed\n");
}

