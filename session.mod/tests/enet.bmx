SuperStrict

Framework BRL.StandardIO
Import BRL.System
Import GameNet.Session
Import GameNet.ENet

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Const TEST_PORT:Int = 46331
Const APP_ID:UInt = $53455353 ' SESS
Const APP_VERSION:UInt = 1

Local serverTransport:TENetTransport = TENetTransport.Listen(TEST_PORT, 1, 4, "localhost")
Check(serverTransport <> Null, "create ENet server")
Local clientTransport:TENetTransport = TENetTransport.CreateClient(1, 4)
Check(clientTransport <> Null, "create ENet client")
Local pendingPeer:SNetPeer
Check(clientTransport.Connect("localhost", TEST_PORT, pendingPeer) = ETransportResult.Ok, "connect ENet client")

Local host:TNetSession = TNetSession.CreateHost(serverTransport, APP_ID, APP_VERSION, 1, 1200)
Local client:TNetSession = TNetSession.CreateClient(clientTransport, APP_ID, APP_VERSION, Null, 0, 1, 1200)
Check(host <> Null And client <> Null, "create ENet sessions")

Local hostEvent:SSessionEvent
Local clientEvent:SSessionEvent
Local hostPeer:SNetPeer
Local deadline:Int = MilliSecs() + 3000
While Not hostPeer.IsValid() And MilliSecs() < deadline
	client.Poll(clientEvent)
	If host.Poll(hostEvent) And hostEvent.Kind() = ESessionEventKind.JoinRequested Then hostPeer = hostEvent.Peer()
	Delay 1
Wend
Check(hostPeer.IsValid(), "ENet host receives join request")

Check(host.Accept(hostPeer) = ETransportResult.Ok, "ENet host accepts peer")
Local hostJoined:Int
Local clientJoined:Int
Local clientPeer:SNetPeer
deadline = MilliSecs() + 3000
While (Not hostJoined Or Not clientJoined) And MilliSecs() < deadline
	If host.Poll(hostEvent) And hostEvent.Kind() = ESessionEventKind.Joined Then hostJoined = True
	If client.Poll(clientEvent) And clientEvent.Kind() = ESessionEventKind.Joined Then
		clientJoined = True
		clientPeer = clientEvent.Peer()
	End If
	Delay 1
Wend
Check(hostJoined And clientJoined, "ENet sessions join")
Check(clientPeer.Equals(pendingPeer), "session retains pending ENet peer")

Local payload:Byte[2]
payload[0] = 9
payload[1] = 8
Check(client.Send(clientPeer, 17, 1, EDeliveryMode.UnreliableSequenced, Byte Ptr(payload), Size_T(payload.Length)) = ETransportResult.Ok, "send ENet session message")

Local received:Int
deadline = MilliSecs() + 3000
While Not received And MilliSecs() < deadline
	client.Poll(clientEvent)
	If host.Poll(hostEvent) And hostEvent.Kind() = ESessionEventKind.Message Then
		Check(hostEvent.MessageType() = 17, "ENet session message type")
		Check(hostEvent.Channel() = 1, "ENet session channel")
		Check(hostEvent.Delivery() = EDeliveryMode.UnreliableSequenced, "ENet session delivery")
		Check(hostEvent.Payload().Length() = 2 And hostEvent.Payload().Data()[0] = 9, "ENet session payload")
		received = True
	End If
	Delay 1
Wend
Check(received, "receive ENet session message")

client.Close()
host.Close()

Print "GameNet.Session ENet tests passed"
