SuperStrict

Framework GameNet.SteamSockets
Import BRL.StandardIO

Const TEST_PORT:Int = 27961

If Not SteamInit(False) Then Throw "Steam is not running"

Local server:TSteamSocketsTransport = TSteamSocketsTransport.ListenIP(TEST_PORT, 1, 2, "127.0.0.1")
If Not server Then Throw "Could not create listener"
Local client:TSteamSocketsTransport = TSteamSocketsTransport.ConnectIP("127.0.0.1", TEST_PORT, 2)
If Not client Then Throw "Could not create client"

Local serverPeer:SNetPeer
Local clientPeer:SNetPeer
Local deadline:Int = MilliSecs() + 5000
While MilliSecs() < deadline And (Not serverPeer.IsValid() Or Not clientPeer.IsValid())
	Local event:SNetEvent
	While server.Poll(event)
		If event.Kind() = ENetEventKind.Connected Then serverPeer = event.Peer()
	Wend
	While client.Poll(event)
		If event.Kind() = ENetEventKind.Connected Then clientPeer = event.Peer()
	Wend
	Delay 1
Wend

If Not serverPeer.IsValid() Or Not clientPeer.IsValid() Then Throw "Connection timed out"

Local payload:Byte[] = [Byte(11), Byte(22), Byte(33)]
If client.Send(clientPeer, 1, EDeliveryMode.ReliableOrdered, payload, Size_T(payload.Length)) <> ETransportResult.Ok Then Throw "Send failed"

Local received:Int
deadline = MilliSecs() + 5000
While MilliSecs() < deadline And Not received
	Local event:SNetEvent
	While server.Poll(event)
		If event.Kind() = ENetEventKind.Data Then
			If event.Channel() <> 1 Or event.Delivery() <> EDeliveryMode.ReliableOrdered Or event.Packet().Length() <> 3 Then Throw "Unexpected packet"
			received = True
		End If
	Wend
	client.Poll(event)
	Delay 1
Wend

If Not received Then Throw "Packet timed out"

Print "Steam Networking Sockets IP loopback passed"
client.Close()
server.Close()
SteamShutdown()
