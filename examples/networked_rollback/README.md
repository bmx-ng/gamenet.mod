# Networked rollback example

This example runs the same deterministic two-player simulation on two clients.
A small ENet relay pairs the clients and forwards inputs, but does not simulate
or own game state. Each client uses `GameNet.RollbackSession` above
`GameNet.Session`; the example only supplies its deterministic game-state and
input operations.

Build and start the relay:

```sh
bmk makeapp server.bmx
./server [port] [latency-ms] [loss-percent] [jitter-ms] [random-seed]
```

The default port is 46341. Network impairment defaults to zero and the seed
defaults to one. For example, `./server 46341 100 5 20 7` adds 100 ms base
one-way latency, up to 20 ms symmetric jitter, and 5% loss to outbound
unreliable traffic. The reusable `GameNet.Impairment` decorator makes the run
repeatable for a given seed and call sequence while leaving reliable control
messages intact.

Start two clients:

```sh
bmk makeapp client.bmx
./client <relay-address> [port] [auto]
```

The optional `auto` argument supplies scripted direction changes for soak
testing. Otherwise, use WASD, the arrow keys, or the on-screen stick. A mobile
build needs the relay's LAN address as its default or first application
argument; `127.0.0.1` refers to the mobile device itself.

The clients apply a three-frame local input delay and send the twelve newest
local inputs in every packet. Simulation stops before an unresolved input can
fall outside that redundancy window. Late inputs are compared with predictions;
a mismatch restores the earliest affected state and re-simulates to the current
frame.

Every thirty confirmed frames, clients exchange a hash of deterministic state.
The HUD reports relay round-trip time, confirmed and peer frames, rollback
depth, prediction outcomes, checked hashes, desyncs, completed state syncs,
prediction lead, and the players blocking progress if prediction is exhausted.
If the hashes disagree, player one requests a confirmed snapshot from player
zero and replays its retained inputs from that state. The match continues
without reconnecting or restarting.

The relay treats rollback input, hash, and state-sync payloads as opaque messages. Their
encoding, redundant delivery, prediction limits, rollback, hash checking, and
diagnostic counters are owned by `GameNet.RollbackSession`.

Crossing a background grid line emits a deterministic presentation effect.
The HUD counts these only after their frames are confirmed, demonstrating that
an effect is not duplicated when its frame is rolled back and re-simulated.
