# GameNet.Nakama

`GameNet.Nakama` adapts Nakama's client-relayed realtime matches to the
provider-neutral `GameNet.Online` and `INetTransport` APIs.

The initial capability set is deliberately narrow:

- device authentication and realtime socket setup;
- native Nakama matchmaking and cancellation;
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
