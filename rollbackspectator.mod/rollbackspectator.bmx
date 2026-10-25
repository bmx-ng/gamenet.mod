' Copyright (c) 2026 Bruce A Henderson and contributors
'
' This software is provided 'as-is', without any express or implied
' warranty. In no event will the authors be held liable for any damages
' arising from the use of this software.
'
' Permission is granted to anyone to use this software for any purpose,
' including commercial applications, and to alter it and redistribute it
' freely, subject to the restrictions in the zlib/libpng licence.

SuperStrict

Rem
bbdoc: Live confirmed-input playback for rollback match spectators.
End Rem
Module GameNet.RollbackSpectator

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"
ModuleInfo "History: 0.1 Initial confirmed-input spectator stream"

Import GameNet.RollbackSession
Import BRL.Blitz

Private

Const SPECTATOR_BOOTSTRAP_MAGIC:UInt = $474e5342:UInt ' GNSB
Const SPECTATOR_FRAME_MAGIC:UInt = $474e5346:UInt ' GNSF
Const SPECTATOR_WIRE_VERSION:UInt = 1
Const SPECTATOR_BOOTSTRAP_OVERHEAD:Size_T = 18
Const SPECTATOR_FRAME_OVERHEAD:Size_T = 14

Public

Rem
bbdoc: Fatal reason a spectator playback stream stopped.
End Rem
Enum ERollbackSpectatorFailure:Byte
	None
	InvalidBootstrap
	StateLoadFailed
	InvalidFrame
	SimulationFailed
	StateSaveFailed
	StateHashMismatch
End Enum

Rem
bbdoc: Produces a confirmed rollback timeline for one spectator connection.
about: The source snapshots a confirmed state when #PrepareBootstrap is called.
Bootstrap and frame packets are intended for reliable ordered delivery. Writing
a packet does not advance the source; commit it only after delivery is accepted.
End Rem
Type TRollbackSpectatorSource
	Private
	Field _session:TRollbackSession
	Field _stateStorage:Byte Ptr
	Field _inputs:SPacketView[]
	Field _stateLength:Size_T
	Field _bootstrapFrame:UInt
	Field _nextFrame:UInt
	Field _prepared:Int
	Field _started:Int

	Method New(session:TRollbackSession)
		_session = session
		_stateStorage = MemAlloc(session.MaxStateSize())
		_inputs = New SPacketView[session.PlayerCount()]
	End Method

	Public
	Function Create:TRollbackSpectatorSource(session:TRollbackSession)
		If Not session Then
			Return Null
		End If
		Return New TRollbackSpectatorSource(session)
	End Function

	Method Delete()
		If _stateStorage Then
			MemFree(_stateStorage)
		End If
		_stateStorage = Null
	End Method

	Rem
	bbdoc: Captures the newest fully confirmed state as the spectator starting point.
	End Rem
	Method PrepareBootstrap:Int()
		If Not _session.IsRunning() Or _session.HasPendingRollback() Or Not _session.HasConfirmedFrame() Then
			Return False
		End If
		Local frame:UInt = _session.ConfirmedFrame() + 1
		Local state:SPacketView
		If Not _session.GetSavedState(frame, state) Or state.IsEmpty() Or state.Length() > _session.MaxStateSize() Then
			Return False
		End If
		MemCopy(_stateStorage, state.Data(), state.Length())
		_stateLength = state.Length()
		_bootstrapFrame = frame
		_nextFrame = frame
		_prepared = True
		_started = False
		Return True
	End Method

	Method WriteBootstrap:Size_T(buffer:Byte Ptr, capacity:Size_T)
		If Not _prepared Or Not buffer Or capacity < SPECTATOR_BOOTSTRAP_OVERHEAD + _stateLength Then
			Return 0
		End If
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(SPECTATOR_BOOTSTRAP_MAGIC)
		writer.WriteUInt8(SPECTATOR_WIRE_VERSION)
		writer.WriteUInt8(UInt(_session.PlayerCount()))
		writer.WriteUInt32(_bootstrapFrame)
		writer.WriteUInt32(UInt(_stateLength))
		writer.WriteUInt32(RollbackHash32(_stateStorage, _stateLength))
		writer.WriteBytes(_stateStorage, _stateLength)
		If writer.Failed() Then
			Return 0
		End If
		Return writer.Position()
	End Method

	Method CommitBootstrap:Int(frame:UInt)
		If Not _prepared Or frame <> _bootstrapFrame Then
			Return False
		End If
		_started = True
		Return True
	End Method

	Rem
	bbdoc: Writes the next fully confirmed input frame without consuming it.
	End Rem
	Method WriteNextFrame:Size_T(buffer:Byte Ptr, capacity:Size_T)
		If Not _started Or Not buffer Or _session.HasPendingRollback() Or Not _session.HasConfirmedFrame() Then
			Return 0
		End If
		If RollbackFrameAfter(_nextFrame, _session.ConfirmedFrame()) Then
			Return 0
		End If
		Local required:Size_T = SPECTATOR_FRAME_OVERHEAD + Size_T(_session.PlayerCount() * 2)
		For Local player:Int = 0 Until _inputs.Length
			If Not _session.GetConfirmedInput(player, _nextFrame, _inputs[player]) Then
				Return 0
			End If
			required :+ _inputs[player].Length()
		Next
		If capacity < required Then
			Return 0
		End If
		Local nextState:SPacketView
		If Not _session.GetSavedState(_nextFrame + 1, nextState) Then
			Return 0
		End If

		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(SPECTATOR_FRAME_MAGIC)
		writer.WriteUInt8(SPECTATOR_WIRE_VERSION)
		writer.WriteUInt8(UInt(_inputs.Length))
		writer.WriteUInt32(_nextFrame)
		writer.WriteUInt32(RollbackHash32(nextState.Data(), nextState.Length()))
		For Local input:SPacketView = EachIn _inputs
			writer.WriteUInt16(UInt(input.Length()))
			writer.WriteBytes(input.Data(), input.Length())
		Next
		If writer.Failed() Then
			Return 0
		End If
		Return writer.Position()
	End Method

	Method CommitFrame:Int(frame:UInt)
		If Not _started Or frame <> _nextFrame Then
			Return False
		End If
		_nextFrame :+ 1
		Return True
	End Method

	Method BootstrapFrame:UInt()
		Return _bootstrapFrame
	End Method

	Method NextFrame:UInt()
		Return _nextFrame
	End Method

	Method BootstrapPacketCapacity:Size_T()
		Return SPECTATOR_BOOTSTRAP_OVERHEAD + _session.MaxStateSize()
	End Method

	Method FramePacketCapacity:Size_T()
		Return SPECTATOR_FRAME_OVERHEAD + Size_T(_session.PlayerCount()) * (2 + _session.MaxInputSize())
	End Method
End Type

Rem
bbdoc: Replays a reliable ordered stream of confirmed rollback input.
about: A spectator never predicts and therefore never rolls back. It begins from
the source's confirmed bootstrap state and advances only on sequential frames.
End Rem
Type TRollbackSpectatorSession
	Private
	Field _simulation:IRollbackSimulation
	Field _playerCount:Int
	Field _maxStateSize:Size_T
	Field _maxInputSize:Size_T
	Field _stateBuffer:Byte Ptr
	Field _inputs:SRollbackInput[]
	Field _running:Int
	Field _failed:Int
	Field _failure:ERollbackSpectatorFailure
	Field _currentFrame:UInt
	Field _framesPlayed:Long

	Method New(simulation:IRollbackSimulation, playerCount:Int, maxStateSize:Size_T, maxInputSize:Size_T)
		_simulation = simulation
		_playerCount = playerCount
		_maxStateSize = maxStateSize
		_maxInputSize = maxInputSize
		_stateBuffer = MemAlloc(maxStateSize)
		_inputs = New SRollbackInput[playerCount]
	End Method

	Method Fail:Int(reason:ERollbackSpectatorFailure)
		_failed = True
		_running = False
		_failure = reason
		Return False
	End Method

	Public
	Function Create:TRollbackSpectatorSession(simulation:IRollbackSimulation, playerCount:Int, maxStateSize:Size_T, maxInputSize:Size_T)
		If Not simulation Or playerCount < 2 Or playerCount > ROLLBACK_SESSION_MAX_PLAYERS Or maxStateSize < 1 Or maxInputSize < 1 Or maxInputSize > 65535 Then
			Return Null
		End If
		Return New TRollbackSpectatorSession(simulation, playerCount, maxStateSize, maxInputSize)
	End Function

	Method Delete()
		If _stateBuffer Then
			MemFree(_stateBuffer)
		End If
		_stateBuffer = Null
	End Method

	Method ReceiveBootstrap:Int(packet:SPacketView)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local magic:UInt
		Local version:UInt
		Local players:UInt
		Local frame:UInt
		Local length:UInt
		Local expectedHash:UInt
		If Not reader.ReadUInt32(magic) Or magic <> SPECTATOR_BOOTSTRAP_MAGIC Then
			Return Fail(ERollbackSpectatorFailure.InvalidBootstrap)
		End If
		If Not reader.ReadUInt8(version) Or version <> SPECTATOR_WIRE_VERSION Or Not reader.ReadUInt8(players) Or Int(players) <> _playerCount Then
			Return Fail(ERollbackSpectatorFailure.InvalidBootstrap)
		End If
		If Not reader.ReadUInt32(frame) Or Not reader.ReadUInt32(length) Or length < 1 Or Size_T(length) > _maxStateSize Or Not reader.ReadUInt32(expectedHash) Or Size_T(length) <> reader.Remaining() Then
			Return Fail(ERollbackSpectatorFailure.InvalidBootstrap)
		End If
		Local state:SPacketView = reader.RemainingView()
		If RollbackHash32(state.Data(), state.Length()) <> expectedHash Then
			Return Fail(ERollbackSpectatorFailure.InvalidBootstrap)
		End If
		If Not _simulation.LoadState(state) Then
			Return Fail(ERollbackSpectatorFailure.StateLoadFailed)
		End If
		_currentFrame = frame
		_framesPlayed = 0
		_failed = False
		_failure = ERollbackSpectatorFailure.None
		_running = True
		Return True
	End Method

	Method ReceiveFrame:Int(packet:SPacketView)
		If Not _running Or _failed Then
			Return False
		End If
		Local reader:SPacketReader = New SPacketReader(packet)
		Local magic:UInt
		Local version:UInt
		Local players:UInt
		Local frame:UInt
		Local expectedHash:UInt
		If Not reader.ReadUInt32(magic) Or magic <> SPECTATOR_FRAME_MAGIC Or Not reader.ReadUInt8(version) Or version <> SPECTATOR_WIRE_VERSION Then
			Return Fail(ERollbackSpectatorFailure.InvalidFrame)
		End If
		If Not reader.ReadUInt8(players) Or Int(players) <> _playerCount Or Not reader.ReadUInt32(frame) Or frame <> _currentFrame Or Not reader.ReadUInt32(expectedHash) Then
			Return Fail(ERollbackSpectatorFailure.InvalidFrame)
		End If

		For Local player:Int = 0 Until _playerCount
			Local length:UInt
			If Not reader.ReadUInt16(length) Or length < 1 Or Size_T(length) > _maxInputSize Or Size_T(length) > reader.Remaining() Then
				Return Fail(ERollbackSpectatorFailure.InvalidFrame)
			End If
			_inputs[player] = New SRollbackInput(frame, player, ERollbackInputStatus.Confirmed, New SPacketView(reader.RemainingView().Data(), Size_T(length)))
			If Not reader.Skip(Size_T(length)) Then
				Return Fail(ERollbackSpectatorFailure.InvalidFrame)
			End If
		Next
		If reader.Remaining() <> 0 Then
			Return Fail(ERollbackSpectatorFailure.InvalidFrame)
		End If
		If Not _simulation.SimulateFrame(frame, _inputs) Then
			Return Fail(ERollbackSpectatorFailure.SimulationFailed)
		End If
		Local stateLength:Size_T = _simulation.SaveState(_stateBuffer, _maxStateSize)
		If stateLength = 0 Or stateLength > _maxStateSize Then
			Return Fail(ERollbackSpectatorFailure.StateSaveFailed)
		End If
		If RollbackHash32(_stateBuffer, stateLength) <> expectedHash Then
			Return Fail(ERollbackSpectatorFailure.StateHashMismatch)
		End If
		_currentFrame :+ 1
		_framesPlayed :+ 1
		Return True
	End Method

	Method IsRunning:Int()
		Return _running
	End Method

	Method Failed:Int()
		Return _failed
	End Method

	Method FailureReason:ERollbackSpectatorFailure()
		Return _failure
	End Method

	Method CurrentFrame:UInt()
		Return _currentFrame
	End Method

	Method FramesPlayed:Long()
		Return _framesPlayed
	End Method
End Type

?
