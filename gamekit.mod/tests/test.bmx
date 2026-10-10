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
Check(TGameKitTransport.CreateForBackend(New TFakeGameKitMatch, GAMEKIT_MAX_REMOTE_PEERS, 1, 64) <> Null, "support fifteen remote GameKit peers")
Check(TGameKitTransport.CreateForBackend(New TFakeGameKitMatch, GAMEKIT_MAX_REMOTE_PEERS + 1, 1, 64) = Null, "reject more than sixteen total GameKit players")

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
Check(Not transport.SetPlayerEnabled(2, False), "freeze player filter after polling")

' Disconnecting one GameKit peer ends the whole match and reports active peers locally.
Check(transport.Disconnect(peer, 77) = ETransportResult.Ok, "disconnect GameKit match")
Check(Not backend.open, "native match disconnected")
Check(transport.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 77, "local disconnect event")
Check(Not transport.IsOpen(), "transport closes after pending disconnect")

' A star-topology client exposes only its elected host from a larger native mesh.
Local filteredBackend:TFakeGameKitMatch = New TFakeGameKitMatch
Local filtered:TGameKitTransport = TGameKitTransport.CreateForBackend(filteredBackend, 3, 2, 64)
Check(filtered.EnableOnlyPlayer(2) And filtered.PlayerEnabled(2) And Not filtered.PlayerEnabled(1) And Not filtered.PlayerEnabled(3), "configure elected host filter")
filteredBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 1, 0, Null))
filteredBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 2, 0, Null))
filteredBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 3, 0, Null))
Check(filtered.Poll(event) And event.Kind() = ENetEventKind.Connected And event.Peer().Id() = 2, "expose only elected host connection")
Check(Not filtered.Poll(event), "discard hidden mesh connections")
Local filteredHost:SNetPeer = New SNetPeer(2, 1)
Check(filtered.Send(filteredHost, 0, EDeliveryMode.ReliableOrdered, Varptr value, 1) = ETransportResult.Ok, "send to elected host")
Check(filtered.Send(New SNetPeer(1, 1), 0, EDeliveryMode.ReliableOrdered, Varptr value, 1) = ETransportResult.InvalidPeer, "reject hidden mesh peer")
filteredBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 1, filteredBackend.lastLength, Null), Byte Ptr(filteredBackend.lastPacket), filteredBackend.lastLength)
filteredBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 2, filteredBackend.lastLength, Null), Byte Ptr(filteredBackend.lastPacket), filteredBackend.lastLength)
Check(filtered.Poll(event) And event.Kind() = ENetEventKind.Data And event.Peer().Id() = 2, "discard hidden data and deliver host data")
filteredBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerDisconnected, 1, 0, Null))
Check(Not filtered.Poll(event), "discard hidden participant loss")
filtered.Close()

' A host keeps the remaining participant links alive when one peer leaves.
Local hostBackend:TFakeGameKitMatch = New TFakeGameKitMatch
Local hostTransport:TGameKitTransport = TGameKitTransport.CreateForBackend(hostBackend, 3, 2, 64)
For Local playerIndex:Int = 1 To 3
	hostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, playerIndex, 0, Null))
	Check(hostTransport.Poll(event) And event.Kind() = ENetEventKind.Connected And event.Peer().Id() = UInt(playerIndex), "connect host participant " + playerIndex)
Next
hostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerDisconnected, 2, 0, Null))
Check(hostTransport.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Peer().Id() = 2, "report one departed participant")
Check(hostTransport.IsOpen(), "keep native match open after participant loss")
Check(hostTransport.Send(New SNetPeer(1, 1), 0, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.Ok, "first remaining participant stays active")
Check(hostTransport.Send(New SNetPeer(2, 1), 0, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.InvalidPeer, "departed participant becomes invalid")
Check(hostTransport.Send(New SNetPeer(3, 1), 0, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.Ok, "third participant stays active")
hostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerDisconnected, 2, 0, Null))
hostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 2, 0, Null))
Check(hostTransport.Poll(event) And event.Kind() = ENetEventKind.Connected And event.Peer().Id() = 2, "ignore duplicate leave and reconnect stable participant")
hostTransport.Close()

' A native close without a failure callback remains visible to the application.
Local closedBackend:TFakeGameKitMatch = New TFakeGameKitMatch
Local closedTransport:TGameKitTransport = TGameKitTransport.CreateForBackend(closedBackend, 1, 2, 64)
closedBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 1, 0, Null))
Check(closedTransport.Poll(event) And event.Kind() = ENetEventKind.Connected, "connect before native close")
closedBackend.open = False
Check(closedTransport.Poll(event) And event.Kind() = ENetEventKind.Error And event.Code() = Int(EGameKitTransportError.MatchClosed), "report unexpected native close")
Check(closedTransport.Poll(event) And event.Kind() = ENetEventKind.Disconnected, "report exposed peer after native close")
Check(Not closedTransport.IsOpen(), "finish native close delivery")

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

' Three native mesh participants form one host session with two filtered clients.
Local meshHostBackend:TFakeGameKitMatch = New TFakeGameKitMatch
Local meshClientABackend:TFakeGameKitMatch = New TFakeGameKitMatch
Local meshClientBBackend:TFakeGameKitMatch = New TFakeGameKitMatch
Local meshHostTransport:TGameKitTransport = TGameKitTransport.CreateForBackend(meshHostBackend, 2, 2, 128)
Local meshClientATransport:TGameKitTransport = TGameKitTransport.CreateForBackend(meshClientABackend, 3, 2, 128)
Local meshClientBTransport:TGameKitTransport = TGameKitTransport.CreateForBackend(meshClientBBackend, 3, 2, 128)
Check(meshClientATransport.EnableOnlyPlayer(2), "client A exposes elected host")
Check(meshClientBTransport.EnableOnlyPlayer(3), "client B exposes elected host")
meshHostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 1, 0, Null))
meshHostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 2, 0, Null))
meshClientABackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 1, 0, Null))
meshClientABackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 2, 0, Null))
meshClientABackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 3, 0, Null))
meshClientBBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 1, 0, Null))
meshClientBBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 2, 0, Null))
meshClientBBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerConnected, 3, 0, Null))
Local meshHost:TNetSession = TNetSession.CreateHost(meshHostTransport, $4d455348, 1, 2, 128)
Local meshClientA:TNetSession = TNetSession.CreateClient(meshClientATransport, $4d455348, 1, Null, 0, 1, 128)
Local meshClientB:TNetSession = TNetSession.CreateClient(meshClientBTransport, $4d455348, 1, Null, 0, 1, 128)
Check(Not meshHost.Poll(sessionEvent), "mesh host registers both clients")

' Client A sends its hello only to host index 2.
Check(Not meshClientA.Poll(sessionEvent) And meshClientABackend.lastPlayerIndex = 2, "mesh client A sends hello to host")
meshHostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 1, meshClientABackend.lastLength, Null), Byte Ptr(meshClientABackend.lastPacket), meshClientABackend.lastLength)
Check(meshHost.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.JoinRequested And sessionEvent.Peer().Id() = 1, "mesh host receives client A join")
Local meshPeerA:SNetPeer = sessionEvent.Peer()
Check(meshHost.Accept(meshPeerA) = ETransportResult.Ok And meshHostBackend.lastPlayerIndex = 1, "mesh host accepts client A")
Check(meshHost.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Joined, "mesh host joins client A")
meshClientABackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 2, meshHostBackend.lastLength, Null), Byte Ptr(meshHostBackend.lastPacket), meshHostBackend.lastLength)
Check(meshClientA.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Joined, "mesh client A joins host")
Local meshHostForA:SNetPeer = sessionEvent.Peer()

' Client B independently joins the same host and never sees client A.
Check(Not meshClientB.Poll(sessionEvent) And meshClientBBackend.lastPlayerIndex = 3, "mesh client B sends hello to host")
meshHostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 2, meshClientBBackend.lastLength, Null), Byte Ptr(meshClientBBackend.lastPacket), meshClientBBackend.lastLength)
Check(meshHost.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.JoinRequested And sessionEvent.Peer().Id() = 2, "mesh host receives client B join")
Local meshPeerB:SNetPeer = sessionEvent.Peer()
Check(meshHost.Accept(meshPeerB) = ETransportResult.Ok And meshHostBackend.lastPlayerIndex = 2, "mesh host accepts client B")
Check(meshHost.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Joined, "mesh host joins client B")
meshClientBBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 3, meshHostBackend.lastLength, Null), Byte Ptr(meshHostBackend.lastPacket), meshHostBackend.lastLength)
Check(meshClientB.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Joined, "mesh client B joins host")
Local meshHostForB:SNetPeer = sessionEvent.Peer()

' Client A leaves; client B remains usable.
meshHostBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerDisconnected, 1, 0, Null))
Check(meshHost.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Left And sessionEvent.Peer().Equals(meshPeerA), "mesh host reports only client A leaving")
meshClientABackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.PlayerDisconnected, 2, 0, Null))
Check(meshClientA.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Left And sessionEvent.Peer().Equals(meshHostForA), "departing client reports host loss")
Local meshValue:Byte = 91
Check(meshHost.Send(meshPeerB, 7, 1, EDeliveryMode.ReliableOrdered, Varptr meshValue, 1) = ETransportResult.Ok, "mesh host sends after participant loss")
meshClientBBackend.Queue(New SGameCenterMatchEvent(EGameCenterMatchEventKind.Data, 3, meshHostBackend.lastLength, Null), Byte Ptr(meshHostBackend.lastPacket), meshHostBackend.lastLength)
Check(meshClientB.Poll(sessionEvent) And sessionEvent.Kind() = ESessionEventKind.Message And sessionEvent.Peer().Equals(meshHostForB), "remaining mesh client receives after participant loss")
Check(sessionEvent.MessageType() = 7 And sessionEvent.Payload().Length() = 1 And sessionEvent.Payload().Data()[0] = 91, "remaining mesh payload is intact")
meshHost.Close()
meshClientA.Close()
meshClientB.Close()

Print "GameNet.GameKit tests passed"
