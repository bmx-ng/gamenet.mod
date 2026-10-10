SuperStrict

Framework BRL.StandardIO
Import GameNet.Match
Import GameNet.Loopback

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Const APP_ID:UInt = $4d415443 ' MATC
Const APP_VERSION:UInt = 1
Const COMMAND_MESSAGE:UInt = 40
Const STATE_MESSAGE:UInt = 41

Function RouteMessages(session:TNetSession, lifecycle:TMatchLifecycle, nowMillis:UInt)
	Local event:SSessionEvent
	While session.PollAt(event, nowMillis)
		If event.Kind() = ESessionEventKind.Message Then Check(lifecycle.ReceiveAt(event.Peer(), event.MessageType(), event.Payload(), nowMillis), "route lifecycle message")
	Wend
End Function

Local pair:TLoopbackPair = TLoopbackPair.Create(64, 1200)
Local hostSession:TNetSession = TNetSession.CreateHost(pair.First(), APP_ID, APP_VERSION, 1, 1200)
Local clientSession:TNetSession = TNetSession.CreateClient(pair.Second(), APP_ID, APP_VERSION, Null, 0, 1, 1200)
Check(hostSession <> Null And clientSession <> Null, "create sessions")

Local sessionEvent:SSessionEvent
clientSession.PollAt(sessionEvent, 0)
Check(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.JoinRequested, "host join request")
Local hostPeer:SNetPeer = sessionEvent.Peer()
Check(hostSession.Accept(hostPeer) = ETransportResult.Ok, "accept client")
Check(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "host joined")
Check(clientSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "client joined")
Local clientPeer:SNetPeer = sessionEvent.Peer()

Local host:TMatchLifecycle = TMatchLifecycle.Create(hostSession, New SMatchLifecycleConfig(2, 0, 0, COMMAND_MESSAGE, STATE_MESSAGE, 0, 32))
Local client:TMatchLifecycle = TMatchLifecycle.Create(clientSession, New SMatchLifecycleConfig(2, 1, 0, COMMAND_MESSAGE, STATE_MESSAGE, 0, 32))
Check(host <> Null And client <> Null, "create lifecycles")
Local maximumLifecycle:TMatchLifecycle = TMatchLifecycle.Create(hostSession, New SMatchLifecycleConfig(MATCH_MAX_PLAYERS, 0, 0, COMMAND_MESSAGE, STATE_MESSAGE, 0, MATCH_MAX_PLAYERS * 2 + 4))
Check(maximumLifecycle <> Null, "support sixteen-player match lifecycle")
Check(TMatchLifecycle.Create(hostSession, New SMatchLifecycleConfig(MATCH_MAX_PLAYERS + 1, 0, 0, COMMAND_MESSAGE, STATE_MESSAGE, 0, 64)) = Null, "reject match lifecycle above sixteen players")
Check(client.BindPlayer(0, clientPeer), "bind client authority")
Check(host.PlayerJoined(1, hostPeer, 0) = ETransportResult.Ok, "host joins player")
RouteMessages(clientSession, client, 0)
Check(host.AllConnected() And client.AllConnected(), "synchronise roster")

Check(client.SetLocalReady(True, 10) = ETransportResult.Ok, "client requests ready")
RouteMessages(hostSession, host, 10)
RouteMessages(clientSession, client, 10)
Check(host.PlayerReady(1) And client.PlayerReady(1), "client ready replicated")
Check(host.SetLocalReady(True, 20) = ETransportResult.Ok, "host ready")
RouteMessages(clientSession, client, 20)
Check(host.AllReady() And client.AllReady(), "all ready replicated")

Check(host.BeginMatch($12345678:UInt, 120, 500, 100) = ETransportResult.Ok, "begin countdown")
RouteMessages(clientSession, client, 120)
Check(host.Phase() = EMatchPhase.Countdown And client.Phase() = EMatchPhase.Countdown, "countdown replicated")
Check(host.Seed() = $12345678:UInt And client.Seed() = host.Seed(), "seed replicated")
Check(client.StartFrame() = 120 And client.Round() = 1, "start frame and round replicated")
Check(client.CountdownRemaining(120) = 500, "client countdown starts on receipt")

Check(host.UpdateAt(600) = ETransportResult.Ok, "authority starts match")
Check(client.UpdateAt(620) = ETransportResult.Ok, "client reaches local start")
RouteMessages(clientSession, client, 620)
Check(host.Phase() = EMatchPhase.Running And client.Phase() = EMatchPhase.Running, "running replicated")

Check(client.SetLocalPaused(True, 700) = ETransportResult.Ok, "client requests pause")
RouteMessages(hostSession, host, 700)
RouteMessages(clientSession, client, 700)
Check(host.Phase() = EMatchPhase.Paused And client.Phase() = EMatchPhase.Paused And client.PlayerPaused(1), "pause replicated")
Check(client.SetLocalPaused(False, 800) = ETransportResult.Ok, "client requests resume")
RouteMessages(hostSession, host, 800)
RouteMessages(clientSession, client, 800)
Check(host.Phase() = EMatchPhase.Running And client.Phase() = EMatchPhase.Running, "resume replicated")

Check(host.Finish(1, 77, 900) = ETransportResult.Ok, "finish match")
RouteMessages(clientSession, client, 900)
Check(client.Phase() = EMatchPhase.Finished And client.Winner() = 1 And client.FinishCode() = 77, "result replicated")

Check(host.SetLocalReady(True, 910) = ETransportResult.Ok, "host rematch ready")
RouteMessages(clientSession, client, 910)
Check(client.SetLocalReady(True, 920) = ETransportResult.Ok, "client rematch ready")
RouteMessages(hostSession, host, 920)
RouteMessages(clientSession, client, 920)
Check(host.AllReady() And client.AllReady(), "rematch ready replicated")
Check(host.BeginMatch(99, 0, 0, 930) = ETransportResult.Ok, "begin immediate rematch")
RouteMessages(clientSession, client, 930)
Check(client.Phase() = EMatchPhase.Running And client.Round() = 2 And client.Seed() = 99, "rematch replicated")

Local malformed:Byte[1]
Check(Not host.ReceiveAt(hostPeer, COMMAND_MESSAGE, New SPacketView(Byte Ptr(malformed), 1), 1000), "reject malformed command")
Check(host.RejectedPackets() = 1, "count malformed command")

Check(host.PlayerLeft(1, 12, 1100) = ETransportResult.Ok, "leave aborts host match")
Check(host.Phase() = EMatchPhase.Aborted, "host match aborted")

Local lifecycleEvent:SMatchEvent
Local sawStarted:Int, sawPaused:Int, sawPlayerPause:Int, sawFinished:Int, sawAborted:Int
While host.Poll(lifecycleEvent)
	Select lifecycleEvent.Kind()
		Case EMatchEventKind.Started
			sawStarted = True
		Case EMatchEventKind.Paused
			sawPaused = True
		Case EMatchEventKind.PlayerPauseChanged
			sawPlayerPause = True
		Case EMatchEventKind.Finished
			sawFinished = True
		Case EMatchEventKind.Aborted
			sawAborted = True
	End Select
Wend
Check(sawStarted And sawPaused And sawPlayerPause And sawFinished And sawAborted, "queue lifecycle transitions")
Check(host.DroppedEvents() = 0 And client.DroppedEvents() = 0, "event queues remain bounded")

hostSession.Close()
clientSession.Close()
Print "GameNet.Match tests passed"
