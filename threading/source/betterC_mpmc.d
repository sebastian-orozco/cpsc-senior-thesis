// betterC_mpmc.d
extern(C):

import core.stdc.stdio : printf;

// BetterC wrappers:
import betterC_threadlib;   // Thread, malloc, free, ThreadFn, etc.
import betterC_mutex;       // Mutex
import betterC_condition;   // Condition

struct BoundedBuffer {
    int*   data;
    size_t capacity;
    size_t count;
    size_t head;  // read index
    size_t tail;  // write index

    Mutex     mtx;
    Condition notFull;
    Condition notEmpty;

    bool done;

    int init(size_t cap) {
        // allocate ring buffer
        data = cast(int*) malloc(cap * int.sizeof);
        if (data is null) {
            printf("Failed to allocate buffer\n");
            return -1;
        }

        capacity = cap;
        count = 0;
        head  = 0;
        tail  = 0;
        done  = false;

        if (mtx.init() != 0) {
            printf("Failed to init mutex\n");
            return -1;
        }
        if (notFull.init() != 0) {
            printf("Failed to init notFull condition\n");
            return -1;
        }
        if (notEmpty.init() != 0) {
            printf("Failed to init notEmpty condition\n");
            return -1;
        }

        return 0;
    }

    void destroy() {
        if (data !is null) {
            free(data);
            data = null;
        }
        mtx.destroy();
        notFull.destroy();
        notEmpty.destroy();
    }

    void put(int item) {
        // lock the mutex
        mtx.lock();

        // wait while buffer is full (and not shutting down)
        while (count == capacity && !done) {
            notFull.wait(&mtx);
        }

        // if done was set while we were waiting, bail out
        if (done) {
            mtx.unlock();
            return;
        }

        // write item
        data[tail] = item;
        tail = (tail + 1) % capacity;
        ++count;

        // wake one waiting consumer
        notEmpty.signal();

        mtx.unlock();
    }

    int get() {
        mtx.lock();

        // wait while buffer is empty and not done
        while (count == 0 && !done) {
            notEmpty.wait(&mtx);
        }

        // if done and empty → sentinel
        if (count == 0 && done) {
            mtx.unlock();
            return -1; // sentinel
        }

        int item = data[head];
        head = (head + 1) % capacity;
        --count;

        // wake one waiting producer (space available)
        notFull.signal();

        mtx.unlock();
        return item;
    }

    void signalDone() {
        mtx.lock();
        done = true;
        // wake all waiters so they can see done == true
        notEmpty.broadcast();
        notFull.broadcast(); // optional; in case producers are blocked
        mtx.unlock();
    }
}

// global shared buffer
__gshared BoundedBuffer gBuffer;


enum NUM_PRODUCERS      = 2;
enum NUM_CONSUMERS      = 6;
enum BUFFER_SIZE        = 64;
enum ITEMS_PER_PRODUCER = 10;

struct ProducerArgs {
    int id;
}

struct ConsumerArgs {
    int id;
}

void producerThread(void* ctx) {
    auto args = cast(ProducerArgs*) ctx;
    int id = args.id;
    free(args); // free per-thread context

    for (int i = 0; i < ITEMS_PER_PRODUCER; ++i) {
        int item = id * 100 + i;
        gBuffer.put(item);
        // printf("Producer %d: produced item %d\n", id, item);
    }
    printf("Producer %d: finished\n", id);
}

void consumerThread(void* ctx) {
    auto args = cast(ConsumerArgs*) ctx;
    int id = args.id;
    free(args);

    int itemsConsumed = 0;
    while (true) {
        int item = gBuffer.get();
        if (item == -1) {
            break; // sentinel meaning done
        }
        ++itemsConsumed;
        // printf("Consumer %d: consumed item %d\n", id, item);
    }
    printf("Consumer %d: finished (consumed %d items)\n", id, itemsConsumed);
}

int main() {
    if (gBuffer.init(BUFFER_SIZE) != 0) {
        printf("Failed to init bounded buffer\n");
        return 1;
    }

    Thread[NUM_PRODUCERS] producers;
    Thread[NUM_CONSUMERS] consumers;

    // start producers
    for (int i = 0; i < NUM_PRODUCERS; ++i) {
        auto pargs = cast(ProducerArgs*) malloc(ProducerArgs.sizeof);
        if (pargs is null) {
            printf("Failed to allocate ProducerArgs\n");
            return 1;
        }
        pargs.id = i;

        if (producers[i].start(&producerThread, pargs) != 0) {
            printf("Failed to start producer %d\n", i);
            return 1;
        }
    }

    // start consumers
    for (int i = 0; i < NUM_CONSUMERS; ++i) {
        auto cargs = cast(ConsumerArgs*) malloc(ConsumerArgs.sizeof);
        if (cargs is null) {
            printf("Failed to allocate ConsumerArgs\n");
            return 1;
        }
        cargs.id = i;

        if (consumers[i].start(&consumerThread, cargs) != 0) {
            printf("Failed to start consumer %d\n", i);
            return 1;
        }
    }

    // wait for all producers
    for (int i = 0; i < NUM_PRODUCERS; ++i) {
        producers[i].join();
    }

    // tell consumers we're done producing
    gBuffer.signalDone();

    // wait for all consumers
    for (int i = 0; i < NUM_CONSUMERS; ++i) {
        consumers[i].join();
    }

    printf("All threads completed\n");

    gBuffer.destroy();
    return 0;
}
