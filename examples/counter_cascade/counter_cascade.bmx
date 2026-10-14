SuperStrict

Framework Max2D.SDL3RenderMax2D
Import Max2D.TileMap
Import GameNet.Core
Import BRL.Event
Import BRL.PolledInput
Import BRL.PNGLoader

?macos Or ios
Import GameNet.GameKitOnline
Import GameNet.MatchRoom
Import GameNet.Online
Import GameNet.Session
?

Incbin "images/tabletop-background.png"

Include "rules.bmx"
Include "maps.bmx"
Include "protocol.bmx"

Const SCREEN_WIDTH:Int = 1000
Const SCREEN_HEIGHT:Int = 700
Const DEFAULT_CASCADE_STEP_MILLIS:Int = 100
Const ONLINE_RETRY_MILLIS:UInt = 750
Const ONLINE_MAX_MOVE_RETRIES:Int = 8
Const ONLINE_RECOVERY_RETRY_MILLIS:UInt = 1000
Const ONLINE_MAX_RECOVERY_RETRIES:Int = 4

Enum ECascadeMenuPage
	Main
	LocalPlay
	Multiplayer
End Enum

?ios Or android
Global pointerHover:Int = False
?Not ios And Not android
Global pointerHover:Int = True
?

Global game:TCascadeGame
Global viewGrid:TTileGrid
Global lobbyOpen:Int
Global lobbyConfig:SCascadeMatchConfig
Global menuPage:ECascadeMenuPage = ECascadeMenuPage.Main
Global playerPalette:Int[CASCADE_MAX_PLAYERS]
Global eventLog:TCascadeEventLog = TCascadeEventLog.Create()
Global boardX:Float
Global boardY:Float
Global statusText:String = "Choose how to play"
Global hoverCell:Int = -1
Global testMode:Int
Global screenshotPath:String
Global frames:Int
Global background:TImage
Global counterImage:TImage
Global displayOwners:Byte[]
Global displayCounters:Int[]
Global balanceShares:Float[CASCADE_MAX_PLAYERS]
Global balanceLastMillis:Int
Global balanceInitialized:Int
Global animationActive:Int
Global animationIndex:Int
Global animationStarted:Int
Global animationStartMillis:Int
Global animationResult:ECascadeMoveResult
Global cascadeStepMillis:Int = DEFAULT_CASCADE_STEP_MILLIS
Global touchHitPending:Int
Global touchHitX:Float
Global touchHitY:Float

?macos Or ios
Global online:IOnlineService
Global onlineRequest:UInt
Global onlineTransport:INetTransport
Global onlineSession:TNetSession
Global onlineRoom:TMatchRoom
Global onlinePeer:SNetPeer
Global onlineHost:Int
Global onlineJoined:Int
Global onlineMode:Int
Global onlineOpening:Int
Global onlineWaitingForMove:Int
Global onlineMoveRequest:SCascadeMoveRequest
Global onlineMoveSentAt:UInt
Global onlineMoveRetries:Int
Global onlineLobbyConfigReady:Int
Global onlineResyncPending:Int
Global onlineResyncSentAt:UInt
Global onlineResyncRetries:Int
Global pendingMoveRequest:SCascadeMoveRequest
Global hasPendingMoveRequest:Int
Global pendingAppliedMove:SCascadeAppliedMove
Global hasPendingAppliedMove:Int
Global lastAppliedMove:SCascadeAppliedMove
Global hasLastAppliedMove:Int
Global onlineDebugText:String
Global onlinePacket:Byte[1024]
?

For Local argument:String = EachIn AppArgs[1..]
	If argument = "--test" Then testMode = True
	If argument.StartsWith("--screenshot=") Then screenshotPath = argument[13..]
Next

Graphics SCREEN_WIDTH, SCREEN_HEIGHT
SetVirtualResolution(SCREEN_WIDTH, SCREEN_HEIGHT, VIRTUAL_LETTERBOX)
SetClsColor(15, 20, 31)
Local staticImageFlags:Int = FILTEREDIMAGE
If Max2DSupportsImageFlags(FILTEREDIMAGE | MIPMAPPEDIMAGE) Then staticImageFlags :| MIPMAPPEDIMAGE
background = LoadImage("incbin::images/tabletop-background.png", staticImageFlags)
counterImage = CreateCounterImage(staticImageFlags)
ResetPlayerColours()
?ios Or android
AddHook EmitEventHook, CascadeTouchEventHook
?
If testMode Then
	StartHex(3)
	StartConfiguredMatch()
End If

While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	?macos Or ios
	PollOnlineGame()
	?
	If game Then
		UpdateGame()
	Else If lobbyOpen Then
		UpdateLobby()
	Else
		UpdateMenu()
	End If
	Cls()
	If game Then
		DrawGame()
	Else If lobbyOpen Then
		DrawLobby()
	Else
		DrawMenu()
	End If
	frames :+ 1
	If frames = 3 And screenshotPath.Length Then SavePixmapPNG(GrabPixmap(0, 0, NativeResolutionWidth(), NativeResolutionHeight()), screenshotPath)
	Flip()
	If testMode And frames >= 3 Then Exit
Wend
?ios Or android
RemoveHook EmitEventHook, CascadeTouchEventHook
?
?macos Or ios
CloseOnlineGame()
?
EndGraphics()

Function StartSquare(players:Int)
	Local size:Int = 8
	If players = 2 Then size = 5
	OpenLocalLobby(New SCascadeMatchConfig(ECascadeBoardLayout.Square, size, players))
End Function

Function StartHex(players:Int)
	If players = 4 Then
		OpenLocalLobby(New SCascadeMatchConfig(ECascadeBoardLayout.HexRhombus, 7, players))
	Else If players = 2 Then
		OpenLocalLobby(New SCascadeMatchConfig(ECascadeBoardLayout.Hexagon, 3, players))
	Else
		OpenLocalLobby(New SCascadeMatchConfig(ECascadeBoardLayout.Hexagon, 4, players))
	End If
End Function

Function OpenLocalLobby(config:SCascadeMatchConfig)
	If Not config.IsValid() Then Return
	config.startingPlayer = MilliSecs() Mod config.playerCount
	lobbyConfig = config
	lobbyOpen = True
	ResetPlayerColours()
	statusText = "Choose colours, then start the match"
End Function

Function StartConfiguredMatch()
	Local board:TCascadeBoard = lobbyConfig.CreateBoard()
	If Not board Then
		statusText = "Could not create the selected board"
		Return
	End If
	game = TCascadeGame.Create(board)
	game.Reset(lobbyConfig.startingPlayer)
	If board.geometry = ECascadeGeometry.Square Then
		viewGrid = TTileGrid.Rectangular(62, 62)
		statusText = "Place a counter on an empty square or one of your own"
	Else
		viewGrid = TTileGrid.Hexagonal(58, 68, ETileLayout.PointyHex, ETileStagger.Odd)
		statusText = "Place a counter on an empty hexagon or one of your own"
	End If
	lobbyOpen = False
	PrepareBoardView()
	balanceInitialized = False
End Function

Function ResetPlayerColours()
	For Local player:Int = 0 Until CASCADE_MAX_PLAYERS
		playerPalette[player] = player
	Next
End Function

Function PrepareBoardView()
	Local minX:Double = 1000000.0, minY:Double = 1000000.0
	Local maxX:Double = -1000000.0, maxY:Double = -1000000.0
	For Local cell:Int = 0 Until game.board.CellCount()
		For Local corner:Int = 0 Until viewGrid.CornerCount()
			Local x:Double, y:Double
			viewGrid.CellCorner(game.board.cells[cell].column, game.board.cells[cell].row, corner, x, y)
			minX = Min(minX, x)
			minY = Min(minY, y)
			maxX = Max(maxX, x)
			maxY = Max(maxY, y)
		Next
	Next
	boardX = Float((SCREEN_WIDTH - (maxX - minX)) * 0.5 - minX)
	boardY = Float(112.0 + (520.0 - (maxY - minY)) * 0.5 - minY)
	SyncPresentation()
End Function

Function SyncPresentation()
	If Not game Then Return
	If displayOwners.Length <> game.board.CellCount() Then
		displayOwners = New Byte[game.board.CellCount()]
		displayCounters = New Int[game.board.CellCount()]
	End If
	For Local cell:Int = 0 Until game.board.CellCount()
		displayOwners[cell] = game.owners[cell]
		displayCounters[cell] = game.counters[cell]
	Next
End Function

Function UpdateMenu()
	?macos Or ios
	If onlineMode Then
		Local roomX:Float, roomY:Float
		If PollPress(roomX, roomY) Then
			If onlineJoined Then
				If onlineHost And roomY >= 405 And roomY < 457 And ((roomX >= 210 And roomX < 310) Or (roomX >= 690 And roomX < 790)) Then
					CycleOnlineMatch()
				Else If roomY >= 515 And roomY < 575 And roomX >= 300 And roomX < 480 Then
					SetOnlineReady()
				Else If roomY >= 515 And roomY < 575 And roomX >= 520 And roomX < 700 Then
					CloseOnlineMatch()
					menuPage = ECascadeMenuPage.Multiplayer
					statusText = "Choose a multiplayer mode"
				End If
			Else If roomY >= 485 And roomY < 545 And roomX >= 410 And roomX < 590 Then
				CloseOnlineMatch()
				menuPage = ECascadeMenuPage.Multiplayer
				statusText = "Choose a multiplayer mode"
			End If
		End If
		Return
	End If
	?
	Select menuPage
		Case ECascadeMenuPage.Main
			If KeyHit(KEY_1) Then OpenLocalMenu()
			If KeyHit(KEY_2) Then OpenMultiplayerMenu()
		Case ECascadeMenuPage.LocalPlay
			If KeyHit(KEY_1) Then StartSquare(2)
			If KeyHit(KEY_2) Then StartSquare(4)
			If KeyHit(KEY_3) Then StartHex(2)
			If KeyHit(KEY_4) Then StartHex(3)
			If KeyHit(KEY_5) Then StartHex(4)
			If KeyHit(KEY_M) Then OpenMainMenu()
		Case ECascadeMenuPage.Multiplayer
			?macos Or ios
			If KeyHit(KEY_1) Then BeginOnlineSearch()
			?
			If KeyHit(KEY_M) Then OpenMainMenu()
	End Select
	Local x:Float, y:Float
	If Not PollPress(x, y) Then Return
	Select menuPage
		Case ECascadeMenuPage.Main
			If x >= 200 And x < 800 And y >= 275 And y < 335 Then OpenLocalMenu()
			If x >= 200 And x < 800 And y >= 365 And y < 425 Then OpenMultiplayerMenu()
		Case ECascadeMenuPage.LocalPlay
			If x >= 200 And x < 800 Then
				If y >= 180 And y < 240 Then StartSquare(2)
				If y >= 255 And y < 315 Then StartSquare(4)
				If y >= 330 And y < 390 Then StartHex(2)
				If y >= 405 And y < 465 Then StartHex(3)
				If y >= 480 And y < 540 Then StartHex(4)
			End If
			If x >= 410 And x < 590 And y >= 575 And y < 635 Then OpenMainMenu()
		Case ECascadeMenuPage.Multiplayer
			?macos Or ios
			If x >= 200 And x < 800 And y >= 285 And y < 345 Then BeginOnlineSearch()
			?
			If x >= 410 And x < 590 And y >= 500 And y < 560 Then OpenMainMenu()
	End Select
End Function

Function OpenMainMenu()
	menuPage = ECascadeMenuPage.Main
	statusText = "Choose how to play"
End Function

Function OpenLocalMenu()
	menuPage = ECascadeMenuPage.LocalPlay
	statusText = "Choose a local match"
End Function

Function OpenMultiplayerMenu()
	menuPage = ECascadeMenuPage.Multiplayer
	statusText = "Choose a multiplayer mode"
End Function

Function UpdateLobby()
	If KeyHit(KEY_M) Then
		lobbyOpen = False
		OpenLocalMenu()
		Return
	End If
	If KeyHit(KEY_ENTER) Then
		StartConfiguredMatch()
		Return
	End If
	Local x:Float, y:Float
	If Not PollPress(x, y) Then Return
	If y >= 575 And y < 635 Then
		If x >= 200 And x < 380 Then
			lobbyOpen = False
			OpenLocalMenu()
		Else If x >= 620 And x < 800 Then
			StartConfiguredMatch()
		End If
		Return
	End If
	For Local player:Int = 0 Until lobbyConfig.playerCount
		Local slotX:Float = LobbySlotX(player)
		If x >= slotX And x < slotX + 170 And y >= 255 And y < 430 Then
			CyclePlayerColour(player)
			Return
		End If
	Next
End Function

Function LobbySlotX:Float(player:Int)
	Local totalWidth:Float = Float(lobbyConfig.playerCount * 170 + (lobbyConfig.playerCount - 1) * 20)
	Return (SCREEN_WIDTH - totalWidth) * 0.5 + Float(player * 190)
End Function

Function CyclePlayerColour(player:Int)
	For Local attempt:Int = 1 To 6
		Local candidate:Int = (playerPalette[player] + attempt) Mod 6
		Local used:Int
		For Local other:Int = 0 Until lobbyConfig.playerCount
			If other <> player And playerPalette[other] = candidate Then used = True
		Next
		If Not used Then
			playerPalette[player] = candidate
			Return
		End If
	Next
End Function

' Returns a press and the coordinates captured by that same input event. Mobile
' uses the native touch event instead of SDL's compatibility mouse position.
Function PollPress:Int(x:Float Var, y:Float Var)
	?ios Or android
	If Not touchHitPending Then Return False
	x = touchHitX
	y = touchHitY
	touchHitPending = False
	Return True
	?
	?Not ios And Not android
	If Not MouseHit(1) Then Return False
	Return GetVirtualMouse(x, y, True)
	?
End Function

?ios Or android
Function CascadeTouchEventHook:Object(id:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If Not event Or event.id <> EVENT_TOUCHDOWN Then Return data
	Local nativeX:Float = NativeResolutionWidth() * event.x / 10000.0
	Local nativeY:Float = NativeResolutionHeight() * event.y / 10000.0
	NativeToVirtual(nativeX, nativeY, touchHitX, touchHitY)
	touchHitPending = True
	Return data
End Function
?

?macos Or ios
Function BeginOnlineSearch()
	If onlineSession Or onlineRequest Then Return
	onlineMode = True
	lobbyOpen = False
	game = Null
	viewGrid = Null
	statusText = "Connecting to Game Center..."
	If Not online Then online = TGameKitOnlineService.Create(1, 2, 900)
	If Not online Then
		statusText = "Game Center multiplayer is unavailable"
		Return
	End If
	If online.State() = EOnlineServiceState.Closed Then
		onlineOpening = online.Open() <> 0
	Else If online.State() = EOnlineServiceState.Ready Then
		StartOnlineMatchmaking()
	End If
End Function

Function StartOnlineMatchmaking()
	If Not online Or online.State() <> EOnlineServiceState.Ready Or onlineRequest Then Return
	Local request:TOnlineMatchmakingRequest = New TOnlineMatchmakingRequest
	request.minPlayers = 2
	request.maxPlayers = 2
	onlineRequest = online.StartMatchmaking(request)
	If onlineRequest = 0 Then
		statusText = "Could not start Game Center matchmaking"
	Else
		statusText = "Looking for another player..."
	End If
End Function

Function BeginOnlineSession(requestId:UInt)
	Local info:SOnlineMatchInfo
	If Not online.MatchInfo(requestId, info) Then
		statusText = "Game Center match information is unavailable"
		Return
	End If
	onlineTransport = online.TakeMatchTransport(requestId)
	If Not onlineTransport Then
		statusText = "Could not create the Game Center connection"
		Return
	End If
	onlineHost = info.IsSessionHost()
	onlineWaitingForMove = False
	hasPendingMoveRequest = False
	hasPendingAppliedMove = False
	hasLastAppliedMove = False
	onlineMoveRetries = 0
	onlineLobbyConfigReady = False
	onlineResyncPending = False
	onlineResyncRetries = 0
	onlineDebugText = ""
	If onlineHost Then
		onlineSession = TNetSession.CreateHost(onlineTransport, CASCADE_APP_ID, CASCADE_APP_VERSION, 1, 900)
	Else
		onlineSession = TNetSession.CreateClient(onlineTransport, CASCADE_APP_ID, CASCADE_APP_VERSION, Null, 0, 1, 900)
	End If
	If Not onlineSession Then
		statusText = "Could not create the Counter Cascade session"
		Return
	End If
	Local roomConfig:SMatchRoomConfig = New SMatchRoomConfig(2, CASCADE_ROOM_COMMAND_MESSAGE, CASCADE_ROOM_STATE_MESSAGE, CASCADE_CONTROL_CHANNEL, 32, 32)
	If onlineHost Then
		onlineRoom = TMatchRoom.CreateHost(onlineSession, roomConfig)
	Else
		onlineRoom = TMatchRoom.CreateClient(onlineSession, info.SessionHostPeer(), roomConfig)
	End If
	If Not onlineRoom Then
		statusText = "Could not create the Counter Cascade room"
		onlineSession.Close()
		onlineSession = Null
		Return
	End If
	onlineSession.ConfigureHealth(New SSessionHealthConfig(10000, 15000, 500, 2000))
	onlineRequest = 0
	statusText = "Match found; connecting..."
End Function

Function PollOnlineGame()
	If online Then
		online.Pump()
		Local onlineEvent:SOnlineEvent
		While online.Poll(onlineEvent)
			Select onlineEvent.Kind()
				Case EOnlineEventKind.ServiceReady
				onlineOpening = False
				If onlineMode Then StartOnlineMatchmaking()
				Case EOnlineEventKind.MatchmakingStarted
					statusText = "Looking for another player..."
				Case EOnlineEventKind.MatchReady
					BeginOnlineSession(onlineEvent.RequestId())
				Case EOnlineEventKind.MatchmakingCancelled
					onlineRequest = 0
					statusText = "Matchmaking cancelled"
				Case EOnlineEventKind.OperationFailed
					onlineRequest = 0
					onlineOpening = False
					statusText = "Game Center: " + onlineEvent.Detail()
			End Select
		Wend
	End If
	If onlineSession Then PollOnlineSession()
	ProcessPendingOnlineMove()
	RetryOnlineMove()
	RetryOnlineStateRequest()
End Function

Function PollOnlineSession()
	Local sessionEvent:SSessionEvent
	While onlineSession.Poll(sessionEvent)
		Select sessionEvent.Kind()
			Case ESessionEventKind.JoinRequested
				If onlineSession.Accept(sessionEvent.Peer()) <> ETransportResult.Ok Then statusText = "Could not accept the other player"
			Case ESessionEventKind.Joined
				onlinePeer = sessionEvent.Peer()
				onlineJoined = True
				If onlineRoom.PlayerJoined(onlinePeer) <> ETransportResult.Ok Then
					ReturnToMultiplayerAfterFailure("Could not join the online room")
					Return
				End If
				If onlineHost Then
					lobbyConfig = New SCascadeMatchConfig(ECascadeBoardLayout.Square, 5, 2, MilliSecs() Mod 2)
					ResetPlayerColours()
					If PublishOnlineLobbyConfig() Then
						onlineLobbyConfigReady = True
						statusText = "Choose a match, then ready up"
					Else
						statusText = "Could not publish the match settings"
					End If
				Else
					statusText = "Connected; waiting for the host..."
				End If
			Case ESessionEventKind.Message
				If onlineRoom And onlineRoom.HandlesMessageType(sessionEvent.MessageType()) Then
					If Not onlineRoom.Receive(sessionEvent.Peer(), sessionEvent.MessageType(), sessionEvent.Payload()) Then statusText = "Invalid online room message"
				Else
					ReceiveOnlineMessage(sessionEvent)
				End If
			Case ESessionEventKind.Left
				ReturnToMultiplayerAfterFailure("The other player left the match")
				Return
			Case ESessionEventKind.Rejected
				ReturnToMultiplayerAfterFailure("The Counter Cascade session was rejected")
				Return
			Case ESessionEventKind.Error
				ReturnToMultiplayerAfterFailure("Counter Cascade session error " + sessionEvent.Code())
				Return
		End Select
		ProcessOnlineRoomEvents()
	Wend
	ProcessOnlineRoomEvents()
End Function

Function ReturnToMultiplayerAfterFailure(message:String)
	CloseOnlineMatch()
	game = Null
	viewGrid = Null
	lobbyOpen = False
	menuPage = ECascadeMenuPage.Multiplayer
	statusText = message
End Function

Function PublishOnlineLobbyConfig:Int()
	If Not onlineHost Or Not onlineRoom Then Return False
	Local length:Size_T = EncodeCascadeConfig(Byte Ptr(onlinePacket), Size_T(onlinePacket.Length), lobbyConfig)
	If length = 0 Then Return False
	Return onlineRoom.SetConfiguration(New SPacketView(Byte Ptr(onlinePacket), length)) = ETransportResult.Ok
End Function

Function ReceiveOnlineMessage(sessionEvent:SSessionEvent)
	Select sessionEvent.MessageType()
		Case CASCADE_MSG_MOVE_REQUEST
			If Not onlineHost Or hasPendingMoveRequest Then Return
			Local request:SCascadeMoveRequest
			If DecodeCascadeMoveRequest(sessionEvent.Payload(), request) Then
				pendingMoveRequest = request
				hasPendingMoveRequest = True
				onlineDebugText = "Host received move for turn " + request.turn
			Else
				onlineDebugText = "Host rejected a malformed move packet"
			End If
		Case CASCADE_MSG_MOVE_APPLIED
			If onlineHost Or hasPendingAppliedMove Then Return
			Local move:SCascadeAppliedMove
			If DecodeCascadeAppliedMove(sessionEvent.Payload(), move) Then
				pendingAppliedMove = move
				hasPendingAppliedMove = True
			End If
		Case CASCADE_MSG_STATE_REQUEST
			If onlineHost And sessionEvent.Payload().Length() = 0 Then SendOnlineState()
		Case CASCADE_MSG_STATE
			If onlineHost Or Not game Then Return
			If DecodeCascadeState(sessionEvent.Payload(), game) Then
				onlineResyncPending = False
				onlineResyncRetries = 0
				onlineWaitingForMove = False
				hasPendingAppliedMove = False
				animationActive = False
				animationStarted = False
				eventLog.Clear()
				SyncPresentation()
				balanceInitialized = False
				statusText = "Match resynchronised with the host"
				onlineDebugText = "Recovered authoritative turn " + game.turn
			Else
				statusText = "The host sent an invalid recovery state"
			End If
	End Select
End Function

Function SendOnlineState:Int()
	If Not onlineHost Or Not onlineSession Or Not onlineJoined Or Not game Then Return False
	Local length:Size_T = EncodeCascadeState(Byte Ptr(onlinePacket), Size_T(onlinePacket.Length), game)
	If length = 0 Then Return False
	Return onlineSession.Send(onlinePeer, CASCADE_MSG_STATE, CASCADE_CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(onlinePacket), length) = ETransportResult.Ok
End Function

Function RequestOnlineState(reason:String)
	If onlineHost Or Not onlineSession Or Not onlineJoined Or Not game Then Return
	If onlineResyncPending Then Return
	If SendOnlineControlMessage(CASCADE_MSG_STATE_REQUEST) Then
		onlineResyncPending = True
		onlineResyncSentAt = UInt(MilliSecs())
		onlineResyncRetries = 0
		onlineWaitingForMove = False
		statusText = "Recovering match state from the host..."
		onlineDebugText = reason
	Else
		statusText = "Could not request match recovery"
	End If
End Function

Function RetryOnlineStateRequest()
	If onlineHost Or Not onlineResyncPending Or Not onlineSession Or Not onlineJoined Then Return
	Local now:UInt = UInt(MilliSecs())
	If now - onlineResyncSentAt < ONLINE_RECOVERY_RETRY_MILLIS Then Return
	If onlineResyncRetries >= ONLINE_MAX_RECOVERY_RETRIES Then
		ReturnToMultiplayerAfterFailure("The match could not be recovered")
		Return
	End If
	onlineResyncRetries :+ 1
	onlineResyncSentAt = now
	If SendOnlineControlMessage(CASCADE_MSG_STATE_REQUEST) Then
		statusText = "Recovering match state; retry " + onlineResyncRetries
	Else
		statusText = "Waiting to retry match recovery"
	End If
End Function

Function SendOnlineControlMessage:Int(messageType:UInt)
	If Not onlineSession Or Not onlineJoined Then Return False
	Return onlineSession.Send(onlinePeer, messageType, CASCADE_CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered) = ETransportResult.Ok
End Function

Function ShowOnlineRoom(message:String)
	game = Null
	viewGrid = Null
	animationActive = False
	onlineWaitingForMove = False
	hasPendingMoveRequest = False
	hasPendingAppliedMove = False
	onlineResyncPending = False
	onlineResyncRetries = 0
	statusText = message
	onlineDebugText = "Choose READY when both players are in the lobby"
End Function

Function EnterOnlineRoom()
	If Not onlineRoom Then Return
	If onlineRoom.ReturnToRoom() <> ETransportResult.Ok Then
		statusText = "Could not return to the online lobby"
	Else
		statusText = "Returning to the online lobby..."
		ProcessOnlineRoomEvents()
	End If
End Function

Function ApplyOnlineRoomConfiguration:Int()
	If Not onlineRoom Then Return False
	Local config:SCascadeMatchConfig
	If Not DecodeCascadeConfig(onlineRoom.Configuration(), config) Or config.playerCount <> 2 Then
		statusText = "The host sent invalid room settings"
		Return False
	End If
	lobbyConfig = config
	onlineLobbyConfigReady = True
	ResetPlayerColours()
	Return True
End Function

Function ProcessOnlineRoomEvents()
	If Not onlineRoom Then Return
	Local roomEvent:SMatchRoomEvent
	While onlineRoom.Poll(roomEvent)
		Select roomEvent.Kind()
			Case EMatchRoomEventKind.ConfigurationChanged
				If ApplyOnlineRoomConfiguration() And Not onlineHost Then statusText = "The host selected " + LobbyDescription()
			Case EMatchRoomEventKind.MatchStarted
				If ApplyOnlineRoomConfiguration() Then
					lobbyConfig.startingPlayer = Int(onlineRoom.Seed() Mod ULong(lobbyConfig.playerCount))
					onlineResyncPending = False
					onlineResyncRetries = 0
					StartConfiguredMatch()
					statusText = "Round " + onlineRoom.Round() + " started"
				End If
			Case EMatchRoomEventKind.MemberReturned
				If roomEvent.Player() = OnlineLocalPlayer() Then
					If onlineRoom.IsInRoom(1 - OnlineLocalPlayer()) Then
						ShowOnlineRoom("Both players are in the online lobby")
					Else
						ShowOnlineRoom("Waiting for the other player to return")
					End If
				Else If game And game.winner >= 0 Then
					statusText = "The other player returned to the lobby"
				End If
			Case EMatchRoomEventKind.StagingOpened
				If onlineRoom.IsInRoom(OnlineLocalPlayer()) Then ShowOnlineRoom("Both players are in the online lobby")
			Case EMatchRoomEventKind.AuthorityLeft
				ReturnToMultiplayerAfterFailure("The room host left the match")
				Return
		End Select
	Wend
	TryStartOnlineRound()
End Function

Function SetOnlineReady()
	If Not onlineJoined Or Not onlineRoom Or Not onlineLobbyConfigReady Then Return
	Local localPlayer:Int = OnlineLocalPlayer()
	If Not onlineRoom.IsInRoom(0) Or Not onlineRoom.IsInRoom(1) Or onlineRoom.IsReady(localPlayer) Then Return
	If onlineRoom.SetLocalReady(True) <> ETransportResult.Ok Then
		statusText = "Could not send ready state"
		Return
	End If
	statusText = "Ready; waiting for the other player"
	ProcessOnlineRoomEvents()
	TryStartOnlineRound()
End Function

Function CycleOnlineMatch()
	If Not onlineHost Or Not onlineJoined Or Not onlineRoom Or Not onlineLobbyConfigReady Then Return
	Local startingPlayer:Int = lobbyConfig.startingPlayer
	If lobbyConfig.layout = ECascadeBoardLayout.Square Then
		lobbyConfig = New SCascadeMatchConfig(ECascadeBoardLayout.Hexagon, 3, 2, startingPlayer)
	Else
		lobbyConfig = New SCascadeMatchConfig(ECascadeBoardLayout.Square, 5, 2, startingPlayer)
	End If
	If PublishOnlineLobbyConfig() Then
		statusText = "Match changed; both players must ready up"
	Else
		statusText = "Could not send the room settings"
	End If
End Function

Function TryStartOnlineRound()
	If Not onlineHost Or Not onlineJoined Or Not onlineRoom Or Not onlineRoom.AllPresentReady(2) Then Return
	Local startingPlayer:Int = lobbyConfig.startingPlayer
	If onlineRoom.Round() > 0 Then startingPlayer = (Int(onlineRoom.Seed()) + 1) Mod 2
	If onlineRoom.BeginMatch(ULong(startingPlayer), 2) = ETransportResult.Ok Then ProcessOnlineRoomEvents()
End Function

Function ProcessPendingOnlineMove()
	If Not game Or animationActive Then Return
	If onlineHost And hasPendingMoveRequest Then
		Local request:SCascadeMoveRequest = pendingMoveRequest
		hasPendingMoveRequest = False
		If request.turn = game.turn And game.currentPlayer = 1 Then
			ApplyAuthoritativeOnlineMove(1, request.cell)
		Else If hasLastAppliedMove And lastAppliedMove.turn = request.turn And lastAppliedMove.player = 1 And lastAppliedMove.cell = request.cell Then
			SendOnlineAppliedMove(lastAppliedMove)
			onlineDebugText = "Host acknowledged a repeated move"
		Else
			onlineDebugText = "Host expected turn " + game.turn + ", player " + (game.currentPlayer + 1)
		End If
	Else If Not onlineHost And hasPendingAppliedMove Then
		Local move:SCascadeAppliedMove = pendingAppliedMove
		hasPendingAppliedMove = False
		If move.turn < game.turn Then
			If onlineWaitingForMove And move.turn = onlineMoveRequest.turn Then onlineWaitingForMove = False
			Return
		End If
		If move.turn <> game.turn Or move.player <> game.currentPlayer Then
			RequestOnlineState("Local turn " + game.turn + ", host sent " + move.turn)
			Return
		End If
		onlineWaitingForMove = False
		If move.result <> ECascadeMoveResult.Accepted And move.result <> ECascadeMoveResult.Won Then
			If game.StateHash() <> move.stateHash Then
				RequestOnlineState("Rejected move state hash differed")
				Return
			End If
			Select move.result
				Case ECascadeMoveResult.Invalid
					statusText = "That cell belongs to the other player"
				Case ECascadeMoveResult.CycleDetected
					statusText = "Move rejected: repeating cascade"
				Case ECascadeMoveResult.ToppleLimitReached
					statusText = "Move rejected: cascade safety limit reached"
			End Select
			onlineDebugText = "Host rejected turn " + move.turn + "; choose another cell"
			Return
		End If
		Local result:ECascadeMoveResult = game.ApplyMove(move.player, move.cell, eventLog)
		If result <> move.result Or game.StateHash() <> move.stateHash Then
			RequestOnlineState("Applied move state hash differed")
			Return
		End If
		onlineDebugText = "Host confirmed turn " + move.turn
		BeginCascadeAnimation(result)
	End If
End Function

Function ApplyAuthoritativeOnlineMove(player:Int, cell:Int)
	If Not game Or Not onlineHost Or Not onlineJoined Then Return
	Local turn:UInt = game.turn
	Local result:ECascadeMoveResult = game.ApplyMove(player, cell, eventLog)
	Local move:SCascadeAppliedMove = New SCascadeAppliedMove(turn, player, cell, result, game.StateHash())
	lastAppliedMove = move
	hasLastAppliedMove = True
	If Not SendOnlineAppliedMove(move) Then
		statusText = "Could not send the move response"
		Return
	End If
	Select result
		Case ECascadeMoveResult.Accepted, ECascadeMoveResult.Won
			BeginCascadeAnimation(result)
		Case ECascadeMoveResult.Invalid
			statusText = "That cell belongs to another player"
		Case ECascadeMoveResult.CycleDetected
			statusText = "Move rejected: repeating cascade"
		Case ECascadeMoveResult.ToppleLimitReached
			statusText = "Move rejected: cascade safety limit reached"
	End Select
End Function

Function SendOnlineAppliedMove:Int(move:SCascadeAppliedMove)
	Local length:Size_T = EncodeCascadeAppliedMove(Byte Ptr(onlinePacket), Size_T(onlinePacket.Length), move)
	If length = 0 Then Return False
	Return onlineSession.Send(onlinePeer, CASCADE_MSG_MOVE_APPLIED, CASCADE_GAME_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(onlinePacket), length) = ETransportResult.Ok
End Function

Function SendOnlineMove(cell:Int)
	If Not onlineSession Or Not onlineJoined Or onlineWaitingForMove Or onlineResyncPending Then Return
	onlineMoveRequest = New SCascadeMoveRequest(game.turn, cell)
	onlineMoveRetries = 0
	If SendOnlineMoveRequest() Then
		onlineWaitingForMove = True
		statusText = "Move sent to the host..."
	Else
		statusText = "Could not send the move"
	End If
End Function

Function SendOnlineMoveRequest:Int()
	Local length:Size_T = EncodeCascadeMoveRequest(Byte Ptr(onlinePacket), Size_T(onlinePacket.Length), onlineMoveRequest)
	If length = 0 Then Return False
	Local result:ETransportResult = onlineSession.Send(onlinePeer, CASCADE_MSG_MOVE_REQUEST, CASCADE_GAME_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(onlinePacket), length)
	If result <> ETransportResult.Ok Then Return False
	onlineMoveSentAt = UInt(MilliSecs())
	Return True
End Function

Function RetryOnlineMove()
	If onlineHost Or Not onlineWaitingForMove Or Not onlineSession Or Not onlineJoined Then Return
	Local now:UInt = UInt(MilliSecs())
	If now - onlineMoveSentAt < ONLINE_RETRY_MILLIS Then Return
	If onlineMoveRetries >= ONLINE_MAX_MOVE_RETRIES Then
		onlineWaitingForMove = False
		RequestOnlineState("Host did not acknowledge turn " + onlineMoveRequest.turn)
		Return
	End If
	If SendOnlineMoveRequest() Then
		onlineMoveRetries :+ 1
		statusText = "Waiting for host; retry " + onlineMoveRetries
		onlineDebugText = "Resent turn " + onlineMoveRequest.turn
	Else
		statusText = "Could not resend the move"
	End If
End Function

Function CloseOnlineMatch()
	If onlineRequest And online Then online.CancelMatchmaking(onlineRequest)
	If onlineSession Then onlineSession.Close()
	onlineSession = Null
	onlineRoom = Null
	onlineTransport = Null
	onlinePeer = New SNetPeer
	onlineRequest = 0
	onlineJoined = False
	onlineMode = False
	onlineWaitingForMove = False
	hasPendingMoveRequest = False
	hasPendingAppliedMove = False
	hasLastAppliedMove = False
	onlineMoveRetries = 0
	onlineLobbyConfigReady = False
	onlineResyncPending = False
	onlineResyncRetries = 0
	onlineDebugText = ""
End Function

Function CloseOnlineGame()
	CloseOnlineMatch()
	If online Then online.Close()
	online = Null
End Function
?

Function UpdateGame()
	If animationActive Then
		Local ignoredX:Float, ignoredY:Float
		PollPress(ignoredX, ignoredY)
		UpdateCascadeAnimation()
		Return
	End If
	If KeyHit(KEY_M) Then
		?macos Or ios
		If onlineMode Then
			EnterOnlineRoom()
			Return
		End If
		?
		game = Null
		viewGrid = Null
		OpenLocalMenu()
		Return
	End If
	If KeyHit(KEY_R) Then
		?macos Or ios
		If onlineMode Then Return
		?
		game.Reset(lobbyConfig.startingPlayer)
		SyncPresentation()
		statusText = "Board reset"
		Return
	End If
	hoverCell = -1
	Local pressX:Float, pressY:Float
	Local clicked:Int = PollPress(pressX, pressY)
	If game.winner >= 0 Then
		If clicked And pressY >= 365 And pressY < 421 Then
			?macos Or ios
			If onlineMode Then
				If pressX >= 330 And pressX < 490 Then
					EnterOnlineRoom()
				Else If pressX >= 510 And pressX < 670 Then
					CloseOnlineMatch()
					game = Null
					viewGrid = Null
					OpenMultiplayerMenu()
				End If
				Return
			End If
			?
			If pressX >= 330 And pressX < 490 Then
				lobbyConfig.startingPlayer = (lobbyConfig.startingPlayer + 1) Mod lobbyConfig.playerCount
				game.Reset(lobbyConfig.startingPlayer)
				SyncPresentation()
				statusText = "Player 1 to move"
			Else If pressX >= 510 And pressX < 670 Then
				game = Null
				viewGrid = Null
				OpenLocalMenu()
			End If
		End If
		Return
	End If
	If pointerHover Then
		Local mouseX:Float, mouseY:Float
		Local column:Int, row:Int
		If GetVirtualMouse(mouseX, mouseY, True) Then
			If viewGrid.LocalToCell(mouseX - boardX, mouseY - boardY, column, row) Then
				hoverCell = game.board.CellAt(column, row)
			End If
		End If
	End If
	If Not clicked Then Return
	Local pressedColumn:Int, pressedRow:Int
	If Not viewGrid.LocalToCell(pressX - boardX, pressY - boardY, pressedColumn, pressedRow) Then Return
	Local pressedCell:Int = game.board.CellAt(pressedColumn, pressedRow)
	If pressedCell < 0 Then Return
	Local player:Int = game.currentPlayer
	?macos Or ios
	If onlineMode Then
		If Not onlineJoined Then
			statusText = "Waiting for the other player..."
			Return
		End If
		Local localPlayer:Int = OnlineLocalPlayer()
		If player <> localPlayer Then
			statusText = "Waiting for Player " + (game.currentPlayer + 1)
			Return
		End If
		If Not game.IsLegalMove(localPlayer, pressedCell) Then
			statusText = "That cell belongs to the other player"
			Return
		End If
		If onlineHost Then ApplyAuthoritativeOnlineMove(player, pressedCell) Else SendOnlineMove(pressedCell)
		Return
	End If
	?
	Local result:ECascadeMoveResult = game.ApplyMove(player, pressedCell, eventLog)
	Select result
		Case ECascadeMoveResult.Invalid
			statusText = "That cell belongs to another player"
		Case ECascadeMoveResult.Accepted
			BeginCascadeAnimation(result)
		Case ECascadeMoveResult.Won
			BeginCascadeAnimation(result)
		Case ECascadeMoveResult.CycleDetected
			statusText = "Move rejected: repeating cascade"
		Case ECascadeMoveResult.ToppleLimitReached
			statusText = "Move rejected: cascade safety limit reached"
	End Select
End Function

Function BeginCascadeAnimation(result:ECascadeMoveResult)
	animationActive = eventLog.count > 0
	animationIndex = 0
	animationStarted = False
	animationResult = result
	statusText = "Resolving move..."
	If Not animationActive Then FinishCascadeAnimation()
End Function

Function UpdateCascadeAnimation()
	If animationIndex >= eventLog.count Then
		FinishCascadeAnimation()
		Return
	End If
	Local event:SCascadeEvent = eventLog.events[animationIndex]
	If Not animationStarted Then
		animationStarted = True
		animationStartMillis = MilliSecs()
		If event.kind = ECascadeEventKind.Placed Or event.kind = ECascadeEventKind.Toppled Then ApplyPresentationEvent(event)
	End If
	Local duration:Int
	Select event.kind
		Case ECascadeEventKind.Placed
			duration = 90
		Case ECascadeEventKind.Toppled
			duration = cascadeStepMillis
		Default
			duration = 0
	End Select
	If Int(MilliSecs() - animationStartMillis) < duration Then Return
	If event.kind = ECascadeEventKind.Toppled Then
		For Local direction:Int = 1 To game.board.routeCount
			If animationIndex + direction >= eventLog.count Then Exit
			Local landing:SCascadeEvent = eventLog.events[animationIndex + direction]
			If landing.kind <> ECascadeEventKind.Landed Or landing.source <> event.cell Then Exit
			ApplyPresentationEvent(landing)
		Next
		animationIndex :+ 1 + game.board.routeCount
	Else
		animationIndex :+ 1
	End If
	animationStarted = False
End Function

Function ApplyPresentationEvent(event:SCascadeEvent)
	If event.cell < 0 Or event.cell >= displayCounters.Length Then Return
	displayCounters[event.cell] = event.count
	If event.count = 0 Then displayOwners[event.cell] = 0 Else displayOwners[event.cell] = Byte(event.player + 1)
End Function

Function FinishCascadeAnimation()
	animationActive = False
	animationStarted = False
	SyncPresentation()
	If animationResult = ECascadeMoveResult.Won Then
		statusText = "Player " + (game.winner + 1) + " wins!"
		?macos Or ios
		If onlineMode And onlineHost And onlineRoom And onlineRoom.Phase() = EMatchRoomPhase.Playing Then
			onlineRoom.FinishMatch()
			ProcessOnlineRoomEvents()
		End If
		?
	Else
		statusText = "Player " + (game.currentPlayer + 1) + " to move"
		If game.lastTopples Then statusText = game.lastTopples + " topple" + Plural(game.lastTopples) + " resolved"
	End If
End Function

Function Plural:String(value:Int)
	If value = 1 Then Return ""
	Return "s"
End Function

Function DrawMenu()
	DrawBackground()
	SetColor 236, 241, 250
	DrawText "COUNTER CASCADE", 405, 100
	?macos Or ios
	If onlineMode Then
		DrawOnlinePanel()
		Return
	End If
	?
	Select menuPage
		Case ECascadeMenuPage.Main
			DrawMainMenu()
		Case ECascadeMenuPage.LocalPlay
			DrawLocalMenu()
		Case ECascadeMenuPage.Multiplayer
			DrawMultiplayerMenu()
	End Select
End Function

Function DrawMainMenu()
	SetColor 154, 171, 197
	Local subtitle:String = "A deterministic square and hex strategy game"
	DrawText subtitle, (SCREEN_WIDTH - TextWidth(subtitle)) * 0.5, 145
	DrawMenuButton 275, "1   LOCAL PLAY", 35, 155, 135
	DrawMenuButton 365, "2   MULTIPLAYER", 40, 115, 205
	SetColor 126, 143, 170
	Local hint:String = "Choose how you want to play"
	DrawText hint, (SCREEN_WIDTH - TextWidth(hint)) * 0.5, 490
End Function

Function DrawLocalMenu()
	SetColor 154, 171, 197
	Local heading:String = "LOCAL PLAY  /  SHARE THIS DEVICE"
	DrawText heading, (SCREEN_WIDTH - TextWidth(heading)) * 0.5, 140
	DrawMenuButton 180, "1   SQUARE DUEL", 40, 115, 205
	DrawMenuButton 255, "2   FOUR CORNERS", 150, 86, 205
	DrawMenuButton 330, "3   HEX DUEL", 35, 155, 135
	DrawMenuButton 405, "4   HEX TRIAD", 185, 112, 48
	DrawMenuButton 480, "5   HEX RHOMBUS", 142, 90, 180
	DrawLobbyButton 410, 575, "BACK", 58, 68, 91
	SetColor 126, 143, 170
	Local hint:String = "M: back   or choose a match"
	DrawText hint, (SCREEN_WIDTH - TextWidth(hint)) * 0.5, 654
End Function

Function DrawMultiplayerMenu()
	SetColor 154, 171, 197
	Local heading:String = "MULTIPLAYER"
	DrawText heading, (SCREEN_WIDTH - TextWidth(heading)) * 0.5, 155
	?macos Or ios
	DrawMenuButton 285, "1   QUICK MATCH", 40, 115, 205
	SetColor 145, 163, 191
	Local provider:String = "Find another player through Game Center"
	DrawText provider, (SCREEN_WIDTH - TextWidth(provider)) * 0.5, 370
	?
	?Not macos And Not ios
	SetColor 145, 163, 191
	Local unavailable:String = "No multiplayer provider is available in this build"
	DrawText unavailable, (SCREEN_WIDTH - TextWidth(unavailable)) * 0.5, 315
	?
	If statusText <> "Choose a multiplayer mode" Then
		SetColor 210, 176, 112
		DrawText statusText, (SCREEN_WIDTH - TextWidth(statusText)) * 0.5, 425
	End If
	DrawLobbyButton 410, 500, "BACK", 58, 68, 91
	SetColor 126, 143, 170
	Local hint:String = "Rooms and local-network play are coming next"
	DrawText hint, (SCREEN_WIDTH - TextWidth(hint)) * 0.5, 605
End Function

?macos Or ios
Function DrawOnlinePanel()
	If Not onlineJoined Then
		SetColor 8, 12, 22
		SetAlpha 0.92
		DrawRect 250, 205, 500, 380
		SetAlpha 1.0
		SetColor 235, 241, 250
		DrawText "GAME CENTER QUICK MATCH", 391, 255
		SetColor 224, 233, 247
		DrawText statusText, 500 - TextWidth(statusText) * 0.5, 365
		SetColor 145, 163, 191
		If onlineSession Then
			DrawText "Creating a secure GameNet session", 379, 435
		Else If onlineRequest Then
			DrawText "Matchmaking through Game Center", 388, 435
		Else
			DrawText "Signing in to Game Center", 410, 435
		End If
		DrawLobbyButton 410, 485, "CANCEL", 58, 68, 91
		Return
	End If

	SetColor 8, 12, 22
	SetAlpha 0.92
	DrawRect 160, 170, 680, 450
	SetAlpha 1.0
	SetColor 235, 241, 250
	DrawText "ONLINE LOBBY", 437, 208
	SetColor 95, 160, 245
	DrawOval 300, 252, 48, 48
	SetColor 239, 82, 88
	DrawOval 652, 252, 48, 48
	SetColor 225, 234, 248
	DrawText "PLAYER 1", 285, 310
	DrawText "PLAYER 2", 637, 310
	SetColor 145, 163, 191
	If onlineHost Then
		DrawText "HOST / YOU", 278, 334
		DrawText "GUEST", 649, 334
	Else
		DrawText "HOST", 305, 334
		DrawText "GUEST / YOU", 625, 334
	End If
	Local playerOneState:String = OnlineRoomPlayerState(0)
	Local playerTwoState:String = OnlineRoomPlayerState(1)
	SetColor 145, 163, 191
	DrawText playerOneState, 324 - TextWidth(playerOneState) * 0.5, 358
	DrawText playerTwoState, 676 - TextWidth(playerTwoState) * 0.5, 358

	SetColor 177, 190, 211
	If onlineLobbyConfigReady Then
		Local description:String = LobbyDescription()
		DrawText description, (SCREEN_WIDTH - TextWidth(description)) * 0.5, 417
	Else
		Local waiting:String = "WAITING FOR MATCH SETTINGS"
		DrawText waiting, (SCREEN_WIDTH - TextWidth(waiting)) * 0.5, 417
	End If
	If onlineHost And onlineLobbyConfigReady Then
		DrawRoomButton 210, 405, 100, 52, "<", 58, 68, 91
		DrawRoomButton 690, 405, 100, 52, ">", 58, 68, 91
		SetColor 126, 143, 170
		Local hostHint:String = "You are the host - choose the match"
		DrawText hostHint, (SCREEN_WIDTH - TextWidth(hostHint)) * 0.5, 449
	Else
		SetColor 126, 143, 170
		Local guestHint:String = "The host chooses the match"
		DrawText guestHint, (SCREEN_WIDTH - TextWidth(guestHint)) * 0.5, 449
	End If
	SetColor 224, 233, 247
	DrawText statusText, (SCREEN_WIDTH - TextWidth(statusText)) * 0.5, 478
	If onlineRoom And onlineRoom.IsInRoom(0) And onlineRoom.IsInRoom(1) Then
		DrawLobbyButton 300, 515, "READY", 40, 115, 205
	Else
		DrawLobbyButton 300, 515, "WAITING", 58, 68, 91
	End If
	DrawLobbyButton 520, 515, "LEAVE", 89, 72, 142
End Function

Function OnlineRoomPlayerState:String(player:Int)
	If Not onlineRoom Or Not onlineRoom.IsPresent(player) Then Return "WAITING"
	If onlineRoom.IsReady(player) Then Return "READY"
	If onlineRoom.IsInRoom(player) Then Return "IN LOBBY"
	Return "RESULTS"
End Function
?

Function DrawRoomButton(x:Float, y:Float, width:Float, height:Float, label:String, red:Int, green:Int, blue:Int)
	SetColor red, green, blue
	DrawRect x, y, width, height
	SetColor 255, 255, 255
	DrawText label, x + (width - TextWidth(label)) * 0.5, y + (height - TextHeight(label)) * 0.5
End Function

Function DrawMenuButton(y:Float, label:String, red:Int, green:Int, blue:Int)
	SetColor red, green, blue
	DrawRect 200, y, 600, 60
	SetColor 255, 255, 255
	DrawText label, (SCREEN_WIDTH - TextWidth(label)) * 0.5, y + 21
End Function

Function DrawLobby()
	DrawBackground()
	SetColor 236, 241, 250
	DrawText "LOCAL MATCH", 446, 66
	SetColor 154, 171, 197
	DrawText LobbyDescription(), 385, 108
	DrawText "Tap a player to change colour", 390, 170
	DrawText "Player " + (lobbyConfig.startingPlayer + 1) + " starts", 448, 208

	For Local player:Int = 0 Until lobbyConfig.playerCount
		DrawLobbyPlayer player
	Next

	DrawLobbyButton 200, 575, "BACK", 58, 68, 91
	DrawLobbyButton 620, 575, "START MATCH", 40, 115, 205
	SetColor 126, 143, 170
	DrawText "M: back   Enter: start", 414, 654
End Function

Function LobbyDescription:String()
	Select lobbyConfig.layout
		Case ECascadeBoardLayout.Square
			Return lobbyConfig.size + " x " + lobbyConfig.size + " SQUARE  /  " + lobbyConfig.playerCount + " PLAYERS"
		Case ECascadeBoardLayout.Hexagon
			Return "RADIUS " + lobbyConfig.size + " HEX  /  " + lobbyConfig.playerCount + " PLAYERS"
		Case ECascadeBoardLayout.HexRhombus
			Return lobbyConfig.size + " x " + lobbyConfig.size + " HEX RHOMBUS  /  4 PLAYERS"
	End Select
	Return "CUSTOM MATCH"
End Function

Function DrawLobbyPlayer(player:Int)
	Local x:Float = LobbySlotX(player)
	SetPaletteColor(playerPalette[player])
	SetAlpha 0.18
	DrawRect x, 255, 170, 175
	SetAlpha 1.0
	SetColor 222, 231, 245
	Local playerLabel:String = "PLAYER " + (player + 1)
	DrawText playerLabel, x + (170 - TextWidth(playerLabel)) * 0.5, 276
	SetPaletteColor(playerPalette[player])
	DrawImageRect counterImage, x + 52, 305, 66, 66
	SetColor 255, 255, 255
	Local initial:String = String(player + 1)
	DrawText initial, x + 85 - TextWidth(initial) * 0.5, 330
	SetColor 190, 205, 227
	Local colourName:String = PaletteName(playerPalette[player])
	DrawText colourName, x + (170 - TextWidth(colourName)) * 0.5, 393
End Function

Function DrawLobbyButton(x:Float, y:Float, label:String, red:Int, green:Int, blue:Int)
	SetColor red, green, blue
	DrawRect x, y, 180, 60
	SetColor 255, 255, 255
	DrawText label, x + (180 - TextWidth(label)) * 0.5, y + 22
End Function

Function DrawGame()
	DrawBackground()
	SetColor 235, 240, 249
	DrawText "COUNTER CASCADE", 38, 28
	SetColor 148, 165, 193
	DrawText game.board.identifier.ToUpper(), 38, 55
	?macos Or ios
	If onlineMode Then DrawOnlineIdentity()
	?
	If animationActive Then
		SetColor 245, 211, 105
		DrawText "CASCADE", 463, 42
	Else If game.winner >= 0 Then
		SetPlayerColor(game.winner)
		?macos Or ios
		If onlineMode Then
			If game.winner = OnlineLocalPlayer() Then DrawText "YOU WIN", 462, 42 Else DrawText "OPPONENT WINS", 423, 42
		Else
			DrawText "PLAYER " + (game.winner + 1) + " WINS", 414, 42
		End If
		?
		?Not macos And Not ios
		DrawText "PLAYER " + (game.winner + 1) + " WINS", 414, 42
		?
	Else
		SetPlayerColor(game.currentPlayer)
		?macos Or ios
		If onlineMode Then
			If game.currentPlayer = OnlineLocalPlayer() Then DrawText "IT'S YOUR TURN", 430, 42 Else DrawText "OPPONENT'S TURN", 420, 42
		Else
			DrawText "PLAYER " + (game.currentPlayer + 1) + "'S TURN", 430, 42
		End If
		?
		?Not macos And Not ios
		DrawText "PLAYER " + (game.currentPlayer + 1) + "'S TURN", 430, 42
		?
	End If
	SetColor 148, 165, 193
	DrawText "Turn " + game.turn + "   Topples " + game.lastTopples, 780, 32
	DrawText "M: modes   R: reset", 804, 57

	For Local cell:Int = 0 Until game.board.CellCount()
		If pointerHover And Not animationActive And cell = hoverCell And game.IsLegalMove(game.currentPlayer, cell) Then
			SetColor 245, 211, 105
			SetLineWidth 3
		Else
			SetColor 65, 80, 106
			SetLineWidth 1
		End If
		DrawCellOutline(cell)
		If displayCounters[cell] > 0 Then DrawCounter(cell)
	Next
	DrawCascadeMotion()
	DrawBalanceChart()
	SetLineWidth 1
	SetColor 177, 190, 211
	DrawText statusText, 38, 660
	?macos Or ios
	If onlineMode And onlineDebugText.Length Then
		SetColor 111, 130, 159
		DrawText onlineDebugText, 650, 660
	End If
	?
	If game.winner >= 0 And Not animationActive Then DrawWinnerPanel()
End Function

Function DrawBalanceChart()
	Local totals:Int[CASCADE_MAX_PLAYERS]
	Local combined:Int
	For Local cell:Int = 0 Until displayCounters.Length
		Local player:Int = Int(displayOwners[cell]) - 1
		If player >= 0 And player < lobbyConfig.playerCount Then
			totals[player] :+ displayCounters[cell]
			combined :+ displayCounters[cell]
		End If
	Next
	Local now:Int = MilliSecs()
	If Not balanceInitialized Then
		For Local player:Int = 0 Until lobbyConfig.playerCount
			If combined > 0 Then balanceShares[player] = Float(totals[player]) / Float(combined)
		Next
		balanceInitialized = True
		balanceLastMillis = now
	Else
		Local elapsed:Int = Min(100, Max(0, now - balanceLastMillis))
		Local blend:Float = Min(1.0, Float(elapsed) / 180.0)
		For Local player:Int = 0 Until lobbyConfig.playerCount
			Local target:Float
			If combined > 0 Then target = Float(totals[player]) / Float(combined)
			balanceShares[player] :+ (target - balanceShares[player]) * blend
		Next
		balanceLastMillis = now
	End If

	Local panelX:Float = 856
	Local panelY:Float = 122
	Local panelWidth:Float = 106
	Local panelHeight:Float = 112
	SetColor 8, 12, 22
	SetAlpha 0.78
	DrawRect panelX, panelY, panelWidth, panelHeight
	SetAlpha 1.0
	SetColor 158, 175, 201
	Local title:String = "BALANCE"
	DrawText title, panelX + (panelWidth - TextWidth(title)) * 0.5, panelY + 8

	Local plotX:Float = panelX + 9
	Local plotY:Float = panelY + 31
	Local plotWidth:Float = panelWidth - 18
	Local plotHeight:Float = 54
	Local stepWidth:Float = plotWidth / Float(lobbyConfig.playerCount)
	Local barWidth:Float = Min(14.0, stepWidth - 6.0)
	For Local player:Int = 0 Until lobbyConfig.playerCount
		Local barX:Float = plotX + stepWidth * (Float(player) + 0.5) - barWidth * 0.5
		SetColor 40, 49, 67
		DrawRect barX, plotY, barWidth, plotHeight
		Local height:Float = plotHeight * balanceShares[player]
		If balanceShares[player] > 0.001 Then height = Max(height, 2.0)
		SetPlayerColor player
		DrawRect barX, plotY + plotHeight - height, barWidth, height
		SetColor 185, 198, 220
		Local label:String = String(player + 1)
		DrawText label, barX + (barWidth - TextWidth(label)) * 0.5, plotY + plotHeight + 8
	Next
End Function

?macos Or ios
Function OnlineLocalPlayer:Int()
	If onlineRoom And onlineRoom.LocalPlayer() >= 0 Then Return onlineRoom.LocalPlayer()
	If onlineHost Then Return 0 Else Return 1
End Function

Function DrawOnlineIdentity()
	Local player:Int = OnlineLocalPlayer()
	SetColor 8, 12, 22
	SetAlpha 0.78
	DrawRect 748, 72, 214, 34
	SetAlpha 1.0
	SetPlayerColor player
	DrawImageRect counterImage, 758, 79, 20, 20
	SetColor 236, 242, 251
	Local label:String = "YOU: " + PaletteName(playerPalette[player]) + "  /  PLAYER " + (player + 1)
	DrawText label, 788, 81
End Function
?

Function DrawBackground()
	SetColor 255, 255, 255
	SetAlpha 0.82
	If background Then
		Local sourceWidth:Float = Float(background.height) * Float(SCREEN_WIDTH) / Float(SCREEN_HEIGHT)
		Local sourceX:Float = (Float(background.width) - sourceWidth) * 0.5
		DrawSubImageRect background, 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, sourceX, 0, sourceWidth, background.height
	End If
	SetAlpha 1.0
End Function

Function DrawCellOutline(cell:Int)
	For Local corner:Int = 0 Until viewGrid.CornerCount()
		Local x0:Double, y0:Double, x1:Double, y1:Double
		viewGrid.CellCorner(game.board.cells[cell].column, game.board.cells[cell].row, corner, x0, y0)
		viewGrid.CellCorner(game.board.cells[cell].column, game.board.cells[cell].row, (corner + 1) Mod viewGrid.CornerCount(), x1, y1)
		DrawLine Float(x0) + boardX, Float(y0) + boardY, Float(x1) + boardX, Float(y1) + boardY, False
	Next
End Function

Function DrawCounter(cell:Int)
	Local x:Double, y:Double
	viewGrid.CellCenter(game.board.cells[cell].column, game.board.cells[cell].row, x, y)
	x :+ boardX
	y :+ boardY
	Local player:Int = Int(displayOwners[cell]) - 1
	Local ready:Int = displayCounters[cell] >= game.board.routeCount - 1
	Local scaleX:Float = 1.0
	Local scaleY:Float = 1.0
	If ready Then
		Local phase:Float = Float(MilliSecs()) * 0.48 + Float(cell * 47)
		x :+ Sin(phase) * 1.35
		y :+ Sin(phase * 1.71) * 0.55
		scaleX :+ Sin(phase * 1.13) * 0.035
		scaleY :- Sin(phase * 1.13) * 0.030
	End If
	SetPlayerColor(player)
	SetAlpha 0.20
	DrawImageRect counterImage, Float(x - 27 * scaleX), Float(y - 27 * scaleY), 54 * scaleX, 54 * scaleY
	SetAlpha 1.0
	SetPlayerColor(player)
	DrawImageRect counterImage, Float(x - 21 * scaleX), Float(y - 21 * scaleY), 42 * scaleX, 42 * scaleY
	DrawCounterPips(Float(x), Float(y), displayCounters[cell], scaleX, scaleY)
End Function

Function DrawCounterPips(x:Float, y:Float, count:Int, scaleX:Float, scaleY:Float)
	SetColor 248, 251, 255
	Select count
		Case 1
			DrawCounterPip x, y
		Case 2
			DrawCounterPip x - 6 * scaleX, y - 6 * scaleY
			DrawCounterPip x + 6 * scaleX, y + 6 * scaleY
		Case 3
			DrawCounterPip x - 7 * scaleX, y - 7 * scaleY
			DrawCounterPip x, y
			DrawCounterPip x + 7 * scaleX, y + 7 * scaleY
		Case 4
			DrawCounterPip x - 7 * scaleX, y - 7 * scaleY
			DrawCounterPip x + 7 * scaleX, y - 7 * scaleY
			DrawCounterPip x - 7 * scaleX, y + 7 * scaleY
			DrawCounterPip x + 7 * scaleX, y + 7 * scaleY
		Case 5
			DrawCounterPip x - 8 * scaleX, y - 8 * scaleY
			DrawCounterPip x + 8 * scaleX, y - 8 * scaleY
			DrawCounterPip x, y
			DrawCounterPip x - 8 * scaleX, y + 8 * scaleY
			DrawCounterPip x + 8 * scaleX, y + 8 * scaleY
		Case 6
			For Local row:Int = -1 To 1
				DrawCounterPip x - 7 * scaleX, y + row * 8 * scaleY
				DrawCounterPip x + 7 * scaleX, y + row * 8 * scaleY
			Next
		Case 7
			DrawCounterPipSized x, y, 5.5
			For Local index:Int = 0 Until 6
				Local angle:Float = -90.0 + Float(index) * 60.0
				DrawCounterPipSized Float(x + Cos(angle) * 10.5 * scaleX), Float(y + Sin(angle) * 10.5 * scaleY), 5.5
			Next
		Case 8
			For Local index:Int = 0 Until 8
				Local angle:Float = -90.0 + Float(index) * 45.0
				DrawCounterPipSized Float(x + Cos(angle) * 10.5 * scaleX), Float(y + Sin(angle) * 10.5 * scaleY), 5.0
			Next
		Default
			DrawDenseCounterPips x, y, count, scaleX, scaleY
	End Select
End Function

Function DrawCounterPip(x:Float, y:Float)
	DrawCounterPipSized x, y, 7.0
End Function

Function DrawCounterPipSized(x:Float, y:Float, size:Float)
	DrawImageRect counterImage, x - size * 0.5, y - size * 0.5, size, size
End Function

' Cascades can temporarily accumulate more than the stable limit in a cell.
' Keep representing the actual count with compact pips instead of falling back
' to a digit, even for unusual crowded-board states.
Function DrawDenseCounterPips(x:Float, y:Float, count:Int, scaleX:Float, scaleY:Float)
	Local columns:Int = 3
	While columns * columns < count
		columns :+ 1
	Wend
	Local rows:Int = (count + columns - 1) / columns
	Local spacing:Float = Min(6.5, 26.0 / Float(Max(columns - 1, rows - 1)))
	Local pipSize:Float = Max(2.0, Min(4.8, spacing * 0.68))
	Local drawn:Int
	For Local row:Int = 0 Until rows
		Local inRow:Int = Min(columns, count - drawn)
		Local rowWidth:Float = Float(inRow - 1) * spacing
		For Local column:Int = 0 Until inRow
			Local px:Float = x + (Float(column) * spacing - rowWidth * 0.5) * scaleX
			Local py:Float = y + (Float(row) - Float(rows - 1) * 0.5) * spacing * scaleY
			DrawCounterPipSized px, py, pipSize
			drawn :+ 1
		Next
	Next
End Function

Function DrawWinnerPanel()
	SetColor 8, 12, 22
	SetAlpha 0.90
	DrawRect 290, 235, 420, 230
	SetAlpha 1.0
	SetPlayerColor(game.winner)
	DrawText "PLAYER " + (game.winner + 1) + " WINS", 425, 285
	SetColor 163, 180, 207
	DrawText "The last colour on the board", 390, 323
	?macos Or ios
	If onlineMode Then
		DrawActionButton 330, 365, "RETURN TO LOBBY", 40, 115, 205
		DrawActionButton 510, 365, "LEAVE", 89, 72, 142
	Else
		DrawActionButton 330, 365, "PLAY AGAIN", 40, 115, 205
		DrawActionButton 510, 365, "MODES", 89, 72, 142
	End If
	?
	?Not macos And Not ios
	DrawActionButton 330, 365, "PLAY AGAIN", 40, 115, 205
	DrawActionButton 510, 365, "MODES", 89, 72, 142
	?
End Function

Function DrawActionButton(x:Float, y:Float, label:String, red:Int, green:Int, blue:Int)
	SetColor red, green, blue
	DrawRect x, y, 160, 56
	SetColor 255, 255, 255
	DrawText label, x + (160 - TextWidth(label)) * 0.5, y + 20
End Function

Function DrawCascadeMotion()
	If Not animationActive Or Not animationStarted Or animationIndex >= eventLog.count Then Return
	Local event:SCascadeEvent = eventLog.events[animationIndex]
	If event.kind = ECascadeEventKind.Placed Then
		Local x:Double, y:Double
		CellCentre(event.cell, x, y)
		Local progress:Float = Min(1.0, Float(Int(MilliSecs() - animationStartMillis)) / 90.0)
		SetPlayerColor(event.player)
		SetAlpha(1.0 - progress)
		Local radius:Float = 22.0 + progress * 20.0
		SetLineWidth 3
		DrawOval Float(x) - radius, Float(y) - radius, radius * 2.0, radius * 2.0
		SetLineWidth 1
		SetAlpha 1.0
		Return
	End If
	If event.kind <> ECascadeEventKind.Toppled Then Return
	Local sourceX:Double, sourceY:Double
	CellCentre(event.cell, sourceX, sourceY)
	Local progress:Float = Min(1.0, Float(Int(MilliSecs() - animationStartMillis)) / Float(cascadeStepMillis))
	progress = progress * progress * (3.0 - 2.0 * progress)
	For Local direction:Int = 1 To game.board.routeCount
		If animationIndex + direction >= eventLog.count Then Exit
		Local landing:SCascadeEvent = eventLog.events[animationIndex + direction]
		If landing.kind <> ECascadeEventKind.Landed Or landing.source <> event.cell Then Exit
		Local destinationX:Double, destinationY:Double
		CellCentre(landing.cell, destinationX, destinationY)
		Local x:Float = Float(sourceX + (destinationX - sourceX) * progress)
		Local y:Float = Float(sourceY + (destinationY - sourceY) * progress)
		SetPlayerColor(event.player)
		SetAlpha 0.2
		DrawImageRect counterImage, x - 13, y - 13, 26, 26
		SetAlpha 1.0
		SetPlayerColor(event.player)
		DrawImageRect counterImage, x - 8, y - 8, 16, 16
	Next
	SetAlpha 1.0
End Function

' Build the neutral counter at a much higher resolution than it is displayed.
' Filtering and mipmaps then preserve a smooth silhouette on Retina displays,
' while SetColor supplies the player's colour at draw time.
Function CreateCounterImage:TImage(flags:Int)
	Const SIZE:Int = 256
	Const CENTRE:Float = 127.5
	Const RADIUS:Float = 106.0
	Local pixmap:TPixmap = CreatePixmap(SIZE, SIZE, PF_RGBA8888)
	For Local py:Int = 0 Until SIZE
		For Local px:Int = 0 Until SIZE
			Local dx:Float = Float(px) - CENTRE
			Local dy:Float = Float(py) - CENTRE
			Local distance:Float = Sqr(dx * dx + dy * dy)
			Local coverage:Float = Min(1.0, Max(0.0, RADIUS + 0.75 - distance))
			If coverage > 0.0 Then
				Local shade:Float = 0.88 + 0.10 * (1.0 - (dy + RADIUS) / (RADIUS * 2.0))
				If distance > RADIUS - 14.0 Then shade :* 0.72
				Local highlightDistance:Float = Sqr((dx + 31.0) * (dx + 31.0) + (dy + 37.0) * (dy + 37.0))
				If highlightDistance < 25.0 Then shade = Min(1.0, shade + (25.0 - highlightDistance) / 170.0)
				Local alpha:Int = Min(255, Max(0, Int(coverage * 255.0)))
				Local grey:Int = Min(255, Max(0, Int(shade * 255.0)))
				pixmap.WritePixel(px, py, (alpha Shl 24) | (grey Shl 16) | (grey Shl 8) | grey)
			End If
		Next
	Next
	Return LoadImage(pixmap, flags)
End Function

Function CellCentre(cell:Int, x:Double Var, y:Double Var)
	viewGrid.CellCenter(game.board.cells[cell].column, game.board.cells[cell].row, x, y)
	x :+ boardX
	y :+ boardY
End Function

Function SetPlayerColor(player:Int)
	If player < 0 Or player >= CASCADE_MAX_PLAYERS Then
		SetColor 180, 190, 205
		Return
	End If
	SetPaletteColor playerPalette[player]
End Function

Function SetPaletteColor(index:Int)
	Select index
		Case 0
			SetColor 55, 145, 245
		Case 1
			SetColor 242, 91, 91
		Case 2
			SetColor 67, 190, 119
		Case 3
			SetColor 218, 151, 45
		Case 4
			SetColor 166, 92, 224
		Case 5
			SetColor 40, 190, 194
		Default
			SetColor 180, 190, 205
	End Select
End Function

Function PaletteName:String(index:Int)
	Select index
		Case 0
			Return "BLUE"
		Case 1
			Return "RED"
		Case 2
			Return "GREEN"
		Case 3
			Return "AMBER"
		Case 4
			Return "PURPLE"
		Case 5
			Return "CYAN"
	End Select
	Return "COLOUR"
End Function
