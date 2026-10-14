SuperStrict

Framework Max2D.TileMap
Import BRL.StandardIO

Include "rules.bmx"
Include "maps.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then RuntimeError "Counter Cascade test failed: " + message
End Function

Local square:TCascadeBoard = CreateSquareCascadeBoard(5, 5, 4)
Check(square <> Null And square.Validate(), "create square board")
Check(square.routeCount = 4 And square.CellCount() = 25, "square dimensions")
Local corner:Int = square.CellAt(0, 0)
Local east:Int = square.CellAt(1, 0)
Local south:Int = square.CellAt(0, 1)
Check(square.cells[corner].routes[0] = east And square.cells[corner].routes[2] = east, "reflect west edge east")
Check(square.cells[corner].routes[1] = south And square.cells[corner].routes[3] = south, "reflect north edge south")

Local squareGame:TCascadeGame = TCascadeGame.Create(square)
Check(squareGame <> Null, "create square game")
For Local player:Int = 0 Until 4
	Check(squareGame.counters[square.starts[player]] = 2 And squareGame.owners[square.starts[player]] = player + 1, "square starting counters")
	Check(squareGame.PlayerAlive(player), "square player starts alive")
Next
Check(Not squareGame.IsLegalMove(0, square.starts[1]), "reject opponent square")
Check(squareGame.ApplyMove(0, square.starts[0]) = ECascadeMoveResult.Accepted, "accept first square move")
Check(squareGame.currentPlayer = 1 And squareGame.counters[square.starts[0]] = 3, "advance square turn")

' Complete one round, then make player zero's corner topple. Its two available
' neighbours receive two counters each.
Check(squareGame.ApplyMove(1, square.starts[1]) = ECascadeMoveResult.Accepted, "square player one move")
Check(squareGame.ApplyMove(2, square.starts[2]) = ECascadeMoveResult.Accepted, "square player two move")
Check(squareGame.ApplyMove(3, square.starts[3]) = ECascadeMoveResult.Accepted, "square player three move")
Local squareLog:TCascadeEventLog = TCascadeEventLog.Create()
Check(squareGame.ApplyMove(0, square.starts[0], squareLog) = ECascadeMoveResult.Accepted, "topple square corner")
Check(squareGame.counters[corner] = 0 And squareGame.owners[corner] = 0, "empty toppled square corner")
Check(squareGame.counters[east] = 2 And squareGame.owners[east] = 1, "double reflected square east")
Check(squareGame.counters[south] = 2 And squareGame.owners[south] = 1, "double reflected square south")
Check(squareGame.lastTopples = 1 And squareLog.count = 6, "record square cascade events")

Local hex:TCascadeBoard = CreateHexCascadeBoard(3, 3)
Check(hex <> Null And hex.Validate(), "create hex board")
Check(hex.routeCount = 6 And hex.CellCount() = 37, "hex dimensions")
Local hexGame:TCascadeGame = TCascadeGame.Create(hex)
For Local player:Int = 0 Until 3
	Check(hexGame.counters[hex.starts[player]] = 3 And hexGame.owners[hex.starts[player]] = player + 1, "hex starting counters")
Next

' State hashes must be stable for identical games and change after a move.
Local twin:TCascadeGame = TCascadeGame.Create(CreateHexCascadeBoard(3, 3))
Local initialHash:ULong = hexGame.StateHash()
Check(initialHash = twin.StateHash(), "stable initial state hash")
Check(hexGame.ApplyMove(0, hex.starts[0]) = ECascadeMoveResult.Accepted, "accept hex move")
Check(hexGame.StateHash() <> initialHash, "state hash changes after move")
Check(twin.ApplyMove(0, twin.board.starts[0]) = ECascadeMoveResult.Accepted, "repeat hex move")
Check(hexGame.StateHash() = twin.StateHash(), "identical move produces identical state")

' A cell holding threshold plus one keeps one counter after toppling.
Local centre:Int = hex.CellAt(0, 0)
hexGame.currentPlayer = 1
hexGame.owners[centre] = 2
hexGame.counters[centre] = 6
Check(hexGame.ApplyMove(1, centre) = ECascadeMoveResult.Accepted, "topple seven hex counters")
Check(hexGame.counters[centre] = 1 And hexGame.owners[centre] = 2, "hex retains seventh counter")

Local rhombus:TCascadeBoard = CreateHexRhombusCascadeBoard(5)
Check(rhombus <> Null And rhombus.Validate(), "create four-player hex rhombus")
Check(rhombus.routeCount = 6 And rhombus.playerCount = 4 And rhombus.CellCount() = 25, "hex rhombus dimensions")

Local duel:TCascadeGame = TCascadeGame.Create(CreateSquareCascadeBoard(3, 3, 2))
For Local cell:Int = 0 Until duel.board.CellCount()
	duel.owners[cell] = 0
	duel.counters[cell] = 0
Next
duel.owners[0] = 1
duel.counters[0] = 1
Local winLog:TCascadeEventLog = TCascadeEventLog.Create()
Check(duel.ApplyMove(0, 0, winLog) = ECascadeMoveResult.Won, "eliminate final opponent")
Check(duel.winner = 0 And Not duel.PlayerAlive(1), "record winner and elimination")

' A crowded board may have no stable cascade state. Capturing the final opposing
' colour still ends the match after the completing topple, before cycle safety is
' consulted. Remaining unstable cells are irrelevant once the winner is known.
Local crowded:TCascadeGame = TCascadeGame.Create(CreateSquareCascadeBoard(3, 3, 2))
For Local cell:Int = 0 Until crowded.board.CellCount()
	crowded.owners[cell] = 1
	crowded.counters[cell] = 3
Next
Local finalOpponent:Int = crowded.board.CellAt(1, 0)
crowded.owners[finalOpponent] = 2
crowded.currentPlayer = 0
Local crowdedLog:TCascadeEventLog = TCascadeEventLog.Create()
Check(crowded.ApplyMove(0, 0, crowdedLog) = ECascadeMoveResult.Won, "win before a repeating cascade")
Check(crowded.winner = 0 And crowded.lastTopples = 1, "stop cascade at the winning topple")
Check(Not crowded.PlayerOwnsCells(1), "final opposing colour captured")

Print "Counter Cascade rules tests passed"
