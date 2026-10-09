Const ROLLBACK_APP_ID:UInt = $52424b32 ' RBK2
Const ROLLBACK_APP_VERSION:UInt = 1
Const ROLLBACK_PORT:Int = 46341

Const ROLLBACK_CONTROL_CHANNEL:UInt = 0
Const ROLLBACK_GAMEPLAY_CHANNEL:UInt = 1

Const ROLLBACK_MSG_START:UInt = 1
Const ROLLBACK_MSG_INPUT:UInt = 2
Const ROLLBACK_MSG_HASH:UInt = 3
Const ROLLBACK_MSG_STOP:UInt = 4
Const ROLLBACK_MSG_PING:UInt = 5
Const ROLLBACK_MSG_PONG:UInt = 6

Const ROLLBACK_PLAYER_COUNT:Int = 2
Const ROLLBACK_INPUT_BATCH_MAX:Int = 12
Const ROLLBACK_INPUT_SIZE:Size_T = 2

Function EncodePlayerAssignment:Size_T(buffer:Byte Ptr, capacity:Size_T, player:Int)
	If player < 0 Or player >= ROLLBACK_PLAYER_COUNT Then Return 0
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(UInt(player))
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodePlayerAssignment:Int(packet:SPacketView, player:Int Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local value:UInt
	If Not reader.ReadUInt8(value) Or reader.Remaining() <> 0 Or value >= UInt(ROLLBACK_PLAYER_COUNT) Then Return False
	player = Int(value)
	Return True
End Function

Function EncodeMatch:Size_T(buffer:Byte Ptr, capacity:Size_T, matchId:UInt)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(matchId)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeMatch:Int(packet:SPacketView, matchId:UInt Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	If Not reader.ReadUInt32(matchId) Then Return False
	Return reader.Remaining() = 0
End Function

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

Function EncodeRollbackInputBatch:Size_T(buffer:Byte Ptr, capacity:Size_T, simulatedFrame:UInt, frames:UInt[], axisXs:Int[], axisYs:Int[], count:Int)
	If count < 1 Or count > ROLLBACK_INPUT_BATCH_MAX Or count > frames.Length Or count > axisXs.Length Or count > axisYs.Length Then Return 0
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(simulatedFrame)
	writer.WriteUInt8(UInt(count))
	For Local index:Int = 0 Until count
		If index > 0 And Not RollbackFrameAfter(frames[index], frames[index - 1]) Then Return 0
		writer.WriteUInt32(frames[index])
		writer.WriteUInt8(UInt(axisXs[index]) & $ff:UInt)
		writer.WriteUInt8(UInt(axisYs[index]) & $ff:UInt)
	Next
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeRollbackInputBatch:Int(packet:SPacketView, simulatedFrame:UInt Var, frames:UInt[], axisXs:Int[], axisYs:Int[], count:Int Var)
	count = 0
	Local reader:SPacketReader = New SPacketReader(packet)
	Local encodedCount:UInt
	If Not reader.ReadUInt32(simulatedFrame) Or Not reader.ReadUInt8(encodedCount) Then Return False
	If encodedCount < 1 Or encodedCount > UInt(ROLLBACK_INPUT_BATCH_MAX) Then Return False
	If encodedCount > UInt(frames.Length) Or encodedCount > UInt(axisXs.Length) Or encodedCount > UInt(axisYs.Length) Then Return False
	For Local index:Int = 0 Until Int(encodedCount)
		Local encodedX:UInt
		Local encodedY:UInt
		If Not reader.ReadUInt32(frames[index]) Or Not reader.ReadUInt8(encodedX) Or Not reader.ReadUInt8(encodedY) Then Return False
		If index > 0 And Not RollbackFrameAfter(frames[index], frames[index - 1]) Then Return False
		axisXs[index] = Int(encodedX)
		axisYs[index] = Int(encodedY)
		If axisXs[index] > 127 Then axisXs[index] :- 256
		If axisYs[index] > 127 Then axisYs[index] :- 256
	Next
	If reader.Remaining() <> 0 Then Return False
	count = Int(encodedCount)
	Return True
End Function

Function EncodeStateHash:Size_T(buffer:Byte Ptr, capacity:Size_T, frame:UInt, hash:UInt)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(frame)
	writer.WriteUInt32(hash)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeStateHash:Int(packet:SPacketView, frame:UInt Var, hash:UInt Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	If Not reader.ReadUInt32(frame) Or Not reader.ReadUInt32(hash) Then Return False
	Return reader.Remaining() = 0
End Function

Function EncodePing:Size_T(buffer:Byte Ptr, capacity:Size_T, token:UInt)
	Return EncodeMatch(buffer, capacity, token)
End Function

Function DecodePing:Int(packet:SPacketView, token:UInt Var)
	Return DecodeMatch(packet, token)
End Function
