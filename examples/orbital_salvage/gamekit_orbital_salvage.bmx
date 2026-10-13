SuperStrict

Framework Max2D.SDL3RenderMax2D
Import GameNet.GameKitOnline
Import GameNet.Online
Import GameNet.Replication
Import GameNet.AuthoritativeSession
Import Max2D.VirtualJoystick
Import BRL.PolledInput
Import BRL.StandardIO

Global online:IOnlineService
Global matchmakingRequest:UInt

Function BeginGameKitSession(requestId:UInt)
	Local info:SOnlineMatchInfo
	If Not online.MatchInfo(requestId, info) Then
		statusText = "Match information unavailable"
		Return
	End If
	transport = online.TakeMatchTransport(requestId)
	If Not transport Then
		statusText = "Could not take Game Center transport"
		Return
	End If
	isAuthority = info.IsSessionHost()
	localPlayer = 1
	If isAuthority Then
		localPlayer = 0
		session = TNetSession.CreateHost(transport, SALVAGE_APP_ID, SALVAGE_APP_VERSION, 1, 900)
		statusText = "Match connected; preparing salvage field"
	Else
		session = TNetSession.CreateClient(transport, SALVAGE_APP_ID, SALVAGE_APP_VERSION, Null, 0, 1, 900)
		statusText = "Match connected; joining authority"
	End If
	If Not session Or Not CreateReplicationWorld() Then
		statusText = "Could not create replicated game world"
		If session Then session.Close()
		session = Null
	End If
	matchmakingRequest = 0
End Function

Function InitializeSalvageConnection:Int()
	online = TGameKitOnlineService.Create(1, 2, 900)
	If Not online Or online.Open() = 0 Then Return False
	statusText = "Starting Game Center..."
	Return True
End Function

Function PollSalvageConnection(now:Int)
	If Not online Then Return
	online.Pump()
	Local event:SOnlineEvent
	While online.Poll(event)
		Select event.Kind()
			Case EOnlineEventKind.ServiceReady
				statusText = "Authenticated as " + event.Player().DisplayName()
				detailText = "Find a friend and recover five energy cores"
			Case EOnlineEventKind.MatchmakingStarted
				statusText = "Looking for another salvage pilot..."
				detailText = "Start Orbital Salvage on the other device"
			Case EOnlineEventKind.MatchReady
				BeginGameKitSession(event.RequestId())
			Case EOnlineEventKind.MatchmakingCancelled
				matchmakingRequest = 0
				statusText = "Matchmaking cancelled"
			Case EOnlineEventKind.OperationFailed
				If event.Operation() = EOnlineOperation.StartMatchmaking Then matchmakingRequest = 0
				statusText = "Game Center operation failed: " + Int(event.Error())
				detailText = event.Detail()
		End Select
	Wend
End Function

Function HandleSalvageConnectionInput()
	If session Then Return
	Local pressed:Int = MouseHit(1) And VirtualMouseX() >= 250 And VirtualMouseX() < 550 And VirtualMouseY() >= 185 And VirtualMouseY() < 253
	If KeyHit(KEY_ENTER) Then pressed = True
	If pressed And online.State() = EOnlineServiceState.Ready And matchmakingRequest = 0 Then
		Local request:TOnlineMatchmakingRequest = New TOnlineMatchmakingRequest
		request.minPlayers = 2
		request.maxPlayers = 2
		matchmakingRequest = online.StartMatchmaking(request)
		If matchmakingRequest = 0 Then statusText = "Could not start matchmaking"
	End If
End Function

Function DrawSalvageConnection()
	SetColor 31, 105, 170
	DrawRect 250, 185, 300, 68
	SetColor 255, 255, 255
	DrawText "FIND SALVAGE MATCH", 317, 210
End Function

Function CloseSalvageConnection()
	If online Then online.Close()
End Function

Include "orbital_salvage_game.bmx"
