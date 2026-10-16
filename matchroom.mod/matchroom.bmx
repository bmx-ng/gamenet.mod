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
bbdoc: Backend-neutral pre-match room and rematch coordination.
End Rem
Module GameNet.MatchRoom

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial authoritative staging-room protocol"

Import GameNet.Session
Import BRL.Blitz

Const MATCH_ROOM_MAX_PLAYERS:Int = 16
Const MATCH_ROOM_PROTOCOL_VERSION:UInt = 1
Const MATCH_ROOM_COMMAND_PACKET_SIZE:Size_T = 3
Const MATCH_ROOM_STATE_HEADER_SIZE:Size_T = 38

Rem
bbdoc: Current stage of a match room.
End Rem
Enum EMatchRoomPhase:Byte
	Staging
	Playing
	Results
	Closed
End Enum

Rem
bbdoc: Application-visible room transition.
End Rem
Enum EMatchRoomEventKind:Byte
	StateChanged
	MemberJoined
	MemberLeft
	ReadyChanged
	ConfigurationChanged
	MatchStarted
	MatchFinished
	MemberReturned
	StagingOpened
	AuthorityLeft
End Enum

Private

Enum EMatchRoomCommand:Byte
	Synchronize = 1
	Ready
	ReturnToRoom
End Enum

Public

Rem
bbdoc: Fixed storage and message identifiers for one room.
about: CommandMessageType and StateMessageType must be distinct identifiers
reserved by the application. Configuration is an opaque game-defined byte
sequence carried in each authoritative room snapshot.
End Rem
Struct SMatchRoomConfig
	Field maxPlayers:Int
	Field commandMessageType:UInt
	Field stateMessageType:UInt
	Field channel:UInt
	Field maxConfigurationBytes:Int
	Field eventCapacity:Int

	Method New(maxPlayers:Int = 2, commandMessageType:UInt = 65000, stateMessageType:UInt = 65001, channel:UInt = 0, maxConfigurationBytes:Int = 256, eventCapacity:Int = 64)
		Self.maxPlayers = maxPlayers
		Self.commandMessageType = commandMessageType
		Self.stateMessageType = stateMessageType
		Self.channel = channel
		Self.maxConfigurationBytes = maxConfigurationBytes
		Self.eventCapacity = eventCapacity
	End Method
End Struct

Rem
bbdoc: One queued room transition.
End Rem
Struct SMatchRoomEvent
	Private
	Field _kind:EMatchRoomEventKind
	Field _phase:EMatchRoomPhase
	Field _player:Int
	Field _value:Int
	Field _round:UInt
	Field _seed:ULong
	Field _revision:UInt

	Method New(kind:EMatchRoomEventKind, phase:EMatchRoomPhase, player:Int, value:Int, round:UInt, seed:ULong, revision:UInt)
		_kind = kind
		_phase = phase
		_player = player
		_value = value
		_round = round
		_seed = seed
		_revision = revision
	End Method

	Public
	Method New()
	End Method

	Method Kind:EMatchRoomEventKind()
		Return _kind
	End Method

	Method Phase:EMatchRoomPhase()
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

	Method Seed:ULong()
		Return _seed
	End Method

	Method Revision:UInt()
		Return _revision
	End Method
End Struct

Rem
bbdoc: Coordinates a dynamic staging room above a #TNetSession.
about: Slot zero is the authoritative host. The host assigns stable slots to
joined peers, validates commands, and broadcasts complete room snapshots.
Provider discovery and invitations remain the responsibility of
GameNet.Online; gameplay messages remain the responsibility of the game.
End Rem
Type TMatchRoom
	Private
	Field _session:TNetSession
	Field _config:SMatchRoomConfig
	Field _authority:Int
	Field _authorityPeer:SNetPeer
	Field _authorityBound:Int
	Field _localPlayer:Int = -1
	Field _phase:EMatchRoomPhase = EMatchRoomPhase.Staging
	Field _revision:UInt
	Field _hasRemoteRevision:Int
	Field _round:UInt
	Field _seed:ULong
	Field _presentMask:UInt
	Field _readyMask:UInt
	Field _inRoomMask:UInt
	Field _peers:SNetPeer[]
	Field _peerBound:Byte[]
	Field _configuration:Byte[]
	Field _configurationLength:Int
	Field _configurationRevision:UInt
	Field _commandBuffer:Byte Ptr
	Field _stateBuffer:Byte Ptr
	Field _stateCapacity:Size_T
	Field _events:SMatchRoomEvent[]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _droppedEvents:Int
	Field _rejectedPackets:Int

	Method New(session:TNetSession, config:SMatchRoomConfig, authority:Int, authorityPeer:SNetPeer)
		_session = session
		_config = config
		_authority = authority
		_authorityPeer = authorityPeer
		_authorityBound = authorityPeer.IsValid()
		_peers = New SNetPeer[config.maxPlayers]
		_peerBound = New Byte[config.maxPlayers]
		_configuration = New Byte[config.maxConfigurationBytes]
		_commandBuffer = MemAlloc(MATCH_ROOM_COMMAND_PACKET_SIZE)
		_stateCapacity = MATCH_ROOM_STATE_HEADER_SIZE + Size_T(config.maxConfigurationBytes)
		_stateBuffer = MemAlloc(_stateCapacity)
		_events = New SMatchRoomEvent[config.eventCapacity]
		If authority Then
			_localPlayer = 0
			_presentMask = 1
			_inRoomMask = 1
		End If
	End Method

	Function ValidConfig:Int(session:TNetSession, config:SMatchRoomConfig)
		Return session <> Null And config.maxPlayers >= 2 And config.maxPlayers <= MATCH_ROOM_MAX_PLAYERS ..
			And config.commandMessageType <= 65535 And config.stateMessageType <= 65535 ..
			And config.commandMessageType <> config.stateMessageType And config.maxConfigurationBytes >= 0 And config.maxConfigurationBytes <= 65535 ..
			And config.eventCapacity >= config.maxPlayers * 3 ..
			And session.MaxPayloadSize(EDeliveryMode.ReliableOrdered) >= MATCH_ROOM_STATE_HEADER_SIZE + Size_T(config.maxConfigurationBytes)
	End Function

	Method FullMask:UInt()
		Return (1:UInt Shl _config.maxPlayers) - 1
	End Method

	Method Queue(kind:EMatchRoomEventKind, player:Int = -1, value:Int = 0)
		If _eventCount = _events.Length Then
			_droppedEvents :+ 1
			Return
		End If
		_events[_eventWrite] = New SMatchRoomEvent(kind, _phase, player, value, _round, _seed, _revision)
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
	End Method

	Method QueueMaskChanges(kind:EMatchRoomEventKind, oldMask:UInt, newMask:UInt)
		Local changed:UInt = oldMask ~ newMask
		For Local player:Int = 0 Until _config.maxPlayers
			Local bit:UInt = 1:UInt Shl player
			If changed & bit Then Queue(kind, player, (newMask & bit) <> 0)
		Next
	End Method

	Method QueuePresenceChanges(oldMask:UInt, newMask:UInt)
		Local joined:UInt = newMask & ~oldMask
		Local left:UInt = oldMask & ~newMask
		For Local player:Int = 0 Until _config.maxPlayers
			Local bit:UInt = 1:UInt Shl player
			If joined & bit Then Queue(EMatchRoomEventKind.MemberJoined, player, True)
			If left & bit Then Queue(EMatchRoomEventKind.MemberLeft, player, False)
		Next
	End Method

	Method PlayerForPeer:Int(peer:SNetPeer)
		For Local player:Int = 1 Until _config.maxPlayers
			If _peerBound[player] And _peers[player].Equals(peer) Then Return player
		Next
		Return -1
	End Method

	Method FreePlayer:Int()
		For Local player:Int = 1 Until _config.maxPlayers
			If Not (_presentMask & (1:UInt Shl player)) Then Return player
		Next
		Return -1
	End Method

	Method WriteCommand:Size_T(kind:EMatchRoomCommand, value:Int = 0)
		Local writer:SPacketWriter = New SPacketWriter(_commandBuffer, MATCH_ROOM_COMMAND_PACKET_SIZE)
		writer.WriteUInt8(MATCH_ROOM_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(kind))
		writer.WriteUInt8(UInt(value <> 0))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method SendCommand:ETransportResult(kind:EMatchRoomCommand, value:Int = 0)
		If Not _authorityBound Then Return ETransportResult.InvalidPeer
		Local length:Size_T = WriteCommand(kind, value)
		If length = 0 Then Return ETransportResult.Failed
		Return _session.Send(_authorityPeer, _config.commandMessageType, _config.channel, EDeliveryMode.ReliableOrdered, _commandBuffer, length)
	End Method

	Method WriteState:Size_T(assignedPlayer:Int)
		Local writer:SPacketWriter = New SPacketWriter(_stateBuffer, _stateCapacity)
		writer.WriteUInt8(MATCH_ROOM_PROTOCOL_VERSION)
		writer.WriteUInt32(_revision)
		writer.WriteUInt8(UInt(_phase))
		writer.WriteUInt8(UInt(_config.maxPlayers))
		writer.WriteUInt8(UInt(assignedPlayer))
		writer.WriteUInt32(_round)
		writer.WriteUInt64(_seed)
		writer.WriteUInt32(_presentMask)
		writer.WriteUInt32(_readyMask)
		writer.WriteUInt32(_inRoomMask)
		writer.WriteUInt32(_configurationRevision)
		writer.WriteUInt16(UInt(_configurationLength))
		If _configurationLength Then writer.WriteBytes(Byte Ptr(_configuration), Size_T(_configurationLength))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method SendStateTo:ETransportResult(player:Int)
		If player <= 0 Or player >= _config.maxPlayers Or Not _peerBound[player] Then Return ETransportResult.InvalidPeer
		Local length:Size_T = WriteState(player)
		If length = 0 Then Return ETransportResult.Failed
		Return _session.Send(_peers[player], _config.stateMessageType, _config.channel, EDeliveryMode.ReliableOrdered, _stateBuffer, length)
	End Method

	Method BroadcastState:ETransportResult()
		Local result:ETransportResult = ETransportResult.Ok
		For Local player:Int = 1 Until _config.maxPlayers
			If Not (_presentMask & (1:UInt Shl player)) Or Not _peerBound[player] Then Continue
			Local sent:ETransportResult = SendStateTo(player)
			If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
		Next
		Return result
	End Method

	Method CommitState:ETransportResult()
		_revision :+ 1
		Queue(EMatchRoomEventKind.StateChanged)
		Return BroadcastState()
	End Method

	Method OpenStaging()
		Local oldPhase:EMatchRoomPhase = _phase
		Local oldReady:UInt = _readyMask
		Local oldInRoom:UInt = _inRoomMask
		_phase = EMatchRoomPhase.Staging
		_readyMask = 0
		_inRoomMask = _presentMask
		QueueMaskChanges(EMatchRoomEventKind.ReadyChanged, oldReady, _readyMask)
		QueueMaskChanges(EMatchRoomEventKind.MemberReturned, oldInRoom, _inRoomMask)
		If oldPhase <> _phase Then Queue(EMatchRoomEventKind.StagingOpened)
	End Method

	Method ApplyReady:ETransportResult(player:Int, ready:Int)
		If _phase <> EMatchRoomPhase.Staging Or Not (_presentMask & (1:UInt Shl player)) Or Not (_inRoomMask & (1:UInt Shl player)) Then Return ETransportResult.Failed
		Local oldReady:UInt = _readyMask
		Local bit:UInt = 1:UInt Shl player
		If ready Then _readyMask :| bit Else _readyMask :& ~bit
		If oldReady = _readyMask Then Return ETransportResult.Ok
		QueueMaskChanges(EMatchRoomEventKind.ReadyChanged, oldReady, _readyMask)
		Return CommitState()
	End Method

	Method ApplyReturn:ETransportResult(player:Int)
		If Not (_presentMask & (1:UInt Shl player)) Then Return ETransportResult.Failed
		If _phase = EMatchRoomPhase.Playing Then
			OpenStaging()
			Return CommitState()
		End If
		If _phase <> EMatchRoomPhase.Results Then Return ETransportResult.Failed
		Local bit:UInt = 1:UInt Shl player
		If _inRoomMask & bit Then Return ETransportResult.Ok
		_inRoomMask :| bit
		Queue(EMatchRoomEventKind.MemberReturned, player, True)
		If _inRoomMask = _presentMask Then OpenStaging()
		Return CommitState()
	End Method

	Method ReceiveCommand:Int(player:Int, packet:SPacketView)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local version:UInt, kindValue:UInt, value:UInt
		If Not reader.ReadUInt8(version) Or version <> MATCH_ROOM_PROTOCOL_VERSION Or Not reader.ReadUInt8(kindValue) Or Not reader.ReadUInt8(value) Or value > 1 Or reader.Remaining() <> 0 Then Return False
		Select EMatchRoomCommand(kindValue)
			Case EMatchRoomCommand.Synchronize
				Return SendStateTo(player) = ETransportResult.Ok
			Case EMatchRoomCommand.Ready
				Return ApplyReady(player, Int(value)) = ETransportResult.Ok
			Case EMatchRoomCommand.ReturnToRoom
				Return ApplyReturn(player) = ETransportResult.Ok
		End Select
		Return False
	End Method

	Method ReceiveState:Int(packet:SPacketView)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local version:UInt, revision:UInt, phaseValue:UInt, maxPlayers:UInt, assignedPlayer:UInt
		Local round:UInt, seed:ULong, presentMask:UInt, readyMask:UInt, inRoomMask:UInt, configurationRevision:UInt, configurationLength:UInt
		If Not reader.ReadUInt8(version) Or version <> MATCH_ROOM_PROTOCOL_VERSION Or Not reader.ReadUInt32(revision) Or Not reader.ReadUInt8(phaseValue) ..
			Or Not reader.ReadUInt8(maxPlayers) Or Not reader.ReadUInt8(assignedPlayer) Or Not reader.ReadUInt32(round) Or Not reader.ReadUInt64(seed) ..
			Or Not reader.ReadUInt32(presentMask) Or Not reader.ReadUInt32(readyMask) Or Not reader.ReadUInt32(inRoomMask) ..
			Or Not reader.ReadUInt32(configurationRevision) Or Not reader.ReadUInt16(configurationLength) Then Return False
		If phaseValue > UInt(EMatchRoomPhase.Closed) Or maxPlayers <> UInt(_config.maxPlayers) Or assignedPlayer >= maxPlayers ..
			Or configurationLength > UInt(_config.maxConfigurationBytes) Or reader.Remaining() <> Size_T(configurationLength) Then Return False
		Local validMask:UInt = FullMask()
		If (presentMask & ~validMask) Or (readyMask & ~presentMask) Or (inRoomMask & ~presentMask) Or Not (presentMask & 1) Or Not (presentMask & (1:UInt Shl assignedPlayer)) Then Return False
		If _localPlayer >= 0 And assignedPlayer <> UInt(_localPlayer) Then Return False
		If _hasRemoteRevision And Int(revision - _revision) <= 0 Then Return True

		Local decodedConfiguration:Byte[] = New Byte[Int(configurationLength)]
		If configurationLength And Not reader.ReadBytes(Byte Ptr(decodedConfiguration), Size_T(configurationLength)) Then Return False
		Local oldPhase:EMatchRoomPhase = _phase
		Local oldPresent:UInt = _presentMask
		Local oldReady:UInt = _readyMask
		Local oldInRoom:UInt = _inRoomMask
		Local oldConfigurationRevision:UInt = _configurationRevision
		_revision = revision
		_hasRemoteRevision = True
		_localPlayer = Int(assignedPlayer)
		_phase = EMatchRoomPhase(phaseValue)
		_round = round
		_seed = seed
		_presentMask = presentMask
		_readyMask = readyMask
		_inRoomMask = inRoomMask
		_configurationRevision = configurationRevision
		_configurationLength = Int(configurationLength)
		If _configurationLength Then MemCopy(Byte Ptr(_configuration), Byte Ptr(decodedConfiguration), Size_T(_configurationLength))
		QueuePresenceChanges(oldPresent, _presentMask)
		QueueMaskChanges(EMatchRoomEventKind.ReadyChanged, oldReady, _readyMask)
		Local returned:UInt = _inRoomMask & ~oldInRoom
		For Local player:Int = 0 Until _config.maxPlayers
			If returned & (1:UInt Shl player) Then Queue(EMatchRoomEventKind.MemberReturned, player, True)
		Next
		If oldConfigurationRevision <> _configurationRevision Then Queue(EMatchRoomEventKind.ConfigurationChanged)
		If oldPhase <> _phase Then
			Select _phase
				Case EMatchRoomPhase.Staging Queue(EMatchRoomEventKind.StagingOpened)
				Case EMatchRoomPhase.Playing Queue(EMatchRoomEventKind.MatchStarted)
				Case EMatchRoomPhase.Results Queue(EMatchRoomEventKind.MatchFinished)
			End Select
		End If
		Queue(EMatchRoomEventKind.StateChanged)
		Return True
	End Method

	Public
	Function CreateHost:TMatchRoom(session:TNetSession, config:SMatchRoomConfig)
		If Not ValidConfig(session, config) Then Return Null
		Return New TMatchRoom(session, config, True, New SNetPeer)
	End Function

	Function CreateClient:TMatchRoom(session:TNetSession, authorityPeer:SNetPeer, config:SMatchRoomConfig)
		If Not ValidConfig(session, config) Or Not authorityPeer.IsValid() Then Return Null
		Return New TMatchRoom(session, config, False, authorityPeer)
	End Function

	Method Delete()
		If _commandBuffer Then MemFree(_commandBuffer)
		If _stateBuffer Then MemFree(_stateBuffer)
		_commandBuffer = Null
		_stateBuffer = Null
	End Method

	Rem
	bbdoc: Reports a session peer joining and synchronizes the room.
	End Rem
	Method PlayerJoined:ETransportResult(peer:SNetPeer)
		If Not peer.IsValid() Then Return ETransportResult.InvalidPeer
		If Not _authority Then
			If Not peer.Equals(_authorityPeer) Then Return ETransportResult.InvalidPeer
			_authorityBound = True
			Return SendCommand(EMatchRoomCommand.Synchronize)
		End If
		Local existing:Int = PlayerForPeer(peer)
		If existing >= 0 Then Return SendStateTo(existing)
		Local player:Int = FreePlayer()
		If player < 0 Then Return ETransportResult.Failed
		Local bit:UInt = 1:UInt Shl player
		_peers[player] = peer
		_peerBound[player] = True
		_presentMask :| bit
		_inRoomMask :| bit
		Queue(EMatchRoomEventKind.MemberJoined, player, True)
		Return CommitState()
	End Method

	Rem
	bbdoc: Reports a departed peer and safely reopens staging when the host remains.
	End Rem
	Method PlayerLeft:ETransportResult(peer:SNetPeer, code:Int = 0)
		If Not _authority Then
			If Not peer.Equals(_authorityPeer) Then Return ETransportResult.InvalidPeer
			_phase = EMatchRoomPhase.Closed
			_authorityBound = False
			Queue(EMatchRoomEventKind.AuthorityLeft, 0, code)
			Queue(EMatchRoomEventKind.StateChanged)
			Return ETransportResult.Ok
		End If
		Local player:Int = PlayerForPeer(peer)
		If player < 0 Then Return ETransportResult.InvalidPeer
		Local bit:UInt = 1:UInt Shl player
		_peerBound[player] = False
		_presentMask :& ~bit
		_readyMask :& ~bit
		_inRoomMask :& ~bit
		Queue(EMatchRoomEventKind.MemberLeft, player, code)
		OpenStaging()
		Return CommitState()
	End Method

	Rem
	bbdoc: Routes one room protocol message received from the session.
	returns: True when the message belongs to the room and is valid.
	End Rem
	Method Receive:Int(peer:SNetPeer, messageType:UInt, packet:SPacketView)
		Local accepted:Int
		If _authority And messageType = _config.commandMessageType Then
			Local player:Int = PlayerForPeer(peer)
			If player >= 0 Then accepted = ReceiveCommand(player, packet)
		Else If Not _authority And messageType = _config.stateMessageType And peer.Equals(_authorityPeer) Then
			accepted = ReceiveState(packet)
		Else
			Return False
		End If
		If Not accepted Then _rejectedPackets :+ 1
		Return accepted
	End Method

	Method HandlesMessageType:Int(messageType:UInt)
		Return messageType = _config.commandMessageType Or messageType = _config.stateMessageType
	End Method

	Rem
	bbdoc: Replaces the host-controlled opaque match configuration.
	End Rem
	Method SetConfiguration:ETransportResult(packet:SPacketView)
		If Not _authority Or _phase <> EMatchRoomPhase.Staging Or packet.Length() > Size_T(_config.maxConfigurationBytes) Then Return ETransportResult.Failed
		If packet.Length() And Not packet.Data() Then Return ETransportResult.Failed
		_configurationLength = Int(packet.Length())
		If _configurationLength Then MemCopy(Byte Ptr(_configuration), packet.Data(), packet.Length())
		_configurationRevision :+ 1
		Local oldReady:UInt = _readyMask
		_readyMask = 0
		QueueMaskChanges(EMatchRoomEventKind.ReadyChanged, oldReady, _readyMask)
		Queue(EMatchRoomEventKind.ConfigurationChanged)
		Return CommitState()
	End Method

	Method SetLocalReady:ETransportResult(ready:Int)
		If _localPlayer < 0 Then Return ETransportResult.Failed
		If _authority Then Return ApplyReady(_localPlayer, ready)
		Return SendCommand(EMatchRoomCommand.Ready, ready)
	End Method

	Rem
	bbdoc: Starts a host-authoritative round after all present members are in staging and ready.
	End Rem
	Method BeginMatch:ETransportResult(seed:ULong, minimumPlayers:Int = 2)
		If Not _authority Or _phase <> EMatchRoomPhase.Staging Or MemberCount() < minimumPlayers Or _inRoomMask <> _presentMask Or _readyMask <> _presentMask Then Return ETransportResult.Failed
		Local oldReady:UInt = _readyMask
		Local oldPhase:EMatchRoomPhase = _phase
		_round :+ 1
		_seed = seed
		_phase = EMatchRoomPhase.Playing
		_readyMask = 0
		_inRoomMask = 0
		QueueMaskChanges(EMatchRoomEventKind.ReadyChanged, oldReady, _readyMask)
		If oldPhase <> _phase Then Queue(EMatchRoomEventKind.MatchStarted)
		Return CommitState()
	End Method

	Rem
	bbdoc: Marks the current round complete while members independently view results.
	End Rem
	Method FinishMatch:ETransportResult()
		If Not _authority Or _phase <> EMatchRoomPhase.Playing Then Return ETransportResult.Failed
		_phase = EMatchRoomPhase.Results
		_inRoomMask = 0
		Queue(EMatchRoomEventKind.MatchFinished)
		Return CommitState()
	End Method

	Rem
	bbdoc: Returns the local member to staging, abandoning an active match if necessary.
	End Rem
	Method ReturnToRoom:ETransportResult()
		If _localPlayer < 0 Then Return ETransportResult.Failed
		If _authority Then Return ApplyReturn(_localPlayer)
		Return SendCommand(EMatchRoomCommand.ReturnToRoom)
	End Method

	Method Synchronize:ETransportResult()
		If _authority Then Return BroadcastState()
		Return SendCommand(EMatchRoomCommand.Synchronize)
	End Method

	Method Poll:Int(event:SMatchRoomEvent Var)
		If _eventCount = 0 Then
			event = New SMatchRoomEvent
			Return False
		End If
		event = _events[_eventRead]
		_eventRead = (_eventRead + 1) Mod _events.Length
		_eventCount :- 1
		Return True
	End Method

	Method IsAuthority:Int()
		Return _authority
	End Method

	Method Phase:EMatchRoomPhase()
		Return _phase
	End Method

	Method LocalPlayer:Int()
		Return _localPlayer
	End Method

	Method MaxPlayers:Int()
		Return _config.maxPlayers
	End Method

	Rem
	bbdoc: Returns the stable room slot assigned to a session peer, or -1.
	End Rem
	Method PlayerForSessionPeer:Int(peer:SNetPeer)
		Return PlayerForPeer(peer)
	End Method

	Rem
	bbdoc: Returns the session peer assigned to a remote room slot.
	End Rem
	Method SessionPeer:SNetPeer(player:Int)
		If player < 0 Or player >= _config.maxPlayers Or Not _peerBound[player] Then Return New SNetPeer
		Return _peers[player]
	End Method

	Method Round:UInt()
		Return _round
	End Method

	Method Seed:ULong()
		Return _seed
	End Method

	Method Revision:UInt()
		Return _revision
	End Method

	Method ConfigurationRevision:UInt()
		Return _configurationRevision
	End Method

	Method Configuration:SPacketView()
		Local data:Byte Ptr
		If _configurationLength Then data = Byte Ptr(_configuration)
		Return New SPacketView(data, Size_T(_configurationLength))
	End Method

	Method MemberCount:Int()
		Local count:Int
		For Local player:Int = 0 Until _config.maxPlayers
			If _presentMask & (1:UInt Shl player) Then count :+ 1
		Next
		Return count
	End Method

	Method IsPresent:Int(player:Int)
		Return player >= 0 And player < _config.maxPlayers And (_presentMask & (1:UInt Shl player)) <> 0
	End Method

	Method IsReady:Int(player:Int)
		Return player >= 0 And player < _config.maxPlayers And (_readyMask & (1:UInt Shl player)) <> 0
	End Method

	Method IsInRoom:Int(player:Int)
		Return player >= 0 And player < _config.maxPlayers And (_inRoomMask & (1:UInt Shl player)) <> 0
	End Method

	Method AllPresentReady:Int(minimumPlayers:Int = 2)
		Return MemberCount() >= minimumPlayers And _inRoomMask = _presentMask And _readyMask = _presentMask
	End Method

	Method AllPresentInRoom:Int(minimumPlayers:Int = 2)
		Return MemberCount() >= minimumPlayers And _inRoomMask = _presentMask
	End Method

	Method DroppedEvents:Int()
		Return _droppedEvents
	End Method

	Method RejectedPackets:Int()
		Return _rejectedPackets
	End Method
End Type
