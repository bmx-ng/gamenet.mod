# GameNet.Snapshot

`GameNet.Snapshot` is an optional presentation layer for games which receive
periodic authoritative state. It does not send packets and does not understand
the contents of game state.

`TSnapshotTimeline` stores a bounded history of opaque state bytes. Sampling
returns borrowed views of the two surrounding states and a blend factor; the
game decodes and interpolates its own fields. Sampling before or after the
stored range clamps to an endpoint and never extrapolates.

`TSnapshotClock` estimates the current server tick between snapshot arrivals.
`TSnapshotDelay` optionally expands a render delay when packets arrive late and
slowly recovers toward a configured base delay.

All per-frame operations reuse storage allocated at creation. Separate
timelines should normally be used for independently sampled entities.
