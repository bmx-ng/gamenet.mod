SuperStrict

Framework Max2D.SDL3RenderMax2D
Import Apple.GameKit
Import GameNet.GameKit
Import GameNet.Session
Import GameNet.Match
Import GameNet.Lifecycle
Import GameNet.RollbackSession
Import SDL3.SDL3System
Import Max2D.VirtualJoystick
Import BRL.PolledInput
Import BRL.StandardIO

Include "protocol.bmx"

Const SIMULATION_HZ:Int = 60
Const SIMULATION_STEP:Double = 1.0 / Double(SIMULATION_HZ)
Const MAX_STEPS_PER_RENDER:Int = 8
Const MAX_ACCUMULATED_TIME:Double = 0.25
Const INPUT_DELAY_FRAMES:Int = 6
Const MAX_PREDICTION_LEAD:Int = 18
Const ROLLBACK_HISTORY:Int = 240
Const HASH_INTERVAL:UInt = 30
Const HASH_QUEUE_SIZE:Int = 32

Global gameCenter:TGameCenter = TGameCenter.Shared()
Global pendingMatch:TGameCenterMatch
Global transport:TGameKitTransport
Global session:TNetSession
Global matchLifecycle:TMatchLifecycle
Global remotePeer:SNetPeer
Global simulation:TReboundSimulation
Global rollbackGame:TRollbackSession
Global localPlayer:Int = -1
Global sessionHost:Int
Global joined:Int
Global statusText:String = "Starting Game Center..."
Global detailText:String = ""
Global opponentName:String = ""
Global inputBuffer:Byte[REBOUND_INPUT_SIZE]
Global packetBuffer:Byte[900]
Global lastInputSend:Int
Global confirmedEffects:Int
Global lastEffectText:String = ""
Global effectFlash:Int
Global searching:Int
Global stalledRenders:Int
Global multiStepRenders:Int
Global maximumStepsPerRender:Int
Global previousPower:Int
Global appLifecycle:TAppLifecycle = TAppLifecycle.Create()
Global resumeAction:EAppResumeAction
Global resumePending:Int
Global waitingForStateSync:Int
Global resumeDecisionAt:UInt
Global recoveryStartedAt:UInt
Global lastRecoveryRequestAt:UInt

Function ErrorText:String(error:TGameCenterError)
	If Not error Then Return ""
	Return error.domain + " (" + error.code + "): " + error.message
End Function

Function FixedToFloat:Float(value:Int)
	Return Float(value) / Float(REBOUND_SCALE)
End Function

Function SetLocalMatchPaused(paused:Int, now:UInt)
	If matchLifecycle And (matchLifecycle.Phase() = EMatchPhase.Running Or matchLifecycle.Phase() = EMatchPhase.Paused) Then
		matchLifecycle.SetLocalPaused(paused, now)
	End If
End Function

Function ApplicationLifecycle(data:Object, event:Int)
	Local now:UInt = UInt(MilliSecs())
	Select event
		Case SDL_EVENT_WILL_ENTER_BACKGROUND
			If appLifecycle.SuspendAt(now) Then
				' Give the shared lifecycle its best opportunity to pause every player.
				SetLocalMatchPaused(True, now)
				If session Then session.SuspendAt(now)
			End If
		Case SDL_EVENT_DID_ENTER_FOREGROUND
			If appLifecycle.IsSuspended() Then
				If session Then session.ResumeAt(now)
				Local connected:Int = True
				If session Then connected = session.IsOpen()
				resumeAction = appLifecycle.ResumeAt(now, connected)
				resumePending = True
				resumeDecisionAt = now + 500
			End If
		Case SDL_EVENT_TERMINATING
			appLifecycle.Terminate()
	End Select
End Function

Function LeaveStaleMatch(reason:String)
	If rollbackGame Then rollbackGame.Stop()
	If session Then session.Close()
	session = Null
	transport = Null
	matchLifecycle = Null
	remotePeer = New SNetPeer
	joined = False
	waitingForStateSync = False
	lastRecoveryRequestAt = 0
	statusText = reason
	detailText = "Find a new match to continue"
End Function

Function ProcessApplicationResume(now:UInt)
	If waitingForStateSync Then
		If rollbackGame And Not rollbackGame.NeedsStateSync() Then
			waitingForStateSync = False
			lastRecoveryRequestAt = 0
			SetLocalMatchPaused(False, now)
			statusText = "Rebound match running"
			detailText = "Recovered after returning to the game"
		Else If now - recoveryStartedAt >= 5000 Then
			LeaveStaleMatch("Could not resynchronise the match")
			Return
		End If
	End If
	If Not resumePending Then Return
	If session And Not joined Then resumeAction = EAppResumeAction.Reconnect
	If resumeAction = EAppResumeAction.Resynchronise Then
		' The authority's replicated pause proves both simulations stopped. It is
		' safer and quicker to resume that agreed timeline than replace its state.
		If matchLifecycle And matchLifecycle.Phase() = EMatchPhase.Paused And matchLifecycle.PlayerPaused(localPlayer) Then
			resumeAction = EAppResumeAction.Continue
		Else If Int(now - resumeDecisionAt) < 0 Then
			statusText = "Restoring match..."
			Return
		End If
	End If
	resumePending = False
	Select resumeAction
		Case EAppResumeAction.Continue
			SetLocalMatchPaused(False, now)
		Case EAppResumeAction.Resynchronise
			If rollbackGame And rollbackGame.IsRunning() And Not rollbackGame.IsAuthority() And rollbackGame.RequestStateSync() Then
				waitingForStateSync = True
				recoveryStartedAt = now
				lastRecoveryRequestAt = 0
				statusText = "Resynchronising after interruption..."
			Else
				' The authority remains canonical if the shared pause reached its peer.
				SetLocalMatchPaused(False, now)
			End If
		Case EAppResumeAction.Reconnect
			LeaveStaleMatch("Connection interrupted")
		Case EAppResumeAction.Leave
			LeaveStaleMatch("Match left after a long interruption")
	End Select
End Function

Function ConfirmedFrameText:String(game:TRollbackSession)
	If Not game Or Not game.HasConfirmedFrame() Then Return "none"
	Return String(game.ConfirmedFrame())
End Function

Function StartRollbackGame(seed:UInt)
	If rollbackGame Then rollbackGame.Stop()
	simulation = New TReboundSimulation
	simulation.Reset(seed)
	Local config:SRollbackSessionConfig = New SRollbackSessionConfig(REBOUND_PLAYER_COUNT, localPlayer, ROLLBACK_HISTORY, REBOUND_STATE_SIZE, REBOUND_INPUT_SIZE, INPUT_DELAY_FRAMES, MAX_PREDICTION_LEAD, REBOUND_INPUT_BATCH_MAX, HASH_INTERVAL, HASH_QUEUE_SIZE, 4, 1, 64, 0)
	rollbackGame = TRollbackSession.Create(simulation, config)
	Local inputLength:Size_T = EncodeReboundInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), 0, False)
	If Not rollbackGame Or Not rollbackGame.Start(Byte Ptr(inputBuffer), inputLength) Then
		statusText = "Could not start rollback simulation"
		rollbackGame = Null
		Return
	End If
	confirmedEffects = 0
	lastEffectText = ""
	effectFlash = 0
	stalledRenders = 0
	multiStepRenders = 0
	maximumStepsPerRender = 0
	statusText = "Rebound match running"
	detailText = "You are player " + (localPlayer + 1) + " - " + opponentName + " is your opponent"
End Function

Function ProcessMatchLifecycle(now:Int)
	If Not matchLifecycle Then Return
	matchLifecycle.UpdateAt(UInt(now))
	Local event:SMatchEvent
	While matchLifecycle.Poll(event)
		Select event.Kind()
			Case EMatchEventKind.CountdownStarted
				statusText = "Both players ready"
				detailText = "Round " + event.Round() + " begins shortly"
			Case EMatchEventKind.Started
				StartRollbackGame(event.Seed())
			Case EMatchEventKind.Paused
				statusText = "Match paused"
			Case EMatchEventKind.Resumed
				statusText = "Rebound match running"
			Case EMatchEventKind.Finished
				statusText = "Round complete"
				detailText = "Press POWER when you are ready for a rematch"
			Case EMatchEventKind.Aborted
				statusText = "Match ended"
				If rollbackGame Then rollbackGame.Stop()
		End Select
	Wend
	If matchLifecycle.IsAuthority() And (matchLifecycle.Phase() = EMatchPhase.Waiting Or matchLifecycle.Phase() = EMatchPhase.Finished) And matchLifecycle.AllReady() Then
		Local seed:UInt = UInt(now) ~ $9e3779b9:UInt ~ matchLifecycle.Round()
		If matchLifecycle.BeginMatch(seed, 0, 750, UInt(now)) <> ETransportResult.Ok Then statusText = "Could not begin the match"
	End If
End Function

Type TReboundListener Implements IGameCenterListener, IGameCenterMultiplayerListener
	Method OnGameCenterAuthenticationChanged(authenticated:Int, player:TGameCenterPlayer, error:TGameCenterError)
		If error Then
			statusText = "Authentication failed"
			detailText = ErrorText(error)
		Else If authenticated Then
			statusText = "Welcome, " + player.displayName
			detailText = "Find another player to begin"
		Else
			statusText = "Game Center is not authenticated"
			detailText = "Sign in to Game Center in Settings"
		End If
	End Method

	Method OnGameCenterMatchFound(requestId:Int, match:TGameCenterMatch, error:TGameCenterError)
		searching = False
		If error Then
			statusText = "Matchmaking failed"
			detailText = ErrorText(error)
		Else
			pendingMatch = match
			statusText = "Match found"
			detailText = "Waiting for the other player..."
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

Function BeginNetworkSession()
	If Not pendingMatch Or pendingMatch.ExpectedPlayerCount() <> 0 Or pendingMatch.PlayerCount() <> 1 Then Return
	Local other:TGameCenterPlayer = pendingMatch.Player(1)
	If Not other Or Not gameCenter.localPlayer Then Return
	opponentName = other.displayName
	sessionHost = gameCenter.localPlayer.gamePlayerId < other.gamePlayerId
	localPlayer = 1
	If sessionHost Then localPlayer = 0
	transport = TGameKitTransport.Create(pendingMatch, 1, 2, 900)
	If Not transport Then
		statusText = "Could not create GameKit transport"
		Return
	End If
	If sessionHost Then
		session = TNetSession.CreateHost(transport, REBOUND_APP_ID, REBOUND_APP_VERSION, 1, 900)
		statusText = "Connected; preparing the match"
	Else
		session = TNetSession.CreateClient(transport, REBOUND_APP_ID, REBOUND_APP_VERSION, Null, 0, 1, 900)
		statusText = "Connected; joining the match"
	End If
	If session Then
		session.ConfigureHealth(New SSessionHealthConfig(10000, 15000, 500, 2000))
		matchLifecycle = TMatchLifecycle.Create(session, New SMatchLifecycleConfig(REBOUND_PLAYER_COUNT, localPlayer, 0, REBOUND_MSG_MATCH_COMMAND, REBOUND_MSG_MATCH_STATE, REBOUND_CONTROL_CHANNEL, 32))
		If Not matchLifecycle Then statusText = "Could not create match lifecycle"
	End If
	pendingMatch = Null
End Function

Function PollNetwork(now:Int)
	If Not session Then Return
	Local event:SSessionEvent
	While session.PollAt(event, UInt(now))
		Select event.Kind()
			Case ESessionEventKind.JoinRequested
				If session.Accept(event.Peer()) <> ETransportResult.Ok Then statusText = "Could not accept opponent"
			Case ESessionEventKind.Joined
				remotePeer = event.Peer()
				joined = True
				statusText = "GameNet session joined; getting ready"
				Local lifecycleResult:ETransportResult
				If sessionHost Then
					lifecycleResult = matchLifecycle.PlayerJoined(1, remotePeer, UInt(now))
				Else If Not matchLifecycle.BindPlayer(0, remotePeer) Then
					lifecycleResult = ETransportResult.InvalidPeer
				End If
				If lifecycleResult = ETransportResult.Ok Then lifecycleResult = matchLifecycle.SetLocalReady(True, UInt(now))
				If lifecycleResult <> ETransportResult.Ok Then statusText = "Could not join the match lifecycle"
			Case ESessionEventKind.Message
				Select event.MessageType()
					Case REBOUND_MSG_MATCH_COMMAND, REBOUND_MSG_MATCH_STATE
						If Not matchLifecycle.ReceiveAt(event.Peer(), event.MessageType(), event.Payload(), UInt(now)) Then statusText = "Invalid match lifecycle message"
					Case REBOUND_MSG_INPUT
						If rollbackGame And rollbackGame.IsRunning() Then rollbackGame.ReceiveInputs(1 - localPlayer, event.Payload())
					Case REBOUND_MSG_HASH
						If rollbackGame And rollbackGame.IsRunning() Then rollbackGame.ReceiveHash(1 - localPlayer, event.Payload())
					Case REBOUND_MSG_STATE_SYNC_REQUEST
						If rollbackGame And rollbackGame.IsRunning() And rollbackGame.IsAuthority() Then rollbackGame.SendStateSyncResponse(session, remotePeer, REBOUND_MSG_STATE_SYNC_RESPONSE, REBOUND_CONTROL_CHANNEL, event.Payload(), Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
					Case REBOUND_MSG_STATE_SYNC_RESPONSE
						If rollbackGame And rollbackGame.IsRunning() Then rollbackGame.ReceiveStateSync(event.Payload())
				End Select
			Case ESessionEventKind.Left
				If matchLifecycle Then matchLifecycle.PlayerLeft(1 - localPlayer, event.Code(), UInt(now))
				joined = False
				statusText = "The other player left"
				detailText = "Restart the example to find another match"
				If rollbackGame Then rollbackGame.Stop()
			Case ESessionEventKind.Rejected
				statusText = "Session rejected (" + event.Code() + ")"
			Case ESessionEventKind.Error
				statusText = "Session error (" + event.Code() + ", detail " + Int(session.LastProtocolError()) + ")"
		End Select
	Wend
	If rollbackGame And rollbackGame.IsRunning() And rollbackGame.NeedsStateSync() Then
		If lastRecoveryRequestAt = 0 Or UInt(now) - lastRecoveryRequestAt >= 1000 Then
			Local length:Size_T = rollbackGame.WriteStateSyncRequest(Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
			If length > 0 And session.Send(remotePeer, REBOUND_MSG_STATE_SYNC_REQUEST, REBOUND_CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(packetBuffer), length) = ETransportResult.Ok Then lastRecoveryRequestAt = UInt(now)
		End If
	End If
End Function

Function ProcessConfirmedEffects()
	If Not rollbackGame Then Return
	Local effect:SRollbackEffect
	While rollbackGame.PollConfirmedEffect(effect)
		confirmedEffects :+ 1
		effectFlash = 8
		Local player:Int
		If effect.Payload().Length() = 1 Then player = Int(effect.Payload().Data()[0])
		Select effect.Kind()
			Case REBOUND_EFFECT_PADDLE
				lastEffectText = "Player " + (player + 1) + " returned the pulse"
			Case REBOUND_EFFECT_POWER
				lastEffectText = "Player " + (player + 1) + " used a POWER RETURN"
			Case REBOUND_EFFECT_SCORE
				lastEffectText = "Player " + (player + 1) + " broke a shield"
			Case REBOUND_EFFECT_WIN
				lastEffectText = "Player " + (player + 1) + " destroyed the core"
				If matchLifecycle And matchLifecycle.IsAuthority() And matchLifecycle.Phase() = EMatchPhase.Running Then
					matchLifecycle.Finish(player, 0, UInt(MilliSecs()))
				End If
		End Select
	Wend
End Function

Function DrawArena()
	SetColor 17, 25, 43
	DrawRect 0, 0, REBOUND_WORLD_WIDTH, REBOUND_WORLD_HEIGHT
	SetColor 29, 45, 70
	For Local y:Int = 18 Until REBOUND_WORLD_HEIGHT Step 28
		DrawRect REBOUND_WORLD_WIDTH / 2 - 2, y, 4, 14
	Next
	SetColor 80, 105, 145
	DrawRect 330, 105, 140, 16
	DrawRect 330, 329, 140, 16
	SetColor 40, 58, 88
	DrawRect 337, 110, 126, 6
	DrawRect 337, 334, 126, 6
End Function

Function DrawDefences(player:Int)
	Local opponentScore:Int = simulation.Score(1 - player)
	For Local index:Int = 0 Until REBOUND_WIN_SCORE
		If index < REBOUND_WIN_SCORE - opponentScore Then
			If player = localPlayer Then SetColor 49, 190, 238 Else SetColor 246, 94, 102
		Else
			SetColor 31, 38, 57
		End If
		Local x:Int = 13
		If player = 1 Then x = REBOUND_WORLD_WIDTH - 25
		DrawRect x, 72 + index * 62, 12, 44
	Next
	If player = localPlayer Then SetColor 120, 225, 255 Else SetColor 255, 150, 155
	Local coreX:Int = 2
	If player = 1 Then coreX = REBOUND_WORLD_WIDTH - 10
	DrawRect coreX, REBOUND_WORLD_HEIGHT / 2 - 36, 8, 72
End Function

Function DrawGame()
	If Not simulation Then Return
	DrawDefences(0)
	DrawDefences(1)
	For Local player:Int = 0 Until REBOUND_PLAYER_COUNT
		If player = localPlayer Then SetColor 48, 192, 240 Else SetColor 245, 84, 98
		Local x:Float = FixedToFloat(REBOUND_LEFT_X - REBOUND_PADDLE_WIDTH / 2)
		If player = 1 Then x = FixedToFloat(REBOUND_RIGHT_X - REBOUND_PADDLE_WIDTH / 2)
		Local y:Float = FixedToFloat(simulation.PaddlePosition(player) - REBOUND_PADDLE_HEIGHT / 2)
		DrawRect x, y, FixedToFloat(REBOUND_PADDLE_WIDTH), FixedToFloat(REBOUND_PADDLE_HEIGHT)
	Next
	If effectFlash > 0 Then SetColor 255, 255, 255 Else SetColor 255, 220, 80
	Local ballRadius:Float = FixedToFloat(REBOUND_BALL_RADIUS)
	DrawOval FixedToFloat(simulation.BallX()) - ballRadius, FixedToFloat(simulation.BallY()) - ballRadius, ballRadius * 2, ballRadius * 2

	For Local player:Int = 0 Until REBOUND_PLAYER_COUNT
		Local x:Int = 80
		If player = 1 Then x = REBOUND_WORLD_WIDTH - 280
		SetColor 30, 38, 56
		DrawRect x, REBOUND_WORLD_HEIGHT - 27, 200, 11
		If player = localPlayer Then SetColor 45, 187, 235 Else SetColor 240, 80, 94
		DrawRect x, REBOUND_WORLD_HEIGHT - 27, 2 * simulation.Power(player), 11
	Next

	SetColor 245, 248, 255
	DrawText simulation.Score(0), 300, 18
	DrawText simulation.Score(1), 486, 18
	If simulation.ServeFrames() > 0 And simulation.Winner() < 0 Then
		DrawText "GET READY", 360, 205
	End If
	If simulation.Winner() >= 0 Then
		SetColor 8, 12, 22
		DrawRect 205, 150, 390, 150
		If simulation.Winner() = localPlayer Then SetColor 80, 230, 150 Else SetColor 255, 105, 115
		Local result:String = "OPPONENT WINS"
		If simulation.Winner() = localPlayer Then result = "YOU WIN"
		DrawText result, 350, 177
		SetColor 245, 248, 255
		DrawText "Press POWER to ready for a rematch", 270, 220
		Local readyText:String = "You: waiting    Opponent: waiting"
		If matchLifecycle And matchLifecycle.PlayerReady(localPlayer) Then readyText = "You: READY    Opponent: waiting"
		If matchLifecycle And matchLifecycle.PlayerReady(1 - localPlayer) Then readyText = "You: waiting    Opponent: READY"
		If matchLifecycle And matchLifecycle.AllReady() Then readyText = "Both players ready"
		DrawText readyText, 288, 252
	End If
End Function

?ios
Graphics 1280, 720, 32, 0, GRAPHICS_FULLSCREEN_DESKTOP
?Not ios
Graphics 1280, 720
?
SetVirtualResolution(REBOUND_WORLD_WIDTH, REBOUND_WORLD_HEIGHT, VIRTUAL_LETTERBOX)
SetVirtualBarColor 5, 8, 15
SetClsColor 17, 25, 43
SetLifecycleCallback(ApplicationLifecycle)

Local controls:TVirtualJoystick = TVirtualJoystick.Create(3, "Rebound controls")
controls.SetStickEnabled(False)
controls.SetButtonLabel(0, "UP")
controls.SetButtonLabel(1, "DOWN")
controls.SetButtonLabel(2, "POWER")
Local safeX:Int, safeY:Int, safeWidth:Int, safeHeight:Int
GetWindowSafeArea(safeX, safeY, safeWidth, safeHeight)
If safeWidth <= 0 Or safeHeight <= 0 Then
	safeWidth = GraphicsWidth()
	safeHeight = GraphicsHeight()
End If
Local controlScale:Float = Max(0.68, Min(1.8, Float(Min(safeWidth, safeHeight)) / 720.0))
Local controlEdge:Float = 42.0 * controlScale
Local moveRadius:Float = 58.0 * controlScale
Local moveX:Float = safeX + controlEdge + moveRadius
Local downY:Float = safeY + safeHeight - controlEdge - moveRadius
controls.SetButton(1, moveX, downY, moveRadius)
controls.SetButton(0, moveX, downY - moveRadius * 2.0 - 18.0 * controlScale, moveRadius)
Local powerRadius:Float = 62.0 * controlScale
controls.SetButton(2, safeX + safeWidth - controlEdge - powerRadius, safeY + safeHeight - controlEdge - powerRadius, powerRadius)
Local accumulator:Double
Local previousTime:Int = MilliSecs()

gameCenter.Start(New TReboundListener)

While Not AppTerminate() And Not KeyDown(KEY_ESCAPE)
	Local now:Int = MilliSecs()
	Local elapsed:Int = Min(250, Max(0, now - previousTime))
	previousTime = now
	BeginNetworkSession()
	PollNetwork(now)
	ProcessMatchLifecycle(now)
	ProcessApplicationResume(UInt(now))

	Local movement:Int
	If controls.ButtonDown(0) Or KeyDown(KEY_W) Or KeyDown(KEY_UP) Then movement :- 127
	If controls.ButtonDown(1) Or KeyDown(KEY_S) Or KeyDown(KEY_DOWN) Then movement :+ 127
	Local power:Int = controls.ButtonDown(2) Or KeyDown(KEY_SPACE)
	Local powerPressed:Int = power And Not previousPower
	previousPower = power
	If powerPressed And matchLifecycle And matchLifecycle.Phase() = EMatchPhase.Finished And Not matchLifecycle.PlayerReady(localPlayer) Then
		If matchLifecycle.SetLocalReady(True, UInt(now)) <> ETransportResult.Ok Then statusText = "Could not ready for rematch"
	End If

	If rollbackGame And rollbackGame.IsRunning() And matchLifecycle And matchLifecycle.Phase() = EMatchPhase.Running Then
		accumulator = Min(MAX_ACCUMULATED_TIME, accumulator + Double(elapsed) / 1000.0)
		Local steps:Int
		While accumulator >= SIMULATION_STEP And steps < MAX_STEPS_PER_RENDER
			If Not rollbackGame.CanStep() Then
				stalledRenders :+ 1
				Exit
			End If
			accumulator :- SIMULATION_STEP
			steps :+ 1
			Local inputLength:Size_T = EncodeReboundInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), movement, power)
			If Not rollbackGame.Step(Byte Ptr(inputBuffer), inputLength) Then Exit
			rollbackGame.SendInputs(session, remotePeer, REBOUND_MSG_INPUT, REBOUND_GAMEPLAY_CHANNEL, Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
			rollbackGame.SendReadyHash(session, remotePeer, REBOUND_MSG_HASH, REBOUND_CONTROL_CHANNEL, Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
			lastInputSend = now
		Wend
		If steps > 1 Then multiStepRenders :+ 1
		maximumStepsPerRender = Max(maximumStepsPerRender, steps)
		If now - lastInputSend >= 50 Then
			rollbackGame.SendInputs(session, remotePeer, REBOUND_MSG_INPUT, REBOUND_GAMEPLAY_CHANNEL, Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
			lastInputSend = now
		End If
		If rollbackGame.Failed() Then statusText = "Rollback failed (" + Int(rollbackGame.FailureReason()) + ")"
	Else
		accumulator = 0.0
	End If
	ProcessConfirmedEffects()
	If effectFlash > 0 Then effectFlash :- 1

	Local buttonX:Float = 250
	Local buttonY:Float = 190
	Local buttonWidth:Float = 300
	Local buttonHeight:Float = 68
	Local findPressed:Int = MouseHit(1) And VirtualMouseX() >= buttonX And VirtualMouseX() < buttonX + buttonWidth And VirtualMouseY() >= buttonY And VirtualMouseY() < buttonY + buttonHeight
	If KeyHit(KEY_ENTER) Then findPressed = True
	If findPressed And gameCenter.IsAuthenticated() And Not searching And Not pendingMatch And Not session Then
		searching = True
		statusText = "Looking for another Rebound player..."
		detailText = "Start the example with a different Game Center account on another device"
		gameCenter.FindMatch(2, 2)
	End If

	Cls
	DrawArena()
	If rollbackGame Then DrawGame()
	SetColor 245, 248, 255
	DrawText "GAMEKIT REBOUND", 18, 14
	DrawText statusText, 18, 38
	DrawText detailText, 18, 58
	If Not session And Not pendingMatch Then
		SetColor 44, 115, 190
		DrawRect buttonX, buttonY, buttonWidth, buttonHeight
		SetColor 255, 255, 255
		DrawText "FIND MATCH", buttonX + 101, buttonY + 25
	Else If rollbackGame And rollbackGame.IsRunning() Then
		SetColor 220, 230, 245
		DrawText lastEffectText, 280, REBOUND_WORLD_HEIGHT - 48
		Local health:SSessionPeerHealth
		Local healthText:String = "Game Center connection"
		If remotePeer.IsValid() And session.GetPeerHealth(remotePeer, UInt(now), health) And health.HasRoundTrip() Then
			Local stepInfo:SRollbackStepInfo = rollbackGame.StepInfo()
			healthText = "RTT " + health.RoundTripMillis() + " ms  jitter " + health.JitterMillis() + "  lead " + stepInfo.PredictionLead() + "  stalls " + stalledRenders
			DrawText "rollback " + rollbackGame.RollbackCount() + "  depth " + rollbackGame.LastRollbackDepth() + "/" + rollbackGame.LargestRollbackDepth() + "  multi-step " + multiStepRenders + " max " + maximumStepsPerRender + "  confirmed " + ConfirmedFrameText(rollbackGame), 185, REBOUND_WORLD_HEIGHT - 16
		End If
		DrawText healthText, 225, REBOUND_WORLD_HEIGHT - 32
		controls.Render()
	End If
	Flip 1
Wend

controls.Free()
SetLifecycleCallback(Null)
If session Then session.Close()
If pendingMatch Then pendingMatch.Disconnect()
gameCenter.Stop()
EndGraphics
