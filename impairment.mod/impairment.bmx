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
bbdoc: Deterministic, bounded outbound network impairment decorator.
End Rem
Module GameNet.Impairment

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial latency, jitter, loss, duplication, reordering, and bandwidth simulation"

Import GameNet.Core
Import BRL.Blitz

Const IMPAIRMENT_PROBABILITY_SCALE:UInt = 10000
Const IMPAIRMENT_ERROR_SEND_BASE:Int = 1000
Const IMPAIRMENT_DELIVERY_UNRELIABLE:UInt = 1 Shl Int(EDeliveryMode.Unreliable)
Const IMPAIRMENT_DELIVERY_UNRELIABLE_SEQUENCED:UInt = 1 Shl Int(EDeliveryMode.UnreliableSequenced)
Const IMPAIRMENT_DELIVERY_RELIABLE_ORDERED:UInt = 1 Shl Int(EDeliveryMode.ReliableOrdered)
Const IMPAIRMENT_DELIVERY_ALL:UInt = IMPAIRMENT_DELIVERY_UNRELIABLE | IMPAIRMENT_DELIVERY_UNRELIABLE_SEQUENCED | IMPAIRMENT_DELIVERY_RELIABLE_ORDERED

Rem
bbdoc: Outbound packet impairment policy.
about: Probabilities use integer units out of 10,000, so 100 is one percent.
Reordering adds up to #reorderDelayMillis to selected packets. Zero disables
each corresponding effect.
End Rem
Struct SImpairmentConfig
	Field latencyMillis:UInt
	Field jitterMillis:UInt
	Field lossProbability:UInt
	Field duplicationProbability:UInt
	Field reorderingProbability:UInt
	Field reorderDelayMillis:UInt
	Field bandwidthBytesPerSecond:UInt
	Field deliveryMask:UInt

	Method New(latencyMillis:UInt = 0, jitterMillis:UInt = 0, lossProbability:UInt = 0, duplicationProbability:UInt = 0, reorderingProbability:UInt = 0, reorderDelayMillis:UInt = 0, bandwidthBytesPerSecond:UInt = 0, deliveryMask:UInt = IMPAIRMENT_DELIVERY_ALL)
		Self.latencyMillis = latencyMillis
		Self.jitterMillis = jitterMillis
		Self.lossProbability = lossProbability
		Self.duplicationProbability = duplicationProbability
		Self.reorderingProbability = reorderingProbability
		Self.reorderDelayMillis = reorderDelayMillis
		Self.bandwidthBytesPerSecond = bandwidthBytesPerSecond
		Self.deliveryMask = deliveryMask
	End Method
End Struct

Rem
bbdoc: Cumulative diagnostic counters for an impaired transport.
End Rem
Struct SImpairmentStats
	Private
	Field _queued:Int
	Field _sent:ULong
	Field _dropped:ULong
	Field _duplicated:ULong
	Field _reordered:ULong
	Field _queueOverflows:ULong
	Field _sendFailures:ULong

	Method New(queued:Int, sent:ULong, dropped:ULong, duplicated:ULong, reordered:ULong, queueOverflows:ULong, sendFailures:ULong)
		_queued = queued
		_sent = sent
		_dropped = dropped
		_duplicated = duplicated
		_reordered = reordered
		_queueOverflows = queueOverflows
		_sendFailures = sendFailures
	End Method

	Public
	Method New()
	End Method

	Method Queued:Int()
		Return _queued
	End Method

	Method Sent:ULong()
		Return _sent
	End Method

	Method Dropped:ULong()
		Return _dropped
	End Method

	Method Duplicated:ULong()
		Return _duplicated
	End Method

	Method Reordered:ULong()
		Return _reordered
	End Method

	Method QueueOverflows:ULong()
		Return _queueOverflows
	End Method

	Method SendFailures:ULong()
		Return _sendFailures
	End Method
End Struct

Private

Struct SImpairedPacket
	Field active:Int
	Field dueAt:UInt
	Field order:ULong
	Field peer:SNetPeer
	Field channel:UInt
	Field delivery:EDeliveryMode
	Field length:Size_T
End Struct

Public

Rem
bbdoc: Wraps any GameNet transport with deterministic outbound impairment.
about: All delayed packet metadata and bytes are allocated by #Create. Send
and Poll perform no managed allocation within the configured bounds. Apply a
decorator to every endpoint whose outbound traffic should be impaired.

Connected, disconnected, and error events from the wrapped transport are not
delayed. Loss and duplication are deliberately applied above backend delivery
guarantees, including reliable packets when that mode is selected, so
applications can test recovery from blackouts and pathological failures. A
deferred backend send failure is reported as an error event whose code is
#IMPAIRMENT_ERROR_SEND_BASE plus the underlying #ETransportResult value.
End Rem
Type TImpairedTransport Implements INetTransport
	Private
	Field _inner:INetTransport
	Field _config:SImpairmentConfig
	Field _packets:SImpairedPacket[]
	Field _storage:Byte Ptr
	Field _maxPacketSize:Size_T
	Field _queued:Int
	Field _nextOrder:ULong
	Field _randomState:UInt
	Field _manualClock:Int
	Field _nowMillis:UInt
	Field _bandwidthAt:UInt
	Field _bandwidthActive:Int
	Field _pendingError:Int
	Field _pendingErrorPeer:SNetPeer
	Field _sent:ULong
	Field _dropped:ULong
	Field _duplicated:ULong
	Field _reordered:ULong
	Field _queueOverflows:ULong
	Field _sendFailures:ULong

	Method New(inner:INetTransport, queueCapacity:Int, maxPacketSize:Size_T, config:SImpairmentConfig, seed:UInt, manualClock:Int)
		_inner = inner
		_config = config
		_packets = New SImpairedPacket[queueCapacity]
		_maxPacketSize = maxPacketSize
		_storage = MemAlloc(Size_T(queueCapacity) * maxPacketSize)
		_randomState = seed
		If _randomState = 0 Then _randomState = $6d2b79f5
		_manualClock = manualClock
		If Not _manualClock Then _nowMillis = UInt(MilliSecs())
	End Method

	Method RefreshClock()
		If Not _manualClock Then _nowMillis = UInt(MilliSecs())
	End Method

	Method RandomUInt:UInt()
		Local value:UInt = _randomState
		value :~ value Shl 13
		value :~ value Shr 17
		value :~ value Shl 5
		_randomState = value
		Return value
	End Method

	Method Happens:Int(probability:UInt)
		If probability = 0 Then Return False
		If probability >= IMPAIRMENT_PROBABILITY_SCALE Then Return True
		Return RandomUInt() Mod IMPAIRMENT_PROBABILITY_SCALE < probability
	End Method

	Method ShouldImpair:Int(delivery:EDeliveryMode)
		Return (_config.deliveryMask & (1 Shl Int(delivery))) <> 0
	End Method

	Method BaseDelay:UInt()
		If _config.jitterMillis = 0 Then Return _config.latencyMillis
		Local span:ULong = ULong(_config.jitterMillis) * 2 + 1
		Local offset:Long = Long(ULong(RandomUInt()) Mod span) - Long(_config.jitterMillis)
		Local delay:Long = Long(_config.latencyMillis) + offset
		If delay < 0 Then Return 0
		Return UInt(delay)
	End Method

	Method TimeAfter:Int(first:UInt, second:UInt)
		Return Int(first - second) > 0
	End Method

	Method FindFree:Int()
		For Local index:Int = 0 Until _packets.Length
			If Not _packets[index].active Then Return index
		Next
		Return -1
	End Method

	Method Schedule:Int(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T, duplicate:Int)
		Local index:Int = FindFree()
		If index < 0 Then Return False

		Local dueAt:UInt = _nowMillis + BaseDelay()
		If _config.bandwidthBytesPerSecond > 0 Then
			If _bandwidthActive And TimeAfter(_bandwidthAt, dueAt) Then dueAt = _bandwidthAt
			Local transmissionMillis:ULong = (ULong(length) * 1000 + ULong(_config.bandwidthBytesPerSecond) - 1) / ULong(_config.bandwidthBytesPerSecond)
			_bandwidthAt = dueAt + UInt(transmissionMillis)
			_bandwidthActive = True
		End If

		If _config.reorderDelayMillis > 0 And Happens(_config.reorderingProbability) Then
			dueAt :+ 1 + RandomUInt() Mod _config.reorderDelayMillis
			_reordered :+ 1
		End If

		_packets[index].active = True
		_packets[index].dueAt = dueAt
		_packets[index].order = _nextOrder
		_packets[index].peer = peer
		_packets[index].channel = channel
		_packets[index].delivery = delivery
		_packets[index].length = length
		_nextOrder :+ 1
		If length > 0 Then MemCopy(_storage + Size_T(index) * _maxPacketSize, data, length)
		_queued :+ 1
		If duplicate Then _duplicated :+ 1
		Return True
	End Method

	Method FindDue:Int()
		Local found:Int = -1
		For Local index:Int = 0 Until _packets.Length
			If Not _packets[index].active Or Int(_nowMillis - _packets[index].dueAt) < 0 Then Continue
			If found < 0 Or TimeAfter(_packets[found].dueAt, _packets[index].dueAt) Or (_packets[found].dueAt = _packets[index].dueAt And _packets[index].order < _packets[found].order) Then found = index
		Next
		Return found
	End Method

	Method Remove(index:Int)
		_packets[index] = New SImpairedPacket
		_queued :- 1
	End Method

	Method FlushDue()
		While Not _pendingError
			Local index:Int = FindDue()
			If index < 0 Then Return
			Local packet:SImpairedPacket = _packets[index]
			Local data:Byte Ptr
			If packet.length > 0 Then data = _storage + Size_T(index) * _maxPacketSize
			Local result:ETransportResult = _inner.Send(packet.peer, packet.channel, packet.delivery, data, packet.length)
			If result = ETransportResult.WouldBlock Then Return
			Remove(index)
			If result = ETransportResult.Ok Then
				_sent :+ 1
			Else
				_sendFailures :+ 1
				_pendingError = IMPAIRMENT_ERROR_SEND_BASE + Int(result)
				_pendingErrorPeer = packet.peer
			End If
		Wend
	End Method

	Method RemovePeer(peer:SNetPeer)
		For Local index:Int = 0 Until _packets.Length
			If _packets[index].active And _packets[index].peer.Equals(peer) Then Remove(index)
		Next
	End Method

	Public
	Method Delete()
		If _storage Then MemFree(_storage)
		_storage = Null
	End Method

	Rem
	bbdoc: Creates a bounded decorator around @inner.
	returns: Null for an invalid transport, capacity, packet size, or probability.
	about: Set @manualClock to True for deterministic tests and call #SetTime
	before sending or polling. Otherwise the monotonic millisecond clock is read
	automatically. The configured packet size must not exceed the backend limit
	when that limit is known.
	End Rem
	Function Create:TImpairedTransport(inner:INetTransport, queueCapacity:Int, maxPacketSize:Size_T, config:SImpairmentConfig, seed:UInt = 1, manualClock:Int = False)
		If Not inner Or queueCapacity < 1 Or maxPacketSize < 1 Then Return Null
		If config.lossProbability > IMPAIRMENT_PROBABILITY_SCALE Or config.duplicationProbability > IMPAIRMENT_PROBABILITY_SCALE Or config.reorderingProbability > IMPAIRMENT_PROBABILITY_SCALE Then Return Null
		If config.latencyMillis >= $80000000 Or config.jitterMillis >= $80000000 Or config.reorderDelayMillis >= $80000000 Then Return Null
		Local maximumDelay:ULong = ULong(config.latencyMillis) + ULong(config.jitterMillis) + ULong(config.reorderDelayMillis)
		If config.bandwidthBytesPerSecond > 0 Then
			Local packetTransmission:ULong = (ULong(maxPacketSize) * 1000 + ULong(config.bandwidthBytesPerSecond) - 1) / ULong(config.bandwidthBytesPerSecond)
			maximumDelay :+ packetTransmission * ULong(queueCapacity)
		End If
		If maximumDelay >= $80000000:ULong Then Return Null
		For Local mode:Int = Int(EDeliveryMode.Unreliable) To Int(EDeliveryMode.ReliableOrdered)
			Local backendMaximum:Size_T = inner.MaxPacketSize(EDeliveryMode(mode))
			If backendMaximum > 0 And maxPacketSize > backendMaximum Then Return Null
		Next
		Return New TImpairedTransport(inner, queueCapacity, maxPacketSize, config, seed, manualClock)
	End Function

	Rem
	bbdoc: Sets the current deterministic time used by a manual-clock decorator.
	returns: False when this decorator uses the automatic system clock.
	End Rem
	Method SetTime:Int(nowMillis:UInt)
		If Not _manualClock Then Return False
		_nowMillis = nowMillis
		Return True
	End Method

	Rem
	bbdoc: Returns cumulative impairment counters.
	End Rem
	Method Stats:SImpairmentStats()
		Return New SImpairmentStats(_queued, _sent, _dropped, _duplicated, _reordered, _queueOverflows, _sendFailures)
	End Method

	Method Poll:Int(event:SNetEvent Var) Override
		RefreshClock()
		FlushDue()
		If _pendingError Then
			event = SNetEvent.Error(_pendingErrorPeer, _pendingError)
			_pendingError = 0
			_pendingErrorPeer = New SNetPeer
			Return True
		End If
		Return _inner.Poll(event)
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T) Override
		RefreshClock()
		If Not _inner.IsOpen() Then Return ETransportResult.Closed
		If length > _maxPacketSize Then Return ETransportResult.PacketTooLarge
		If length > 0 And Not data Then Return ETransportResult.Failed
		If Not ShouldImpair(delivery) Then
			Local directResult:ETransportResult = _inner.Send(peer, channel, delivery, data, length)
			If directResult = ETransportResult.Ok Then _sent :+ 1
			Return directResult
		End If
		If FindFree() < 0 Then
			_queueOverflows :+ 1
			Return ETransportResult.WouldBlock
		End If
		If Happens(_config.lossProbability) Then
			_dropped :+ 1
			Return ETransportResult.Ok
		End If

		Local duplicate:Int = Happens(_config.duplicationProbability)
		If Not Schedule(peer, channel, delivery, data, length, False) Then
			_queueOverflows :+ 1
			Return ETransportResult.WouldBlock
		End If
		If duplicate Then Schedule(peer, channel, delivery, data, length, True)
		FlushDue()
		Return ETransportResult.Ok
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0) Override
		RemovePeer(peer)
		Return _inner.Disconnect(peer, code)
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode) Override
		Return _maxPacketSize
	End Method

	Method IsOpen:Int() Override
		Return _inner And (_inner.IsOpen() Or _queued > 0 Or _pendingError <> 0)
	End Method

	Method Close() Override
		For Local index:Int = 0 Until _packets.Length
			_packets[index] = New SImpairedPacket
		Next
		_queued = 0
		_pendingError = 0
		_bandwidthActive = False
		If _inner Then _inner.Close()
	End Method
End Type
