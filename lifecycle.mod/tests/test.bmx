SuperStrict

Framework BRL.StandardIO
Import GameNet.Lifecycle

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Check(TAppLifecycle.Create(New SAppLifecycleConfig(20, 10, 30)) = Null, "reject unordered thresholds")

Local lifecycle:TAppLifecycle = TAppLifecycle.Create(New SAppLifecycleConfig(100, 500, 1000, 16))
Check(lifecycle <> Null, "create lifecycle")
Local event:SAppLifecycleEvent
Check(lifecycle.SuspendAt(1000) And lifecycle.IsSuspended(), "suspend")
Check(Not lifecycle.SuspendAt(1010), "ignore duplicate suspend")
Check(lifecycle.Poll(event) And event.Kind() = EAppLifecycleEventKind.Suspended, "poll suspension")
Check(lifecycle.ResumeAt(1050) = EAppResumeAction.Continue, "continue after short suspension")
Check(lifecycle.Poll(event) And event.Kind() = EAppLifecycleEventKind.Resumed And event.SuspendedMillis() = 50, "poll short resume")

Check(lifecycle.SuspendAt(2000), "suspend for state recovery")
Check(lifecycle.ResumeAt(2150) = EAppResumeAction.Resynchronise, "resynchronise after medium suspension")
Check(lifecycle.SuspendAt(3000), "suspend for reconnect")
Check(lifecycle.ResumeAt(3600) = EAppResumeAction.Reconnect, "reconnect after long suspension")
Check(lifecycle.SuspendAt(4000), "suspend with lost connection")
Check(lifecycle.ResumeAt(4050, False) = EAppResumeAction.Reconnect, "lost connection forces reconnect")
Check(lifecycle.SuspendAt(5000), "suspend for leave")
Check(lifecycle.ResumeAt(6000) = EAppResumeAction.Leave, "leave after maximum suspension")

lifecycle.Terminate()
Local sawTerminate:Int
While lifecycle.Poll(event)
	If event.Kind() = EAppLifecycleEventKind.Terminating And event.Action() = EAppResumeAction.Leave Then sawTerminate = True
Wend
Check(sawTerminate, "queue termination")

Print "GameNet.Lifecycle tests passed"
