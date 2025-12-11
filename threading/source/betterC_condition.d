extern (C):

import betterC_mutex;

// pthread condition variable declarations
import core.sys.posix.pthread : pthread_cond_t, pthread_cond_init,
                                pthread_cond_wait, pthread_cond_signal,
                                pthread_cond_broadcast, pthread_cond_destroy;

// Condition variable wrapper
struct Condition {
    pthread_cond_t cond;
    bool initialized;
    
    // Initialize the condition variable
    int init() {
        if (initialized) return -1; // already initialized
        int rc = pthread_cond_init(&cond, null);
        if (rc == 0) {
            initialized = true;
        }
        return rc;
    }
    
    // Wait on the condition variable (must hold mutex)
    int wait(Mutex* mutex) {
        if (!initialized || !mutex.initialized) return -1;
        return pthread_cond_wait(&cond, &mutex.mtx);
    }
    
    // Signal one waiting thread
    int signal() {
        if (!initialized) return -1;
        return pthread_cond_signal(&cond);
    }
    
    // Broadcast to all waiting threads
    int broadcast() {
        if (!initialized) return -1;
        return pthread_cond_broadcast(&cond);
    }
    
    // Destroy the condition variable
    int destroy() {
        if (!initialized) return -1;
        int rc = pthread_cond_destroy(&cond);
        if (rc == 0) {
            initialized = false;
        }
        return rc;
    }
}

