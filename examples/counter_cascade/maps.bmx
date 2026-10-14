Function CreateSquareCascadeBoard:TCascadeBoard(width:Int, height:Int, players:Int)
	If width < 3 Or height < 3 Then Return Null
	If players <> 2 And players <> 4 Then Return Null
	If width * height > CASCADE_MAX_CELLS Then Return Null
	Local grid:TTileGrid = TTileGrid.Rectangular(1, 1)
	Local board:TCascadeBoard = TCascadeBoard.Create("square-" + width + "x" + height + "-p" + players, ECascadeGeometry.Square, grid.NeighbourCount(), width * height, players)
	If Not board Then Return Null
	For Local row:Int = 0 Until height
		For Local column:Int = 0 Until width
			Local cell:Int = row * width + column
			board.SetCell(cell, column, row)
		Next
	Next
	If Not PopulateReflectedRoutes(board, grid) Then Return Null
	board.SetStart(0, board.CellAt(0, 0))
	board.SetStart(1, board.CellAt(width - 1, height - 1))
	If players = 4 Then
		board.SetStart(1, board.CellAt(width - 1, 0))
		board.SetStart(2, board.CellAt(width - 1, height - 1))
		board.SetStart(3, board.CellAt(0, height - 1))
	End If
	If Not board.Validate() Then Return Null
	Return board
End Function

Function CreateHexCascadeBoard:TCascadeBoard(radius:Int, players:Int)
	If radius < 2 Or radius > 8 Then Return Null
	If players <> 2 And players <> 3 Then Return Null
	Local cellCount:Int = 1 + 3 * radius * (radius + 1)
	If cellCount > CASCADE_MAX_CELLS Then Return Null
	Local grid:TTileGrid = TTileGrid.Hexagonal(1, 1, ETileLayout.PointyHex, ETileStagger.Odd)
	Local board:TCascadeBoard = TCascadeBoard.Create("hex-r" + radius + "-p" + players, ECascadeGeometry.Hexagonal, grid.NeighbourCount(), cellCount, players)
	If Not board Then Return Null
	Local index:Int
	For Local axialR:Int = -radius To radius
		Local q0:Int = Max(-radius, -axialR - radius)
		Local q1:Int = Min(radius, -axialR + radius)
		For Local axialQ:Int = q0 To q1
			Local column:Int, row:Int
			grid.FromAxial(axialQ, axialR, column, row)
			board.SetCell(index, column, row)
			index :+ 1
		Next
	Next
	If Not PopulateReflectedRoutes(board, grid) Then Return Null
	Local column:Int, row:Int
	grid.FromAxial(radius, 0, column, row)
	board.SetStart(0, board.CellAt(column, row))
	If players = 2 Then
		grid.FromAxial(-radius, 0, column, row)
		board.SetStart(1, board.CellAt(column, row))
	Else
		grid.FromAxial(-radius, radius, column, row)
		board.SetStart(1, board.CellAt(column, row))
		grid.FromAxial(0, -radius, column, row)
		board.SetStart(2, board.CellAt(column, row))
	End If
	If Not board.Validate() Then Return Null
	Return board
End Function

Function CreateHexRhombusCascadeBoard:TCascadeBoard(size:Int, players:Int = 4)
	If size < 3 Or size * size > CASCADE_MAX_CELLS Or players <> 4 Then Return Null
	Local grid:TTileGrid = TTileGrid.Hexagonal(1, 1, ETileLayout.PointyHex, ETileStagger.Odd)
	Local board:TCascadeBoard = TCascadeBoard.Create("hex-rhombus-" + size + "-p4", ECascadeGeometry.Hexagonal, grid.NeighbourCount(), size * size, players)
	If Not board Then Return Null
	Local index:Int
	For Local axialR:Int = 0 Until size
		For Local axialQ:Int = 0 Until size
			Local column:Int, row:Int
			grid.FromAxial(axialQ, axialR, column, row)
			board.SetCell(index, column, row)
			index :+ 1
		Next
	Next
	If Not PopulateReflectedRoutes(board, grid) Then Return Null
	Local cornerQ:Int[4]
	Local cornerR:Int[4]
	cornerQ[0] = 0; cornerR[0] = 0
	cornerQ[1] = size - 1; cornerR[1] = 0
	cornerQ[2] = size - 1; cornerR[2] = size - 1
	cornerQ[3] = 0; cornerR[3] = size - 1
	For Local player:Int = 0 Until players
		Local column:Int, row:Int
		grid.FromAxial(cornerQ[player], cornerR[player], column, row)
		board.SetStart(player, board.CellAt(column, row))
	Next
	If Not board.Validate() Then Return Null
	Return board
End Function

Function PopulateReflectedRoutes:Int(board:TCascadeBoard, grid:TTileGrid)
	For Local cell:Int = 0 Until board.CellCount()
		For Local direction:Int = 0 Until board.routeCount
			Local column:Int, row:Int
			grid.Neighbour(board.cells[cell].column, board.cells[cell].row, direction, column, row)
			Local destination:Int = board.CellAt(column, row)
			If destination < 0 Then
				Local opposite:Int = (direction + board.routeCount / 2) Mod board.routeCount
				grid.Neighbour(board.cells[cell].column, board.cells[cell].row, opposite, column, row)
				destination = board.CellAt(column, row)
				For Local offset:Int = 1 Until board.routeCount / 2
					If destination >= 0 Then Exit
					Local reflected:Int = (opposite + offset) Mod board.routeCount
					grid.Neighbour(board.cells[cell].column, board.cells[cell].row, reflected, column, row)
					destination = board.CellAt(column, row)
					If destination >= 0 Then Exit
					reflected = (opposite - offset + board.routeCount) Mod board.routeCount
					grid.Neighbour(board.cells[cell].column, board.cells[cell].row, reflected, column, row)
					destination = board.CellAt(column, row)
				Next
			End If
			If destination < 0 Or Not board.SetRoute(cell, direction, destination) Then Return False
		Next
	Next
	Return True
End Function
