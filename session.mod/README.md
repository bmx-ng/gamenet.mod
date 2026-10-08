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

```blitzmax
Const GAME_PROTOCOL:UInt = $41535452 ' ASTR
Const GAME_VERSION:UInt = 1

Local host:TNetSession = TNetSession.CreateHost(transport, GAME_PROTOCOL, GAME_VERSION)
```

Session and message payloads are borrowed packet views. Process or copy them
before the next call to `Poll` on that session.

The session owns its transport. Closing the session closes the transport.
