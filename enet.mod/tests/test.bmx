SuperStrict

Framework BRL.StandardIO
Import BRL.System
Import GameNet.ENet

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Const TEST_PORT:Int = 46329

Local server:TENetTransport = TENetTransport.Listen(TEST_PORT, 1, 4, "localhost")
Check(server <> Null, "create server")

Local client:TENetTransport = TENetTransport.CreateClient(1, 4)
Check(client <> Null, "create client")
Local pendingPeer:SNetPeer
Check(client.Connect("localhost", TEST_PORT, pendingPeer) = ETransportResult.Ok, "begin connection")
Check(pendingPeer.IsValid(), "pending peer handle")

Local clientPeer:SNetPeer
Local serverPeer:SNetPeer
Local event:SNetEvent
Local deadline:Int = MilliSecs() + 3000

While (Not clientPeer.IsValid() Or Not serverPeer.IsValid()) And MilliSecs() < deadline
	If client.Poll(event) And event.Kind() = ENetEventKind.Connected Then clientPeer = event.Peer()
	If server.Poll(event) And event.Kind() = ENetEventKind.Connected Then serverPeer = event.Peer()
	Delay 1
Wend

Check(clientPeer.IsValid(), "client connected")
Check(serverPeer.IsValid(), "server connected")
Check(clientPeer.Equals(pendingPeer), "connected peer retains pending handle")

Local sendBytes:Byte[8]
Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(sendBytes), Size_T(sendBytes.Length))
writer.WriteUInt32($decafbad:UInt)
writer.WriteFloat32(7.25)
Check(client.Send(clientPeer, 2, EDeliveryMode.UnreliableSequenced, writer.View().Data(), writer.View().Length()) = ETransportResult.Ok, "send client packet")

Local received:Int
deadline = MilliSecs() + 3000
While Not received And MilliSecs() < deadline
	If server.Poll(event) And event.Kind() = ENetEventKind.Data Then
		Check(event.Peer().Equals(serverPeer), "server packet peer")
		Check(event.Channel() = 2, "server packet channel")
		Check(event.Delivery() = EDeliveryMode.UnreliableSequenced, "server packet delivery")
		Local reader:SPacketReader = New SPacketReader(event.Packet())
		Local number:UInt
		Local decimal:Float
		Check(reader.ReadUInt32(number) And number = $decafbad:UInt, "server packet integer")
		Check(reader.ReadFloat32(decimal) And decimal = 7.25, "server packet float")
		received = True
	End If
	client.Poll(event)
	Delay 1
Wend
Check(received, "server received packet")

Local unreliableByte:Byte = 91
Check(server.Send(serverPeer, 3, EDeliveryMode.Unreliable, Varptr unreliableByte, 1) = ETransportResult.Ok, "send unsequenced packet")
received = False
deadline = MilliSecs() + 3000
While Not received And MilliSecs() < deadline
	If client.Poll(event) And event.Kind() = ENetEventKind.Data Then
		Check(event.Channel() = 3, "unsequenced packet channel")
		Check(event.Delivery() = EDeliveryMode.Unreliable, "unsequenced packet delivery")
		Check(event.Packet().Length() = 1 And event.Packet().Data()[0] = 91, "unsequenced packet data")
		received = True
	End If
	server.Poll(event)
	Delay 1
Wend
Check(received, "client received unsequenced packet")

Check(server.Send(serverPeer, 1, EDeliveryMode.ReliableOrdered, Null, 0) = ETransportResult.Ok, "send empty reliable packet")
received = False
deadline = MilliSecs() + 3000
While Not received And MilliSecs() < deadline
	If client.Poll(event) And event.Kind() = ENetEventKind.Data Then
		Check(event.Channel() = 1, "client packet channel")
		Check(event.Delivery() = EDeliveryMode.ReliableOrdered, "client packet delivery")
		Check(event.Packet().Length() = 0, "empty packet length")
		received = True
	End If
	server.Poll(event)
	Delay 1
Wend
Check(received, "client received packet")

Check(client.Send(clientPeer, 4, EDeliveryMode.Unreliable, Null, 0) = ETransportResult.InvalidChannel, "reject invalid channel")
Check(client.Disconnect(clientPeer, 17) = ETransportResult.Ok, "begin disconnect")

Local clientDisconnected:Int
Local serverDisconnected:Int
deadline = MilliSecs() + 3000
While (Not clientDisconnected Or Not serverDisconnected) And MilliSecs() < deadline
	If client.Poll(event) And event.Kind() = ENetEventKind.Disconnected Then clientDisconnected = True
	If server.Poll(event) And event.Kind() = ENetEventKind.Disconnected Then serverDisconnected = True
	Delay 1
Wend
Check(clientDisconnected, "client disconnected")
Check(serverDisconnected, "server disconnected")

client.Close()
server.Close()

Print "GameNet.ENet tests passed"
