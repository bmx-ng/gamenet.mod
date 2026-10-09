# GameNet.RollbackSession

`GameNet.RollbackSession` coordinates the common machinery of a two-player
deterministic rollback game above `GameNet.Session` and `GameNet.Rollback`.

It provides:

- configurable local input delay and prediction lead;
- redundant frame-numbered input batches;
- bounded prediction, restoration, and re-simulation;
- rollback-safe presentation effects released only after confirmation;
- confirmed-state hash exchange and desync counters; and
- rollback, prediction, rejection, and peer-frame diagnostics.

The game implements `IRollbackSimulation`. It remains responsible for encoding
and restoring deterministic state, predicting its own input format, and
advancing the simulation by one frame. It can optionally also implement
`IRollbackEffectSimulation` to receive an `IRollbackEffectWriter` while each
frame is simulated. This is intended for presentation events such as sounds,
particles, and notifications. Existing simulations that only implement
`IRollbackSimulation` remain source-compatible and incur no effect-buffer
allocation. Effects from predicted frames are retained, rebuilt if the frame
is re-simulated, and returned once through `PollConfirmedEffect` only after the
final inputs are confirmed.

Effect kind and payload are application-defined. Both per-frame recording and
the confirmed delivery queue have fixed configurable bounds. Applications
should poll effects regularly and can inspect `DroppedConfirmedEffects` to
detect a delivery queue that is too small.

Applications retain control of their session protocol. Route each remote
input message to `ReceiveInputs`, and each hash message to `ReceiveHash`.
`SendInputs` and `SendReadyHash` are convenience methods for sending through a
`TNetSession`; `WriteInputs` and `WriteReadyHash` are also available when the
application needs to compose or route messages itself.
