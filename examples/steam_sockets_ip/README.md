# Steam Networking Sockets IP example

This example creates a Steam Networking Sockets listener and client in one
process over `127.0.0.1`. It verifies connection events and reliable GameNet
packet delivery without requiring a deployed server.

Steam must be running. During development, provide the application's Steam App
ID in the usual way and make the Steam API runtime library available beside the
executable or through the platform library search path.
