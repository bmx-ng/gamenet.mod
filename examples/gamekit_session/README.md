# GameKit session example

This Apple-only example programmatically automatches two Game Center players, elects a deterministic GameNet session host from their scoped player identifiers, and exchanges a reliable application message through `GameNet.Session` over `GameNet.GameKit`.

Before building, give `gamekit_session.settings` a bundle identifier which has Game Center enabled in App Store Connect. Sign each build with the appropriate development team. The two devices must use different authenticated Game Center players.

Launch the example on both devices and select **Find Match**. Once both sessions join, **Send Packet** transmits an incrementing counter to the other device.

The initial example deliberately requests exactly two players. A `GKMatch` is a full peer-to-peer mesh, while the current host/client `GameNet.Session` exposes every transport peer to one global session role. Supporting larger GameKit matches cleanly requires an explicit topology decision: expose only the elected host to clients, or introduce a peer-symmetric session layer.
