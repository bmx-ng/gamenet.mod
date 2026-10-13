SuperStrict

Framework Max2D.SDL3RenderMax2D
Import GameNet.SteamOnline
Import GameNet.Session
Import BRL.PolledInput

Const APP_ID:UInt = $53544541 ' STEA
Const APP_VERSION:UInt = 1

Global steamOnline:TSteamOnlineService = TSteamOnlineService.Create(2, 900, ESteamOnlineTransportKind.NetworkingSockets)
Global online:IOnlineService = steamOnline
Global statusText:String = "Starting Steam..."
Global detailText:String = ""
Global transport:INetTransport
Global session:TNetSession
Global peers:SNetPeer[8]
Global joinedCount:Int
Global hostRole:Int
Global findRequest:UInt
Global startRequest:UInt
Global sentCount:UInt
Global receivedCount:UInt

Function BeginSession(requestId:UInt)
	Local info:SOnlineMatchInfo
	If Not online.MatchInfo(requestId, info) Then statusText = "Match information unavailable"; Return
	transport = online.TakeMatchTransport(requestId)
	If Not transport Then statusText = "Could not take Steam transport"; Return
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
	online.Pump()
	Local event:SOnlineEvent
	While online.Poll(event)
		Select event.Kind()
			Case EOnlineEventKind.ServiceReady
				statusText = "Steam: " + event.Player().DisplayName()
				detailText = "Create a lobby on one computer; find it on the other"
			Case EOnlineEventKind.LobbyCreated
				statusText = "Lobby created"
				detailText = "Lobby " + event.SubjectId() + "; waiting for another player"
			Case EOnlineEventKind.LobbySearchCompleted
				findRequest = 0
				If online.LobbyResultCount(event.RequestId()) Then
					Local lobby:IOnlineLobby = online.LobbyResult(event.RequestId(), 0)
					online.JoinLobby(lobby.Id())
					statusText = "Joining " + lobby.Name()
				Else
					statusText = "No matching lobby found"
				End If
			Case EOnlineEventKind.LobbyJoined
				statusText = "Lobby joined"
				detailText = "Both players should press Start Match"
			Case EOnlineEventKind.LobbyChanged
				Local lobby:IOnlineLobby = online.CurrentLobby()
				If lobby Then detailText = "Lobby players: " + lobby.MemberCount() + "/" + lobby.MaxPlayers()
			Case EOnlineEventKind.MatchReady
				BeginSession(event.RequestId())
			Case EOnlineEventKind.InvitationReceived
				statusText = "Lobby invitation from " + event.Player().DisplayName()
				detailText = "Invitation lobby: " + event.SubjectId()
			Case EOnlineEventKind.OperationFailed
				statusText = "Online operation failed: " + Int(event.Error())
				detailText = event.Detail()
		End Select
	Wend
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
				If index >= 0 And index < peers.Length And Not peers[index].IsValid() Then peers[index] = event.Peer(); joinedCount :+ 1
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
If Not online Or online.Open() = 0 Then Throw "Could not open Steam online service"

While Not AppTerminate()
	PollOnline()
	PollSession()
	Cls
	SetColor 235, 240, 250
	DrawText "GameNet Steam lobby and session test", 28, 30
	DrawText statusText, 28, 90
	DrawText detailText, 28, 125

	If Button(28, 210, 250, "Create Lobby") And Not online.CurrentLobby() Then
		Local options:TOnlineLobbyOptions = New TOnlineLobbyOptions
		options.name = "GameNet test lobby"
		options.maxPlayers = 2
		options.visibility = EOnlineLobbyVisibility.Public
		options.properties.Set("example", "gamenet-steam-session")
		online.CreateLobby(options)
	End If

	If Button(310, 210, 250, "Find Lobby") And Not online.CurrentLobby() And findRequest = 0 Then
		Local query:TOnlineLobbyQuery = New TOnlineLobbyQuery
		query.maximumResults = 10
		query.properties.Set("example", "gamenet-steam-session")
		findRequest = online.FindLobbies(query)
	End If

	Local action:String = "Start Match"
	If joinedCount Then action = "Send Packet"
	If Button(592, 210, 250, action) Then
		If joinedCount Then
			SendPacket()
		Else If online.CurrentLobby() And startRequest = 0 Then
			startRequest = online.StartMatch()
			If startRequest Then detailText = "Waiting for lobby owner to start"
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
If online Then online.Close()
