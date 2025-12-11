// extern (C):

// // posix pthread declarations 
// alias pthread_t = size_t;
// alias ThreadFn = void* function(void*);

// int pthread_create(pthread_t* thread, const(void)* attr,
//                    ThreadFn start_routine, void* arg);
// int pthread_join(pthread_t thread, void** retval);

// // pthread mutex stuff
// import core.sys.posix.pthread : pthread_mutex_t, pthread_mutex_init,
//                                 pthread_mutex_lock, pthread_mutex_unlock,
//                                 pthread_mutex_destroy;

// // sleep from libc 
// uint sleep(uint seconds);

// // shared state
// __gshared int counter = 0;
// __gshared pthread_mutex_t mtx;

// // worker thread 
// extern(C)  
// void* worker(void* arg)
// {
//     import core.stdc.stdio : printf;

//     // critical section: increment shared counter
//     pthread_mutex_lock(&mtx);
//     counter += 1;
//     pthread_mutex_unlock(&mtx);

//     printf("worker incremented\n");
//     return null;
// }

// // program entry 
// extern(C) void main()
// {
//     import core.stdc.stdio : printf;

//     // init mutex
//     pthread_mutex_init(&mtx, null);

//     enum N = 3;
//     pthread_t[N] tids;

//     // create N threads
//     foreach (i; 0 .. N) {
//         int rc = pthread_create(&tids[i], null, &worker, null);
//         if (rc != 0) {
//             printf("pthread_create failed w error %d at i=%d\n", rc, i);
//             return;
//         }
//     }

//     // join all
//     foreach (i; 0 .. N) {
//         pthread_join(tids[i], null);
//     }

//     // print final value (expected 3)
//     printf("final counter = %d\n", counter);

//     // cleanup
//     pthread_mutex_destroy(&mtx);
// }
