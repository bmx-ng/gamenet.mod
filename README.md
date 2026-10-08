# Game networking modules for BlitzMax NG

Transport-independent building blocks for real-time multiplayer games.

## Modules

- `GameNet.Core` defines peer and event values, the transport contract, delivery
  modes, and bounded packet readers and writers.
- `GameNet.Loopback` provides an in-process, preallocated transport for tests,
  local multiplayer, and protocol development.
- `GameNet.ENet` provides UDP networking through ENet for direct and hosted
  connections.

Planned transport modules include `GameNet.GameKit`. Each backend imports
`GameNet.Core`; the core module does not depend on a native networking library
or platform service.

This repository requires the current bcc2-based BlitzMax NG toolchain because
its low-allocation API uses value Structs.

Install the repository as `mod/gamenet.mod` in a BlitzMax NG SDK:

```sh
git clone https://github.com/bmx-ng/gamenet.mod.git mod/gamenet.mod
```
