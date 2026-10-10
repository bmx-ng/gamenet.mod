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
bbdoc: Bounded input history and sequencing for client-side prediction.
End Rem
Module GameNet.Prediction

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial input history and sequencer"

Import GameNet.Core
Import BRL.Blitz

Rem
bbdoc: Returns the signed modular distance from @reference to @sequence.
about: The result is valid when the values are less than 2^31 apart.
End Rem
Function PredictionSequenceDelta:Int(sequence:UInt, reference:UInt)
	Return Int(sequence - reference)
End Function

Rem
bbdoc: Returns True when @sequence is newer than @reference.
End Rem
Function PredictionSequenceAfter:Int(sequence:UInt, reference:UInt)
	Return PredictionSequenceDelta(sequence, reference) > 0
End Function

Rem
bbdoc: One borrowed, sequenced input command.
about: The payload remains valid only until its history is changed.
End Rem
Struct SPredictionInput
	Private
	Field _sequence:UInt
	Field _payload:SPacketView

	Method New(sequence:UInt, payload:SPacketView)
		_sequence = sequence
		_payload = payload
	End Method

	Public
	Method New()
	End Method

	Rem
	bbdoc: Returns the command sequence number.
	End Rem
	Method Sequence:UInt()
		Return _sequence
	End Method

	Rem
	bbdoc: Returns a borrowed view of the game-defined command bytes.
	End Rem
	Method Payload:SPacketView()
		Return _payload
	End Method
End Struct

Rem
bbdoc: A fixed-capacity history of unacknowledged prediction inputs.
about: Storage is allocated by #Create. Adding, acknowledging, and reading
commands within the configured bounds perform no managed allocation. Commands
must be added in sequence order. A full history rejects new input rather than
silently discarding an unacknowledged command.
End Rem
Type TPredictionHistory
	Private
	Field _sequences:UInt[]
	Field _lengths:Size_T[]
	Field _storage:Byte Ptr
	Field _maxPayloadSize:Size_T
	Field _readIndex:Int
	Field _writeIndex:Int
	Field _count:Int

	Method New(capacity:Int, maxPayloadSize:Size_T)
		_sequences = New UInt[capacity]
		_lengths = New Size_T[capacity]
		_maxPayloadSize = maxPayloadSize
		_storage = MemAlloc(Size_T(capacity) * maxPayloadSize)
	End Method

	Method PayloadView:SPacketView(index:Int)
		Return New SPacketView(_storage + Size_T(index) * _maxPayloadSize, _lengths[index])
	End Method

	Public
	Method Delete()
		If _storage Then MemFree(_storage)
		_storage = Null
	End Method

	Rem
	bbdoc: Creates a bounded input history.
	returns: A new history, or Null when either argument is less than one.
	End Rem
	Function Create:TPredictionHistory(capacity:Int, maxPayloadSize:Size_T)
		If capacity < 1 Or maxPayloadSize < 1 Then Return Null
		Local storageBytes:Size_T
		If Not NetAccumulateSize(storageBytes, Size_T(capacity), maxPayloadSize) Then Return Null
		Return New TPredictionHistory(capacity, maxPayloadSize)
	End Function

	Rem
	bbdoc: Removes every command without reallocating storage.
	End Rem
	Method Clear()
		_readIndex = 0
		_writeIndex = 0
		_count = 0
	End Method

	Rem
	bbdoc: Adds an unacknowledged game-defined command.
	returns: False when the history is full, the payload is invalid or too
	large, or @sequence does not follow the newest stored command.
	End Rem
	Method Add:Int(sequence:UInt, payload:Byte Ptr, length:Size_T)
		If _count = _sequences.Length Then Return False
		If length > _maxPayloadSize Or (length > 0 And Not payload) Then Return False
		If _count > 0 Then
			Local latestIndex:Int = (_writeIndex - 1 + _sequences.Length) Mod _sequences.Length
			If Not PredictionSequenceAfter(sequence, _sequences[latestIndex]) Then Return False
		End If

		_sequences[_writeIndex] = sequence
		_lengths[_writeIndex] = length
		If length > 0 Then MemCopy(_storage + Size_T(_writeIndex) * _maxPayloadSize, payload, length)
		_writeIndex = (_writeIndex + 1) Mod _sequences.Length
		_count :+ 1
		Return True
	End Method

	Rem
	bbdoc: Removes commands up to and including @acknowledgedSequence.
	returns: The number of removed commands. An acknowledgement older than the
	oldest command changes nothing.
	End Rem
	Method Acknowledge:Int(acknowledgedSequence:UInt)
		Local removed:Int
		While _count > 0 And Not PredictionSequenceAfter(_sequences[_readIndex], acknowledgedSequence)
			_readIndex = (_readIndex + 1) Mod _sequences.Length
			_count :- 1
			removed :+ 1
		Wend
		If _count = 0 Then _readIndex = _writeIndex
		Return removed
	End Method

	Rem
	bbdoc: Reads a command by oldest-first @index.
	returns: False when @index is outside the retained history.
	End Rem
	Method Get:Int(index:Int, input:SPredictionInput Var)
		If index < 0 Or index >= _count Then
			input = New SPredictionInput
			Return False
		End If
		Local slot:Int = (_readIndex + index) Mod _sequences.Length
		input = New SPredictionInput(_sequences[slot], PayloadView(slot))
		Return True
	End Method

	Rem
	bbdoc: Returns the number of retained, unacknowledged commands.
	End Rem
	Method Count:Int()
		Return _count
	End Method

	Rem
	bbdoc: Returns the maximum number of retained commands.
	End Rem
	Method Capacity:Int()
		Return _sequences.Length
	End Method

	Rem
	bbdoc: Returns the maximum payload size for one command.
	End Rem
	Method MaxPayloadSize:Size_T()
		Return _maxPayloadSize
	End Method

	Rem
	bbdoc: Returns the oldest retained sequence, or zero when empty.
	End Rem
	Method OldestSequence:UInt()
		If _count = 0 Then Return 0
		Return _sequences[_readIndex]
	End Method

	Rem
	bbdoc: Returns the newest retained sequence, or zero when empty.
	End Rem
	Method LatestSequence:UInt()
		If _count = 0 Then Return 0
		Local index:Int = (_writeIndex - 1 + _sequences.Length) Mod _sequences.Length
		Return _sequences[index]
	End Method
End Type

Rem
bbdoc: Result of inspecting a received input sequence.
End Rem
Enum EPredictionSequenceResult:Byte
	Accepted
	Duplicate
	Gap
End Enum

Rem
bbdoc: Tracks the next input sequence an authority can process.
about: #Process accepts an exact next command once, rejects already processed
commands as duplicates, and reports future commands as gaps without advancing.
End Rem
Struct SPredictionSequencer
	Private
	Field _nextSequence:UInt
	Field _lastProcessed:UInt
	Field _processed:Int

	Public
	Rem
	bbdoc: Resets the sequencer to expect @nextSequence.
	End Rem
	Method Reset(nextSequence:UInt = 1)
		_nextSequence = nextSequence
		_lastProcessed = nextSequence - 1
		_processed = False
	End Method

	Rem
	bbdoc: Processes @sequence if it is exactly the next expected command.
	End Rem
	Method Process:EPredictionSequenceResult(sequence:UInt)
		Local delta:Int = PredictionSequenceDelta(sequence, _nextSequence)
		If delta < 0 Then Return EPredictionSequenceResult.Duplicate
		If delta > 0 Then Return EPredictionSequenceResult.Gap
		_lastProcessed = sequence
		_nextSequence = sequence + 1
		_processed = True
		Return EPredictionSequenceResult.Accepted
	End Method

	Rem
	bbdoc: Returns the sequence expected next.
	End Rem
	Method NextSequence:UInt()
		Return _nextSequence
	End Method

	Rem
	bbdoc: Returns the last processed sequence.
	End Rem
	Method LastProcessed:UInt()
		Return _lastProcessed
	End Method

	Rem
	bbdoc: Returns True after at least one command has been processed.
	End Rem
	Method HasProcessed:Int()
		Return _processed
	End Method
End Struct

?
