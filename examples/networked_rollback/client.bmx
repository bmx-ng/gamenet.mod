SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import BRL.StandardIO
Import Max2D.VirtualJoystick
Import GameNet.Session
Import GameNet.ENet
Import GameNet.RollbackSession

Include "protocol.bmx"

Const WORLD_WIDTH:Int = 640
Const WORLD_HEIGHT:Int = 360
Const PLAYER_RADIUS:Int = 14
Const PLAYER_SPEED:Int = 3
Const SIMULATION_HZ:Int = 60
Const SIMULATION_STEP:Double = 1.0 / Double(SIMULATION_HZ)
Const MAX_STEPS_PER_RENDER:Int = 8
Const INPUT_DELAY_FRAMES:Int = 3
Const MAX_PREDICTION_LEAD:Int = 8
Const ROLLBACK_HISTORY:Int = 240
Const GAME_STATE_SIZE:Size_T = 16
Const HASH_INTERVAL:UInt = 30
Const HASH_QUEUE_SIZE:Int = 32
Const EFFECT_GRID_CROSSING:UInt = 1

Struct SGameState
	Field player0X:Int
	Field player0Y:Int
	Field player1X:Int
	Field player1Y:Int
End Struct

Global inputBuffer:Byte[ROLLBACK_INPUT_SIZE]
Global packetBuffer:Byte[256]

Function EncodeMovementInput:Size_T(buffer:Byte Ptr, capacity:Size_T, axisX:Int, axisY:Int)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(UInt(axisX) & $ff:UInt)
	writer.WriteUInt8(UInt(axisY) & $ff:UInt)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeMovementInput:Int(packet:SPacketView, axisX:Int Var, axisY:Int Var)
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

Type TGameSimulation Implements IRollbackSimulation, IRollbackEffectSimulation
	Private
	Field _state:SGameState
	Field _effectPayload:Byte[1]

	Public
	Method Reset()
		_state = New SGameState
		_state.player0X = WORLD_WIDTH / 3
		_state.player0Y = WORLD_HEIGHT / 2
		_state.player1X = WORLD_WIDTH * 2 / 3
		_state.player1Y = WORLD_HEIGHT / 2
	End Method

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(UInt(_state.player0X))
		writer.WriteUInt32(UInt(_state.player0Y))
		writer.WriteUInt32(UInt(_state.player1X))
		writer.WriteUInt32(UInt(_state.player1Y))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method LoadState:Int(packet:SPacketView)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local x0:UInt, y0:UInt, x1:UInt, y1:UInt
		If Not reader.ReadUInt32(x0) Or Not reader.ReadUInt32(y0) Or Not reader.ReadUInt32(x1) Or Not reader.ReadUInt32(y1) Or reader.Remaining() <> 0 Then Return False
		_state.player0X = Int(x0)
		_state.player0Y = Int(y0)
		_state.player1X = Int(x1)
		_state.player1Y = Int(y1)
		Return True
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If previous.Length() = ROLLBACK_INPUT_SIZE Then
			MemCopy(buffer, previous.Data(), ROLLBACK_INPUT_SIZE)
			Return ROLLBACK_INPUT_SIZE
		End If
		Return EncodeMovementInput(buffer, capacity, 0, 0)
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		Return SimulateFrame(frame, inputs, Null)
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[], effects:IRollbackEffectWriter)
		For Local player:Int = 0 Until ROLLBACK_PLAYER_COUNT
			Local x:Int, y:Int
			If Not DecodeMovementInput(inputs[player].Payload(), x, y) Then Return False
			Local oldX:Int = PlayerX(player)
			Local oldY:Int = PlayerY(player)
			If player = 0 Then
				_state.player0X = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, _state.player0X + x * PLAYER_SPEED))
				_state.player0Y = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, _state.player0Y + y * PLAYER_SPEED))
			Else
				_state.player1X = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, _state.player1X + x * PLAYER_SPEED))
				_state.player1Y = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, _state.player1Y + y * PLAYER_SPEED))
			End If
			If oldX / 40 <> PlayerX(player) / 40 Or oldY / 40 <> PlayerY(player) / 40 Then
				_effectPayload[0] = Byte(player)
				If effects And Not effects.Emit(EFFECT_GRID_CROSSING, Byte Ptr(_effectPayload), 1) Then Return False
			End If
		Next
		Return True
	End Method

	Method PlayerX:Int(player:Int)
		If player = 0 Then Return _state.player0X Else Return _state.player1X
	End Method

	Method PlayerY:Int(player:Int)
		If player = 0 Then Return _state.player0Y Else Return _state.player1Y
	End Method
End Type

Function ScriptedInput(frame:UInt, player:Int, x:Int Var, y:Int Var)
	Select Int((frame / 90 + UInt(player * 2)) Mod 4)
		Case 0
			x = 1
			y = 0
		Case 1
			x = 0
			y = 1
		Case 2
			x = -1
			y = 0
		Default
			x = 0
			y = -1
	End Select
End Function

Function ConfirmedFrameText:String(game:TRollbackSession)
	If Not game.HasConfirmedFrame() Then Return "none"
	Return String(game.ConfirmedFrame())
End Function

Local serverAddress:String = "127.0.0.1"
Local serverPort:Int = ROLLBACK_PORT
Local scriptedInput:Int
If AppArgs.Length > 1 Then serverAddress = AppArgs[1]
If AppArgs.Length > 2 Then serverPort = Int(AppArgs[2])
If AppArgs.Length > 3 Then scriptedInput = AppArgs[3].ToLower() = "auto"

Local transport:TENetTransport = TENetTransport.CreateClient(1, 2)
If Not transport Then Throw "Could not create the ENet client"
Local pendingPeer:SNetPeer
If transport.Connect(serverAddress, serverPort, pendingPeer) <> ETransportResult.Ok Then Throw "Could not connect to " + serverAddress
Local session:TNetSession = TNetSession.CreateClient(transport, ROLLBACK_APP_ID, ROLLBACK_APP_VERSION, Null, 0, 1, 1200)
If Not session Then Throw "Could not create the rollback client session"

?android Or ios
Graphics 960, 540, 32, 0, GRAPHICS_FULLSCREEN_DESKTOP
?Not android And Not ios
Graphics 960, 540
?
SetVirtualResolution(WORLD_WIDTH, WORLD_HEIGHT, VIRTUAL_LETTERBOX)
SetVirtualBarColor 6, 9, 16
SetClsColor 12, 18, 30

Local controls:TVirtualJoystick = TVirtualJoystick.Create(0)
Local hostPeer:SNetPeer
Local simulation:TGameSimulation
Local game:TRollbackSession
Local localPlayer:Int = -1
Local matchId:UInt
Local status:String = "Connecting to " + serverAddress + ":" + serverPort
Local accumulator:Double
Local previousTime:Int = MilliSecs()
Local lastInputSend:Int, lastPingSend:Int, roundTripMillis:Int
Local lastDiagnosticFrame:UInt
Local confirmedEffects:Int
Local lastConfirmedEffectFrame:UInt
Local reportedSimulationFailure:Int

While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local now:Int = MilliSecs()
	Local elapsed:Int = Min(100, Max(0, now - previousTime))
	previousTime = now
	Local event:SSessionEvent
	While session.Poll(event)
		Select event.Kind()
			Case ESessionEventKind.Joined
				If DecodePlayerAssignment(event.Payload(), localPlayer) Then
					hostPeer = event.Peer()
					simulation = New TGameSimulation
					simulation.Reset()
					Local config:SRollbackSessionConfig = New SRollbackSessionConfig(ROLLBACK_PLAYER_COUNT, localPlayer, ROLLBACK_HISTORY, GAME_STATE_SIZE, ROLLBACK_INPUT_SIZE, INPUT_DELAY_FRAMES, MAX_PREDICTION_LEAD, ROLLBACK_INPUT_BATCH_MAX, HASH_INTERVAL, HASH_QUEUE_SIZE)
					game = TRollbackSession.Create(simulation, config)
					status = "Joined as player " + (localPlayer + 1) + "; waiting for opponent"
				Else
					status = "Invalid player assignment"
				End If
			Case ESessionEventKind.Rejected
				status = "Join rejected (code " + event.Code() + ")"
			Case ESessionEventKind.Left
				status = "Disconnected (code " + event.Code() + ")"
				hostPeer = New SNetPeer
				If game Then game.Stop()
			Case ESessionEventKind.Message
				Select event.MessageType()
					Case ROLLBACK_MSG_START
						If game And DecodeMatch(event.Payload(), matchId) Then
							simulation.Reset()
							Local n:Size_T = EncodeMovementInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), 0, 0)
							game.Start(Byte Ptr(inputBuffer), n)
							confirmedEffects = 0
							lastConfirmedEffectFrame = 0
							reportedSimulationFailure = False
							game.SendInputs(session, hostPeer, ROLLBACK_MSG_INPUT, ROLLBACK_GAMEPLAY_CHANNEL, Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
							lastInputSend = now
							accumulator = 0.0
							status = "Match " + matchId + " running"
						End If
					Case ROLLBACK_MSG_INPUT
						If game And game.IsRunning() Then game.ReceiveInputs(1 - localPlayer, event.Payload())
					Case ROLLBACK_MSG_HASH
						If game And game.IsRunning() Then game.ReceiveHash(1 - localPlayer, event.Payload())
					Case ROLLBACK_MSG_STATE_SYNC_REQUEST
						If game And game.IsRunning() And game.IsAuthority() Then game.SendStateSyncResponse(session, hostPeer, ROLLBACK_MSG_STATE_SYNC_RESPONSE, ROLLBACK_CONTROL_CHANNEL, event.Payload(), Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
					Case ROLLBACK_MSG_STATE_SYNC_RESPONSE
						If game And game.IsRunning() Then game.ReceiveStateSync(event.Payload())
					Case ROLLBACK_MSG_STOP
						Local player:Int
						If DecodePlayerAssignment(event.Payload(), player) Then status = "Player " + (player + 1) + " left; waiting for opponent"
						If game Then game.Stop()
					Case ROLLBACK_MSG_PONG
						Local token:UInt
						If DecodePing(event.Payload(), token) Then roundTripMillis = Int(UInt(now) - token)
				End Select
			Case ESessionEventKind.Error
				status = "Session error (code " + event.Code() + ")"
		End Select
	Wend

	If hostPeer.IsValid() And now - lastPingSend >= 500 Then
		Local n:Size_T = EncodePing(Byte Ptr(packetBuffer), Size_T(packetBuffer.Length), UInt(now))
		session.Send(hostPeer, ROLLBACK_MSG_PING, ROLLBACK_CONTROL_CHANNEL, EDeliveryMode.UnreliableSequenced, Byte Ptr(packetBuffer), n)
		lastPingSend = now
	End If
	If game And game.IsRunning() And game.NeedsStateSync() Then
		game.SendStateSyncRequest(session, hostPeer, ROLLBACK_MSG_STATE_SYNC_REQUEST, ROLLBACK_CONTROL_CHANNEL, Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
	End If

	Local axisX:Float = controls.X(), axisY:Float = controls.Y()
	axisX :+ Float(KeyDown(KEY_D) Or KeyDown(KEY_RIGHT))
	axisX :- Float(KeyDown(KEY_A) Or KeyDown(KEY_LEFT))
	axisY :+ Float(KeyDown(KEY_S) Or KeyDown(KEY_DOWN))
	axisY :- Float(KeyDown(KEY_W) Or KeyDown(KEY_UP))
	Local localX:Int, localY:Int
	If axisX > 0.35 Then localX = 1 Else If axisX < -0.35 Then localX = -1
	If axisY > 0.35 Then localY = 1 Else If axisY < -0.35 Then localY = -1
	If scriptedInput And game Then ScriptedInput(game.CurrentFrame(), localPlayer, localX, localY)

	If game And game.IsRunning() Then
		accumulator :+ Double(elapsed) / 1000.0
		Local steps:Int
		While accumulator >= SIMULATION_STEP And steps < MAX_STEPS_PER_RENDER
			If Not game.CanStep() Then
				accumulator = 0.0
				Exit
			End If
			accumulator :- SIMULATION_STEP
			steps :+ 1
			Local n:Size_T = EncodeMovementInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), localX, localY)
			If Not game.Step(Byte Ptr(inputBuffer), n) Then Exit
			game.SendInputs(session, hostPeer, ROLLBACK_MSG_INPUT, ROLLBACK_GAMEPLAY_CHANNEL, Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
			game.SendReadyHash(session, hostPeer, ROLLBACK_MSG_HASH, ROLLBACK_CONTROL_CHANNEL, Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
			lastInputSend = now
			If game.CurrentFrame() Mod 300 = 0 And game.CurrentFrame() <> lastDiagnosticFrame Then
				lastDiagnosticFrame = game.CurrentFrame()
				Print "Player " + (localPlayer + 1) + " frame " + game.CurrentFrame() + ", confirmed " + ConfirmedFrameText(game) + ", rollbacks " + game.RollbackCount() + ", hashes " + game.HashesChecked() + ", desyncs " + game.HashMismatches()
			End If
		Wend
		If steps = MAX_STEPS_PER_RENDER Then accumulator = 0.0
		If now - lastInputSend >= 50 Then
			game.SendInputs(session, hostPeer, ROLLBACK_MSG_INPUT, ROLLBACK_GAMEPLAY_CHANNEL, Byte Ptr(packetBuffer), Size_T(packetBuffer.Length))
			lastInputSend = now
		End If
		If game.Failed() Then
			status = "Rollback simulation failed (reason " + Int(game.FailureReason()) + ")"
			If Not reportedSimulationFailure Then
				Print status + " at frame " + game.CurrentFrame()
				reportedSimulationFailure = True
			End If
		End If
	Else
		accumulator = 0.0
	End If

	If game Then
		Local effect:SRollbackEffect
		While game.PollConfirmedEffect(effect)
			confirmedEffects :+ 1
			lastConfirmedEffectFrame = effect.Frame()
		Wend
	End If

	Cls
	SetColor 25, 38, 57
	For Local x:Int = 0 Until WORLD_WIDTH Step 40
		DrawLine x, 0, x, WORLD_HEIGHT
	Next
	For Local y:Int = 0 Until WORLD_HEIGHT Step 40
		DrawLine 0, y, WORLD_WIDTH, y
	Next
	If game Then
		For Local player:Int = 0 Until ROLLBACK_PLAYER_COUNT
			If player = localPlayer Then SetColor 55, 170, 240 Else SetColor 245, 166, 35
			DrawOval simulation.PlayerX(player) - PLAYER_RADIUS, simulation.PlayerY(player) - PLAYER_RADIUS, PLAYER_RADIUS * 2, PLAYER_RADIUS * 2
			SetColor 255, 255, 255
			DrawText String(player + 1), simulation.PlayerX(player) - 4, simulation.PlayerY(player) - 7
		Next
	End If
	SetColor 255, 255, 255
	DrawText status, 12, 12
	DrawText "Blue: you    Orange: remote player    input delay " + INPUT_DELAY_FRAMES, 12, 32
	DrawText "Relay RTT " + roundTripMillis + " ms", 12, 52
	If game And game.IsRunning() Then
		DrawText "Frame " + game.CurrentFrame() + "    peer " + game.RemoteSimulationFrame() + "    confirmed " + ConfirmedFrameText(game), 12, 72
		DrawText "Rollbacks " + game.RollbackCount() + "    last " + game.LastRollbackDepth() + "    largest " + game.LargestRollbackDepth(), 12, 92
		DrawText "Predicted " + game.PredictedFrames() + "    matched " + game.PredictionMatches() + "    mismatched " + game.PredictionMismatches(), 12, 112
		DrawText "Hashes " + game.HashesChecked() + "    desyncs " + game.HashMismatches() + "    state syncs " + game.StateSyncCount(), 12, 132
		DrawText "Confirmed effects " + confirmedEffects + "    latest frame " + lastConfirmedEffectFrame + "    dropped " + game.DroppedConfirmedEffects(), 12, 152
		Local stepInfo:SRollbackStepInfo = game.StepInfo()
		If stepInfo.Status() = ERollbackStepStatus.WaitingForInputs Then
			DrawText "Waiting at input frame " + stepInfo.InputFrame() + "    player mask " + stepInfo.UnconfirmedPlayersMask() + "    lead " + stepInfo.PredictionLead(), 12, 172
		Else If stepInfo.NeedsStateSync() Then
			DrawText "Recovering state mismatch at frame " + stepInfo.StateSyncMismatchFrame(), 12, 172
		Else
			DrawText "Simulation ready    prediction lead " + stepInfo.PredictionLead(), 12, 172
		End If
	Else
		DrawText "Waiting for a two-player match", 12, 72
	End If
	DrawText "WASD / arrows / on-screen stick", 12, 192
	controls.Render()
	Flip 1
Wend

controls.Free()
session.Close()
EndGraphics
