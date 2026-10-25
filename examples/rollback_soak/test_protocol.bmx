SuperStrict

Framework BRL.StandardIO
Import GameNet.RollbackSession

Const SOAK_FRAMES:UInt = 5000
Const LINK_CAPACITY:Int = 256
Const LINK_PACKET_SIZE:Size_T = 512

Function Check(condition:Int, message:String)
	If Not condition Then
		Throw "FAILED: " + message
	End If
End Function

Type TSoakSimulation Implements IRollbackSimulation
	Field positions:Int[2]
	Field accumulator:UInt

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(UInt(positions[0]))
		writer.WriteUInt32(UInt(positions[1]))
		writer.WriteUInt32(accumulator)
		If writer.Failed() Then
			Return 0
		End If
		Return writer.Position()
	End Method

	Method LoadState:Int(state:SPacketView)
		Local reader:SPacketReader = New SPacketReader(state)
		Local position0:UInt
		Local position1:UInt
		If Not reader.ReadUInt32(position0) Or Not reader.ReadUInt32(position1) Or Not reader.ReadUInt32(accumulator) Or reader.Remaining() <> 0 Then
			Return False
		End If
		positions[0] = Int(position0)
		positions[1] = Int(position1)
		Return True
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If capacity < 1 Then
			Return 0
		End If
		buffer[0] = 0
		If Not previous.IsEmpty() Then
			buffer[0] = previous.Data()[0]
		End If
		Return 1
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		If inputs.Length <> 2 Then
			Return False
		End If
		For Local player:Int = 0 Until 2
			If inputs[player].Payload().Length() <> 1 Then
				Return False
			End If
			Local value:Int = Int(Byte(inputs[player].Payload().Data()[0]))
			positions[player] :+ value
			accumulator = accumulator * 33 + UInt((value + 3) * (player + 1)) + frame
		Next
		Return True
	End Method
End Type

Type TDelayedLink
	Field _deliverAt:Int[] = New Int[LINK_CAPACITY]
	Field _lengths:Size_T[] = New Size_T[LINK_CAPACITY]
	Field _active:Byte[] = New Byte[LINK_CAPACITY]
	Field _storage:Byte Ptr = MemAlloc(Size_T(LINK_CAPACITY) * LINK_PACKET_SIZE)
	Field _sent:Int
	Field _dropped:Int
	Field _duplicated:Int
	Field _delivered:Int

	Method Delete()
		If _storage Then
			MemFree(_storage)
		End If
		_storage = Null
	End Method

	Method PacketAddress:Byte Ptr(slot:Int)
		Return _storage + Size_T(slot) * LINK_PACKET_SIZE
	End Method

	Method Enqueue:Int(packet:Byte Ptr, length:Size_T, deliverAt:Int)
		For Local slot:Int = 0 Until LINK_CAPACITY
			If Not _active[slot] Then
				MemCopy(PacketAddress(slot), packet, length)
				_lengths[slot] = length
				_deliverAt[slot] = deliverAt
				_active[slot] = True
				Return True
			End If
		Next
		Return False
	End Method

	Method Send:Int(packet:Byte Ptr, length:Size_T, tick:Int)
		If Not packet Or length < 1 Or length > LINK_PACKET_SIZE Then
			Return False
		End If
		_sent :+ 1
		If _sent Mod 9 = 0 Then
			_dropped :+ 1
			Return True
		End If
		Local delay:Int = 2 + (_sent * 7) Mod 13
		If Not Enqueue(packet, length, tick + delay) Then
			Return False
		End If
		If _sent Mod 17 = 0 Then
			If Not Enqueue(packet, length, tick + delay + 3) Then
				Return False
			End If
			_duplicated :+ 1
		End If
		Return True
	End Method

	Method Pump:Int(tick:Int, target:TRollbackSession, remotePlayer:Int)
		For Local slot:Int = 0 Until LINK_CAPACITY
			If _active[slot] And _deliverAt[slot] <= tick Then
				Local packet:SPacketView = New SPacketView(PacketAddress(slot), _lengths[slot])
				If Not target.ReceiveInputs(remotePlayer, packet) Then
					Return False
				End If
				_active[slot] = False
				_delivered :+ 1
			End If
		Next
		Return True
	End Method

	Method Pending:Int()
		Local count:Int
		For Local slot:Int = 0 Until LINK_CAPACITY
			If _active[slot] Then
				count :+ 1
			End If
		Next
		Return count
	End Method

	Method Dropped:Int()
		Return _dropped
	End Method

	Method Duplicated:Int()
		Return _duplicated
	End Method
End Type

Function InputForFrame:Byte(player:Int, frame:UInt)
	Local period:UInt = UInt(7 + player * 4)
	If (frame / period) Mod 2 = 0 Then
		Return 1
	End If
	Return Byte(-1)
End Function

Local simulations:TSoakSimulation[2]
Local sessions:TRollbackSession[2]
For Local player:Int = 0 Until 2
	simulations[player] = New TSoakSimulation
	Local config:SRollbackSessionConfig = New SRollbackSessionConfig(2, player, 256, 12, 1, 2, 12, 16, 120, 16)
	sessions[player] = TRollbackSession.Create(simulations[player], config)
	Local neutral:Byte[1]
	Check(sessions[player] And sessions[player].Start(Byte Ptr(neutral), 1), "start soak rollback session")
Next

Local links:TDelayedLink[2]
links[0] = New TDelayedLink
links[1] = New TDelayedLink
Local controllers:TRollbackPacingController[2]
controllers[0] = TRollbackPacingController.Create(8, 4, 1, 1)
controllers[1] = TRollbackPacingController.Create(8, 4, 1, 1)
Local packetStorage:Byte Ptr = MemAlloc(1024)
Local tick:Int
While (sessions[0].CurrentFrame() < SOAK_FRAMES Or sessions[1].CurrentFrame() < SOAK_FRAMES) And tick < 50000
	Check(links[0].Pump(tick, sessions[1], 0), "deliver delayed player-zero inputs")
	Check(links[1].Pump(tick, sessions[0], 1), "deliver delayed player-one inputs")
	For Local player:Int = 0 Until 2
		If sessions[player].CurrentFrame() >= SOAK_FRAMES Or Not sessions[player].CanStep() Then
			Continue
		End If
		Local pacing:SRollbackPacingDecision = controllers[player].Update(sessions[player].PacingInfo(2, 1))
		If pacing.ShouldDelay() And tick Mod 2 = 0 Then
			Continue
		End If
		Local input:Byte[1]
		input[0] = InputForFrame(player, sessions[player].CurrentFrame())
		Check(sessions[player].Step(Byte Ptr(input), 1), "advance soak rollback session")
		Local packet:Byte Ptr = packetStorage + player * 512
		Local length:Size_T = sessions[player].WriteInputs(packet, 512)
		Check(length > 0 And links[player].Send(packet, length, tick), "queue impaired rollback inputs")
	Next
	tick :+ 1
Wend
Check(sessions[0].CurrentFrame() = SOAK_FRAMES And sessions[1].CurrentFrame() = SOAK_FRAMES, "complete soak frame budget")

' Repeat the final redundant windows so deterministic loss cannot strand the
' last confirmed inputs after normal frame production stops.
For Local repeat:Int = 0 Until 24
	For Local player:Int = 0 Until 2
		Local packet:Byte Ptr = packetStorage + player * 512
		Local length:Size_T = sessions[player].WriteInputs(packet, 512)
		Check(length > 0 And links[player].Send(packet, length, tick), "flush final redundant inputs")
	Next
	Check(links[0].Pump(tick, sessions[1], 0), "flush player-zero inputs")
	Check(links[1].Pump(tick, sessions[0], 1), "flush player-one inputs")
	tick :+ 1
Next
While (links[0].Pending() Or links[1].Pending()) And tick < 51000
	Check(links[0].Pump(tick, sessions[1], 0), "drain player-zero link")
	Check(links[1].Pump(tick, sessions[0], 1), "drain player-one link")
	tick :+ 1
Wend

Local finalInput:Byte[1]
Check(sessions[0].Step(Byte Ptr(finalInput), 1) And sessions[1].Step(Byte Ptr(finalInput), 1), "resolve final soak rollback")
Check(simulations[0].positions[0] = simulations[1].positions[0] And simulations[0].positions[1] = simulations[1].positions[1], "soak peers converge")
Check(simulations[0].accumulator = simulations[1].accumulator, "soak deterministic state converges")
Check(sessions[0].RollbackCount() > 0 And sessions[1].RollbackCount() > 0, "soak exercises rollback")
Check(links[0].Dropped() > 0 And links[1].Dropped() > 0, "soak exercises packet loss")
Check(links[0].Duplicated() > 0 And links[1].Duplicated() > 0, "soak exercises packet duplication")
Check(Not sessions[0].Failed() And Not sessions[1].Failed(), "soak sessions remain healthy")
MemFree(packetStorage)

Print "GameNet rollback soak tests passed"
