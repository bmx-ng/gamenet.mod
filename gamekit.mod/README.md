# GameNet.GameKit

`GameNet.GameKit` adapts an `Apple.GameKit` real-time `TGameCenterMatch` to the common `INetTransport` contract. It is available on macOS and iOS.

Applications can import `GameNet.GameKitOnline` and use
`TGameKitOnlineService` through the optional `GameNet.Online` interface for
programmatic automatching. A `MatchReady` event then supplies the transport
through `TakeMatchTransport`.

The lower-level route remains available. When the `Apple.GameKit` multiplayer
listener supplies a match, create the transport and place `GameNet.Session`
above it:

```blitzmax
Method OnGameCenterMatchFound(requestId:Int, match:TGameCenterMatch, error:TGameCenterError)
	If error Then Return
	Local transport:TGameKitTransport = TGameKitTransport.Create(match, 8, 4, 900)
	Local session:TNetSession = TNetSession.CreateClient(transport, applicationId, version, Null, 0, 4, 900)
End Method
```

The host/client role is a GameNet protocol decision, not a GameKit distinction. Peers need to agree which participant is the GameNet host before creating their sessions; the first integration example uses a deterministic player-identity comparison.

## Matches with more than two players

`GKMatch` is a full peer-to-peer mesh, while `GameNet.Session` has one host or
client role. Use `GameKitElectedHostIndex` on every participant. It returns
zero to the elected local host and otherwise returns that host's stable
one-based match index. The host leaves every transport player enabled and
creates a host session sized for all remote participants. Each client calls
`EnableOnlyPlayer(hostIndex)` before its first transport/session poll and
creates a one-peer client session. The other native mesh participants are then
hidden from that client session.

Player filtering affects only the GameNet view; GameKit still owns the native
mesh. It must be configured before polling begins. A participant which leaves
produces a disconnection only for that peer, and the remaining host/client
links stay open. If the elected host leaves, clients should end or rematch
unless the game implements its own host-migration protocol.

## Wire adaptation

`GKMatch` offers reliable and unreliable delivery. The adapter adds:

- logical channel identifiers;
- delivery-mode metadata;
- sequence numbers and stale-packet rejection for `UnreliableSequenced`;
- stable `SNetPeer` handles for Game Center match players.

The default maximum GameNet payload is 900 bytes. Every packet also carries a 12-byte adapter header. Applications can choose a different bound when creating the transport, but small unreliable packets are strongly recommended by Apple.

Apple currently permits 16 total participants in a GameKit match. Since the
local participant is not represented as a transport peer, the adapter supports
and defaults to `GAMEKIT_MAX_REMOTE_PEERS` (15). Higher-level simulation models
may deliberately impose smaller limits; `GameNet.RollbackSession`, for example,
remains capped at eight total players.

GameKit does not expose a way to remove only one participant from a peer-to-peer `GKMatch`. Calling `INetTransport.Disconnect` therefore ends the entire native match and produces local disconnection events for every active peer.

Duplicate connection/disconnection notifications and late packets from hidden
or departed players are discarded. If the native match closes without first
delivering its failure callback, the adapter reports `MatchClosed` followed by
local disconnection events for every exposed active peer.
