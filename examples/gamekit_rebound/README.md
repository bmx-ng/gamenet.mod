# GameKit Rebound

GameKit Rebound is a small two-player rollback game built above
`Apple.GameKit`, `GameNet.GameKit`, `GameNet.Session`, and
`GameNet.RollbackSession`. Each player protects five shield segments and a
core. Move the paddle to steer returns, charge the energy bar, and hold POWER
as the ball reaches the paddle for a faster return. The first player to break
all five opposing shields wins. Both players can then hold POWER to ready a
rematch without leaving the Game Center match.

The deterministic simulation uses integer fixed-point positions, a shared
random seed, bounded input and state sizes, redundant unreliable input,
confirmed state hashes, rollback-safe effects, and authority-based full-state
recovery. The HUD shows live GameNet health and rollback information.

Before building, replace the example bundle identifier in
`gamekit_rebound.settings` with an App Store Connect application that has Game
Center enabled. Sign the generated project with your development team. Run the
example on two devices using different Game Center friends, tap **Find Match**
on both, and use the on-screen UP, DOWN, and POWER buttons. WASD or the arrow keys
and Space provide desktop controls.

`test_protocol.bmx` runs the game simulation twice for 1,200 frames and checks
that every saved state is identical, that scoring occurs, and that state
serialization round-trips correctly.
