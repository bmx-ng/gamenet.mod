# GameNet.Online

`GameNet.Online` defines an optional, backend-neutral contract for moving
players from an online service into a connected GameNet match. It does not
contact a service by itself and it is not required for direct ENet, LAN, or
known-server connections.

Adapters can implement the contract for services such as GameKit, Steam,
Nakama, or Epic Online Services. The common surface covers player identity,
lobbies, invitations, matchmaking, asynchronous events, and delivery of an
`INetTransport`. Provider-specific features remain available through each
adapter rather than being forced into the common model.

Online operations return a nonzero request identifier when accepted. Call
`Pump` regularly, drain `Poll`, and correlate completion events through
`SOnlineEvent.RequestId`. A `MatchReady` event allows the application to take
ownership of the resulting transport exactly once using `TakeMatchTransport`.
Before taking it, `MatchInfo` reports whether the local game should create a
GameNet host or client session and identifies the host peer for a client.

Always inspect `Capabilities` before presenting optional features. For example,
a backend may support invitations and matchmaking without searchable lobbies,
or it may arrange a dedicated server instead of creating a peer-to-peer match.

The initial contract deliberately does not try to standardise achievements,
leaderboards, cloud storage, friends, commerce, or provider authentication.
Those features have different lifecycles and can be added as separate service
interfaces if concrete integrations demonstrate a useful common model.
