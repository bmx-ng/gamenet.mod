SuperStrict

Framework BRL.StandardIO
Import GameNet.Loopback

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local pair:TLoopbackPair = TLoopbackPair.Create(3, 32)
Check(pair <> Null, "create pair")

Local first:TLoopbackTransport = pair.First()
Local second:TLoopbackTransport = pair.Second()
Local event:SNetEvent

Check(first.Poll(event), "first connected event")
Check(event.Kind() = ENetEventKind.Connected, "first connected kind")
Check(second.Poll(event), "second connected event")
Check(event.Kind() = ENetEventKind.Connected, "second connected kind")

Local bytes:Byte[8]
Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(bytes), Size_T(bytes.Length))
writer.WriteUInt16($cafe)
writer.WriteFloat32(3.5)

Check(first.Send(first.RemotePeer(), 7, EDeliveryMode.UnreliableSequenced, writer.View().Data(), writer.View().Length()) = ETransportResult.Ok, "send packet")
bytes[0] = 0 ' The loopback transport owns a copy.

Check(second.Poll(event), "receive packet")
Check(event.Kind() = ENetEventKind.Data, "data event kind")
Check(event.Channel() = 7, "logical channel")
Check(event.Delivery() = EDeliveryMode.UnreliableSequenced, "delivery mode")

Local reader:SPacketReader = New SPacketReader(event.Packet())
Local number:UInt
Local decimal:Float
Check(reader.ReadUInt16(number) And number = $cafe, "packet integer")
Check(reader.ReadFloat32(decimal) And decimal = 3.5, "packet float")
Check(reader.Remaining() = 0, "packet fully consumed")

Local large:Byte[33]
Check(first.Send(first.RemotePeer(), 0, EDeliveryMode.ReliableOrdered, Byte Ptr(large), Size_T(large.Length)) = ETransportResult.PacketTooLarge, "packet size limit")

Check(first.Disconnect(first.RemotePeer(), 42) = ETransportResult.Ok, "disconnect")
Check(first.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 42, "local disconnect event")
Check(second.Poll(event) And event.Kind() = ENetEventKind.Disconnected And event.Code() = 42, "remote disconnect event")
Check(first.Send(first.RemotePeer(), 0, EDeliveryMode.ReliableOrdered, Null, 0) = ETransportResult.Closed, "send after disconnect")

Print "GameNet.Loopback tests passed"
