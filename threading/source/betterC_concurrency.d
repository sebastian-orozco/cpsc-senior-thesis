// betterC_concurrency.d
extern(C):

import core.stdc.stdlib : malloc, free;
import betterC_threadlib;   // Thread, ThreadFn, etc.
import betterC_mutex;       // Mutex
import betterC_condition;   // Condition

// -------------------------
// Mailbox + Tid
// -------------------------

alias Message = void*;

// Simple singly-linked list node for messages
struct MailboxNode {
    Message msg;
    MailboxNode* next;
}

// FIFO mailbox with a mutex + condition
struct Mailbox {
    MailboxNode* head;
    MailboxNode* tail;
    size_t       count;

    Mutex     mtx;
    Condition cond;
    bool      closed;
}

// "Address" for an actor: basically a pointer to its mailbox
struct Tid {
    Mailbox* box;
}

// -------------------------
// Mailbox operations
// -------------------------

int mailboxInit(Mailbox* mb) {
    mb.head = null;
    mb.tail = null;
    mb.count = 0;
    mb.closed = false;

    if (mb.mtx.init() != 0) {
        return -1;
    }
    if (mb.cond.init() != 0) {
        return -1;
    }
    return 0;
}

void mailboxDestroy(Mailbox* mb) {
    // Free any remaining messages (nodes only; the payloads are user-managed)
    mb.mtx.lock();
    auto node = mb.head;
    while (node !is null) {
        auto next = node.next;
        free(node);
        node = next;
    }
    mb.head = null;
    mb.tail = null;
    mb.count = 0;
    mb.closed = true;
    mb.mtx.unlock();

    mb.cond.destroy();
    mb.mtx.destroy();
}

// Send a message to the mailbox (enqueue)
void mailboxSend(Mailbox* mb, Message msg) {
    auto node = cast(MailboxNode*) malloc(MailboxNode.sizeof);
    if (node is null) {
        // Out-of-memory: in minimal version we just drop the message.
        return;
    }
    node.msg  = msg;
    node.next = null;

    mb.mtx.lock();

    if (mb.closed) {
        mb.mtx.unlock();
        free(node);
        return;
    }

    if (mb.tail is null) {
        // empty queue
        mb.head = node;
        mb.tail = node;
    } else {
        mb.tail.next = node;
        mb.tail      = node;
    }
    ++mb.count;

    // wake a receiver waiting for messages
    mb.cond.signal();

    mb.mtx.unlock();
}

// Receive a message from the mailbox (blocking).
// Returns null if the mailbox is closed and empty.
Message mailboxReceive(Mailbox* mb) {
    mb.mtx.lock();

    // wait while queue is empty and not closed
    while (mb.head is null && !mb.closed) {
        mb.cond.wait(&mb.mtx);
    }

    // closed and no messages left → sentinel null
    if (mb.head is null && mb.closed) {
        mb.mtx.unlock();
        return null;
    }

    auto node = mb.head;
    mb.head   = node.next;
    if (mb.head is null) {
        mb.tail = null;
    }
    --mb.count;

    auto msg = node.msg;
    free(node);

    mb.mtx.unlock();
    return msg;
}

// Close the mailbox: no more sends, wake all receivers.
void mailboxClose(Mailbox* mb) {
    mb.mtx.lock();
    mb.closed = true;
    mb.cond.broadcast();
    mb.mtx.unlock();
}

// -------------------------
// Public message-passing API
// -------------------------

// Send to a Tid
void send(Tid dest, Message msg) {
    if (dest.box !is null) {
        mailboxSend(dest.box, msg);
    }
}

// Blocking receive on your own mailbox.
// Returns null if mailbox is closed and empty.
Message receive(Mailbox* self) {
    return mailboxReceive(self);
}

// Optional helper: close a Tid's mailbox
void close(Tid dest) {
    if (dest.box !is null) {
        mailboxClose(dest.box);
    }
}

// -------------------------
// Actor + spawn helper 
// -------------------------

// User actor function: gets its own Tid and an opaque user context.
alias ActorFn = void function(Tid, void*);

// Internal start context passed to thread trampoline
struct ActorStartCtx {
    ActorFn fn;
    void*   userCtx;
    Mailbox* mailbox;
}

// We tie together a thread and its mailbox.
struct Actor {
    Thread  thread;
    Mailbox mailbox;
}

// Trampoline that runs inside the new thread
void actorTrampoline(void* p) {
    auto ctx = cast(ActorStartCtx*) p;

    ActorFn fn       = ctx.fn;
    void*   userCtx  = ctx.userCtx;
    Mailbox* mailbox = ctx.mailbox;

    Tid selfTid;
    selfTid.box = mailbox;

    free(ctx);

    // Run user actor code
    fn(selfTid, userCtx);
}

// Spawn an actor with its own mailbox.
// - actor: storage for the Actor (allocated by caller)
// - fn   : user actor function (takes Tid + user context)
// - userCtx: opaque pointer passed to user function
// - outTid: where to store the new actor's Tid
//
// Returns 0 on success, non-zero on error.
int spawnActor(Actor* actor, ActorFn fn, void* userCtx, Tid* outTid) {
    if (mailboxInit(&actor.mailbox) != 0) {
        return -1;
    }

    auto ctx = cast(ActorStartCtx*) malloc(ActorStartCtx.sizeof);
    if (ctx is null) {
        mailboxDestroy(&actor.mailbox);
        return -1;
    }

    ctx.fn      = fn;
    ctx.userCtx = userCtx;
    ctx.mailbox = &actor.mailbox;

    int rc = actor.thread.start(&actorTrampoline, ctx);
    if (rc != 0) {
        free(ctx);
        mailboxDestroy(&actor.mailbox);
        return rc;
    }

    outTid.box = &actor.mailbox;
    return 0;
}

// Gracefully shut down an actor:
// - close its mailbox (wakes any receiver)
// - join the thread
// - destroy mailbox
int joinActor(Actor* actor) {
    // The actor's own code should typically call mailboxClose on itself
    // when it's done sending/receiving. But we can enforce close here too:
    mailboxClose(&actor.mailbox);

    int rc = actor.thread.join();
    mailboxDestroy(&actor.mailbox);
    return rc;
}
