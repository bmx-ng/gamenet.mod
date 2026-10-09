# GameNet.RollbackSession

`GameNet.RollbackSession` coordinates the common machinery of a two-player
deterministic rollback game above `GameNet.Session` and `GameNet.Rollback`.

It provides:

- configurable local input delay and prediction lead;
- redundant frame-numbered input batches;
- bounded prediction, restoration, and re-simulation;
- confirmed-state hash exchange and desync counters; and
- rollback, prediction, rejection, and peer-frame diagnostics.

The game implements `IRollbackSimulation`. It remains responsible for encoding
and restoring deterministic state, predicting its own input format, and
advancing the simulation by one frame. Rendering, audio, particles, and other
irreversible presentation effects should not occur in `SimulateFrame`, because
a predicted frame may be simulated again during rollback.

Applications retain control of their session protocol. Route each remote
input message to `ReceiveInputs`, and each hash message to `ReceiveHash`.
`SendInputs` and `SendReadyHash` are convenience methods for sending through a
`TNetSession`; `WriteInputs` and `WriteReadyHash` are also available when the
application needs to compose or route messages itself.
