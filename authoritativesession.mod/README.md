# GameNet.AuthoritativeSession

`GameNet.AuthoritativeSession` composes the lower-level session, prediction,
and snapshot modules into a reusable server-authoritative networking layer.
Game state and inputs remain opaque byte payloads, so the module is independent
of a game's simulation, coordinate system, and rendering.

`TAuthoritativeClientSession` provides:

- bounded, sequenced local input history;
- redundant unreliable-sequenced input batches;
- acknowledgement and removal of processed inputs;
- local reconciliation by restoring an authoritative state and replaying every
  still-unacknowledged input;
- bounded per-entity snapshot timelines;
- server-clock estimation and adaptive interpolation delay; and
- explicit packet rejection, storage, and failure diagnostics.

`TAuthoritativeServerSession` provides:

- fixed player-to-peer bindings;
- validation and de-duplication of redundant input batches;
- bounded, contiguous per-player input queues;
- explicit acknowledgement after the game applies an input; and
- recipient-specific snapshot encoding and sending.

The module does not own or poll `TNetSession`. Applications retain control over
join policy, entity spawning, match lifecycle, simulation cadence, and snapshot
frequency. Route the configured input and snapshot message types to the
appropriate authoritative session methods.

## Typical flow

The client queues each fixed-step input, immediately predicts it in the game,
and calls `SendInputs`. When a local authoritative snapshot arrives, call
`ReceiveSnapshot` followed immediately by `Reconcile`. Remote entities are
rendered by sampling `SampleEntity` at `RenderTick`.

The authority binds a player after the network session accepts it. It routes
input packets to `ReceiveInputs`, applies commands returned by `PeekInput`, and
then calls `AcknowledgeInput`. At its chosen snapshot frequency it calls
`SendSnapshot` for the relevant entities and recipients.

All capacities are fixed by `SAuthoritativeSessionConfig`. Normal input,
snapshot, acknowledgement, reconciliation, and interpolation operations reuse
preallocated storage.

`TAuthoritativeClientSession.MemoryRequirements` and
`TAuthoritativeServerSession.MemoryRequirements` expose the native payload
buffers and managed array element storage implied by a configuration before it
is allocated. The estimates exclude runtime object and array headers and reject
`Size_T` arithmetic overflow.

After an application suspension, `BeginRecovery` clears stale snapshot and
clock history, temporarily refuses new prediction input, and waits for a fresh
snapshot of the configured local entity. Existing unacknowledged inputs remain
available for normal server acknowledgement and reconciliation.
