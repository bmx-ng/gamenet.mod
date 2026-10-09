Const ROLLBACK_APP_ID:UInt = $52424b32 ' RBK2
Const ROLLBACK_APP_VERSION:UInt = 3
Const ROLLBACK_PORT:Int = 46341

Const ROLLBACK_CONTROL_CHANNEL:UInt = 0
Const ROLLBACK_GAMEPLAY_CHANNEL:UInt = 1

Const ROLLBACK_MSG_START:UInt = 1
Const ROLLBACK_MSG_INPUT:UInt = 2
Const ROLLBACK_MSG_HASH:UInt = 3
Const ROLLBACK_MSG_STOP:UInt = 4
Const ROLLBACK_MSG_PING:UInt = 5
Const ROLLBACK_MSG_PONG:UInt = 6
Const ROLLBACK_MSG_STATE_SYNC_REQUEST:UInt = 7
Const ROLLBACK_MSG_STATE_SYNC_RESPONSE:UInt = 8

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

Function EncodePing:Size_T(buffer:Byte Ptr, capacity:Size_T, token:UInt)
	Return EncodeMatch(buffer, capacity, token)
End Function

Function DecodePing:Int(packet:SPacketView, token:UInt Var)
	Return DecodeMatch(packet, token)
End Function
