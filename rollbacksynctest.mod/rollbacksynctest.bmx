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
bbdoc: Automatic determinism verification for rollback simulations.
End Rem
Module GameNet.RollbackSyncTest

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"
ModuleInfo "History: 0.1 Initial rollback determinism test harness"

Import GameNet.RollbackSession
Import BRL.Blitz

Rem
bbdoc: Reason a rollback determinism test stopped.
End Rem
Enum ERollbackSyncTestFailure:Byte
	None
	SaveInitialStateFailed
	FirstSimulationFailed
	SaveFirstResultFailed
	LoadInitialStateFailed
	SecondSimulationFailed
	SaveSecondResultFailed
	StateLengthMismatch
	StateContentMismatch
	RestoreResultFailed
End Enum

Rem
bbdoc: Runs every supplied frame twice from the same state and compares results.
about: Successful frames leave the simulation in the state produced by the
first execution. All storage is allocated by #Create, and #Step performs no
managed allocation. Presentation effects should remain outside the simulation,
as they are for normal rollback re-simulation.
End Rem
Type TRollbackSyncTest
	Private
	Field _simulation:IRollbackSimulation
	Field _capacity:Size_T
	Field _initialState:Byte Ptr
	Field _firstState:Byte Ptr
	Field _secondState:Byte Ptr
	Field _failed:Int
	Field _failure:ERollbackSyncTestFailure
	Field _failureFrame:UInt
	Field _mismatchOffset:Size_T
	Field _testedFrames:Long

	Method New(simulation:IRollbackSimulation, capacity:Size_T)
		_simulation = simulation
		_capacity = capacity
		_initialState = MemAlloc(capacity)
		_firstState = MemAlloc(capacity)
		_secondState = MemAlloc(capacity)
	End Method

	Method Fail:Int(reason:ERollbackSyncTestFailure, frame:UInt, mismatchOffset:Size_T = 0)
		_failed = True
		_failure = reason
		_failureFrame = frame
		_mismatchOffset = mismatchOffset
		Return False
	End Method

	Method RestoreFirst:Int(length:Size_T, frame:UInt)
		If Not _simulation.LoadState(New SPacketView(_firstState, length)) Then
			Return Fail(ERollbackSyncTestFailure.RestoreResultFailed, frame)
		End If
		Return True
	End Method

	Public
	Function Create:TRollbackSyncTest(simulation:IRollbackSimulation, maxStateSize:Size_T)
		If Not simulation Or maxStateSize < 1 Then
			Return Null
		End If
		Return New TRollbackSyncTest(simulation, maxStateSize)
	End Function

	Method Delete()
		If _initialState Then
			MemFree(_initialState)
		End If
		If _firstState Then
			MemFree(_firstState)
		End If
		If _secondState Then
			MemFree(_secondState)
		End If
		_initialState = Null
		_firstState = Null
		_secondState = Null
	End Method

	Rem
	bbdoc: Executes @frame twice from identical state and verifies byte-identical results.
	End Rem
	Method Step:Int(frame:UInt, inputs:SRollbackInput[])
		If _failed Then
			Return False
		End If
		Local initialLength:Size_T = _simulation.SaveState(_initialState, _capacity)
		If initialLength = 0 Or initialLength > _capacity Then
			Return Fail(ERollbackSyncTestFailure.SaveInitialStateFailed, frame)
		End If
		If Not _simulation.SimulateFrame(frame, inputs) Then
			Return Fail(ERollbackSyncTestFailure.FirstSimulationFailed, frame)
		End If
		Local firstLength:Size_T = _simulation.SaveState(_firstState, _capacity)
		If firstLength = 0 Or firstLength > _capacity Then
			Return Fail(ERollbackSyncTestFailure.SaveFirstResultFailed, frame)
		End If
		If Not _simulation.LoadState(New SPacketView(_initialState, initialLength)) Then
			Return Fail(ERollbackSyncTestFailure.LoadInitialStateFailed, frame)
		End If
		If Not _simulation.SimulateFrame(frame, inputs) Then
			If Not RestoreFirst(firstLength, frame) Then
				Return False
			End If
			Return Fail(ERollbackSyncTestFailure.SecondSimulationFailed, frame)
		End If
		Local secondLength:Size_T = _simulation.SaveState(_secondState, _capacity)
		If secondLength = 0 Or secondLength > _capacity Then
			If Not RestoreFirst(firstLength, frame) Then
				Return False
			End If
			Return Fail(ERollbackSyncTestFailure.SaveSecondResultFailed, frame)
		End If

		Local mismatch:ERollbackSyncTestFailure
		Local mismatchOffset:Size_T
		If firstLength <> secondLength Then
			mismatch = ERollbackSyncTestFailure.StateLengthMismatch
			mismatchOffset = Min(firstLength, secondLength)
		Else
			For Local index:Size_T = 0 Until firstLength
				If _firstState[index] <> _secondState[index] Then
					mismatch = ERollbackSyncTestFailure.StateContentMismatch
					mismatchOffset = index
					Exit
				End If
			Next
		End If

		If Not RestoreFirst(firstLength, frame) Then
			Return False
		End If
		If mismatch <> ERollbackSyncTestFailure.None Then
			Return Fail(mismatch, frame, mismatchOffset)
		End If
		_testedFrames :+ 1
		Return True
	End Method

	Method Failed:Int()
		Return _failed
	End Method

	Method FailureReason:ERollbackSyncTestFailure()
		Return _failure
	End Method

	Method FailureFrame:UInt()
		Return _failureFrame
	End Method

	Method MismatchOffset:Size_T()
		Return _mismatchOffset
	End Method

	Method TestedFrames:Long()
		Return _testedFrames
	End Method
End Type

?
