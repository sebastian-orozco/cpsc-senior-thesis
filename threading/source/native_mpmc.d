import core.thread;
import core.exception;
import core.sync.mutex;
import core.sync.condition;
import core.stdc.stdio : printf;

// -------------------------
// BOUNDED BUFFER (MPMC)
// -------------------------

struct BoundedBuffer {
    int[]  buffer;
    size_t capacity;
    size_t count;
    size_t head;  // Read position
    size_t tail;  // Write position

    Mutex     mutex;
    Condition notFull;   // Signaled when space available
    Condition notEmpty;  // Signaled when items available

    bool done;  // Flag to signal producers to stop

    void init(size_t cap) {
        buffer.length = cap;
        capacity = cap;
        count = 0;
        head = 0;
        tail = 0;
        done = false;

        mutex    = new Mutex;
        notFull  = new Condition(mutex);
        notEmpty = new Condition(mutex);
    }

    void put(int item) {
        synchronized (mutex) {
            while (count == capacity) {
                notFull.wait();
            }

            buffer[tail] = item;
            tail = (tail + 1) % capacity;
            count++;

            notEmpty.notify(); // wake one consumer
        }
    }

    int get() {
        int item;
        synchronized (mutex) {
            while (count == 0 && !done) {
                notEmpty.wait();
            }

            if (count == 0 && done) {
                return -1; // sentinel
            }

            item = buffer[head];
            head = (head + 1) % capacity;
            count--;

            notFull.notify(); // wake one producer
        }
        return item;
    }

    void signalDone() {
        synchronized (mutex) {
            done = true;
            notEmpty.notifyAll(); // wake all waiting consumers
        }
    }
}

__gshared BoundedBuffer buffer;

void producer(int id) {
    foreach (i; 0 .. 10) {
        int item = id * 100 + i;
        buffer.put(item);
        // printf("Producer %d: produced item %d\n", id, item);
    }
    printf("Producer %d: finished\n", id);
}

void consumer(int id) {
    int itemsConsumed = 0;
    while (true) {
        int item = buffer.get();
        if (item == -1) {
            break;
        }
        itemsConsumed++;
        // printf("Consumer %d: consumed item %d\n", id, item);
    }
    printf("Consumer %d: finished (consumed %d items)\n", id, itemsConsumed);
}

// Helper that builds a thread for a given producer id
Thread makeProducerThread(int id) {
    return new Thread({
        producer(id); // captures the parameter id, not a loop variable
    });
}

// Same idea for consumers
Thread makeConsumerThread(int id) {
    return new Thread({
        consumer(id);
    });
}

void main() {
    enum NUM_PRODUCERS = 2;
    enum NUM_CONSUMERS = 6;
    enum BUFFER_SIZE   = 64;

    buffer.init(BUFFER_SIZE);

    Thread[NUM_PRODUCERS] producers;
    foreach (i; 0 .. NUM_PRODUCERS) {
        producers[i] = makeProducerThread(i);
        producers[i].start();
    }

    Thread[NUM_CONSUMERS] consumers;
    foreach (i; 0 .. NUM_CONSUMERS) {
        consumers[i] = makeConsumerThread(i);
        consumers[i].start();
    }

    foreach (ref p; producers) {
        p.join();
    }

    buffer.signalDone();

    foreach (ref c; consumers) {
        c.join();
    }

    printf("All threads completed\n");
}
