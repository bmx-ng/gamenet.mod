# GameNet.Steam

`GameNet.Steam` adapts Steam Networking Messages to `INetTransport` on desktop
targets. Peers are addressed by Steam ID, while the transport exposes stable
GameNet peer handles, logical channels, and the three GameNet delivery modes.

Create a transport after a Steam lobby has selected the participating players.
The lobby owner is normally used as the GameNet session host. Applications that
want the common lobby flow should use `GameNet.SteamOnline` rather than creating
this lower-level transport directly.

The default payload limit is 1200 bytes. Steam can fragment larger messages,
but the conservative default keeps GameNet traffic suitable for real-time play.
