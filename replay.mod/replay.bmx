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
bbdoc: Bounded deterministic input recordings and portable replay encoding.
End Rem
Module GameNet.Replay

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial deterministic replay tape"

Import GameNet.Core
Import BRL.Blitz

Private

Const REPLAY_MAGIC:UInt = $474e5231:UInt ' GNR1
Const REPLAY_WIRE_VERSION:UInt = 1
Const REPLAY_HEADER_SIZE:Size_T = 18
Const REPLAY_FRAME_HEADER_SIZE:Size_T = 9
Const REPLAY_CHECKSUM_SIZE:Size_T = 4

Function ReplayHash32:UInt(data:Byte Ptr, length:Size_T)
	Local hash:UInt = $811c9dc5:UInt
	For Local index:Size_T = 0 Until length
		hash :~ UInt(data[index]) & $ff:UInt
		hash :* $01000193:UInt
	Next
	Return hash
End Function

Public

Rem
bbdoc: One borrowed frame in a #TReplayTape.
about: Input views remain valid until the tape is cleared, loaded, or deleted.
End Rem
Struct SReplayFrame
	Private
	Field _tape:TReplayTape
	Field _index:Int
	Field _frame:UInt
	Field _hasStateHash:Int
	Field _stateHash:UInt

	Method New(tape:TReplayTape, index:Int, frame:UInt, hasStateHash:Int, stateHash:UInt)
		_tape = tape
		_index = index
		_frame = frame
		_hasStateHash = hasStateHash
		_stateHash = stateHash
	End Method

	Public
	Method New()
	End Method

	Method Frame:UInt()
		Return _frame
	End Method

	Method HasStateHash:Int()
		Return _hasStateHash
	End Method

	Method StateHash:UInt()
		Return _stateHash
	End Method

	Method Input:Int(player:Int, payload:SPacketView Var)
		If Not _tape Then
			payload = New SPacketView
			Return False
		End If
		Return _tape.GetInput(_index, player, payload)
	End Method
End Struct

Rem
bbdoc: A value cursor which reads a replay tape from oldest to newest.
End Rem
Struct SReplayCursor
	Private
	Field _tape:TReplayTape
	Field _index:Int

	Public
	Method New(tape:TReplayTape)
		_tape = tape
	End Method

	Method Reset()
		_index = 0
	End Method

	Method Next:Int(frame:SReplayFrame Var)
		If Not _tape Or Not _tape.GetFrame(_index, frame) Then
			frame = New SReplayFrame
			Return False
		End If
		_index :+ 1
		Return True
	End Method

	Method Position:Int()
		Return _index
	End Method

	Method Remaining:Int()
		If Not _tape Then Return 0
		Return Max(0, _tape.FrameCount() - _index)
	End Method
End Struct

Rem
bbdoc: A fixed-capacity deterministic replay recording.
about: The tape stores one opaque initial state and sequential frames of opaque
input for every configured player. Storage is allocated by #Create; beginning,
appending, reading, writing, and iterating do not inherently allocate managed
objects. A full tape rejects new frames rather than discarding old recording.
End Rem
Type TReplayTape
	Private
	Field _playerCount:Int
	Field _capacity:Int
	Field _maxInitialStateSize:Size_T
	Field _maxInputSize:Size_T
	Field _initialFrame:UInt
	Field _initialStateLength:Size_T
	Field _initialStateStorage:Byte Ptr
	Field _frameNumbers:UInt[]
	Field _hashValid:Byte[]
	Field _hashes:UInt[]
	Field _inputLengths:Size_T[]
	Field _inputStorage:Byte Ptr
	Field _count:Int

	Method New(playerCount:Int, capacity:Int, maxInitialStateSize:Size_T, maxInputSize:Size_T)
		_playerCount = playerCount
		_capacity = capacity
		_maxInitialStateSize = maxInitialStateSize
		_maxInputSize = maxInputSize
		_initialStateStorage = MemAlloc(maxInitialStateSize)
		_frameNumbers = New UInt[capacity]
		_hashValid = New Byte[capacity]
		_hashes = New UInt[capacity]
		_inputLengths = New Size_T[capacity * playerCount]
		_inputStorage = MemAlloc(Size_T(capacity * playerCount) * maxInputSize)
	End Method

	Method InputSlot:Int(frameIndex:Int, player:Int)
		Return frameIndex * _playerCount + player
	End Method

	Method InputAddress:Byte Ptr(frameIndex:Int, player:Int)
		Return _inputStorage + Size_T(InputSlot(frameIndex, player)) * _maxInputSize
	End Method

	Public
	Method Delete()
		If _initialStateStorage Then MemFree(_initialStateStorage)
		If _inputStorage Then MemFree(_inputStorage)
		_initialStateStorage = Null
		_inputStorage = Null
	End Method

	Rem
	bbdoc: Creates an empty replay tape with fixed storage bounds.
	End Rem
	Function Create:TReplayTape(playerCount:Int, capacity:Int, maxInitialStateSize:Size_T, maxInputSize:Size_T)
		If playerCount < 1 Or playerCount > 255 Or capacity < 1 Or capacity > $7fffffff / playerCount Then Return Null
		If maxInitialStateSize < 1 Or maxInitialStateSize > Size_T($ffffffff:UInt) Or maxInputSize < 1 Or maxInputSize > 65535 Then Return Null
		Return New TReplayTape(playerCount, capacity, maxInitialStateSize, maxInputSize)
	End Function

	Rem
	bbdoc: Clears the tape without reallocating storage.
	End Rem
	Method Clear()
		_initialFrame = 0
		_initialStateLength = 0
		_count = 0
	End Method

	Rem
	bbdoc: Begins a recording from opaque @initialState at @initialFrame.
	End Rem
	Method Begin:Int(initialFrame:UInt, initialState:Byte Ptr, length:Size_T)
		If length < 1 Or length > _maxInitialStateSize Or Not initialState Then Return False
		_initialFrame = initialFrame
		_initialStateLength = length
		MemCopy(_initialStateStorage, initialState, length)
		_count = 0
		Return True
	End Method

	Rem
	bbdoc: Appends one sequential frame of input for every player.
	param stateHash: Optional hash of deterministic state after this frame.
	End Rem
	Method Append:Int(frame:UInt, inputs:SPacketView[], stateHash:UInt = 0, hasStateHash:Int = False)
		If _initialStateLength = 0 Or _count = _capacity Or inputs.Length <> _playerCount Then Return False
		If frame <> _initialFrame + UInt(_count) Then Return False
		For Local player:Int = 0 Until _playerCount
			If inputs[player].Length() > _maxInputSize Or (inputs[player].Length() > 0 And Not inputs[player].Data()) Then Return False
		Next

		Local frameIndex:Int = _count
		_frameNumbers[frameIndex] = frame
		_hashValid[frameIndex] = 0
		If hasStateHash Then _hashValid[frameIndex] = 1
		_hashes[frameIndex] = stateHash
		For Local player:Int = 0 Until _playerCount
			Local slot:Int = InputSlot(frameIndex, player)
			_inputLengths[slot] = inputs[player].Length()
			If inputs[player].Length() > 0 Then MemCopy(InputAddress(frameIndex, player), inputs[player].Data(), inputs[player].Length())
		Next
		_count :+ 1
		Return True
	End Method

	Rem
	bbdoc: Returns the borrowed initial deterministic state.
	End Rem
	Method InitialState:Int(state:SPacketView Var)
		If _initialStateLength = 0 Then
			state = New SPacketView
			Return False
		End If
		state = New SPacketView(_initialStateStorage, _initialStateLength)
		Return True
	End Method

	Method GetInput:Int(frameIndex:Int, player:Int, payload:SPacketView Var)
		If frameIndex < 0 Or frameIndex >= _count Or player < 0 Or player >= _playerCount Then
			payload = New SPacketView
			Return False
		End If
		Local slot:Int = InputSlot(frameIndex, player)
		payload = New SPacketView(InputAddress(frameIndex, player), _inputLengths[slot])
		Return True
	End Method

	Method GetFrame:Int(index:Int, frame:SReplayFrame Var)
		If index < 0 Or index >= _count Then
			frame = New SReplayFrame
			Return False
		End If
		frame = New SReplayFrame(Self, index, _frameNumbers[index], _hashValid[index], _hashes[index])
		Return True
	End Method

	Method Cursor:SReplayCursor()
		Return New SReplayCursor(Self)
	End Method

	Rem
	bbdoc: Returns the exact byte capacity needed by #Write.
	End Rem
	Method SerializedSize:Size_T()
		If _initialStateLength = 0 Then Return 0
		Local size:Size_T = REPLAY_HEADER_SIZE + _initialStateLength + REPLAY_CHECKSUM_SIZE
		For Local frameIndex:Int = 0 Until _count
			size :+ REPLAY_FRAME_HEADER_SIZE + Size_T(_playerCount * 2)
			For Local player:Int = 0 Until _playerCount
				size :+ _inputLengths[InputSlot(frameIndex, player)]
			Next
		Next
		Return size
	End Method

	Rem
	bbdoc: Writes a portable replay packet and returns its length.
	End Rem
	Method Write:Size_T(buffer:Byte Ptr, capacity:Size_T)
		If _initialStateLength = 0 Or Not buffer Then Return 0
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(REPLAY_MAGIC)
		writer.WriteUInt8(REPLAY_WIRE_VERSION)
		writer.WriteUInt8(UInt(_playerCount))
		writer.WriteUInt32(_initialFrame)
		writer.WriteUInt32(UInt(_initialStateLength))
		writer.WriteUInt32(UInt(_count))
		writer.WriteBytes(_initialStateStorage, _initialStateLength)
		For Local frameIndex:Int = 0 Until _count
			writer.WriteUInt32(_frameNumbers[frameIndex])
			writer.WriteUInt8(UInt(_hashValid[frameIndex]))
			writer.WriteUInt32(_hashes[frameIndex])
			For Local player:Int = 0 Until _playerCount
				Local slot:Int = InputSlot(frameIndex, player)
				writer.WriteUInt16(UInt(_inputLengths[slot]))
				writer.WriteBytes(InputAddress(frameIndex, player), _inputLengths[slot])
			Next
		Next
		If writer.Failed() Then Return 0
		Local checksum:UInt = ReplayHash32(buffer, writer.Position())
		writer.WriteUInt32(checksum)
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Rem
	bbdoc: Replaces the tape from a portable packet after fully validating it.
	about: Invalid data leaves the existing recording unchanged.
	End Rem
	Method Read:Int(packet:SPacketView)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local magic:UInt, version:UInt, playerCount:UInt
		Local initialFrame:UInt, initialLength:UInt, frameCount:UInt
		If Not reader.ReadUInt32(magic) Or magic <> REPLAY_MAGIC Or Not reader.ReadUInt8(version) Or version <> REPLAY_WIRE_VERSION Or Not reader.ReadUInt8(playerCount) Or Int(playerCount) <> _playerCount Then Return False
		If Not reader.ReadUInt32(initialFrame) Or Not reader.ReadUInt32(initialLength) Or initialLength < 1 Or Size_T(initialLength) > _maxInitialStateSize Then Return False
		If Not reader.ReadUInt32(frameCount) Or frameCount > UInt(_capacity) Or Size_T(initialLength) > reader.Remaining() Or Not reader.Skip(Size_T(initialLength)) Then Return False
		For Local frameIndex:Int = 0 Until Int(frameCount)
			Local frame:UInt, hashValid:UInt, hash:UInt
			If Not reader.ReadUInt32(frame) Or frame <> initialFrame + UInt(frameIndex) Or Not reader.ReadUInt8(hashValid) Or hashValid > 1 Or Not reader.ReadUInt32(hash) Then Return False
			For Local player:Int = 0 Until _playerCount
				Local length:UInt
				If Not reader.ReadUInt16(length) Or Size_T(length) > _maxInputSize Or Size_T(length) > reader.Remaining() Or Not reader.Skip(Size_T(length)) Then Return False
			Next
		Next
		Local checksum:UInt
		If Not reader.ReadUInt32(checksum) Or reader.Remaining() <> 0 Then Return False
		If packet.Length() < REPLAY_CHECKSUM_SIZE Or ReplayHash32(packet.Data(), packet.Length() - REPLAY_CHECKSUM_SIZE) <> checksum Then Return False

		' Decode again only after complete validation, keeping replacement atomic.
		reader = New SPacketReader(packet)
		reader.ReadUInt32(magic)
		reader.ReadUInt8(version)
		reader.ReadUInt8(playerCount)
		reader.ReadUInt32(initialFrame)
		reader.ReadUInt32(initialLength)
		reader.ReadUInt32(frameCount)
		Local initialState:SPacketView = reader.RemainingView()
		Begin(initialFrame, initialState.Data(), Size_T(initialLength))
		reader.Skip(Size_T(initialLength))
		For Local frameIndex:Int = 0 Until Int(frameCount)
			Local frame:UInt, hashValid:UInt, hash:UInt
			reader.ReadUInt32(frame)
			reader.ReadUInt8(hashValid)
			reader.ReadUInt32(hash)
			_frameNumbers[frameIndex] = frame
			_hashValid[frameIndex] = Byte(hashValid)
			_hashes[frameIndex] = hash
			For Local player:Int = 0 Until _playerCount
				Local length:UInt
				reader.ReadUInt16(length)
				Local slot:Int = InputSlot(frameIndex, player)
				_inputLengths[slot] = Size_T(length)
				If length > 0 Then MemCopy(InputAddress(frameIndex, player), reader.RemainingView().Data(), Size_T(length))
				reader.Skip(Size_T(length))
			Next
		Next
		_count = Int(frameCount)
		Return True
	End Method

	Method PlayerCount:Int()
		Return _playerCount
	End Method

	Method Capacity:Int()
		Return _capacity
	End Method

	Method FrameCount:Int()
		Return _count
	End Method

	Method InitialFrame:UInt()
		Return _initialFrame
	End Method

	Method MaxInitialStateSize:Size_T()
		Return _maxInitialStateSize
	End Method

	Method MaxInputSize:Size_T()
		Return _maxInputSize
	End Method
End Type

?
