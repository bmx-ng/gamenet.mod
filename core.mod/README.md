# GameNet.Core

`GameNet.Core` defines the backend-neutral boundary used by game networking
transports. It deliberately does not perform matchmaking, open sockets, or
replicate game objects.

The polling and packet APIs use value Structs and caller- or backend-owned
storage. Polling an idle transport and processing an existing packet therefore
do not inherently create managed garbage.

Packet views returned in events are borrowed. They remain valid until the next
call to `Poll` on that transport and should be copied if the game needs to retain
the bytes.

Delivery modes describe game intent:

- `Unreliable` sends time-sensitive data which may be lost or reordered.
- `UnreliableSequenced` additionally discards obsolete messages within a
  logical channel. A backend can provide this directly or implement it in the
  common protocol layer.
- `ReliableOrdered` delivers every message in order unless the peer disconnects.
