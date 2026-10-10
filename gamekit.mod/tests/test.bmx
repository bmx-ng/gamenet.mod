SuperStrict

Framework BRL.StandardIO
Import GameNet.GameKit
Import GameNet.Session

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Type TFakeGameKitMatch Implements IGameKitMatchBackend
	Field remote:TFakeGameKitMatch
	Field events:SGameCenterMatchEvent[16]
	Field lengths:Size_T[16]
	Field storage:Byte[16384]
	Field readIndex:Int
	Field writeIndex:Int
	Field count:Int
	Field open:Int = True
	Field lastPacket:Byte[1024]
	Field lastLength:Size_T
	Field lastPlayerIndex:Int
	Field lastMode:EGameCenterMatchSendMode

	Method Queue(event:SGameCenterMatchEvent, data:Byte Ptr = Null, length:Size_T = 0)
		events[writeIndex] = event
		lengths[writeIndex] = length
		If length > 0 Then MemCopy(Byte Ptr(storage) + Size_T(writeIndex * 1024), data, length)
		writeIndex = (writeIndex + 1) Mod events.Length
		count :+ 1
	End Method

	Method Poll:Int(event:SGameCenterMatchEvent Var, data:Byte Ptr, dataCapacity:Size_T) Override
		If count = 0 Then
			event = New SGameCenterMatchEvent
			Return False
		End If
		event = events[readIndex]
		Local length:Size_T = lengths[readIndex]
		If length > 0 And length <= dataCapacity Then MemCopy(data, Byte Ptr(storage) + Size_T(readIndex * 1024), length)
		readIndex = (readIndex + 1) Mod events.Length
		count :- 1
		Return True
	End Method

	Method Send:Int(playerIndex:Int, mode:EGameCenterMatchSendMode, data:Byte Ptr, length:Size_T, error:TGameCenterError Var) Override
		If Not open Or length > Size_T(lastPacket.Length) Then Return False
		lastPlayerIndex = playerIndex
		lastMode = mode
		lastLength = length
		If length > 0 Then MemCopy(Byte Ptr(lastPacket), data, length)
		If remote Then remote.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 1, length, Null), data, length)
		Return True
	End Method

	Method IsOpen:Int() Override
		Return open
	End Method

	Method Disconnect() Override
		open = False
	End Method
End Type

Local backend:TFakeGameKitMatch = New TFakeGameKitMatch
Local transport:TGameKitTransport = TGameKitTransport.CreateForBackend(backend, 2, 4, 64)
Check(transport <> Null, "create GameKit transport")

backend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 1, 0, Null))
Local event:SNetEvent
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Connected, "connected event")
Local peer:SNetPeer = event.Peer()
Check(peer.Id() = 1 And peer.Generation() = 1, "stable peer handle")

Local value:Byte = 42
Check(transport.Send(peer, 2, EDeliveryMode.ReliableOrdered, Varptr value, 1) = ETransportResult.Ok, "send reliable packet")
Check(backend.lastPlayerIndex = 1 And backend.lastMode = EGameCenterMatchSendMode.Reliable, "map reliable send")
Local reader:SPacketReader = New SPacketReader(Byte Ptr(backend.lastPacket), backend.lastLength)
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
Check(Not reader.Failed() And magic = GAMEKIT_FRAME_MAGIC And version = GAMEKIT_FRAME_VERSION, "GameKit frame identity")
Check(delivery = UInt(EDeliveryMode.ReliableOrdered) And channel = 2 And sequence = 0, "GameKit frame metadata")

backend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 1, backend.lastLength, Null), Byte Ptr(backend.lastPacket), backend.lastLength)
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Data, "receive framed packet")
Check(event.Peer().Equals(peer) And event.Channel() = 2 And event.Delivery() = EDeliveryMode.ReliableOrdered, "received packet metadata")
Check(event.Packet().Length() = 1 And event.Packet().Data()[0] = 42, "received packet payload")

' Later unreliable-sequenced data is delivered and its stale predecessor is discarded.
Local firstValue:Byte = 11
Local secondValue:Byte = 22
Local firstPacket:Byte[128]
Local secondPacket:Byte[128]
Local firstLength:Size_T
Local secondLength:Size_T
Check(transport.Send(peer, 1, EDeliveryMode.UnreliableSequenced, Varptr firstValue, 1) = ETransportResult.Ok, "send first sequenced packet")
firstLength = backend.lastLength
MemCopy(Byte Ptr(firstPacket), Byte Ptr(backend.lastPacket), firstLength)
Check(transport.Send(peer, 1, EDeliveryMode.UnreliableSequenced, Varptr secondValue, 1) = ETransportResult.Ok, "send second sequenced packet")
secondLength = backend.lastLength
MemCopy(Byte Ptr(secondPacket), Byte Ptr(backend.lastPacket), secondLength)
Check(backend.lastMode = EGameCenterMatchSendMode.Unreliable, "map sequenced send to GameKit unreliable")
backend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 1, secondLength, Null), Byte Ptr(secondPacket), secondLength)
backend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 1, firstLength, Null), Byte Ptr(firstPacket), firstLength)
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Data And event.Packet().Data()[0] = 22, "deliver newest sequenced packet")
Check(Not transport.Poll(event), "discard stale sequenced packet")

Check(transport.Send(peer, 4, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.InvalidChannel, "reject invalid channel")
Check(transport.Send(peer, 0, EDeliveryMode.Unreliable, Varptr value, 65) = ETransportResult.PacketTooLarge, "reject oversized packet")

' Disconnecting one GameKit peer ends the whole match and reports active peers locally.
Check(transport.Disconnect(peer, 77) = ETransportResult.Ok, "disconnect GameKit match")
Check(Not backend.open, "native match disconnected")
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 77, "local disconnect event")
Check(Not transport.IsOpen(), "transport closes after pending disconnect")

' GameNet.Session can perform its normal handshake over paired GameKit adapters.
Local firstBackend:TFakeGameKitMatch = New TFakeGameKitMatch
Local secondBackend:TFakeGameKitMatch = New TFakeGameKitMatch
firstBackend.remote = secondBackend
secondBackend.remote = firstBackend
Local firstTransport:TGameKitTransport = TGameKitTransport.CreateForBackend(firstBackend, 1, 2, 128)
Local secondTransport:TGameKitTransport = TGameKitTransport.CreateForBackend(secondBackend, 1, 2, 128)
firstBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 1, 0, Null))
secondBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 1, 0, Null))
Local host:TNetSession = TNetSession.CreateHost(firstTransport, $474b5445, 1, 1, 128)
Local client:TNetSession = TNetSession.CreateClient(secondTransport, $474b5445, 1, Null, 0, 2, 128)
Check(host <> Null And client <> Null, "create sessions over GameKit")
Local sessionEvent:SSessionEvent
Check(Not client.Poll(sessionEvent), "GameKit client connects and sends hello")
Check(host.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.JoinRequested, "GameKit host receives join request")
Local hostPeer:SNetPeer = sessionEvent.Peer()
Check(host.Accept(hostPeer) = ETransportResult.Ok, "GameKit host accepts peer")
Check(host.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Joined, "GameKit host joins peer")
Check(client.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Joined, "GameKit client joins host")
host.Close()
client.Close()

Print "GameNet.GameKit tests passed"
