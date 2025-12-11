import std.stdio : writeln, writefln;
import std.concurrency : spawn, send, Tid, thisTid, receiveOnly;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.typecons : Tuple, tuple;

// Minimal native ping-pong microbenchmark using std.concurrency.
void pong(Tid peer) {
    while (true) {
        // Expect a tuple (tag, payload); any other tag ends the loop.
        auto msg = receiveOnly!(Tuple!(string, int))();

        if (msg[0] == "ping") {
            send(peer, msg); // echo back
        } else if (msg[0] == "shutdown") {
            break;
        }
    }
}

void main() {
    enum EXCHANGES = 100_000;

    Tid pingTid = thisTid;
    Tid pongTid = spawn(&pong, pingTid);

    StopWatch sw = StopWatch(AutoStart.yes);
    size_t completed = 0;

    foreach (i; 0 .. EXCHANGES) {
        send(pongTid, tuple("ping", i));
        auto echoed = receiveOnly!(Tuple!(string, int))();
        if (echoed[0] != "ping") {
            writeln("Unexpected message tag: ", echoed[0]);
            break;
        }
        ++completed;
    }
    sw.stop();

    // Tell pong to exit.
    send(pongTid, tuple("shutdown", 0));

    auto dur = sw.peek();
    double totalSecs = dur.total!"nsecs" / 1_000_000_000.0; // convert nanoseconds to seconds
    double roundTrip = totalSecs / (completed == 0 ? 1 : completed);
    double msgs = 2.0 * completed; // ping + pong per exchange
    double throughput = msgs / totalSecs;

    writefln("Ping-pong: %s/%s exchanges completed", completed, EXCHANGES);
    writefln("Total time: %.6f s", totalSecs);
    writefln("Round-trip latency: %.3f us", roundTrip * 1_000_000.0);
    writefln("Throughput: %.0f messages/sec", throughput);
}
