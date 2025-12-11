extern (C):

import betterC_threadlib;
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

    // try doing something with locks, with native there might higher lock cost 
    // do the message passing too
    // classes have implicit locks you can synchronize across
    // can I call core.threads in my native threading wrapper 
    // bookkeeping, garbage collection etc, TLC heavy, copy of every variable
    // producer consumer programs, more benchmarks, 
    // reader writer , like bank accounts etc
    // image processing maybe -> every thread has group of pixels 
    // optimizer flags -o -o2 ; compare across optimization 
    // perf profiler (might be diff on mac) (can also try on zoo) (instruments maybe??) (d has built in profiler)
    // -equal=gc? look up garbage collected memory
    // info abt that 
    // contribution to the compiler maybe?

    // cross-platform for windows and linux 

    // more data collection and benchmarks 
    // understanding why might be slower
    // little book of semaphores
    // 
    // having non concurrent version also 
    

    // maybe thread lazy creation, synchronization with p threads?? 
    // async execution in pthreads? and also in native D

    // appropriate number of threads but also check out hyper threading with crazy stuff like 50 (scheduling, maybe reveal cost of context switching)
}

// Dummy worker function that prints hello world
extern(C) void worker(void* arg) 
{
    printf("hello world\n");
}

// Example worker function that performs CPU-intensive computation
extern(C) void workerHeavy(void* arg) 
{
    // Perform heavy computation
    ulong result = heavyComputation(50_000_000);

    if (result == 0) printf("unexpected zero result\n");
}

// Program entry
extern(C) void main() 
{
    enum N = 8;

    // Create N threads
    Thread[N] threads;
    
    // Start all threads
    foreach (i; 0 .. N) {
        int rc = threads[i].start(&workerHeavy, null);
        if (rc != 0) {
            printf("Failed to start thread %d: error %d\n", i, rc);
            return;
        }
    }
    
    // Wait for all threads to complete
    foreach (i; 0 .. N) {
        threads[i].join();
    }
    
    printf("All threads completed\n");
}
