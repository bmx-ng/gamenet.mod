# GameNet.GameKitOnline

`GameNet.GameKitOnline` adapts Game Center authentication and programmatic
automatching to the optional `GameNet.Online` service contract. A successful
matchmaking operation emits `MatchReady`; call `TakeMatchTransport` with that
event's request identifier to take ownership of its `TGameKitTransport`.
`MatchInfo` reports the deterministically elected GameNet session host. Client
transports are filtered to that host before ownership is transferred.

The adapter advertises `Matchmaking` and `MatchTransport`. It does not pretend
that Game Center automatching is a searchable lobby service.

Game Center has one process-wide listener. Create this adapter after installing
any `Apple.GameKit` listener used by the rest of the application. While open,
the adapter forwards authentication, achievement, leaderboard, and dashboard
callbacks to that listener. Closing the adapter restores it.
