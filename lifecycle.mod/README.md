# GameNet.Lifecycle

`GameNet.Lifecycle` turns application foreground/background notifications into
explicit, bounded events and a time-based recovery recommendation. It remains
independent of SDL, Apple, Android, and the selected network transport.

The default policy recommends:

- continuing after a very short interruption;
- resynchronising after 250 milliseconds;
- reconnecting after thirty seconds; and
- leaving the match after two minutes.

All thresholds are configurable. A lost connection always escalates a
continue or resynchronise result to reconnect.

Call `TNetSession.SuspendAt` with the same monotonic time when the application
enters the background. This stops session polling and sending and freezes its
health deadlines. On return, call `TNetSession.ResumeAt`, process any queued
transport disconnect, then call `TAppLifecycle.ResumeAt` with the resulting
connection state.

If a match is running, request its shared pause immediately before suspending
the session where the platform permits it. Do not clear that pause on return
until the selected recovery action has completed.

For a resynchronise result, authoritative clients should call
`TAuthoritativeClientSession.BeginRecovery`; rollback non-authority peers should
call `TRollbackSession.RequestStateSync`. A rollback authority can only safely
continue if the match was paused for all players; otherwise it should reconnect
or leave because the authority-based recovery protocol cannot replace its state
from a non-authority peer.

With `SDL3.SDL3System`, feed `SDL_EVENT_WILL_ENTER_BACKGROUND` to `SuspendAt`,
`SDL_EVENT_DID_ENTER_FOREGROUND` to `ResumeAt`, and `SDL_EVENT_TERMINATING` to
`Terminate` from `SetLifecycleCallback`.
