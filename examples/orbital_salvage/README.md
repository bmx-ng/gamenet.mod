# Orbital Salvage

Orbital Salvage is a small two-player authoritative game built to exercise
`GameNet.Replication` over either a real Game Center match or a direct ENet
connection. Each pilot collects the glowing energy cores near the centre of
the arena and carries them back to their coloured dock. A short-range pulse
forces a nearby opponent to drop the core they are carrying. The first player
to recover five cores wins.

The elected GameKit host or explicit ENet host runs the simulation and owns the
replicated world. `GameNet.Replication` carries entity lifecycle, core state,
scores, and the winner. Deposited cores exercise reliable despawn followed by
a later spawn, and the authority uses separate bounded reliable and snapshot
budgets.

Fast-moving player state uses `GameNet.AuthoritativeSession`. Both player
positions travel in one atomic world snapshot so sequenced delivery cannot
discard one player's update in favour of the other's. The replica
numbers and redundantly transmits its fixed-tick inputs, predicts its own ship,
then reconciles each authoritative position by replaying inputs the host has
not acknowledged. Remote ships are rendered from a short, adaptive snapshot
history rather than chasing the most recently received position. A carried
core is presented as an attachment to that ship, so the pair cannot visibly
disagree even though the authority still owns pickup, collision, and scoring.

`protocol.bmx` contains the transport-neutral schemas, packet encoding,
deterministic movement, and authority simulation. `orbital_salvage_game.bmx`
contains the shared hybrid session orchestration, presentation, and rendering.
The small GameKit and ENet launchers only establish their respective transports,
so both versions run the same game and network protocol.

## GameKit

Before building, replace the example bundle identifier in
`gamekit_orbital_salvage.settings` with an App Store Connect application that
has Game Center enabled. Sign the generated project with your development
team. Run it on two devices using different Game Center friends, then select
**Find Salvage Match** on both devices.

## ENet

`enet_orbital_salvage.bmx` runs the same game directly between two devices on
the same local network. Its iOS settings include a local-network usage message;
the first launch may therefore display the standard iOS permission prompt.

Start the program on both devices and select **Host Game** on one of them. The
host screen displays its preferred LAN IPv4 address and UDP port. Enter that
address in the second device's **Host Address** field and select **Join Game**.
This version requires no Game Center accounts or Internet matchmaking service.
The displayed address is local to the current network and may change when the
device joins another network.

## Controls and tests

The on-screen analogue stick moves the ship and **PULSE** activates its
short-range field. WASD or the arrow keys and Space provide desktop controls.

`test_protocol.bmx` uses loopback sessions to verify the complete initial
world, client-to-authority input, replicated movement, core pickup and pulse
drop, reliable scoring, and entity destruction.
