# Game networking modules for BlitzMax NG

Transport-independent building blocks for real-time multiplayer games.

## Modules

- `GameNet.Core` defines peer and event values, the transport contract, delivery
  modes, and bounded packet readers and writers.
- `GameNet.Loopback` provides an in-process, preallocated transport for tests,
  local multiplayer, and protocol development.
- `GameNet.ENet` provides UDP networking through ENet for direct and hosted
  connections.
- `GameNet.Session` adds a versioned handshake and framed application messages
  above any GameNet transport.
- `GameNet.Snapshot` optionally provides bounded snapshot history, server-clock
  estimation, and adaptive jitter delay for real-time presentation.
- `GameNet.Prediction` optionally retains sequenced input for authoritative
  acknowledgement, replay, and loss recovery.
- `GameNet.Rollback` optionally stores deterministic frame state and predicted
  input, reporting the earliest frame which requires re-simulation.
- `GameNet.RollbackSession` composes sessions and rollback storage into a
  reusable two-player deterministic timeline with input delay, redundant
  delivery, re-simulation, confirmed presentation effects, state hashes,
  bounded authority-based resynchronisation, and explicit failure diagnostics.

Planned transport modules include `GameNet.GameKit`. Each backend imports
`GameNet.Core`; the core module does not depend on a native networking library
or platform service.

This repository requires the current bcc2-based BlitzMax NG toolchain because
its low-allocation API uses value Structs.

Install the repository as `mod/gamenet.mod` in a BlitzMax NG SDK:

```sh
git clone https://github.com/bmx-ng/gamenet.mod.git mod/gamenet.mod
```

## Example

[`examples/authoritative`](examples/authoritative) contains a small headless
ENet host and Max2D client. It demonstrates a server-owned simulation, versioned
session join, reliable lifecycle messages, and unreliable-sequenced input and
snapshots.

[`examples/rollback`](examples/rollback) contains a deterministic local Max2D
simulation with deliberately delayed remote input. It demonstrates input
prediction, mismatch detection, state restoration, and bounded re-simulation
without requiring a network connection.

[`examples/networked_rollback`](examples/networked_rollback) connects two
deterministic Max2D clients through a non-authoritative ENet relay. It adds
frame-numbered redundant input, bounded prediction lead, rollback over a real
session, confirmed-state hashes, and repeatable delay and packet-loss testing.
