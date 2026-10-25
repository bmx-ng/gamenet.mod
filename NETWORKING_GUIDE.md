# GameNet developer guide

GameNet provides reusable networking machinery, but it deliberately does not
define a game's state or decide how that state should be shared. Those choices
affect responsiveness, memory use and how a match recovers when a device loses
connectivity. This guide explains the decisions a game developer needs to make
before treating a multiplayer build as production-ready.

## Choose the session model first

GameNet currently offers two higher-level session models. They solve different
problems, so player count alone should not determine which one a game uses.

An **authoritative session** has one server that owns the accepted game state.
Clients send inputs, predict immediate local motion where useful, and later
reconcile with server snapshots. Remote objects are normally displayed slightly
in the past so that snapshots can be interpolated smoothly. This model suits
games with many entities or players, games that do not need every machine to
run precisely the same simulation, and games where the authority should make
the final decision.

A **rollback session** runs the same deterministic simulation on every peer.
When a remote input is late, a peer predicts it. If the real input differs, the
peer restores an earlier state and simulates those frames again. This can give
very responsive controls, but every peer must produce exactly the same result
from the same state and inputs. GameNet therefore limits this implementation to
eight players; in practice, the best number may be lower for a simulation that
is expensive to replay.

Both models sit above `GameNet.Session` and can use ENet, GameKit or another
transport implementing `INetTransport`. Transport independence does not make
the backends operationally identical: GameKit supplies Apple matchmaking and
connectivity, while an Internet ENet game still needs a plan for discovery,
NAT traversal, relays or dedicated servers.

`GameNet.SteamSockets` is another transport choice for desktop games. It can
listen or connect using Steam identities, or use numeric IP addresses for an
ordinary hosted server. A dedicated server can run the same `GameNet.Session`
and authoritative-session code as an ENet server; Steam game-server login,
advertisement, and player authentication are optional surrounding services.

## Decide how players find the match

Two devices do not need an online service merely because they are playing a
networked game. Devices on the same LAN can connect directly through ENet.
`GameNet.LANDiscovery` supplies an optional local browser: the host advertises
its game identifier, wire-protocol version, ENet port, player counts, flags and
small application-defined metadata, while joining devices discover its source
address automatically. Manual entry, a QR code, or an application-specific
exchange remain valid alternatives. Likewise, an Internet game can connect
directly to a known public or dedicated-server address when routing and
firewall configuration permit it.

LAN discovery is intentionally not an Internet rendezvous service. It uses
bounded, unauthenticated UDP queries and replies on the local IPv4 network. A
result is suitable for a join screen, not proof of identity: the subsequent
GameNet session handshake must still validate the joining peer and game
protocol. iOS applications must explain local-network access with
`NSLocalNetworkUsageDescription`, and Android applications require the normal
`INTERNET` permission.

Online services solve the surrounding coordination problem. GameKit, Steam,
Nakama, EOS, and similar systems can provide some combination of identity,
invitations, lobby search, matchmaking, NAT traversal, relay traffic, or server
allocation. `GameNet.Online` provides an optional common contract for that
stage. A successful provider operation hands the game an `INetTransport`, after
which the ordinary GameNet session and simulation layers take over.

`GameNet.OnlineFlow` supplies the reusable state machine above that contract.
The application asks it to host, find and join, accept an invitation, or start
Quick Play. Quick Play prefers native matchmaking when the provider advertises
it. Otherwise it searches for the first joinable lobby and can create one when
the search is empty. The coordinator correlates asynchronous requests, waits
for the configured player count, starts the provider match, and returns one
`TOnlineMatchLaunch` containing both `SOnlineMatchInfo` and the transferred
transport.

```blitzmax
Local flow:TOnlineFlowCoordinator = TOnlineFlowCoordinator.Create(online)
If Not flow.Open() Then
	Throw "Could not open the online service"
End If

' After the Ready flow event:
Local request:TOnlineFlowRequest = New TOnlineFlowRequest
request.lobbyOptions.minPlayers = 2
request.lobbyOptions.maxPlayers = 2
request.matchmakingRequest.minPlayers = 2
request.matchmakingRequest.maxPlayers = 2
request.startPolicy = EOnlineFlowStartPolicy.WhenMinimumPlayers
flow.QuickPlay(request)

' Pump and poll the coordinator rather than the provider directly.
flow.Pump()
Local event:SOnlineFlowEvent
While flow.Poll(event)
	If event.Kind() = EOnlineFlowEventKind.MatchReady Then
		Local launch:TOnlineMatchLaunch = flow.TakeMatch()
		' Create a host or client TNetSession from launch.Info() and
		' launch.Transport().
	End If
Wend
```

The coordinator does not replace provider login, the provider adapter, or the
game session. For example, `TEOSSessionCoordinator` maintains EOS Auth and
Connect identity, `TEOSOnlineService` exposes EOS lobby operations, and
`TOnlineFlowCoordinator` combines those operations into the requested player
flow. `TNetSession` begins only after the match transport has been transferred.

The interface is capability-based because providers are not interchangeable in
every respect. Check a provider's advertised capabilities before displaying a
feature, and use its native adapter API when the game needs something outside
the shared lobby-and-match flow. Direct ENet remains available and does not
require `GameNet.Online`.

Once a transport and `TNetSession` exist, `GameNet.MatchRoom` supplies the
portable staging layer. The elected session host owns a dynamic roster of up
to sixteen slots, an opaque game-defined configuration, ready state, round
number, and shared seed. This is deliberately distinct from a provider lobby:
Steam or EOS can use their backend lobby for discovery and invitations, while
GameKit or direct LAN play can run the same staging protocol over the newly
connected transport. Each game still chooses its own room limit; for example,
a four-player game creates a four-slot room even though the module supports
more.

`GameNet.SteamOnline` is the first lobby-oriented provider. It maps Steam lobby
metadata and membership into `IOnlineLobby`, uses the lobby owner as the
GameNet session host, and yields a Steam peer transport when the match starts.
Networking Messages remains the compatibility default; a game can instead ask
the provider for Networking Sockets, making the lobby owner a P2P listener and
connecting the remaining members to it. Steam lobby discovery stays separate
from either transport, matching the service/transport split in GameNet.

`GameNet.EOSOnline` follows the same split for Epic Online Services. The
preferred path constructs `TEOSOnlineService` from a ready
`TEOSSessionCoordinator`, keeping Auth tokens and Product User identifiers out
of application multiplayer code. A lower-level platform and Product User
factory remains available for deliberate manual identity management. The
adapter provides searchable, bucket-partitioned lobbies, invitations,
lobby-owner start signalling, and an `EOSP2P` match transport. Continue pumping
the online service or its online-flow coordinator while the lobby is in use.
The transferred transport also ticks its platform when polled, so it remains
operational if the online service is subsequently closed.

When an allocator or developer-owned host supplies a dedicated endpoint, the
lobby owner can publish it through `TSteamOnlineService.SetDedicatedServer`.
All lobby members then receive client transports connected to that server. The
same route supports a direct IPv4 listener or a Steam-identity P2P listener;
automatic hosted-SDR allocation and ticket exchange remain deliberately
outside this layer until there is a real hosting service to coordinate them.

## Plan packet sizes rather than relying on fragmentation

A transport's maximum accepted packet is not necessarily a good size to send
over the Internet. Large UDP datagrams may be divided into IP fragments. If
one fragment is lost, the complete datagram is lost; reliability can resend it,
but the resulting delay is often visible in a real-time game.

GameNet defines `GAMENET_RECOMMENDED_INTERNET_PACKET_SIZE` as 1200 bytes. This
is a conservative starting point that leaves space for networking headers
within the IPv6 minimum MTU. It is guidance, not a promise that every route or
backend has the same limit.

There are two limits to inspect:

1. `INetTransport.MaxPacketSize` reports what the selected backend accepts.
2. `TNetSession.MaxPayloadSize` reports how much application data remains after
   GameNet's session framing has been accounted for.

Design ordinary gameplay packets to fit the smaller applicable value. Inputs
should usually be compact. For a large world snapshot, prefer sending relevant
entities or independently useful sections rather than one indivisible world
blob.

Rollback state synchronisation is intentionally simple: one complete state is
sent in one reliable session message. `StateSyncPacketCapacity` reports the
buffer size needed by the rollback layer, but that message must also fit
`TNetSession.MaxPayloadSize(EDeliveryMode.ReliableOrdered)`. If it does not fit,
reduce the deterministic state or implement a game-specific fragmented transfer
with validation before applying the assembled state.

## Decide capacities before the match

Histories and queues in GameNet have fixed capacities. This keeps normal frame
processing predictable and avoids growing managed collections while a match is
running. The tradeoff is that the application must choose limits appropriate
for its tick rate and expected network conditions.

For example, a rollback history must retain enough frames to cover the maximum
prediction and recovery window. An authoritative client's input history must
retain commands until the server can acknowledge them. Snapshot capacity must
cover the interpolation delay plus realistic jitter. A very large number is not
automatically safer: it consumes memory and can conceal a connection that
should instead be resynchronised or ended.

The high-level session types can report their reserved storage before they are
created:

```blitzmax
Local memory:SNetMemoryRequirements
If Not TRollbackSession.MemoryRequirements(simulation, config, memory) Then
	Throw "Invalid rollback configuration"
End If

Print "Native buffers: " + memory.NativeBytes()
Print "Managed array data: " + memory.ManagedArrayBytes()
Print "Payload storage: " + memory.TotalPayloadBytes()
```

Equivalent methods are available on `TAuthoritativeClientSession` and
`TAuthoritativeServerSession`. `NativeBytes` covers buffers allocated outside
the garbage-collected heap. `ManagedArrayBytes` covers the elements stored in
managed arrays. Runtime-specific object and array headers are not included, so
the total is best used to compare configurations and enforce a budget rather
than predict the exact process memory shown by the operating system.

The constructors repeat the overflow checks. A configuration whose size cannot
be represented safely is rejected instead of reaching a wrapped allocation.

## Understand deterministic rollback

Rollback may simulate the same frame more than once. It only works if every
simulation produces the same next state every time it receives the same state
and player inputs. Rendering does not need to be deterministic; the simulation
does.

Common sources of divergence are easier to understand by considering what
happens during replay:

| Source | Why it diverges | Safer approach |
| --- | --- | --- |
| Wall clocks or render time | The replay occurs at a different real time | Advance using the numbered simulation frame only |
| Unseeded randomness | Each peer or replay draws a different value | Start a deterministic generator from the shared match seed and store its complete state |
| Unordered collections | Iteration order may vary by process or platform | Use a defined order or sort before order-sensitive work |
| Threads and asynchronous callbacks | Completion order is not reproducible | Feed completed work into the simulation at an agreed frame |
| Floating-point differences | Architectures and compilers may round or fuse operations differently | Prefer integer or explicitly defined fixed-point state |
| Audio, particles and notifications | Replay may perform the visible effect twice | Emit them as rollback effects and consume them only after confirmation |

Collision order is a frequent subtle case. If resolving object A against B
changes the result of later resolving A against C, all peers must visit those
pairs in the same order. Stable identifiers and explicitly sorted collections
are more reliable than object addresses or hash-table traversal.

State snapshots must include everything that influences future deterministic
frames. That includes random-generator state, counters and pending game rules,
not only visible positions. Conversely, camera interpolation, UI state and
audio playback normally should not be included.

Rollback sessions exchange 32-bit state hashes by default. Set `useHash64` in
every peer's `SRollbackSessionConfig` to use 64-bit FNV-1a hashes for desync
checks and state-sync validation. This costs four additional bytes in each hash
and state-sync message. All peers must use the same setting because it changes
the wire format. A stronger hash improves diagnostics; it does not repair a
non-deterministic simulation and is not protection against a malicious peer.

Use `GameNet.RollbackSyncTest` during development to find nondeterministic
state before it becomes a network-only failure. Its `Step` method executes the
same frame twice from the same saved state, compares the complete resulting
state byte-for-byte, and leaves the simulation at the result of one execution.
A failure reports the frame, reason, and first differing byte offset. Run long
scripted input sequences through it on every supported architecture; matching
results on one machine do not prove that floating-point behaviour will match
another compiler or CPU.

`TRollbackSession.PacingInfo` compares the local frame with the slowest reported
remote frame. When the local simulation exceeds the acceptable lead, it returns
a bounded number of simulation steps to defer. Continue pumping networking and
rendering while deferring those steps. The rollback layer deliberately does not
sleep internally or modify input delay, because the application owns its render
loop and fixed-step accumulator.

For live viewing, `GameNet.RollbackSpectator` captures a confirmed state and
then streams confirmed input frames. Send bootstrap and frame packets reliably
and in order, and call the source's matching commit method only after the send
is accepted. Spectators never predict, so their presentation trails the active
players by the confirmation window but never rolls back. Each frame includes
the source state hash; a divergent spectator stops with an explicit hash
mismatch rather than silently showing a different match.

## Treat mobile suspension as part of the protocol

When a mobile app enters the background, it may stop running for much longer
than the rollback history or snapshot window. Treating that interval as
ordinary latency leaves the returning device far behind and may also cause the
other participants to time out.

Use `GameNet.Lifecycle` to turn foreground and background notifications into an
explicit match decision:

- **Continue** only when every participant was deliberately paused and the
  retained state is still valid.
- **Resynchronise** when the connection remains usable but local history is no
  longer trustworthy. An authoritative client waits for a fresh local snapshot;
  a non-authority rollback peer can request state from the configured authority.
- **Reconnect** when the backend session has been lost but the match permits a
  returning participant.
- **Leave** when the game cannot restore a safe, agreed state.

The important point is that resume behaviour is chosen and visible to the
match. It should not depend on how long the operating system happened to suspend
one process.

## Test in layers

Automated protocol tests should run first because they are fast and repeatable.
At minimum, cover truncated and malformed messages, maximum field values,
duplicate and reordered delivery, bounded-queue overflow, and wraparound of
32-bit frame, tick and millisecond counters. A malformed packet should be
rejected before it can partially change game state.

Next, use `GameNet.Impairment` for repeatable latency, jitter, loss,
duplication, reordering, bandwidth limits and temporary blackouts. Short tests
are useful for individual recovery paths; longer scripted soak tests find slow
queue growth, wraparound mistakes and rare ordering combinations.

Finally, test the real backends on real devices. Include background and
foreground transitions, network changes and participant loss. A two-player
GameKit match ending when one player leaves is not enough to test a larger
match, where the remaining participants must continue, so GameKit testing
should eventually include at least three devices or players. ENet Internet
testing must include the actual hosting, NAT or relay arrangement intended for
release; a successful local-network test does not exercise that infrastructure.

During these tests, expose the available health and recovery counters in a
diagnostic overlay or log. Round-trip time, jitter, prediction lead, rollback
depth, stalls, queue overflows and state resynchronisations make a problem much
easier to classify than a general report that the game felt laggy.
