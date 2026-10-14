# GameNet.MatchRoom

`GameNet.MatchRoom` coordinates the staging area around a multiplayer match.
It is deliberately separate from provider discovery: Steam or EOS may supply a
backend lobby, GameKit may supply an already-connected `GKMatch`, and LAN play
may begin with local discovery. Once a `TNetSession` exists, all of them can use
the same room protocol.

The elected session host owns the canonical roster, ready state, opaque match
configuration, round number, and shared seed. Complete bounded snapshots make
late synchronization and recovery straightforward. The room also coordinates
match completion, independent result viewing, rematches, active-match
abandonment, and participant loss.

Applications reserve two session message identifiers, report session joins and
leaves with `PlayerJoined` and `PlayerLeft`, and route matching messages to
`Receive`. Game-specific configuration remains an opaque packet, so a game can
encode maps, teams, colours, rule variants, or any other compact setup data.
