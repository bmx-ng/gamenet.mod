Const AUTHORITATIVE_APP_ID:UInt = $41555448 ' AUTH
Const AUTHORITATIVE_APP_VERSION:UInt = 1
Const AUTHORITATIVE_PORT:Int = 46340

Const CONTROL_CHANNEL:UInt = 0
Const GAMEPLAY_CHANNEL:UInt = 1

Const MSG_SPAWN:UInt = 1
Const MSG_INPUT:UInt = 2
Const MSG_SNAPSHOT:UInt = 3

Const PLAYER_ENTITY_ID:UInt = 1
Const WORLD_WIDTH:Float = 640.0
Const WORLD_HEIGHT:Float = 360.0
Const PLAYER_RADIUS:Float = 14.0

Function EncodeInput:Size_T(buffer:Byte Ptr, capacity:Size_T, sequence:UInt, axisX:Int, axisY:Int)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(sequence)
	writer.WriteUInt8(UInt(axisX) & $ff:UInt)
	writer.WriteUInt8(UInt(axisY) & $ff:UInt)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeInput:Int(packet:SPacketView, sequence:UInt Var, axisX:Int Var, axisY:Int Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local encodedX:UInt
	Local encodedY:UInt
	If Not reader.ReadUInt32(sequence) Or Not reader.ReadUInt8(encodedX) Or Not reader.ReadUInt8(encodedY) Then Return False
	If reader.Remaining() <> 0 Then Return False
	axisX = Int(encodedX)
	axisY = Int(encodedY)
	If axisX > 127 Then axisX :- 256
	If axisY > 127 Then axisY :- 256
	Return True
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

Function EncodeSnapshot:Size_T(buffer:Byte Ptr, capacity:Size_T, tick:UInt, acknowledgedInput:UInt, x:Float, y:Float)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(tick)
	writer.WriteUInt32(acknowledgedInput)
	writer.WriteFloat32(x)
	writer.WriteFloat32(y)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeSnapshot:Int(packet:SPacketView, tick:UInt Var, acknowledgedInput:UInt Var, x:Float Var, y:Float Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	If Not reader.ReadUInt32(tick) Or Not reader.ReadUInt32(acknowledgedInput) Then Return False
	If Not reader.ReadFloat32(x) Or Not reader.ReadFloat32(y) Then Return False
	Return Not reader.Failed() And reader.Remaining() = 0
End Function
