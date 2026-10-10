Const REBOUND_APP_ID:UInt = $52424e44 ' RBND
Const REBOUND_APP_VERSION:UInt = 2

Const REBOUND_CONTROL_CHANNEL:UInt = 0
Const REBOUND_GAMEPLAY_CHANNEL:UInt = 1

Const REBOUND_MSG_START:UInt = 1
Const REBOUND_MSG_INPUT:UInt = 2
Const REBOUND_MSG_HASH:UInt = 3
Const REBOUND_MSG_STATE_SYNC_REQUEST:UInt = 4
Const REBOUND_MSG_STATE_SYNC_RESPONSE:UInt = 5

Const REBOUND_PLAYER_COUNT:Int = 2
Const REBOUND_INPUT_SIZE:Size_T = 2
Const REBOUND_STATE_SIZE:Size_T = 60
Const REBOUND_INPUT_BATCH_MAX:Int = 12

Const REBOUND_WORLD_WIDTH:Int = 800
Const REBOUND_WORLD_HEIGHT:Int = 450
Const REBOUND_SCALE:Int = 16
Const REBOUND_PADDLE_WIDTH:Int = 14 * REBOUND_SCALE
Const REBOUND_PADDLE_HEIGHT:Int = 82 * REBOUND_SCALE
Const REBOUND_PADDLE_SPEED:Int = 6 * REBOUND_SCALE
Const REBOUND_LEFT_X:Int = 54 * REBOUND_SCALE
Const REBOUND_RIGHT_X:Int = (REBOUND_WORLD_WIDTH - 54) * REBOUND_SCALE
Const REBOUND_BALL_RADIUS:Int = 8 * REBOUND_SCALE
Const REBOUND_INITIAL_BALL_SPEED:Int = 5 * REBOUND_SCALE
Const REBOUND_MAX_BALL_SPEED:Int = 10 * REBOUND_SCALE
Const REBOUND_BALL_ACCELERATION:Int = REBOUND_SCALE / 3
Const REBOUND_SERVE_FRAMES:Int = 75
Const REBOUND_WIN_SCORE:Int = 5
Const REBOUND_MAX_ENERGY:Int = 100
Const REBOUND_POWER_COST:Int = 50

Const REBOUND_INPUT_POWER:UInt = 1

Const REBOUND_EFFECT_PADDLE:UInt = 1
Const REBOUND_EFFECT_POWER:UInt = 2
Const REBOUND_EFFECT_SCORE:UInt = 3
Const REBOUND_EFFECT_WIN:UInt = 4

Struct SReboundState
	Field paddle0Y:Int
	Field paddle1Y:Int
	Field ballX:Int
	Field ballY:Int
	Field ballVX:Int
	Field ballVY:Int
	Field score0:Int
	Field score1:Int
	Field energy0:Int
	Field energy1:Int
	Field serveFrames:Int
	Field winner:Int
	Field readyMask:Int
	Field randomState:UInt
	Field pointNumber:Int
End Struct

Function EncodeReboundInput:Size_T(buffer:Byte Ptr, capacity:Size_T, movement:Int, power:Int)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(UInt(Max(-127, Min(127, movement))) & $ff:UInt)
	Local flags:UInt
	If power Then flags :| REBOUND_INPUT_POWER
	writer.WriteUInt8(flags)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeReboundInput:Int(packet:SPacketView, movement:Int Var, power:Int Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local encodedMovement:UInt
	Local flags:UInt
	If Not reader.ReadUInt8(encodedMovement) Or Not reader.ReadUInt8(flags) Or reader.Remaining() <> 0 Then Return False
	movement = Int(encodedMovement)
	If movement > 127 Then movement :- 256
	If movement < -127 Or movement > 127 Then Return False
	power = (flags & REBOUND_INPUT_POWER) <> 0
	Return True
End Function

Function EncodeReboundStart:Size_T(buffer:Byte Ptr, capacity:Size_T, seed:UInt)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(seed)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeReboundStart:Int(packet:SPacketView, seed:UInt Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Return reader.ReadUInt32(seed) And reader.Remaining() = 0
End Function

Type TReboundSimulation Implements IRollbackSimulation, IRollbackEffectSimulation
	Private
	Field _state:SReboundState
	Field _effectData:Byte[1]

	Method NextRandom:Int()
		_state.randomState = _state.randomState * 1664525:UInt + 1013904223:UInt
		Return Int((_state.randomState Shr 16) & $7fff:UInt)
	End Method

	Method ResetRound(direction:Int)
		_state.paddle0Y = REBOUND_WORLD_HEIGHT * REBOUND_SCALE / 2
		_state.paddle1Y = _state.paddle0Y
		_state.ballX = REBOUND_WORLD_WIDTH * REBOUND_SCALE / 2
		_state.ballY = REBOUND_WORLD_HEIGHT * REBOUND_SCALE / 2
		_state.ballVX = direction * REBOUND_INITIAL_BALL_SPEED
		Local vertical:Int = (NextRandom() Mod 7) - 3
		If vertical = 0 Then vertical = 1
		_state.ballVY = vertical * REBOUND_SCALE
		_state.serveFrames = REBOUND_SERVE_FRAMES
		_state.pointNumber :+ 1
	End Method

	Method ResetMatch()
		_state.score0 = 0
		_state.score1 = 0
		_state.energy0 = 0
		_state.energy1 = 0
		_state.winner = -1
		_state.readyMask = 0
		_state.pointNumber = 0
		Local direction:Int = -1
		If (NextRandom() & 1) Then direction = 1
		ResetRound(direction)
	End Method

	Method EmitEffect:Int(effects:IRollbackEffectWriter, kind:UInt, player:Int)
		If Not effects Then Return True
		_effectData[0] = Byte(player)
		Return effects.Emit(kind, Byte Ptr(_effectData), 1)
	End Method

	Method PaddleY:Int(player:Int)
		If player = 0 Then Return _state.paddle0Y Else Return _state.paddle1Y
	End Method

	Method SetPaddleY(player:Int, value:Int)
		If player = 0 Then _state.paddle0Y = value Else _state.paddle1Y = value
	End Method

	Method Energy:Int(player:Int)
		If player = 0 Then Return _state.energy0 Else Return _state.energy1
	End Method

	Method SetEnergy(player:Int, value:Int)
		If player = 0 Then _state.energy0 = value Else _state.energy1 = value
	End Method

	Method BounceFromPaddle:Int(player:Int, paddleMovement:Int, power:Int, effects:IRollbackEffectWriter)
		Local paddleX:Int = REBOUND_LEFT_X
		If player = 1 Then paddleX = REBOUND_RIGHT_X
		If Abs(_state.ballY - PaddleY(player)) > REBOUND_PADDLE_HEIGHT / 2 + REBOUND_BALL_RADIUS Then Return True
		Local speed:Int = Abs(_state.ballVX) + REBOUND_BALL_ACCELERATION
		If speed > REBOUND_MAX_BALL_SPEED Then speed = REBOUND_MAX_BALL_SPEED
		If power And Energy(player) >= REBOUND_POWER_COST Then
			speed = Min(REBOUND_MAX_BALL_SPEED, speed + 2 * REBOUND_SCALE)
			SetEnergy(player, Energy(player) - REBOUND_POWER_COST)
			If Not EmitEffect(effects, REBOUND_EFFECT_POWER, player) Then Return False
		Else
			If Not EmitEffect(effects, REBOUND_EFFECT_PADDLE, player) Then Return False
		End If
		If player = 0 Then
			_state.ballX = paddleX + REBOUND_PADDLE_WIDTH / 2 + REBOUND_BALL_RADIUS
			_state.ballVX = speed
		Else
			_state.ballX = paddleX - REBOUND_PADDLE_WIDTH / 2 - REBOUND_BALL_RADIUS
			_state.ballVX = -speed
		End If
		_state.ballVY :+ (_state.ballY - PaddleY(player)) / 10 + paddleMovement / 2
		_state.ballVY = Max(-7 * REBOUND_SCALE, Min(7 * REBOUND_SCALE, _state.ballVY))
		SetEnergy(player, Min(REBOUND_MAX_ENERGY, Energy(player) + 18))
		Return True
	End Method

	Method CollideBumper:Int(left:Int, top:Int, right:Int, bottom:Int, oldX:Int, oldY:Int)
		If _state.ballX + REBOUND_BALL_RADIUS < left Or _state.ballX - REBOUND_BALL_RADIUS > right Or _state.ballY + REBOUND_BALL_RADIUS < top Or _state.ballY - REBOUND_BALL_RADIUS > bottom Then Return False
		If oldY + REBOUND_BALL_RADIUS <= top And _state.ballVY > 0 Then
			_state.ballY = top - REBOUND_BALL_RADIUS
			_state.ballVY = -Abs(_state.ballVY)
		Else If oldY - REBOUND_BALL_RADIUS >= bottom And _state.ballVY < 0 Then
			_state.ballY = bottom + REBOUND_BALL_RADIUS
			_state.ballVY = Abs(_state.ballVY)
		Else If oldX < left Then
			_state.ballX = left - REBOUND_BALL_RADIUS
			_state.ballVX = -Abs(_state.ballVX)
		Else
			_state.ballX = right + REBOUND_BALL_RADIUS
			_state.ballVX = Abs(_state.ballVX)
		End If
		Return True
	End Method

	Method Score:Int(player:Int, effects:IRollbackEffectWriter)
		If player = 0 Then _state.score0 :+ 1 Else _state.score1 :+ 1
		If Not EmitEffect(effects, REBOUND_EFFECT_SCORE, player) Then Return False
		If Score(player) >= REBOUND_WIN_SCORE Then
			_state.winner = player
			_state.ballVX = 0
			_state.ballVY = 0
			_state.ballX = REBOUND_WORLD_WIDTH * REBOUND_SCALE / 2
			_state.ballY = REBOUND_WORLD_HEIGHT * REBOUND_SCALE / 2
			Return EmitEffect(effects, REBOUND_EFFECT_WIN, player)
		End If
		Local direction:Int = 1
		If player = 1 Then direction = -1
		ResetRound(direction)
		Return True
	End Method

	Public
	Method Reset(seed:UInt)
		_state = New SReboundState
		_state.randomState = seed
		If _state.randomState = 0 Then _state.randomState = 1
		ResetMatch()
	End Method

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(UInt(_state.paddle0Y)); writer.WriteUInt32(UInt(_state.paddle1Y))
		writer.WriteUInt32(UInt(_state.ballX)); writer.WriteUInt32(UInt(_state.ballY))
		writer.WriteUInt32(UInt(_state.ballVX)); writer.WriteUInt32(UInt(_state.ballVY))
		writer.WriteUInt32(UInt(_state.score0)); writer.WriteUInt32(UInt(_state.score1))
		writer.WriteUInt32(UInt(_state.energy0)); writer.WriteUInt32(UInt(_state.energy1))
		writer.WriteUInt32(UInt(_state.serveFrames)); writer.WriteUInt32(UInt(_state.winner))
		writer.WriteUInt32(UInt(_state.readyMask)); writer.WriteUInt32(_state.randomState)
		writer.WriteUInt32(UInt(_state.pointNumber))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method LoadState:Int(packet:SPacketView)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local values:UInt[15]
		For Local index:Int = 0 Until values.Length
			If Not reader.ReadUInt32(values[index]) Then Return False
		Next
		If reader.Remaining() <> 0 Then Return False
		_state.paddle0Y = Int(values[0]); _state.paddle1Y = Int(values[1])
		_state.ballX = Int(values[2]); _state.ballY = Int(values[3])
		_state.ballVX = Int(values[4]); _state.ballVY = Int(values[5])
		_state.score0 = Int(values[6]); _state.score1 = Int(values[7])
		_state.energy0 = Int(values[8]); _state.energy1 = Int(values[9])
		_state.serveFrames = Int(values[10]); _state.winner = Int(values[11])
		_state.readyMask = Int(values[12]); _state.randomState = values[13]
		_state.pointNumber = Int(values[14])
		Return True
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If previous.Length() = REBOUND_INPUT_SIZE Then
			MemCopy(buffer, previous.Data(), REBOUND_INPUT_SIZE)
			Return REBOUND_INPUT_SIZE
		End If
		Return EncodeReboundInput(buffer, capacity, 0, False)
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		Return SimulateFrame(frame, inputs, Null)
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[], effects:IRollbackEffectWriter)
		Local movements:Int[2]
		Local paddleDeltas:Int[2]
		Local powers:Int[2]
		For Local player:Int = 0 Until REBOUND_PLAYER_COUNT
			If Not DecodeReboundInput(inputs[player].Payload(), movements[player], powers[player]) Then Return False
		Next

		If _state.winner >= 0 Then
			For Local player:Int = 0 Until REBOUND_PLAYER_COUNT
				If powers[player] Then _state.readyMask :| (1 Shl player)
			Next
			If _state.readyMask = 3 Then ResetMatch()
			Return True
		End If

		Local minimumY:Int = REBOUND_PADDLE_HEIGHT / 2 + 12 * REBOUND_SCALE
		Local maximumY:Int = REBOUND_WORLD_HEIGHT * REBOUND_SCALE - minimumY
		For Local player:Int = 0 Until REBOUND_PLAYER_COUNT
			paddleDeltas[player] = movements[player] * REBOUND_PADDLE_SPEED / 127
			SetPaddleY(player, Max(minimumY, Min(maximumY, PaddleY(player) + paddleDeltas[player])))
			If frame Mod 4 = UInt(player * 2) Then SetEnergy(player, Min(REBOUND_MAX_ENERGY, Energy(player) + 1))
		Next
		If _state.serveFrames > 0 Then
			_state.serveFrames :- 1
			Return True
		End If

		Local oldX:Int = _state.ballX
		Local oldY:Int = _state.ballY
		_state.ballX :+ _state.ballVX
		_state.ballY :+ _state.ballVY
		If _state.ballY - REBOUND_BALL_RADIUS < 0 Then
			_state.ballY = REBOUND_BALL_RADIUS
			_state.ballVY = Abs(_state.ballVY)
		Else If _state.ballY + REBOUND_BALL_RADIUS > REBOUND_WORLD_HEIGHT * REBOUND_SCALE Then
			_state.ballY = REBOUND_WORLD_HEIGHT * REBOUND_SCALE - REBOUND_BALL_RADIUS
			_state.ballVY = -Abs(_state.ballVY)
		End If

		Local bumperLeft:Int = 330 * REBOUND_SCALE
		Local bumperRight:Int = 470 * REBOUND_SCALE
		CollideBumper(bumperLeft, 105 * REBOUND_SCALE, bumperRight, 121 * REBOUND_SCALE, oldX, oldY)
		CollideBumper(bumperLeft, 329 * REBOUND_SCALE, bumperRight, 345 * REBOUND_SCALE, oldX, oldY)

		If _state.ballVX < 0 And oldX - REBOUND_BALL_RADIUS >= REBOUND_LEFT_X + REBOUND_PADDLE_WIDTH / 2 And _state.ballX - REBOUND_BALL_RADIUS <= REBOUND_LEFT_X + REBOUND_PADDLE_WIDTH / 2 Then
			If Not BounceFromPaddle(0, paddleDeltas[0], powers[0], effects) Then Return False
		Else If _state.ballVX > 0 And oldX + REBOUND_BALL_RADIUS <= REBOUND_RIGHT_X - REBOUND_PADDLE_WIDTH / 2 And _state.ballX + REBOUND_BALL_RADIUS >= REBOUND_RIGHT_X - REBOUND_PADDLE_WIDTH / 2 Then
			If Not BounceFromPaddle(1, paddleDeltas[1], powers[1], effects) Then Return False
		End If

		If _state.ballX + REBOUND_BALL_RADIUS < 0 Then Return Score(1, effects)
		If _state.ballX - REBOUND_BALL_RADIUS > REBOUND_WORLD_WIDTH * REBOUND_SCALE Then Return Score(0, effects)
		Return True
	End Method

	Method PaddlePosition:Int(player:Int)
		Return PaddleY(player)
	End Method

	Method BallX:Int()
		Return _state.ballX
	End Method

	Method BallY:Int()
		Return _state.ballY
	End Method

	Method BallVX:Int()
		Return _state.ballVX
	End Method

	Method BallVY:Int()
		Return _state.ballVY
	End Method

	Method Score:Int(player:Int)
		If player = 0 Then Return _state.score0 Else Return _state.score1
	End Method

	Method Power:Int(player:Int)
		Return Energy(player)
	End Method

	Method ServeFrames:Int()
		Return _state.serveFrames
	End Method

	Method Winner:Int()
		Return _state.winner
	End Method

	Method Ready:Int(player:Int)
		Return (_state.readyMask & (1 Shl player)) <> 0
	End Method
End Type
