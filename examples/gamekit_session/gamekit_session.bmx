SuperStrict

Framework Max2D.SDL3RenderMax2D
Import Apple.GameKit
Import GameNet.GameKit
Import GameNet.Session
Import BRL.PolledInput
Import BRL.StandardIO

Const APP_ID:UInt = $474b5445 ' GKTE
Const APP_VERSION:UInt = 1
Const MATCH_MIN_PLAYERS:Int = 2
Const MATCH_MAX_PLAYERS:Int = 2 ' Raise both values together to test a larger fixed roster.

Global statusText:String = "Starting Game Center..."
Global detailText:String = ""
Global gameCenter:TGameCenter = TGameCenter.Shared()
Global pendingMatch:TGameCenterMatch
Global transport:TGameKitTransport
Global session:TNetSession
Global remotePeers:SNetPeer[GAMEKIT_MAX_REMOTE_PEERS]
Global joinedCount:Int
Global hostRole:Int
Global sentCount:UInt
Global receivedCount:UInt

Function ErrorText:String(error:TGameCenterError)
	If Not error Then Return ""
	Return error.domain + " (" + error.code + "): " + error.message
End Function

Type TListener Implements IGameCenterListener, IGameCenterMultiplayerListener
	Method OnGameCenterAuthenticationChanged(authenticated:Int, player:TGameCenterPlayer, error:TGameCenterError)
		If error Then
			statusText = "Authentication failed"
			detailText = ErrorText(error)
		Else If authenticated Then
			statusText = "Authenticated as " + player.displayName
			detailText = "Tap Find Match on both devices"
		Else
			statusText = "Game Center is not authenticated"
		End If
	End Method

	Method OnGameCenterMatchFound(requestId:Int, match:TGameCenterMatch, error:TGameCenterError)
		If error Then
			statusText = "Matchmaking failed"
			detailText = ErrorText(error)
		Else
			pendingMatch = match
			statusText = "Match found; waiting for the other player..."
			detailText = ""
		End If
	End Method

	Method OnGameCenterAchievementReported(requestId:Int, identifier:String, error:TGameCenterError)
	End Method

	Method OnGameCenterAchievementsLoaded(requestId:Int, result:TGameCenterAchievementResult, error:TGameCenterError)
	End Method

	Method OnGameCenterAchievementsReset(requestId:Int, error:TGameCenterError)
	End Method

	Method OnGameCenterScoreSubmitted(requestId:Int, leaderboardIdentifier:String, score:Long, error:TGameCenterError)
	End Method

	Method OnGameCenterLeaderboardLoaded(requestId:Int, leaderboard:TGameCenterLeaderboardResult, error:TGameCenterError)
	End Method

	Method OnGameCenterViewDismissed(view:EGameCenterView)
	End Method
End Type

Function BeginSession()
	If Not pendingMatch Or pendingMatch.ExpectedPlayerCount() <> 0 Or pendingMatch.PlayerCount() < MATCH_MIN_PLAYERS - 1 Then Return
	If Not gameCenter.localPlayer Then Return
	Local hostIndex:Int = GameKitElectedHostIndex(pendingMatch, gameCenter.localPlayer)
	If hostIndex < 0 Then Return
	hostRole = hostIndex = 0
	transport = TGameKitTransport.Create(pendingMatch, GAMEKIT_MAX_REMOTE_PEERS, 2, 900)
	If Not transport Then
		statusText = "Could not create GameKit transport"
		Return
	End If
	If hostRole Then
		session = TNetSession.CreateHost(transport, APP_ID, APP_VERSION, pendingMatch.PlayerCount(), 900)
		statusText = "Match connected; hosting " + (pendingMatch.PlayerCount() + 1) + " players"
	Else
		If Not transport.EnableOnlyPlayer(hostIndex) Then
			statusText = "Could not select the session host"
			transport.Close()
			transport = Null
			Return
		End If
		session = TNetSession.CreateClient(transport, APP_ID, APP_VERSION, Null, 0, 1, 900)
		statusText = "Match connected; joining session host"
	End If
	detailText = "Native GameKit players: " + (pendingMatch.PlayerCount() + 1)
	pendingMatch = Null
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
gameCenter.Start(New TListener)

While Not AppTerminate()
	BeginSession()
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
		Else If gameCenter.IsAuthenticated() And Not pendingMatch And Not session Then
			statusText = "Looking for " + MATCH_MIN_PLAYERS + "-" + MATCH_MAX_PLAYERS + " players..."
			Local requestId:Int = gameCenter.FindMatch(MATCH_MIN_PLAYERS, MATCH_MAX_PLAYERS)
			detailText = "Matchmaking request " + requestId
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
If pendingMatch Then pendingMatch.Disconnect()
gameCenter.Stop()
