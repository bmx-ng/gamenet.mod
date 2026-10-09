# GameNet.Session

`GameNet.Session` adds a small versioned protocol above `INetTransport`.
It deliberately stops short of game-state replication.

A client sends an application identifier, application protocol version, and
optional opaque hello data. A compatible host receives a `JoinRequested` event
and explicitly accepts or rejects it. This permits authentication to be local,
GameKit-based, Google-based, or backed by a developer service without changing
the wire/session API.

After acceptance, either side can send numeric application message types using
any logical channel and delivery mode supported by the underlying transport.

An optional `SSessionHealthConfig` adds handshake and idle deadlines plus
internal active probes. Configure it before the first call to `Poll`.
`GetPeerHealth` then reports smoothed round-trip time, jitter, unanswered probe
count, idle time, and aggregate session frame/byte counters. Probes are internal
protocol frames and never appear as application messages. `PollAt` accepts an
explicit modular millisecond clock for deterministic tests; ordinary `Poll`
uses `MilliSecs`.

```blitzmax
Const GAME_PROTOCOL:UInt = $41535452 ' ASTR
Const GAME_VERSION:UInt = 1

Local host:TNetSession = TNetSession.CreateHost(transport, GAME_PROTOCOL, GAME_VERSION)
host.ConfigureHealth(New SSessionHealthConfig(10000, 30000, 1000, 3000))
```

Session and message payloads are borrowed packet views. Process or copy them
before the next call to `Poll` on that session.

The session owns its transport. Closing the session closes the transport.
Health is disabled by default. Both endpoints should run a build which supports
health probes before probes are enabled. Probe loss describes unanswered health
probes; it is not a measurement of every unreliable application packet. Poll
regularly because measured latency necessarily includes time waiting in the
local event queue.
