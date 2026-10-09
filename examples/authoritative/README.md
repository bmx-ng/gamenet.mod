# Authoritative movement example

This example deliberately separates game authority from presentation:

- `server.bmx` is a headless ENet host. It owns the simulation and the players'
  positions, with room for four clients.
- `client.bmx` uses `GameNet.Prediction` to retain and replay sequenced input,
  predicts its own movement immediately, reconciles it with the host, and uses
  `GameNet.Snapshot` to interpolate other players from a bounded timeline.
- `protocol.bmx` is shared wire-format code built from `GameNet.Core` packet
  readers and writers.

Spawn and despawn messages use reliable ordered delivery on the control channel.
Input and per-entity snapshots use unreliable sequenced delivery on the gameplay
channel. Each input packet repeats the client's bounded unacknowledged command
window, so a later packet can repair an earlier loss. The host processes every
command exactly once and acknowledges the last processed sequence in snapshots.
This is a small example of choosing guarantees per message rather than making
every packet reliable.

Build and run the host first:

```sh
bmk makeapp -r -t console server.bmx
./server
```

Then build and run the client:

```sh
bmk makeapp -r client.bmx
./client
```

The client defaults to `127.0.0.1:46340`. A desktop client can specify another
host and port on its command line:

```sh
./client 192.168.1.20 46340
```

For an iOS or Android device, set `serverAddress` near the top of `client.bmx`
to the host computer's LAN address before building. The host firewall must allow
incoming UDP traffic on port 46340. `client.settings` applies the included
Android manifest and iOS property-list overlays so device builds request local
network access.

The example sends snapshots at 60 Hz. Local prediction keeps input responsive;
small reconciliation errors are corrected over several frames rather than by
snapping. Other players use an adaptive render delay: it expands when snapshot
arrivals are late, then slowly recovers toward a two-tick baseline. The host's
positions remain authoritative throughout. The host also buffers eight fixed-
step input commands before consuming them, allowing ordinary arrival jitter to
be absorbed without making remote movement bursty.
