SuperStrict

Framework Max2D.SDL3RenderMax2D
Import GameNet.SteamOnline
Import GameNet.OnlineFlow
Import GameNet.Session
Import BRL.PolledInput

Const APP_ID:UInt = $53544541 ' STEA
Const APP_VERSION:UInt = 1

Global steamOnline:TSteamOnlineService = TSteamOnlineService.Create(2, 900, ESteamOnlineTransportKind.NetworkingSockets)
Global online:IOnlineService = steamOnline
Global onlineFlow:TOnlineFlowCoordinator
Global statusText:String = "Starting Steam..."
Global detailText:String = ""
Global transport:INetTransport
Global session:TNetSession
Global peers:SNetPeer[8]
Global joinedCount:Int
Global hostRole:Int
Global sentCount:UInt
Global receivedCount:UInt

Function BeginSession()
	Local launch:TOnlineMatchLaunch = onlineFlow.TakeMatch()
	If Not launch Or Not launch.IsValid() Then
		statusText = "Could not take Steam transport"
		Return
	End If
	Local info:SOnlineMatchInfo = launch.Info()
	transport = launch.Transport()
	hostRole = info.IsSessionHost()
	If hostRole Then
		session = TNetSession.CreateHost(transport, APP_ID, APP_VERSION, info.PlayerCount() - 1, 900)
		statusText = "Steam match connected; hosting"
	Else
		session = TNetSession.CreateClient(transport, APP_ID, APP_VERSION, Null, 0, 1, 900)
		statusText = "Steam match connected; joining host"
	End If
	detailText = "Online players: " + info.PlayerCount()
End Function

Function PollOnline()
	onlineFlow.Pump()
	Local event:SOnlineFlowEvent
	While onlineFlow.Poll(event)
		Select event.Kind()
			Case EOnlineFlowEventKind.Ready
				statusText = "Steam is ready"
				detailText = "Host directly or use Quick Play on both computers"
			Case EOnlineFlowEventKind.Searching
				statusText = "Looking for a compatible Steam lobby"
			Case EOnlineFlowEventKind.Creating
				statusText = "Creating a Steam lobby"
			Case EOnlineFlowEventKind.Joining
				statusText = "Joining a Steam lobby"
			Case EOnlineFlowEventKind.WaitingForPlayers
				statusText = "Waiting in the Steam lobby"
				detailText = "Lobby players: " + event.PlayerCount() + "/2"
			Case EOnlineFlowEventKind.StartingMatch
				statusText = "Starting the match"
			Case EOnlineFlowEventKind.NoMatchFound
				statusText = "No matching lobby found"
			Case EOnlineFlowEventKind.MatchReady
				BeginSession()
			Case EOnlineFlowEventKind.InvitationReceived
				statusText = "Lobby invitation from " + event.Player().DisplayName()
				detailText = "Invitation lobby: " + event.SubjectId()
			Case EOnlineFlowEventKind.Failed
				statusText = "Online operation failed: " + Int(event.Error())
				detailText = event.Detail()
		End Select
	Wend
End Function

Function NewSteamFlowRequest:TOnlineFlowRequest(startPolicy:EOnlineFlowStartPolicy)
	Local request:TOnlineFlowRequest = New TOnlineFlowRequest
	request.lobbyOptions.name = "GameNet test lobby"
	request.lobbyOptions.minPlayers = 2
	request.lobbyOptions.maxPlayers = 2
	request.lobbyOptions.visibility = EOnlineLobbyVisibility.Public
	request.lobbyOptions.properties.Set("example", "gamenet-steam-session")
	request.lobbyQuery.maximumResults = 10
	request.lobbyQuery.properties.Set("example", "gamenet-steam-session")
	request.startPolicy = startPolicy
	Return request
End Function

Function PollSession()
	If Not session Then Return
	Local event:SSessionEvent
	While session.Poll(event)
		Select event.Kind()
			Case ESessionEventKind.JoinRequested
				session.Accept(event.Peer())
			Case ESessionEventKind.Joined
				Local index:Int = Int(event.Peer().Id()) - 1
				If index >= 0 And index < peers.Length And Not peers[index].IsValid() Then
					peers[index] = event.Peer()
					joinedCount :+ 1
				End If
				statusText = "GameNet session ready"
				detailText = "Press Send Packet"
			Case ESessionEventKind.Message
				If event.MessageType() = 1 And event.Payload().Length() = 4 Then
					Local reader:SPacketReader = New SPacketReader(event.Payload().Data(), event.Payload().Length())
					reader.ReadUInt32(receivedCount)
					detailText = "Received packet " + receivedCount
				End If
			Case ESessionEventKind.Left
				statusText = "Steam peer left"
			Case ESessionEventKind.Error
				statusText = "Session error: " + event.Code()
		End Select
	Wend
End Function

Function SendPacket()
	sentCount :+ 1
	Local bytes:Byte[4]
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(bytes), 4)
	writer.WriteUInt32(sentCount)
	For Local peer:SNetPeer = EachIn peers
		If peer.IsValid() Then session.Send(peer, 1, 1, EDeliveryMode.ReliableOrdered, Byte Ptr(bytes), 4)
	Next
	detailText = "Sent packet " + sentCount
End Function

Function Button:Int(x:Float, y:Float, width:Float, label:String)
	Local over:Int = VirtualMouseX() >= x And VirtualMouseX() < x + width And VirtualMouseY() >= y And VirtualMouseY() < y + 56
	SetColor 45 + 25 * over, 100 + 20 * over, 170 + 20 * over
	DrawRect x, y, width, 56
	SetColor 255, 255, 255
	DrawText label, x + 18, y + 18
	Return over And MouseHit(1)
End Function

Graphics 900, 500
SetClsColor 12, 16, 24
onlineFlow = TOnlineFlowCoordinator.Create(online)
If Not onlineFlow Or Not onlineFlow.Open() Then
	Throw "Could not open Steam online service"
End If

While Not AppTerminate()
	PollOnline()
	PollSession()
	Cls
	SetColor 235, 240, 250
	DrawText "GameNet Steam lobby and session test", 28, 30
	DrawText statusText, 28, 90
	DrawText detailText, 28, 125

	If Button(28, 210, 250, "Host Lobby") And onlineFlow.State() = EOnlineFlowState.Ready Then
		onlineFlow.Host(NewSteamFlowRequest(EOnlineFlowStartPolicy.Manual))
	End If

	If Button(310, 210, 250, "Quick Play") And onlineFlow.State() = EOnlineFlowState.Ready Then
		onlineFlow.QuickPlay(NewSteamFlowRequest(EOnlineFlowStartPolicy.WhenMinimumPlayers))
	End If

	Local action:String = "Start Match"
	If joinedCount Then action = "Send Packet"
	If Button(592, 210, 250, action) Then
		If joinedCount Then
			SendPacket()
		Else If onlineFlow.State() = EOnlineFlowState.WaitingForPlayers Then
			If onlineFlow.StartMatch() Then
				detailText = "Waiting for the lobby owner to start"
			End If
		End If
	End If

	If online.CurrentLobby() And Not joinedCount And Button(28, 290, 250, "Invite Friends") Then
		steamOnline.ShowInviteDialog()
	End If

	SetColor 170, 180, 195
	DrawText "Steam must be running. Use different Steam accounts on the two computers.", 28, 450
	Flip
Wend

If session Then session.Close()
If onlineFlow Then onlineFlow.Close()
