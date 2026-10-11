# GameKit session example

This Apple-only example programmatically automatches Game Center players,
elects a deterministic GameNet session host from their scoped player
identifiers, and exchanges reliable application messages through
`GameNet.Session` over `GameNet.GameKit`. Matchmaking is driven through the
backend-neutral `GameNet.Online` API and its `GameNet.GameKitOnline` provider.

Before building, give `gamekit_session.settings` a bundle identifier which has Game Center enabled in App Store Connect. Sign each build with the appropriate development team. The two devices must use different authenticated Game Center players.

Launch the example on each device and select **Find Match**. Once the sessions
join, **Send Packet** transmits an incrementing counter. The elected host sends
to every joined client; each client sends only to the host.

The checked-in constants request exactly two players so the example remains
easy to run. Raise both `MATCH_MIN_PLAYERS` and `MATCH_MAX_PLAYERS` to the same
fixed roster size to exercise a larger match. The native `GKMatch` remains a
full mesh, but clients filter it to expose only the elected host; the host
exposes every participant. If one client leaves, the host and remaining
clients stay connected. Host migration is not implemented, so losing the
elected host ends the client sessions.
