extern (C):

import betterC_threadlib;
import betterC_mutex;
import betterC_condition;
import core.stdc.stdio : printf;

// Shared state
__gshared int counter = 0;
__gshared Mutex mtx;
__gshared Condition cond;
__gshared bool ready = false;

// Worker thread that increments counter with mutex protection
extern(C) void worker(void* arg) 
{
    // Lock mutex before accessing shared state
    mtx.lock();
    
    // Critical section: increment shared counter
    counter += 1;
    printf("Thread incremented counter to %d\n", counter);
    
    // Signal that we're done
    ready = true;
    cond.signal();
    
    // Unlock mutex
    mtx.unlock();
}

// Program entry
extern(C) void main() 
{
    enum N = 3;
    
    // Initialize mutex
    if (mtx.init() != 0) {
        printf("Failed to initialize mutex\n");
        return;
    }
    
    // Initialize condition variable
    if (cond.init() != 0) {
        printf("Failed to initialize condition variable\n");
        mtx.destroy();
        return;
    }
    
    // Create N threads
    Thread[N] threads;
    
    // Start all threads
    foreach (i; 0 .. N) {
        int rc = threads[i].start(&worker, null);
        if (rc != 0) {
            printf("Failed to start thread %d: error %d\n", i, rc);
            mtx.destroy();
            cond.destroy();
            return;
        }
    }
    
    // Wait for all threads to complete
    foreach (i; 0 .. N) {
        threads[i].join();
    }
    
    // Print final value (expected N)
    printf("Final counter = %d (expected %d)\n", counter, N);
    
    // Cleanup
    mtx.destroy();
    cond.destroy();
}

