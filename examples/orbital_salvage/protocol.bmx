Import BRL.Math

Const SALVAGE_APP_ID:UInt = $53414c56 ' SALV
Const SALVAGE_APP_VERSION:UInt = 1

Const SALVAGE_PLAYER_COUNT:Int = 2
Const SALVAGE_CORE_COUNT:Int = 4
Const SALVAGE_WIN_SCORE:Int = 5
Const SALVAGE_WORLD_WIDTH:Float = 800.0
Const SALVAGE_WORLD_HEIGHT:Float = 450.0
Const SALVAGE_PLAYER_RADIUS:Float = 16.0
Const SALVAGE_CORE_RADIUS:Float = 9.0
Const SALVAGE_PLAYER_SPEED:Float = 175.0
Const SALVAGE_PULSE_RADIUS:Float = 92.0
Const SALVAGE_PULSE_COOLDOWN_TICKS:Int = 45
Const SALVAGE_SIMULATION_STEP:Float = 1.0 / 60.0
Const SALVAGE_REPLICATION_MESSAGE:UInt = 80
Const SALVAGE_INPUT_MESSAGE:UInt = 81
Const SALVAGE_SNAPSHOT_MESSAGE:UInt = 82
Const SALVAGE_REPLICATION_CHANNEL:UInt = 1
Const SALVAGE_INPUT_HISTORY_CAPACITY:Int = 96
Const SALVAGE_SERVER_INPUT_CAPACITY:Int = 192
Const SALVAGE_SNAPSHOT_CAPACITY:Int = 32
Const SALVAGE_REDUNDANT_INPUTS:Int = 32
Const SALVAGE_MOVEMENT_STATE_SIZE:Size_T = 16

Const SALVAGE_PLAYER_TYPE:UInt = 1
Const SALVAGE_CORE_TYPE:UInt = 2
Const SALVAGE_MATCH_TYPE:UInt = 3

Const SALVAGE_FIELD_X:UInt = 1
Const SALVAGE_FIELD_Y:UInt = 2
Const SALVAGE_FIELD_CARRIER:UInt = 3
Const SALVAGE_FIELD_SCORE_0:UInt = 1
Const SALVAGE_FIELD_SCORE_1:UInt = 2
Const SALVAGE_FIELD_WINNER:UInt = 3

Const SALVAGE_MESSAGE_INPUT:UInt = 1
Const SALVAGE_MESSAGE_PULSE:UInt = 2

Function CreateSalvagePlayerSchema:TReplicationSchema()
	Local schema:TReplicationSchema = TReplicationSchema.Create(SALVAGE_PLAYER_TYPE, 1, 2)
	If Not schema Then Return Null
	If Not schema.AddFloat32(SALVAGE_FIELD_X) Or Not schema.AddFloat32(SALVAGE_FIELD_Y) Then Return Null
	If Not schema.SetUpdateMode(EReplicationUpdateMode.UnreliableSnapshots, 20) Then Return Null
	Return schema
End Function

Function CreateSalvageCoreSchema:TReplicationSchema()
	Local schema:TReplicationSchema = TReplicationSchema.Create(SALVAGE_CORE_TYPE, 1, 3)
	If Not schema Then Return Null
	If Not schema.AddFloat32(SALVAGE_FIELD_X) Or Not schema.AddFloat32(SALVAGE_FIELD_Y) Or Not schema.AddUInt32(SALVAGE_FIELD_CARRIER) Then Return Null
	If Not schema.SetUpdateMode(EReplicationUpdateMode.UnreliableSnapshots, 20) Then Return Null
	Return schema
End Function

Function CreateSalvageMatchSchema:TReplicationSchema()
	Local schema:TReplicationSchema = TReplicationSchema.Create(SALVAGE_MATCH_TYPE, 1, 3)
	If Not schema Then Return Null
	If Not schema.AddInt32(SALVAGE_FIELD_SCORE_0) Or Not schema.AddInt32(SALVAGE_FIELD_SCORE_1) Or Not schema.AddInt32(SALVAGE_FIELD_WINNER) Then Return Null
	Return schema
End Function

Function RegisterSalvageSchemas:Int(world:TReplicationWorld)
	If Not world Then Return False
	Return world.RegisterSchema(CreateSalvagePlayerSchema()) And world.RegisterSchema(CreateSalvageCoreSchema()) And world.RegisterSchema(CreateSalvageMatchSchema())
End Function

Function EncodeSalvageInput:Size_T(buffer:Byte Ptr, capacity:Size_T, axisX:Int, axisY:Int, pulse:Int)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(UInt(Max(-127, Min(127, axisX))) & $ff:UInt)
	writer.WriteUInt8(UInt(Max(-127, Min(127, axisY))) & $ff:UInt)
	writer.WriteUInt8(UInt(pulse <> 0))
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeSalvageInput:Int(payload:SPacketView, axisX:Int Var, axisY:Int Var, pulse:Int Var)
	Local reader:SPacketReader = New SPacketReader(payload)
	Local encodedX:UInt, encodedY:UInt, encodedPulse:UInt
	If Not reader.ReadUInt8(encodedX) Or Not reader.ReadUInt8(encodedY) Or Not reader.ReadUInt8(encodedPulse) Then Return False
	If reader.Remaining() <> 0 Or encodedPulse > 1 Then Return False
	axisX = Int(encodedX)
	axisY = Int(encodedY)
	If axisX > 127 Then axisX :- 256
	If axisY > 127 Then axisY :- 256
	pulse = encodedPulse <> 0
	Return True
End Function

Function EncodeSalvageMovementState:Size_T(buffer:Byte Ptr, capacity:Size_T, x0:Float, y0:Float, x1:Float, y1:Float)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteFloat32(x0)
	writer.WriteFloat32(y0)
	writer.WriteFloat32(x1)
	writer.WriteFloat32(y1)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeSalvageMovementPlayer:Int(payload:SPacketView, player:Int, x:Float Var, y:Float Var)
	If player < 0 Or player >= SALVAGE_PLAYER_COUNT Then Return False
	Local reader:SPacketReader = New SPacketReader(payload)
	Local positions:Float[4]
	For Local index:Int = 0 Until positions.Length
		If Not reader.ReadFloat32(positions[index]) Then Return False
	Next
	x = positions[player * 2]
	y = positions[player * 2 + 1]
	Return Not reader.Failed() And reader.Remaining() = 0
End Function

Function ApplySalvageMovement(x:Float Var, y:Float Var, axisX:Int, axisY:Int, seconds:Float)
	Local moveX:Float = Float(axisX) / 127.0
	Local moveY:Float = Float(axisY) / 127.0
	Local lengthSquared:Float = moveX * moveX + moveY * moveY
	If lengthSquared > 1.0 Then
		Local inverseLength:Float = 1.0 / Sqr(lengthSquared)
		moveX :* inverseLength
		moveY :* inverseLength
	End If
	x :+ moveX * SALVAGE_PLAYER_SPEED * seconds
	y :+ moveY * SALVAGE_PLAYER_SPEED * seconds
	x = Max(SALVAGE_PLAYER_RADIUS, Min(SALVAGE_WORLD_WIDTH - SALVAGE_PLAYER_RADIUS, x))
	y = Max(SALVAGE_PLAYER_RADIUS, Min(SALVAGE_WORLD_HEIGHT - SALVAGE_PLAYER_RADIUS, y))
End Function

Type TSalvageAuthority
	Field world:TReplicationWorld
	Field players:TReplicatedEntity[SALVAGE_PLAYER_COUNT]
	Field cores:TReplicatedEntity[SALVAGE_CORE_COUNT]
	Field matchState:TReplicatedEntity
	Field inputX:Int[SALVAGE_PLAYER_COUNT]
	Field inputY:Int[SALVAGE_PLAYER_COUNT]
	Field pulsePending:Byte[SALVAGE_PLAYER_COUNT]
	Field pulseCooldown:Int[SALVAGE_PLAYER_COUNT]
	Field carriedCore:Int[SALVAGE_PLAYER_COUNT]
	Field respawnFrames:Int[SALVAGE_CORE_COUNT]
	Field pickupCooldown:Int[SALVAGE_CORE_COUNT]
	Field spawnSequence:UInt
	Field pulseSequence:UInt
	Field lastPulsePlayer:Int = -1
	Field effectBuffer:Byte[2]

	Function Create:TSalvageAuthority(world:TReplicationWorld)
		If Not world Or world.Role() <> EReplicationRole.Authority Then Return Null
		Local game:TSalvageAuthority = New TSalvageAuthority
		game.world = world
		For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
			game.carriedCore[player] = -1
		Next
		Return game
	End Function

	Method Start:Int()
		matchState = world.Spawn(SALVAGE_MATCH_TYPE)
		If Not matchState Then Return False
		matchState.SetInt32(SALVAGE_FIELD_WINNER, -1)
		For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
			players[player] = world.Spawn(SALVAGE_PLAYER_TYPE, Null, UInt(player + 1))
			If Not players[player] Then Return False
			players[player].SetPriority(UInt(EReplicationPriority.Critical))
			Local x:Float = 105.0
			If player = 1 Then x = SALVAGE_WORLD_WIDTH - 105.0
			players[player].SetFloat32(SALVAGE_FIELD_X, x)
			players[player].SetFloat32(SALVAGE_FIELD_Y, SALVAGE_WORLD_HEIGHT * 0.5)
		Next
		For Local core:Int = 0 Until SALVAGE_CORE_COUNT
			If Not SpawnCore(core) Then Return False
		Next
		Return True
	End Method

	Method SpawnCore:Int(index:Int)
		cores[index] = world.Spawn(SALVAGE_CORE_TYPE)
		If Not cores[index] Then Return False
		cores[index].SetPriority(UInt(EReplicationPriority.High))
		spawnSequence :+ 1
		Local column:Int = index Mod 2
		Local row:Int = index / 2
		Local wobble:Float = Float(Int((spawnSequence * 37 + UInt(index * 53)) Mod 41) - 20)
		cores[index].SetFloat32(SALVAGE_FIELD_X, SALVAGE_WORLD_WIDTH * 0.5 + Float(column * 2 - 1) * 72.0 + wobble)
		cores[index].SetFloat32(SALVAGE_FIELD_Y, 145.0 + Float(row) * 160.0 - wobble * 0.35)
		cores[index].SetUInt32(SALVAGE_FIELD_CARRIER, 0)
		respawnFrames[index] = 0
		pickupCooldown[index] = 0
		Return True
	End Method

	Method PlayerEntity:TReplicatedEntity(index:Int)
		If index < 0 Or index >= SALVAGE_PLAYER_COUNT Then Return Null
		Return players[index]
	End Method

	Method SetInput(index:Int, axisX:Int, axisY:Int, pulse:Int)
		If index < 0 Or index >= SALVAGE_PLAYER_COUNT Then Return
		inputX[index] = Max(-127, Min(127, axisX))
		inputY[index] = Max(-127, Min(127, axisY))
		If pulse Then pulsePending[index] = True
	End Method

	Method ReceiveMessage:Int(event:SReplicationEvent)
		If event.Kind() <> EReplicationEventKind.Message Or event.MessageId() <> SALVAGE_MESSAGE_INPUT Then Return False
		Local player:Int = Int(event.Entity().OwnerId()) - 1
		If player < 0 Or player >= SALVAGE_PLAYER_COUNT Then Return False
		Local axisX:Int, axisY:Int, pulse:Int
		If Not DecodeSalvageInput(event.Payload(), axisX, axisY, pulse) Then Return False
		SetInput(player, axisX, axisY, pulse)
		Return True
	End Method

	Method DistanceSquared:Float(ax:Float, ay:Float, bx:Float, by:Float)
		Local dx:Float = ax - bx
		Local dy:Float = ay - by
		Return dx * dx + dy * dy
	End Method

	Method SendPulse(player:Int, tick:UInt)
		effectBuffer[0] = Byte(player)
		effectBuffer[1] = 0
		world.SendMessage(players[player], SALVAGE_MESSAGE_PULSE, New SPacketView(Byte Ptr(effectBuffer), Size_T(effectBuffer.Length)), tick, EDeliveryMode.Unreliable)
	End Method

	Method DropCore(player:Int)
		Local core:Int = carriedCore[player]
		If core < 0 Or Not cores[core] Then Return
		carriedCore[player] = -1
		cores[core].SetUInt32(SALVAGE_FIELD_CARRIER, 0)
		pickupCooldown[core] = 18
		Local direction:Float = -1.0
		If player = 0 Then direction = 1.0
		cores[core].SetFloat32(SALVAGE_FIELD_X, players[player].GetFloat32(SALVAGE_FIELD_X) + direction * 34.0)
		cores[core].SetFloat32(SALVAGE_FIELD_Y, players[player].GetFloat32(SALVAGE_FIELD_Y))
	End Method

	Method ProcessPulse(player:Int, tick:UInt)
		If Not pulsePending[player] Then Return
		pulsePending[player] = False
		If pulseCooldown[player] > 0 Then Return
		pulseCooldown[player] = SALVAGE_PULSE_COOLDOWN_TICKS
		pulseSequence :+ 1
		lastPulsePlayer = player
		SendPulse(player, tick)
		Local opponent:Int = 1 - player
		If carriedCore[opponent] < 0 Then Return
		Local distance:Float = DistanceSquared(players[player].GetFloat32(SALVAGE_FIELD_X), players[player].GetFloat32(SALVAGE_FIELD_Y), players[opponent].GetFloat32(SALVAGE_FIELD_X), players[opponent].GetFloat32(SALVAGE_FIELD_Y))
		If distance <= SALVAGE_PULSE_RADIUS * SALVAGE_PULSE_RADIUS Then DropCore(opponent)
	End Method

	Method MovePlayer(player:Int)
		Local x:Float = players[player].GetFloat32(SALVAGE_FIELD_X)
		Local y:Float = players[player].GetFloat32(SALVAGE_FIELD_Y)
		ApplySalvageMovement(x, y, inputX[player], inputY[player], SALVAGE_SIMULATION_STEP)
		players[player].SetFloat32(SALVAGE_FIELD_X, x)
		players[player].SetFloat32(SALVAGE_FIELD_Y, y)
	End Method

	Method TryPickup(player:Int)
		If carriedCore[player] >= 0 Then Return
		For Local core:Int = 0 Until SALVAGE_CORE_COUNT
			If Not cores[core] Or pickupCooldown[core] > 0 Or cores[core].GetUInt32(SALVAGE_FIELD_CARRIER) <> 0 Then Continue
			Local distance:Float = DistanceSquared(players[player].GetFloat32(SALVAGE_FIELD_X), players[player].GetFloat32(SALVAGE_FIELD_Y), cores[core].GetFloat32(SALVAGE_FIELD_X), cores[core].GetFloat32(SALVAGE_FIELD_Y))
			Local pickupRadius:Float = SALVAGE_PLAYER_RADIUS + SALVAGE_CORE_RADIUS + 3.0
			If distance <= pickupRadius * pickupRadius Then
				carriedCore[player] = core
				cores[core].SetUInt32(SALVAGE_FIELD_CARRIER, UInt(player + 1))
				Return
			End If
		Next
	End Method

	Method Score:Int(player:Int)
		If player = 0 Then Return matchState.GetInt32(SALVAGE_FIELD_SCORE_0)
		Return matchState.GetInt32(SALVAGE_FIELD_SCORE_1)
	End Method

	Method Deposit(player:Int, tick:UInt)
		Local core:Int = carriedCore[player]
		If core < 0 Then Return
		Local x:Float = players[player].GetFloat32(SALVAGE_FIELD_X)
		If (player = 0 And x > 62.0) Or (player = 1 And x < SALVAGE_WORLD_WIDTH - 62.0) Then Return
		If world.Despawn(cores[core], 1, tick) <> ETransportResult.Ok Then Return
		carriedCore[player] = -1
		cores[core] = Null
		respawnFrames[core] = 75
		Local scoreField:UInt = SALVAGE_FIELD_SCORE_0
		If player = 1 Then scoreField = SALVAGE_FIELD_SCORE_1
		Local score:Int = matchState.GetInt32(scoreField) + 1
		matchState.SetInt32(scoreField, score)
		If score >= SALVAGE_WIN_SCORE Then matchState.SetInt32(SALVAGE_FIELD_WINNER, player)
	End Method

	Method Step(tick:UInt)
		If Not matchState Or matchState.GetInt32(SALVAGE_FIELD_WINNER) >= 0 Then Return
		For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
			MovePlayer(player)
			If pulseCooldown[player] > 0 Then pulseCooldown[player] :- 1
			ProcessPulse(player, tick)
		Next
		For Local core:Int = 0 Until SALVAGE_CORE_COUNT
			If pickupCooldown[core] > 0 Then pickupCooldown[core] :- 1
		Next
		For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
			TryPickup(player)
		Next
		For Local player:Int = 0 Until SALVAGE_PLAYER_COUNT
			Local core:Int = carriedCore[player]
			If core >= 0 And cores[core] Then
				Local offset:Float = 24.0
				If player = 1 Then offset = -24.0
				cores[core].SetFloat32(SALVAGE_FIELD_X, players[player].GetFloat32(SALVAGE_FIELD_X) + offset)
				cores[core].SetFloat32(SALVAGE_FIELD_Y, players[player].GetFloat32(SALVAGE_FIELD_Y))
			End If
			Deposit(player, tick)
		Next
		For Local core:Int = 0 Until SALVAGE_CORE_COUNT
			If cores[core] Or respawnFrames[core] <= 0 Then Continue
			respawnFrames[core] :- 1
			If respawnFrames[core] = 0 Then SpawnCore(core)
		Next
	End Method
End Type
