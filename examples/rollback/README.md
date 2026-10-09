# Rollback example

This Max2D example runs a deterministic two-player simulation locally. Blue is
controlled with WASD, the arrow keys, or the on-screen stick. Orange follows a
script whose inputs are deliberately delayed by 6-18 simulation frames.

The client predicts missing orange input from the last confirmed value. When a
late input differs, it restores the saved state at the earliest mismatched
frame, replaces later predictions, and re-simulates up to the present frame.
The HUD reports the number and depth of those corrections.

The artificial local delay makes rollback behavior reproducible without a
network connection. A real transport supplies the same per-frame confirmed
inputs to `TRollbackBuffer`; it does not change the simulation or replay path.

Only deterministic game state belongs in rollback history. Rendering, sound,
particles, analytics, and other one-shot effects should be derived after the
simulation or guarded so re-simulation does not emit them twice.
