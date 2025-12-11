extern (C):

// POSIX pthread declarations
alias pthread_t = size_t;
alias PthreadStart = void* function(void*);

int pthread_create(pthread_t* thread, const(void)* attr,
                   PthreadStart start_routine, void* arg);
int pthread_join(pthread_t thread, void** retval);

// libc malloc/free for thread context
void* malloc(size_t);
void free(void*);

// User callback signature: void function(void*)
alias ThreadFn = void function(void*);

// Higher-level Thread struct
struct Thread {
    pthread_t tid;
    bool started;
    
    // Start a thread with the given function and context
    int start(ThreadFn fn, void* ctx) {
        if (started) return -1; // already started
        
        // Allocate context pack
        auto pack = cast(StartPack*) malloc(StartPack.sizeof);
        if (pack is null) return -1; // out of memory
        
        pack.fn = fn;
        pack.ctx = ctx;
        
        int rc = pthread_create(&tid, null, &thread_trampoline, pack);
        if (rc == 0) {
            started = true;
        } else {
            free(pack); // cleanup on failure
        }
        return rc;
    }
    
    // Join the thread (wait for it to complete)
    int join() {
        if (!started) return -1;
        return pthread_join(tid, null);
    }
}

// Internal structure to pass function and context to trampoline
private struct StartPack {
    ThreadFn fn;
    void* ctx;
}

// Trampoline function to convert pthread signature to user function
extern(C) void* thread_trampoline(void* p) {
    auto pack = cast(StartPack*) p;
    auto fn = pack.fn;
    auto ctx = pack.ctx;
    
    free(pack); // free the context pack
    
    fn(ctx); // call user function
    
    return null;
}

