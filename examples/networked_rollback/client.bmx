SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import BRL.StandardIO
Import Max2D.VirtualJoystick
Import GameNet.Session
Import GameNet.ENet
Import GameNet.Rollback

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

Struct SGameState
	Field player0X:Int
	Field player0Y:Int
	Field player1X:Int
	Field player1Y:Int
End Struct

Global stateBuffer:Byte[GAME_STATE_SIZE]
Global inputBuffer:Byte[ROLLBACK_INPUT_SIZE]
Global packetBuffer:Byte[256]
Global batchFrames:UInt[ROLLBACK_INPUT_BATCH_MAX]
Global batchAxisXs:Int[ROLLBACK_INPUT_BATCH_MAX]
Global batchAxisYs:Int[ROLLBACK_INPUT_BATCH_MAX]

Function EncodeGameState:Size_T(state:SGameState)
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(stateBuffer), Size_T(stateBuffer.Length))
	writer.WriteUInt32(UInt(state.player0X))
	writer.WriteUInt32(UInt(state.player0Y))
	writer.WriteUInt32(UInt(state.player1X))
	writer.WriteUInt32(UInt(state.player1Y))
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeGameState:Int(packet:SPacketView, state:SGameState Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local player0X:UInt
	Local player0Y:UInt
	Local player1X:UInt
	Local player1Y:UInt
	If Not reader.ReadUInt32(player0X) Or Not reader.ReadUInt32(player0Y) Then Return False
	If Not reader.ReadUInt32(player1X) Or Not reader.ReadUInt32(player1Y) Or reader.Remaining() <> 0 Then Return False
	state.player0X = Int(player0X)
	state.player0Y = Int(player0Y)
	state.player1X = Int(player1X)
	state.player1Y = Int(player1Y)
	Return True
End Function

Function ApplyGameInput(state:SGameState Var, player:Int, axisX:Int, axisY:Int)
	If player = 0 Then
		state.player0X :+ axisX * PLAYER_SPEED
		state.player0Y :+ axisY * PLAYER_SPEED
		state.player0X = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, state.player0X))
		state.player0Y = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, state.player0Y))
	Else
		state.player1X :+ axisX * PLAYER_SPEED
		state.player1Y :+ axisY * PLAYER_SPEED
		state.player1X = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, state.player1X))
		state.player1Y = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, state.player1Y))
	End If
End Function

Function SimulateGameFrame:Int(rollback:TRollbackBuffer, frame:UInt, state:SGameState Var)
	For Local player:Int = 0 Until ROLLBACK_PLAYER_COUNT
		Local input:SRollbackInput
		If Not rollback.GetInput(player, frame, input) Then Return False
		Local axisX:Int
		Local axisY:Int
		If Not DecodeMovementInput(input.Payload(), axisX, axisY) Then Return False
		ApplyGameInput(state, player, axisX, axisY)
	Next
	Return True
End Function

Function ScriptedInput(frame:UInt, player:Int, axisX:Int Var, axisY:Int Var)
	Select Int((frame / 90 + UInt(player * 2)) Mod 4)
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

Type TRollbackGame
	Private
	Field _rollback:TRollbackBuffer
	Field _state:SGameState
	Field _localPlayer:Int
	Field _remotePlayer:Int
	Field _matchId:UInt
	Field _currentFrame:UInt
	Field _running:Int
	Field _failed:Int
	Field _hasRemoteFrame:Int
	Field _latestRemoteInputFrame:UInt
	Field _remoteSimulationFrame:UInt
	Field _rollbackCount:Int
	Field _lastRollbackDepth:Int
	Field _largestRollbackDepth:Int
	Field _predictedFrames:Int
	Field _matchedPredictions:Int
	Field _mismatchedPredictions:Int
	Field _rejectedInputs:Int
	Field _hashesChecked:Int
	Field _hashMismatches:Int
	Field _hasLastHashSent:Int
	Field _lastHashSent:UInt
	Field _remoteHashValid:Byte[]
	Field _remoteHashFrames:UInt[]
	Field _remoteHashes:UInt[]

	Method FindPriorConfirmedInput(player:Int, frame:UInt, axisX:Int Var, axisY:Int Var)
		axisX = 0
		axisY = 0
		For Local age:Int = 1 Until _rollback.Capacity()
			Local input:SRollbackInput
			If _rollback.GetInput(player, frame - UInt(age), input) And input.Status() = ERollbackInputStatus.Confirmed Then
				DecodeMovementInput(input.Payload(), axisX, axisY)
				Return
			End If
		Next
	End Method

	Method PerformRollback:Int()
		If Not _rollback.NeedsRollback() Then Return True
		Local startFrame:UInt = _rollback.RollbackFrame()
		Local savedState:SPacketView
		If Not _rollback.GetState(startFrame, savedState) Or Not DecodeGameState(savedState, _state) Then Return False
		Local predictedRemoteX:Int
		Local predictedRemoteY:Int
		FindPriorConfirmedInput(_remotePlayer, startFrame, predictedRemoteX, predictedRemoteY)
		Local depth:Int = RollbackFrameDelta(_currentFrame, startFrame)
		If depth < 0 Or depth >= _rollback.Capacity() Then Return False
		For Local offset:Int = 0 Until depth
			Local frame:UInt = startFrame + UInt(offset)
			Local length:Size_T = EncodeGameState(_state)
			If Not _rollback.SaveState(frame, Byte Ptr(stateBuffer), length) Then Return False
			Local remote:SRollbackInput
			If Not _rollback.GetInput(_remotePlayer, frame, remote) Then Return False
			If remote.Status() = ERollbackInputStatus.Confirmed Then
				If Not DecodeMovementInput(remote.Payload(), predictedRemoteX, predictedRemoteY) Then Return False
			Else
				length = EncodeMovementInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), predictedRemoteX, predictedRemoteY)
				If Not _rollback.PredictInput(_remotePlayer, frame, Byte Ptr(inputBuffer), length) Then Return False
			End If
			If Not SimulateGameFrame(_rollback, frame, _state) Then Return False
		Next
		Local length:Size_T = EncodeGameState(_state)
		If Not _rollback.SaveState(_currentFrame, Byte Ptr(stateBuffer), length) Then Return False
		_rollback.ClearRollback()
		_rollbackCount :+ 1
		_lastRollbackDepth = depth
		_largestRollbackDepth = Max(_largestRollbackDepth, depth)
		Return True
	End Method

	Method CheckRemoteHashes()
		If Not _rollback.HasConfirmedFrame() Then Return
		Local confirmedStateFrame:UInt = _rollback.ConfirmedFrame() + 1
		For Local slot:Int = 0 Until _remoteHashValid.Length
			If Not _remoteHashValid[slot] Then Continue
			If RollbackFrameAfter(_remoteHashFrames[slot], confirmedStateFrame) Or RollbackFrameAfter(_remoteHashFrames[slot], _currentFrame) Then Continue
			Local localHash:UInt = _rollback.StateHash(_remoteHashFrames[slot])
			If localHash <> 0 Then
				_hashesChecked :+ 1
				If localHash <> _remoteHashes[slot] Then _hashMismatches :+ 1
			End If
			_remoteHashValid[slot] = False
		Next
	End Method

	Public
	Method New(player:Int)
		_localPlayer = player
		_remotePlayer = 1 - player
		_rollback = TRollbackBuffer.Create(ROLLBACK_PLAYER_COUNT, ROLLBACK_HISTORY, GAME_STATE_SIZE, ROLLBACK_INPUT_SIZE)
		_remoteHashValid = New Byte[HASH_QUEUE_SIZE]
		_remoteHashFrames = New UInt[HASH_QUEUE_SIZE]
		_remoteHashes = New UInt[HASH_QUEUE_SIZE]
	End Method

	Method Start(matchId:UInt)
		_matchId = matchId
		_currentFrame = 0
		_running = True
		_failed = False
		_hasRemoteFrame = False
		_latestRemoteInputFrame = 0
		_remoteSimulationFrame = 0
		_rollbackCount = 0
		_lastRollbackDepth = 0
		_largestRollbackDepth = 0
		_predictedFrames = 0
		_matchedPredictions = 0
		_mismatchedPredictions = 0
		_rejectedInputs = 0
		_hashesChecked = 0
		_hashMismatches = 0
		_hasLastHashSent = False
		_rollback.Clear()
		For Local slot:Int = 0 Until _remoteHashValid.Length
			_remoteHashValid[slot] = False
		Next
		_state = New SGameState
		_state.player0X = WORLD_WIDTH / 3
		_state.player0Y = WORLD_HEIGHT / 2
		_state.player1X = WORLD_WIDTH * 2 / 3
		_state.player1Y = WORLD_HEIGHT / 2
		For Local frame:UInt = 0 Until UInt(INPUT_DELAY_FRAMES)
			Local length:Size_T = EncodeMovementInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), 0, 0)
			_rollback.ConfirmInput(_localPlayer, frame, Byte Ptr(inputBuffer), length)
		Next
		Local length:Size_T = EncodeGameState(_state)
		_rollback.SaveState(0, Byte Ptr(stateBuffer), length)
	End Method

	Method Stop()
		_running = False
	End Method

	Method ReceiveInputs:Int(packet:SPacketView)
		Local simulatedFrame:UInt
		Local count:Int
		If Not DecodeRollbackInputBatch(packet, simulatedFrame, batchFrames, batchAxisXs, batchAxisYs, count) Then Return False
		If Not _hasRemoteFrame Or RollbackFrameAfter(simulatedFrame, _remoteSimulationFrame) Then _remoteSimulationFrame = simulatedFrame
		For Local index:Int = 0 Until count
			Local length:Size_T = EncodeMovementInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), batchAxisXs[index], batchAxisYs[index])
			Local result:ERollbackConfirmResult = _rollback.ConfirmInput(_remotePlayer, batchFrames[index], Byte Ptr(inputBuffer), length)
			Select result
				Case ERollbackConfirmResult.PredictionMatched
					_matchedPredictions :+ 1
				Case ERollbackConfirmResult.PredictionMismatched
					_mismatchedPredictions :+ 1
				Case ERollbackConfirmResult.Rejected
					_rejectedInputs :+ 1
			End Select
			If result <> ERollbackConfirmResult.Rejected Then
				If Not _hasRemoteFrame Or RollbackFrameAfter(batchFrames[index], _latestRemoteInputFrame) Then _latestRemoteInputFrame = batchFrames[index]
				_hasRemoteFrame = True
			End If
		Next
		Return True
	End Method

	Method ReceiveHash:Int(packet:SPacketView)
		Local frame:UInt
		Local hash:UInt
		If Not DecodeStateHash(packet, frame, hash) Then Return False
		Local slot:Int = Int(frame Mod UInt(_remoteHashValid.Length))
		_remoteHashValid[slot] = True
		_remoteHashFrames[slot] = frame
		_remoteHashes[slot] = hash
		CheckRemoteHashes()
		Return True
	End Method

	Method CanStep:Int()
		If Not _running Or _failed Then Return False
		If Not _rollback.HasConfirmedFrame() Then Return _currentFrame <= UInt(MAX_PREDICTION_LEAD)
		Local nextUnconfirmedFrame:UInt = _rollback.ConfirmedFrame() + 1
		Return RollbackFrameDelta(_currentFrame, nextUnconfirmedFrame) <= MAX_PREDICTION_LEAD
	End Method

	Method Step:Int(axisX:Int, axisY:Int)
		If Not CanStep() Then Return False
		If Not PerformRollback() Then
			_failed = True
			Return False
		End If

		Local length:Size_T = EncodeGameState(_state)
		If Not _rollback.SaveState(_currentFrame, Byte Ptr(stateBuffer), length) Then
			_failed = True
			Return False
		End If

		Local scheduledFrame:UInt = _currentFrame + UInt(INPUT_DELAY_FRAMES)
		length = EncodeMovementInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), axisX, axisY)
		If _rollback.ConfirmInput(_localPlayer, scheduledFrame, Byte Ptr(inputBuffer), length) = ERollbackConfirmResult.Rejected Then
			_failed = True
			Return False
		End If

		Local remote:SRollbackInput
		If Not _rollback.GetInput(_remotePlayer, _currentFrame, remote) Then
			Local predictedX:Int
			Local predictedY:Int
			FindPriorConfirmedInput(_remotePlayer, _currentFrame, predictedX, predictedY)
			length = EncodeMovementInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), predictedX, predictedY)
			If Not _rollback.PredictInput(_remotePlayer, _currentFrame, Byte Ptr(inputBuffer), length) Then
				_failed = True
				Return False
			End If
			_predictedFrames :+ 1
		End If

		If Not SimulateGameFrame(_rollback, _currentFrame, _state) Then
			_failed = True
			Return False
		End If
		_currentFrame :+ 1
		length = EncodeGameState(_state)
		If Not _rollback.SaveState(_currentFrame, Byte Ptr(stateBuffer), length) Then
			_failed = True
			Return False
		End If
		CheckRemoteHashes()
		Return True
	End Method

	Method SendInputs:ETransportResult(session:TNetSession, peer:SNetPeer)
		If Not _running Or Not peer.IsValid() Then Return ETransportResult.InvalidPeer
		Local newestFrame:UInt = _currentFrame + UInt(INPUT_DELAY_FRAMES - 1)
		Local count:Int
		For Local age:Int = ROLLBACK_INPUT_BATCH_MAX - 1 To 0 Step -1
			If UInt(age) > newestFrame Then Continue
			Local frame:UInt = newestFrame - UInt(age)
			Local input:SRollbackInput
			If Not _rollback.GetInput(_localPlayer, frame, input) Or input.Status() <> ERollbackInputStatus.Confirmed Then Continue
			batchFrames[count] = frame
			If Not DecodeMovementInput(input.Payload(), batchAxisXs[count], batchAxisYs[count]) Then Return ETransportResult.Failed
			count :+ 1
		Next
		Local length:Size_T = EncodeRollbackInputBatch(Byte Ptr(packetBuffer), Size_T(packetBuffer.Length), _currentFrame, batchFrames, batchAxisXs, batchAxisYs, count)
		If length = 0 Then Return ETransportResult.Failed
		Return session.Send(peer, ROLLBACK_MSG_INPUT, ROLLBACK_GAMEPLAY_CHANNEL, EDeliveryMode.UnreliableSequenced, Byte Ptr(packetBuffer), length)
	End Method

	Method SendReadyHash:ETransportResult(session:TNetSession, peer:SNetPeer)
		If Not _running Or Not _rollback.HasConfirmedFrame() Then Return ETransportResult.WouldBlock
		Local confirmedStateFrame:UInt = _rollback.ConfirmedFrame() + 1
		Local frame:UInt = (confirmedStateFrame / HASH_INTERVAL) * HASH_INTERVAL
		If frame = 0 Or RollbackFrameAfter(frame, _currentFrame) Then Return ETransportResult.WouldBlock
		If _hasLastHashSent And Not RollbackFrameAfter(frame, _lastHashSent) Then Return ETransportResult.WouldBlock
		Local hash:UInt = _rollback.StateHash(frame)
		If hash = 0 Then Return ETransportResult.WouldBlock
		Local length:Size_T = EncodeStateHash(Byte Ptr(packetBuffer), Size_T(packetBuffer.Length), frame, hash)
		Local result:ETransportResult = session.Send(peer, ROLLBACK_MSG_HASH, ROLLBACK_CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(packetBuffer), length)
		If result = ETransportResult.Ok Then
			_hasLastHashSent = True
			_lastHashSent = frame
		End If
		Return result
	End Method

	Method IsRunning:Int()
		Return _running
	End Method

	Method Failed:Int()
		Return _failed
	End Method

	Method LocalPlayer:Int()
		Return _localPlayer
	End Method

	Method MatchId:UInt()
		Return _matchId
	End Method

	Method CurrentFrame:UInt()
		Return _currentFrame
	End Method

	Method RemoteSimulationFrame:UInt()
		Return _remoteSimulationFrame
	End Method

	Method ConfirmedFrame:String()
		If Not _rollback.HasConfirmedFrame() Then Return "none"
		Return String(_rollback.ConfirmedFrame())
	End Method

	Method RollbackCount:Int()
		Return _rollbackCount
	End Method

	Method LastRollbackDepth:Int()
		Return _lastRollbackDepth
	End Method

	Method LargestRollbackDepth:Int()
		Return _largestRollbackDepth
	End Method

	Method PredictedFrames:Int()
		Return _predictedFrames
	End Method

	Method PredictionMatches:Int()
		Return _matchedPredictions
	End Method

	Method PredictionMismatches:Int()
		Return _mismatchedPredictions
	End Method

	Method RejectedInputs:Int()
		Return _rejectedInputs
	End Method

	Method HashesChecked:Int()
		Return _hashesChecked
	End Method

	Method HashMismatches:Int()
		Return _hashMismatches
	End Method

	Method PlayerX:Int(player:Int)
		If player = 0 Then Return _state.player0X
		Return _state.player1X
	End Method

	Method PlayerY:Int(player:Int)
		If player = 0 Then Return _state.player0Y
		Return _state.player1Y
	End Method
End Type

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
Local game:TRollbackGame
Local status:String = "Connecting to " + serverAddress + ":" + serverPort
Local accumulator:Double
Local previousTime:Int = MilliSecs()
Local lastInputSend:Int
Local lastPingSend:Int
Local roundTripMillis:Int
Local lastDiagnosticFrame:UInt

While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local now:Int = MilliSecs()
	Local elapsed:Int = Min(100, Max(0, now - previousTime))
	previousTime = now

	Local event:SSessionEvent
	While session.Poll(event)
		Select event.Kind()
			Case ESessionEventKind.Joined
				Local player:Int
				If DecodePlayerAssignment(event.Payload(), player) Then
					hostPeer = event.Peer()
					game = New TRollbackGame(player)
					status = "Joined as player " + (player + 1) + "; waiting for opponent"
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
						Local matchId:UInt
						If game And DecodeMatch(event.Payload(), matchId) Then
							game.Start(matchId)
							game.SendInputs(session, hostPeer)
							lastInputSend = now
							accumulator = 0.0
							status = "Match " + matchId + " running"
						End If

					Case ROLLBACK_MSG_INPUT
						If game And game.IsRunning() Then game.ReceiveInputs(event.Payload())

					Case ROLLBACK_MSG_HASH
						If game And game.IsRunning() Then game.ReceiveHash(event.Payload())

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
		Local length:Size_T = EncodePing(Byte Ptr(packetBuffer), Size_T(packetBuffer.Length), UInt(now))
		session.Send(hostPeer, ROLLBACK_MSG_PING, ROLLBACK_CONTROL_CHANNEL, EDeliveryMode.UnreliableSequenced, Byte Ptr(packetBuffer), length)
		lastPingSend = now
	End If

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
	If scriptedInput And game Then ScriptedInput(game.CurrentFrame(), game.LocalPlayer(), localAxisX, localAxisY)

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
			If Not game.Step(localAxisX, localAxisY) Then Exit
			game.SendInputs(session, hostPeer)
			game.SendReadyHash(session, hostPeer)
			lastInputSend = now
			If game.CurrentFrame() Mod 300 = 0 And game.CurrentFrame() <> lastDiagnosticFrame Then
				lastDiagnosticFrame = game.CurrentFrame()
				Print "Player " + (game.LocalPlayer() + 1) + " frame " + game.CurrentFrame() + ", confirmed " + game.ConfirmedFrame() + ", rollbacks " + game.RollbackCount() + ", hashes " + game.HashesChecked() + ", desyncs " + game.HashMismatches()
			End If
		Wend
		If steps = MAX_STEPS_PER_RENDER Then accumulator = 0.0
		If now - lastInputSend >= 50 Then
			game.SendInputs(session, hostPeer)
			lastInputSend = now
		End If
		If game.Failed() Then status = "Rollback simulation failed"
	Else
		accumulator = 0.0
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
			If player = game.LocalPlayer() Then
				SetColor 55, 170, 240
			Else
				SetColor 245, 166, 35
			End If
			DrawOval game.PlayerX(player) - PLAYER_RADIUS, game.PlayerY(player) - PLAYER_RADIUS, PLAYER_RADIUS * 2, PLAYER_RADIUS * 2
			SetColor 255, 255, 255
			DrawText String(player + 1), game.PlayerX(player) - 4, game.PlayerY(player) - 7
		Next
	End If

	SetColor 255, 255, 255
	DrawText status, 12, 12
	DrawText "Blue: you    Orange: remote player    input delay " + INPUT_DELAY_FRAMES, 12, 32
	DrawText "Relay RTT " + roundTripMillis + " ms", 12, 52
	If game And game.IsRunning() Then
		DrawText "Frame " + game.CurrentFrame() + "    peer " + game.RemoteSimulationFrame() + "    confirmed " + game.ConfirmedFrame(), 12, 72
		DrawText "Rollbacks " + game.RollbackCount() + "    last " + game.LastRollbackDepth() + "    largest " + game.LargestRollbackDepth(), 12, 92
		DrawText "Predicted " + game.PredictedFrames() + "    matched " + game.PredictionMatches() + "    mismatched " + game.PredictionMismatches(), 12, 112
		DrawText "Hashes " + game.HashesChecked() + "    desyncs " + game.HashMismatches() + "    rejected inputs " + game.RejectedInputs(), 12, 132
	Else
		DrawText "Waiting for a two-player match", 12, 72
	End If
	DrawText "WASD / arrows / on-screen stick", 12, 152
	controls.Render()
	Flip 1
Wend

controls.Free()
session.Close()
EndGraphics
