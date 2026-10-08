SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import Max2D.VirtualJoystick
Import GameNet.Session
Import GameNet.ENet

Include "protocol.bmx"

Const INPUT_INTERVAL:Int = 33
Const SNAPSHOT_BUFFER_SIZE:Int = 32
Const INTERPOLATION_DELAY_TICKS:Float = 8.0
Const SERVER_TICK_MILLIS:Float = 1000.0 / 60.0
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

Global snapshotTicks:UInt[AUTHORITATIVE_MAX_PLAYERS * SNAPSHOT_BUFFER_SIZE]
Global snapshotXs:Float[AUTHORITATIVE_MAX_PLAYERS * SNAPSHOT_BUFFER_SIZE]
Global snapshotYs:Float[AUTHORITATIVE_MAX_PLAYERS * SNAPSHOT_BUFFER_SIZE]
Global snapshotWrites:Int[AUTHORITATIVE_MAX_PLAYERS]
Global snapshotCounts:Int[AUTHORITATIVE_MAX_PLAYERS]

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

Function StoreSnapshot(entityIndex:Int, tick:UInt, x:Float, y:Float)
	Local writeIndex:Int = snapshotWrites[entityIndex]
	Local snapshotIndex:Int = entityIndex * SNAPSHOT_BUFFER_SIZE + writeIndex
	snapshotTicks[snapshotIndex] = tick
	snapshotXs[snapshotIndex] = x
	snapshotYs[snapshotIndex] = y
	snapshotWrites[entityIndex] = (writeIndex + 1) Mod SNAPSHOT_BUFFER_SIZE
	If snapshotCounts[entityIndex] < SNAPSHOT_BUFFER_SIZE Then snapshotCounts[entityIndex] :+ 1
End Function

Function SampleSnapshot:Int(entityIndex:Int, renderTick:Float, x:Float Var, y:Float Var)
	Local count:Int = snapshotCounts[entityIndex]
	If count = 0 Then Return False
	Local oldest:Int = (snapshotWrites[entityIndex] - count + SNAPSHOT_BUFFER_SIZE) Mod SNAPSHOT_BUFFER_SIZE
	Local previousIndex:Int = entityIndex * SNAPSHOT_BUFFER_SIZE + oldest
	x = snapshotXs[previousIndex]
	y = snapshotYs[previousIndex]
	If renderTick <= Float(snapshotTicks[previousIndex]) Then Return True

	For Local offset:Int = 1 Until count
		Local ringIndex:Int = (oldest + offset) Mod SNAPSHOT_BUFFER_SIZE
		Local currentIndex:Int = entityIndex * SNAPSHOT_BUFFER_SIZE + ringIndex
		Local currentTick:Float = Float(snapshotTicks[currentIndex])
		If renderTick <= currentTick Then
			Local previousTick:Float = Float(snapshotTicks[previousIndex])
			Local span:Float = currentTick - previousTick
			Local blend:Float
			If span > 0.0 Then blend = Max(0.0, Min(1.0, (renderTick - previousTick) / span))
			x = snapshotXs[previousIndex] + (snapshotXs[currentIndex] - snapshotXs[previousIndex]) * blend
			y = snapshotYs[previousIndex] + (snapshotYs[currentIndex] - snapshotYs[previousIndex]) * blend
			Return True
		End If
		previousIndex = currentIndex
	Next

	x = snapshotXs[previousIndex]
	y = snapshotYs[previousIndex]
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
Local inputSequence:UInt
Local acknowledgedInput:UInt
Local serverTick:UInt
Local inputBuffer:Byte[16]
Local inputHistorySequence:UInt[64]
Local inputHistoryX:Int[64]
Local inputHistoryY:Int[64]
Local inputHistoryTime:Int[64]
Local inputHistoryWrite:Int
Local inputHistoryCount:Int
Local nextInputTime:Int = MilliSecs()
Local latestServerTick:UInt
Local latestServerTickTime:Int
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
						snapshotCounts[index] = 0
						snapshotWrites[index] = 0
					Next
					inputHistoryWrite = 0
					inputHistoryCount = 0
					latestServerTick = 0
					latestServerTickTime = 0
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
				For Local index:Int = 0 Until players.Length
					players[index] = New SClientPlayer
					snapshotCounts[index] = 0
					snapshotWrites[index] = 0
				Next

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
								snapshotCounts[index] = 0
								snapshotWrites[index] = 0
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
								StoreSnapshot(index, tick, x, y)
								If latestServerTick = 0 Or tick > latestServerTick Then
									latestServerTick = tick
									latestServerTickTime = frameNow
								End If
								If entityId = ownEntityId Then
									serverTick = tick
									acknowledgedInput = acknowledged
									Local previousRenderX:Float = players[index].renderX
									Local previousRenderY:Float = players[index].renderY
									Local reconciledX:Float = x
									Local reconciledY:Float = y
									Local oldestInput:Int = (inputHistoryWrite - inputHistoryCount + inputHistorySequence.Length) Mod inputHistorySequence.Length
									For Local offset:Int = 0 Until inputHistoryCount
										Local historyIndex:Int = (oldestInput + offset) Mod inputHistorySequence.Length
										If inputHistorySequence[historyIndex] <= acknowledged Then Continue
										Local inputEndTime:Int = frameNow
										If offset + 1 < inputHistoryCount Then
											Local nextHistoryIndex:Int = (oldestInput + offset + 1) Mod inputHistorySequence.Length
											inputEndTime = inputHistoryTime[nextHistoryIndex]
										End If
										Local inputMillis:Int = Min(INPUT_INTERVAL, Max(0, inputEndTime - inputHistoryTime[historyIndex]))
										ApplyInput(reconciledX, reconciledY, inputHistoryX[historyIndex], inputHistoryY[historyIndex], Float(inputMillis) / 1000.0)
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
		ApplyInput(players[ownIndex].predictedX, players[ownIndex].predictedY, currentInputX, currentInputY, frameSeconds)
		Local correctionBlend:Float = Max(0.0, 1.0 - CORRECTION_RATE * frameSeconds)
		players[ownIndex].correctionX :* correctionBlend
		players[ownIndex].correctionY :* correctionBlend
		players[ownIndex].renderX = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, players[ownIndex].predictedX + players[ownIndex].correctionX))
		players[ownIndex].renderY = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, players[ownIndex].predictedY + players[ownIndex].correctionY))
	End If
	If ownIndex >= 0 And ownIndex < players.Length And players[ownIndex].active And hostPeer.IsValid() And frameNow >= nextInputTime Then
		nextInputTime = frameNow + INPUT_INTERVAL
		inputSequence :+ 1
		Local historyIndex:Int = inputHistoryWrite
		inputHistorySequence[historyIndex] = inputSequence
		inputHistoryX[historyIndex] = currentInputX
		inputHistoryY[historyIndex] = currentInputY
		inputHistoryTime[historyIndex] = frameNow
		inputHistoryWrite = (inputHistoryWrite + 1) Mod inputHistorySequence.Length
		If inputHistoryCount < inputHistorySequence.Length Then inputHistoryCount :+ 1
		Local length:Size_T = EncodeInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), inputSequence, currentInputX, currentInputY)
		session.Send(hostPeer, MSG_INPUT, GAMEPLAY_CHANNEL, EDeliveryMode.UnreliableSequenced, Byte Ptr(inputBuffer), length)
	End If

	If latestServerTick > 0 Then
		Local estimatedServerTick:Float = Float(latestServerTick) + Float(Max(0, frameNow - latestServerTickTime)) / SERVER_TICK_MILLIS
		Local renderTick:Float = estimatedServerTick - INTERPOLATION_DELAY_TICKS
		For Local index:Int = 0 Until players.Length
			If index = ownIndex Or Not players[index].active Then Continue
			If SampleSnapshot(index, renderTick, players[index].renderX, players[index].renderY) Then players[index].initialized = True
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
	DrawText "WASD / arrows / on-screen stick", 12, 112
	controls.Render()
	Flip 1
Wend

controls.Free()
session.Close()
EndGraphics
