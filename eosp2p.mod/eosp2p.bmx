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
'    claim that you wrote the original software.
' 2. Altered source versions must be plainly marked as such.
' 3. This notice may not be removed or altered from any source distribution.

SuperStrict

Rem
bbdoc: Epic Online Services P2P transport for GameNet.
End Rem
Module GameNet.EOSP2P

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"
ModuleInfo "History: 0.1 Initial EOS P2P transport"

?bmxng2 And Not android And Not ios

Import GameNet.Core
Import EOS.SDK

Const EOS_P2P_FRAME_HEADER_SIZE:Size_T = 10
Const EOS_P2P_FRAME_MAGIC:UInt = $4F454E47 ' GNEO in little-endian byte order
Const EOS_P2P_FRAME_VERSION:UInt = 1
Const EOS_P2P_CONTROL_DELIVERY:UInt = 255
Const EOS_P2P_DEFAULT_MAX_PACKET_SIZE:Size_T = EOS_P2P_MAX_PACKET_SIZE - EOS_P2P_FRAME_HEADER_SIZE
Const EOS_P2P_MAX_SKIPPED_PACKETS_PER_POLL:Int = 32

Enum EEOSP2PTransportError:Int
	InvalidFrame = 1
	UnknownPeer = 2
	UnexpectedSocket = 3
	ConnectionInterrupted = 4
	IncomingQueueFull = 5
	BackendFailure = 6
End Enum

Rem
bbdoc: Narrow EOS P2P boundary used by #TEOSP2PTransport.
about: Applications normally use #TEOSP2PTransport.Create. This interface is
public so the transport can be tested without signing in to EOS.
End Rem
Interface IEOSP2PTransportBackend
	Method InstallListeners:Int(requestListener:IEOSP2PConnectionRequestListener, establishedListener:IEOSP2PConnectionEstablishedListener, interruptedListener:IEOSP2PConnectionInterruptedListener, closedListener:IEOSP2PConnectionClosedListener, queueFullListener:IEOSP2PIncomingPacketQueueFullListener)
	Method RemoveListeners()
	Method Pump()
	Method Send:EEOSResult(remoteUserId:TEOSProductUserId, channel:Int, data:Byte[], reliability:EEOSPacketReliability)
	Method Receive:EEOSResult(packet:TEOSP2PPacket Var)
	Method Accept:EEOSResult(remoteUserId:TEOSProductUserId)
	Method ClosePeer:EEOSResult(remoteUserId:TEOSProductUserId)
End Interface

Type TEOSNativeP2PBackend Implements IEOSP2PTransportBackend
	Private
	Field _platform:TEOSPlatform
	Field _p2p:TEOSP2P
	Field _localUserId:TEOSProductUserId
	Field _socketName:String
	Field _pumpPlatform:Int
	Field _requestSubscription:TEOSP2PConnectionRequestSubscription
	Field _establishedSubscription:TEOSP2PConnectionEstablishedSubscription
	Field _interruptedSubscription:TEOSP2PConnectionInterruptedSubscription
	Field _closedSubscription:TEOSP2PConnectionClosedSubscription
	Field _queueFullSubscription:TEOSP2PIncomingPacketQueueFullSubscription

	Public
	Method New(platform:TEOSPlatform, p2p:TEOSP2P, localUserId:TEOSProductUserId, socketName:String, pumpPlatform:Int)
		_platform = platform
		_p2p = p2p
		_localUserId = localUserId
		_socketName = socketName
		_pumpPlatform = pumpPlatform
	End Method

	Method InstallListeners:Int(requestListener:IEOSP2PConnectionRequestListener, establishedListener:IEOSP2PConnectionEstablishedListener, interruptedListener:IEOSP2PConnectionInterruptedListener, closedListener:IEOSP2PConnectionClosedListener, queueFullListener:IEOSP2PIncomingPacketQueueFullListener) Override
		_requestSubscription = _p2p.AddNotifyConnectionRequest(_localUserId, _socketName, requestListener)
		_establishedSubscription = _p2p.AddNotifyConnectionEstablished(_localUserId, _socketName, establishedListener)
		_interruptedSubscription = _p2p.AddNotifyConnectionInterrupted(_localUserId, _socketName, interruptedListener)
		_closedSubscription = _p2p.AddNotifyConnectionClosed(_localUserId, _socketName, closedListener)
		_queueFullSubscription = _p2p.AddNotifyIncomingPacketQueueFull(queueFullListener)
		If Not _requestSubscription Or Not _establishedSubscription Or Not _interruptedSubscription Or Not _closedSubscription Or Not _queueFullSubscription Then
			RemoveListeners()
			Return False
		End If
		Return True
	End Method

	Method RemoveListeners() Override
		If _requestSubscription Then _requestSubscription.Remove()
		If _establishedSubscription Then _establishedSubscription.Remove()
		If _interruptedSubscription Then _interruptedSubscription.Remove()
		If _closedSubscription Then _closedSubscription.Remove()
		If _queueFullSubscription Then _queueFullSubscription.Remove()
		_requestSubscription = Null
		_establishedSubscription = Null
		_interruptedSubscription = Null
		_closedSubscription = Null
		_queueFullSubscription = Null
	End Method

	Method Pump() Override
		If _pumpPlatform And _platform Then _platform.Tick()
	End Method

	Method Send:EEOSResult(remoteUserId:TEOSProductUserId, channel:Int, data:Byte[], reliability:EEOSPacketReliability) Override
		Local options:TEOSP2PSendOptions = New TEOSP2PSendOptions
		options.LocalUserId = _localUserId
		options.RemoteUserId = remoteUserId
		options.SocketName = _socketName
		options.Channel = channel
		options.Data = data
		options.AllowDelayedDelivery = True
		options.Reliability = reliability
		options.DisableAutoAcceptConnection = True
		Return _p2p.SendPacket(options)
	End Method

	Method Receive:EEOSResult(packet:TEOSP2PPacket Var) Override
		Return _p2p.ReceivePacket(_localUserId, -1, packet)
	End Method

	Method Accept:EEOSResult(remoteUserId:TEOSProductUserId) Override
		Return _p2p.AcceptConnection(_localUserId, remoteUserId, _socketName)
	End Method

	Method ClosePeer:EEOSResult(remoteUserId:TEOSProductUserId) Override
		Return _p2p.CloseConnection(_localUserId, remoteUserId, _socketName)
	End Method
End Type

Rem
bbdoc: Adapts an EOS P2P socket to #INetTransport.
about: Remote Product User IDs are fixed when the transport is created. Poll
can tick the EOS platform, or that responsibility can remain with a containing
online service. The transport is the sole receiver for its local Product User
ID; do not have another object consume the same EOS P2P receive queue.
End Rem
Type TEOSP2PTransport Implements INetTransport, IEOSP2PConnectionRequestListener, IEOSP2PConnectionEstablishedListener, IEOSP2PConnectionInterruptedListener, IEOSP2PConnectionClosedListener, IEOSP2PIncomingPacketQueueFullListener
	Private
	Field _backend:IEOSP2PTransportBackend
	Field _remoteUserIds:TEOSProductUserId[]
	Field _remoteIdText:String[]
	Field _socketName:String
	Field _channelCount:Int
	Field _maxPacketSize:Size_T
	Field _active:Byte[]
	Field _pendingConnected:Byte[]
	Field _pendingDisconnected:Byte[]
	Field _pendingDisconnectCode:Int[]
	Field _pendingError:Byte[]
	Field _pendingErrorCode:Int[]
	Field _sendSequence:UInt[]
	Field _receiveSequence:UInt[]
	Field _receiveSequenceSeen:Byte[]
	Field _receivePacket:TEOSP2PPacket
	Field _open:Int = True
	Field _globalError:Int

	Method New(backend:IEOSP2PTransportBackend, remoteUserIds:TEOSProductUserId[], socketName:String, channelCount:Int, maxPacketSize:Size_T)
		_backend = backend
		_remoteUserIds = remoteUserIds[..]
		_remoteIdText = New String[remoteUserIds.Length]
		_socketName = socketName
		_channelCount = channelCount
		_maxPacketSize = maxPacketSize
		_active = New Byte[remoteUserIds.Length]
		_pendingConnected = New Byte[remoteUserIds.Length]
		_pendingDisconnected = New Byte[remoteUserIds.Length]
		_pendingDisconnectCode = New Int[remoteUserIds.Length]
		_pendingError = New Byte[remoteUserIds.Length]
		_pendingErrorCode = New Int[remoteUserIds.Length]
		_sendSequence = New UInt[channelCount]
		_receiveSequence = New UInt[remoteUserIds.Length * channelCount]
		_receiveSequenceSeen = New Byte[remoteUserIds.Length * channelCount]
		For Local index:Int = 0 Until remoteUserIds.Length
			_remoteIdText[index] = remoteUserIds[index].ToString()
		Next
	End Method

	Method PeerForIndex:SNetPeer(index:Int)
		Return New SNetPeer(UInt(index + 1), 1)
	End Method

	Method PeerIndex:Int(peer:SNetPeer)
		If Not peer.IsValid() Or peer.Generation() <> 1 Or peer.Id() < 1 Or peer.Id() > UInt(_remoteUserIds.Length) Then Return -1
		Return Int(peer.Id()) - 1
	End Method

	Method PeerIndexForUser:Int(userId:TEOSProductUserId)
		If Not userId Then Return -1
		Local value:String = userId.ToString()
		For Local index:Int = 0 Until _remoteIdText.Length
			If _remoteIdText[index] = value Then Return index
		Next
		Return -1
	End Method

	Method SequenceIndex:Int(peerIndex:Int, channel:UInt)
		Return peerIndex * _channelCount + Int(channel)
	End Method

	Method NextPending:Int(values:Byte[])
		For Local index:Int = 0 Until values.Length
			If values[index] Then Return index
		Next
		Return -1
	End Method

	Method BuildFrame:Byte[](delivery:UInt, sequence:UInt, data:Byte Ptr = Null, length:Size_T = 0)
		Local frame:Byte[] = New Byte[Int(EOS_P2P_FRAME_HEADER_SIZE + length)]
		Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(frame), Size_T(frame.Length))
		writer.WriteUInt32(EOS_P2P_FRAME_MAGIC)
		writer.WriteUInt8(EOS_P2P_FRAME_VERSION)
		writer.WriteUInt8(delivery)
		writer.WriteUInt32(sequence)
		writer.WriteBytes(data, length)
		Return frame
	End Method

	Method Start:Int()
		If Not _backend.InstallListeners(Self, Self, Self, Self, Self) Then Return False
		Local probe:Byte[] = BuildFrame(EOS_P2P_CONTROL_DELIVERY, 0)
		For Local index:Int = 0 Until _remoteUserIds.Length
			Local result:EEOSResult = _backend.Send(_remoteUserIds[index], 0, probe, EEOSPacketReliability.ReliableOrdered)
			If result <> EEOSResult.Success Then
				_backend.RemoveListeners()
				Return False
			End If
		Next
		Return True
	End Method

	Method EmitPending:Int(event:SNetEvent Var)
		Local index:Int = NextPending(_pendingConnected)
		If index >= 0 Then
			_pendingConnected[index] = False
			event = SNetEvent.Connected(PeerForIndex(index))
			Return True
		End If
		index = NextPending(_pendingDisconnected)
		If index >= 0 Then
			_pendingDisconnected[index] = False
			event = SNetEvent.Disconnected(PeerForIndex(index), _pendingDisconnectCode[index])
			Return True
		End If
		index = NextPending(_pendingError)
		If index >= 0 Then
			_pendingError[index] = False
			event = SNetEvent.Error(PeerForIndex(index), _pendingErrorCode[index])
			Return True
		End If
		If _globalError Then
			Local code:Int = _globalError
			_globalError = 0
			event = SNetEvent.Error(New SNetPeer, code)
			Return True
		End If
		Return False
	End Method

	Public
	Function Create:TEOSP2PTransport(platform:TEOSPlatform, p2p:TEOSP2P, localUserId:TEOSProductUserId, remoteUserIds:TEOSProductUserId[], socketName:String, channelCount:Int = 4, maxPacketSize:Size_T = EOS_P2P_DEFAULT_MAX_PACKET_SIZE, pumpPlatform:Int = True)
		If Not platform Or Not platform.IsValid() Or Not p2p Or Not localUserId Or Not localUserId.IsValid() Then Return Null
		Local backend:IEOSP2PTransportBackend = New TEOSNativeP2PBackend(platform, p2p, localUserId, socketName, pumpPlatform)
		Return CreateWithBackend(remoteUserIds, socketName, channelCount, maxPacketSize, backend)
	End Function

	Function CreateWithBackend:TEOSP2PTransport(remoteUserIds:TEOSProductUserId[], socketName:String, channelCount:Int, maxPacketSize:Size_T, backend:IEOSP2PTransportBackend)
		If Not backend Or Not remoteUserIds Or remoteUserIds.Length = 0 Or remoteUserIds.Length > EOS_P2P_MAX_CONNECTIONS Then Return Null
		If socketName.Length < 1 Or socketName.Length > 32 Or channelCount < 1 Or channelCount > 256 Then Return Null
		If maxPacketSize < 1 Or maxPacketSize > EOS_P2P_DEFAULT_MAX_PACKET_SIZE Then Return Null
		Local idText:String[] = New String[remoteUserIds.Length]
		For Local index:Int = 0 Until remoteUserIds.Length
			If Not remoteUserIds[index] Or Not remoteUserIds[index].IsValid() Then Return Null
			idText[index] = remoteUserIds[index].ToString()
			For Local earlier:Int = 0 Until index
				If idText[earlier] = idText[index] Then Return Null
			Next
		Next
		Local transport:TEOSP2PTransport = New TEOSP2PTransport(backend, remoteUserIds, socketName, channelCount, maxPacketSize)
		If Not transport.Start() Then Return Null
		Return transport
	End Function

	Method ProductUserId:TEOSProductUserId(peer:SNetPeer)
		Local index:Int = PeerIndex(peer)
		If index < 0 Then Return Null
		Return _remoteUserIds[index]
	End Method

	Method Poll:Int(event:SNetEvent Var) Override
		_receivePacket = Null
		If _open Then _backend.Pump()
		If EmitPending(event) Then Return True
		If Not _open Then
			event = New SNetEvent
			Return False
		End If

		For Local skipped:Int = 0 Until EOS_P2P_MAX_SKIPPED_PACKETS_PER_POLL
			Local result:EEOSResult = _backend.Receive(_receivePacket)
			If result = EEOSResult.NotFound Then Exit
			If result <> EEOSResult.Success Or Not _receivePacket Then
				event = SNetEvent.Error(New SNetPeer, Int(EEOSP2PTransportError.BackendFailure))
				Return True
			End If
			Local peerIndex:Int = PeerIndexForUser(_receivePacket.RemoteUserId)
			If peerIndex < 0 Then
				event = SNetEvent.Error(New SNetPeer, Int(EEOSP2PTransportError.UnknownPeer))
				Return True
			End If
			If _receivePacket.SocketName <> _socketName Then
				event = SNetEvent.Error(PeerForIndex(peerIndex), Int(EEOSP2PTransportError.UnexpectedSocket))
				Return True
			End If
			If _receivePacket.Channel < 0 Or _receivePacket.Channel >= _channelCount Or Not _receivePacket.Data Or _receivePacket.Data.Length < Int(EOS_P2P_FRAME_HEADER_SIZE) Then
				event = SNetEvent.Error(PeerForIndex(peerIndex), Int(EEOSP2PTransportError.InvalidFrame))
				Return True
			End If
			Local reader:SPacketReader = New SPacketReader(Byte Ptr(_receivePacket.Data), Size_T(_receivePacket.Data.Length))
			Local magic:UInt, version:UInt, deliveryValue:UInt, sequence:UInt
			reader.ReadUInt32(magic)
			reader.ReadUInt8(version)
			reader.ReadUInt8(deliveryValue)
			reader.ReadUInt32(sequence)
			If reader.Failed() Or magic <> EOS_P2P_FRAME_MAGIC Or version <> EOS_P2P_FRAME_VERSION Then
				event = SNetEvent.Error(PeerForIndex(peerIndex), Int(EEOSP2PTransportError.InvalidFrame))
				Return True
			End If
			If deliveryValue = EOS_P2P_CONTROL_DELIVERY Then Continue
			If deliveryValue > UInt(EDeliveryMode.ReliableOrdered) Or Not _active[peerIndex] Then
				event = SNetEvent.Error(PeerForIndex(peerIndex), Int(EEOSP2PTransportError.InvalidFrame))
				Return True
			End If
			Local delivery:EDeliveryMode = EDeliveryMode(deliveryValue)
			If delivery = EDeliveryMode.UnreliableSequenced Then
				Local sequenceIndex:Int = SequenceIndex(peerIndex, UInt(_receivePacket.Channel))
				If _receiveSequenceSeen[sequenceIndex] And Int(sequence - _receiveSequence[sequenceIndex]) <= 0 Then Continue
				_receiveSequenceSeen[sequenceIndex] = True
				_receiveSequence[sequenceIndex] = sequence
			End If
			event = SNetEvent.Data(PeerForIndex(peerIndex), UInt(_receivePacket.Channel), delivery, New SPacketView(Byte Ptr(_receivePacket.Data) + EOS_P2P_FRAME_HEADER_SIZE, Size_T(_receivePacket.Data.Length) - EOS_P2P_FRAME_HEADER_SIZE))
			Return True
		Next
		event = New SNetEvent
		Return False
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T) Override
		If Not _open Then Return ETransportResult.Closed
		Local peerIndex:Int = PeerIndex(peer)
		If peerIndex < 0 Or Not _active[peerIndex] Then Return ETransportResult.InvalidPeer
		If channel >= UInt(_channelCount) Then Return ETransportResult.InvalidChannel
		If length > _maxPacketSize Then Return ETransportResult.PacketTooLarge
		If length > 0 And Not data Then Return ETransportResult.Failed
		If delivery < EDeliveryMode.Unreliable Or delivery > EDeliveryMode.ReliableOrdered Then Return ETransportResult.Failed
		Local sequence:UInt
		If delivery = EDeliveryMode.UnreliableSequenced Then
			_sendSequence[Int(channel)] :+ 1
			sequence = _sendSequence[Int(channel)]
		End If
		Local frame:Byte[] = BuildFrame(UInt(delivery), sequence, data, length)
		Local reliability:EEOSPacketReliability = EEOSPacketReliability.UnreliableUnordered
		If delivery = EDeliveryMode.ReliableOrdered Then reliability = EEOSPacketReliability.ReliableOrdered
		Local result:EEOSResult = _backend.Send(_remoteUserIds[peerIndex], Int(channel), frame, reliability)
		Select result
			Case EEOSResult.Success
				Return ETransportResult.Ok
			Case EEOSResult.NoConnection, EEOSResult.OperationWillRetry, EEOSResult.LimitExceeded, EEOSResult.TooManyRequests
				Return ETransportResult.WouldBlock
		End Select
		Return ETransportResult.Failed
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0) Override
		If Not _open Then Return ETransportResult.Closed
		Local index:Int = PeerIndex(peer)
		If index < 0 Or Not _active[index] Then Return ETransportResult.InvalidPeer
		Local result:EEOSResult = _backend.ClosePeer(_remoteUserIds[index])
		If result <> EEOSResult.Success And result <> EEOSResult.NotFound Then Return ETransportResult.Failed
		_active[index] = False
		_pendingDisconnected[index] = True
		_pendingDisconnectCode[index] = code
		Return ETransportResult.Ok
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode) Override Return _maxPacketSize End Method
	Method IsOpen:Int() Override Return _open Or NextPending(_pendingDisconnected) >= 0 End Method

	Method Close() Override
		If Not _open Then Return
		_open = False
		_backend.RemoveListeners()
		For Local index:Int = 0 Until _remoteUserIds.Length
			If _active[index] Then _backend.ClosePeer(_remoteUserIds[index])
			_active[index] = False
		Next
	End Method

	Method Delete()
		Close()
	End Method

	Method OnEOSP2PConnectionRequest(localUserId:TEOSProductUserId, remoteUserId:TEOSProductUserId, socketName:String) Override
		If Not _open Or socketName <> _socketName Then Return
		Local index:Int = PeerIndexForUser(remoteUserId)
		If index >= 0 Then _backend.Accept(_remoteUserIds[index])
	End Method

	Method OnEOSP2PConnectionEstablished(localUserId:TEOSProductUserId, remoteUserId:TEOSProductUserId, socketName:String, connectionType:EEOSConnectionEstablishedType, networkType:EEOSNetworkConnectionType) Override
		If Not _open Or socketName <> _socketName Then Return
		Local index:Int = PeerIndexForUser(remoteUserId)
		If index < 0 Then Return
		If Not _active[index] Then _pendingConnected[index] = True
		_active[index] = True
	End Method

	Method OnEOSP2PConnectionInterrupted(localUserId:TEOSProductUserId, remoteUserId:TEOSProductUserId, socketName:String) Override
		If Not _open Or socketName <> _socketName Then Return
		Local index:Int = PeerIndexForUser(remoteUserId)
		If index < 0 Then Return
		_pendingError[index] = True
		_pendingErrorCode[index] = Int(EEOSP2PTransportError.ConnectionInterrupted)
	End Method

	Method OnEOSP2PConnectionClosed(localUserId:TEOSProductUserId, remoteUserId:TEOSProductUserId, socketName:String, reason:EEOSConnectionClosedReason) Override
		If socketName <> _socketName Then Return
		Local index:Int = PeerIndexForUser(remoteUserId)
		If index < 0 Or (Not _active[index] And _pendingDisconnected[index]) Then Return
		_active[index] = False
		_pendingDisconnected[index] = True
		_pendingDisconnectCode[index] = Int(reason)
	End Method

	Method OnEOSP2PIncomingPacketQueueFull(maxSizeBytes:ULong, currentSizeBytes:ULong, localUserId:TEOSProductUserId, channel:Int, packetSizeBytes:UInt) Override
		If _open Then _globalError = Int(EEOSP2PTransportError.IncomingQueueFull)
	End Method
End Type

?
