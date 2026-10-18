SuperStrict

Framework Max2D.SDL3RenderMax2D
Import GameNet.GameKitOnline
Import GameNet.OnlineFlow
Import GameNet.Session
Import BRL.PolledInput
Import BRL.StandardIO

Const APP_ID:UInt = $474b5445 ' GKTE
Const APP_VERSION:UInt = 1
Const MATCH_MIN_PLAYERS:Int = 2
Const MATCH_MAX_PLAYERS:Int = 2 ' Raise both values together to test a larger fixed roster.

Global statusText:String = "Starting online service..."
Global detailText:String = ""
Global online:IOnlineService = TGameKitOnlineService.Create(GAMEKIT_MAX_REMOTE_PEERS, 2, 900)
Global onlineFlow:TOnlineFlowCoordinator
Global transport:INetTransport
Global session:TNetSession
Global remotePeers:SNetPeer[GAMEKIT_MAX_REMOTE_PEERS]
Global joinedCount:Int
Global hostRole:Int
Global sentCount:UInt
Global receivedCount:UInt

Function BeginSession()
	Local launch:TOnlineMatchLaunch = onlineFlow.TakeMatch()
	If Not launch Or Not launch.IsValid() Then
		statusText = "Could not take online match transport"
		Return
	End If
	Local info:SOnlineMatchInfo = launch.Info()
	transport = launch.Transport()
	hostRole = info.IsSessionHost()
	If hostRole Then
		session = TNetSession.CreateHost(transport, APP_ID, APP_VERSION, info.PlayerCount() - 1, 900)
		statusText = "Match connected; hosting " + info.PlayerCount() + " players"
	Else
		session = TNetSession.CreateClient(transport, APP_ID, APP_VERSION, Null, 0, 1, 900)
		statusText = "Match connected; joining session host"
	End If
	detailText = "Online players: " + info.PlayerCount()
End Function

Function PollOnline()
	If Not onlineFlow Then
		Return
	End If
	onlineFlow.Pump()
	Local event:SOnlineFlowEvent
	While onlineFlow.Poll(event)
		Select event.Kind()
			Case EOnlineFlowEventKind.Ready
				statusText = "Game Center is ready"
				detailText = "Tap Find Match on both devices"
			Case EOnlineFlowEventKind.Matchmaking
				statusText = "Looking for " + MATCH_MIN_PLAYERS + "-" + MATCH_MAX_PLAYERS + " players..."
				detailText = "Game Center matchmaking is active"
			Case EOnlineFlowEventKind.WaitingForPlayers
				statusText = "Waiting for players"
				detailText = "Online players: " + event.PlayerCount()
			Case EOnlineFlowEventKind.MatchReady
				BeginSession()
			Case EOnlineFlowEventKind.Cancelled
				statusText = "Matchmaking cancelled"
			Case EOnlineFlowEventKind.Failed
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
				If session.Accept(event.Peer()) <> ETransportResult.Ok Then statusText = "Could not accept session peer"
			Case ESessionEventKind.Joined
				Local peerIndex:Int = Int(event.Peer().Id()) - 1
				If peerIndex >= 0 And peerIndex < remotePeers.Length And Not remotePeers[peerIndex].IsValid() Then
					remotePeers[peerIndex] = event.Peer()
					joinedCount :+ 1
				End If
				statusText = "GameNet session joined " + joinedCount + " peer(s)"
				detailText = "Tap Send Packet to exchange a reliable message"
			Case ESessionEventKind.Message
				If event.MessageType() = 1 And event.Payload().Length() = 4 Then
					Local reader:SPacketReader = New SPacketReader(event.Payload().Data(), event.Payload().Length())
					reader.ReadUInt32(receivedCount)
					detailText = "Received packet " + receivedCount
				End If
			Case ESessionEventKind.Left
				Local peerIndex:Int = Int(event.Peer().Id()) - 1
				If peerIndex >= 0 And peerIndex < remotePeers.Length And remotePeers[peerIndex].IsValid() Then
					remotePeers[peerIndex] = New SNetPeer
					joinedCount = Max(0, joinedCount - 1)
				End If
				statusText = "A player left; " + joinedCount + " peer(s) remain"
			Case ESessionEventKind.Rejected
				statusText = "Session rejected: " + event.Code()
			Case ESessionEventKind.Error
				statusText = "Session error: " + event.Code()
		End Select
	Wend
End Function

Function SendPacket()
	If Not session Or joinedCount = 0 Then Return
	sentCount :+ 1
	Local data:Byte[4]
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(data), Size_T(data.Length))
	writer.WriteUInt32(sentCount)
	Local sent:Int
	For Local peer:SNetPeer = EachIn remotePeers
		If peer.IsValid() Then
			Local result:ETransportResult = session.Send(peer, 1, 1, EDeliveryMode.ReliableOrdered, Byte Ptr(data), Size_T(data.Length))
			If result = ETransportResult.Ok Then sent :+ 1 Else statusText = "Send failed: " + Int(result)
		End If
	Next
	If sent Then detailText = "Sent packet " + sentCount + " to " + sent + " peer(s)"
End Function

Graphics 800, 480
SetClsColor 12, 16, 24
SetColor 235, 240, 250
If Not online Then Throw "GameKit online service unavailable"
onlineFlow = TOnlineFlowCoordinator.Create(online)
If Not onlineFlow Or Not onlineFlow.Open() Then
	Throw "Could not open GameKit online service"
End If

While Not AppTerminate()
	PollOnline()
	PollSession()

	Local buttonX:Float = 250
	Local buttonY:Float = 260
	Local buttonWidth:Float = 300
	Local buttonHeight:Float = 70
	Local actionText:String = "Find Match"
	If joinedCount > 0 Then actionText = "Send Packet"
	Local pointerX:Float = VirtualMouseX()
	Local pointerY:Float = VirtualMouseY()
	Local pressed:Int = MouseHit(1) And pointerX >= buttonX And pointerX < buttonX + buttonWidth And pointerY >= buttonY And pointerY < buttonY + buttonHeight
	If KeyHit(KEY_SPACE) Then pressed = True
	If pressed Then
		If joinedCount > 0 Then
			SendPacket()
		Else If onlineFlow.State() = EOnlineFlowState.Ready And Not session Then
			Local request:TOnlineFlowRequest = New TOnlineFlowRequest
			request.matchmakingRequest.minPlayers = MATCH_MIN_PLAYERS
			request.matchmakingRequest.maxPlayers = MATCH_MAX_PLAYERS
			If Not onlineFlow.QuickPlay(request) Then
				statusText = "Could not start matchmaking"
			End If
		End If
	End If

	Cls
	SetColor 235, 240, 250
	DrawText "GameNet.GameKit session test", 28, 30
	DrawText statusText, 28, 100
	DrawText detailText, 28, 140
	SetColor 50, 105, 185
	DrawRect buttonX, buttonY, buttonWidth, buttonHeight
	SetColor 255, 255, 255
	DrawText actionText, buttonX + 95, buttonY + 24
	DrawText "Space also activates the button", 28, 430
	Flip
Wend

If session Then session.Close()
If onlineFlow Then onlineFlow.Close()
