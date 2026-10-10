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
bbdoc: Backend-neutral application suspension and recovery policy.
End Rem
Module GameNet.Lifecycle

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial mobile lifecycle policy"

Import BRL.Blitz

Rem
bbdoc: Identifies an application lifecycle transition.
End Rem
Enum EAppLifecycleEventKind:Byte
	None
	Suspended
	Resumed
	Terminating
End Enum

Rem
bbdoc: Recommends how a network game should recover after returning to the foreground.
End Rem
Enum EAppResumeAction:Byte
	Continue
	Resynchronise
	Reconnect
	Leave
End Enum

Rem
bbdoc: Time-based recovery policy for a suspended application.
about: A zero threshold disables that escalation. Thresholds must be ordered
from the shortest enabled action to the longest.
End Rem
Struct SAppLifecycleConfig
	Field resynchroniseAfterMillis:UInt
	Field reconnectAfterMillis:UInt
	Field leaveAfterMillis:UInt
	Field eventCapacity:Int

	Method New(resynchroniseAfterMillis:UInt = 250, reconnectAfterMillis:UInt = 30000, leaveAfterMillis:UInt = 120000, eventCapacity:Int = 4)
		Self.resynchroniseAfterMillis = resynchroniseAfterMillis
		Self.reconnectAfterMillis = reconnectAfterMillis
		Self.leaveAfterMillis = leaveAfterMillis
		Self.eventCapacity = eventCapacity
	End Method
End Struct

Rem
bbdoc: One queued application lifecycle transition.
End Rem
Struct SAppLifecycleEvent
	Private
	Field _kind:EAppLifecycleEventKind
	Field _action:EAppResumeAction
	Field _suspendedMillis:UInt

	Method New(kind:EAppLifecycleEventKind, action:EAppResumeAction, suspendedMillis:UInt)
		_kind = kind
		_action = action
		_suspendedMillis = suspendedMillis
	End Method

	Public
	Method New()
	End Method

	Method Kind:EAppLifecycleEventKind()
		Return _kind
	End Method

	Method Action:EAppResumeAction()
		Return _action
	End Method

	Method SuspendedMillis:UInt()
		Return _suspendedMillis
	End Method
End Struct

Rem
bbdoc: Converts platform foreground/background notifications into bounded events and recovery decisions.
about: This type deliberately has no SDL, Apple, Android, or transport dependency.
Feed it notifications from the application's platform layer, suspend the
TNetSession at the same time, and apply the returned recovery action after
the session resumes and queued disconnect events have been processed.
End Rem
Type TAppLifecycle
	Private
	Field _config:SAppLifecycleConfig
	Field _events:SAppLifecycleEvent[]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _suspended:Int
	Field _suspendedAt:UInt
	Field _droppedEvents:Int

	Method New(config:SAppLifecycleConfig)
		_config = config
		_events = New SAppLifecycleEvent[config.eventCapacity]
	End Method

	Method Queue(event:SAppLifecycleEvent)
		If _eventCount = _events.Length Then
			_droppedEvents :+ 1
			Return
		End If
		_events[_eventWrite] = event
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
	End Method

	Function ThresholdsValid:Int(config:SAppLifecycleConfig)
		If config.eventCapacity < 2 Then Return False
		If config.resynchroniseAfterMillis And config.reconnectAfterMillis And config.resynchroniseAfterMillis > config.reconnectAfterMillis Then Return False
		If config.reconnectAfterMillis And config.leaveAfterMillis And config.reconnectAfterMillis > config.leaveAfterMillis Then Return False
		If config.resynchroniseAfterMillis And config.leaveAfterMillis And config.resynchroniseAfterMillis > config.leaveAfterMillis Then Return False
		Return True
	End Function

	Public
	Function Create:TAppLifecycle(config:SAppLifecycleConfig)
		If Not ThresholdsValid(config) Then Return Null
		Return New TAppLifecycle(config)
	End Function

	Function Create:TAppLifecycle()
		Return Create(New SAppLifecycleConfig)
	End Function

	Rem
	bbdoc: Records the first transition into the background.
	End Rem
	Method SuspendAt:Int(nowMillis:UInt)
		If _suspended Then Return False
		_suspended = True
		_suspendedAt = nowMillis
		Queue(New SAppLifecycleEvent(EAppLifecycleEventKind.Suspended, EAppResumeAction.Continue, 0))
		Return True
	End Method

	Method Suspend:Int()
		Return SuspendAt(UInt(MilliSecs()))
	End Method

	Rem
	bbdoc: Records a foreground transition and returns its recommended recovery action.
	param connected: False escalates Continue or Resynchronise to Reconnect.
	End Rem
	Method ResumeAt:EAppResumeAction(nowMillis:UInt, connected:Int = True)
		If Not _suspended Then Return EAppResumeAction.Continue
		Local elapsed:UInt = nowMillis - _suspendedAt
		Local action:EAppResumeAction = EAppResumeAction.Continue
		If _config.resynchroniseAfterMillis And elapsed >= _config.resynchroniseAfterMillis Then action = EAppResumeAction.Resynchronise
		If _config.reconnectAfterMillis And elapsed >= _config.reconnectAfterMillis Then action = EAppResumeAction.Reconnect
		If _config.leaveAfterMillis And elapsed >= _config.leaveAfterMillis Then action = EAppResumeAction.Leave
		If Not connected And action < EAppResumeAction.Reconnect Then action = EAppResumeAction.Reconnect
		_suspended = False
		Queue(New SAppLifecycleEvent(EAppLifecycleEventKind.Resumed, action, elapsed))
		Return action
	End Method

	Method Resume:EAppResumeAction(connected:Int = True)
		Return ResumeAt(UInt(MilliSecs()), connected)
	End Method

	Rem
	bbdoc: Records a terminal lifecycle notification and recommends leaving the match.
	End Rem
	Method Terminate()
		_suspended = False
		Queue(New SAppLifecycleEvent(EAppLifecycleEventKind.Terminating, EAppResumeAction.Leave, 0))
	End Method

	Method Poll:Int(event:SAppLifecycleEvent Var)
		If _eventCount = 0 Then
			event = New SAppLifecycleEvent
			Return False
		End If
		event = _events[_eventRead]
		_eventRead = (_eventRead + 1) Mod _events.Length
		_eventCount :- 1
		Return True
	End Method

	Method IsSuspended:Int()
		Return _suspended
	End Method

	Method DroppedEvents:Int()
		Return _droppedEvents
	End Method
End Type

?
