Const CASCADE_APP_ID:UInt = $43415343 ' CASC
Const CASCADE_APP_VERSION:UInt = 1

Const CASCADE_CONTROL_CHANNEL:UInt = 0
Const CASCADE_GAME_CHANNEL:UInt = 1
Const CASCADE_ROOM_COMMAND_MESSAGE:UInt = 65000
Const CASCADE_ROOM_STATE_MESSAGE:UInt = 65001

Const CASCADE_MSG_MOVE_REQUEST:UInt = 2
Const CASCADE_MSG_MOVE_APPLIED:UInt = 3
Const CASCADE_MSG_MATCH_COMMAND:UInt = 4
Const CASCADE_MSG_MATCH_STATE:UInt = 5
Const CASCADE_MSG_STATE_REQUEST:UInt = 9
Const CASCADE_MSG_STATE:UInt = 10

Const CASCADE_CONFIG_PACKET_SIZE:Size_T = 5
Const CASCADE_MOVE_REQUEST_PACKET_SIZE:Size_T = 7
Const CASCADE_MOVE_APPLIED_PACKET_SIZE:Size_T = 17
Const CASCADE_STATE_HEADER_SIZE:Size_T = 22
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

Function CascadeStatePacketSize:Size_T(cellCount:Int)
	If cellCount < 0 Or cellCount > CASCADE_MAX_CELLS Then Return 0
	Return CASCADE_STATE_HEADER_SIZE + Size_T(cellCount) * 3
End Function

Function EncodeCascadeState:Size_T(buffer:Byte Ptr, capacity:Size_T, game:TCascadeGame)
	If Not game Or capacity < CascadeStatePacketSize(game.board.CellCount()) Then Return 0
	Local aliveMask:UInt
	For Local player:Int = 0 Until game.board.playerCount
		If game.alive[player] Then aliveMask :| UInt(1 Shl player)
	Next
	Local encodedWinner:UInt = 255
	If game.winner >= 0 Then encodedWinner = UInt(game.winner)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt8(CASCADE_PROTOCOL_VERSION)
	writer.WriteUInt32(game.turn)
	writer.WriteUInt8(UInt(game.currentPlayer))
	writer.WriteUInt8(encodedWinner)
	writer.WriteUInt32(UInt(game.lastTopples))
	writer.WriteUInt16(UInt(game.board.CellCount()))
	writer.WriteUInt8(aliveMask)
	writer.WriteUInt64(game.StateHash())
	For Local cell:Int = 0 Until game.board.CellCount()
		If game.counters[cell] < 0 Or game.counters[cell] > 65535 Then Return 0
		writer.WriteUInt8(UInt(game.owners[cell]))
		writer.WriteUInt16(UInt(game.counters[cell]))
	Next
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function DecodeCascadeState:Int(packet:SPacketView, game:TCascadeGame)
	If Not game Then Return False
	Local reader:SPacketReader = New SPacketReader(packet)
	Local version:UInt, turn:UInt, currentPlayer:UInt, encodedWinner:UInt, lastTopples:UInt
	Local cellCount:UInt, aliveMask:UInt, expectedHash:ULong
	If Not reader.ReadUInt8(version) Or version <> CASCADE_PROTOCOL_VERSION Then Return False
	If Not reader.ReadUInt32(turn) Then Return False
	If Not reader.ReadUInt8(currentPlayer) Or currentPlayer >= UInt(game.board.playerCount) Then Return False
	If Not reader.ReadUInt8(encodedWinner) Or (encodedWinner <> 255 And encodedWinner >= UInt(game.board.playerCount)) Then Return False
	If Not reader.ReadUInt32(lastTopples) Or lastTopples > UInt(CASCADE_MAX_TOPPLES) Then Return False
	If Not reader.ReadUInt16(cellCount) Or cellCount <> UInt(game.board.CellCount()) Then Return False
	If Not reader.ReadUInt8(aliveMask) Or (aliveMask Shr UInt(game.board.playerCount)) <> 0 Then Return False
	If Not reader.ReadUInt64(expectedHash) Then Return False

	Local decodedOwners:Byte[] = New Byte[Int(cellCount)]
	Local decodedCounters:Int[] = New Int[Int(cellCount)]
	Local decodedAlive:Byte[] = New Byte[game.board.playerCount]
	For Local player:Int = 0 Until game.board.playerCount
		decodedAlive[player] = Byte((aliveMask Shr UInt(player)) & 1)
	Next
	For Local cell:Int = 0 Until Int(cellCount)
		Local owner:UInt, counter:UInt
		If Not reader.ReadUInt8(owner) Or owner > UInt(game.board.playerCount) Or Not reader.ReadUInt16(counter) Then Return False
		If (counter = 0 And owner <> 0) Or (counter > 0 And owner = 0) Then Return False
		decodedOwners[cell] = Byte(owner)
		decodedCounters[cell] = Int(counter)
	Next
	If reader.Remaining() <> 0 Then Return False
	Local winner:Int = -1
	If encodedWinner <> 255 Then winner = Int(encodedWinner)
	If CascadeStateHash(game.board, turn, Int(currentPlayer), winner, decodedAlive, decodedOwners, decodedCounters) <> expectedHash Then Return False

	game.turn = turn
	game.currentPlayer = Int(currentPlayer)
	game.winner = winner
	game.lastTopples = Int(lastTopples)
	For Local player:Int = 0 Until game.board.playerCount
		game.alive[player] = decodedAlive[player]
	Next
	For Local cell:Int = 0 Until Int(cellCount)
		game.owners[cell] = decodedOwners[cell]
		game.counters[cell] = decodedCounters[cell]
	Next
	Return True
End Function
