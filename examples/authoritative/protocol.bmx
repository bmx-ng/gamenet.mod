Const AUTHORITATIVE_APP_ID:UInt = $41555448 ' AUTH
Const AUTHORITATIVE_APP_VERSION:UInt = 3
Const AUTHORITATIVE_PORT:Int = 46340

Const CONTROL_CHANNEL:UInt = 0
Const GAMEPLAY_CHANNEL:UInt = 1

Const MSG_SPAWN:UInt = 1
Const MSG_INPUT:UInt = 2
Const MSG_SNAPSHOT:UInt = 3
Const MSG_DESPAWN:UInt = 4

Const AUTHORITATIVE_MAX_PLAYERS:Int = 4
Const AUTHORITATIVE_PLAYER_SPEED:Float = 180.0
Const AUTHORITATIVE_SIMULATION_STEP:Float = 1.0 / 60.0
Const AUTHORITATIVE_INPUT_HISTORY_CAPACITY:Int = 64
Const AUTHORITATIVE_SERVER_INPUT_CAPACITY:Int = 128
Const AUTHORITATIVE_SERVER_INPUT_DELAY:Int = 8
Const AUTHORITATIVE_INPUT_PAYLOAD_SIZE:Size_T = 2
Const WORLD_WIDTH:Float = 640.0
Const WORLD_HEIGHT:Float = 360.0
Const PLAYER_RADIUS:Float = 14.0

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
	If Not reader.ReadUInt8(encodedX) Or Not reader.ReadUInt8(encodedY) Then Return False
	If reader.Remaining() <> 0 Then Return False
	axisX = Int(encodedX)
	axisY = Int(encodedY)
	If axisX > 127 Then axisX :- 256
	If axisY > 127 Then axisY :- 256
	Return True
End Function

Function EncodeInputBatch:Size_T(buffer:Byte Ptr, capacity:Size_T, history:TPredictionHistory)
	If Not history Or history.Count() > 255 Then Return 0
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(UInt(history.Count()))
	For Local index:Int = 0 Until history.Count()
		Local input:SPredictionInput
		If Not history.Get(index, input) Or input.Payload().Length() <> AUTHORITATIVE_INPUT_PAYLOAD_SIZE Then Return 0
		writer.WriteUInt32(input.Sequence())
		writer.WriteBytes(input.Payload().Data(), input.Payload().Length())
	Next
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeInputBatch:Int(packet:SPacketView, sequences:UInt[], axisXs:Int[], axisYs:Int[], count:Int Var)
	count = 0
	Local reader:SPacketReader = New SPacketReader(packet)
	Local encodedCount:UInt
	If Not reader.ReadUInt8(encodedCount) Then Return False
	If encodedCount > UInt(AUTHORITATIVE_INPUT_HISTORY_CAPACITY) Or encodedCount > UInt(sequences.Length) Or encodedCount > UInt(axisXs.Length) Or encodedCount > UInt(axisYs.Length) Then Return False
	For Local index:Int = 0 Until Int(encodedCount)
		Local encodedX:UInt
		Local encodedY:UInt
		If Not reader.ReadUInt32(sequences[index]) Or Not reader.ReadUInt8(encodedX) Or Not reader.ReadUInt8(encodedY) Then Return False
		axisXs[index] = Int(encodedX)
		axisYs[index] = Int(encodedY)
		If axisXs[index] > 127 Then axisXs[index] :- 256
		If axisYs[index] > 127 Then axisYs[index] :- 256
	Next
	If reader.Failed() Or reader.Remaining() <> 0 Then Return False
	count = Int(encodedCount)
	Return True
End Function

Function EncodeEntity:Size_T(buffer:Byte Ptr, capacity:Size_T, entityId:UInt)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(entityId)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeEntity:Int(packet:SPacketView, entityId:UInt Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	If Not reader.ReadUInt32(entityId) Then Return False
	Return Not reader.Failed() And reader.Remaining() = 0
End Function

Function EncodeSpawn:Size_T(buffer:Byte Ptr, capacity:Size_T, entityId:UInt, x:Float, y:Float)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(entityId)
	writer.WriteFloat32(x)
	writer.WriteFloat32(y)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeSpawn:Int(packet:SPacketView, entityId:UInt Var, x:Float Var, y:Float Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	If Not reader.ReadUInt32(entityId) Or Not reader.ReadFloat32(x) Or Not reader.ReadFloat32(y) Then Return False
	Return Not reader.Failed() And reader.Remaining() = 0
End Function

Function EncodeSnapshot:Size_T(buffer:Byte Ptr, capacity:Size_T, entityId:UInt, tick:UInt, acknowledgedInput:UInt, x:Float, y:Float)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(entityId)
	writer.WriteUInt32(tick)
	writer.WriteUInt32(acknowledgedInput)
	writer.WriteFloat32(x)
	writer.WriteFloat32(y)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeSnapshot:Int(packet:SPacketView, entityId:UInt Var, tick:UInt Var, acknowledgedInput:UInt Var, x:Float Var, y:Float Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	If Not reader.ReadUInt32(entityId) Or Not reader.ReadUInt32(tick) Or Not reader.ReadUInt32(acknowledgedInput) Then Return False
	If Not reader.ReadFloat32(x) Or Not reader.ReadFloat32(y) Then Return False
	Return Not reader.Failed() And reader.Remaining() = 0
End Function
