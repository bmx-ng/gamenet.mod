SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import Max2D.VirtualJoystick
Import GameNet.Rollback

Const WORLD_WIDTH:Int = 640
Const WORLD_HEIGHT:Int = 360
Const PLAYER_RADIUS:Int = 14
Const PLAYER_SPEED:Int = 3
Const SIMULATION_HZ:Int = 60
Const SIMULATION_STEP:Double = 1.0 / Double(SIMULATION_HZ)
Const MAX_STEPS_PER_FRAME:Int = 8
Const PLAYER_COUNT:Int = 2
Const LOCAL_PLAYER:Int = 0
Const REMOTE_PLAYER:Int = 1
Const ROLLBACK_CAPACITY:Int = 240
Const STATE_SIZE:Size_T = 16
Const INPUT_SIZE:Size_T = 2
Const DELAY_QUEUE_CAPACITY:Int = 64

Struct SGameState
	Field localX:Int
	Field localY:Int
	Field remoteX:Int
	Field remoteY:Int
End Struct

Global stateBuffer:Byte[STATE_SIZE]
Global inputBuffer:Byte[INPUT_SIZE]
Global delayValid:Byte[DELAY_QUEUE_CAPACITY]
Global delaySourceFrame:UInt[DELAY_QUEUE_CAPACITY]
Global delayDeliveryFrame:UInt[DELAY_QUEUE_CAPACITY]
Global delayAxisX:Int[DELAY_QUEUE_CAPACITY]
Global delayAxisY:Int[DELAY_QUEUE_CAPACITY]

Function EncodeState:Size_T(state:SGameState)
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(stateBuffer), Size_T(stateBuffer.Length))
	writer.WriteUInt32(UInt(state.localX))
	writer.WriteUInt32(UInt(state.localY))
	writer.WriteUInt32(UInt(state.remoteX))
	writer.WriteUInt32(UInt(state.remoteY))
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeState:Int(packet:SPacketView, state:SGameState Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local localX:UInt
	Local localY:UInt
	Local remoteX:UInt
	Local remoteY:UInt
	If Not reader.ReadUInt32(localX) Or Not reader.ReadUInt32(localY) Then Return False
	If Not reader.ReadUInt32(remoteX) Or Not reader.ReadUInt32(remoteY) Then Return False
	If reader.Remaining() <> 0 Then Return False
	state.localX = Int(localX)
	state.localY = Int(localY)
	state.remoteX = Int(remoteX)
	state.remoteY = Int(remoteY)
	Return True
End Function

Function EncodeInput:Size_T(axisX:Int, axisY:Int)
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length))
	writer.WriteUInt8(UInt(axisX))
	writer.WriteUInt8(UInt(axisY))
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeInput:Int(packet:SPacketView, axisX:Int Var, axisY:Int Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local encodedX:UInt
	Local encodedY:UInt
	If Not reader.ReadUInt8(encodedX) Or Not reader.ReadUInt8(encodedY) Or reader.Remaining() <> 0 Then Return False
	axisX = Int(encodedX)
	axisY = Int(encodedY)
	If axisX > 127 Then axisX :- 256
	If axisY > 127 Then axisY :- 256
	Return True
End Function

Function ApplyInput(state:SGameState Var, player:Int, axisX:Int, axisY:Int)
	If player = LOCAL_PLAYER Then
		state.localX :+ axisX * PLAYER_SPEED
		state.localY :+ axisY * PLAYER_SPEED
		state.localX = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, state.localX))
		state.localY = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, state.localY))
	Else
		state.remoteX :+ axisX * PLAYER_SPEED
		state.remoteY :+ axisY * PLAYER_SPEED
		state.remoteX = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, state.remoteX))
		state.remoteY = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, state.remoteY))
	End If
End Function

Function SimulateFrame:Int(rollback:TRollbackBuffer, frame:UInt, state:SGameState Var)
	For Local player:Int = 0 Until PLAYER_COUNT
		Local input:SRollbackInput
		If Not rollback.GetInput(player, frame, input) Then Return False
		Local axisX:Int
		Local axisY:Int
		If Not DecodeInput(input.Payload(), axisX, axisY) Then Return False
		ApplyInput(state, player, axisX, axisY)
	Next
	Return True
End Function

Function RemoteInput(frame:UInt, axisX:Int Var, axisY:Int Var)
	Select Int((frame / 90) Mod 4)
		Case 0
			axisX = 1
			axisY = 0
		Case 1
			axisX = 0
			axisY = 1
		Case 2
			axisX = -1
			axisY = 0
		Default
			axisX = 0
			axisY = -1
	End Select
End Function

Function ArtificialDelay:Int(frame:UInt)
	If frame Mod 240 >= 180 And frame Mod 240 < 190 Then Return 18
	If frame Mod 120 >= 80 And frame Mod 120 < 84 Then Return 12
	Return 6
End Function

Function QueueRemoteInput(frame:UInt, axisX:Int, axisY:Int, delay:Int)
	Local slot:Int = Int(frame Mod UInt(DELAY_QUEUE_CAPACITY))
	delayValid[slot] = True
	delaySourceFrame[slot] = frame
	delayDeliveryFrame[slot] = frame + UInt(delay)
	delayAxisX[slot] = axisX
	delayAxisY[slot] = axisY
End Function

Function DeliverRemoteInputs(rollback:TRollbackBuffer, currentFrame:UInt, lastConfirmedFrame:UInt Var, hasLastConfirmed:Int Var, lastAxisX:Int Var, lastAxisY:Int Var)
	For Local slot:Int = 0 Until DELAY_QUEUE_CAPACITY
		If Not delayValid[slot] Or RollbackFrameDelta(currentFrame, delayDeliveryFrame[slot]) < 0 Then Continue
		Local length:Size_T = EncodeInput(delayAxisX[slot], delayAxisY[slot])
		rollback.ConfirmInput(REMOTE_PLAYER, delaySourceFrame[slot], Byte Ptr(inputBuffer), length)
		If Not hasLastConfirmed Or RollbackFrameAfter(delaySourceFrame[slot], lastConfirmedFrame) Then
			hasLastConfirmed = True
			lastConfirmedFrame = delaySourceFrame[slot]
			lastAxisX = delayAxisX[slot]
			lastAxisY = delayAxisY[slot]
		End If
		delayValid[slot] = False
	Next
End Function

Function FindPriorRemoteInput(rollback:TRollbackBuffer, frame:UInt, axisX:Int Var, axisY:Int Var)
	axisX = 0
	axisY = 0
	For Local age:Int = 1 Until rollback.Capacity()
		Local input:SRollbackInput
		If rollback.GetInput(REMOTE_PLAYER, frame - UInt(age), input) And input.Status() = ERollbackInputStatus.Confirmed Then
			DecodeInput(input.Payload(), axisX, axisY)
			Return
		End If
	Next
End Function

Function PerformRollback:Int(rollback:TRollbackBuffer, currentFrame:UInt, state:SGameState Var)
	If Not rollback.NeedsRollback() Then Return 0
	Local startFrame:UInt = rollback.RollbackFrame()
	Local savedState:SPacketView
	If Not rollback.GetState(startFrame, savedState) Or Not DecodeState(savedState, state) Then Return -1
	Local replayRemoteX:Int
	Local replayRemoteY:Int
	FindPriorRemoteInput(rollback, startFrame, replayRemoteX, replayRemoteY)
	Local depth:Int = RollbackFrameDelta(currentFrame, startFrame)
	If depth < 0 Or depth >= rollback.Capacity() Then Return -1
	For Local offset:Int = 0 Until depth
		Local frame:UInt = startFrame + UInt(offset)
		Local length:Size_T = EncodeState(state)
		If Not rollback.SaveState(frame, Byte Ptr(stateBuffer), length) Then Return -1
		Local remote:SRollbackInput
		If Not rollback.GetInput(REMOTE_PLAYER, frame, remote) Then Return -1
		If remote.Status() = ERollbackInputStatus.Confirmed Then
			If Not DecodeInput(remote.Payload(), replayRemoteX, replayRemoteY) Then Return -1
		Else
			length = EncodeInput(replayRemoteX, replayRemoteY)
			If Not rollback.PredictInput(REMOTE_PLAYER, frame, Byte Ptr(inputBuffer), length) Then Return -1
		End If
		If Not SimulateFrame(rollback, frame, state) Then Return -1
	Next
	rollback.ClearRollback()
	Return depth
End Function

?android Or ios
Graphics 960, 540, 32, 0, GRAPHICS_FULLSCREEN_DESKTOP
?Not android And Not ios
Graphics 960, 540
?
SetVirtualResolution(WORLD_WIDTH, WORLD_HEIGHT, VIRTUAL_LETTERBOX)
SetVirtualBarColor 6, 9, 16
SetClsColor 12, 18, 30

Local controls:TVirtualJoystick = TVirtualJoystick.Create(0)
Local rollback:TRollbackBuffer = TRollbackBuffer.Create(PLAYER_COUNT, ROLLBACK_CAPACITY, STATE_SIZE, INPUT_SIZE)
If Not rollback Then Throw "Could not create rollback storage"
Local state:SGameState
state.localX = WORLD_WIDTH / 3
state.localY = WORLD_HEIGHT / 2
state.remoteX = WORLD_WIDTH * 2 / 3
state.remoteY = WORLD_HEIGHT / 2
Local currentFrame:UInt
Local hasLastConfirmedRemote:Int
Local lastConfirmedRemoteFrame:UInt
Local lastConfirmedRemoteX:Int
Local lastConfirmedRemoteY:Int
Local rollbackCount:Int
Local lastRollbackDepth:Int
Local largestRollbackDepth:Int
Local status:String = "Deterministic local delay harness"
Local accumulator:Double
Local previousTime:Int = MilliSecs()

While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local now:Int = MilliSecs()
	Local elapsed:Int = Min(100, Max(0, now - previousTime))
	previousTime = now
	accumulator :+ Double(elapsed) / 1000.0

	Local axisX:Float = controls.X()
	Local axisY:Float = controls.Y()
	axisX :+ Float(KeyDown(KEY_D) Or KeyDown(KEY_RIGHT))
	axisX :- Float(KeyDown(KEY_A) Or KeyDown(KEY_LEFT))
	axisY :+ Float(KeyDown(KEY_S) Or KeyDown(KEY_DOWN))
	axisY :- Float(KeyDown(KEY_W) Or KeyDown(KEY_UP))
	Local localAxisX:Int
	Local localAxisY:Int
	If axisX > 0.35 Then localAxisX = 1 Else If axisX < -0.35 Then localAxisX = -1
	If axisY > 0.35 Then localAxisY = 1 Else If axisY < -0.35 Then localAxisY = -1

	Local steps:Int
	While accumulator >= SIMULATION_STEP And steps < MAX_STEPS_PER_FRAME
		accumulator :- SIMULATION_STEP
		steps :+ 1
		DeliverRemoteInputs(rollback, currentFrame, lastConfirmedRemoteFrame, hasLastConfirmedRemote, lastConfirmedRemoteX, lastConfirmedRemoteY)
		If rollback.NeedsRollback() Then
			lastRollbackDepth = PerformRollback(rollback, currentFrame, state)
			If lastRollbackDepth < 0 Then
				status = "Rollback failed"
				Exit
			End If
			rollbackCount :+ 1
			largestRollbackDepth = Max(largestRollbackDepth, lastRollbackDepth)
		End If

		Local length:Size_T = EncodeState(state)
		If Not rollback.SaveState(currentFrame, Byte Ptr(stateBuffer), length) Then
			status = "State history full"
			Exit
		End If
		length = EncodeInput(localAxisX, localAxisY)
		rollback.ConfirmInput(LOCAL_PLAYER, currentFrame, Byte Ptr(inputBuffer), length)

		Local actualRemoteX:Int
		Local actualRemoteY:Int
		RemoteInput(currentFrame, actualRemoteX, actualRemoteY)
		Local delay:Int = ArtificialDelay(currentFrame)
		QueueRemoteInput(currentFrame, actualRemoteX, actualRemoteY, delay)
		length = EncodeInput(lastConfirmedRemoteX, lastConfirmedRemoteY)
		If Not rollback.PredictInput(REMOTE_PLAYER, currentFrame, Byte Ptr(inputBuffer), length) Then
			status = "Could not store predicted input"
			Exit
		End If
		If Not SimulateFrame(rollback, currentFrame, state) Then
			status = "Could not simulate frame"
			Exit
		End If
		currentFrame :+ 1
	Wend
	If steps = MAX_STEPS_PER_FRAME Then accumulator = 0.0

	Cls
	SetColor 25, 38, 57
	For Local x:Int = 0 Until WORLD_WIDTH Step 40
		DrawLine x, 0, x, WORLD_HEIGHT
	Next
	For Local y:Int = 0 Until WORLD_HEIGHT Step 40
		DrawLine 0, y, WORLD_WIDTH, y
	Next
	SetColor 55, 170, 240
	DrawOval state.localX - PLAYER_RADIUS, state.localY - PLAYER_RADIUS, PLAYER_RADIUS * 2, PLAYER_RADIUS * 2
	SetColor 245, 166, 35
	DrawOval state.remoteX - PLAYER_RADIUS, state.remoteY - PLAYER_RADIUS, PLAYER_RADIUS * 2, PLAYER_RADIUS * 2
	SetColor 255, 255, 255
	DrawText status, 12, 12
	DrawText "Blue: local confirmed input    Orange: delayed remote input", 12, 32
	DrawText "Frame " + currentFrame + "    rollbacks " + rollbackCount, 12, 52
	DrawText "Last rollback " + lastRollbackDepth + " frames    largest " + largestRollbackDepth, 12, 72
	If rollback.HasConfirmedFrame() Then DrawText "Fully confirmed through frame " + rollback.ConfirmedFrame(), 12, 92
	DrawText "Remote input delay " + ArtificialDelay(currentFrame) + " frames", 12, 112
	DrawText "WASD / arrows / on-screen stick", 12, 132
	controls.Render()
	Flip 1
Wend

controls.Free()
EndGraphics
