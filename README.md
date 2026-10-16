# Game networking modules for BlitzMax NG

Transport-independent building blocks for real-time multiplayer games.

## Modules

- `GameNet.Core` defines peer and event values, the transport contract, delivery
  modes, and bounded packet readers and writers.
- `GameNet.Loopback` provides an in-process, preallocated transport for tests,
  local multiplayer, and protocol development.
- `GameNet.ENet` provides UDP networking through ENet for direct and hosted
  connections, including local-address reporting for manual LAN join screens.
- `GameNet.LANDiscovery` provides bounded, versioned UDP advertisement and
  browsing so compatible ENet games can find one another on an IPv4 LAN
  without accounts or an external service.
- `GameNet.GameKit` adapts Apple Game Center real-time matches to the common
  transport contract on macOS and iOS.
- `GameNet.GameKitOnline` adapts Game Center authentication and programmatic
  automatching to `GameNet.Online`, yielding a `GameNet.GameKit` transport.
- `GameNet.Steam` adapts Steam Networking Messages to the common transport
  contract on desktop targets.
- `GameNet.SteamSockets` provides connection-oriented Steam P2P and direct IP
  transports for peer-hosted and dedicated-server games.
- `GameNet.SteamOnline` implements online identity, searchable lobbies,
  invitations, lobby ownership, peer-hosted match startup, and routing lobby
  members to a known dedicated server with Steam.
- `GameNet.Online` defines an optional common contract for online identity,
  lobbies, invitations, matchmaking, and handing a connected transport to a
  game. Service adapters can target GameKit, Steam, Nakama, EOS, or future
  providers without making them dependencies of the core networking modules.
- `GameNet.Impairment` decorates any transport with deterministic, bounded
  latency, jitter, bandwidth, loss, duplication, and reordering simulation.
- `GameNet.Session` adds a versioned handshake, framed application messages,
  optional handshake/idle timeouts, keepalive probes, and per-peer health
  statistics above any GameNet transport.
- `GameNet.MatchRoom` coordinates a provider-neutral staging room with dynamic
  membership, stable player slots, opaque game configuration, ready state,
  shared round seeds, results, rematches, and participant-loss recovery.
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
- `GameNet.Replication` provides a GNet-style schema and replicated-entity
  facade with stable identities, typed fields, ownership, reliable changed
  fields or periodic full unreliable snapshots, late-join state, schema
  compatibility checks, bounded custom field codecs, per-peer relevance, and
  bounded update batching with traffic diagnostics, priority scheduling,
  per-peer byte budgets, complete-state catch-up, and bounded bidirectional
  entity messages above a session.
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

## Tests

Run every module test and backend-neutral example protocol test with:

```sh
./tests/run_all.sh /path/to/BlitzMax/bin/bmk
```

GameNet must be installed as the `mod/gamenet.mod` used by that `bmk`; the
runner rejects a different checkout so it cannot accidentally validate stale
installed modules. It creates an isolated output directory, installs the
appropriate Steam runtime beside the test executables, skips the native
GameKit transport test away from macOS, and retains all build and run logs.
An explicit unused output directory can be supplied as the second argument.

The suite requires the current `bcc2`/`bmk2` toolchain and the sibling Steam
module. macOS runs additionally require `Apple.GameKit`. These dependencies
are not all present in the currently published BlitzMax SDK setup action, so a
hosted workflow should not be enabled until that action can provision the same
toolchain used by supported GameNet builds.

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

[`examples/orbital_salvage`](examples/orbital_salvage) is a playable
authoritative game built around `GameNet.Replication`, with launchers for both
GameKit matchmaking and direct ENet play with automatic discovery on a local
network. Two pilots collect and steal energy cores using replicated entities,
reliable score state, unreliable movement snapshots, bounded player commands
and pulse effects, priority scheduling, entity destruction, and respawn.

[`examples/counter_cascade`](examples/counter_cascade) begins a deterministic
turn-based game for two to four players. Its data-driven route tables support
rectangular and hexagonal Max2D grids, reflected boundaries, configurable board
sizes, canonical cascades, elimination, state hashes, cycle protection, and a
local rules playground for all supported player counts. Its Game Center mode
uses `GameNet.MatchRoom` for match selection, ready-up, shared starting state,
independent result viewing, and rematches.

[`examples/steam_sockets_ip`](examples/steam_sockets_ip) verifies a Steam
Networking Sockets connection and packet exchange over local IP. The companion
[`examples/steam_sockets_dedicated`](examples/steam_sockets_dedicated) shows a
bounded-duration headless echo server with Steam game-server login,
advertisement, orderly shutdown, and a normal GameNet transport.

[`examples/lan_discovery`](examples/lan_discovery) is a small headless host and
joiner which discovers a compatible game, uses the returned endpoint to create
an ENet connection, and exchanges a reliable greeting.
