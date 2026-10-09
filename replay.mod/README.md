# GameNet.Replay

`GameNet.Replay` stores a bounded deterministic recording independently of any
transport or renderer. A tape contains an opaque initial game state followed by
sequential frames of opaque input for every player. Frames may also carry an
optional state hash for deterministic verification during playback.

`TReplayTape` allocates all state, input, and index storage when it is created.
Appending frames, reading them through `SReplayFrame` or `SReplayCursor`, and
serialising into caller-owned memory do not inherently allocate managed
objects. When its configured frame capacity is full, appending fails rather
than silently losing the beginning of the recording.

The portable encoding uses network byte order and includes a magic value,
format version, player count, initial frame, initial state, and frame count.
`Read` validates the entire packet—including sequential frame numbers and all
length bounds—and verifies a checksum before replacing an existing tape. File
storage, compression, metadata, and upload policy remain application concerns.

Record only confirmed inputs when capturing a rollback match. Predicted inputs
may later be replaced and therefore cannot reproduce the final deterministic
timeline. `TRollbackSession.GetConfirmedInput` exposes a borrowed confirmed
input for this purpose. The application should retain its next recording frame,
append each frame once every player's input is available, and stop or rotate to
a new tape when capacity is reached. Drain confirmed frames regularly: the
rollback session's history is also bounded, so very old confirmed inputs are
eventually overwritten.

Playback restores the tape's `InitialState`, then iterates `SReplayCursor`.
Each `SReplayFrame` returns the borrowed input for a requested player. These
views can be wrapped in public `SRollbackInput` values and passed to the same
deterministic simulation used by `GameNet.RollbackSession`. If a frame has a
state hash, the application can hash its resulting state and stop at the first
divergent frame.
