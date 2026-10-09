' Copyright (c) 2026 Bruce A Henderson and contributors
'
' This software is provided 'as-is', without any express or implied
' warranty. In no event will the authors be held liable for any damages
' arising from the use of this software.
'
' Permission is granted to anyone to use this software for any purpose,
' including commercial applications, and to alter it and redistribute it
' freely, subject to the following restrictions:
'
' 1. The origin of this software must not be misrepresented; you must not
'    claim that you wrote the original software. If you use this software
'    in a product, an acknowledgment in the product documentation would be
'    appreciated but is not required.
' 2. Altered source versions must be plainly marked as such, and must not be
'    misrepresented as being the original software.
' 3. This notice may not be removed or altered from any source distribution.

SuperStrict

Rem
bbdoc: Bounded deterministic state and input history for rollback simulation.
End Rem
Module GameNet.Rollback

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial rollback buffer"

Import GameNet.Core
Import BRL.Blitz

Rem
bbdoc: Returns the signed modular distance from @reference to @frame.
about: The result is valid when the frames are less than 2^31 apart.
End Rem
Function RollbackFrameDelta:Int(frame:UInt, reference:UInt)
	Return Int(frame - reference)
End Function

Rem
bbdoc: Returns True when @frame is newer than @reference.
End Rem
Function RollbackFrameAfter:Int(frame:UInt, reference:UInt)
	Return RollbackFrameDelta(frame, reference) > 0
End Function

Rem
bbdoc: Computes a stable 32-bit FNV-1a hash over opaque state bytes.
End Rem
Function RollbackHash32:UInt(data:Byte Ptr, length:Size_T, seed:UInt = $811c9dc5:UInt)
	Local hash:UInt = seed
	For Local index:Size_T = 0 Until length
		hash :~ UInt(data[index]) & $ff:UInt
		hash :* $01000193:UInt
	Next
	Return hash
End Function

Rem
bbdoc: Identifies whether one player's frame input is absent, predicted, or confirmed.
End Rem
Enum ERollbackInputStatus:Byte
	Missing
	Predicted
	Confirmed
End Enum

Rem
bbdoc: Reports how confirmed input relates to an existing prediction.
End Rem
Enum ERollbackConfirmResult:Byte
	Stored
	PredictionMatched
	PredictionMismatched
	Duplicate
	Rejected
End Enum

Rem
bbdoc: A borrowed input for one player and simulation frame.
about: The payload remains valid only until its rollback buffer is changed.
End Rem
Struct SRollbackInput
	Private
	Field _frame:UInt
	Field _player:Int
	Field _status:ERollbackInputStatus
	Field _payload:SPacketView

	Method New(frame:UInt, player:Int, status:ERollbackInputStatus, payload:SPacketView)
		_frame = frame
		_player = player
		_status = status
		_payload = payload
	End Method

	Public
	Method New()
	End Method

	Method Frame:UInt()
		Return _frame
	End Method

	Method Player:Int()
		Return _player
	End Method

	Method Status:ERollbackInputStatus()
		Return _status
	End Method

	Method Payload:SPacketView()
		Return _payload
	End Method
End Struct

Rem
bbdoc: Fixed-capacity state and per-player input storage for rollback games.
about: The game prepares frames, saves state at the beginning of each frame,
and supplies confirmed or predicted opaque input. When confirmed input differs
from a prediction, #NeedsRollback and #RollbackFrame identify the earliest
frame which must be restored and re-simulated. Storage is allocated by #Create;
normal frame operations perform no managed allocation.
End Rem
Type TRollbackBuffer
	Private
	Field _maxPlayers:Int
	Field _capacity:Int
	Field _maxStateSize:Size_T
	Field _maxInputSize:Size_T
	Field _frameTags:UInt[]
	Field _frameValid:Byte[]
	Field _stateLengths:Size_T[]
	Field _stateHashes:UInt[]
	Field _stateStorage:Byte Ptr
	Field _inputLengths:Size_T[]
	Field _inputStatuses:Byte[]
	Field _inputStorage:Byte Ptr
	Field _hasLatest:Int
	Field _latestFrame:UInt
	Field _hasConfirmCursor:Int
	Field _nextConfirmFrame:UInt
	Field _hasConfirmedFrame:Int
	Field _confirmedFrame:UInt
	Field _needsRollback:Int
	Field _rollbackFrame:UInt

	Method New(maxPlayers:Int, capacity:Int, maxStateSize:Size_T, maxInputSize:Size_T)
		_maxPlayers = maxPlayers
		_capacity = capacity
		_maxStateSize = maxStateSize
		_maxInputSize = maxInputSize
		_frameTags = New UInt[capacity]
		_frameValid = New Byte[capacity]
		_stateLengths = New Size_T[capacity]
		_stateHashes = New UInt[capacity]
		_inputLengths = New Size_T[maxPlayers * capacity]
		_inputStatuses = New Byte[maxPlayers * capacity]
		_stateStorage = MemAlloc(Size_T(capacity) * maxStateSize)
		_inputStorage = MemAlloc(Size_T(maxPlayers * capacity) * maxInputSize)
	End Method

	Method FrameSlot:Int(frame:UInt)
		Return Int(frame Mod UInt(_capacity))
	End Method

	Method InputSlot:Int(player:Int, frameSlot:Int)
		Return player * _capacity + frameSlot
	End Method

	Method StateAddress:Byte Ptr(frameSlot:Int)
		Return _stateStorage + Size_T(frameSlot) * _maxStateSize
	End Method

	Method InputAddress:Byte Ptr(inputSlot:Int)
		Return _inputStorage + Size_T(inputSlot) * _maxInputSize
	End Method

	Method ResetSlot(frame:UInt)
		Local frameSlot:Int = FrameSlot(frame)
		_frameTags[frameSlot] = frame
		_frameValid[frameSlot] = True
		_stateLengths[frameSlot] = 0
		_stateHashes[frameSlot] = 0
		For Local player:Int = 0 Until _maxPlayers
			Local inputSlot:Int = InputSlot(player, frameSlot)
			_inputLengths[inputSlot] = 0
			_inputStatuses[inputSlot] = Byte(ERollbackInputStatus.Missing)
		Next
	End Method

	Method HasFrame:Int(frame:UInt)
		Local slot:Int = FrameSlot(frame)
		Return _frameValid[slot] And _frameTags[slot] = frame
	End Method

	Method PayloadEquals:Int(address:Byte Ptr, length:Size_T, other:Byte Ptr, otherLength:Size_T)
		If length <> otherLength Then Return False
		For Local index:Size_T = 0 Until length
			If address[index] <> other[index] Then Return False
		Next
		Return True
	End Method

	Method AllInputsConfirmed:Int(frame:UInt)
		If Not HasFrame(frame) Then Return False
		Local frameSlot:Int = FrameSlot(frame)
		For Local player:Int = 0 Until _maxPlayers
			If ERollbackInputStatus(_inputStatuses[InputSlot(player, frameSlot)]) <> ERollbackInputStatus.Confirmed Then Return False
		Next
		Return True
	End Method

	Method UpdateConfirmedFrame()
		If Not _hasConfirmCursor Then Return
		While AllInputsConfirmed(_nextConfirmFrame)
			_confirmedFrame = _nextConfirmFrame
			_hasConfirmedFrame = True
			_nextConfirmFrame :+ 1
		Wend
	End Method

	Method MarkMismatch(frame:UInt)
		If Not _needsRollback Or RollbackFrameAfter(_rollbackFrame, frame) Then
			_needsRollback = True
			_rollbackFrame = frame
		End If
	End Method

	Public
	Method Delete()
		If _stateStorage Then MemFree(_stateStorage)
		If _inputStorage Then MemFree(_inputStorage)
		_stateStorage = Null
		_inputStorage = Null
	End Method

	Rem
	bbdoc: Creates a rollback buffer with bounded opaque storage.
	End Rem
	Function Create:TRollbackBuffer(maxPlayers:Int, capacity:Int, maxStateSize:Size_T, maxInputSize:Size_T)
		If maxPlayers < 1 Or capacity < 2 Or maxStateSize < 1 Or maxInputSize < 1 Then Return Null
		Return New TRollbackBuffer(maxPlayers, capacity, maxStateSize, maxInputSize)
	End Function

	Rem
	bbdoc: Clears all retained frames without reallocating storage.
	End Rem
	Method Clear()
		For Local index:Int = 0 Until _frameValid.Length
			_frameValid[index] = False
		Next
		_hasLatest = False
		_hasConfirmCursor = False
		_hasConfirmedFrame = False
		_needsRollback = False
	End Method

	Rem
	bbdoc: Makes @frame available for state and input storage.
	returns: False when @frame is older than the retained window or advances by
	at least the complete capacity in one operation.
	End Rem
	Method PrepareFrame:Int(frame:UInt)
		If Not _hasLatest Then
			ResetSlot(frame)
			_hasLatest = True
			_latestFrame = frame
			_hasConfirmCursor = True
			_nextConfirmFrame = frame
			Return True
		End If

		Local delta:Int = RollbackFrameDelta(frame, _latestFrame)
		If delta > 0 Then
			If delta >= _capacity Then Return False
			For Local offset:Int = 1 To delta
				ResetSlot(_latestFrame + UInt(offset))
			Next
			_latestFrame = frame
			Return True
		End If
		Return HasFrame(frame)
	End Method

	Rem
	bbdoc: Saves opaque state representing the beginning of @frame.
	End Rem
	Method SaveState:Int(frame:UInt, state:Byte Ptr, length:Size_T)
		If length > _maxStateSize Or (length > 0 And Not state) Or Not PrepareFrame(frame) Then Return False
		Local slot:Int = FrameSlot(frame)
		_stateLengths[slot] = length
		If length > 0 Then MemCopy(StateAddress(slot), state, length)
		_stateHashes[slot] = RollbackHash32(StateAddress(slot), length)
		Return True
	End Method

	Rem
	bbdoc: Returns borrowed state saved for the beginning of @frame.
	End Rem
	Method GetState:Int(frame:UInt, state:SPacketView Var)
		If Not HasFrame(frame) Then
			state = New SPacketView
			Return False
		End If
		Local slot:Int = FrameSlot(frame)
		If _stateLengths[slot] = 0 Then
			state = New SPacketView
			Return False
		End If
		state = New SPacketView(StateAddress(slot), _stateLengths[slot])
		Return True
	End Method

	Rem
	bbdoc: Returns the stored state's stable hash, or zero when unavailable.
	End Rem
	Method StateHash:UInt(frame:UInt)
		If Not HasFrame(frame) Then Return 0
		Return _stateHashes[FrameSlot(frame)]
	End Method

	Rem
	bbdoc: Stores or replaces predicted input unless that player/frame is confirmed.
	End Rem
	Method PredictInput:Int(player:Int, frame:UInt, payload:Byte Ptr, length:Size_T)
		If player < 0 Or player >= _maxPlayers Or length > _maxInputSize Or (length > 0 And Not payload) Or Not PrepareFrame(frame) Then Return False
		Local inputSlot:Int = InputSlot(player, FrameSlot(frame))
		If ERollbackInputStatus(_inputStatuses[inputSlot]) = ERollbackInputStatus.Confirmed Then Return False
		_inputLengths[inputSlot] = length
		If length > 0 Then MemCopy(InputAddress(inputSlot), payload, length)
		_inputStatuses[inputSlot] = Byte(ERollbackInputStatus.Predicted)
		Return True
	End Method

	Rem
	bbdoc: Stores confirmed input and compares it with any prior prediction.
	End Rem
	Method ConfirmInput:ERollbackConfirmResult(player:Int, frame:UInt, payload:Byte Ptr, length:Size_T)
		If player < 0 Or player >= _maxPlayers Or length > _maxInputSize Or (length > 0 And Not payload) Or Not PrepareFrame(frame) Then Return ERollbackConfirmResult.Rejected
		Local inputSlot:Int = InputSlot(player, FrameSlot(frame))
		Local status:ERollbackInputStatus = ERollbackInputStatus(_inputStatuses[inputSlot])
		If status = ERollbackInputStatus.Confirmed Then
			If PayloadEquals(InputAddress(inputSlot), _inputLengths[inputSlot], payload, length) Then Return ERollbackConfirmResult.Duplicate
			Return ERollbackConfirmResult.Rejected
		End If

		Local result:ERollbackConfirmResult = ERollbackConfirmResult.Stored
		If status = ERollbackInputStatus.Predicted Then
			If PayloadEquals(InputAddress(inputSlot), _inputLengths[inputSlot], payload, length) Then
				result = ERollbackConfirmResult.PredictionMatched
			Else
				result = ERollbackConfirmResult.PredictionMismatched
				MarkMismatch(frame)
			End If
		End If

		_inputLengths[inputSlot] = length
		If length > 0 Then MemCopy(InputAddress(inputSlot), payload, length)
		_inputStatuses[inputSlot] = Byte(ERollbackInputStatus.Confirmed)
		UpdateConfirmedFrame()
		Return result
	End Method

	Rem
	bbdoc: Returns one player's borrowed input for @frame.
	End Rem
	Method GetInput:Int(player:Int, frame:UInt, input:SRollbackInput Var)
		If player < 0 Or player >= _maxPlayers Or Not HasFrame(frame) Then
			input = New SRollbackInput
			Return False
		End If
		Local inputSlot:Int = InputSlot(player, FrameSlot(frame))
		Local status:ERollbackInputStatus = ERollbackInputStatus(_inputStatuses[inputSlot])
		If status = ERollbackInputStatus.Missing Then
			input = New SRollbackInput
			Return False
		End If
		input = New SRollbackInput(frame, player, status, New SPacketView(InputAddress(inputSlot), _inputLengths[inputSlot]))
		Return True
	End Method

	Method NeedsRollback:Int()
		Return _needsRollback
	End Method

	Method RollbackFrame:UInt()
		Return _rollbackFrame
	End Method

	Rem
	bbdoc: Clears the pending rollback request after the game re-simulates.
	End Rem
	Method ClearRollback()
		_needsRollback = False
	End Method

	Method HasConfirmedFrame:Int()
		Return _hasConfirmedFrame
	End Method

	Method ConfirmedFrame:UInt()
		Return _confirmedFrame
	End Method

	Method LatestFrame:UInt()
		Return _latestFrame
	End Method

	Method Capacity:Int()
		Return _capacity
	End Method

	Method MaxPlayers:Int()
		Return _maxPlayers
	End Method
End Type

?
