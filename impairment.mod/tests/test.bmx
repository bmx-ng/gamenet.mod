SuperStrict

Framework BRL.StandardIO
Import GameNet.Impairment
Import GameNet.Loopback
Import GameNet.Session

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Function ConsumeConnections(first:INetTransport, second:INetTransport)
	Local event:SNetEvent
	Check(first.Poll(event) And event.Kind() = ENetEventKind.Connected, "first connection")
	Check(second.Poll(event) And event.Kind() = ENetEventKind.Connected, "second connection")
End Function

' Fixed latency delays an outbound packet without allocating while active.
Local pair:TLoopbackPair = TLoopbackPair.Create(16, 64)
Local config:SImpairmentConfig = New SImpairmentConfig(100)
Local impaired:TImpairedTransport = TImpairedTransport.Create(pair.First(), 8, 64, config, 1, True)
Check(impaired <> Null, "create impaired transport")
ConsumeConnections(impaired, pair.Second())
Local peer:SNetPeer = pair.First().RemotePeer()
Local value:Byte = 42
Check(impaired.SetTime(10), "set deterministic time")
Check(impaired.Send(peer, 2, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.Ok, "queue delayed packet")
Local stats:SImpairmentStats = impaired.Stats()
Check(stats.Queued() = 1 And stats.Sent() = 0, "delayed packet stats")
Local event:SNetEvent
Check(Not pair.Second().Poll(event), "not delivered early")
impaired.SetTime(109)
Check(Not impaired.Poll(event), "not flushed before deadline")
Check(Not pair.Second().Poll(event), "still not delivered")
impaired.SetTime(110)
Check(Not impaired.Poll(event), "flush at deadline")
Check(pair.Second().Poll(event) And event.Kind() = ENetEventKind.Data, "delivered at deadline")
Check(event.Channel() = 2 And event.Packet().Length() = 1 And event.Packet().Data()[0] = 42, "delayed packet contents")
stats = impaired.Stats()
Check(stats.Queued() = 0 And stats.Sent() = 1, "sent packet stats")
pair.Close()

' Complete loss consumes the packet successfully but never reaches the backend.
pair = TLoopbackPair.Create(16, 64)
config = New SImpairmentConfig(0, 0, IMPAIRMENT_PROBABILITY_SCALE)
impaired = TImpairedTransport.Create(pair.First(), 4, 64, config, 2, True)
ConsumeConnections(impaired, pair.Second())
peer = pair.First().RemotePeer()
Check(impaired.Send(peer, 0, EDeliveryMode.ReliableOrdered, Varptr value, 1) = ETransportResult.Ok, "drop selected packet")
Check(Not pair.Second().Poll(event), "dropped packet absent")
stats = impaired.Stats()
Check(stats.Dropped() = 1 And stats.Queued() = 0, "drop stats")
pair.Close()

' A delivery mask can preserve reliable backend guarantees.
pair = TLoopbackPair.Create(16, 64)
config = New SImpairmentConfig(0, 0, IMPAIRMENT_PROBABILITY_SCALE, 0, 0, 0, 0, IMPAIRMENT_DELIVERY_UNRELIABLE)
impaired = TImpairedTransport.Create(pair.First(), 4, 64, config, 2, True)
ConsumeConnections(impaired, pair.Second())
peer = pair.First().RemotePeer()
Check(impaired.Send(peer, 0, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.Ok, "drop selected delivery mode")
Check(impaired.Send(peer, 0, EDeliveryMode.ReliableOrdered, Varptr value, 1) = ETransportResult.Ok, "pass unselected delivery mode")
Check(pair.Second().Poll(event) And event.Delivery() = EDeliveryMode.ReliableOrdered, "reliable packet bypasses impairment")
Check(Not pair.Second().Poll(event), "selected unreliable packet absent")
stats = impaired.Stats()
Check(stats.Dropped() = 1 And stats.Sent() = 1, "delivery mask stats")
pair.Close()

' Complete duplication produces two independent packet copies.
pair = TLoopbackPair.Create(16, 64)
config = New SImpairmentConfig(0, 0, 0, IMPAIRMENT_PROBABILITY_SCALE)
impaired = TImpairedTransport.Create(pair.First(), 4, 64, config, 3, True)
ConsumeConnections(impaired, pair.Second())
peer = pair.First().RemotePeer()
Check(impaired.Send(peer, 1, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.Ok, "duplicate selected packet")
Check(pair.Second().Poll(event) And event.Packet().Data()[0] = 42, "first duplicate copy")
Check(pair.Second().Poll(event) And event.Packet().Data()[0] = 42, "second duplicate copy")
stats = impaired.Stats()
Check(stats.Duplicated() = 1 And stats.Sent() = 2, "duplication stats")
pair.Close()

' Explicit reordering can let a later packet pass an earlier packet.
pair = TLoopbackPair.Create(16, 64)
config = New SImpairmentConfig(0, 0, 0, 0, IMPAIRMENT_PROBABILITY_SCALE, 100)
impaired = TImpairedTransport.Create(pair.First(), 4, 64, config, 4, True)
ConsumeConnections(impaired, pair.Second())
peer = pair.First().RemotePeer()
Local firstValue:Byte = 1
Local secondValue:Byte = 2
Check(impaired.Send(peer, 0, EDeliveryMode.Unreliable, Varptr firstValue, 1) = ETransportResult.Ok, "queue first reordered packet")
Check(impaired.Send(peer, 0, EDeliveryMode.Unreliable, Varptr secondValue, 1) = ETransportResult.Ok, "queue second reordered packet")
impaired.SetTime(41)
Check(Not impaired.Poll(event), "release later packet first")
Check(pair.Second().Poll(event) And event.Packet().Data()[0] = 2, "observe reordered packet")
impaired.SetTime(77)
Check(Not impaired.Poll(event), "release earlier packet later")
Check(pair.Second().Poll(event) And event.Packet().Data()[0] = 1, "observe delayed first packet")
stats = impaired.Stats()
Check(stats.Reordered() = 2, "reordering stats")
pair.Close()

' Bandwidth serialization spaces queued packets even with no base latency.
pair = TLoopbackPair.Create(16, 64)
config = New SImpairmentConfig(0, 0, 0, 0, 0, 0, 1000)
impaired = TImpairedTransport.Create(pair.First(), 4, 64, config, 4, True)
ConsumeConnections(impaired, pair.Second())
peer = pair.First().RemotePeer()
Local block:Byte[10]
impaired.SetTime(0)
Check(impaired.Send(peer, 0, EDeliveryMode.Unreliable, Byte Ptr(block), Size_T(block.Length)) = ETransportResult.Ok, "queue first bandwidth packet")
Check(impaired.Send(peer, 0, EDeliveryMode.Unreliable, Byte Ptr(block), Size_T(block.Length)) = ETransportResult.Ok, "queue second bandwidth packet")
Check(pair.Second().Poll(event), "first bandwidth packet immediate")
Check(Not pair.Second().Poll(event), "second bandwidth packet serialized")
impaired.SetTime(9)
Check(Not impaired.Poll(event) And Not pair.Second().Poll(event), "bandwidth packet waits")
impaired.SetTime(10)
Check(Not impaired.Poll(event) And pair.Second().Poll(event), "bandwidth packet released")
pair.Close()

' Scheduled deadlines remain valid across the 32-bit millisecond wrap.
pair = TLoopbackPair.Create(16, 64)
config = New SImpairmentConfig(20)
impaired = TImpairedTransport.Create(pair.First(), 4, 64, config, 6, True)
ConsumeConnections(impaired, pair.Second())
peer = pair.First().RemotePeer()
impaired.SetTime($fffffff5)
Check(impaired.Send(peer, 0, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.Ok, "queue packet before clock wrap")
impaired.SetTime(8)
Check(Not impaired.Poll(event) And Not pair.Second().Poll(event), "wrapped deadline not early")
impaired.SetTime(9)
Check(Not impaired.Poll(event) And pair.Second().Poll(event), "wrapped deadline delivered")
pair.Close()

' A bounded queue reports backpressure without losing its retained packet.
pair = TLoopbackPair.Create(16, 64)
config = New SImpairmentConfig(100)
impaired = TImpairedTransport.Create(pair.First(), 1, 64, config, 5, True)
ConsumeConnections(impaired, pair.Second())
peer = pair.First().RemotePeer()
Check(impaired.Send(peer, 0, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.Ok, "fill impairment queue")
Check(impaired.Send(peer, 0, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.WouldBlock, "queue backpressure")
stats = impaired.Stats()
Check(stats.Queued() = 1 And stats.QueueOverflows() = 1, "overflow stats")
pair.Close()

' Deferred backend failures are observable through the normal event stream.
pair = TLoopbackPair.Create(16, 64)
config = New SImpairmentConfig
impaired = TImpairedTransport.Create(pair.First(), 4, 64, config, 7, True)
ConsumeConnections(impaired, pair.Second())
Local invalidPeer:SNetPeer = New SNetPeer(99, 1)
Check(impaired.Send(invalidPeer, 0, EDeliveryMode.Unreliable, Varptr value, 1) = ETransportResult.Ok, "accept deferred invalid send")
Check(impaired.Poll(event) And event.Kind() = ENetEventKind.Error, "report deferred send error")
Check(event.Code() = IMPAIRMENT_ERROR_SEND_BASE + Int(ETransportResult.InvalidPeer), "deferred send error code")
stats = impaired.Stats()
Check(stats.SendFailures() = 1, "send failure stats")
pair.Close()

' The decorator composes beneath GameNet.Session without session changes.
pair = TLoopbackPair.Create(16, 128)
config = New SImpairmentConfig(10)
impaired = TImpairedTransport.Create(pair.Second(), 8, 128, config, 8, True)
Local host:TNetSession = TNetSession.CreateHost(pair.First(), $54455354, 1, 1, 128)
Local client:TNetSession = TNetSession.CreateClient(impaired, $54455354, 1, Null, 0, 1, 128)
Local sessionEvent:SSessionEvent
Check(host <> Null And client <> Null, "create sessions over impairment")
impaired.SetTime(0)
Check(Not client.PollAt(sessionEvent, 0), "delayed session hello")
Check(Not host.PollAt(sessionEvent, 0), "host awaits impaired hello")
impaired.SetTime(9)
Check(Not client.PollAt(sessionEvent, 9) And Not host.PollAt(sessionEvent, 9), "session hello still delayed")
impaired.SetTime(10)
Check(Not client.PollAt(sessionEvent, 10), "flush session hello")
Check(host.PollAt(sessionEvent, 10) And sessionEvent.Kind() = ESessionEventKind.JoinRequested, "session receives impaired hello")
host.Close()
client.Close()

' Configuration rejects invalid probabilities and oversized storage promises.
pair = TLoopbackPair.Create(4, 32)
config = New SImpairmentConfig(0, 0, IMPAIRMENT_PROBABILITY_SCALE + 1)
Check(TImpairedTransport.Create(pair.First(), 4, 32, config) = Null, "reject invalid probability")
config = New SImpairmentConfig
Check(TImpairedTransport.Create(pair.First(), 4, 64, config) = Null, "reject backend oversize")
pair.Close()

Print "GameNet.Impairment tests passed"
