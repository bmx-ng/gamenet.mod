SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import Max2D.VirtualJoystick
Import GameNet.Session
Import GameNet.ENet
Import GameNet.Snapshot
Import GameNet.Prediction

Include "protocol.bmx"

Const SNAPSHOT_BUFFER_SIZE:Int = 32
Const SNAPSHOT_STATE_SIZE:Size_T = 8
Const SERVER_TICKS_PER_SECOND:Double = 60.0
Const SNAPSHOT_BASE_DELAY_TICKS:Float = 2.0
Const SNAPSHOT_MAXIMUM_DELAY_TICKS:Float = 12.0
Const CORRECTION_RATE:Float = 10.0

Struct SClientPlayer
	Field active:Int
	Field x:Float
	Field y:Float
	Field predictedX:Float
	Field predictedY:Float
	Field correctionX:Float
	Field correctionY:Float
	Field renderX:Float
	Field renderY:Float
	Field initialized:Int
End Struct

Global snapshotStateBuffer:Byte[SNAPSHOT_STATE_SIZE]
Global predictionInputBuffer:Byte[AUTHORITATIVE_INPUT_PAYLOAD_SIZE]

Function ApplyInput(x:Float Var, y:Float Var, inputX:Int, inputY:Int, seconds:Float)
	Local moveX:Float = Float(inputX) / 127.0
	Local moveY:Float = Float(inputY) / 127.0
	Local magnitudeSquared:Float = moveX * moveX + moveY * moveY
	If magnitudeSquared > 1.0 Then
		Local inverseMagnitude:Float = 1.0 / Sqr(magnitudeSquared)
		moveX :* inverseMagnitude
		moveY :* inverseMagnitude
	End If
	x :+ moveX * AUTHORITATIVE_PLAYER_SPEED * seconds
	y :+ moveY * AUTHORITATIVE_PLAYER_SPEED * seconds
	x = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, x))
	y = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, y))
End Function

Function StorePositionSnapshot:Int(timeline:TSnapshotTimeline, tick:UInt, x:Float, y:Float)
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(snapshotStateBuffer), Size_T(snapshotStateBuffer.Length))
	writer.WriteFloat32(x)
	writer.WriteFloat32(y)
	If writer.Failed() Then Return False
	Return timeline.Add(tick, Byte Ptr(snapshotStateBuffer), writer.Position())
End Function

Function DecodePositionState:Int(state:SPacketView, x:Float Var, y:Float Var)
	Local reader:SPacketReader = New SPacketReader(state)
	Return reader.ReadFloat32(x) And reader.ReadFloat32(y) And reader.Remaining() = 0
End Function

Function SamplePositionSnapshot:Int(timeline:TSnapshotTimeline, renderTick:Double, x:Float Var, y:Float Var)
	Local sample:SSnapshotSample
	If Not timeline.Sample(renderTick, sample) Then Return False
	Local fromX:Float
	Local fromY:Float
	If Not DecodePositionState(sample.FromState(), fromX, fromY) Then Return False
	If Not sample.IsInterpolated() Then
		x = fromX
		y = fromY
		Return True
	End If
	Local toX:Float
	Local toY:Float
	If Not DecodePositionState(sample.ToState(), toX, toY) Then Return False
	x = fromX + (toX - fromX) * sample.Blend()
	y = fromY + (toY - fromY) * sample.Blend()
	Return True
End Function

Local serverAddress:String = "127.0.0.1"
Local serverPort:Int = AUTHORITATIVE_PORT
If AppArgs.Length > 1 Then serverAddress = AppArgs[1]
If AppArgs.Length > 2 Then serverPort = Int(AppArgs[2])

Local transport:TENetTransport = TENetTransport.CreateClient(1, 2)
If Not transport Then Throw "Could not create the ENet client"
Local pendingPeer:SNetPeer
If transport.Connect(serverAddress, serverPort, pendingPeer) <> ETransportResult.Ok Then Throw "Could not begin connecting to " + serverAddress

Local session:TNetSession = TNetSession.CreateClient(transport, AUTHORITATIVE_APP_ID, AUTHORITATIVE_APP_VERSION, Null, 0, 1, 1200)
If Not session Then Throw "Could not create the client session"

?android Or ios
Graphics 960, 540, 32, 0, GRAPHICS_FULLSCREEN_DESKTOP
?Not android And Not ios
Graphics 960, 540
?
SetVirtualResolution(Int(WORLD_WIDTH), Int(WORLD_HEIGHT), VIRTUAL_LETTERBOX)
SetVirtualBarColor 6, 9, 16
SetClsColor 12, 18, 30

Local controls:TVirtualJoystick = TVirtualJoystick.Create(0)
Local hostPeer:SNetPeer
Local status:String = "Connecting to " + serverAddress + ":" + serverPort + "..."
Local ownEntityId:UInt
Local players:SClientPlayer[AUTHORITATIVE_MAX_PLAYERS]
Local snapshotTimelines:TSnapshotTimeline[AUTHORITATIVE_MAX_PLAYERS]
For Local index:Int = 0 Until snapshotTimelines.Length
	snapshotTimelines[index] = TSnapshotTimeline.Create(SNAPSHOT_BUFFER_SIZE, SNAPSHOT_STATE_SIZE)
Next
Local snapshotClock:TSnapshotClock = TSnapshotClock.Create(SERVER_TICKS_PER_SECOND)
Local snapshotDelay:TSnapshotDelay = TSnapshotDelay.Create(SERVER_TICKS_PER_SECOND, SNAPSHOT_BASE_DELAY_TICKS, SNAPSHOT_MAXIMUM_DELAY_TICKS)
Local inputHistory:TPredictionHistory = TPredictionHistory.Create(AUTHORITATIVE_INPUT_HISTORY_CAPACITY, AUTHORITATIVE_INPUT_PAYLOAD_SIZE)
Local inputSequence:UInt
Local acknowledgedInput:UInt
Local serverTick:UInt
Local inputBatchBuffer:Byte[512]
Local predictionAccumulator:Float
Local timingWindowStart:Int = MilliSecs()
Local framesInWindow:Int
Local snapshotsInWindow:Int
Local displayedFramesPerSecond:Int
Local displayedSnapshotsPerSecond:Int
Local lastFrameTime:Int
Local frameGap:Int
Local largestFrameGap:Int
Local lastSnapshotTime:Int
Local snapshotGap:Int
Local largestSnapshotGap:Int

While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local frameNow:Int = MilliSecs()
	Local frameElapsed:Int
	If lastFrameTime > 0 Then frameElapsed = Min(50, Max(0, frameNow - lastFrameTime))
	framesInWindow :+ 1
	If lastFrameTime > 0 Then largestFrameGap = Max(largestFrameGap, frameNow - lastFrameTime)
	lastFrameTime = frameNow
	Local event:SSessionEvent
	While session.Poll(event)
		Select event.Kind()
			Case ESessionEventKind.Joined
				hostPeer = event.Peer()
				If DecodeEntity(event.Payload(), ownEntityId) And ownEntityId >= 1 And ownEntityId <= UInt(players.Length) Then
					For Local index:Int = 0 Until players.Length
						players[index] = New SClientPlayer
						snapshotTimelines[index].Clear()
					Next
					inputHistory.Clear()
					inputSequence = 0
					predictionAccumulator = 0.0
					snapshotClock.Clear()
					snapshotDelay.Clear()
					status = "Joined as player " + ownEntityId + "; waiting for spawn"
				Else
					status = "Joined with an invalid entity ID"
				End If

			Case ESessionEventKind.Rejected
				status = "Join rejected (code " + event.Code() + ")"

			Case ESessionEventKind.Left
				status = "Disconnected (code " + event.Code() + ")"
				hostPeer = New SNetPeer
				ownEntityId = 0
				inputSequence = 0
				acknowledgedInput = 0
				inputHistory.Clear()
				predictionAccumulator = 0.0
				For Local index:Int = 0 Until players.Length
					players[index] = New SClientPlayer
					snapshotTimelines[index].Clear()
				Next
				snapshotClock.Clear()
				snapshotDelay.Clear()

			Case ESessionEventKind.Message
				Select event.MessageType()
					Case MSG_SPAWN
						If event.Channel() = CONTROL_CHANNEL And event.Delivery() = EDeliveryMode.ReliableOrdered Then
							Local entityId:UInt
							Local x:Float
							Local y:Float
							If DecodeSpawn(event.Payload(), entityId, x, y) And entityId >= 1 And entityId <= UInt(players.Length) Then
								Local index:Int = Int(entityId) - 1
								players[index].active = True
								players[index].x = x
								players[index].y = y
								players[index].predictedX = x
								players[index].predictedY = y
								players[index].correctionX = 0.0
								players[index].correctionY = 0.0
								players[index].renderX = x
								players[index].renderY = y
								players[index].initialized = True
								If entityId = ownEntityId Then status = "Connected as player " + ownEntityId
							End If
						End If

					Case MSG_DESPAWN
						If event.Channel() = CONTROL_CHANNEL And event.Delivery() = EDeliveryMode.ReliableOrdered Then
							Local entityId:UInt
							If DecodeEntity(event.Payload(), entityId) And entityId >= 1 And entityId <= UInt(players.Length) Then
								Local index:Int = Int(entityId) - 1
								players[index] = New SClientPlayer
								snapshotTimelines[index].Clear()
							End If
						End If

					Case MSG_SNAPSHOT
						If event.Channel() = GAMEPLAY_CHANNEL And event.Delivery() = EDeliveryMode.UnreliableSequenced Then
							Local entityId:UInt
							Local tick:UInt
							Local acknowledged:UInt
							Local x:Float
							Local y:Float
							If DecodeSnapshot(event.Payload(), entityId, tick, acknowledged, x, y) And entityId >= 1 And entityId <= UInt(players.Length) Then
								Local index:Int = Int(entityId) - 1
								players[index].active = True
								players[index].x = x
								players[index].y = y
								StorePositionSnapshot(snapshotTimelines[index], tick, x, y)
								If snapshotClock.Observe(tick, frameNow) Then
									snapshotDelay.Observe(tick, frameNow)
								End If
								If entityId = ownEntityId Then
									serverTick = tick
									acknowledgedInput = acknowledged
									inputHistory.Acknowledge(acknowledged)
									Local previousRenderX:Float = players[index].renderX
									Local previousRenderY:Float = players[index].renderY
									Local reconciledX:Float = x
									Local reconciledY:Float = y
									For Local historyIndex:Int = 0 Until inputHistory.Count()
										Local input:SPredictionInput
										Local replayX:Int
										Local replayY:Int
										If inputHistory.Get(historyIndex, input) And DecodeMovementInput(input.Payload(), replayX, replayY) Then
											ApplyInput(reconciledX, reconciledY, replayX, replayY, AUTHORITATIVE_SIMULATION_STEP)
										End If
									Next
									players[index].predictedX = reconciledX
									players[index].predictedY = reconciledY
									players[index].correctionX = previousRenderX - reconciledX
									players[index].correctionY = previousRenderY - reconciledY
									players[index].initialized = True
									snapshotsInWindow :+ 1
									If lastSnapshotTime > 0 Then largestSnapshotGap = Max(largestSnapshotGap, frameNow - lastSnapshotTime)
									lastSnapshotTime = frameNow
								End If
							End If
						End If
				End Select

			Case ESessionEventKind.Error
				status = "Session error (code " + event.Code() + ")"
		End Select
	Wend

	Local axisX:Float = controls.X()
	Local axisY:Float = controls.Y()
	axisX :+ Float(KeyDown(KEY_D) Or KeyDown(KEY_RIGHT))
	axisX :- Float(KeyDown(KEY_A) Or KeyDown(KEY_LEFT))
	axisY :+ Float(KeyDown(KEY_S) Or KeyDown(KEY_DOWN))
	axisY :- Float(KeyDown(KEY_W) Or KeyDown(KEY_UP))
	axisX = Max(-1.0, Min(1.0, axisX))
	axisY = Max(-1.0, Min(1.0, axisY))
	Local currentInputX:Int = Int(axisX * 127.0)
	Local currentInputY:Int = Int(axisY * 127.0)

	If frameNow - timingWindowStart >= 1000 Then
		Local timingElapsed:Int = frameNow - timingWindowStart
		displayedFramesPerSecond = framesInWindow * 1000 / timingElapsed
		displayedSnapshotsPerSecond = snapshotsInWindow * 1000 / timingElapsed
		frameGap = largestFrameGap
		snapshotGap = largestSnapshotGap
		framesInWindow = 0
		snapshotsInWindow = 0
		largestFrameGap = 0
		largestSnapshotGap = 0
		timingWindowStart = frameNow
	End If

	Local ownIndex:Int = Int(ownEntityId) - 1
	If ownIndex >= 0 And ownIndex < players.Length And players[ownIndex].active And players[ownIndex].initialized Then
		Local frameSeconds:Float = Float(frameElapsed) / 1000.0
		predictionAccumulator :+ frameSeconds
		Local addedInput:Int
		While predictionAccumulator >= AUTHORITATIVE_SIMULATION_STEP
			predictionAccumulator :- AUTHORITATIVE_SIMULATION_STEP
			Local nextSequence:UInt = inputSequence + 1
			Local inputLength:Size_T = EncodeMovementInput(Byte Ptr(predictionInputBuffer), Size_T(predictionInputBuffer.Length), currentInputX, currentInputY)
			If Not inputHistory.Add(nextSequence, Byte Ptr(predictionInputBuffer), inputLength) Then
				status = "Prediction input history full"
				predictionAccumulator = 0.0
				Exit
			End If
			inputSequence = nextSequence
			addedInput = True
			ApplyInput(players[ownIndex].predictedX, players[ownIndex].predictedY, currentInputX, currentInputY, AUTHORITATIVE_SIMULATION_STEP)
		Wend
		Local correctionBlend:Float = Max(0.0, 1.0 - CORRECTION_RATE * frameSeconds)
		players[ownIndex].correctionX :* correctionBlend
		players[ownIndex].correctionY :* correctionBlend
		players[ownIndex].renderX = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, players[ownIndex].predictedX + players[ownIndex].correctionX))
		players[ownIndex].renderY = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, players[ownIndex].predictedY + players[ownIndex].correctionY))
		If addedInput And hostPeer.IsValid() Then
			Local length:Size_T = EncodeInputBatch(Byte Ptr(inputBatchBuffer), Size_T(inputBatchBuffer.Length), inputHistory)
			If length > 0 Then session.Send(hostPeer, MSG_INPUT, GAMEPLAY_CHANNEL, EDeliveryMode.UnreliableSequenced, Byte Ptr(inputBatchBuffer), length)
		End If
	Else
		predictionAccumulator = 0.0
	End If

	If snapshotClock.IsObserved() Then
		Local renderTick:Double = snapshotClock.Estimate(frameNow) - Double(snapshotDelay.DelayTicks())
		For Local index:Int = 0 Until players.Length
			If index = ownIndex Or Not players[index].active Then Continue
			If SamplePositionSnapshot(snapshotTimelines[index], renderTick, players[index].renderX, players[index].renderY) Then players[index].initialized = True
		Next
	End If

	Cls
	SetColor 25, 38, 57
	For Local x:Int = 0 Until Int(WORLD_WIDTH) Step 40
		DrawLine x, 0, x, WORLD_HEIGHT
	Next
	For Local y:Int = 0 Until Int(WORLD_HEIGHT) Step 40
		DrawLine 0, y, WORLD_WIDTH, y
	Next

	For Local index:Int = 0 Until players.Length
		If Not players[index].active Then Continue
		If UInt(index + 1) = ownEntityId Then
			SetColor 55, 170, 240
		Else
			SetColor 245, 166, 35
		End If
		DrawOval players[index].renderX - PLAYER_RADIUS, players[index].renderY - PLAYER_RADIUS, PLAYER_RADIUS * 2.0, PLAYER_RADIUS * 2.0
		DrawText String(index + 1), players[index].renderX - 4, players[index].renderY - 7
	Next

	SetColor 255, 255, 255
	DrawText status, 12, 12
	DrawText "Server-authoritative positions", 12, 32
	DrawText "Input " + inputSequence + "  acknowledged " + acknowledgedInput + "  server tick " + serverTick, 12, 52
	DrawText "FPS " + displayedFramesPerSecond + "  snapshots/s " + displayedSnapshotsPerSecond, 12, 72
	DrawText "Largest frame gap " + frameGap + " ms  snapshot gap " + snapshotGap + " ms", 12, 92
	DrawText "Snapshot buffer " + Int(snapshotDelay.DelayMillis()) + " ms", 12, 112
	DrawText "WASD / arrows / on-screen stick", 12, 132
	controls.Render()
	Flip 1
Wend

controls.Free()
session.Close()
EndGraphics
