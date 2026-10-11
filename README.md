# Game networking modules for BlitzMax NG

Transport-independent building blocks for real-time multiplayer games.

## Modules

- `GameNet.Core` defines peer and event values, the transport contract, delivery
  modes, and bounded packet readers and writers.
- `GameNet.Loopback` provides an in-process, preallocated transport for tests,
  local multiplayer, and protocol development.
- `GameNet.ENet` provides UDP networking through ENet for direct and hosted
  connections.
- `GameNet.GameKit` adapts Apple Game Center real-time matches to the common
  transport contract on macOS and iOS.
- `GameNet.GameKitOnline` adapts Game Center authentication and programmatic
  automatching to `GameNet.Online`, yielding a `GameNet.GameKit` transport.
- `GameNet.Online` defines an optional common contract for online identity,
  lobbies, invitations, matchmaking, and handing a connected transport to a
  game. Service adapters can target GameKit, Steam, Nakama, EOS, or future
  providers without making them dependencies of the core networking modules.
- `GameNet.Impairment` decorates any transport with deterministic, bounded
  latency, jitter, bandwidth, loss, duplication, and reordering simulation.
- `GameNet.Session` adds a versioned handshake, framed application messages,
  optional handshake/idle timeouts, keepalive probes, and per-peer health
  statistics above any GameNet transport.
- `GameNet.Match` adds an authoritative, backend-neutral match lifecycle with
  fixed rosters, ready and pause requests, shared seeds, countdowns, agreed
  start frames, completion, rematches, and bounded transition events.
- `GameNet.Lifecycle` turns platform foreground/background notifications into
  explicit events and configurable continue, resynchronise, reconnect, or
  leave decisions, while sessions can freeze health timing during suspension.
- `GameNet.Snapshot` optionally provides bounded snapshot history, server-clock
  estimation, and adaptive jitter delay for real-time presentation.
- `GameNet.Prediction` optionally retains sequenced input for authoritative
  acknowledgement, replay, and loss recovery.
- `GameNet.AuthoritativeSession` composes bounded prediction and snapshot
  storage into reusable client/server orchestration with redundant input,
  acknowledgement, reconciliation, interpolation, and adaptive render delay.
- `GameNet.Rollback` optionally stores deterministic frame state and predicted
  input, reporting the earliest frame which requires re-simulation.
- `GameNet.RollbackSession` composes sessions and rollback storage into a
  reusable two- to eight-player deterministic timeline with input delay,
  redundant delivery, re-simulation, confirmed presentation effects, state
  hashes, bounded authority-based resynchronisation, and explicit failure
  and input-stall diagnostics.
- `GameNet.Replay` optionally records bounded confirmed-input timelines with
  opaque initial state, verification hashes, cursor playback, and portable
  serialization.

Each backend imports `GameNet.Core`; the core module does not depend on a native
networking library or platform service.

This repository requires the current bcc2-based BlitzMax NG toolchain because
its low-allocation API uses value Structs.

See the [GameNet developer guide](NETWORKING_GUIDE.md) for choosing a session
model, packet/MTU budgeting, capacity and memory sizing, deterministic rollback,
mobile lifecycle recovery, and a practical testing strategy.

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

[`examples/gamekit_session`](examples/gamekit_session) programmatically
automatches two Game Center players and validates a complete `GameNet.Session`
handshake and message exchange over `GKMatch` on Apple devices.

[`examples/gamekit_rebound`](examples/gamekit_rebound) turns the same GameKit
matchmaking into a playable two-player fixed-point rollback game with touch and
keyboard input, destructible shields, power returns, deterministic collisions,
state hashes, full-state recovery, confirmed effects, and a transport-neutral
`GameNet.Match` lifecycle for ready-up, countdown, completion, and rematches.
