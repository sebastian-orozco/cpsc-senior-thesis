import core.thread;
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

// Dummy worker function that prints hello world
void worker()
{
    printf("hello world\n");
}

// Example worker function that performs CPU-intensive computation
void workerHeavy()
{
    // Perform heavy computation
    ulong result = heavyComputation(50_000_000);
    if (result == 0) printf("unexpected zero result\n");
}

// Program entry
void main()
{
    enum N = 8;

    // Create N threads
    Thread[N] threads;
    
    // Start all threads
    foreach (i; 0 .. N) {
        threads[i] = new Thread(&workerHeavy);
        try {
            threads[i].start();
        } catch (Exception e) {
            printf("Failed to start thread %d: %s\n", i, e.msg.ptr);
            return;
        }
    }
    
    // Wait for all threads to complete
    foreach (ref t; threads) {
        t.join();
    }

    printf("All threads completed\n");
}

