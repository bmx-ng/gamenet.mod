# Counter Cascade

Counter Cascade is a deterministic board-game example for two to four players.
Players add counters to empty cells or cells they already own. A square cell
topples four counters and a hexagonal cell topples six, capturing every cell
the counters enter. Boundary routes reflect inward, so an edge can send more
than one counter to the same neighbour.

The board uses a high-resolution filtered counter texture so pieces remain
smooth on Retina displays. Cascades are shown one atomic topple at a time
instead of jumping directly to the resolved board. The presentation currently
uses a 100 ms delay per topple; this can later become a game option.
Counter quantities are shown as pips rather than digits. A cell wobbles when
its next counter will make it topple. A compact balance chart shows each
player's share of all counters and updates at every animated cascade step.

The first implementation is a local rules playground with five layouts:

- a quick two-player 5 by 5 rectangular duel;
- a four-player square board;
- a quick two-player radius-3 hexagonal board;
- a three-player regular hexagonal board;
- a four-player hexagonal rhombus.

The map builder uses `Max2D.TileMap` for rectangular and hexagonal coordinate
systems, neighbour directions, drawing geometry and pointer picking. It turns
each map into a compact route table before play. The rules engine consequently
depends only on stable cell indices and can be run without a graphics context.

Every move resolves cells in a canonical order and produces a bounded event
log for presentation. A player wins immediately after an atomic topple leaves
only one participating colour on the board. Other repeating or excessive
cascades are detected, and the attempted move is rolled back rather than
leaving a partial board. The state hash includes the map topology, turn state,
owners and counter totals.

`test_rules.bmx` verifies square and hex construction, reflected boundaries,
starting counters, legal turns, corner toppling, retained excess counters and
deterministic state hashes.

`protocol.bmx` defines compact backend-neutral messages for online matches:
room configuration and readiness, validated match configuration and starting
player, move requests, authoritative applied moves, and post-move state
hashes. On Apple targets the Multiplayer menu offers Game Center quick match.
Matched players enter a persistent room where the host selects a square or hex
duel and both players ready up before play. After a match, each player returns
to the lobby independently; the lobby shows when the other player is still on
the results screen and does not permit another ready-up until both return.
GameKit supplies matchmaking and transport, while a GameNet session elects
the authority and carries the same deterministic protocol that another
backend could use later.

`test_protocol.bmx` verifies strict packet decoding and proves that host and
client games remain identical while replaying transmitted moves. If a client
nevertheless detects a turn or state-hash disagreement, it requests a bounded
full-state snapshot and validates it completely before replacing local state.
