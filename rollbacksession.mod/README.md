# GameNet.RollbackSession

`GameNet.RollbackSession` coordinates the common machinery of a two- to
eight-player deterministic rollback game above `GameNet.Session` and
`GameNet.Rollback`.

It provides:

- configurable local input delay and prediction lead;
- redundant frame-numbered input batches;
- bounded prediction, restoration, and re-simulation;
- rollback-safe presentation effects released only after confirmation;
- confirmed-state hash exchange, desync detection, and bounded authoritative
  state resynchronisation;
- explicit fatal failure reasons; and
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

For sessions with more than two players, identify the source player when
calling `ReceiveHash(player, packet)`. `WriteInputs` and `WriteReadyHash`
produce one local packet which may be broadcast to every other player;
`SendInputs` sends an input packet to one chosen peer. `SendReadyHash` is a
two-player convenience because a ready hash is consumed once it is written;
larger sessions should write it once and broadcast the same bytes.
`HasRemoteFrame(player)` and `RemoteSimulationFrame(player)` expose individual
progress, while their no-argument forms report whether all remote players have
reported and return the slowest reported frame.

The supported range is deliberately capped at eight. Memory is allocated only
for the configured count, but simulation/replay cost grows with player count
and a full peer mesh also increases message fan-out. Larger games should
normally use an authoritative server and snapshots rather than one shared
rollback timeline.

## Step status and stalls

`CanStep` remains the simple readiness check. `StepStatus` distinguishes a
ready session from one which is stopped, fatally failed, or waiting because it
has consumed its prediction allowance. `StepInfo` returns the same status plus
the current and confirmed frames, prediction lead, earliest unconfirmed input
frame, and a player bitmask identifying whose input is not yet confirmed.

`SRollbackStepInfo` is a value Struct and gathering it has no side effects or
managed allocation. It also reports pending state synchronisation separately:
recovery is important match-health information, but it does not block stepping
while prediction budget remains. These details allow a game to distinguish a
normal short network stall from a stopped match or simulation fault and show
useful diagnostics without reproducing rollback-buffer logic.

`GetConfirmedInput` exposes one player's borrowed confirmed input for a frame.
It can be used to feed `GameNet.Replay` after advancing a separate recording
cursor through newly confirmed frames.

## Desync recovery

`authorityPlayer` in `SRollbackSessionConfig` selects the peer whose state wins
if confirmed hashes disagree. It defaults to player zero. A non-authority peer
then reports `NeedsStateSync`; it can send `WriteStateSyncRequest` or
`SendStateSyncRequest`. The authority answers with `WriteStateSyncResponse` or
`SendStateSyncResponse`, and the requester routes the reply to
`ReceiveStateSync`. Responses echo the mismatch frame so a delayed response to
an older request cannot replace a newer recovery attempt.

The response contains one confirmed opaque game-state snapshot. The receiver
validates its hash, restores it, and replays retained inputs to its current
frame without restarting the match. The authority never selects a state newer
than the confirmed boundary reported by either peer. Request and response
messages must use a reliable ordered channel. The response occupies
`StateSyncPacketCapacity` bytes at most (`maxStateSize + 17`), so both the
caller's packet buffer and the underlying session payload limit must be at
least that large. This initial facility intentionally does not fragment large
states.

The authority is a convergence policy, not a cheat-prevention mechanism: if
its state is wrong, that state still wins. Nor can recovery retract an
irreversible presentation effect the application has already consumed. Games
should continue to keep deterministic state compact and use confirmed effects
for presentation work.

`RequestStateSync` lets a non-authority peer enter the same recovery path
explicitly after returning from application suspension, without waiting for a
confirmed hash mismatch. An authority cannot use this path to replace its own
state; it may continue only if the match was paused for everyone, otherwise it
should reconnect or leave.

`Failed` now has a corresponding `FailureReason`. Invalid network packets are
simply rejected; a failure reason is set only when the local deterministic
simulation can no longer safely continue.
