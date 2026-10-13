# GameNet.SteamOnline

`GameNet.SteamOnline` implements the optional `GameNet.Online` service contract
with Steam lobbies. It supports local identity, lobby creation and discovery,
joining and leaving, invitations, lobby metadata, and handing a connected
GameNet transport to the game. `TSteamOnlineService.Create` uses
`GameNet.Steam` Networking Messages by default for compatibility. Passing
`ESteamOnlineTransportKind.NetworkingSockets` selects the connection-oriented
`GameNet.SteamSockets` backend instead.

With Networking Sockets, the lobby owner creates a P2P listener and the other
members connect to the owner's Steam identity. Steam can negotiate direct or
relayed routes; the game continues to receive the same `INetTransport` from
`TakeMatchTransport`.

Alternatively, the lobby owner can call `SetDedicatedServer` with a known
numeric IPv4 endpoint or a Steam game-server identity before starting the
match. Steam publishes that assignment through the lobby. Every member,
including the owner, then receives a client transport whose session-host peer
is the dedicated server. Discovering or allocating that machine remains an
external concern; the service does not pretend to supply hosting.

Invitations are reported both when Steam delivers them to a running game and
when accepting one launches the game with `+connect_lobby`. The application
decides when to call `AcceptInvitation`, so it can show its own confirmation or
leave an existing session first.

The concrete service also provides `ShowInviteDialog` for Steam's standard
friend picker and `InvitePlayer` when the application already knows a Steam
player ID. Automatic queue-based matchmaking is not implemented in this first
provider; `StartMatchmaking` returns zero. Games can create/find lobbies or add
a separate ticket-based coordinator later without changing the transport.

For a peer-hosted match, the Steam lobby owner is the GameNet session host. For
a dedicated match, every lobby member is a client. Calling `StartMatch` as the
lobby owner closes the lobby to new members and marks it started; joined
clients that have also requested `StartMatch` then receive their own
`MatchReady` event.

The provider initializes Steam callback processing in manual mode and pumps it
from `Pump`. It does not shut down the process-wide Steam API when closed,
because other Steam features may still be in use by the application.

The provider's Steam operations are isolated behind `ISteamOnlineBackend`.
Normal applications use `TSteamOnlineService.Create`; `CreateForBackend` exists
for deterministic service tests and specialised embedding.
