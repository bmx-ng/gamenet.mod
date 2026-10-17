SuperStrict

Framework GameNet.EOSP2P
Import BRL.StandardIO

Function Check(condition:Int, message:String)
	If Not condition Then Throw "FAILED: " + message
End Function

Type TMockEOSP2PBackend Implements IEOSP2PTransportBackend
	Field requestListener:IEOSP2PConnectionRequestListener
	Field establishedListener:IEOSP2PConnectionEstablishedListener
	Field interruptedListener:IEOSP2PConnectionInterruptedListener
	Field closedListener:IEOSP2PConnectionClosedListener
	Field queueFullListener:IEOSP2PIncomingPacketQueueFullListener
	Field sent:Byte[]
	Field sentUserId:TEOSProductUserId
	Field sentChannel:Int
	Field sentReliability:EEOSPacketReliability
	Field incoming:TEOSP2PPacket
	Field accepted:TEOSProductUserId
	Field closed:TEOSProductUserId

	Method InstallListeners:Int(request:IEOSP2PConnectionRequestListener, established:IEOSP2PConnectionEstablishedListener, interrupted:IEOSP2PConnectionInterruptedListener, connectionClosed:IEOSP2PConnectionClosedListener, queueFull:IEOSP2PIncomingPacketQueueFullListener) Override
		requestListener = request
		establishedListener = established
		interruptedListener = interrupted
		closedListener = connectionClosed
		queueFullListener = queueFull
		Return True
	End Method

	Method RemoveListeners() Override
		requestListener = Null
		establishedListener = Null
		interruptedListener = Null
		closedListener = Null
		queueFullListener = Null
	End Method

	Method Pump() Override
	End Method

	Method Send:EEOSResult(remoteUserId:TEOSProductUserId, channel:Int, data:Byte[], reliability:EEOSPacketReliability) Override
		sentUserId = remoteUserId
		sentChannel = channel
		sent = data[..]
		sentReliability = reliability
		Return EEOSResult.Success
	End Method

	Method Receive:EEOSResult(packet:TEOSP2PPacket Var) Override
		If Not incoming Then
			packet = Null
			Return EEOSResult.NotFound
		End If
		packet = incoming
		incoming = Null
		Return EEOSResult.Success
	End Method

	Method Accept:EEOSResult(remoteUserId:TEOSProductUserId) Override
		accepted = remoteUserId
		Return EEOSResult.Success
	End Method

	Method ClosePeer:EEOSResult(remoteUserId:TEOSProductUserId) Override
		closed = remoteUserId
		Return EEOSResult.Success
	End Method

	Method QueueLastSend(remoteUserId:TEOSProductUserId, socketName:String)
		incoming = New TEOSP2PPacket
		incoming.RemoteUserId = remoteUserId
		incoming.SocketName = socketName
		incoming.Channel = sentChannel
		incoming.Data = sent[..]
	End Method
End Type

Local initializeOptions:TEOSInitializeOptions = New TEOSInitializeOptions
initializeOptions.ProductName = "GameNet.EOSP2P tests"
initializeOptions.ProductVersion = "0.1.0"
Check(EOSInitialize(initializeOptions) = EEOSResult.Success, "initialize EOS SDK")

Local remoteId:TEOSProductUserId = TEOSProductUserId.FromString("0123456789abcdef0123456789abcdef")
Check(remoteId And remoteId.IsValid(), "create test Product User ID")

Local backend:TMockEOSP2PBackend = New TMockEOSP2PBackend
Local transport:TEOSP2PTransport = TEOSP2PTransport.CreateWithBackend([remoteId], "GAMENET", 2, 64, backend)
Check(transport <> Null, "create transport")
Check(backend.sent And backend.sent.Length = Int(EOS_P2P_FRAME_HEADER_SIZE), "send connection probe")

backend.requestListener.OnEOSP2PConnectionRequest(Null, remoteId, "GAMENET")
Check(backend.accepted = remoteId, "accept known peer request")
backend.establishedListener.OnEOSP2PConnectionEstablished(Null, remoteId, "GAMENET", EEOSConnectionEstablishedType.NewConnection, EEOSNetworkConnectionType.DirectConnection)

Local event:SNetEvent
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Connected, "connection event")
Local peer:SNetPeer = event.Peer()
Check(transport.ProductUserId(peer) = remoteId, "map peer to Product User ID")

Local payload:Byte[] = [Byte(10), Byte(20), Byte(30)]
Check(transport.Send(peer, 1, EDeliveryMode.UnreliableSequenced, Byte Ptr(payload), Size_T(payload.Length)) = ETransportResult.Ok, "send sequenced packet")
Check(backend.sentChannel = 1 And backend.sentReliability = EEOSPacketReliability.UnreliableUnordered, "map channel and unreliable delivery")
backend.QueueLastSend(remoteId, "GAMENET")
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Data, "receive packet")
Check(event.Delivery() = EDeliveryMode.UnreliableSequenced And event.Channel() = 1 And event.Packet().Length() = 3, "preserve frame metadata")
Check(event.Packet().Data()[0] = 10 And event.Packet().Data()[2] = 30, "preserve payload")

backend.QueueLastSend(remoteId, "GAMENET")
Check(Not transport.Poll(event), "discard stale sequenced packet")

Check(transport.Send(peer, 0, EDeliveryMode.ReliableOrdered, Byte Ptr(payload), Size_T(payload.Length)) = ETransportResult.Ok, "send reliable packet")
Check(backend.sentReliability = EEOSPacketReliability.ReliableOrdered, "map reliable delivery")
Check(transport.Disconnect(peer, 7) = ETransportResult.Ok, "disconnect peer")
Check(backend.closed = remoteId, "close EOS peer")
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 7, "disconnect event")

transport.Close()
Check(EOSShutdown() = EEOSResult.Success, "shut down EOS SDK")
Print "GameNet.EOSP2P tests passed"
