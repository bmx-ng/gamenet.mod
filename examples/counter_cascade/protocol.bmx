Const CASCADE_APP_ID:UInt = $43415343 ' CASC
Const CASCADE_APP_VERSION:UInt = 1

Const CASCADE_CONTROL_CHANNEL:UInt = 0
Const CASCADE_GAME_CHANNEL:UInt = 1

Const CASCADE_MSG_CONFIG:UInt = 1
Const CASCADE_MSG_MOVE_REQUEST:UInt = 2
Const CASCADE_MSG_MOVE_APPLIED:UInt = 3
Const CASCADE_MSG_MATCH_COMMAND:UInt = 4
Const CASCADE_MSG_MATCH_STATE:UInt = 5
Const CASCADE_MSG_ROOM_READY:UInt = 6
Const CASCADE_MSG_RETURN_TO_ROOM:UInt = 7
Const CASCADE_MSG_ROOM_CONFIG:UInt = 8

Const CASCADE_CONFIG_PACKET_SIZE:Size_T = 5
Const CASCADE_MOVE_REQUEST_PACKET_SIZE:Size_T = 7
Const CASCADE_MOVE_APPLIED_PACKET_SIZE:Size_T = 17
Const CASCADE_PROTOCOL_VERSION:UInt = 1

Enum ECascadeBoardLayout:Byte
	Square = 1
	Hexagon
	HexRhombus
End Enum

Struct SCascadeMatchConfig
	Field layout:ECascadeBoardLayout
	Field size:Int
	Field playerCount:Int
	Field startingPlayer:Int

	Method New(layout:ECascadeBoardLayout, size:Int, playerCount:Int, startingPlayer:Int = 0)
		Self.layout = layout
		Self.size = size
		Self.playerCount = playerCount
		Self.startingPlayer = startingPlayer
	End Method

	Method IsValid:Int()
		If startingPlayer < 0 Or startingPlayer >= playerCount Then Return False
		Select layout
			Case ECascadeBoardLayout.Square
				Return size >= 3 And size * size <= CASCADE_MAX_CELLS And (playerCount = 2 Or playerCount = 4)
			Case ECascadeBoardLayout.Hexagon
				Return size >= 2 And size <= 8 And 1 + 3 * size * (size + 1) <= CASCADE_MAX_CELLS And (playerCount = 2 Or playerCount = 3)
			Case ECascadeBoardLayout.HexRhombus
				Return size >= 3 And size * size <= CASCADE_MAX_CELLS And playerCount = 4
		End Select
		Return False
	End Method

	Method CreateBoard:TCascadeBoard()
		If Not IsValid() Then Return Null
		Select layout
			Case ECascadeBoardLayout.Square
				Return CreateSquareCascadeBoard(size, size, playerCount)
			Case ECascadeBoardLayout.Hexagon
				Return CreateHexCascadeBoard(size, playerCount)
			Case ECascadeBoardLayout.HexRhombus
				Return CreateHexRhombusCascadeBoard(size, playerCount)
		End Select
		Return Null
	End Method
End Struct

Struct SCascadeMoveRequest
	Field turn:UInt
	Field cell:Int

	Method New(turn:UInt, cell:Int)
		Self.turn = turn
		Self.cell = cell
	End Method
End Struct

Struct SCascadeAppliedMove
	Field turn:UInt
	Field player:Int
	Field cell:Int
	Field result:ECascadeMoveResult
	Field stateHash:ULong

	Method New(turn:UInt, player:Int, cell:Int, result:ECascadeMoveResult, stateHash:ULong)
		Self.turn = turn
		Self.player = player
		Self.cell = cell
		Self.result = result
		Self.stateHash = stateHash
	End Method
End Struct

Function EncodeCascadeConfig:Size_T(buffer:Byte Ptr, capacity:Size_T, config:SCascadeMatchConfig)
	If Not config.IsValid() Then Return 0
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(CASCADE_PROTOCOL_VERSION)
	writer.WriteUInt8(UInt(config.layout))
	writer.WriteUInt8(UInt(config.size))
	writer.WriteUInt8(UInt(config.playerCount))
	writer.WriteUInt8(UInt(config.startingPlayer))
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeCascadeConfig:Int(packet:SPacketView, config:SCascadeMatchConfig Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local version:UInt, layout:UInt, size:UInt, playerCount:UInt, startingPlayer:UInt
	If Not reader.ReadUInt8(version) Or version <> CASCADE_PROTOCOL_VERSION Or Not reader.ReadUInt8(layout) Or Not reader.ReadUInt8(size) Or Not reader.ReadUInt8(playerCount) Or Not reader.ReadUInt8(startingPlayer) Or reader.Remaining() <> 0 Then Return False
	config = New SCascadeMatchConfig(ECascadeBoardLayout(layout), Int(size), Int(playerCount), Int(startingPlayer))
	Return config.IsValid()
End Function

Function EncodeCascadeMoveRequest:Size_T(buffer:Byte Ptr, capacity:Size_T, request:SCascadeMoveRequest)
	If request.cell < 0 Or request.cell > 65535 Then Return 0
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(CASCADE_PROTOCOL_VERSION)
	writer.WriteUInt32(request.turn)
	writer.WriteUInt16(UInt(request.cell))
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeCascadeMoveRequest:Int(packet:SPacketView, request:SCascadeMoveRequest Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local version:UInt, cell:UInt
	If Not reader.ReadUInt8(version) Or version <> CASCADE_PROTOCOL_VERSION Or Not reader.ReadUInt32(request.turn) Or Not reader.ReadUInt16(cell) Or reader.Remaining() <> 0 Then Return False
	request.cell = Int(cell)
	Return True
End Function

Function EncodeCascadeAppliedMove:Size_T(buffer:Byte Ptr, capacity:Size_T, move:SCascadeAppliedMove)
	If move.player < 0 Or move.player >= CASCADE_MAX_PLAYERS Or move.cell < 0 Or move.cell > 65535 Then Return 0
	If UInt(move.result) > UInt(ECascadeMoveResult.ToppleLimitReached) Then Return 0
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(CASCADE_PROTOCOL_VERSION)
	writer.WriteUInt32(move.turn)
	writer.WriteUInt8(UInt(move.player))
	writer.WriteUInt16(UInt(move.cell))
	writer.WriteUInt8(UInt(move.result))
	writer.WriteUInt64(move.stateHash)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeCascadeAppliedMove:Int(packet:SPacketView, move:SCascadeAppliedMove Var)
	Local reader:SPacketReader = New SPacketReader(packet)
	Local version:UInt, player:UInt, cell:UInt, result:UInt
	If Not reader.ReadUInt8(version) Or version <> CASCADE_PROTOCOL_VERSION Or Not reader.ReadUInt32(move.turn) Or Not reader.ReadUInt8(player) Or Not reader.ReadUInt16(cell) Or Not reader.ReadUInt8(result) Or Not reader.ReadUInt64(move.stateHash) Or reader.Remaining() <> 0 Then Return False
	If player >= CASCADE_MAX_PLAYERS Or result > UInt(ECascadeMoveResult.ToppleLimitReached) Then Return False
	move.player = Int(player)
	move.cell = Int(cell)
	move.result = ECascadeMoveResult(result)
	Return True
End Function
