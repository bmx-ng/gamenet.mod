SuperStrict

Framework BRL.StandardIO
Import GameNet.Session
Import GameNet.Loopback

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Const APP_ID:UInt = $54455354 ' TEST
Const APP_VERSION:UInt = 3

Function AwaitEvent:Int(session:TNetSession, kind:ESessionEventKind, event:SSessionEvent Var, attempts:Int = 20)
	For Local attempt:Int = 0 Until attempts
		If session.Poll(event) And event.Kind() = kind Then Return True
	Next
	Return False
End Function

Local pair:TLoopbackPair = TLoopbackPair.Create(16, 1200)
Local hello:Byte[2]
hello[0] = 12
hello[1] = 34
Local host:TNetSession = TNetSession.CreateHost(pair.First(), APP_ID, APP_VERSION, 1, 1200)
Local client:TNetSession = TNetSession.CreateClient(pair.Second(), APP_ID, APP_VERSION, Byte Ptr(hello), Size_T(hello.Length), 1, 1200)
Check(host <> Null And client <> Null, "create sessions")

Local event:SSessionEvent
client.Poll(event) ' Consume the transport connection and send Hello.
Check(AwaitEvent(host, ESessionEventKind.JoinRequested, event), "host join request")
Check(event.Payload().Length() = 2, "hello payload length")
Check(event.Payload().Data()[0] = 12 And event.Payload().Data()[1] = 34, "hello payload data")
Local hostPeer:SNetPeer = event.Peer()

Local welcome:Byte = 77
Check(host.Accept(hostPeer, Varptr welcome, 1) = ETransportResult.Ok, "host accepts")
Check(AwaitEvent(host, ESessionEventKind.Joined, event), "host joined event")
Check(event.Peer().Equals(hostPeer), "host joined peer")
Check(AwaitEvent(client, ESessionEventKind.Joined, event), "client joined event")
Check(event.Payload().Length() = 1 And event.Payload().Data()[0] = 77, "accept payload")
Local clientPeer:SNetPeer = event.Peer()

Local message:Byte[3]
message[0] = 5
message[1] = 6
message[2] = 7
Check(client.Send(clientPeer, 42, 2, EDeliveryMode.UnreliableSequenced, Byte Ptr(message), Size_T(message.Length)) = ETransportResult.Ok, "client sends message")
Check(AwaitEvent(host, ESessionEventKind.Message, event), "host message event")
Check(event.MessageType() = 42, "message type")
Check(event.Channel() = 2, "message channel")
Check(event.Delivery() = EDeliveryMode.UnreliableSequenced, "message delivery")
Check(event.Payload().Length() = 3 And event.Payload().Data()[2] = 7, "message payload")

host.Close()
client.Close()

' A compatible host can reject application credentials after inspecting hello data.
pair = TLoopbackPair.Create(16, 1200)
host = TNetSession.CreateHost(pair.First(), APP_ID, APP_VERSION, 1, 1200)
client = TNetSession.CreateClient(pair.Second(), APP_ID, APP_VERSION, Null, 0, 1, 1200)
client.Poll(event)
Check(AwaitEvent(host, ESessionEventKind.JoinRequested, event), "reject join request")
hostPeer = event.Peer()
Check(host.Reject(hostPeer, SESSION_REJECT_APPLICATION_BASE + 7) = ETransportResult.Ok, "host rejects")
Check(AwaitEvent(client, ESessionEventKind.Rejected, event), "client rejected event")
Check(event.Code() = SESSION_REJECT_APPLICATION_BASE + 7, "application rejection code")
host.Close()
client.Close()

' Incompatible application versions are rejected before reaching the host application.
pair = TLoopbackPair.Create(16, 1200)
host = TNetSession.CreateHost(pair.First(), APP_ID, APP_VERSION, 1, 1200)
client = TNetSession.CreateClient(pair.Second(), APP_ID, APP_VERSION + 1, Null, 0, 1, 1200)
client.Poll(event)
host.Poll(event) ' Validate Hello and send the automatic rejection.
Check(AwaitEvent(client, ESessionEventKind.Rejected, event), "version rejected event")
Check(event.Code() = Int(ESessionRejectCode.VersionMismatch), "version rejection code")
host.Close()
client.Close()

' Malformed packets are rejected without reading outside their bounds.
pair = TLoopbackPair.Create(16, 1200)
host = TNetSession.CreateHost(pair.First(), APP_ID, APP_VERSION, 1, 1200)
Local raw:TLoopbackTransport = pair.Second()
Local rawEvent:SNetEvent
raw.Poll(rawEvent)
host.Poll(event)
Local malformed:Byte[2]
Check(raw.Send(raw.RemotePeer(), 0, EDeliveryMode.ReliableOrdered, Byte Ptr(malformed), Size_T(malformed.Length)) = ETransportResult.Ok, "send malformed packet")
Check(AwaitEvent(host, ESessionEventKind.Error, event), "malformed packet error")
Check(event.Code() = Int(ESessionRejectCode.ProtocolViolation), "malformed packet error code")
host.Close()
raw.Close()

Print "GameNet.Session tests passed"
