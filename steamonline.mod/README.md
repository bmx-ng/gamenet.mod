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

Invitations are reported both when Steam delivers them to a running game and
when accepting one launches the game with `+connect_lobby`. The application
decides when to call `AcceptInvitation`, so it can show its own confirmation or
leave an existing session first.

The concrete service also provides `ShowInviteDialog` for Steam's standard
friend picker and `InvitePlayer` when the application already knows a Steam
player ID. Automatic queue-based matchmaking is not implemented in this first
provider; `StartMatchmaking` returns zero. Games can create/find lobbies or add
a separate ticket-based coordinator later without changing the transport.

The Steam lobby owner is the GameNet session host. Calling `StartMatch` as the
owner closes the lobby to new members and marks it started; joined clients that
have also requested `StartMatch` then receive their own `MatchReady` event.

The provider initializes Steam callback processing in manual mode and pumps it
from `Pump`. It does not shut down the process-wide Steam API when closed,
because other Steam features may still be in use by the application.

The provider's Steam operations are isolated behind `ISteamOnlineBackend`.
Normal applications use `TSteamOnlineService.Create`; `CreateForBackend` exists
for deterministic service tests and specialised embedding.
