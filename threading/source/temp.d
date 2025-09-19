extern (C):

// posix pthread declarations 
alias pthread_t = size_t;
alias ThreadFn = void* function(void*);

int pthread_create(pthread_t* thread, const(void)* attr,
                   ThreadFn start_routine, void* arg);
int pthread_join(pthread_t thread, void** retval);

// sleep from libc
uint sleep(uint seconds);

// worker thread 
extern(C)  
void* worker(void* arg)
{
    import core.stdc.stdio : printf;

    printf("worker sleeping\n");
    sleep(10); // block thread
    printf("Worker woke up\n");

    return null;
}

// program entry 
extern(C) void main()
{
    import core.stdc.stdio : printf;

    pthread_t tid;
    int rc = pthread_create(&tid, null, &worker, null);
    if (rc != 0) {
        printf("pthread_create failed w error %d\n", rc);
        return;
    }

    printf("main thread (this should print before worker finishes)\n");

    // wait for worker to finish
    pthread_join(tid, null);
    printf("main thread complete\n");
}
