# Better Concurrency for betterC: Building a Lightweight Threading Library for the D Programming Language

A comprehensive comparison of threading implementations in the D programming language, featuring a custom betterC-compatible threading library built on POSIX pthreads. Submitted as a Senior Thesis as a partial fulfillment of requirements for the Bachelor of Science in Computer Science.


## Abstract

This project explores how concurrency can be supported in the D programming lan-
guage’s betterC mode, which excludes the D runtime to minimize binary size and maxi-
mize portability. The central research question asks: How can threading and synchroniza-
tion be implemented in betterC while maintaining performance and compatibility across
platforms? To address this, I designed and implemented a lightweight high performance
threading library that replicates D’s core threading functionality using system-level APIs,
providing abstractions for thread creation, joining, and synchronization primitives such
as mutexes and condition variables.

Comparative testing and performance evaluation across multiple benchmarks, includ-
ing basic threading, multiple producer-multiple consumer (MPMC) patterns, and synchro-
nization primitives, were conducted to evaluate the trade-offs of removing D runtime de-
pendencies. The results demonstrate that the betterC implementation achieves compara-
ble runtime performance to D’s native threading while producing binaries that are 30–40x
smaller. This lightweight threading library extends D’s applicability to performance-
critical and resource-constrained environments while preserving the expressiveness of the
D language.

## Overview

This repository contains a custom threading library for D's betterC mode, which allows D programs to be compiled without the D runtime. The library provides threading primitives (threads, mutexes, condition variables, and message-passing concurrency) by wrapping POSIX pthreads, enabling concurrent programming in betterC mode where native D threading is unavailable.

The project includes:

- **betterC Threading Library**: A lightweight threading library compatible with betterC mode
- **Native D Implementations**: Reference implementations using `core.thread` and `std.concurrency`
- **Benchmarking Suite**: Comprehensive performance comparison tools
- **Multiple Concurrency Patterns**: Examples demonstrating simple threading, MPMC (Multiple Producer-Multiple Consumer), and ping-pong synchronization

## Library Components

### Core Library Files

- **`betterC_threadlib.d`**: Core threading primitives (`Thread` struct)
- **`betterC_mutex.d`**: Mutex wrapper for `pthread_mutex_t`
- **`betterC_condition.d`**: Condition variable wrapper for `pthread_cond_t`
- **`betterC_concurrency.d`**: Message-passing concurrency primitives (Mailbox, Tid, Actor)

## Usage

### Prerequisites

- D compiler (ldc2 recommended)
- DUB build system
- POSIX-compatible system (Linux, macOS, etc.)
- pthread library

### Basic Threading Example

To create and manage threads using the betterC library:

```d
extern (C):

import betterC_threadlib;
import core.stdc.stdio : printf;

// Worker function signature: void function(void*)
extern(C) void worker(void* arg) {
    printf("Hello from thread!\n");
}

extern(C) int main() {
    Thread thread;
    
    // Start the thread
    int rc = thread.start(&worker, null);
    if (rc != 0) {
        printf("Failed to start thread: error %d\n", rc);
        return 1;
    }
    
    // Wait for thread to complete
    thread.join();
    
    return 0;
}
```

### Using Mutexes and Condition Variables

```d
extern (C):

import betterC_mutex;
import betterC_condition;
import core.stdc.stdio : printf;

extern(C) int main() {
    Mutex mtx;
    Condition cond;
    
    // Initialize
    if (mtx.init() != 0 || cond.init() != 0) {
        printf("Initialization failed\n");
        return 1;
    }
    
    // Use mutex
    mtx.lock();
    // ... critical section ...
    mtx.unlock();
    
    // Use condition variable (must hold mutex)
    mtx.lock();
    cond.wait(&mtx);  // Wait for signal
    mtx.unlock();
    
    // Signal waiting threads
    cond.signal();
    
    // Cleanup
    cond.destroy();
    mtx.destroy();
    
    return 0;
}
```

### Message-Passing Concurrency

The library includes a message-passing system similar to D's `std.concurrency`:

```d
extern (C):

import betterC_concurrency;
import betterC_threadlib;

// Actor function signature
extern(C) void actor(void* arg) {
    Tid* self = cast(Tid*) arg;
    // Receive and process messages
    void* msg = receive(self);
    // ... process message ...
}

extern(C) int main() {
    Tid actorTid = spawnActor(&actor);
    
    // Send message
    send(actorTid, cast(void*) someData);
    
    // Wait for actor to complete
    joinActor(actorTid);
    
    return 0;
}
```

## Build Configurations

The project includes multiple DUB configurations for different use cases:

### betterC Configurations

- **`betterC`**: Simple threading example 
- **`betterC_mpmc`**: Multiple Producer-Multiple Consumer pattern
- **`betterC_ping_pong`**: Ping-pong synchronization benchmark
- **`betterC_mutex`**: Mutex and condition variable demonstration
- **`empty_betterC`**: Empty program for binary size comparison

### Native D Configurations

- **`native`**: Simple threading using `core.thread`
- **`native_spawn`**: Threading using `std.concurrency.spawn`
- **`native_mpmc`**: MPMC using `core.sync.mutex` and `core.sync.condition`
- **`native_ping_pong`**: Ping-pong using `std.concurrency`
- **`empty_native`**: Empty program with D runtime for binary size comparison

### Building

To build a specific configuration:

```bash
cd threading
dub build --compiler=ldc2 --config=<config_name>
```

To run:

```bash
dub run --compiler=ldc2 --config=<config_name>
```

Example:

```bash
dub run --compiler=ldc2 --config=betterC
```

## Benchmarking

The repository includes comprehensive benchmarking scripts to compare performance between betterC and native D implementations.

### Running Benchmarks

**Clean builds** (cleans before each run):

```bash
cd threading
./benchmark.sh [threading|mpmc|ping_pong] [runs]
```

**Pre-built binaries** (builds once, runs multiple times):

```bash
./benchmark_prebuilt.sh [threading|mpmc|ping_pong] [runs]
```

**std.concurrency.spawn** (benchmarks `native_spawn`):

```bash
./benchmark_spawn.sh [runs]
```

Examples:

```bash
# Benchmark simple threading with 10 runs (default)
./benchmark.sh threading

# Benchmark MPMC with 20 runs
./benchmark.sh mpmc 20

# Benchmark ping-pong with pre-built binaries
./benchmark_prebuilt.sh ping_pong 15
```

### Benchmark Metrics

The scripts collect the following metrics:

- **Real time**: Wall-clock execution time
- **User time**: CPU time spent in user mode
- **Sys time**: CPU time spent in kernel mode
- **Max RSS**: Maximum resident set size (peak physical memory)
- **Instructions retired**: Total CPU instructions executed
- **Peak memory footprint**: Largest memory allocation

Results include averages and standard deviations across multiple runs.

## Binary Size Comparison

To demonstrate the binary size reduction achieved by betterC mode:

```bash
cd threading
./show_binary_sizes.sh
```

This script builds both `empty_native` and `empty_betterC` configurations and displays the size difference. Typical results show betterC binaries are 30-40x smaller than native D binaries.

## Project Structure

```
threading/
├── dub.json                 # DUB build configuration
├── source/                  # Source files
│   ├── betterC_threadlib.d  # Core threading library
│   ├── betterC_mutex.d      # Mutex wrapper
│   ├── betterC_condition.d  # Condition variable wrapper
│   ├── betterC_concurrency.d # Message-passing primitives
│   ├── betterC_threading.d   # Simple threading example
│   ├── betterC_mpmc.d       # MPMC example
│   ├── betterC_ping_pong.d  # Ping-pong example
│   ├── native_threading.d   # Native D threading example
│   ├── spawn_threading.d    # std.concurrency example
│   └── ...
├── benchmark.sh             # Benchmark script (clean builds)
├── benchmark_prebuilt.sh    # Benchmark script (pre-built)
├── benchmark_spawn.sh       # Benchmark std.concurrency.spawn
└── show_binary_sizes.sh     # Binary size comparison
```

## Key Features

- **betterC Compatible**: Works without the D runtime, producing smaller binaries
- **POSIX pthreads Backend**: Direct wrapping of pthread primitives for minimal overhead
- **Comprehensive API**: Threads, mutexes, condition variables, and message-passing
- **Performance Benchmarked**: Extensive performance comparison with native D implementations
- **Multiple Patterns**: Examples for common concurrency patterns

## License

MIT License. You are free to use any of this code without explicit permission from the author, but with citation.

## Author

Sebastian Orozco