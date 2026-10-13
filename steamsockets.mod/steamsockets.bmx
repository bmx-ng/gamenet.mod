' Copyright (c) 2026 Bruce A Henderson and contributors
'
' This software is provided 'as-is', without any express or implied
' warranty. In no event will the authors be held liable for any damages.
'
SuperStrict

Rem
bbdoc: Steam Networking Sockets transport for GameNet.
End Rem
Module GameNet.SteamSockets

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"
ModuleInfo "History: 0.1 Initial Steam Networking Sockets transport"

?bmxng2 And Not android And Not ios

Import GameNet.Core
Import Steam.SteamSDK

Const STEAM_SOCKETS_DEFAULT_MAX_PACKET_SIZE:Size_T = 1200
Const STEAM_SOCKETS_FRAME_HEADER_SIZE:Size_T = 12
Const STEAM_SOCKETS_FRAME_MAGIC:UInt = $474E5353 ' GNSS
Const STEAM_SOCKETS_FRAME_VERSION:UInt = 1

Enum ESteamSocketsTransportError:Int
	InvalidFrame = 1
	IncomingPacketTooLarge = 2
	UnknownConnection = 3
	EventQueueFull = 4
	ConnectionFailed = 5
End Enum

Rem
bbdoc: Adapts Steam Networking Sockets to #INetTransport.
about: A transport is either a listener accepting several connections or a
client with one outgoing connection. Steam P2P connections can use direct NAT
traversal or Steam Datagram Relay; IP connections use the supplied numeric
address directly. All storage is bounded at construction.
End Rem
Type TSteamSocketsTransport Implements INetTransport, ISteamNetworkingSocketsListener
	Private
	Field _sockets:TSteamNetworkingSockets
	Field _listenSocket:UInt
	Field _pollGroup:UInt
	Field _connections:UInt[]
	Field _generations:UInt[]
	Field _active:Byte[]
	Field _connected:Byte[]
	Field _remoteSteamIds:ULong[]
	Field _channelCount:Int
	Field _maxPacketSize:Size_T
	Field _wireCapacity:Size_T
	Field _receiveBuffer:Byte Ptr
	Field _sendBuffer:Byte Ptr
	Field _sendSequence:UInt[]
	Field _receiveSequence:UInt[]
	Field _receiveSequenceSeen:Byte[]
	Field _events:SNetEvent[]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _eventOverflow:Int
	Field _open:Int = True

	Method New(sockets:TSteamNetworkingSockets, maxPeers:Int, channelCount:Int, maxPacketSize:Size_T)
		_sockets = sockets
		_channelCount = channelCount
		_maxPacketSize = maxPacketSize
		_wireCapacity = maxPacketSize + STEAM_SOCKETS_FRAME_HEADER_SIZE
		_receiveBuffer = MemAlloc(_wireCapacity)
		_sendBuffer = MemAlloc(_wireCapacity)
		_connections = New UInt[maxPeers]
		_generations = New UInt[maxPeers]
		_active = New Byte[maxPeers]
		_connected = New Byte[maxPeers]
		_remoteSteamIds = New ULong[maxPeers]
		_sendSequence = New UInt[maxPeers * channelCount]
		_receiveSequence = New UInt[maxPeers * channelCount]
		_receiveSequenceSeen = New Byte[maxPeers * channelCount]
		_events = New SNetEvent[Max(8, maxPeers * 4)]
		_pollGroup = _sockets.CreatePollGroup()
		_sockets.SetListener(Self)
	End Method

	Method PeerForSlot:SNetPeer(slot:Int)
		Return New SNetPeer(UInt(slot + 1), _generations[slot])
	End Method

	Method SlotForPeer:Int(peer:SNetPeer)
		If Not peer.IsValid() Or peer.Id() < 1 Or peer.Id() > UInt(_connections.Length) Then Return -1
		Local slot:Int = Int(peer.Id()) - 1
		If Not _active[slot] Or _generations[slot] <> peer.Generation() Then Return -1
		Return slot
	End Method

	Method SlotForConnection:Int(connection:UInt)
		For Local slot:Int = 0 Until _connections.Length
			If _active[slot] And _connections[slot] = connection Then Return slot
		Next
		Return -1
	End Method

	Method AllocateSlot:Int(connection:UInt, remoteSteamID:ULong)
		For Local slot:Int = 0 Until _connections.Length
			If Not _active[slot] Then
				_generations[slot] :+ 1
				If _generations[slot] = 0 Then _generations[slot] = 1
				_connections[slot] = connection
				_remoteSteamIds[slot] = remoteSteamID
				_active[slot] = True
				_connected[slot] = False
				For Local channel:Int = 0 Until _channelCount
					Local index:Int = slot * _channelCount + channel
					_sendSequence[index] = 0
					_receiveSequence[index] = 0
					_receiveSequenceSeen[index] = False
				Next
				Return slot
			End If
		Next
		Return -1
	End Method

	Method QueueEvent:Int(event:SNetEvent)
		If _eventCount = _events.Length Then
			_eventOverflow = True
			Return False
		End If
		_events[_eventWrite] = event
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
		Return True
	End Method

	Method ReleaseSlot(slot:Int, code:Int, reportFailure:Int)
		Local peer:SNetPeer = PeerForSlot(slot)
		If reportFailure Then QueueEvent(SNetEvent.Error(peer, code))
		QueueEvent(SNetEvent.Disconnected(peer, code))
		_sockets.CloseConnection(_connections[slot], 0, "", False)
		_connections[slot] = 0
		_remoteSteamIds[slot] = 0
		_active[slot] = False
		_connected[slot] = False
	End Method

	Method ConfigureConnection:Int(connection:UInt, remoteSteamID:ULong)
		Local slot:Int = AllocateSlot(connection, remoteSteamID)
		If slot < 0 Then Return -1
		If _pollGroup And Not _sockets.SetConnectionPollGroup(connection, _pollGroup) Then
			_connections[slot] = 0
			_remoteSteamIds[slot] = 0
			_active[slot] = False
			_connected[slot] = False
			Return -1
		End If
		Return slot
	End Method

	Method AbandonSlot(slot:Int)
		If slot < 0 Then Return
		_connections[slot] = 0
		_remoteSteamIds[slot] = 0
		_active[slot] = False
		_connected[slot] = False
	End Method

	Method SequenceIndex:Int(slot:Int, channel:UInt)
		Return slot * _channelCount + Int(channel)
	End Method

	Public
	Method Delete()
		Close()
		If _receiveBuffer Then MemFree(_receiveBuffer)
		If _sendBuffer Then MemFree(_sendBuffer)
		_receiveBuffer = Null
		_sendBuffer = Null
	End Method

	Function ListenIP:TSteamSocketsTransport(port:Int, maxPeers:Int = 32, channelCount:Int = 8, address:String = "", maxPacketSize:Size_T = STEAM_SOCKETS_DEFAULT_MAX_PACKET_SIZE, sockets:TSteamNetworkingSockets = Null)
		Local transport:TSteamSocketsTransport = Create(maxPeers, channelCount, maxPacketSize, sockets)
		If Not transport Then Return Null
		transport._listenSocket = transport._sockets.CreateListenSocketIP(address, port)
		If Not transport._listenSocket Then
			transport.Close()
			Return Null
		End If
		Return transport
	End Function

	Function ConnectIP:TSteamSocketsTransport(address:String, port:Int, channelCount:Int = 8, maxPacketSize:Size_T = STEAM_SOCKETS_DEFAULT_MAX_PACKET_SIZE, sockets:TSteamNetworkingSockets = Null)
		Local transport:TSteamSocketsTransport = Create(1, channelCount, maxPacketSize, sockets)
		If Not transport Then Return Null
		Local connection:UInt = transport._sockets.ConnectByIPAddress(address, port)
		If Not connection Or transport.ConfigureConnection(connection, 0) < 0 Then
			transport.Close()
			Return Null
		End If
		Return transport
	End Function

	Function ListenP2P:TSteamSocketsTransport(virtualPort:Int = 0, maxPeers:Int = 8, channelCount:Int = 8, maxPacketSize:Size_T = STEAM_SOCKETS_DEFAULT_MAX_PACKET_SIZE, sockets:TSteamNetworkingSockets = Null)
		Local transport:TSteamSocketsTransport = Create(maxPeers, channelCount, maxPacketSize, sockets)
		If Not transport Then Return Null
		transport._listenSocket = transport._sockets.CreateListenSocketP2P(virtualPort)
		If Not transport._listenSocket Then
			transport.Close()
			Return Null
		End If
		Return transport
	End Function

	Function ConnectP2P:TSteamSocketsTransport(steamID:ULong, virtualPort:Int = 0, channelCount:Int = 8, maxPacketSize:Size_T = STEAM_SOCKETS_DEFAULT_MAX_PACKET_SIZE, sockets:TSteamNetworkingSockets = Null)
		If steamID = 0 Then Return Null
		Local transport:TSteamSocketsTransport = Create(1, channelCount, maxPacketSize, sockets)
		If Not transport Then Return Null
		Local connection:UInt = transport._sockets.ConnectP2P(steamID, virtualPort)
		If Not connection Or transport.ConfigureConnection(connection, steamID) < 0 Then
			transport.Close()
			Return Null
		End If
		Return transport
	End Function

	Function Create:TSteamSocketsTransport(maxPeers:Int, channelCount:Int = 8, maxPacketSize:Size_T = STEAM_SOCKETS_DEFAULT_MAX_PACKET_SIZE, sockets:TSteamNetworkingSockets = Null)
		If maxPeers < 1 Or channelCount < 1 Or channelCount > 65536 Or maxPacketSize < 1 Or maxPacketSize > Size_T($FFFFFFFF) - STEAM_SOCKETS_FRAME_HEADER_SIZE Then Return Null
		If Not sockets Then sockets = TSteamNetworkingSockets.Create()
		If Not sockets Then Return Null
		Local transport:TSteamSocketsTransport = New TSteamSocketsTransport(sockets, maxPeers, channelCount, maxPacketSize)
		If Not transport._receiveBuffer Or Not transport._sendBuffer Or Not transport._pollGroup Then
			transport.Close()
			Return Null
		End If
		Return transport
	End Function

	Method SteamId:ULong(peer:SNetPeer)
		Local slot:Int = SlotForPeer(peer)
		If slot < 0 Then Return 0
		Return _remoteSteamIds[slot]
	End Method

	Method Poll:Int(event:SNetEvent Var) Override
		_sockets.RunCallbacks()
		If _eventCount > 0 Then
			event = _events[_eventRead]
			_events[_eventRead] = New SNetEvent
			_eventRead = (_eventRead + 1) Mod _events.Length
			_eventCount :- 1
			Return True
		End If
		If _eventOverflow Then
			_eventOverflow = False
			event = SNetEvent.Error(New SNetPeer, Int(ESteamSocketsTransportError.EventQueueFull))
			Return True
		End If
		If Not _open Then
			event = New SNetEvent
			Return False
		End If

		While True
			Local connection:UInt
			Local wireLength:UInt
			Local flags:Int
			Local received:Int = _sockets.ReceiveMessageOnPollGroup(_pollGroup, _receiveBuffer, UInt(_wireCapacity), connection, wireLength, flags)
			If received = 0 Then
				event = New SNetEvent
				Return False
			End If
			Local slot:Int = SlotForConnection(connection)
			If slot < 0 Then
				event = SNetEvent.Error(New SNetPeer, Int(ESteamSocketsTransportError.UnknownConnection))
				Return True
			End If
			If received < 0 Then
				event = SNetEvent.Error(PeerForSlot(slot), Int(ESteamSocketsTransportError.IncomingPacketTooLarge))
				Return True
			End If

			Local reader:SPacketReader = New SPacketReader(_receiveBuffer, Size_T(wireLength))
			Local magic:UInt
			Local version:UInt
			Local deliveryValue:UInt
			Local channel:UInt
			Local sequence:UInt
			reader.ReadUInt32(magic)
			reader.ReadUInt8(version)
			reader.ReadUInt8(deliveryValue)
			reader.ReadUInt16(channel)
			reader.ReadUInt32(sequence)
			If reader.Failed() Or magic <> STEAM_SOCKETS_FRAME_MAGIC Or version <> STEAM_SOCKETS_FRAME_VERSION Or deliveryValue > UInt(EDeliveryMode.ReliableOrdered) Or channel >= UInt(_channelCount) Then
				event = SNetEvent.Error(PeerForSlot(slot), Int(ESteamSocketsTransportError.InvalidFrame))
				Return True
			End If
			Local delivery:EDeliveryMode = EDeliveryMode(deliveryValue)
			If delivery = EDeliveryMode.UnreliableSequenced Then
				Local sequenceSlot:Int = SequenceIndex(slot, channel)
				If _receiveSequenceSeen[sequenceSlot] And Int(sequence - _receiveSequence[sequenceSlot]) <= 0 Then Continue
				_receiveSequenceSeen[sequenceSlot] = True
				_receiveSequence[sequenceSlot] = sequence
			End If
			event = SNetEvent.Data(PeerForSlot(slot), channel, delivery, New SPacketView(_receiveBuffer + STEAM_SOCKETS_FRAME_HEADER_SIZE, Size_T(wireLength) - STEAM_SOCKETS_FRAME_HEADER_SIZE))
			Return True
		Wend
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T) Override
		If Not _open Then Return ETransportResult.Closed
		Local slot:Int = SlotForPeer(peer)
		If slot < 0 Or Not _connected[slot] Then Return ETransportResult.InvalidPeer
		If channel >= UInt(_channelCount) Then Return ETransportResult.InvalidChannel
		If length > _maxPacketSize Then Return ETransportResult.PacketTooLarge
		If length > 0 And Not data Then Return ETransportResult.Failed
		Local sequence:UInt
		If delivery = EDeliveryMode.UnreliableSequenced Then
			Local index:Int = SequenceIndex(slot, channel)
			_sendSequence[index] :+ 1
			sequence = _sendSequence[index]
		End If
		Local writer:SPacketWriter = New SPacketWriter(_sendBuffer, _wireCapacity)
		writer.WriteUInt32(STEAM_SOCKETS_FRAME_MAGIC)
		writer.WriteUInt8(STEAM_SOCKETS_FRAME_VERSION)
		writer.WriteUInt8(UInt(delivery))
		writer.WriteUInt16(channel)
		writer.WriteUInt32(sequence)
		writer.WriteBytes(data, length)
		If writer.Failed() Then Return ETransportResult.PacketTooLarge
		Local sendFlags:Int = STEAM_NETWORKING_SEND_UNRELIABLE
		If delivery = EDeliveryMode.ReliableOrdered Then sendFlags = STEAM_NETWORKING_SEND_RELIABLE
		Local messageNumber:Long
		If _sockets.SendMessageToConnection(_connections[slot], _sendBuffer, UInt(writer.Position()), sendFlags, messageNumber) <> EResult.k_EResultOK Then Return ETransportResult.Failed
		Return ETransportResult.Ok
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0) Override
		Local slot:Int = SlotForPeer(peer)
		If slot < 0 Then Return ETransportResult.InvalidPeer
		Local nativeConnection:UInt = _connections[slot]
		Local result:Int = _sockets.CloseConnection(nativeConnection, code, "GameNet disconnect", False)
		Local disconnectedPeer:SNetPeer = PeerForSlot(slot)
		_connections[slot] = 0
		_active[slot] = False
		_connected[slot] = False
		QueueEvent(SNetEvent.Disconnected(disconnectedPeer, code))
		If result Then Return ETransportResult.Ok
		Return ETransportResult.Failed
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode) Override
		Return _maxPacketSize
	End Method

	Method IsOpen:Int() Override
		Return _open Or _eventCount > 0
	End Method

	Method Close() Override
		If Not _open Then Return
		_open = False
		If _sockets Then
			_sockets.SetListener(Null)
			For Local slot:Int = 0 Until _connections.Length
				If _active[slot] Then _sockets.CloseConnection(_connections[slot], 0, "GameNet transport closed", False)
				_active[slot] = False
				_connected[slot] = False
				_connections[slot] = 0
			Next
			If _listenSocket Then _sockets.CloseListenSocket(_listenSocket)
			If _pollGroup Then _sockets.DestroyPollGroup(_pollGroup)
		End If
		_listenSocket = 0
		_pollGroup = 0
	End Method

	Method GetConnectionStatus:EResult(peer:SNetPeer, state:ESteamNetworkingConnectionState Var, endReason:Int Var, endDebug:String Var, ping:Int Var, qualityLocal:Float Var, qualityRemote:Float Var, pendingUnreliable:Int Var, pendingReliable:Int Var, sentUnackedReliable:Int Var, queueTimeMicroseconds:Long Var)
		Local slot:Int = SlotForPeer(peer)
		If slot < 0 Then Return EResult.k_EResultInvalidParam
		Return _sockets.GetConnectionStatus(_connections[slot], state, endReason, endDebug, ping, qualityLocal, qualityRemote, pendingUnreliable, pendingReliable, sentUnackedReliable, queueTimeMicroseconds)
	End Method

	Method OnSteamNetworkingSocketsConnectionStatusChanged(connection:UInt, listenSocket:UInt, remoteSteamID:ULong, oldState:ESteamNetworkingConnectionState, state:ESteamNetworkingConnectionState, endReason:Int, debugMessage:String) Override
		If Not _open Then Return
		Local slot:Int = SlotForConnection(connection)
		If slot < 0 And listenSocket = _listenSocket And state = ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connecting Then
			slot = ConfigureConnection(connection, remoteSteamID)
			If slot < 0 Or _sockets.AcceptConnection(connection) <> EResult.k_EResultOK Then
				AbandonSlot(slot)
				_sockets.CloseConnection(connection, Int(ESteamNetConnectionEnd.k_ESteamNetConnectionEnd_App_Generic), "No GameNet peer capacity", False)
				Return
			End If
		End If
		If slot < 0 Then Return
		Select state
			Case ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connected
				If Not _connected[slot] Then
					_connected[slot] = True
					QueueEvent(SNetEvent.Connected(PeerForSlot(slot)))
				End If
			Case ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_ClosedByPeer
				ReleaseSlot(slot, endReason, False)
			Case ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_ProblemDetectedLocally
				ReleaseSlot(slot, endReason, True)
		End Select
	End Method
End Type

?
