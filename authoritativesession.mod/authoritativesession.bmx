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
bbdoc: High-level server-authoritative input, snapshot, prediction, and interpolation orchestration.
End Rem
Module GameNet.AuthoritativeSession

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial authoritative client and server sessions"

Import GameNet.Session
Import GameNet.Prediction
Import GameNet.Snapshot
Import BRL.Blitz

Const AUTHORITATIVE_SESSION_MAX_PLAYERS:Int = 16
Const AUTHORITATIVE_SESSION_MAX_ENTITIES:Int = 256
Const AUTHORITATIVE_SESSION_WIRE_VERSION:UInt = 1
Const AUTHORITATIVE_INPUT_HEADER_SIZE:Size_T = 2
Const AUTHORITATIVE_INPUT_ENTRY_SIZE:Size_T = 6
Const AUTHORITATIVE_SNAPSHOT_HEADER_SIZE:Size_T = 13

Rem
bbdoc: Identifies a fatal local authoritative-session failure.
about: Malformed and irrelevant packets are rejected and counted without
failing the session. These values describe exhausted bounded storage or a game
prediction callback which can no longer reconcile safely.
End Rem
Enum EAuthoritativeSessionFailure:Int
	None
	InputHistoryFull
	ServerInputQueueFull
	AuthoritativeStateRejected
	InputReplayRejected
End Enum

Rem
bbdoc: Shared bounded storage and protocol configuration.
about: Entity indices range from zero through @entityCount minus one. Input and
snapshot message types must be distinct application message identifiers.
End Rem
Struct SAuthoritativeSessionConfig
	Field playerCount:Int
	Field entityCount:Int
	Field inputHistoryCapacity:Int
	Field serverInputCapacity:Int
	Field snapshotCapacity:Int
	Field maxInputSize:Size_T
	Field maxStateSize:Size_T
	Field redundantInputCount:Int
	Field ticksPerSecond:Double
	Field baseDelayTicks:Float
	Field maximumDelayTicks:Float
	Field inputMessageType:UInt
	Field snapshotMessageType:UInt
	Field channel:UInt

	Method New(playerCount:Int, entityCount:Int, inputHistoryCapacity:Int, serverInputCapacity:Int, snapshotCapacity:Int, maxInputSize:Size_T, maxStateSize:Size_T, redundantInputCount:Int = 16, ticksPerSecond:Double = 60.0, baseDelayTicks:Float = 2.0, maximumDelayTicks:Float = 12.0, inputMessageType:UInt = 1, snapshotMessageType:UInt = 2, channel:UInt = 1)
		Self.playerCount = playerCount
		Self.entityCount = entityCount
		Self.inputHistoryCapacity = inputHistoryCapacity
		Self.serverInputCapacity = serverInputCapacity
		Self.snapshotCapacity = snapshotCapacity
		Self.maxInputSize = maxInputSize
		Self.maxStateSize = maxStateSize
		Self.redundantInputCount = redundantInputCount
		Self.ticksPerSecond = ticksPerSecond
		Self.baseDelayTicks = baseDelayTicks
		Self.maximumDelayTicks = maximumDelayTicks
		Self.inputMessageType = inputMessageType
		Self.snapshotMessageType = snapshotMessageType
		Self.channel = channel
	End Method
End Struct

Rem
bbdoc: One validated authoritative snapshot received by a client.
about: The state view is borrowed from the received packet and must be consumed
before the underlying transport is polled again.
End Rem
Struct SAuthoritativeSnapshot
	Private
	Field _entity:Int
	Field _tick:UInt
	Field _acknowledgedInput:UInt
	Field _state:SPacketView

	Method New(entity:Int, tick:UInt, acknowledgedInput:UInt, state:SPacketView)
		_entity = entity
		_tick = tick
		_acknowledgedInput = acknowledgedInput
		_state = state
	End Method

	Public
	Method New()
	End Method

	Method Entity:Int()
		Return _entity
	End Method

	Method Tick:UInt()
		Return _tick
	End Method

	Method AcknowledgedInput:UInt()
		Return _acknowledgedInput
	End Method

	Method State:SPacketView()
		Return _state
	End Method
End Struct

Rem
bbdoc: Game-defined local prediction operations used during reconciliation.
about: Loading the authoritative local state must replace predicted simulation
state. ReplayInput then reapplies every retained unacknowledged command in
sequence order. Presentation smoothing remains under game control.
End Rem
Interface IAuthoritativePredictionSimulation
	Method LoadAuthoritativeState:Int(tick:UInt, state:SPacketView)
	Method ReplayInput:Int(sequence:UInt, input:SPacketView)
End Interface

Rem
bbdoc: Client-side authoritative session orchestration.
about: This object owns bounded input history and per-entity snapshot timelines.
It does not own or poll the network session. Route snapshot messages to
#ReceiveSnapshot, queue local commands through #QueueInput, and send redundant
commands with #SendInputs. Normal operations within configured bounds do not
allocate managed storage.
End Rem
Type TAuthoritativeClientSession
	Private
	Field _config:SAuthoritativeSessionConfig
	Field _history:TPredictionHistory
	Field _timelines:TSnapshotTimeline[]
	Field _clock:TSnapshotClock
	Field _delay:TSnapshotDelay
	Field _sendBuffer:Byte Ptr
	Field _sendCapacity:Size_T
	Field _nextSequence:UInt = 1
	Field _localEntity:Int = -1
	Field _acknowledgedInput:UInt
	Field _recovering:Int
	Field _failed:Int
	Field _failureReason:EAuthoritativeSessionFailure
	Field _rejectedPackets:Int
	Field _snapshotsReceived:ULong

	Method New(config:SAuthoritativeSessionConfig)
		_config = config
		_history = TPredictionHistory.Create(config.inputHistoryCapacity, config.maxInputSize)
		_timelines = New TSnapshotTimeline[config.entityCount]
		For Local entity:Int = 0 Until config.entityCount
			_timelines[entity] = TSnapshotTimeline.Create(config.snapshotCapacity, config.maxStateSize)
		Next
		_clock = TSnapshotClock.Create(config.ticksPerSecond)
		_delay = TSnapshotDelay.Create(config.ticksPerSecond, config.baseDelayTicks, config.maximumDelayTicks)
		_sendCapacity = AUTHORITATIVE_INPUT_HEADER_SIZE + Size_T(config.redundantInputCount) * (AUTHORITATIVE_INPUT_ENTRY_SIZE + config.maxInputSize)
		_sendBuffer = MemAlloc(_sendCapacity)
	End Method

	Public
	Rem
	bbdoc: Calculates client payload storage for @config without allocating it.
	returns: False for an invalid configuration or Size_T arithmetic overflow.
	End Rem
	Function MemoryRequirements:Int(config:SAuthoritativeSessionConfig, requirements:SNetMemoryRequirements Var)
		requirements = New SNetMemoryRequirements
		If Not ValidConfig(config) Then Return False
		Local nativeBytes:Size_T
		Local managedBytes:Size_T
		Local inputCount:Size_T = Size_T(config.inputHistoryCapacity)
		Local entityCount:Size_T = Size_T(config.entityCount)
		Local snapshotCount:Size_T = Size_T(config.snapshotCapacity)
		If Not NetAccumulateSize(nativeBytes, inputCount, config.maxInputSize) Then Return False
		If Not NetAccumulateSize(nativeBytes, entityCount * snapshotCount, config.maxStateSize) Then Return False
		If Not NetAccumulateSize(nativeBytes, 1, AUTHORITATIVE_INPUT_HEADER_SIZE) Then Return False
		If Not NetAccumulateSize(nativeBytes, Size_T(config.redundantInputCount), AUTHORITATIVE_INPUT_ENTRY_SIZE + config.maxInputSize) Then Return False
		If Not NetAccumulateSize(managedBytes, inputCount, Size_T(SizeOf(UInt Null) + SizeOf(Size_T Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, entityCount, Size_T(SizeOf(Byte Ptr Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, entityCount * snapshotCount, Size_T(SizeOf(UInt Null) + SizeOf(Long Null) + SizeOf(Size_T Null))) Then Return False
		Local totalBytes:Size_T = nativeBytes
		If Not NetAccumulateSize(totalBytes, 1, managedBytes) Then Return False
		requirements = New SNetMemoryRequirements(nativeBytes, managedBytes)
		Return True
	End Function

	Function ValidConfig:Int(config:SAuthoritativeSessionConfig)
		Return config.playerCount >= 1 And config.playerCount <= AUTHORITATIVE_SESSION_MAX_PLAYERS ..
			And config.entityCount >= 1 And config.entityCount <= AUTHORITATIVE_SESSION_MAX_ENTITIES ..
			And config.inputHistoryCapacity >= 1 And config.serverInputCapacity >= 1 ..
			And config.snapshotCapacity >= 2 And config.maxInputSize >= 1 And config.maxInputSize <= 65535 ..
			And config.maxStateSize >= 1 And config.maxStateSize <= 65535 ..
			And config.redundantInputCount >= 1 And config.redundantInputCount <= 255 ..
			And config.ticksPerSecond > 0.0 And config.baseDelayTicks >= 0.0 ..
			And config.maximumDelayTicks >= config.baseDelayTicks ..
			And config.inputMessageType <> config.snapshotMessageType
	End Function

	Private
	Method Fail:Int(reason:EAuthoritativeSessionFailure)
		_failed = True
		_failureReason = reason
		Return False
	End Method

	Public
	Function Create:TAuthoritativeClientSession(config:SAuthoritativeSessionConfig)
		Local requirements:SNetMemoryRequirements
		If Not MemoryRequirements(config, requirements) Then Return Null
		Return New TAuthoritativeClientSession(config)
	End Function

	Method Delete()
		If _sendBuffer Then MemFree(_sendBuffer)
		_sendBuffer = Null
	End Method

	Rem
	bbdoc: Clears retained inputs, snapshots, timing, counters, and failure state.
	End Rem
	Method Reset(nextInputSequence:UInt = 1)
		_history.Clear()
		For Local timeline:TSnapshotTimeline = EachIn _timelines
			timeline.Clear()
		Next
		_clock.Clear()
		_delay.Clear()
		_nextSequence = nextInputSequence
		_acknowledgedInput = nextInputSequence - 1
		_recovering = False
		_failed = False
		_failureReason = EAuthoritativeSessionFailure.None
		_rejectedPackets = 0
		_snapshotsReceived = 0
	End Method

	Rem
	bbdoc: Sets the entity whose snapshots are used for local reconciliation.
	End Rem
	Method SetLocalEntity:Int(entity:Int)
		If entity < 0 Or entity >= _timelines.Length Then Return False
		_localEntity = entity
		Return True
	End Method

	Method LocalEntity:Int()
		Return _localEntity
	End Method

	Rem
	bbdoc: Retains one game-defined local input and returns its sequence number.
	returns: Zero if the bounded input history is full or the payload is invalid.
	End Rem
	Method QueueInput:UInt(input:Byte Ptr, length:Size_T)
		If _failed Or _recovering Or length < 1 Or length > _config.maxInputSize Or Not input Then Return 0
		Local sequence:UInt = _nextSequence
		If Not _history.Add(sequence, input, length) Then
			Fail(EAuthoritativeSessionFailure.InputHistoryFull)
			Return 0
		End If
		_nextSequence :+ 1
		Return sequence
	End Method

	Rem
	bbdoc: Writes an oldest-first redundant batch of unacknowledged local inputs.
	End Rem
	Method WriteInputs:Size_T(buffer:Byte Ptr, capacity:Size_T)
		If _failed Or Not buffer Or _history.Count() = 0 Then Return 0
		Local count:Int = Min(_history.Count(), _config.redundantInputCount)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt8(AUTHORITATIVE_SESSION_WIRE_VERSION)
		writer.WriteUInt8(UInt(count))
		For Local index:Int = 0 Until count
			Local input:SPredictionInput
			If Not _history.Get(index, input) Then Return 0
			writer.WriteUInt32(input.Sequence())
			writer.WriteUInt16(UInt(input.Payload().Length()))
			writer.WriteBytes(input.Payload().Data(), input.Payload().Length())
		Next
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Rem
	bbdoc: Sends retained inputs to an authority using unreliable-sequenced delivery.
	End Rem
	Method SendInputs:ETransportResult(session:TNetSession, authority:SNetPeer)
		If Not session Or Not authority.IsValid() Then Return ETransportResult.InvalidPeer
		Local length:Size_T = WriteInputs(_sendBuffer, _sendCapacity)
		If length = 0 Then Return ETransportResult.WouldBlock
		Return session.Send(authority, _config.inputMessageType, _config.channel, EDeliveryMode.UnreliableSequenced, _sendBuffer, length)
	End Method

	Rem
	bbdoc: Validates and stores one authoritative snapshot.
	about: Acknowledged local inputs are discarded. The returned state is suitable
	for immediate reconciliation, while a copy is retained for interpolation.
	End Rem
	Method ReceiveSnapshot:Int(packet:SPacketView, arrivalMillis:Int, snapshot:SAuthoritativeSnapshot Var)
		snapshot = New SAuthoritativeSnapshot
		If _failed Then Return False
		Local reader:SPacketReader = New SPacketReader(packet)
		Local version:UInt
		Local entityValue:UInt
		Local tick:UInt
		Local acknowledged:UInt
		Local length:UInt
		If Not reader.ReadUInt8(version) Or version <> AUTHORITATIVE_SESSION_WIRE_VERSION ..
			Or Not reader.ReadUInt16(entityValue) Or entityValue >= UInt(_timelines.Length) ..
			Or Not reader.ReadUInt32(tick) Or Not reader.ReadUInt32(acknowledged) ..
			Or Not reader.ReadUInt16(length) Or length < 1 Or length > UInt(_config.maxStateSize) ..
			Or Size_T(length) <> reader.Remaining() Then
			_rejectedPackets :+ 1
			Return False
		End If
		If PredictionSequenceAfter(acknowledged, _nextSequence - 1) Then
			_rejectedPackets :+ 1
			Return False
		End If

		Local state:SPacketView = reader.RemainingView()
		Local entity:Int = Int(entityValue)
		If Not _timelines[entity].Add(tick, state.Data(), state.Length()) Then
			_rejectedPackets :+ 1
			Return False
		End If
		If _clock.Observe(tick, arrivalMillis) Then _delay.Observe(tick, arrivalMillis)
		If acknowledged = _acknowledgedInput Or PredictionSequenceAfter(acknowledged, _acknowledgedInput) Then
			_history.Acknowledge(acknowledged)
			_acknowledgedInput = acknowledged
		End If
		_snapshotsReceived :+ 1
		snapshot = New SAuthoritativeSnapshot(entity, tick, acknowledged, state)
		If _recovering And entity = _localEntity Then _recovering = False
		Return True
	End Method

	Rem
	bbdoc: Restores a local authoritative snapshot and replays pending inputs.
	End Rem
	Method Reconcile:Int(snapshot:SAuthoritativeSnapshot, simulation:IAuthoritativePredictionSimulation)
		If _failed Or Not simulation Or snapshot.Entity() <> _localEntity Or snapshot.State().IsEmpty() Then Return False
		If Not simulation.LoadAuthoritativeState(snapshot.Tick(), snapshot.State()) Then Return Fail(EAuthoritativeSessionFailure.AuthoritativeStateRejected)
		For Local index:Int = 0 Until _history.Count()
			Local input:SPredictionInput
			If Not _history.Get(index, input) Or Not simulation.ReplayInput(input.Sequence(), input.Payload()) Then Return Fail(EAuthoritativeSessionFailure.InputReplayRejected)
		Next
		Return True
	End Method

	Rem
	bbdoc: Samples one entity at an unwrapped server render tick.
	End Rem
	Method SampleEntity:Int(entity:Int, renderTick:Double, sample:SSnapshotSample Var)
		If entity < 0 Or entity >= _timelines.Length Then
			sample = New SSnapshotSample
			Return False
		End If
		Return _timelines[entity].Sample(renderTick, sample)
	End Method

	Rem
	bbdoc: Returns the estimated server render tick including adaptive delay.
	End Rem
	Method RenderTick:Double(localMillis:Int)
		If Not _clock.IsObserved() Then Return 0.0
		Return _clock.Estimate(localMillis) - Double(_delay.DelayTicks())
	End Method

	Method ClearEntity(entity:Int)
		If entity >= 0 And entity < _timelines.Length Then _timelines[entity].Clear()
	End Method

	Rem
	bbdoc: Clears stale presentation timing and waits for a fresh local authoritative snapshot.
	about: Pending unacknowledged inputs and their sequence numbers are retained so
	the server can acknowledge them normally. New local inputs are refused until
	a snapshot for the configured local entity arrives.
	End Rem
	Method BeginRecovery:Int()
		If _failed Or _localEntity < 0 Then Return False
		For Local timeline:TSnapshotTimeline = EachIn _timelines
			timeline.Clear()
		Next
		_clock.Clear()
		_delay.Clear()
		_recovering = True
		Return True
	End Method

	Method IsRecovering:Int()
		Return _recovering
	End Method

	Method PendingInputCount:Int()
		Return _history.Count()
	End Method

	Method GetPendingInput:Int(index:Int, input:SPredictionInput Var)
		Return _history.Get(index, input)
	End Method

	Method NextInputSequence:UInt()
		Return _nextSequence
	End Method

	Method AcknowledgedInput:UInt()
		Return _acknowledgedInput
	End Method

	Method DelayTicks:Float()
		Return _delay.DelayTicks()
	End Method

	Method DelayMillis:Float()
		Return _delay.DelayMillis()
	End Method

	Method Failed:Int()
		Return _failed
	End Method

	Method FailureReason:EAuthoritativeSessionFailure()
		Return _failureReason
	End Method

	Method RejectedPackets:Int()
		Return _rejectedPackets
	End Method

	Method SnapshotsReceived:ULong()
		Return _snapshotsReceived
	End Method

	Method InputPacketCapacity:Size_T()
		Return _sendCapacity
	End Method
End Type

Rem
bbdoc: Server-side authoritative input and snapshot orchestration.
about: Bind fixed player slots to active session peers. Received redundant input
batches are de-duplicated and retained in bounded per-player queues. The game
peeks and applies the oldest command, then acknowledges it. Snapshot helpers
include that recipient's acknowledgement automatically.
End Rem
Type TAuthoritativeServerSession
	Private
	Field _config:SAuthoritativeSessionConfig
	Field _peers:SNetPeer[]
	Field _bound:Byte[]
	Field _sequencers:SPredictionSequencer[]
	Field _queues:TPredictionHistory[]
	Field _acknowledged:UInt[]
	Field _sendBuffer:Byte Ptr
	Field _sendCapacity:Size_T
	Field _failed:Int
	Field _failureReason:EAuthoritativeSessionFailure
	Field _rejectedPackets:Int
	Field _duplicateInputs:ULong
	Field _inputGaps:ULong

	Method New(config:SAuthoritativeSessionConfig)
		_config = config
		_peers = New SNetPeer[config.playerCount]
		_bound = New Byte[config.playerCount]
		_sequencers = New SPredictionSequencer[config.playerCount]
		_queues = New TPredictionHistory[config.playerCount]
		_acknowledged = New UInt[config.playerCount]
		For Local player:Int = 0 Until config.playerCount
			_queues[player] = TPredictionHistory.Create(config.serverInputCapacity, config.maxInputSize)
			_sequencers[player].Reset(1)
		Next
		_sendCapacity = AUTHORITATIVE_SNAPSHOT_HEADER_SIZE + config.maxStateSize
		_sendBuffer = MemAlloc(_sendCapacity)
	End Method

	Method Fail:Int(reason:EAuthoritativeSessionFailure)
		_failed = True
		_failureReason = reason
		Return False
	End Method

	Method ValidPlayer:Int(player:Int)
		Return player >= 0 And player < _peers.Length
	End Method

	Public
	Rem
	bbdoc: Calculates server payload storage for @config without allocating it.
	returns: False for an invalid configuration or Size_T arithmetic overflow.
	End Rem
	Function MemoryRequirements:Int(config:SAuthoritativeSessionConfig, requirements:SNetMemoryRequirements Var)
		requirements = New SNetMemoryRequirements
		If Not TAuthoritativeClientSession.ValidConfig(config) Then Return False
		Local nativeBytes:Size_T
		Local managedBytes:Size_T
		Local players:Size_T = Size_T(config.playerCount)
		Local queuedInputs:Size_T = Size_T(config.serverInputCapacity)
		If Not NetAccumulateSize(nativeBytes, players * queuedInputs, config.maxInputSize) Then Return False
		If Not NetAccumulateSize(nativeBytes, 1, AUTHORITATIVE_SNAPSHOT_HEADER_SIZE + config.maxStateSize) Then Return False
		If Not NetAccumulateSize(managedBytes, players, Size_T(SizeOf(SNetPeer) + SizeOf(Byte Null) + SizeOf(SPredictionSequencer) + SizeOf(Byte Ptr Null) + SizeOf(UInt Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, players * queuedInputs, Size_T(SizeOf(UInt Null) + SizeOf(Size_T Null))) Then Return False
		Local totalBytes:Size_T = nativeBytes
		If Not NetAccumulateSize(totalBytes, 1, managedBytes) Then Return False
		requirements = New SNetMemoryRequirements(nativeBytes, managedBytes)
		Return True
	End Function

	Function Create:TAuthoritativeServerSession(config:SAuthoritativeSessionConfig)
		Local requirements:SNetMemoryRequirements
		If Not MemoryRequirements(config, requirements) Then Return Null
		Return New TAuthoritativeServerSession(config)
	End Function

	Method Delete()
		If _sendBuffer Then MemFree(_sendBuffer)
		_sendBuffer = Null
	End Method

	Rem
	bbdoc: Binds a player slot and resets its bounded input stream.
	End Rem
	Method BindPlayer:Int(player:Int, peer:SNetPeer, nextInputSequence:UInt = 1)
		If Not ValidPlayer(player) Or Not peer.IsValid() Then Return False
		For Local other:Int = 0 Until _peers.Length
			If other <> player And _bound[other] And _peers[other].Equals(peer) Then Return False
		Next
		_peers[player] = peer
		_bound[player] = True
		_queues[player].Clear()
		_sequencers[player].Reset(nextInputSequence)
		_acknowledged[player] = nextInputSequence - 1
		Return True
	End Method

	Method UnbindPlayer(player:Int)
		If Not ValidPlayer(player) Then Return
		_peers[player] = New SNetPeer
		_bound[player] = False
		_queues[player].Clear()
		_sequencers[player].Reset(1)
		_acknowledged[player] = 0
	End Method

	Method PlayerForPeer:Int(peer:SNetPeer)
		For Local player:Int = 0 Until _peers.Length
			If _bound[player] And _peers[player].Equals(peer) Then Return player
		Next
		Return -1
	End Method

	Rem
	bbdoc: Validates and queues a redundant client input batch.
	about: Duplicate entries are ignored. A future gap leaves that entry and all
	later entries unprocessed so a subsequent redundant packet can fill it.
	End Rem
	Method ReceiveInputs:Int(player:Int, peer:SNetPeer, packet:SPacketView)
		If _failed Or Not ValidPlayer(player) Or Not _bound[player] Or Not _peers[player].Equals(peer) Then Return False
		Local reader:SPacketReader = New SPacketReader(packet)
		Local version:UInt
		Local countValue:UInt
		If Not reader.ReadUInt8(version) Or version <> AUTHORITATIVE_SESSION_WIRE_VERSION Or Not reader.ReadUInt8(countValue) ..
			Or countValue < 1 Or countValue > UInt(_config.redundantInputCount) Then
			_rejectedPackets :+ 1
			Return False
		End If

		Local expected:UInt = _sequencers[player].NextSequence()
		Local accepted:Int
		Local prior:UInt
		For Local index:Int = 0 Until Int(countValue)
			Local sequence:UInt
			Local length:UInt
			If Not reader.ReadUInt32(sequence) Or Not reader.ReadUInt16(length) Or length < 1 Or length > UInt(_config.maxInputSize) Or Size_T(length) > reader.Remaining() Then
				_rejectedPackets :+ 1
				Return False
			End If
			If index > 0 And Not PredictionSequenceAfter(sequence, prior) Then
				_rejectedPackets :+ 1
				Return False
			End If
			Local delta:Int = PredictionSequenceDelta(sequence, expected)
			If delta = 0 Then
				accepted :+ 1
				expected :+ 1
			Else If delta > 0 Then
				' Later entries cannot be accepted until this gap is filled.
				expected = sequence
			End If
			If Not reader.Skip(Size_T(length)) Then Return False
			prior = sequence
		Next
		If reader.Remaining() <> 0 Then
			_rejectedPackets :+ 1
			Return False
		End If
		If _queues[player].Count() + accepted > _queues[player].Capacity() Then Return Fail(EAuthoritativeSessionFailure.ServerInputQueueFull)

		reader = New SPacketReader(packet)
		reader.ReadUInt8(version)
		reader.ReadUInt8(countValue)
		For Local index:Int = 0 Until Int(countValue)
			Local sequence:UInt
			Local length:UInt
			reader.ReadUInt32(sequence)
			reader.ReadUInt16(length)
			Local payload:SPacketView = reader.RemainingView()
			Select _sequencers[player].Process(sequence)
				Case EPredictionSequenceResult.Accepted
					If Not _queues[player].Add(sequence, payload.Data(), Size_T(length)) Then Return Fail(EAuthoritativeSessionFailure.ServerInputQueueFull)
				Case EPredictionSequenceResult.Duplicate
					_duplicateInputs :+ 1
				Case EPredictionSequenceResult.Gap
					_inputGaps :+ 1
					Return True
			End Select
			reader.Skip(Size_T(length))
		Next
		Return True
	End Method

	Method InputCount:Int(player:Int)
		If Not ValidPlayer(player) Or Not _bound[player] Then Return 0
		Return _queues[player].Count()
	End Method

	Rem
	bbdoc: Borrows the oldest input waiting for authoritative simulation.
	End Rem
	Method PeekInput:Int(player:Int, input:SPredictionInput Var)
		If Not ValidPlayer(player) Or Not _bound[player] Then
			input = New SPredictionInput
			Return False
		End If
		Return _queues[player].Get(0, input)
	End Method

	Rem
	bbdoc: Acknowledges exactly the oldest queued input after it has been applied.
	End Rem
	Method AcknowledgeInput:Int(player:Int, sequence:UInt)
		If Not ValidPlayer(player) Or Not _bound[player] Then Return False
		Local input:SPredictionInput
		If Not _queues[player].Get(0, input) Or input.Sequence() <> sequence Then Return False
		_queues[player].Acknowledge(sequence)
		_acknowledged[player] = sequence
		Return True
	End Method

	Rem
	bbdoc: Writes one entity snapshot for a specific recipient.
	End Rem
	Method WriteSnapshot:Size_T(recipientPlayer:Int, entity:Int, tick:UInt, state:Byte Ptr, length:Size_T, buffer:Byte Ptr, capacity:Size_T)
		If _failed Or Not ValidPlayer(recipientPlayer) Or Not _bound[recipientPlayer] Or entity < 0 Or entity >= _config.entityCount ..
			Or length < 1 Or length > _config.maxStateSize Or Not state Or Not buffer Then Return 0
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt8(AUTHORITATIVE_SESSION_WIRE_VERSION)
		writer.WriteUInt16(UInt(entity))
		writer.WriteUInt32(tick)
		writer.WriteUInt32(_acknowledged[recipientPlayer])
		writer.WriteUInt16(UInt(length))
		writer.WriteBytes(state, length)
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Rem
	bbdoc: Sends one entity snapshot to a bound player using unreliable-sequenced delivery.
	End Rem
	Method SendSnapshot:ETransportResult(session:TNetSession, recipientPlayer:Int, entity:Int, tick:UInt, state:Byte Ptr, length:Size_T)
		If Not session Or Not ValidPlayer(recipientPlayer) Or Not _bound[recipientPlayer] Then Return ETransportResult.InvalidPeer
		Local packetLength:Size_T = WriteSnapshot(recipientPlayer, entity, tick, state, length, _sendBuffer, _sendCapacity)
		If packetLength = 0 Then Return ETransportResult.PacketTooLarge
		Return session.Send(_peers[recipientPlayer], _config.snapshotMessageType, _config.channel, EDeliveryMode.UnreliableSequenced, _sendBuffer, packetLength)
	End Method

	Method PlayerBound:Int(player:Int)
		Return ValidPlayer(player) And _bound[player]
	End Method

	Method PlayerPeer:SNetPeer(player:Int)
		If Not ValidPlayer(player) Or Not _bound[player] Then Return New SNetPeer
		Return _peers[player]
	End Method

	Method AcknowledgedInput:UInt(player:Int)
		If Not ValidPlayer(player) Then Return 0
		Return _acknowledged[player]
	End Method

	Method Failed:Int()
		Return _failed
	End Method

	Method FailureReason:EAuthoritativeSessionFailure()
		Return _failureReason
	End Method

	Method RejectedPackets:Int()
		Return _rejectedPackets
	End Method

	Method DuplicateInputs:ULong()
		Return _duplicateInputs
	End Method

	Method InputGaps:ULong()
		Return _inputGaps
	End Method

	Method SnapshotPacketCapacity:Size_T()
		Return _sendCapacity
	End Method
End Type

?
