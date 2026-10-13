Include "protocol.bmx"

Const SALVAGE_MAX_ENTITIES:Int = 16
Const SALVAGE_MAX_STEPS:Int = 8

Global transport:INetTransport
Global session:TNetSession
Global world:TReplicationWorld
Global authorityGame:TSalvageAuthority
Global authoritativeServer:TAuthoritativeServerSession
Global authoritativeClient:TAuthoritativeClientSession
Global remotePeer:SNetPeer
Global isAuthority:Int
Global localPlayer:Int = -1
Global joined:Int
Global statusText:String = "Starting network service..."
Global detailText:String = ""
Global simulationTick:UInt
Global replicationStep:Int
Global inputBuffer:Byte[3]
Global pulseQueued:Int
Global previousPulse:Int
Global pulseFrames:Int[SALVAGE_PLAYER_COUNT]
Global observedPulseSequence:UInt
Global renderX:Float[SALVAGE_MAX_ENTITIES]
Global renderY:Float[SALVAGE_MAX_ENTITIES]
Global renderGeneration:UInt[SALVAGE_MAX_ENTITIES]
Global movementStateBuffer:Byte[SALVAGE_MOVEMENT_STATE_SIZE]
Global predictedX:Float[SALVAGE_PLAYER_COUNT]
Global predictedY:Float[SALVAGE_PLAYER_COUNT]
Global presentedX:Float[SALVAGE_PLAYER_COUNT]
Global presentedY:Float[SALVAGE_PLAYER_COUNT]
Global correctionX:Float[SALVAGE_PLAYER_COUNT]
Global correctionY:Float[SALVAGE_PLAYER_COUNT]
Global presentationReady:Byte[SALVAGE_PLAYER_COUNT]
Global movementSnapshotsInWindow:Int
Global displayedMovementSnapshots:Int
Global lastMovementSnapshotTime:Int
Global largestMovementSnapshotGap:Int
Global displayedMovementSnapshotGap:Int
Global movementTimingWindowStart:Int
Global localPulseCooldown:Int

Type TSalvagePrediction Implements IAuthoritativePredictionSimulation
	Method LoadAuthoritativeState:Int(tick:UInt, state:SPacketView)
		If localPlayer < 0 Or localPlayer >= SALVAGE_PLAYER_COUNT Then Return False
		If Not DecodeSalvageMovementPlayer(state, localPlayer, predictedX[localPlayer], predictedY[localPlayer]) Then Return False
		Return True
	End Method

	Method ReplayInput:Int(sequence:UInt, input:SPacketView)
		If localPlayer < 0 Or localPlayer >= SALVAGE_PLAYER_COUNT Then Return False
		Local axisX:Int, axisY:Int, pulse:Int
		If Not DecodeSalvageInput(input, axisX, axisY, pulse) Then Return False
		ApplySalvageMovement(predictedX[localPlayer], predictedY[localPlayer], axisX, axisY, SALVAGE_SIMULATION_STEP)
		Return True
	End Method
End Type

Global movementPrediction:TSalvagePrediction = New TSalvagePrediction

Function AuthoritativeConfig:SAuthoritativeSessionConfig()
	Return New SAuthoritativeSessionConfig(SALVAGE_PLAYER_COUNT, 1, SALVAGE_INPUT_HISTORY_CAPACITY, SALVAGE_SERVER_INPUT_CAPACITY, SALVAGE_SNAPSHOT_CAPACITY, Size_T(inputBuffer.Length), SALVAGE_MOVEMENT_STATE_SIZE, SALVAGE_REDUNDANT_INPUTS, 60.0, 6.0, 18.0, SALVAGE_INPUT_MESSAGE, SALVAGE_SNAPSHOT_MESSAGE, SALVAGE_REPLICATION_CHANNEL)
End Function

Function CreateReplicationWorld:Int()
	Local config:SReplicationConfig = New SReplicationConfig(SALVAGE_MAX_ENTITIES, 3, 1, 3, 96, 900, SALVAGE_REPLICATION_MESSAGE, SALVAGE_REPLICATION_CHANNEL, 0, 16, 0, 700, 700, 32)
	If isAuthority Then
		world = TReplicationWorld.CreateAuthority(session, config)
	Else
		world = TReplicationWorld.CreateReplica(session, config)
	End If
	If Not world Or Not RegisterSalvageSchemas(world) Then Return False
	If isAuthority Then
		authorityGame = TSalvageAuthority.Create(world)
		If Not authorityGame Or Not authorityGame.Start() Then Return False
		authoritativeServer = TAuthoritativeServerSession.Create(AuthoritativeConfig())
		If Not authoritativeServer Then Return False
	Else
		authoritativeClient = TAuthoritativeClientSession.Create(AuthoritativeConfig())
		If Not authoritativeClient Then Return False
		authoritativeClient.SetLocalEntity(0)
	End If
	Return True
End Function

Function PollWorldEvents()
	If Not world Then Return
	Local event:SReplicationEvent
	While world.Poll(event)
		If event.Kind() <> EReplicationEventKind.Message Then Continue
		If Not isAuthority And event.MessageId() = SALVAGE_MESSAGE_PULSE And event.Payload().Length() = 2 Then
			Local player:Int = Int(event.Payload().Data()[0])
			' The local disposable effect was predicted when its button was pressed.
			If player >= 0 And player < SALVAGE_PLAYER_COUNT And player <> localPlayer Then pulseFrames[player] = 14
		End If
	Wend
End Function

Function ReceiveMovementSnapshot(event:SSessionEvent, now:Int)
	If isAuthority Or Not authoritativeClient Then Return
	Local snapshot:SAuthoritativeSnapshot
	If Not authoritativeClient.ReceiveSnapshot(event.Payload(), now, snapshot) Then
		statusText = "Invalid movement snapshot"
		Return
	End If
	movementSnapshotsInWindow :+ 1
	If lastMovementSnapshotTime > 0 Then largestMovementSnapshotGap = Max(largestMovementSnapshotGap, now - lastMovementSnapshotTime)
	lastMovementSnapshotTime = now
	Local x:Float, y:Float
	If Not DecodeSalvageMovementPlayer(snapshot.State(), localPlayer, x, y) Then Return
	Local player:Int = localPlayer
	Local wasReady:Int = presentationReady[player]
	Local oldX:Float = x
	Local oldY:Float = y
	If wasReady Then
		oldX = presentedX[player]
		oldY = presentedY[player]
	End If
	If Not authoritativeClient.Reconcile(snapshot, movementPrediction) Then
		statusText = "Movement reconciliation failed"
		Return
	End If
	If wasReady Then
		correctionX[player] = oldX - predictedX[player]
		correctionY[player] = oldY - predictedY[player]
	Else
		presentedX[player] = predictedX[player]
		presentedY[player] = predictedY[player]
		correctionX[player] = 0.0
		correctionY[player] = 0.0
		presentationReady[player] = True
	End If
End Function

Function PollSession(now:UInt)
	If Not session Then Return
	Local event:SSessionEvent
	While session.PollAt(event, now)
		Select event.Kind()
			Case ESessionEventKind.JoinRequested
				If session.Accept(event.Peer()) <> ETransportResult.Ok Then statusText = "Could not accept salvage pilot"
			Case ESessionEventKind.Joined
				remotePeer = event.Peer()
				joined = True
				Local result:ETransportResult = ETransportResult.Ok
				If isAuthority Then
					result = world.AddPeer(remotePeer, simulationTick)
					If result = ETransportResult.Ok And Not authoritativeServer.BindPlayer(1, remotePeer) Then result = ETransportResult.InvalidPeer
				Else If Not world.BindAuthority(remotePeer) Then
					result = ETransportResult.InvalidPeer
				Else
					authoritativeClient.Reset()
					authoritativeClient.SetLocalEntity(0)
				End If
				If result = ETransportResult.Ok Then
					statusText = "Orbital Salvage underway"
					detailText = "Carry glowing cores home; PULSE makes a nearby rival drop theirs"
				Else
					statusText = "Could not attach replication peer"
				End If
			Case ESessionEventKind.Message
				Select event.MessageType()
					Case SALVAGE_REPLICATION_MESSAGE
						If Not world.Receive(event.Peer(), event.MessageType(), event.Payload()) Then statusText = "Invalid replication packet"
					Case SALVAGE_INPUT_MESSAGE
						If isAuthority And authoritativeServer Then
							If Not authoritativeServer.ReceiveInputs(1, event.Peer(), event.Payload()) Then statusText = "Invalid movement input"
						End If
					Case SALVAGE_SNAPSHOT_MESSAGE
						ReceiveMovementSnapshot(event, Int(now))
				End Select
			Case ESessionEventKind.Left
				joined = False
				If authoritativeServer Then authoritativeServer.UnbindPlayer(1)
				statusText = "The other salvage pilot left"
				detailText = "Restart the example to find another match"
			Case ESessionEventKind.Rejected
				statusText = "Session rejected (" + event.Code() + ")"
			Case ESessionEventKind.Error
				statusText = "Session error (" + event.Code() + ")"
		End Select
	Wend
	PollWorldEvents()
End Function

Function EntityForPlayer:TReplicatedEntity(player:Int)
	If Not world Then Return Null
	For Local slot:Int = 0 Until world.EntityCapacity()
		Local entity:TReplicatedEntity = world.EntityAt(slot)
		If entity And entity.TypeId() = SALVAGE_PLAYER_TYPE And entity.OwnerId() = UInt(player + 1) Then Return entity
	Next
	Return Null
End Function

Function MatchEntity:TReplicatedEntity()
	If Not world Then Return Null
	For Local slot:Int = 0 Until world.EntityCapacity()
		Local entity:TReplicatedEntity = world.EntityAt(slot)
		If entity And entity.TypeId() = SALVAGE_MATCH_TYPE Then Return entity
	Next
	Return Null
End Function

Function QueueClientInput:Int(axisX:Int, axisY:Int)
	If isAuthority Or Not joined Or Not authoritativeClient Or Not presentationReady[localPlayer] Then Return False
	Local length:Size_T = EncodeSalvageInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), axisX, axisY, pulseQueued)
	If authoritativeClient.QueueInput(Byte Ptr(inputBuffer), length) = 0 Then
		statusText = "Movement input history full"
		Return False
	End If
	ApplySalvageMovement(predictedX[localPlayer], predictedY[localPlayer], axisX, axisY, SALVAGE_SIMULATION_STEP)
	pulseQueued = False
	Return True
End Function

Function SendMovementSnapshots()
	If Not isAuthority Or Not joined Or Not authoritativeServer Or Not authoritativeServer.PlayerBound(1) Then Return
	Local player0:TReplicatedEntity = authorityGame.PlayerEntity(0)
	Local player1:TReplicatedEntity = authorityGame.PlayerEntity(1)
	If Not player0 Or Not player1 Then Return
	Local length:Size_T = EncodeSalvageMovementState(Byte Ptr(movementStateBuffer), Size_T(movementStateBuffer.Length), player0.GetFloat32(SALVAGE_FIELD_X), player0.GetFloat32(SALVAGE_FIELD_Y), player1.GetFloat32(SALVAGE_FIELD_X), player1.GetFloat32(SALVAGE_FIELD_Y))
	If length Then authoritativeServer.SendSnapshot(session, 1, 0, simulationTick, Byte Ptr(movementStateBuffer), length)
End Function

Function StepAuthority(axisX:Int, axisY:Int, pulse:Int)
	If Not isAuthority Or Not joined Or Not authorityGame Then Return
	authorityGame.SetInput(localPlayer, axisX, axisY, pulse)
	If authoritativeServer Then
		Local remoteX:Int, remoteY:Int, remotePulse:Int
		Local receivedInput:Int
		' Movement axes describe current state, so old samples need not create an
		' artificial input-delay queue. Drain to the newest state while retaining
		' any one-shot pulse contained by an intermediate sample.
		While authoritativeServer.InputCount(1) > 0
			Local remoteInput:SPredictionInput
			If Not authoritativeServer.PeekInput(1, remoteInput) Then Exit
			Local sampleX:Int, sampleY:Int, samplePulse:Int
			If Not DecodeSalvageInput(remoteInput.Payload(), sampleX, sampleY, samplePulse) Then Exit
			remoteX = sampleX
			remoteY = sampleY
			remotePulse :| samplePulse
			receivedInput = True
			If Not authoritativeServer.AcknowledgeInput(1, remoteInput.Sequence()) Then Exit
		Wend
		If receivedInput Then authorityGame.SetInput(1, remoteX, remoteY, remotePulse)
	End If
	simulationTick :+ 1
	authorityGame.Step(simulationTick)
	If authorityGame.pulseSequence <> observedPulseSequence Then
		observedPulseSequence = authorityGame.pulseSequence
		If authorityGame.lastPulsePlayer >= 0 Then pulseFrames[authorityGame.lastPulsePlayer] = 14
	End If
	replicationStep :+ 1
	If replicationStep >= 2 Then
		replicationStep = 0
		SendMovementSnapshots()
		Local result:ETransportResult = world.Flush(simulationTick)
		If result <> ETransportResult.Ok Then statusText = "Replication flush failed (" + Int(result) + ")"
	End If
End Function

Function DrawBackground()
	SetColor 7, 12, 25
	DrawRect 0, 0, SALVAGE_WORLD_WIDTH, SALVAGE_WORLD_HEIGHT
	For Local y:Int = 25 Until Int(SALVAGE_WORLD_HEIGHT) Step 47
		For Local x:Int = 18 Until Int(SALVAGE_WORLD_WIDTH) Step 61
			Local shade:Int = 38 + ((x + y) Mod 30)
			SetColor shade, shade + 8, shade + 20
			DrawRect x, y, 2, 2
		Next
	Next
	SetColor 18, 54, 79
	DrawRect 0, 85, 58, SALVAGE_WORLD_HEIGHT - 170
	SetColor 72, 175, 210
	DrawRect 48, 85, 10, SALVAGE_WORLD_HEIGHT - 170
	SetColor 73, 38, 70
	DrawRect SALVAGE_WORLD_WIDTH - 58, 85, 58, SALVAGE_WORLD_HEIGHT - 170
	SetColor 226, 100, 157
	DrawRect SALVAGE_WORLD_WIDTH - 58, 85, 10, SALVAGE_WORLD_HEIGHT - 170
	SetColor 32, 45, 68
	DrawOval SALVAGE_WORLD_WIDTH * 0.5 - 104, SALVAGE_WORLD_HEIGHT * 0.5 - 104, 208, 208
	SetColor 12, 20, 36
	DrawOval SALVAGE_WORLD_WIDTH * 0.5 - 88, SALVAGE_WORLD_HEIGHT * 0.5 - 88, 176, 176
End Function

Function SmoothedCorePosition(entity:TReplicatedEntity, x:Float Var, y:Float Var)
	Local slot:Int = Int(entity.Identity().Id()) - 1
	Local targetX:Float = entity.GetFloat32(SALVAGE_FIELD_X)
	Local targetY:Float = entity.GetFloat32(SALVAGE_FIELD_Y)
	If slot < 0 Or slot >= SALVAGE_MAX_ENTITIES Then
		x = targetX
		y = targetY
		Return
	End If
	If renderGeneration[slot] <> entity.Identity().Generation() Then
		renderGeneration[slot] = entity.Identity().Generation()
		renderX[slot] = targetX
		renderY[slot] = targetY
	Else
		renderX[slot] :+ (targetX - renderX[slot]) * 0.34
		renderY[slot] :+ (targetY - renderY[slot]) * 0.34
	End If
	x = renderX[slot]
	y = renderY[slot]
End Function

Function PresentedPlayerPosition(player:Int, x:Float Var, y:Float Var)
	If player < 0 Or player >= SALVAGE_PLAYER_COUNT Then Return
	If presentationReady[player] Then
		x = presentedX[player]
		y = presentedY[player]
		Return
	End If
	Local entity:TReplicatedEntity = EntityForPlayer(player)
	If entity Then
		x = entity.GetFloat32(SALVAGE_FIELD_X)
		y = entity.GetFloat32(SALVAGE_FIELD_Y)
	End If
End Function

Function SampleMovementPosition:Int(player:Int, renderTick:Double, x:Float Var, y:Float Var)
	If Not authoritativeClient Then Return False
	Local sample:SSnapshotSample
	If Not authoritativeClient.SampleEntity(0, renderTick, sample) Then Return False
	Local fromX:Float, fromY:Float
	If Not DecodeSalvageMovementPlayer(sample.FromState(), player, fromX, fromY) Then Return False
	If Not sample.IsInterpolated() Then
		x = fromX
		y = fromY
		Return True
	End If
	Local toX:Float, toY:Float
	If Not DecodeSalvageMovementPlayer(sample.ToState(), player, toX, toY) Then Return False
	x = fromX + (toX - fromX) * sample.Blend()
	y = fromY + (toY - fromY) * sample.Blend()
	Return True
End Function

Function UpdatePresentation(now:Int, elapsed:Int)
	If isAuthority Then
		For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
			Local entity:TReplicatedEntity = EntityForPlayer(player)
			If Not entity Then Continue
			presentedX[player] = entity.GetFloat32(SALVAGE_FIELD_X)
			presentedY[player] = entity.GetFloat32(SALVAGE_FIELD_Y)
			presentationReady[player] = True
		Next
		Return
	End If
	If Not authoritativeClient Then Return
	Local seconds:Float = Float(Min(50, elapsed)) / 1000.0
	If localPlayer >= 0 And localPlayer < SALVAGE_PLAYER_COUNT And presentationReady[localPlayer] Then
		Local correctionBlend:Float = Max(0.0, 1.0 - 10.0 * seconds)
		correctionX[localPlayer] :* correctionBlend
		correctionY[localPlayer] :* correctionBlend
		presentedX[localPlayer] = Max(SALVAGE_PLAYER_RADIUS, Min(SALVAGE_WORLD_WIDTH - SALVAGE_PLAYER_RADIUS, predictedX[localPlayer] + correctionX[localPlayer]))
		presentedY[localPlayer] = Max(SALVAGE_PLAYER_RADIUS, Min(SALVAGE_WORLD_HEIGHT - SALVAGE_PLAYER_RADIUS, predictedY[localPlayer] + correctionY[localPlayer]))
	End If
	Local renderTick:Double = authoritativeClient.RenderTick(now)
	If renderTick <= 0.0 Then Return
	For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
		If player = localPlayer Then Continue
		If SampleMovementPosition(player, renderTick, presentedX[player], presentedY[player]) Then presentationReady[player] = True
	Next
End Function

Function DrawWorld()
	If Not world Then Return
	Local playerX:Float[SALVAGE_PLAYER_COUNT]
	Local playerY:Float[SALVAGE_PLAYER_COUNT]
	For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
		PresentedPlayerPosition(player, playerX[player], playerY[player])
	Next
	For Local slot:Int = 0 Until world.EntityCapacity()
		Local entity:TReplicatedEntity = world.EntityAt(slot)
		If Not entity Then Continue
		If entity.TypeId() = SALVAGE_CORE_TYPE Then
			Local x:Float, y:Float
			Local carrier:Int = Int(entity.GetUInt32(SALVAGE_FIELD_CARRIER)) - 1
			If carrier >= 0 And carrier < SALVAGE_PLAYER_COUNT Then
				x = playerX[carrier]
				y = playerY[carrier]
				If carrier = 0 Then x :+ 24.0 Else x :- 24.0
			Else
				SmoothedCorePosition(entity, x, y)
			End If
			SetColor 255, 193, 55
			DrawOval x - SALVAGE_CORE_RADIUS - 5, y - SALVAGE_CORE_RADIUS - 5, (SALVAGE_CORE_RADIUS + 5) * 2, (SALVAGE_CORE_RADIUS + 5) * 2
			SetColor 255, 247, 178
			DrawOval x - SALVAGE_CORE_RADIUS, y - SALVAGE_CORE_RADIUS, SALVAGE_CORE_RADIUS * 2, SALVAGE_CORE_RADIUS * 2
		End If
	Next
	For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
		Local entity:TReplicatedEntity = EntityForPlayer(player)
		If Not entity Then Continue
		Local x:Float = playerX[player]
		Local y:Float = playerY[player]
		If pulseFrames[player] > 0 Then
			SetAlpha Float(pulseFrames[player]) / 28.0
			If player = 0 Then SetColor 65, 211, 255 Else SetColor 255, 91, 161
			Local radius:Float = SALVAGE_PULSE_RADIUS * (1.0 - Float(pulseFrames[player]) / 28.0)
			DrawOval x - radius, y - radius, radius * 2, radius * 2
			SetAlpha 1.0
		End If
		If player = 0 Then SetColor 42, 186, 235 Else SetColor 239, 74, 139
		DrawOval x - SALVAGE_PLAYER_RADIUS, y - SALVAGE_PLAYER_RADIUS, SALVAGE_PLAYER_RADIUS * 2, SALVAGE_PLAYER_RADIUS * 2
		SetColor 236, 250, 255
		Local nose:Float = 8.0
		If player = 1 Then nose = -12.0
		DrawRect x + nose, y - 4, 5, 8
		If player = localPlayer Then
			SetColor 255, 255, 255
			DrawText "YOU", x - 14, y - 34
		End If
	Next
End Function

Function DrawScore()
	Local match:TReplicatedEntity = MatchEntity()
	If Not match Then Return
	Local score0:Int = match.GetInt32(SALVAGE_FIELD_SCORE_0)
	Local score1:Int = match.GetInt32(SALVAGE_FIELD_SCORE_1)
	SetColor 235, 245, 255
	DrawText score0, 344, 20
	DrawText "ORBITAL SALVAGE", 369, 20
	DrawText score1, 448, 20
	Local winner:Int = match.GetInt32(SALVAGE_FIELD_WINNER)
	If winner >= 0 Then
		SetColor 5, 9, 18
		DrawRect 230, 160, 340, 100
		If winner = localPlayer Then SetColor 93, 238, 171 Else SetColor 255, 112, 142
		Local text:String = "RIVAL WINS THE SALVAGE"
		If winner = localPlayer Then text = "YOU WIN THE SALVAGE"
		DrawText text, 300, 198
		SetColor 220, 230, 245
		DrawText "Restart to play another match", 294, 226
	End If
End Function

?ios
Graphics 1280, 720, 32, 0, GRAPHICS_FULLSCREEN_DESKTOP
?Not ios
Graphics 1280, 720
?
SetVirtualResolution(Int(SALVAGE_WORLD_WIDTH), Int(SALVAGE_WORLD_HEIGHT), VIRTUAL_LETTERBOX)
SetVirtualBarColor 3, 6, 14
SetClsColor 7, 12, 25

Local controls:TVirtualJoystick = TVirtualJoystick.Create(1, "Orbital Salvage controls")
controls.SetStickEnabled(True)
controls.SetButtonLabel(0, "PULSE")
Local safeX:Int, safeY:Int, safeWidth:Int, safeHeight:Int
GetWindowSafeArea(safeX, safeY, safeWidth, safeHeight)
If safeWidth <= 0 Or safeHeight <= 0 Then
	safeWidth = GraphicsWidth()
	safeHeight = GraphicsHeight()
End If
Local controlScale:Float = Max(0.68, Min(1.8, Float(Min(safeWidth, safeHeight)) / 720.0))
Local stickRadius:Float = 78.0 * controlScale
Local stickX:Float = safeX + 46.0 * controlScale + stickRadius
Local stickY:Float = safeY + safeHeight - 46.0 * controlScale - stickRadius
controls.SetStick(stickX, stickY, stickRadius, 32.0 * controlScale)
Local pulseRadius:Float = 58.0 * controlScale
controls.SetButton(0, safeX + safeWidth - 46.0 * controlScale - pulseRadius, safeY + safeHeight - 46.0 * controlScale - pulseRadius, pulseRadius)

If Not InitializeSalvageConnection() Then Throw "Could not initialize network service"

Local accumulator:Double
Local previousTime:Int = MilliSecs()

While Not AppTerminate() And Not KeyDown(KEY_ESCAPE)
	Local now:Int = MilliSecs()
	Local elapsed:Int = Min(250, Max(0, now - previousTime))
	previousTime = now
	PollSalvageConnection(now)
	PollSession(UInt(now))
	If movementTimingWindowStart = 0 Then movementTimingWindowStart = now
	If now - movementTimingWindowStart >= 1000 Then
		Local timingElapsed:Int = now - movementTimingWindowStart
		displayedMovementSnapshots = movementSnapshotsInWindow * 1000 / timingElapsed
		displayedMovementSnapshotGap = largestMovementSnapshotGap
		movementSnapshotsInWindow = 0
		largestMovementSnapshotGap = 0
		movementTimingWindowStart = now
	End If

	Local movementX:Float = controls.X()
	Local movementY:Float = controls.Y()
	If KeyDown(KEY_A) Or KeyDown(KEY_LEFT) Then movementX :- 1.0
	If KeyDown(KEY_D) Or KeyDown(KEY_RIGHT) Then movementX :+ 1.0
	If KeyDown(KEY_W) Or KeyDown(KEY_UP) Then movementY :- 1.0
	If KeyDown(KEY_S) Or KeyDown(KEY_DOWN) Then movementY :+ 1.0
	movementX = Max(-1.0, Min(1.0, movementX))
	movementY = Max(-1.0, Min(1.0, movementY))
	Local axisX:Int = Int(movementX * 127.0)
	Local axisY:Int = Int(movementY * 127.0)
	Local pulse:Int = controls.ButtonDown(0) Or KeyDown(KEY_SPACE)
	Local pulsePressed:Int = pulse And Not previousPulse
	previousPulse = pulse
	If pulsePressed Then
		Local pulseReady:Int
		If isAuthority Then
			pulseReady = authorityGame And authorityGame.pulseCooldown[localPlayer] = 0
		Else
			pulseReady = joined And presentationReady[localPlayer] And localPulseCooldown = 0
		End If
		If pulseReady Then
			pulseQueued = True
			If Not isAuthority Then
				pulseFrames[localPlayer] = 14
				localPulseCooldown = SALVAGE_PULSE_COOLDOWN_TICKS
			End If
		End If
	End If

	If joined Then
		accumulator = Min(0.25, accumulator + Double(elapsed) / 1000.0)
		Local queuedClientInput:Int
		While accumulator >= Double(SALVAGE_SIMULATION_STEP)
			accumulator :- Double(SALVAGE_SIMULATION_STEP)
			If Not isAuthority And localPulseCooldown > 0 Then localPulseCooldown :- 1
			If isAuthority Then
				StepAuthority(axisX, axisY, pulseQueued)
				pulseQueued = False
			Else If QueueClientInput(axisX, axisY) Then
				queuedClientInput = True
			End If
		Wend
		If queuedClientInput And authoritativeClient And remotePeer.IsValid() Then
			Local sendResult:ETransportResult = authoritativeClient.SendInputs(session, remotePeer)
			If sendResult <> ETransportResult.Ok And sendResult <> ETransportResult.WouldBlock Then statusText = "Movement input send failed (" + Int(sendResult) + ")"
		End If
	End If
	UpdatePresentation(now, elapsed)

	For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
		If pulseFrames[player] > 0 Then pulseFrames[player] :- 1
	Next

	HandleSalvageConnectionInput()

	Cls
	DrawBackground()
	DrawWorld()
	DrawScore()
	SetColor 235, 245, 255
	DrawText statusText, 16, 16
	DrawText detailText, 16, 39
	If joined Then
		SetColor 160, 190, 215
		If isAuthority And authoritativeServer Then
			DrawText "remote input queue " + authoritativeServer.InputCount(1) + "  acknowledged " + authoritativeServer.AcknowledgedInput(1), 16, 62
		Else If authoritativeClient Then
			DrawText "snapshots/s " + displayedMovementSnapshots + "  largest gap " + displayedMovementSnapshotGap + " ms  buffer " + Int(authoritativeClient.DelayMillis()) + " ms  pending inputs " + authoritativeClient.PendingInputCount(), 16, 62
		End If
		Local displayedPulseCooldown:Int = localPulseCooldown
		If isAuthority And authorityGame Then displayedPulseCooldown = authorityGame.pulseCooldown[localPlayer]
		If displayedPulseCooldown = 0 Then
			SetColor 105, 235, 175
			DrawText "PULSE READY", 16, 84
		Else
			SetColor 170, 180, 205
			DrawText "PULSE RECHARGING " + Int(Float(displayedPulseCooldown) * 1000.0 / 60.0) + " ms", 16, 84
		End If
	End If
	If Not session Then
		DrawSalvageConnection()
	Else If joined Then
		controls.Render()
	End If
	Flip 1
Wend

controls.Free()
If world Then world.Close()
If session Then session.Close()
CloseSalvageConnection()
EndGraphics
