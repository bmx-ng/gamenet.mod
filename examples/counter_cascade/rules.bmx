Const CASCADE_MAX_PLAYERS:Int = 4
Const CASCADE_MAX_ROUTES:Int = 6
Const CASCADE_MAX_CELLS:Int = 256
Const CASCADE_MAX_TOPPLES:Int = 16384
Const CASCADE_CYCLE_SLOTS:Int = 32768

Enum ECascadeGeometry:Byte
	Square = 1
	Hexagonal
End Enum

Enum ECascadeMoveResult:Byte
	Invalid
	Accepted
	Won
	CycleDetected
	ToppleLimitReached
End Enum

Enum ECascadeEventKind:Byte
	Placed = 1
	Toppled
	Landed
	Eliminated
	Won
End Enum

Struct SCascadeCell
	Field column:Int
	Field row:Int
	Field routes:Int[CASCADE_MAX_ROUTES]
End Struct

Struct SCascadeEvent
	Field kind:ECascadeEventKind
	Field cell:Int
	Field source:Int
	Field player:Int
	Field count:Int
End Struct

Type TCascadeEventLog
	Field events:SCascadeEvent[]
	Field count:Int
	Field overflowed:Int

	Function Create:TCascadeEventLog(capacity:Int = 4096)
		If capacity < 1 Then Return Null
		Local log:TCascadeEventLog = New TCascadeEventLog
		log.events = New SCascadeEvent[capacity]
		Return log
	End Function

	Method Clear()
		count = 0
		overflowed = False
	End Method

	Method Add(kind:ECascadeEventKind, cell:Int, source:Int, player:Int, value:Int)
		If count >= events.Length Then
			overflowed = True
			Return
		End If
		events[count].kind = kind
		events[count].cell = cell
		events[count].source = source
		events[count].player = player
		events[count].count = value
		count :+ 1
	End Method
End Type

Type TCascadeBoard
	Field identifier:String
	Field geometry:ECascadeGeometry
	Field routeCount:Int
	Field playerCount:Int
	Field cells:SCascadeCell[]
	Field starts:Int[CASCADE_MAX_PLAYERS]

	Function Create:TCascadeBoard(identifier:String, geometry:ECascadeGeometry, routeCount:Int, cellCount:Int, playerCount:Int)
		If identifier.Length = 0 Then Return Null
		If routeCount <> 4 And routeCount <> 6 Then Return Null
		If cellCount < playerCount Or cellCount > CASCADE_MAX_CELLS Then Return Null
		If playerCount < 2 Or playerCount > CASCADE_MAX_PLAYERS Then Return Null
		Local board:TCascadeBoard = New TCascadeBoard
		board.identifier = identifier
		board.geometry = geometry
		board.routeCount = routeCount
		board.playerCount = playerCount
		board.cells = New SCascadeCell[cellCount]
		For Local player:Int = 0 Until CASCADE_MAX_PLAYERS
			board.starts[player] = -1
		Next
		For Local cell:Int = 0 Until cellCount
			For Local direction:Int = 0 Until CASCADE_MAX_ROUTES
				board.cells[cell].routes[direction] = -1
			Next
		Next
		Return board
	End Function

	Method CellCount:Int()
		Return cells.Length
	End Method

	Method SetCell:Int(index:Int, column:Int, row:Int)
		If index < 0 Or index >= cells.Length Then Return False
		cells[index].column = column
		cells[index].row = row
		Return True
	End Method

	Method SetRoute:Int(index:Int, direction:Int, destination:Int)
		If index < 0 Or index >= cells.Length Then Return False
		If direction < 0 Or direction >= routeCount Then Return False
		If destination < 0 Or destination >= cells.Length Then Return False
		cells[index].routes[direction] = destination
		Return True
	End Method

	Method SetStart:Int(player:Int, cell:Int)
		If player < 0 Or player >= playerCount Then Return False
		If cell < 0 Or cell >= cells.Length Then Return False
		starts[player] = cell
		Return True
	End Method

	Method CellAt:Int(column:Int, row:Int)
		For Local index:Int = 0 Until cells.Length
			If cells[index].column = column And cells[index].row = row Then Return index
		Next
		Return -1
	End Method

	Method Validate:Int()
		If routeCount <> 4 And routeCount <> 6 Then Return False
		If geometry = ECascadeGeometry.Square And routeCount <> 4 Then Return False
		If geometry = ECascadeGeometry.Hexagonal And routeCount <> 6 Then Return False
		For Local cell:Int = 0 Until cells.Length
			For Local direction:Int = 0 Until routeCount
				If cells[cell].routes[direction] < 0 Or cells[cell].routes[direction] >= cells.Length Then Return False
			Next
		Next
		For Local player:Int = 0 Until playerCount
			If starts[player] < 0 Or starts[player] >= cells.Length Then Return False
			For Local other:Int = 0 Until player
				If starts[other] = starts[player] Then Return False
			Next
		Next
		Return True
	End Method

	Method TopologyHash:ULong()
		Local hash:ULong = $cbf29ce484222325:ULong
		hash = CascadeHashUInt(hash, UInt(geometry))
		hash = CascadeHashUInt(hash, UInt(routeCount))
		hash = CascadeHashUInt(hash, UInt(playerCount))
		hash = CascadeHashUInt(hash, UInt(cells.Length))
		For Local cell:Int = 0 Until cells.Length
			hash = CascadeHashUInt(hash, UInt(cells[cell].column))
			hash = CascadeHashUInt(hash, UInt(cells[cell].row))
			For Local direction:Int = 0 Until routeCount
				hash = CascadeHashUInt(hash, UInt(cells[cell].routes[direction]))
			Next
		Next
		For Local player:Int = 0 Until playerCount
			hash = CascadeHashUInt(hash, UInt(starts[player]))
		Next
		Return hash
	End Method
End Type

Type TCascadeGame
	Field board:TCascadeBoard
	Field owners:Byte[]
	Field counters:Int[]
	Field alive:Byte[]
	Field currentPlayer:Int
	Field winner:Int = -1
	Field turn:UInt
	Field lastTopples:Int
	Field _savedOwners:Byte[]
	Field _savedCounters:Int[]
	Field _seen:ULong[]

	Function Create:TCascadeGame(board:TCascadeBoard)
		If Not board Or Not board.Validate() Then Return Null
		Local game:TCascadeGame = New TCascadeGame
		game.board = board
		game.owners = New Byte[board.CellCount()]
		game.counters = New Int[board.CellCount()]
		game.alive = New Byte[board.playerCount]
		game._savedOwners = New Byte[board.CellCount()]
		game._savedCounters = New Int[board.CellCount()]
		game._seen = New ULong[CASCADE_CYCLE_SLOTS]
		game.Reset()
		Return game
	End Function

	Method Reset()
		For Local cell:Int = 0 Until board.CellCount()
			owners[cell] = 0
			counters[cell] = 0
		Next
		Local startingCounters:Int = board.routeCount / 2
		For Local player:Int = 0 Until board.playerCount
			Local cell:Int = board.starts[player]
			owners[cell] = Byte(player + 1)
			counters[cell] = startingCounters
			alive[player] = True
		Next
		currentPlayer = 0
		winner = -1
		turn = 0
		lastTopples = 0
	End Method

	Method IsLegalMove:Int(player:Int, cell:Int)
		If winner >= 0 Or player <> currentPlayer Then Return False
		If cell < 0 Or cell >= board.CellCount() Then Return False
		Return owners[cell] = 0 Or owners[cell] = player + 1
	End Method

	Method ApplyMove:ECascadeMoveResult(player:Int, cell:Int, log:TCascadeEventLog = Null)
		If log Then log.Clear()
		If Not IsLegalMove(player, cell) Then Return ECascadeMoveResult.Invalid
		SaveForRollback()
		owners[cell] = Byte(player + 1)
		counters[cell] :+ 1
		If log Then log.Add(ECascadeEventKind.Placed, cell, -1, player, counters[cell])
		ClearSeen()
		RememberState()
		lastTopples = 0

		Repeat
			Local unstable:Int = FirstUnstableCell()
			If unstable < 0 Then Exit
			If lastTopples >= CASCADE_MAX_TOPPLES Then
				RestoreAfterFailure()
				Return ECascadeMoveResult.ToppleLimitReached
			End If
			Local colour:Int = Int(owners[unstable]) - 1
			If colour < 0 Or colour >= board.playerCount Then
				RestoreAfterFailure()
				Return ECascadeMoveResult.CycleDetected
			End If
			counters[unstable] :- board.routeCount
			If counters[unstable] = 0 Then owners[unstable] = 0
			lastTopples :+ 1
			If log Then log.Add(ECascadeEventKind.Toppled, unstable, unstable, colour, counters[unstable])
			For Local direction:Int = 0 Until board.routeCount
				Local destination:Int = board.cells[unstable].routes[direction]
				owners[destination] = Byte(colour + 1)
				counters[destination] :+ 1
				If log Then log.Add(ECascadeEventKind.Landed, destination, unstable, colour, counters[destination])
			Next
			' A topple is atomic. Once all of its counters have landed, the match is
			' over as soon as only one participating colour remains. Do this before
			' cycle detection: a victorious cascade does not need to reach a stable
			' board, and on a crowded board it may otherwise repeat forever.
			If RemainingColours() = 1 Then
				UpdateEliminations(log)
				turn :+ 1
				winner = FirstLivingPlayer()
				currentPlayer = winner
				If log Then log.Add(ECascadeEventKind.Won, -1, -1, winner, 0)
				Return ECascadeMoveResult.Won
			End If
			If Not RememberState() Then
				RestoreAfterFailure()
				Return ECascadeMoveResult.CycleDetected
			End If
		Forever

		turn :+ 1
		Local remaining:Int = UpdateEliminations(log)
		If remaining = 1 Then
			winner = FirstLivingPlayer()
			currentPlayer = winner
			If log Then log.Add(ECascadeEventKind.Won, -1, -1, winner, 0)
			Return ECascadeMoveResult.Won
		End If
		currentPlayer = NextLivingPlayer(currentPlayer)
		Return ECascadeMoveResult.Accepted
	End Method

	Method PlayerOwnsCells:Int(player:Int)
		If player < 0 Or player >= board.playerCount Then Return False
		For Local cell:Int = 0 Until board.CellCount()
			If owners[cell] = player + 1 Then Return True
		Next
		Return False
	End Method

	Method PlayerAlive:Int(player:Int)
		Return player >= 0 And player < board.playerCount And alive[player]
	End Method

	Method StateHash:ULong()
		Local hash:ULong = board.TopologyHash()
		hash = CascadeHashUInt(hash, turn)
		hash = CascadeHashUInt(hash, UInt(currentPlayer))
		hash = CascadeHashUInt(hash, UInt(winner))
		For Local player:Int = 0 Until board.playerCount
			hash = CascadeHashUInt(hash, UInt(alive[player]))
		Next
		For Local cell:Int = 0 Until board.CellCount()
			hash = CascadeHashUInt(hash, UInt(owners[cell]))
			hash = CascadeHashUInt(hash, UInt(counters[cell]))
		Next
		Return hash
	End Method

	Private
	Method SaveForRollback()
		For Local cell:Int = 0 Until board.CellCount()
			_savedOwners[cell] = owners[cell]
			_savedCounters[cell] = counters[cell]
		Next
	End Method

	Method RestoreAfterFailure()
		For Local cell:Int = 0 Until board.CellCount()
			owners[cell] = _savedOwners[cell]
			counters[cell] = _savedCounters[cell]
		Next
		lastTopples = 0
	End Method

	Method FirstUnstableCell:Int()
		For Local cell:Int = 0 Until board.CellCount()
			If counters[cell] >= board.routeCount Then Return cell
		Next
		Return -1
	End Method

	Method FirstLivingPlayer:Int()
		For Local player:Int = 0 Until board.playerCount
			If alive[player] Then Return player
		Next
		Return -1
	End Method

	Method NextLivingPlayer:Int(afterPlayer:Int)
		For Local offset:Int = 1 To board.playerCount
			Local player:Int = (afterPlayer + offset) Mod board.playerCount
			If alive[player] Then Return player
		Next
		Return afterPlayer
	End Method

	Method UpdateEliminations:Int(log:TCascadeEventLog)
		Local remaining:Int
		For Local player:Int = 0 Until board.playerCount
			If alive[player] And Not PlayerOwnsCells(player) Then
				alive[player] = False
				If log Then log.Add(ECascadeEventKind.Eliminated, -1, -1, player, 0)
			End If
			If alive[player] Then remaining :+ 1
		Next
		Return remaining
	End Method

	Method RemainingColours:Int()
		Local remaining:Int
		For Local player:Int = 0 Until board.playerCount
			If alive[player] And PlayerOwnsCells(player) Then remaining :+ 1
		Next
		Return remaining
	End Method

	Method ClearSeen()
		For Local index:Int = 0 Until _seen.Length
			_seen[index] = 0
		Next
	End Method

	Method CascadeHash:ULong()
		Local hash:ULong = $cbf29ce484222325:ULong
		For Local cell:Int = 0 Until board.CellCount()
			hash = CascadeHashUInt(hash, UInt(owners[cell]))
			hash = CascadeHashUInt(hash, UInt(counters[cell]))
		Next
		If hash = 0 Then hash = 1
		Return hash
	End Method

	Method RememberState:Int()
		Local hash:ULong = CascadeHash()
		Local slot:Int = Int(hash & ULong(_seen.Length - 1))
		For Local probe:Int = 0 Until _seen.Length
			If _seen[slot] = hash Then Return False
			If _seen[slot] = 0 Then
				_seen[slot] = hash
				Return True
			End If
			slot = (slot + 1) & (_seen.Length - 1)
		Next
		Return False
	End Method
End Type

Function CascadeHashByte:ULong(hash:ULong, value:UInt)
	Return (hash ~ ULong(value & $ff:UInt)) * $100000001b3:ULong
End Function

Function CascadeHashUInt:ULong(hash:ULong, value:UInt)
	For Local shift:Int = 0 Until 32 Step 8
		hash = CascadeHashByte(hash, value Shr UInt(shift))
	Next
	Return hash
End Function
