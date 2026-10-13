# GameNet.SteamSockets

`GameNet.SteamSockets` implements `INetTransport` using Steam Networking
Sockets. It supports connection-oriented Steam P2P and numeric IP connections,
including listener transports suitable for peer hosts or dedicated servers.

P2P connections use Steam identities and can benefit from Steam NAT traversal
and relay routing. IP connections are useful for locally testing a dedicated
server without deploying any online infrastructure.

```blitzmax
Local server:TSteamSocketsTransport = TSteamSocketsTransport.ListenIP(27015)
Local client:TSteamSocketsTransport = TSteamSocketsTransport.ConnectIP("127.0.0.1", 27015)
```

The transport exposes the same reliable, unreliable, and unreliable-sequenced
delivery modes as the other GameNet backends. Its default payload limit is 1200
bytes. `GetConnectionStatus` provides Steam's RTT, connection-quality, queue,
and pending-byte diagnostics.

Creating a dedicated server process does not require a hosting provider: the
process can listen locally or on any machine controlled by the developer.
Steam game-server identity, authentication, server registration, allocation,
and hosted Steam Datagram Relay are separate optional layers.

After `SteamGameServerInit` succeeds, create the server forms of both Steam
interfaces and pass the sockets object to the transport:

```blitzmax
Local gameServer:TSteamGameServer = TSteamGameServer.Create()
Local sockets:TSteamNetworkingSockets = TSteamNetworkingSockets.Create(True)
Local transport:TSteamSocketsTransport = TSteamSocketsTransport.ListenIP(27015, 32, 8, "", STEAM_SOCKETS_DEFAULT_MAX_PACKET_SIZE, sockets)
```

Polling the transport dispatches the game-server callback queue as well as
network traffic. The application should still configure and log on the
`TSteamGameServer`, validate player authentication tickets when required, and
call `SteamGameServerShutdown` during orderly shutdown.
