SuperStrict

Framework Max2D.SDL3RenderMax2D
Import Max2D.TileMap
Import BRL.Event
Import BRL.PolledInput
Import BRL.PNGLoader

Incbin "images/tabletop-background.png"

Include "rules.bmx"
Include "maps.bmx"

Const SCREEN_WIDTH:Int = 1000
Const SCREEN_HEIGHT:Int = 700
Const DEFAULT_CASCADE_STEP_MILLIS:Int = 100

?ios Or android
Global pointerHover:Int = False
?Not ios And Not android
Global pointerHover:Int = True
?

Global game:TCascadeGame
Global viewGrid:TTileGrid
Global eventLog:TCascadeEventLog = TCascadeEventLog.Create()
Global boardX:Float
Global boardY:Float
Global statusText:String = "Choose a board"
Global hoverCell:Int = -1
Global testMode:Int
Global screenshotPath:String
Global frames:Int
Global background:TImage
Global counterImage:TImage
Global displayOwners:Byte[]
Global displayCounters:Int[]
Global animationActive:Int
Global animationIndex:Int
Global animationStarted:Int
Global animationStartMillis:Int
Global animationResult:ECascadeMoveResult
Global cascadeStepMillis:Int = DEFAULT_CASCADE_STEP_MILLIS
Global touchHitPending:Int
Global touchHitX:Float
Global touchHitY:Float

For Local argument:String = EachIn AppArgs[1..]
	If argument = "--test" Then testMode = True
	If argument.StartsWith("--screenshot=") Then screenshotPath = argument[13..]
Next

Graphics SCREEN_WIDTH, SCREEN_HEIGHT
SetVirtualResolution(SCREEN_WIDTH, SCREEN_HEIGHT, VIRTUAL_LETTERBOX)
SetClsColor(15, 20, 31)
Local staticImageFlags:Int = FILTEREDIMAGE
If Max2DSupportsImageFlags(FILTEREDIMAGE | MIPMAPPEDIMAGE) Then staticImageFlags :| MIPMAPPEDIMAGE
background = LoadImage("incbin::images/tabletop-background.png", staticImageFlags)
counterImage = CreateCounterImage(staticImageFlags)
?ios Or android
AddHook EmitEventHook, CascadeTouchEventHook
?
If testMode Then StartHex(3)

While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	If game Then
		UpdateGame()
	Else
		UpdateMenu()
	End If
	Cls()
	If game Then
		DrawGame()
	Else
		DrawMenu()
	End If
	frames :+ 1
	If frames = 3 And screenshotPath.Length Then SavePixmapPNG(GrabPixmap(0, 0, NativeResolutionWidth(), NativeResolutionHeight()), screenshotPath)
	Flip()
	If testMode And frames >= 3 Then Exit
Wend
?ios Or android
RemoveHook EmitEventHook, CascadeTouchEventHook
?
EndGraphics()

Function StartSquare(players:Int)
	Local board:TCascadeBoard
	If players = 2 Then board = CreateSquareCascadeBoard(5, 5, players) Else board = CreateSquareCascadeBoard(8, 8, players)
	game = TCascadeGame.Create(board)
	viewGrid = TTileGrid.Rectangular(62, 62)
	PrepareBoardView()
	statusText = "Place a counter on an empty square or one of your own"
End Function

Function StartHex(players:Int)
	If players = 4 Then
		game = TCascadeGame.Create(CreateHexRhombusCascadeBoard(7))
	Else If players = 2 Then
		game = TCascadeGame.Create(CreateHexCascadeBoard(3, players))
	Else
		game = TCascadeGame.Create(CreateHexCascadeBoard(4, players))
	End If
	viewGrid = TTileGrid.Hexagonal(58, 68, ETileLayout.PointyHex, ETileStagger.Odd)
	PrepareBoardView()
	statusText = "Place a counter on an empty hexagon or one of your own"
End Function

Function PrepareBoardView()
	Local minX:Double = 1000000.0, minY:Double = 1000000.0
	Local maxX:Double = -1000000.0, maxY:Double = -1000000.0
	For Local cell:Int = 0 Until game.board.CellCount()
		For Local corner:Int = 0 Until viewGrid.CornerCount()
			Local x:Double, y:Double
			viewGrid.CellCorner(game.board.cells[cell].column, game.board.cells[cell].row, corner, x, y)
			minX = Min(minX, x)
			minY = Min(minY, y)
			maxX = Max(maxX, x)
			maxY = Max(maxY, y)
		Next
	Next
	boardX = Float((SCREEN_WIDTH - (maxX - minX)) * 0.5 - minX)
	boardY = Float(112.0 + (520.0 - (maxY - minY)) * 0.5 - minY)
	SyncPresentation()
End Function

Function SyncPresentation()
	If Not game Then Return
	If displayOwners.Length <> game.board.CellCount() Then
		displayOwners = New Byte[game.board.CellCount()]
		displayCounters = New Int[game.board.CellCount()]
	End If
	For Local cell:Int = 0 Until game.board.CellCount()
		displayOwners[cell] = game.owners[cell]
		displayCounters[cell] = game.counters[cell]
	Next
End Function

Function UpdateMenu()
	If KeyHit(KEY_1) Then StartSquare(2)
	If KeyHit(KEY_2) Then StartSquare(4)
	If KeyHit(KEY_3) Then StartHex(2)
	If KeyHit(KEY_4) Then StartHex(3)
	If KeyHit(KEY_5) Then StartHex(4)
	Local x:Float, y:Float
	If Not PollPress(x, y) Then Return
	If x < 200 Or x >= 800 Then Return
	If y >= 210 And y < 270 Then StartSquare(2)
	If y >= 285 And y < 345 Then StartSquare(4)
	If y >= 360 And y < 420 Then StartHex(2)
	If y >= 435 And y < 495 Then StartHex(3)
	If y >= 510 And y < 570 Then StartHex(4)
End Function

' Returns a press and the coordinates captured by that same input event. Mobile
' uses the native touch event instead of SDL's compatibility mouse position.
Function PollPress:Int(x:Float Var, y:Float Var)
	?ios Or android
	If Not touchHitPending Then Return False
	x = touchHitX
	y = touchHitY
	touchHitPending = False
	Return True
	?
	?Not ios And Not android
	If Not MouseHit(1) Then Return False
	Return GetVirtualMouse(x, y, True)
	?
End Function

?ios Or android
Function CascadeTouchEventHook:Object(id:Int, data:Object, context:Object)
	Local event:TEvent = TEvent(data)
	If Not event Or event.id <> EVENT_TOUCHDOWN Then Return data
	Local nativeX:Float = NativeResolutionWidth() * event.x / 10000.0
	Local nativeY:Float = NativeResolutionHeight() * event.y / 10000.0
	NativeToVirtual(nativeX, nativeY, touchHitX, touchHitY)
	touchHitPending = True
	Return data
End Function
?

Function UpdateGame()
	If animationActive Then
		Local ignoredX:Float, ignoredY:Float
		PollPress(ignoredX, ignoredY)
		UpdateCascadeAnimation()
		Return
	End If
	If KeyHit(KEY_M) Then
		game = Null
		viewGrid = Null
		statusText = "Choose a board"
		Return
	End If
	If KeyHit(KEY_R) Then
		game.Reset()
		SyncPresentation()
		statusText = "Board reset"
		Return
	End If
	hoverCell = -1
	Local pressX:Float, pressY:Float
	Local clicked:Int = PollPress(pressX, pressY)
	If game.winner >= 0 Then
		If clicked And pressY >= 365 And pressY < 421 Then
			If pressX >= 330 And pressX < 490 Then
				game.Reset()
				SyncPresentation()
				statusText = "Player 1 to move"
			Else If pressX >= 510 And pressX < 670 Then
				game = Null
				viewGrid = Null
				statusText = "Choose a board"
			End If
		End If
		Return
	End If
	If pointerHover Then
		Local mouseX:Float, mouseY:Float
		Local column:Int, row:Int
		If GetVirtualMouse(mouseX, mouseY, True) Then
			If viewGrid.LocalToCell(mouseX - boardX, mouseY - boardY, column, row) Then
				hoverCell = game.board.CellAt(column, row)
			End If
		End If
	End If
	If Not clicked Then Return
	Local pressedColumn:Int, pressedRow:Int
	If Not viewGrid.LocalToCell(pressX - boardX, pressY - boardY, pressedColumn, pressedRow) Then Return
	Local pressedCell:Int = game.board.CellAt(pressedColumn, pressedRow)
	If pressedCell < 0 Then Return
	Local player:Int = game.currentPlayer
	Local result:ECascadeMoveResult = game.ApplyMove(player, pressedCell, eventLog)
	Select result
		Case ECascadeMoveResult.Invalid
			statusText = "That cell belongs to another player"
		Case ECascadeMoveResult.Accepted
			BeginCascadeAnimation(result)
		Case ECascadeMoveResult.Won
			BeginCascadeAnimation(result)
		Case ECascadeMoveResult.CycleDetected
			statusText = "Move rejected: repeating cascade"
		Case ECascadeMoveResult.ToppleLimitReached
			statusText = "Move rejected: cascade safety limit reached"
	End Select
End Function

Function BeginCascadeAnimation(result:ECascadeMoveResult)
	animationActive = eventLog.count > 0
	animationIndex = 0
	animationStarted = False
	animationResult = result
	statusText = "Resolving move..."
	If Not animationActive Then FinishCascadeAnimation()
End Function

Function UpdateCascadeAnimation()
	If animationIndex >= eventLog.count Then
		FinishCascadeAnimation()
		Return
	End If
	Local event:SCascadeEvent = eventLog.events[animationIndex]
	If Not animationStarted Then
		animationStarted = True
		animationStartMillis = MilliSecs()
		If event.kind = ECascadeEventKind.Placed Or event.kind = ECascadeEventKind.Toppled Then ApplyPresentationEvent(event)
	End If
	Local duration:Int
	Select event.kind
		Case ECascadeEventKind.Placed
			duration = 90
		Case ECascadeEventKind.Toppled
			duration = cascadeStepMillis
		Default
			duration = 0
	End Select
	If Int(MilliSecs() - animationStartMillis) < duration Then Return
	If event.kind = ECascadeEventKind.Toppled Then
		For Local direction:Int = 1 To game.board.routeCount
			If animationIndex + direction >= eventLog.count Then Exit
			Local landing:SCascadeEvent = eventLog.events[animationIndex + direction]
			If landing.kind <> ECascadeEventKind.Landed Or landing.source <> event.cell Then Exit
			ApplyPresentationEvent(landing)
		Next
		animationIndex :+ 1 + game.board.routeCount
	Else
		animationIndex :+ 1
	End If
	animationStarted = False
End Function

Function ApplyPresentationEvent(event:SCascadeEvent)
	If event.cell < 0 Or event.cell >= displayCounters.Length Then Return
	displayCounters[event.cell] = event.count
	If event.count = 0 Then displayOwners[event.cell] = 0 Else displayOwners[event.cell] = Byte(event.player + 1)
End Function

Function FinishCascadeAnimation()
	animationActive = False
	animationStarted = False
	SyncPresentation()
	If animationResult = ECascadeMoveResult.Won Then
		statusText = "Player " + (game.winner + 1) + " wins!"
	Else
		statusText = "Player " + (game.currentPlayer + 1) + " to move"
		If game.lastTopples Then statusText = game.lastTopples + " topple" + Plural(game.lastTopples) + " resolved"
	End If
End Function

Function Plural:String(value:Int)
	If value = 1 Then Return ""
	Return "s"
End Function

Function DrawMenu()
	DrawBackground()
	SetColor 236, 241, 250
	DrawText "COUNTER CASCADE", 405, 100
	SetColor 154, 171, 197
	DrawText "A deterministic square and hex strategy game", 350, 140
	DrawMenuButton(210, "1   SQUARE DUEL", 40, 115, 205)
	DrawMenuButton(285, "2   FOUR CORNERS", 150, 86, 205)
	DrawMenuButton(360, "3   HEX DUEL", 35, 155, 135)
	DrawMenuButton(435, "4   HEX TRIAD", 185, 112, 48)
	DrawMenuButton(510, "5   HEX RHOMBUS", 142, 90, 180)
	SetColor 126, 143, 170
	DrawText "Click a mode or press 1-5", 395, 605
End Function

Function DrawMenuButton(y:Float, label:String, red:Int, green:Int, blue:Int)
	SetColor red, green, blue
	DrawRect 200, y, 600, 60
	SetColor 255, 255, 255
	DrawText label, 400, y + 21
End Function

Function DrawGame()
	DrawBackground()
	SetColor 235, 240, 249
	DrawText "COUNTER CASCADE", 38, 28
	SetColor 148, 165, 193
	DrawText game.board.identifier.ToUpper(), 38, 55
	If animationActive Then
		SetColor 245, 211, 105
		DrawText "CASCADE", 463, 42
	Else If game.winner >= 0 Then
		SetPlayerColor(game.winner)
		DrawText "PLAYER " + (game.winner + 1) + " WINS", 414, 42
	Else
		SetPlayerColor(game.currentPlayer)
		DrawText "PLAYER " + (game.currentPlayer + 1) + "'S TURN", 430, 42
	End If
	SetColor 148, 165, 193
	DrawText "Turn " + game.turn + "   Topples " + game.lastTopples, 780, 32
	DrawText "M: modes   R: reset", 804, 57

	For Local cell:Int = 0 Until game.board.CellCount()
		If pointerHover And Not animationActive And cell = hoverCell And game.IsLegalMove(game.currentPlayer, cell) Then
			SetColor 245, 211, 105
			SetLineWidth 3
		Else
			SetColor 65, 80, 106
			SetLineWidth 1
		End If
		DrawCellOutline(cell)
		If displayCounters[cell] > 0 Then DrawCounter(cell)
	Next
	DrawCascadeMotion()
	SetLineWidth 1
	SetColor 177, 190, 211
	DrawText statusText, 38, 660
	If game.winner >= 0 And Not animationActive Then DrawWinnerPanel()
End Function

Function DrawBackground()
	SetColor 255, 255, 255
	SetAlpha 0.82
	If background Then
		Local sourceWidth:Float = Float(background.height) * Float(SCREEN_WIDTH) / Float(SCREEN_HEIGHT)
		Local sourceX:Float = (Float(background.width) - sourceWidth) * 0.5
		DrawSubImageRect background, 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, sourceX, 0, sourceWidth, background.height
	End If
	SetAlpha 1.0
End Function

Function DrawCellOutline(cell:Int)
	For Local corner:Int = 0 Until viewGrid.CornerCount()
		Local x0:Double, y0:Double, x1:Double, y1:Double
		viewGrid.CellCorner(game.board.cells[cell].column, game.board.cells[cell].row, corner, x0, y0)
		viewGrid.CellCorner(game.board.cells[cell].column, game.board.cells[cell].row, (corner + 1) Mod viewGrid.CornerCount(), x1, y1)
		DrawLine Float(x0) + boardX, Float(y0) + boardY, Float(x1) + boardX, Float(y1) + boardY, False
	Next
End Function

Function DrawCounter(cell:Int)
	Local x:Double, y:Double
	viewGrid.CellCenter(game.board.cells[cell].column, game.board.cells[cell].row, x, y)
	x :+ boardX
	y :+ boardY
	Local player:Int = Int(displayOwners[cell]) - 1
	Local ready:Int = displayCounters[cell] >= game.board.routeCount - 1
	Local scaleX:Float = 1.0
	Local scaleY:Float = 1.0
	If ready Then
		Local phase:Float = Float(MilliSecs()) * 0.48 + Float(cell * 47)
		x :+ Sin(phase) * 1.35
		y :+ Sin(phase * 1.71) * 0.55
		scaleX :+ Sin(phase * 1.13) * 0.035
		scaleY :- Sin(phase * 1.13) * 0.030
	End If
	SetPlayerColor(player)
	SetAlpha 0.20
	DrawImageRect counterImage, Float(x - 27 * scaleX), Float(y - 27 * scaleY), 54 * scaleX, 54 * scaleY
	SetAlpha 1.0
	SetPlayerColor(player)
	DrawImageRect counterImage, Float(x - 21 * scaleX), Float(y - 21 * scaleY), 42 * scaleX, 42 * scaleY
	DrawCounterPips(Float(x), Float(y), displayCounters[cell], scaleX, scaleY)
End Function

Function DrawCounterPips(x:Float, y:Float, count:Int, scaleX:Float, scaleY:Float)
	SetColor 248, 251, 255
	Select count
		Case 1
			DrawCounterPip x, y
		Case 2
			DrawCounterPip x - 6 * scaleX, y - 6 * scaleY
			DrawCounterPip x + 6 * scaleX, y + 6 * scaleY
		Case 3
			DrawCounterPip x - 7 * scaleX, y - 7 * scaleY
			DrawCounterPip x, y
			DrawCounterPip x + 7 * scaleX, y + 7 * scaleY
		Case 4
			DrawCounterPip x - 7 * scaleX, y - 7 * scaleY
			DrawCounterPip x + 7 * scaleX, y - 7 * scaleY
			DrawCounterPip x - 7 * scaleX, y + 7 * scaleY
			DrawCounterPip x + 7 * scaleX, y + 7 * scaleY
		Case 5
			DrawCounterPip x - 8 * scaleX, y - 8 * scaleY
			DrawCounterPip x + 8 * scaleX, y - 8 * scaleY
			DrawCounterPip x, y
			DrawCounterPip x - 8 * scaleX, y + 8 * scaleY
			DrawCounterPip x + 8 * scaleX, y + 8 * scaleY
		Case 6
			For Local row:Int = -1 To 1
				DrawCounterPip x - 7 * scaleX, y + row * 8 * scaleY
				DrawCounterPip x + 7 * scaleX, y + row * 8 * scaleY
			Next
		Case 7
			DrawCounterPipSized x, y, 5.5
			For Local index:Int = 0 Until 6
				Local angle:Float = -90.0 + Float(index) * 60.0
				DrawCounterPipSized Float(x + Cos(angle) * 10.5 * scaleX), Float(y + Sin(angle) * 10.5 * scaleY), 5.5
			Next
		Case 8
			For Local index:Int = 0 Until 8
				Local angle:Float = -90.0 + Float(index) * 45.0
				DrawCounterPipSized Float(x + Cos(angle) * 10.5 * scaleX), Float(y + Sin(angle) * 10.5 * scaleY), 5.0
			Next
		Default
			DrawDenseCounterPips x, y, count, scaleX, scaleY
	End Select
End Function

Function DrawCounterPip(x:Float, y:Float)
	DrawCounterPipSized x, y, 7.0
End Function

Function DrawCounterPipSized(x:Float, y:Float, size:Float)
	DrawImageRect counterImage, x - size * 0.5, y - size * 0.5, size, size
End Function

' Cascades can temporarily accumulate more than the stable limit in a cell.
' Keep representing the actual count with compact pips instead of falling back
' to a digit, even for unusual crowded-board states.
Function DrawDenseCounterPips(x:Float, y:Float, count:Int, scaleX:Float, scaleY:Float)
	Local columns:Int = 3
	While columns * columns < count
		columns :+ 1
	Wend
	Local rows:Int = (count + columns - 1) / columns
	Local spacing:Float = Min(6.5, 26.0 / Float(Max(columns - 1, rows - 1)))
	Local pipSize:Float = Max(2.0, Min(4.8, spacing * 0.68))
	Local drawn:Int
	For Local row:Int = 0 Until rows
		Local inRow:Int = Min(columns, count - drawn)
		Local rowWidth:Float = Float(inRow - 1) * spacing
		For Local column:Int = 0 Until inRow
			Local px:Float = x + (Float(column) * spacing - rowWidth * 0.5) * scaleX
			Local py:Float = y + (Float(row) - Float(rows - 1) * 0.5) * spacing * scaleY
			DrawCounterPipSized px, py, pipSize
			drawn :+ 1
		Next
	Next
End Function

Function DrawWinnerPanel()
	SetColor 8, 12, 22
	SetAlpha 0.90
	DrawRect 290, 235, 420, 230
	SetAlpha 1.0
	SetPlayerColor(game.winner)
	DrawText "PLAYER " + (game.winner + 1) + " WINS", 425, 285
	SetColor 163, 180, 207
	DrawText "The last colour on the board", 390, 323
	DrawActionButton 330, 365, "PLAY AGAIN", 40, 115, 205
	DrawActionButton 510, 365, "MODES", 89, 72, 142
End Function

Function DrawActionButton(x:Float, y:Float, label:String, red:Int, green:Int, blue:Int)
	SetColor red, green, blue
	DrawRect x, y, 160, 56
	SetColor 255, 255, 255
	DrawText label, x + 38, y + 20
End Function

Function DrawCascadeMotion()
	If Not animationActive Or Not animationStarted Or animationIndex >= eventLog.count Then Return
	Local event:SCascadeEvent = eventLog.events[animationIndex]
	If event.kind = ECascadeEventKind.Placed Then
		Local x:Double, y:Double
		CellCentre(event.cell, x, y)
		Local progress:Float = Min(1.0, Float(Int(MilliSecs() - animationStartMillis)) / 90.0)
		SetPlayerColor(event.player)
		SetAlpha(1.0 - progress)
		Local radius:Float = 22.0 + progress * 20.0
		SetLineWidth 3
		DrawOval Float(x) - radius, Float(y) - radius, radius * 2.0, radius * 2.0
		SetLineWidth 1
		SetAlpha 1.0
		Return
	End If
	If event.kind <> ECascadeEventKind.Toppled Then Return
	Local sourceX:Double, sourceY:Double
	CellCentre(event.cell, sourceX, sourceY)
	Local progress:Float = Min(1.0, Float(Int(MilliSecs() - animationStartMillis)) / Float(cascadeStepMillis))
	progress = progress * progress * (3.0 - 2.0 * progress)
	For Local direction:Int = 1 To game.board.routeCount
		If animationIndex + direction >= eventLog.count Then Exit
		Local landing:SCascadeEvent = eventLog.events[animationIndex + direction]
		If landing.kind <> ECascadeEventKind.Landed Or landing.source <> event.cell Then Exit
		Local destinationX:Double, destinationY:Double
		CellCentre(landing.cell, destinationX, destinationY)
		Local x:Float = Float(sourceX + (destinationX - sourceX) * progress)
		Local y:Float = Float(sourceY + (destinationY - sourceY) * progress)
		SetPlayerColor(event.player)
		SetAlpha 0.2
		DrawImageRect counterImage, x - 13, y - 13, 26, 26
		SetAlpha 1.0
		SetPlayerColor(event.player)
		DrawImageRect counterImage, x - 8, y - 8, 16, 16
	Next
	SetAlpha 1.0
End Function

' Build the neutral counter at a much higher resolution than it is displayed.
' Filtering and mipmaps then preserve a smooth silhouette on Retina displays,
' while SetColor supplies the player's colour at draw time.
Function CreateCounterImage:TImage(flags:Int)
	Const SIZE:Int = 256
	Const CENTRE:Float = 127.5
	Const RADIUS:Float = 106.0
	Local pixmap:TPixmap = CreatePixmap(SIZE, SIZE, PF_RGBA8888)
	For Local py:Int = 0 Until SIZE
		For Local px:Int = 0 Until SIZE
			Local dx:Float = Float(px) - CENTRE
			Local dy:Float = Float(py) - CENTRE
			Local distance:Float = Sqr(dx * dx + dy * dy)
			Local coverage:Float = Min(1.0, Max(0.0, RADIUS + 0.75 - distance))
			If coverage > 0.0 Then
				Local shade:Float = 0.88 + 0.10 * (1.0 - (dy + RADIUS) / (RADIUS * 2.0))
				If distance > RADIUS - 14.0 Then shade :* 0.72
				Local highlightDistance:Float = Sqr((dx + 31.0) * (dx + 31.0) + (dy + 37.0) * (dy + 37.0))
				If highlightDistance < 25.0 Then shade = Min(1.0, shade + (25.0 - highlightDistance) / 170.0)
				Local alpha:Int = Min(255, Max(0, Int(coverage * 255.0)))
				Local grey:Int = Min(255, Max(0, Int(shade * 255.0)))
				pixmap.WritePixel(px, py, (alpha Shl 24) | (grey Shl 16) | (grey Shl 8) | grey)
			End If
		Next
	Next
	Return LoadImage(pixmap, flags)
End Function

Function CellCentre(cell:Int, x:Double Var, y:Double Var)
	viewGrid.CellCenter(game.board.cells[cell].column, game.board.cells[cell].row, x, y)
	x :+ boardX
	y :+ boardY
End Function

Function SetPlayerColor(player:Int)
	Select player
		Case 0
			SetColor 55, 145, 245
		Case 1
			SetColor 242, 91, 91
		Case 2
			SetColor 67, 190, 119
		Case 3
			SetColor 218, 151, 45
		Default
			SetColor 180, 190, 205
	End Select
End Function
