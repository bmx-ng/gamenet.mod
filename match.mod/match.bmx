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
bbdoc: Backend-neutral multiplayer match lifecycle coordination.
End Rem
Module GameNet.Match

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial authoritative match lifecycle"

Import GameNet.Session
Import BRL.Blitz

Const MATCH_MAX_PLAYERS:Int = 8
Const MATCH_PROTOCOL_VERSION:UInt = 1
Const MATCH_COMMAND_PACKET_SIZE:Size_T = 3
Const MATCH_STATE_PACKET_SIZE:Size_T = 39

Rem
bbdoc: Identifies the current match lifecycle phase.
End Rem
Enum EMatchPhase:Byte
	Waiting
	Countdown
	Running
	Paused
	Finished
	Aborted
End Enum

Rem
bbdoc: Identifies an application-visible lifecycle transition.
End Rem
Enum EMatchEventKind:Byte
	StateChanged
	PlayerConnected
	PlayerDisconnected
	PlayerReadyChanged
	PlayerPauseChanged
	CountdownStarted
	Started
	Paused
	Resumed
	Finished
	Aborted
End Enum

Private

Enum EMatchCommandKind:Byte
	Ready = 1
	Pause = 2
End Enum

Public

Rem
bbdoc: Fixed match protocol and storage configuration.
about: Message types must be distinct application message identifiers. The
configured session is borrowed and remains owned by the application.
End Rem
Struct SMatchLifecycleConfig
	Field playerCount:Int
	Field localPlayer:Int
	Field authorityPlayer:Int
	Field commandMessageType:UInt
	Field stateMessageType:UInt
	Field channel:UInt
	Field eventCapacity:Int

	Method New(playerCount:Int, localPlayer:Int, authorityPlayer:Int = 0, commandMessageType:UInt = 1, stateMessageType:UInt = 2, channel:UInt = 0, eventCapacity:Int = 32)
		Self.playerCount = playerCount
		Self.localPlayer = localPlayer
		Self.authorityPlayer = authorityPlayer
		Self.commandMessageType = commandMessageType
		Self.stateMessageType = stateMessageType
		Self.channel = channel
		Self.eventCapacity = eventCapacity
	End Method
End Struct

Rem
bbdoc: One queued match lifecycle transition.
End Rem
Struct SMatchEvent
	Private
	Field _kind:EMatchEventKind
	Field _phase:EMatchPhase
	Field _player:Int
	Field _value:Int
	Field _round:UInt
	Field _seed:UInt
	Field _startFrame:UInt
	Field _winner:Int
	Field _code:Int

	Method New(kind:EMatchEventKind, phase:EMatchPhase, player:Int, value:Int, round:UInt, seed:UInt, startFrame:UInt, winner:Int, code:Int)
		_kind = kind
		_phase = phase
		_player = player
		_value = value
		_round = round
		_seed = seed
		_startFrame = startFrame
		_winner = winner
		_code = code
	End Method

	Public
	Method New()
	End Method

	Method Kind:EMatchEventKind()
		Return _kind
	End Method

	Method Phase:EMatchPhase()
		Return _phase
	End Method

	Method Player:Int()
		Return _player
	End Method

	Method Value:Int()
		Return _value
	End Method

	Method Round:UInt()
		Return _round
	End Method

	Method Seed:UInt()
		Return _seed
	End Method

	Method StartFrame:UInt()
		Return _startFrame
	End Method

	Method Winner:Int()
		Return _winner
	End Method

	Method Code:Int()
		Return _code
	End Method
End Struct

Rem
bbdoc: Coordinates one fixed-roster multiplayer match above #TNetSession.
about: One configured authority accepts player commands and broadcasts the
canonical lifecycle state. All lifecycle traffic is reliable and ordered.
The application routes matching session messages to #ReceiveAt and reports
session joins and leaves through #PlayerJoined and #PlayerLeft.
End Rem
Type TMatchLifecycle
	Private
	Field _session:TNetSession
	Field _config:SMatchLifecycleConfig
	Field _fullMask:UInt
	Field _phase:EMatchPhase
	Field _revision:UInt
	Field _hasRemoteRevision:Int
	Field _round:UInt
	Field _connectedMask:UInt
	Field _readyMask:UInt
	Field _pauseMask:UInt
	Field _seed:UInt
	Field _startFrame:UInt
	Field _countdownDeadline:UInt
	Field _countdownClockAdjusted:Int
	Field _winner:Int = -1
	Field _finishCode:Int
	Field _peers:SNetPeer[]
	Field _peerBound:Byte[]
	Field _commandBuffer:Byte Ptr
	Field _stateBuffer:Byte Ptr
	Field _events:SMatchEvent[]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _droppedEvents:Int
	Field _rejectedPackets:Int

	Method New(session:TNetSession, config:SMatchLifecycleConfig)
		_session = session
		_config = config
		_fullMask = (1:UInt Shl config.playerCount) - 1
		_connectedMask = 1:UInt Shl config.localPlayer
		_peers = New SNetPeer[config.playerCount]
		_peerBound = New Byte[config.playerCount]
		_commandBuffer = MemAlloc(MATCH_COMMAND_PACKET_SIZE)
		_stateBuffer = MemAlloc(MATCH_STATE_PACKET_SIZE)
		_events = New SMatchEvent[config.eventCapacity]
	End Method

	Method QueueEvent(kind:EMatchEventKind, player:Int = -1, value:Int = 0)
		If _eventCount = _events.Length Then
			_droppedEvents :+ 1
			Return
		End If
		_events[_eventWrite] = New SMatchEvent(kind, _phase, player, value, _round, _seed, _startFrame, _winner, _finishCode)
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
	End Method

	Method QueueMaskChanges(kind:EMatchEventKind, oldMask:UInt, newMask:UInt)
		Local changed:UInt = oldMask ~ newMask
		For Local player:Int = 0 Until _config.playerCount
			Local bit:UInt = 1:UInt Shl player
			If changed & bit Then QueueEvent(kind, player, (newMask & bit) <> 0)
		Next
	End Method

	Method QueuePhaseChange(oldPhase:EMatchPhase)
		If oldPhase = _phase Then Return
		QueueEvent(EMatchEventKind.StateChanged)
		Select _phase
			Case EMatchPhase.Countdown
				QueueEvent(EMatchEventKind.CountdownStarted)
			Case EMatchPhase.Running
				If oldPhase = EMatchPhase.Paused Then
					QueueEvent(EMatchEventKind.Resumed)
				Else
					QueueEvent(EMatchEventKind.Started)
				End If
			Case EMatchPhase.Paused
				QueueEvent(EMatchEventKind.Paused)
			Case EMatchPhase.Finished
				QueueEvent(EMatchEventKind.Finished)
			Case EMatchPhase.Aborted
				QueueEvent(EMatchEventKind.Aborted)
		End Select
	End Method

	Method PlayerForPeer:Int(peer:SNetPeer)
		For Local player:Int = 0 Until _config.playerCount
			If _peerBound[player] And _peers[player].Equals(peer) Then Return player
		Next
		Return -1
	End Method

	Method WriteCommand:Size_T(kind:EMatchCommandKind, value:Int)
		Local writer:SPacketWriter = New SPacketWriter(_commandBuffer, MATCH_COMMAND_PACKET_SIZE)
		writer.WriteUInt8(MATCH_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(kind))
		writer.WriteUInt8(UInt(value <> 0))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method SendCommand:ETransportResult(kind:EMatchCommandKind, value:Int)
		If Not _peerBound[_config.authorityPlayer] Then Return ETransportResult.InvalidPeer
		Local length:Size_T = WriteCommand(kind, value)
		If length = 0 Then Return ETransportResult.Failed
		Return _session.Send(_peers[_config.authorityPlayer], _config.commandMessageType, _config.channel, EDeliveryMode.ReliableOrdered, _commandBuffer, length)
	End Method

	Method WriteState:Size_T(nowMillis:UInt)
		Local writer:SPacketWriter = New SPacketWriter(_stateBuffer, MATCH_STATE_PACKET_SIZE)
		writer.WriteUInt8(MATCH_PROTOCOL_VERSION)
		writer.WriteUInt32(_revision)
		writer.WriteUInt32(_round)
		writer.WriteUInt8(UInt(_phase))
		writer.WriteUInt32(_connectedMask)
		writer.WriteUInt32(_readyMask)
		writer.WriteUInt32(_pauseMask)
		writer.WriteUInt32(_seed)
		writer.WriteUInt32(_startFrame)
		writer.WriteUInt32(CountdownRemaining(nowMillis))
		Local encodedWinner:UInt = 255
		If _winner >= 0 Then encodedWinner = UInt(_winner)
		writer.WriteUInt8(encodedWinner)
		writer.WriteUInt32(UInt(_finishCode))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method BroadcastState:ETransportResult(nowMillis:UInt)
		Local length:Size_T = WriteState(nowMillis)
		If length = 0 Then Return ETransportResult.Failed
		Local result:ETransportResult = ETransportResult.Ok
		For Local player:Int = 0 Until _config.playerCount
			If player = _config.localPlayer Or Not _peerBound[player] Or Not (_connectedMask & (1:UInt Shl player)) Then Continue
			Local sent:ETransportResult = _session.Send(_peers[player], _config.stateMessageType, _config.channel, EDeliveryMode.ReliableOrdered, _stateBuffer, length)
			If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
		Next
		Return result
	End Method

	Method CommitState:ETransportResult(nowMillis:UInt)
		_revision :+ 1
		Return BroadcastState(nowMillis)
	End Method

	Method AlignRemoteCountdown(nowMillis:UInt)
		If IsAuthority() Or _countdownClockAdjusted Or _phase <> EMatchPhase.Countdown Or Not _peerBound[_config.authorityPlayer] Then Return
		Local health:SSessionPeerHealth
		If Not _session.GetPeerHealth(_peers[_config.authorityPlayer], nowMillis, health) Or Not health.HasRoundTrip() Then Return
		Local correction:UInt = health.RoundTripMillis() / 2
		Local remaining:UInt = CountdownRemaining(nowMillis)
		If correction > remaining Then correction = remaining
		_countdownDeadline :- correction
		_countdownClockAdjusted = True
	End Method

	Method ApplyReady:ETransportResult(player:Int, ready:Int, nowMillis:UInt)
		Local oldMask:UInt = _readyMask
		Local bit:UInt = 1:UInt Shl player
		If ready Then _readyMask :| bit Else _readyMask :& ~bit
		If oldMask = _readyMask Then Return ETransportResult.Ok
		QueueMaskChanges(EMatchEventKind.PlayerReadyChanged, oldMask, _readyMask)
		QueueEvent(EMatchEventKind.StateChanged)
		Return CommitState(nowMillis)
	End Method

	Method ApplyPause:ETransportResult(player:Int, paused:Int, nowMillis:UInt)
		If _phase <> EMatchPhase.Running And _phase <> EMatchPhase.Paused Then Return ETransportResult.Failed
		Local oldMask:UInt = _pauseMask
		Local bit:UInt = 1:UInt Shl player
		If paused Then _pauseMask :| bit Else _pauseMask :& ~bit
		If oldMask = _pauseMask Then Return ETransportResult.Ok
		QueueMaskChanges(EMatchEventKind.PlayerPauseChanged, oldMask, _pauseMask)
		Local oldPhase:EMatchPhase = _phase
		If _pauseMask Then _phase = EMatchPhase.Paused Else _phase = EMatchPhase.Running
		QueuePhaseChange(oldPhase)
		If oldPhase = _phase Then QueueEvent(EMatchEventKind.StateChanged)
		Return CommitState(nowMillis)
	End Method

	Method ReceiveCommand:Int(player:Int, packet:SPacketView, nowMillis:UInt)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local version:UInt, kindValue:UInt, value:UInt
		If Not reader.ReadUInt8(version) Or version <> MATCH_PROTOCOL_VERSION Or Not reader.ReadUInt8(kindValue) Or Not reader.ReadUInt8(value) Or value > 1 Or reader.Remaining() <> 0 Then Return False
		Select EMatchCommandKind(kindValue)
			Case EMatchCommandKind.Ready
				If _phase <> EMatchPhase.Waiting And _phase <> EMatchPhase.Finished Then Return False
				ApplyReady(player, value <> 0, nowMillis)
			Case EMatchCommandKind.Pause
				If _phase <> EMatchPhase.Running And _phase <> EMatchPhase.Paused Then Return False
				ApplyPause(player, value <> 0, nowMillis)
			Default
				Return False
		End Select
		Return True
	End Method

	Method ReceiveState:Int(packet:SPacketView, nowMillis:UInt)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local version:UInt, revision:UInt, round:UInt, phaseValue:UInt
		Local connectedMask:UInt, readyMask:UInt, pauseMask:UInt, seed:UInt, startFrame:UInt, countdownRemaining:UInt
		Local winnerValue:UInt, finishCode:UInt
		If Not reader.ReadUInt8(version) Or version <> MATCH_PROTOCOL_VERSION Or Not reader.ReadUInt32(revision) Or Not reader.ReadUInt32(round) Or Not reader.ReadUInt8(phaseValue) ..
			Or Not reader.ReadUInt32(connectedMask) Or Not reader.ReadUInt32(readyMask) Or Not reader.ReadUInt32(pauseMask) Or Not reader.ReadUInt32(seed) Or Not reader.ReadUInt32(startFrame) ..
			Or Not reader.ReadUInt32(countdownRemaining) Or Not reader.ReadUInt8(winnerValue) Or Not reader.ReadUInt32(finishCode) Or reader.Remaining() <> 0 Then Return False
		If phaseValue > UInt(EMatchPhase.Aborted) Or (connectedMask & ~_fullMask) Or (readyMask & ~_fullMask) Or (pauseMask & ~_fullMask) Or (winnerValue <> 255 And winnerValue >= UInt(_config.playerCount)) Then Return False
		If _hasRemoteRevision And Int(revision - _revision) <= 0 Then Return True

		Local oldPhase:EMatchPhase = _phase
		Local oldConnected:UInt = _connectedMask
		Local oldReady:UInt = _readyMask
		Local oldPause:UInt = _pauseMask
		_revision = revision
		_hasRemoteRevision = True
		_round = round
		_phase = EMatchPhase(phaseValue)
		_connectedMask = connectedMask
		_readyMask = readyMask
		_pauseMask = pauseMask
		_seed = seed
		_startFrame = startFrame
		_countdownDeadline = nowMillis + countdownRemaining
		_countdownClockAdjusted = False
		_winner = -1
		If winnerValue <> 255 Then _winner = Int(winnerValue)
		_finishCode = Int(finishCode)
		Local connected:UInt = _connectedMask & ~oldConnected
		For Local player:Int = 0 Until _config.playerCount
			If connected & (1:UInt Shl player) Then QueueEvent(EMatchEventKind.PlayerConnected, player, True)
		Next
		Local disconnected:UInt = oldConnected & ~_connectedMask
		For Local player:Int = 0 Until _config.playerCount
			If disconnected & (1:UInt Shl player) Then QueueEvent(EMatchEventKind.PlayerDisconnected, player, False)
		Next
		QueueMaskChanges(EMatchEventKind.PlayerReadyChanged, oldReady, _readyMask)
		QueueMaskChanges(EMatchEventKind.PlayerPauseChanged, oldPause, _pauseMask)
		QueuePhaseChange(oldPhase)
		If oldPhase = _phase Then QueueEvent(EMatchEventKind.StateChanged)
		Return True
	End Method

	Function ValidConfig:Int(session:TNetSession, config:SMatchLifecycleConfig)
		Return session <> Null And config.playerCount >= 2 And config.playerCount <= MATCH_MAX_PLAYERS ..
			And config.localPlayer >= 0 And config.localPlayer < config.playerCount ..
			And config.authorityPlayer >= 0 And config.authorityPlayer < config.playerCount ..
			And config.commandMessageType <= 65535 And config.stateMessageType <= 65535 ..
			And config.commandMessageType <> config.stateMessageType And config.eventCapacity >= config.playerCount * 2 + 4 ..
			And session.MaxPayloadSize(EDeliveryMode.ReliableOrdered) >= MATCH_STATE_PACKET_SIZE
	End Function

	Public
	Function Create:TMatchLifecycle(session:TNetSession, config:SMatchLifecycleConfig)
		If Not ValidConfig(session, config) Then Return Null
		Return New TMatchLifecycle(session, config)
	End Function

	Method Delete()
		If _commandBuffer Then MemFree(_commandBuffer)
		If _stateBuffer Then MemFree(_stateBuffer)
		_commandBuffer = Null
		_stateBuffer = Null
	End Method

	Rem
	bbdoc: Binds a session peer to a stable match player index.
	End Rem
	Method BindPlayer:Int(player:Int, peer:SNetPeer)
		If player < 0 Or player >= _config.playerCount Or player = _config.localPlayer Or Not peer.IsValid() Then Return False
		Local existing:Int = PlayerForPeer(peer)
		If existing >= 0 And existing <> player Then Return False
		_peers[player] = peer
		_peerBound[player] = True
		Return True
	End Method

	Rem
	bbdoc: Reports a joined player and publishes the roster when called by the authority.
	End Rem
	Method PlayerJoined:ETransportResult(player:Int, peer:SNetPeer, nowMillis:UInt)
		If Not BindPlayer(player, peer) Then Return ETransportResult.InvalidPeer
		If Not IsAuthority() Then Return ETransportResult.Ok
		Local bit:UInt = 1:UInt Shl player
		If _connectedMask & bit Then Return ETransportResult.Ok
		_connectedMask :| bit
		QueueEvent(EMatchEventKind.PlayerConnected, player, True)
		QueueEvent(EMatchEventKind.StateChanged)
		Return CommitState(nowMillis)
	End Method

	Rem
	bbdoc: Reports a departed player and aborts an active canonical match.
	End Rem
	Method PlayerLeft:ETransportResult(player:Int, code:Int, nowMillis:UInt)
		If player < 0 Or player >= _config.playerCount Or player = _config.localPlayer Then Return ETransportResult.InvalidPeer
		_peerBound[player] = False
		Local bit:UInt = 1:UInt Shl player
		If Not (_connectedMask & bit) Then Return ETransportResult.Ok
		Local oldReady:UInt = _readyMask
		Local oldPause:UInt = _pauseMask
		_connectedMask :& ~bit
		_readyMask :& ~bit
		_pauseMask :& ~bit
		_finishCode = code
		QueueEvent(EMatchEventKind.PlayerDisconnected, player, code)
		QueueMaskChanges(EMatchEventKind.PlayerReadyChanged, oldReady, _readyMask)
		QueueMaskChanges(EMatchEventKind.PlayerPauseChanged, oldPause, _pauseMask)
		Local oldPhase:EMatchPhase = _phase
		If _phase = EMatchPhase.Countdown Or _phase = EMatchPhase.Running Or _phase = EMatchPhase.Paused Then _phase = EMatchPhase.Aborted
		QueuePhaseChange(oldPhase)
		If oldPhase = _phase Then QueueEvent(EMatchEventKind.StateChanged)
		If IsAuthority() Then Return CommitState(nowMillis)
		Return ETransportResult.Ok
	End Method

	Rem
	bbdoc: Sends the authority's complete current state to every connected peer.
	End Rem
	Method Synchronize:ETransportResult(nowMillis:UInt)
		If Not IsAuthority() Then Return ETransportResult.Failed
		Return CommitState(nowMillis)
	End Method

	Rem
	bbdoc: Changes this player's ready state during waiting or after a finish.
	End Rem
	Method SetLocalReady:ETransportResult(ready:Int, nowMillis:UInt)
		If _phase <> EMatchPhase.Waiting And _phase <> EMatchPhase.Finished Then Return ETransportResult.Failed
		If IsAuthority() Then Return ApplyReady(_config.localPlayer, ready, nowMillis)
		Return SendCommand(EMatchCommandKind.Ready, ready)
	End Method

	Rem
	bbdoc: Begins a new authoritative round once every configured player is connected and ready.
	End Rem
	Method BeginMatch:ETransportResult(seed:UInt, startFrame:UInt, countdownMillis:UInt, nowMillis:UInt)
		If Not IsAuthority() Or (_phase <> EMatchPhase.Waiting And _phase <> EMatchPhase.Finished) Then Return ETransportResult.Failed
		If _connectedMask <> _fullMask Or _readyMask <> _fullMask Then Return ETransportResult.Failed
		Local oldReady:UInt = _readyMask
		Local oldPhase:EMatchPhase = _phase
		_round :+ 1
		_seed = seed
		_startFrame = startFrame
		_readyMask = 0
		_pauseMask = 0
		_winner = -1
		_finishCode = 0
		_countdownDeadline = nowMillis + countdownMillis
		_countdownClockAdjusted = True
		If countdownMillis Then _phase = EMatchPhase.Countdown Else _phase = EMatchPhase.Running
		QueueMaskChanges(EMatchEventKind.PlayerReadyChanged, oldReady, _readyMask)
		QueuePhaseChange(oldPhase)
		Return CommitState(nowMillis)
	End Method

	Rem
	bbdoc: Requests or clears a pause for this player during active play.
	End Rem
	Method SetLocalPaused:ETransportResult(paused:Int, nowMillis:UInt)
		If _phase <> EMatchPhase.Running And _phase <> EMatchPhase.Paused Then Return ETransportResult.Failed
		If IsAuthority() Then Return ApplyPause(_config.localPlayer, paused, nowMillis)
		Return SendCommand(EMatchCommandKind.Pause, paused)
	End Method

	Rem
	bbdoc: Completes the canonical match with an optional winner and application result code.
	End Rem
	Method Finish:ETransportResult(winner:Int, code:Int, nowMillis:UInt)
		If Not IsAuthority() Or (_phase <> EMatchPhase.Running And _phase <> EMatchPhase.Paused) Or winner < -1 Or winner >= _config.playerCount Then Return ETransportResult.Failed
		Local oldReady:UInt = _readyMask
		Local oldPause:UInt = _pauseMask
		Local oldPhase:EMatchPhase = _phase
		_phase = EMatchPhase.Finished
		_readyMask = 0
		_pauseMask = 0
		_winner = winner
		_finishCode = code
		QueueMaskChanges(EMatchEventKind.PlayerReadyChanged, oldReady, _readyMask)
		QueueMaskChanges(EMatchEventKind.PlayerPauseChanged, oldPause, _pauseMask)
		QueuePhaseChange(oldPhase)
		Return CommitState(nowMillis)
	End Method

	Rem
	bbdoc: Advances countdown timing and publishes the authoritative start transition.
	End Rem
	Method UpdateAt:ETransportResult(nowMillis:UInt)
		AlignRemoteCountdown(nowMillis)
		If _phase <> EMatchPhase.Countdown Or Int(nowMillis - _countdownDeadline) < 0 Then Return ETransportResult.Ok
		Local oldPhase:EMatchPhase = _phase
		_phase = EMatchPhase.Running
		QueuePhaseChange(oldPhase)
		If IsAuthority() Then Return CommitState(nowMillis)
		Return ETransportResult.Ok
	End Method

	Method Update:ETransportResult()
		Return UpdateAt(UInt(MilliSecs()))
	End Method

	Rem
	bbdoc: Consumes one lifecycle message from the session.
	returns: True for a valid or stale lifecycle packet, otherwise False.
	End Rem
	Method ReceiveAt:Int(peer:SNetPeer, messageType:UInt, packet:SPacketView, nowMillis:UInt)
		Local player:Int = PlayerForPeer(peer)
		If player < 0 Then
			_rejectedPackets :+ 1
			Return False
		End If
		Local accepted:Int
		If messageType = _config.commandMessageType And IsAuthority() Then
			accepted = ReceiveCommand(player, packet, nowMillis)
		Else If messageType = _config.stateMessageType And Not IsAuthority() And player = _config.authorityPlayer Then
			accepted = ReceiveState(packet, nowMillis)
		End If
		If Not accepted Then _rejectedPackets :+ 1
		Return accepted
	End Method

	Method Receive:Int(peer:SNetPeer, messageType:UInt, packet:SPacketView)
		Return ReceiveAt(peer, messageType, packet, UInt(MilliSecs()))
	End Method

	Method Poll:Int(event:SMatchEvent Var)
		If _eventCount = 0 Then
			event = New SMatchEvent
			Return False
		End If
		event = _events[_eventRead]
		_eventRead = (_eventRead + 1) Mod _events.Length
		_eventCount :- 1
		Return True
	End Method

	Method IsAuthority:Int()
		Return _config.localPlayer = _config.authorityPlayer
	End Method

	Method Phase:EMatchPhase()
		Return _phase
	End Method

	Method Round:UInt()
		Return _round
	End Method

	Method ConnectedMask:UInt()
		Return _connectedMask
	End Method

	Method ReadyMask:UInt()
		Return _readyMask
	End Method

	Method PauseMask:UInt()
		Return _pauseMask
	End Method

	Method AllConnected:Int()
		Return _connectedMask = _fullMask
	End Method

	Method AllReady:Int()
		Return _readyMask = _fullMask
	End Method

	Method PlayerConnected:Int(player:Int)
		Return player >= 0 And player < _config.playerCount And (_connectedMask & (1:UInt Shl player)) <> 0
	End Method

	Method PlayerReady:Int(player:Int)
		Return player >= 0 And player < _config.playerCount And (_readyMask & (1:UInt Shl player)) <> 0
	End Method

	Method PlayerPaused:Int(player:Int)
		Return player >= 0 And player < _config.playerCount And (_pauseMask & (1:UInt Shl player)) <> 0
	End Method

	Method Seed:UInt()
		Return _seed
	End Method

	Method StartFrame:UInt()
		Return _startFrame
	End Method

	Method Winner:Int()
		Return _winner
	End Method

	Method FinishCode:Int()
		Return _finishCode
	End Method

	Method CountdownRemaining:UInt(nowMillis:UInt)
		If _phase <> EMatchPhase.Countdown Then Return 0
		Local remaining:Int = Int(_countdownDeadline - nowMillis)
		If remaining <= 0 Then Return 0
		Return UInt(remaining)
	End Method

	Method DroppedEvents:Int()
		Return _droppedEvents
	End Method

	Method RejectedPackets:Int()
		Return _rejectedPackets
	End Method
End Type

?
