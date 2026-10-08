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
bbdoc: Preallocated in-process GameNet transport.
End Rem
Module GameNet.Loopback

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial Release"

Import GameNet.Core
Import BRL.Blitz

Private

Struct SLoopbackEvent
	Field kind:ENetEventKind
	Field peer:SNetPeer
	Field channel:UInt
	Field delivery:EDeliveryMode
	Field length:Size_T
	Field code:Int

	Method New(kind:ENetEventKind, peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, length:Size_T, code:Int)
		Self.kind = kind
		Self.peer = peer
		Self.channel = channel
		Self.delivery = delivery
		Self.length = length
		Self.code = code
	End Method
End Struct

Public

Rem
bbdoc: One endpoint of an in-process connection created by #TLoopbackPair.
about: Packet storage and event metadata are allocated when the pair is
created. Sending and polling within the configured limits perform no managed
allocation.
End Rem
Type TLoopbackTransport Implements INetTransport
	Private
	Field _events:SLoopbackEvent[]
	Field _storage:Byte Ptr
	Field _maxPacketSize:Size_T
	Field _readIndex:Int
	Field _writeIndex:Int
	Field _queued:Int
	Field _used:Int
	Field _held:Int
	Field _active:Int = True
	Field _peer:SNetPeer
	Field _remote:TLoopbackTransport

	Method New(queueCapacity:Int, maxPacketSize:Size_T)
		_events = New SLoopbackEvent[queueCapacity]
		_maxPacketSize = maxPacketSize
		If maxPacketSize > 0 Then
			_storage = MemAlloc(Size_T(queueCapacity) * maxPacketSize)
		End If
		_peer = New SNetPeer(1, 1)
	End Method

	Method Delete()
		If _storage Then MemFree(_storage)
		_storage = Null
	End Method

	Method CanQueue:Int()
		Return _used < _events.Length
	End Method

	Method AdvanceWrite()
		_writeIndex :+ 1
		If _writeIndex = _events.Length Then _writeIndex = 0
		_queued :+ 1
		_used :+ 1
	End Method

	Method QueueControl:ETransportResult(kind:ENetEventKind, peer:SNetPeer, code:Int = 0)
		If Not CanQueue() Then Return ETransportResult.WouldBlock
		_events[_writeIndex] = New SLoopbackEvent(kind, peer, 0, EDeliveryMode.Unreliable, 0, code)
		AdvanceWrite()
		Return ETransportResult.Ok
	End Method

	Method QueueData:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T)
		If Not _active Then Return ETransportResult.Closed
		If length > _maxPacketSize Then Return ETransportResult.PacketTooLarge
		If length > 0 And Not data Then Return ETransportResult.Failed
		If Not CanQueue() Then Return ETransportResult.WouldBlock

		If length > 0 Then
			Local destination:Byte Ptr = _storage + Size_T(_writeIndex) * _maxPacketSize
			MemCopy(destination, data, length)
		End If
		_events[_writeIndex] = New SLoopbackEvent(ENetEventKind.Data, peer, channel, delivery, length, 0)
		AdvanceWrite()
		Return ETransportResult.Ok
	End Method

	Method MatchesPeer:Int(peer:SNetPeer)
		Return peer.IsValid() And peer.Equals(_peer)
	End Method

	Public
	Function _Create:TLoopbackTransport(queueCapacity:Int, maxPacketSize:Size_T)
		Return New TLoopbackTransport(queueCapacity, maxPacketSize)
	End Function

	Method _Attach(remote:TLoopbackTransport)
		_remote = remote
	End Method

	Method _Start()
		QueueControl(ENetEventKind.Connected, _peer)
	End Method

	Rem
	bbdoc: Returns the handle representing this endpoint's remote peer.
	End Rem
	Method RemotePeer:SNetPeer()
		Return _peer
	End Method

	Method Poll:Int(event:SNetEvent Var) Override
		' Releasing the previously returned slot invalidates its borrowed view.
		If _held Then
			_held = False
			_used :- 1
		End If

		If _queued = 0 Then
			event = New SNetEvent
			Return False
		End If

		Local index:Int = _readIndex
		Local queuedEvent:SLoopbackEvent = _events[index]
		_readIndex :+ 1
		If _readIndex = _events.Length Then _readIndex = 0
		_queued :- 1
		_held = True

		Select queuedEvent.kind
			Case ENetEventKind.Connected
				event = SNetEvent.Connected(queuedEvent.peer)
			Case ENetEventKind.Disconnected
				event = SNetEvent.Disconnected(queuedEvent.peer, queuedEvent.code)
			Case ENetEventKind.Data
				Local data:Byte Ptr
				If queuedEvent.length > 0 Then data = _storage + Size_T(index) * _maxPacketSize
				event = SNetEvent.Data(queuedEvent.peer, queuedEvent.channel, queuedEvent.delivery, New SPacketView(data, queuedEvent.length))
			Case ENetEventKind.Error
				event = SNetEvent.Error(queuedEvent.peer, queuedEvent.code)
			Default
				event = New SNetEvent
		End Select
		Return True
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T) Override
		If Not _active Or Not _remote Or Not _remote._active Then Return ETransportResult.Closed
		If Not MatchesPeer(peer) Then Return ETransportResult.InvalidPeer
		Return _remote.QueueData(_remote._peer, channel, delivery, data, length)
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0) Override
		If Not _active Or Not _remote Or Not _remote._active Then Return ETransportResult.Closed
		If Not MatchesPeer(peer) Then Return ETransportResult.InvalidPeer
		If Not CanQueue() Or Not _remote.CanQueue() Then Return ETransportResult.WouldBlock

		QueueControl(ENetEventKind.Disconnected, _peer, code)
		_remote.QueueControl(ENetEventKind.Disconnected, _remote._peer, code)
		_active = False
		_remote._active = False
		Return ETransportResult.Ok
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode) Override
		Return _maxPacketSize
	End Method

	Method IsOpen:Int() Override
		Return _active Or _queued > 0 Or _held
	End Method

	Method Close() Override
		If Not _active Then Return
		If _remote And _remote._active And CanQueue() And _remote.CanQueue() Then
			QueueControl(ENetEventKind.Disconnected, _peer, 0)
			_remote.QueueControl(ENetEventKind.Disconnected, _remote._peer, 0)
			_remote._active = False
		End If
		_active = False
	End Method
End Type

Rem
bbdoc: Owns two connected #TLoopbackTransport endpoints.
End Rem
Type TLoopbackPair
	Private
	Field _first:TLoopbackTransport
	Field _second:TLoopbackTransport

	Method New(queueCapacity:Int, maxPacketSize:Size_T)
		_first = TLoopbackTransport._Create(queueCapacity, maxPacketSize)
		_second = TLoopbackTransport._Create(queueCapacity, maxPacketSize)
		_first._Attach(_second)
		_second._Attach(_first)
		_first._Start()
		_second._Start()
	End Method

	Public
	Rem
	bbdoc: Creates a connected pair with bounded event and packet storage.
	returns: A new pair, or Null when either argument is less than one.
	End Rem
	Function Create:TLoopbackPair(queueCapacity:Int = 64, maxPacketSize:Size_T = 1200)
		If queueCapacity < 1 Or maxPacketSize < 1 Then Return Null
		Return New TLoopbackPair(queueCapacity, maxPacketSize)
	End Function

	Rem
	bbdoc: Returns the first concrete endpoint.
	End Rem
	Method First:TLoopbackTransport()
		Return _first
	End Method

	Rem
	bbdoc: Returns the second concrete endpoint.
	End Rem
	Method Second:TLoopbackTransport()
		Return _second
	End Method

	Rem
	bbdoc: Closes both endpoints.
	End Rem
	Method Close()
		If _first Then _first.Close()
		If _second Then _second.Close()
	End Method
End Type
