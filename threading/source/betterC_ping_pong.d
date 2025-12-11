// Minimal BetterC ping-pong microbenchmark
extern(C):

import core.stdc.stdio : printf;
import core.stdc.stdlib : malloc, free;
import core.sys.posix.sys.time : gettimeofday, timeval;

import betterC_concurrency; // Actor, Tid, Mailbox, spawnActor, send, receive, joinActor, mailboxInit, mailboxClose, mailboxDestroy

// Messages are heap allocated so both sides can pass the same pointer back and forth.
enum MsgTag : int { MSG_PING = 1 }

struct Msg {
    int tag;      // always MSG_PING
    int payload;  // unused but shows you can carry data
}

struct PongCtx {
    Tid peer; // Tid of the ping side
}

// Pong actor: echo each message back until mailbox is closed.
void pongActorFn(Tid self, void* ctx) {
    auto pctx = cast(PongCtx*) ctx;
    while (true) {
        auto raw = receive(self.box);
        if (raw is null) {
            break; // mailbox closed
        }

        // Just bounce the same allocation back.
        send(pctx.peer, raw);
    }

    free(pctx);
}

double secondsBetween(const timeval* a, const timeval* b) {
    const long sec  = b.tv_sec - a.tv_sec;
    const long usec = b.tv_usec - a.tv_usec;
    return cast(double) sec + cast(double) usec / 1_000_000.0;
}

int main() {
    enum EXCHANGES = 100_000; // number of ping-pong round trips

    // Ping mailbox lives on the main thread.
    Mailbox pingMailbox;
    if (mailboxInit(&pingMailbox) != 0) {
        printf("Failed to init ping mailbox\n");
        return 1;
    }
    Tid pingTid;
    pingTid.box = &pingMailbox;

    // Spawn pong actor with its own mailbox.
    Actor pongActor;
    Tid   pongTid;

    auto pctx = cast(PongCtx*) malloc(PongCtx.sizeof);
    if (pctx is null) {
        printf("Failed to allocate PongCtx\n");
        mailboxClose(&pingMailbox);
        return 1;
    }
    pctx.peer = pingTid;

    if (spawnActor(&pongActor, &pongActorFn, pctx, &pongTid) != 0) {
        printf("Failed to spawn pong actor\n");
        free(pctx);
        mailboxClose(&pingMailbox);
        return 1;
    }

    timeval t0, t1;
    gettimeofday(&t0, null);

    int completed = 0;

    // Ping side: send then await echo EXCHANGES times.
    for (int i = 0; i < EXCHANGES; ++i) {
        auto msg = cast(Msg*) malloc(Msg.sizeof);
        if (msg is null) {
            printf("Out of memory at iteration %d\n", i);
            break;
        }
        msg.tag     = MsgTag.MSG_PING;
        msg.payload = i;

        send(pongTid, msg);

        // Wait for pong to return it.
        auto echoed = cast(Msg*) receive(&pingMailbox);
        if (echoed is null) {
            printf("Ping mailbox closed unexpectedly\n");
            break;
        }
        free(echoed);
        ++completed;
    }

    gettimeofday(&t1, null);

    double totalSecs = secondsBetween(&t0, &t1);
    double roundTripLatency = totalSecs / (completed == 0 ? 1 : completed);
    double msgsExchanged = 2.0 * completed; // ping + pong per round
    double throughput = msgsExchanged / totalSecs;

    printf("Ping-pong: %d/%d exchanges completed\n", completed, EXCHANGES);
    printf("Total time: %.6f s\n", totalSecs);
    printf("Round-trip latency: %.3f us\n", roundTripLatency * 1_000_000.0);
    printf("Throughput: %.0f messages/sec\n", throughput);

    // Shut down: close ping mailbox then join pong (which will exit when its mailbox closes).
    mailboxClose(&pingMailbox);
    joinActor(&pongActor);

    mailboxDestroy(&pingMailbox);

    return 0;
}
