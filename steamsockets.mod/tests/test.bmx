SuperStrict

Framework GameNet.SteamSockets
Import BRL.StandardIO

Function Check(condition:Int, message:String)
	If Not condition Then Throw "FAILED: " + message
End Function

Type TMockSteamSockets Extends TSteamNetworkingSockets
	Const MAX_CALLBACKS:Int = 64
	Const MAX_MESSAGES:Int = 16
	Const MESSAGE_CAPACITY:Int = 2048

	Field target:ISteamNetworkingSocketsListener
	Field nextConnection:UInt = 41
	Field nextListenSocket:UInt = 71
	Field createPollGroupResult:UInt = 91
	Field acceptResult:EResult = EResult.k_EResultOK
	Field sendResult:EResult = EResult.k_EResultOK
	Field closeResult:Int = True
	Field acceptedConnection:UInt
	Field closedConnection:UInt
	Field closedReason:Int
	Field closedListenSocket:UInt
	Field destroyedPollGroup:UInt
	Field lastConnectAddress:String
	Field lastConnectPort:Int
	Field lastP2PSteamId:ULong
	Field lastP2PPort:Int
	Field lastSendConnection:UInt
	Field lastSendFlags:Int
	Field lastSendLength:UInt
	Field lastSend:Byte[MESSAGE_CAPACITY]
	Field callbackConnection:UInt[MAX_CALLBACKS]
	Field callbackListenSocket:UInt[MAX_CALLBACKS]
	Field callbackRemoteSteamId:ULong[MAX_CALLBACKS]
	Field callbackOldState:ESteamNetworkingConnectionState[MAX_CALLBACKS]
	Field callbackState:ESteamNetworkingConnectionState[MAX_CALLBACKS]
	Field callbackReason:Int[MAX_CALLBACKS]
	Field callbackCount:Int
	Field messageConnection:UInt[MAX_MESSAGES]
	Field messageLength:UInt[MAX_MESSAGES]
	Field messageResult:Int[MAX_MESSAGES]
	Field messageStorage:Byte[MAX_MESSAGES * MESSAGE_CAPACITY]
	Field messageRead:Int
	Field messageWrite:Int
	Field messageCount:Int

	Method QueueStatus(connection:UInt, listenSocket:UInt, remoteSteamId:ULong, state:ESteamNetworkingConnectionState, reason:Int = 0, oldState:ESteamNetworkingConnectionState = ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_None)
		Check(callbackCount < MAX_CALLBACKS, "mock callback capacity")
		callbackConnection[callbackCount] = connection
		callbackListenSocket[callbackCount] = listenSocket
		callbackRemoteSteamId[callbackCount] = remoteSteamId
		callbackOldState[callbackCount] = oldState
		callbackState[callbackCount] = state
		callbackReason[callbackCount] = reason
		callbackCount :+ 1
	End Method

	Method QueueMessage(connection:UInt, data:Byte Ptr, length:UInt, result:Int = 1)
		Check(messageCount < MAX_MESSAGES And length <= MESSAGE_CAPACITY, "mock message capacity")
		messageConnection[messageWrite] = connection
		messageLength[messageWrite] = length
		messageResult[messageWrite] = result
		If data And length > 0 Then MemCopy(Byte Ptr(messageStorage) + Size_T(messageWrite * MESSAGE_CAPACITY), data, Size_T(length))
		messageWrite = (messageWrite + 1) Mod MAX_MESSAGES
		messageCount :+ 1
	End Method

	Method SetListener(listener:ISteamNetworkingSocketsListener) Override
		target = listener
	End Method

	Method RunCallbacks() Override
		For Local index:Int = 0 Until callbackCount
			If target Then
				target.OnSteamNetworkingSocketsConnectionStatusChanged(callbackConnection[index], callbackListenSocket[index], callbackRemoteSteamId[index], callbackOldState[index], callbackState[index], callbackReason[index], "mock")
			End If
		Next
		callbackCount = 0
	End Method

	Method CreateListenSocketIP:UInt(address:String, port:Int) Override
		lastConnectAddress = address
		lastConnectPort = port
		Return nextListenSocket
	End Method

	Method ConnectByIPAddress:UInt(address:String, port:Int) Override
		lastConnectAddress = address
		lastConnectPort = port
		Return nextConnection
	End Method

	Method CreateListenSocketP2P:UInt(virtualPort:Int = 0) Override
		lastP2PPort = virtualPort
		Return nextListenSocket
	End Method

	Method ConnectP2P:UInt(steamID:ULong, virtualPort:Int = 0) Override
		lastP2PSteamId = steamID
		lastP2PPort = virtualPort
		Return nextConnection
	End Method

	Method AcceptConnection:EResult(connection:UInt) Override
		acceptedConnection = connection
		Return acceptResult
	End Method

	Method CloseConnection:Int(connection:UInt, reason:Int = 0, debugMessage:String = "", linger:Int = False) Override
		closedConnection = connection
		closedReason = reason
		Return closeResult
	End Method

	Method CloseListenSocket:Int(socket:UInt) Override
		closedListenSocket = socket
		Return True
	End Method

	Method SendMessageToConnection:EResult(connection:UInt, data:Byte Ptr, size:UInt, sendFlags:Int, messageNumber:Long Var) Override
		lastSendConnection = connection
		lastSendFlags = sendFlags
		lastSendLength = size
		If data And size > 0 Then MemCopy(Byte Ptr(lastSend), data, Size_T(size))
		messageNumber = 123
		Return sendResult
	End Method

	Method CreatePollGroup:UInt() Override
		Return createPollGroupResult
	End Method

	Method DestroyPollGroup:Int(group:UInt) Override
		destroyedPollGroup = group
		Return True
	End Method

	Method SetConnectionPollGroup:Int(connection:UInt, group:UInt) Override
		Return True
	End Method

	Method ReceiveMessageOnPollGroup:Int(group:UInt, data:Byte Ptr, capacity:UInt, connection:UInt Var, size:UInt Var, flags:Int Var) Override
		If messageCount = 0 Then Return 0
		connection = messageConnection[messageRead]
		size = messageLength[messageRead]
		Local result:Int = messageResult[messageRead]
		If result > 0 And size <= capacity Then MemCopy(data, Byte Ptr(messageStorage) + Size_T(messageRead * MESSAGE_CAPACITY), Size_T(size))
		messageRead = (messageRead + 1) Mod MAX_MESSAGES
		messageCount :- 1
		Return result
	End Method

	Method GetConnectionStatus:EResult(connection:UInt, state:ESteamNetworkingConnectionState Var, endReason:Int Var, endDebug:String Var, ping:Int Var, qualityLocal:Float Var, qualityRemote:Float Var, pendingUnreliable:Int Var, pendingReliable:Int Var, sentUnackedReliable:Int Var, queueTimeMicroseconds:Long Var) Override
		state = ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connected
		endReason = 0
		endDebug = "healthy"
		ping = 27
		qualityLocal = 0.95
		qualityRemote = 0.9
		pendingUnreliable = 2
		pendingReliable = 3
		sentUnackedReliable = 4
		queueTimeMicroseconds = 500
		Return EResult.k_EResultOK
	End Method
End Type

Function CopyLastSend:Byte[](backend:TMockSteamSockets)
	Local result:Byte[] = New Byte[Int(backend.lastSendLength)]
	If result.Length Then MemCopy(Byte Ptr(result), Byte Ptr(backend.lastSend), Size_T(result.Length))
	Return result
End Function

' Outgoing connection, framing, delivery mapping, diagnostics, and validation.
Local backend:TMockSteamSockets = New TMockSteamSockets
Local transport:TSteamSocketsTransport = TSteamSocketsTransport.ConnectIP("127.0.0.1", 27015, 3, 64, backend)
Check(transport <> Null And backend.lastConnectAddress = "127.0.0.1" And backend.lastConnectPort = 27015, "create IP client")
backend.QueueStatus(41, 0, 0, ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connected)
Local event:SNetEvent
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Connected, "report outgoing connection")
Local peer:SNetPeer = event.Peer()
Check(peer.IsValid(), "connected peer handle")

Local payload:Byte[] = [Byte(10), Byte(20), Byte(30)]
Check(transport.Send(peer, 2, EDeliveryMode.ReliableOrdered, Byte Ptr(payload), Size_T(payload.Length)) = ETransportResult.Ok, "send reliable packet")
Check(backend.lastSendConnection = 41 And (backend.lastSendFlags & STEAM_NETWORKING_SEND_RELIABLE) <> 0, "map reliable delivery")
Local reader:SPacketReader = New SPacketReader(Byte Ptr(backend.lastSend), Size_T(backend.lastSendLength))
Local magic:UInt
Local version:UInt
Local delivery:UInt
Local channel:UInt
Local sequence:UInt
reader.ReadUInt32(magic)
reader.ReadUInt8(version)
reader.ReadUInt8(delivery)
reader.ReadUInt16(channel)
reader.ReadUInt32(sequence)
Check(Not reader.Failed() And magic = STEAM_SOCKETS_FRAME_MAGIC And version = STEAM_SOCKETS_FRAME_VERSION, "frame identity")
Check(delivery = UInt(EDeliveryMode.ReliableOrdered) And channel = 2 And sequence = 0, "frame metadata")
Check(reader.Remaining() = Size_T(payload.Length), "frame payload length")

backend.QueueMessage(41, Byte Ptr(backend.lastSend), backend.lastSendLength)
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Data, "receive framed packet")
Check(event.Peer().Equals(peer) And event.Channel() = 2 And event.Delivery() = EDeliveryMode.ReliableOrdered, "received metadata")
Check(event.Packet().Length() = 3 And event.Packet().Data()[0] = 10 And event.Packet().Data()[2] = 30, "received payload")

' Later sequenced traffic wins when Steam delivers packets out of order.
Local first:Byte = 1
Local second:Byte = 2
Check(transport.Send(peer, 1, EDeliveryMode.UnreliableSequenced, Varptr first, 1) = ETransportResult.Ok, "send first sequence")
Local firstPacket:Byte[] = CopyLastSend(backend)
Check(transport.Send(peer, 1, EDeliveryMode.UnreliableSequenced, Varptr second, 1) = ETransportResult.Ok, "send second sequence")
Local secondPacket:Byte[] = CopyLastSend(backend)
backend.QueueMessage(41, Byte Ptr(secondPacket), UInt(secondPacket.Length))
backend.QueueMessage(41, Byte Ptr(firstPacket), UInt(firstPacket.Length))
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Data And event.Packet().Data()[0] = 2, "deliver newest sequence")
Check(Not transport.Poll(event), "discard stale sequence")

Check(transport.Send(peer, 3, EDeliveryMode.Unreliable, Varptr first, 1) = ETransportResult.InvalidChannel, "reject invalid channel")
Check(transport.Send(peer, 0, EDeliveryMode.Unreliable, Varptr first, 65) = ETransportResult.PacketTooLarge, "reject oversized send")
Check(transport.Send(peer, 0, EDeliveryMode.Unreliable, Null, 1) = ETransportResult.Failed, "reject missing payload")

Local malformed:Byte[STEAM_SOCKETS_FRAME_HEADER_SIZE]
backend.QueueMessage(41, Byte Ptr(malformed), UInt(malformed.Length))
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Error And event.Code() = Int(ESteamSocketsTransportError.InvalidFrame), "report malformed frame")
backend.QueueMessage(999, Byte Ptr(secondPacket), UInt(secondPacket.Length))
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Error And event.Code() = Int(ESteamSocketsTransportError.UnknownConnection), "report unknown connection")
backend.QueueMessage(41, Null, 100, -1)
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Error And event.Code() = Int(ESteamSocketsTransportError.IncomingPacketTooLarge), "report oversized receive")

Local state:ESteamNetworkingConnectionState
Local endReason:Int
Local endDebug:String
Local ping:Int
Local qualityLocal:Float
Local qualityRemote:Float
Local pendingUnreliable:Int
Local pendingReliable:Int
Local sentUnackedReliable:Int
Local queueTime:Long
Check(transport.GetConnectionStatus(peer, state, endReason, endDebug, ping, qualityLocal, qualityRemote, pendingUnreliable, pendingReliable, sentUnackedReliable, queueTime) = EResult.k_EResultOK, "read connection status")
Check(ping = 27 And pendingReliable = 3 And queueTime = 500, "connection diagnostics")

Check(transport.Disconnect(peer, 77) = ETransportResult.Ok, "disconnect client")
Check(backend.closedConnection = 41 And backend.closedReason = 77, "close native connection")
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 77, "report local disconnect")
transport.Close()
Check(backend.destroyedPollGroup = 91, "destroy client poll group")

' Incoming listener connections are accepted and retain their Steam identity.
Local listenerBackend:TMockSteamSockets = New TMockSteamSockets
Local listener:TSteamSocketsTransport = TSteamSocketsTransport.ListenP2P(4, 2, 2, 64, listenerBackend)
Check(listener <> Null And listenerBackend.lastP2PPort = 4, "create P2P listener")
listenerBackend.QueueStatus(51, 71, 765, ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connecting)
listenerBackend.QueueStatus(51, 71, 765, ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connected)
Check(listener.Poll(event) And event.Kind() = ENetEventKind.Connected, "accept incoming connection")
Local listenerPeer:SNetPeer = event.Peer()
Check(listenerBackend.acceptedConnection = 51 And listener.SteamId(listenerPeer) = 765, "retain incoming identity")
listenerBackend.QueueStatus(51, 71, 765, ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_ClosedByPeer, 88)
Check(listener.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 88, "report peer close")
listener.Close()
Check(listenerBackend.closedListenSocket = 71 And listenerBackend.destroyedPollGroup = 91, "close listener resources")

' A local native failure produces a diagnostic before disconnection.
Local failureBackend:TMockSteamSockets = New TMockSteamSockets
Local failed:TSteamSocketsTransport = TSteamSocketsTransport.ConnectP2P(1234, 6, 2, 64, failureBackend)
Check(failed <> Null And failureBackend.lastP2PSteamId = 1234 And failureBackend.lastP2PPort = 6, "create P2P client")
failureBackend.QueueStatus(41, 0, 1234, ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_ProblemDetectedLocally, 44)
Check(failed.Poll(event) And event.Kind() = ENetEventKind.Error And event.Code() = 44, "report connection failure")
Check(failed.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 44, "disconnect after connection failure")
failed.Close()

' Event overflow remains explicit and bounded under a callback burst.
Local overflowBackend:TMockSteamSockets = New TMockSteamSockets
Local overflow:TSteamSocketsTransport = TSteamSocketsTransport.ListenIP(27016, 8, 1, "", 64, overflowBackend)
Check(overflow <> Null, "create overflow listener")
For Local index:Int = 0 Until 8
	Local connection:UInt = UInt(100 + index)
	overflowBackend.QueueStatus(connection, 71, ULong(1000 + index), ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connecting)
	overflowBackend.QueueStatus(connection, 71, ULong(1000 + index), ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connected)
Next
Check(overflow.Poll(event) And event.Kind() = ENetEventKind.Connected, "begin draining connection burst")
For Local index:Int = 0 Until 8
	overflowBackend.QueueStatus(UInt(100 + index), 71, ULong(1000 + index), ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_ProblemDetectedLocally, 99)
Next
For Local index:Int = 0 Until 8
	Local connection:UInt = UInt(200 + index)
	overflowBackend.QueueStatus(connection, 71, ULong(2000 + index), ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connecting)
	overflowBackend.QueueStatus(connection, 71, ULong(2000 + index), ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_Connected)
Next
For Local index:Int = 0 Until 8
	overflowBackend.QueueStatus(UInt(200 + index), 71, ULong(2000 + index), ESteamNetworkingConnectionState.k_ESteamNetworkingConnectionState_ProblemDetectedLocally, 100)
Next
Local sawOverflow:Int
While overflow.Poll(event)
	If event.Kind() = ENetEventKind.Error And event.Code() = Int(ESteamSocketsTransportError.EventQueueFull) Then sawOverflow = True
Wend
Check(sawOverflow, "report bounded event overflow")
overflow.Close()

' Construction failures cleanly reject unusable native backends.
Local noPollGroup:TMockSteamSockets = New TMockSteamSockets
noPollGroup.createPollGroupResult = 0
Check(TSteamSocketsTransport.Create(1, 1, 64, noPollGroup) = Null, "reject missing poll group")
Local noConnection:TMockSteamSockets = New TMockSteamSockets
noConnection.nextConnection = 0
Check(TSteamSocketsTransport.ConnectIP("127.0.0.1", 27015, 1, 64, noConnection) = Null, "reject failed connection creation")
Local noListener:TMockSteamSockets = New TMockSteamSockets
noListener.nextListenSocket = 0
Check(TSteamSocketsTransport.ListenIP(27015, 1, 1, "", 64, noListener) = Null, "reject failed listener creation")

Print "GameNet.SteamSockets tests passed"
