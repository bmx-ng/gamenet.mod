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
bbdoc: ENet transport backend for GameNet.
End Rem
Module GameNet.ENet

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial Release"

Import GameNet.Core
Import Pub.ENet
Import "glue.c"

Extern
	Function bmx_gamenet_enet_address_create:Byte Ptr(address:String, port:Int)
End Extern

Private

Const ENET_DELIVERY_MODES_PER_CHANNEL:UInt = 3
Const ENET_MAX_LOGICAL_CHANNELS:Int = 85
Const ENET_DEFAULT_RELIABLE_PACKET_SIZE:Size_T = 1024 * 1024
Const ENET_DEFAULT_UNRELIABLE_PACKET_SIZE:Size_T = 1200

Struct SENetPeerSlot
	Field peer:Byte Ptr
	Field generation:UInt
	Field connected:Int
End Struct

Public

Rem
bbdoc: A GameNet transport backed by ENet.
about: Create a listening transport with #Listen, or create a client with
#CreateClient and initiate asynchronous connections with #Connect. Successful
connections are reported through #Poll.

GameNet logical channels are mapped to three ENet channels, one for each
#EDeliveryMode. This preserves independent ordering and permits the receiver to
recover the requested delivery mode without adding a packet header.
End Rem
Type TENetTransport Implements INetTransport
	Private
	Field _host:Byte Ptr
	Field _event:ENetEvent
	Field _heldPacket:Byte Ptr
	Field _slots:SENetPeerSlot[]
	Field _logicalChannels:UInt
	Field _physicalChannels:Size_T
	Field _maxReliablePacketSize:Size_T
	Field _maxUnreliablePacketSize:Size_T

	Method New(host:Byte Ptr, maxPeers:Int, logicalChannels:UInt, maxUnreliablePacketSize:Size_T, maxReliablePacketSize:Size_T)
		_host = host
		_event = New ENetEvent
		_slots = New SENetPeerSlot[maxPeers]
		_logicalChannels = logicalChannels
		_physicalChannels = Size_T(logicalChannels * ENET_DELIVERY_MODES_PER_CHANNEL)
		_maxUnreliablePacketSize = maxUnreliablePacketSize
		_maxReliablePacketSize = maxReliablePacketSize
	End Method

	Method ReleaseHeldPacket()
		If _heldPacket Then enet_packet_destroy(_heldPacket)
		_heldPacket = Null
	End Method

	Method FindNativePeer:Int(peer:Byte Ptr)
		For Local index:Int = 0 Until _slots.Length
			If _slots[index].peer = peer Then Return index
		Next
		Return -1
	End Method

	Method AcquirePeer:Int(peer:Byte Ptr, connected:Int)
		For Local index:Int = 0 Until _slots.Length
			If Not _slots[index].peer Then
				_slots[index].generation :+ 1
				If _slots[index].generation = 0 Then _slots[index].generation = 1
				_slots[index].peer = peer
				_slots[index].connected = connected
				Return index
			End If
		Next
		Return -1
	End Method

	Method HandleForSlot:SNetPeer(index:Int)
		Return New SNetPeer(UInt(index + 1), _slots[index].generation)
	End Method

	Method ResolvePeer:Int(peer:SNetPeer, requireConnected:Int = True)
		If Not peer.IsValid() Then Return -1
		Local index:Int = Int(peer.Id()) - 1
		If index < 0 Or index >= _slots.Length Then Return -1
		If Not _slots[index].peer Then Return -1
		If _slots[index].generation <> peer.Generation() Then Return -1
		If requireConnected And Not _slots[index].connected Then Return -1
		Return index
	End Method

	Method DecodePhysicalChannel:Int(physicalChannel:UInt, logicalChannel:UInt Var, delivery:EDeliveryMode Var)
		If physicalChannel >= UInt(_physicalChannels) Then Return False
		logicalChannel = physicalChannel / ENET_DELIVERY_MODES_PER_CHANNEL
		delivery = EDeliveryMode(physicalChannel Mod ENET_DELIVERY_MODES_PER_CHANNEL)
		Return True
	End Method

	Method PacketFlags:UInt(delivery:EDeliveryMode)
		Select delivery
			Case EDeliveryMode.Unreliable
				Return ENET_PACKET_FLAG_UNSEQUENCED
			Case EDeliveryMode.UnreliableSequenced
				Return 0
			Case EDeliveryMode.ReliableOrdered
				Return ENET_PACKET_FLAG_RELIABLE
		End Select
		Return 0
	End Method

	Function CreateTransport:TENetTransport(address:Byte Ptr, maxPeers:Int, logicalChannels:Int, incomingBandwidth:UInt, outgoingBandwidth:UInt, maxUnreliablePacketSize:Size_T, maxReliablePacketSize:Size_T)
		If maxPeers < 1 Then Return Null
		If logicalChannels < 1 Or logicalChannels > ENET_MAX_LOGICAL_CHANNELS Then Return Null
		If maxUnreliablePacketSize < 1 Or maxReliablePacketSize < 1 Then Return Null

		Local physicalChannels:Size_T = Size_T(logicalChannels) * Size_T(ENET_DELIVERY_MODES_PER_CHANNEL)
		Local host:Byte Ptr = enet_host_create(address, Size_T(maxPeers), physicalChannels, incomingBandwidth, outgoingBandwidth)
		If Not host Then Return Null
		Return New TENetTransport(host, maxPeers, UInt(logicalChannels), maxUnreliablePacketSize, maxReliablePacketSize)
	End Function

	Public
	Rem
	bbdoc: Creates an ENet client transport which can initiate connections.
	returns: A new transport, or Null when configuration or native host creation fails.
	End Rem
	Function CreateClient:TENetTransport(maxPeers:Int = 1, logicalChannels:Int = 8, incomingBandwidth:UInt = 0, outgoingBandwidth:UInt = 0, maxUnreliablePacketSize:Size_T = ENET_DEFAULT_UNRELIABLE_PACKET_SIZE, maxReliablePacketSize:Size_T = ENET_DEFAULT_RELIABLE_PACKET_SIZE)
		Return CreateTransport(Null, maxPeers, logicalChannels, incomingBandwidth, outgoingBandwidth, maxUnreliablePacketSize, maxReliablePacketSize)
	End Function

	Rem
	bbdoc: Creates an ENet transport listening at @address and @port.
	returns: A new transport, or Null when configuration, address binding, or native host creation fails.
	about: Use ENET_HOST_ANY as @address to listen on every available interface.
	End Rem
	Function Listen:TENetTransport(port:Int, maxPeers:Int = 32, logicalChannels:Int = 8, address:String = ENET_HOST_ANY, incomingBandwidth:UInt = 0, outgoingBandwidth:UInt = 0, maxUnreliablePacketSize:Size_T = ENET_DEFAULT_UNRELIABLE_PACKET_SIZE, maxReliablePacketSize:Size_T = ENET_DEFAULT_RELIABLE_PACKET_SIZE)
		If port < 0 Or port > 65535 Then Return Null
		Local nativeAddress:Byte Ptr
		If address = ENET_HOST_ANY Then
			nativeAddress = enet_address_create(ENET_HOST_ANY, port)
		Else
			nativeAddress = bmx_gamenet_enet_address_create(address, port)
		End If
		If Not nativeAddress Then Return Null
		Local transport:TENetTransport = CreateTransport(nativeAddress, maxPeers, logicalChannels, incomingBandwidth, outgoingBandwidth, maxUnreliablePacketSize, maxReliablePacketSize)
		enet_address_destroy(nativeAddress)
		Return transport
	End Function

	Rem
	bbdoc: Begins an asynchronous connection to @address and @port.
	returns: Ok when ENet accepted the attempt; completion is reported by #Poll.
	End Rem
	Method Connect:ETransportResult(address:String, port:Int)
		Local peer:SNetPeer
		Return Connect(address, port, peer)
	End Method

	Rem
	bbdoc: Begins an asynchronous connection and writes its pending peer handle.
	returns: Ok when ENet accepted the attempt; completion is reported by #Poll.
	about: The same handle is used by the resulting Connected or Disconnected
event, allowing a failed or timed-out attempt to be correlated.
	End Rem
	Method Connect:ETransportResult(address:String, port:Int, peer:SNetPeer Var)
		peer = New SNetPeer
		If Not _host Then Return ETransportResult.Closed
		If port < 0 Or port > 65535 Then Return ETransportResult.Failed
		Local nativeAddress:Byte Ptr = bmx_gamenet_enet_address_create(address, port)
		If Not nativeAddress Then Return ETransportResult.Failed
		Local nativePeer:Byte Ptr = enet_host_connect(_host, nativeAddress, _physicalChannels, 0)
		enet_address_destroy(nativeAddress)
		If Not nativePeer Then Return ETransportResult.Failed
		Local index:Int = AcquirePeer(nativePeer, False)
		If index < 0 Then
			enet_peer_disconnect(nativePeer, 0)
			Return ETransportResult.WouldBlock
		End If
		peer = HandleForSlot(index)
		Return ETransportResult.Ok
	End Method

	Method Poll:Int(event:SNetEvent Var) Override
		ReleaseHeldPacket()
		If Not _host Then
			event = New SNetEvent
			Return False
		End If

		Repeat
			Local result:Int = enet_host_service(_host, _event.eventPtr, 0)
			If result = 0 Then
				event = New SNetEvent
				Return False
			Else If result < 0 Then
				event = SNetEvent.Error(New SNetPeer, result)
				Return True
			End If

			Select _event.event()
				Case ENET_EVENT_TYPE_CONNECT
					Local index:Int = FindNativePeer(_event.peer())
					If index < 0 Then index = AcquirePeer(_event.peer(), True)
					If index < 0 Then
						enet_peer_disconnect(_event.peer(), 0)
						Continue
					End If
					_slots[index].connected = True
					event = SNetEvent.Connected(HandleForSlot(index))
					Return True

				Case ENET_EVENT_TYPE_DISCONNECT, ENET_EVENT_TYPE_DISCONNECT_TIMEOUT
					Local index:Int = FindNativePeer(_event.peer())
					If index < 0 Then Continue
					Local peer:SNetPeer = HandleForSlot(index)
					_slots[index].peer = Null
					_slots[index].connected = False
					event = SNetEvent.Disconnected(peer, Int(_event.data()))
					Return True

				Case ENET_EVENT_TYPE_RECEIVE
					Local packet:Byte Ptr = _event.packet()
					Local index:Int = FindNativePeer(_event.peer())
					If index < 0 Or Not _slots[index].connected Then
						enet_packet_destroy(packet)
						Continue
					End If

					Local logicalChannel:UInt
					Local delivery:EDeliveryMode
					Local physicalChannel:UInt = UInt(_event.channelID()) & $ff:UInt
					If Not DecodePhysicalChannel(physicalChannel, logicalChannel, delivery) Then
						enet_packet_destroy(packet)
						Continue
					End If

					_heldPacket = packet
					Local view:SPacketView = New SPacketView(bmx_enet_packet_data(packet), bmx_enet_packet_size(packet))
					event = SNetEvent.Data(HandleForSlot(index), logicalChannel, delivery, view)
					Return True
			End Select
		Forever
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T) Override
		If Not _host Then Return ETransportResult.Closed
		Local index:Int = ResolvePeer(peer)
		If index < 0 Then Return ETransportResult.InvalidPeer
		If channel >= _logicalChannels Then Return ETransportResult.InvalidChannel
		If length > MaxPacketSize(delivery) Then Return ETransportResult.PacketTooLarge
		If length > 0 And Not data Then Return ETransportResult.Failed

		Local physicalChannel:UInt = channel * ENET_DELIVERY_MODES_PER_CHANNEL + UInt(delivery)
		If physicalChannel >= UInt(_physicalChannels) Then Return ETransportResult.InvalidChannel
		Local packet:Byte Ptr = enet_packet_create(data, length, PacketFlags(delivery))
		If Not packet Then Return ETransportResult.Failed
		If enet_peer_send(_slots[index].peer, Byte(physicalChannel), packet) < 0 Then
			enet_packet_destroy(packet)
			Return ETransportResult.Failed
		End If
		Return ETransportResult.Ok
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0) Override
		If Not _host Then Return ETransportResult.Closed
		Local index:Int = ResolvePeer(peer, False)
		If index < 0 Then Return ETransportResult.InvalidPeer
		enet_peer_disconnect(_slots[index].peer, UInt(code))
		Return ETransportResult.Ok
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode) Override
		If delivery = EDeliveryMode.ReliableOrdered Then Return _maxReliablePacketSize
		Return _maxUnreliablePacketSize
	End Method

	Rem
	bbdoc: Returns the number of logical channels configured for each peer.
	End Rem
	Method ChannelCount:UInt()
		Return _logicalChannels
	End Method

	Method IsOpen:Int() Override
		Return _host <> Null
	End Method

	Method Close() Override
		ReleaseHeldPacket()
		If _host Then enet_host_destroy(_host)
		_host = Null
		For Local index:Int = 0 Until _slots.Length
			_slots[index].peer = Null
			_slots[index].connected = False
		Next
	End Method

	Method Delete()
		Close()
	End Method
End Type
