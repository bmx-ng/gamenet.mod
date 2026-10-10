# GameNet.GameKit

`GameNet.GameKit` adapts an `Apple.GameKit` real-time `TGameCenterMatch` to the common `INetTransport` contract. It is available on macOS and iOS.

Game Center matchmaking remains in `Apple.GameKit`. When its multiplayer listener supplies a match, create the transport and place `GameNet.Session` above it:

```blitzmax
Method OnGameCenterMatchFound(requestId:Int, match:TGameCenterMatch, error:TGameCenterError)
	If error Then Return
	Local transport:TGameKitTransport = TGameKitTransport.Create(match, 8, 4, 900)
	Local session:TNetSession = TNetSession.CreateClient(transport, applicationId, version, Null, 0, 4, 900)
End Method
```

The host/client role is a GameNet protocol decision, not a GameKit distinction. Peers need to agree which participant is the GameNet host before creating their sessions; the first integration example uses a deterministic player-identity comparison.

## Wire adaptation

`GKMatch` offers reliable and unreliable delivery. The adapter adds:

- logical channel identifiers;
- delivery-mode metadata;
- sequence numbers and stale-packet rejection for `UnreliableSequenced`;
- stable `SNetPeer` handles for Game Center match players.

The default maximum GameNet payload is 900 bytes. Every packet also carries a 12-byte adapter header. Applications can choose a different bound when creating the transport, but small unreliable packets are strongly recommended by Apple.

GameKit does not expose a way to remove only one participant from a peer-to-peer `GKMatch`. Calling `INetTransport.Disconnect` therefore ends the entire native match and produces local disconnection events for every active peer.
