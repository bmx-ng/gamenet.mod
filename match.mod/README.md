# GameNet.Match

`GameNet.Match` coordinates a fixed roster of two to eight players above
`GameNet.Session`. It is transport-independent: the same lifecycle can run
over ENet, GameKit, loopback, or another `INetTransport` implementation.

One configured player is the lifecycle authority. Other players send reliable
ready and pause requests to it, and the authority broadcasts versioned
canonical state. That state contains the connected, ready, and pause masks;
round number; deterministic seed; agreed gameplay start frame; countdown; and
the final winner and application result code.

The layer deliberately does not simulate gameplay or own its session. An
application routes its configured lifecycle message types from
`TNetSession.Poll` into `ReceiveAt`, reports session joins and leaves, calls
`UpdateAt`, and consumes `SMatchEvent` transitions. `GameNet.RollbackSession`
or an authoritative simulation can then start from the published seed and
frame when the phase becomes `Running`.

Countdowns use each peer's monotonic clock and are intended as a presentation
lead-in. A client initially counts from receipt of canonical state, then uses
the session's first available RTT sample to compensate for estimated one-way
transit. The agreed start frame remains authoritative; exact wall-clock
synchronisation is outside this protocol.

All packet and event storage is allocated by `Create`. Lifecycle packet
processing and event polling do not inherently create managed garbage. The
event queue is bounded; `DroppedEvents` reports insufficient capacity.
