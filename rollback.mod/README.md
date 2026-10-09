# GameNet.Rollback

`GameNet.Rollback` provides bounded, transport-independent history for a
deterministic rollback simulation. It stores opaque game state and opaque input
for each player and frame.

The game saves state at the beginning of a frame, confirms available inputs,
and supplies predictions for missing inputs. When confirmed input differs from
the prediction, `TRollbackBuffer` reports the earliest affected frame. The game
restores that state and re-simulates through the present using the retained
inputs.

The module does not run the simulation or presentation. Games must keep audio,
particles, achievements, networking, and other one-shot side effects outside
re-simulation. Deterministic state should avoid platform-dependent time,
randomness, iteration order, and floating-point behavior where cross-platform
peers must agree exactly.

All state and input storage is allocated by `TRollbackBuffer.Create`; ordinary
frame operations perform no managed allocation.
