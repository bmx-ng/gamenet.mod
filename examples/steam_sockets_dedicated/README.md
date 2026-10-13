# Steam Networking Sockets dedicated-server example

This example shows the complete shape of a headless GameNet server: initialize
the Steam game-server API, advertise a server, create the game-server form of
Steam Networking Sockets, and use it through `INetTransport`.

The sample echoes packets for 30 seconds and then shuts down cleanly. Pass a
different duration in seconds as its first argument. Before using it with a
real Steam application, replace the example product and description values,
provide the application's Steam App ID in the normal Steamworks environment,
and choose ports allowed by the host firewall.

Running the process locally is enough for development. Deploying it publicly is
the developer's choice: their own host, a game-server provider, a container, or
another allocation service can all run the same executable. Steam supplies the
networking and game-server APIs, not the machine on which this process runs.
