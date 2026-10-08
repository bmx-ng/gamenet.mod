# Authoritative movement example

This example deliberately separates game authority from presentation:

- `server.bmx` is a headless ENet host. It owns the simulation and the player's
  position.
- `client.bmx` sends sequenced input and only draws positions received from the
  host.
- `protocol.bmx` is shared wire-format code built from `GameNet.Core` packet
  readers and writers.

The spawn message uses reliable ordered delivery on the control channel. Input
and snapshots use unreliable sequenced delivery on the gameplay channel. This
is a small example of choosing guarantees per message rather than making every
packet reliable.

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
incoming UDP traffic on port 46340. The Android SDL template already requests
network access.

The example intentionally does not perform client prediction or snapshot
interpolation. The visible latency makes the boundary clear: input is a request,
and the host's snapshots are authoritative. Those presentation techniques can
be added without changing the transport or session APIs.
