# GameNet.Nakama

`GameNet.Nakama` adapts Nakama's client-relayed realtime matches to the
provider-neutral `GameNet.Online` and `INetTransport` APIs.

The initial capability set is deliberately narrow:

- device authentication and realtime socket setup;
- native Nakama matchmaking and cancellation;
- exact-match string properties from `TOnlineMatchmakingRequest.properties`;
- deterministic GameNet host selection from Nakama session IDs;
- directed match data with GameNet channels and delivery metadata;
- transport ownership which can outlive the online-service object.

Nakama carries match data over its reliable WebSocket. Consequently,
`Unreliable` and `UnreliableSequenced` describe GameNet behavior rather than
the physical wire transport. Sequenced messages reject stale frames, but none
of these modes provide UDP latency or loss characteristics.

Lobby discovery, invitations, parties, RPC, storage, chat and authoritative
server features are not advertised by this adapter. Applications can use
`Nakama.SDK` directly for Nakama facilities outside GameNet's matchmaking and
transport contracts.

Matchmaking property keys may contain ASCII letters, digits, `_`, and `-`.
Each property is submitted as a Nakama string property and converted into a
mandatory exact-match query. Query metacharacters and spaces in values are
escaped automatically.

An unexpected realtime socket loss is terminal for the current adapter and
any handed-off transport: the service reports a `Network` failure and the
transport disconnects its active peers. A game should return to its online
flow and create a fresh service/match rather than attempting to reuse the old
Nakama match. Transparent match restoration is not currently advertised.

## Basic flow

```blitzmax
Local online:TNakamaOnlineService = TNakamaOnlineService.Create( ..
	"127.0.0.1", 7350, "defaultkey", "my-device-id", "Player")

Local openRequest:UInt = online.Open()
' Pump and poll until ServiceReady.

Local request:TOnlineMatchmakingRequest = New TOnlineMatchmakingRequest
request.minPlayers = 2
request.maxPlayers = 2
Local matchRequest:UInt = online.StartMatchmaking(request)
' Pump and poll until MatchReady.

Local info:SOnlineMatchInfo
If online.MatchInfo(matchRequest, info) Then
	Local transport:INetTransport = online.TakeMatchTransport(matchRequest)
	' Create TNetSession.CreateHost or CreateClient according to info.
End If
```

Call `Pump` regularly until the match transport is handed off. After handoff,
polling the transport pumps the shared Nakama connection, and the online
service may be closed independently.

The module has deterministic provider tests in `tests/test.bmx`. The Nakama
repository's `test-server/run-integration.sh` additionally starts a disposable
local server and runs a complete two-client `TNetSession` exchange.

The current validation matrix covers native macOS arm64 and Windows MinGW x64.
Linux, macOS x64, and TLS/WSS integration have not yet been release-tested.
