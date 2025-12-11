extern (C):

// pthread mutex declarations
import core.sys.posix.pthread : pthread_mutex_t, pthread_mutex_init, pthread_mutex_lock, pthread_mutex_unlock, pthread_mutex_destroy;

// Mutex wrapper
struct Mutex {
    pthread_mutex_t mtx;
    bool initialized;
    
    // Initialize the mutex
    int init() {
        if (initialized) return -1; // already initialized
        int rc = pthread_mutex_init(&mtx, null);
        if (rc == 0) {
            initialized = true;
        }
        return rc;
    }
    
    // Lock the mutex
    int lock() {
        if (!initialized) return -1;
        return pthread_mutex_lock(&mtx);
    }
    
    // Unlock the mutex
    int unlock() {
        if (!initialized) return -1;
        return pthread_mutex_unlock(&mtx);
    }
    
    // Destroy the mutex
    int destroy() {
        if (!initialized) return -1;
        int rc = pthread_mutex_destroy(&mtx);
        if (rc == 0) {
            initialized = false;
        }
        return rc;
    }
}

