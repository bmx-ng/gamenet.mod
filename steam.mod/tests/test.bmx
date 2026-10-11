SuperStrict

Framework GameNet.Steam
Import BRL.StandardIO

Function Check(condition:Int, message:String)
	If Not condition Then Throw "FAILED: " + message
End Function

Type TMockSteamMessages Extends TSteamNetworkingMessages
	Field target:ISteamNetworkingMessagesListener
	Field sent:Byte[] = New Byte[0]
	Field sentSteamId:ULong
	Field sentFlags:Int
	Field sentChannel:Int
	Field incoming:Byte[] = New Byte[0]
	Field incomingSteamId:ULong
	Field incomingReliable:Int
	Field incomingChannel:Int
	Field hasIncoming:Int

	Method SetListener(listener:ISteamNetworkingMessagesListener) Override
		target = listener
	End Method

	Method SendMessageToUser:EResult(steamIDRemote:ULong, data:Byte Ptr, size:UInt, sendFlags:Int = STEAM_NETWORKING_SEND_UNRELIABLE, remoteChannel:Int = 0) Override
		sent = New Byte[Int(size)]
		If size Then MemCopy(Byte Ptr(sent), data, Size_T(size))
		sentSteamId = steamIDRemote
		sentFlags = sendFlags
		sentChannel = remoteChannel
		Return EResult.k_EResultOK
	End Method

	Method ReceiveMessage:Int(localChannel:Int, data:Byte Ptr, capacity:UInt, size:UInt Var, steamIDRemote:ULong Var, reliable:Int Var) Override
		If Not hasIncoming Or localChannel <> incomingChannel Then Return 0
		hasIncoming = False
		size = UInt(incoming.Length)
		steamIDRemote = incomingSteamId
		reliable = incomingReliable
		If capacity < UInt(incoming.Length) Then Return -1
		If incoming.Length Then MemCopy(data, Byte Ptr(incoming), Size_T(incoming.Length))
		Return 1
	End Method

	Method AcceptSessionWithUser:Int(steamIDRemote:ULong) Override Return True End Method
	Method CloseSessionWithUser:Int(steamIDRemote:ULong) Override Return True End Method
	Method CloseChannelWithUser:Int(steamIDRemote:ULong, localChannel:Int) Override Return True End Method

	Method QueueLastSend(steamId:ULong)
		incoming = sent[..]
		incomingSteamId = steamId
		incomingReliable = (sentFlags & STEAM_NETWORKING_SEND_RELIABLE) <> 0
		incomingChannel = sentChannel
		hasIncoming = True
	End Method
End Type

Local backend:TMockSteamMessages = New TMockSteamMessages
Local transport:TSteamTransport = TSteamTransport.Create([ULong(42)], 2, 64, backend)
Check(transport <> Null, "create transport")

Local event:SNetEvent
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Connected, "initial connected event")
Local peer:SNetPeer = event.Peer()

Local payload:Byte[] = [Byte(10), Byte(20), Byte(30)]
Check(transport.Send(peer, 1, EDeliveryMode.UnreliableSequenced, Byte Ptr(payload), Size_T(payload.Length)) = ETransportResult.Ok, "send sequenced packet")
Check(backend.sentSteamId = 42 And backend.sentChannel = 1, "route by Steam identity and channel")
backend.QueueLastSend(42)
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Data, "receive packet")
Check(event.Delivery() = EDeliveryMode.UnreliableSequenced And event.Channel() = 1 And event.Packet().Length() = 3, "preserve frame metadata")
Check(event.Packet().Data()[0] = 10 And event.Packet().Data()[2] = 30, "preserve payload")

backend.QueueLastSend(42)
Check(Not transport.Poll(event), "discard stale sequenced packet")

Check(transport.Send(peer, 0, EDeliveryMode.ReliableOrdered, Byte Ptr(payload), Size_T(payload.Length)) = ETransportResult.Ok, "send reliable packet")
Check((backend.sentFlags & STEAM_NETWORKING_SEND_RELIABLE) <> 0, "map reliable delivery")
Check(transport.Disconnect(peer, 7) = ETransportResult.Ok, "disconnect peer")
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 7, "disconnect event")

transport.Close()
Print "GameNet.Steam tests passed"
