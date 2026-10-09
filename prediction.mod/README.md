# GameNet.Prediction

`GameNet.Prediction` supplies transport-independent input bookkeeping for a
server-authoritative prediction model. It does not understand or simulate game
state.

`TPredictionHistory` retains a bounded window of opaque, sequenced client input
commands until the authority acknowledges them. A client can restore an
authoritative snapshot and replay every retained command in order. The same
history can be included in outgoing unreliable packets so later packets recover
earlier packet loss.

`SPredictionSequencer` lets an authority process each command exactly once and
in sequence order. Duplicate commands are harmless, while a gap remains
unacknowledged so a later redundant packet can fill it.

All command storage is allocated when a history is created. Adding,
acknowledging, and iterating commands perform no managed allocation.
