SuperStrict

Framework BRL.StandardIO
Import GameNet.ENet
Import GameNet.LANDiscovery
Import BRL.System

Const EXAMPLE_GAME_ID:String = "net.bmx-ng.gamenet.lan-example"
Const EXAMPLE_PROTOCOL_VERSION:UInt = 1
Const EXAMPLE_GAME_PORT:Int = 46348

If AppArgs.Length < 2 Or (AppArgs[1] <> "host" And AppArgs[1] <> "join") Then
	Print "Usage: lan_discovery <host|join> [discovery-address]"
	Print "Use 127.0.0.1 as the discovery address when running both sides locally."
	End
End If

If AppArgs[1] = "host" Then
	Local transport:TENetTransport = TENetTransport.Listen(EXAMPLE_GAME_PORT, 1, 1)
	If Not transport Then Throw "Could not open ENet game port " + EXAMPLE_GAME_PORT

	Local details:SLANAdvertisement = New SLANAdvertisement(EXAMPLE_GAME_ID, EXAMPLE_PROTOCOL_VERSION, "LAN discovery example", EXAMPLE_GAME_PORT, 1, 2)
	Local advertiser:TLANDiscoveryHost = TLANDiscoveryHost.Create(details)
	If Not advertiser Then Throw "Could not open LAN discovery port " + GAMENET_LAN_DISCOVERY_PORT

	Print "Advertising " + details.name + " on " + ENetLocalIPv4Address() + ":" + EXAMPLE_GAME_PORT
	Local deadline:Int = MilliSecs() + 120000
	Local complete:Int
	While Not complete And MilliSecs() < deadline
		advertiser.Update()
		Local event:SNetEvent
		While transport.Poll(event)
			Select event.Kind()
				Case ENetEventKind.Connected
					Print "Player connected"
					Local greeting:Byte = 42
					If transport.Send(event.Peer(), 0, EDeliveryMode.ReliableOrdered, Varptr greeting, 1) <> ETransportResult.Ok Then Throw "Could not send greeting"
				Case ENetEventKind.Disconnected
					Print "Player disconnected"
					complete = True
				Case ENetEventKind.Error
					Throw "ENet host error " + event.Code()
			End Select
		Wend
		Delay 1
	Wend
	advertiser.Close()
	transport.Close()
Else
	Local browser:TLANDiscoveryBrowser = TLANDiscoveryBrowser.Create(EXAMPLE_GAME_ID, EXAMPLE_PROTOCOL_VERSION)
	If Not browser Then Throw "Could not open LAN browser"
	Local discoveryAddress:String = GAMENET_LAN_BROADCAST_ADDRESS
	If AppArgs.Length > 2 Then discoveryAddress = AppArgs[2]
	If Not browser.Refresh(discoveryAddress) Then Throw "Could not send LAN discovery query"

	Print "Looking for compatible LAN games..."
	Local discoveryDeadline:Int = MilliSecs() + 5000
	While browser.Count() = 0 And MilliSecs() < discoveryDeadline
		browser.Update()
		Delay 1
	Wend
	If browser.Count() = 0 Then Throw "No compatible LAN game was found"

	Local game:TLANDiscoveredGame = browser.Game(0)
	Print "Joining " + game.Name() + " at " + game.Address() + ":" + game.Port()
	Local transport:TENetTransport = TENetTransport.CreateClient(1, 1)
	If Not transport Then Throw "Could not create ENet client"
	Local peer:SNetPeer
	If transport.Connect(game.Address(), game.Port(), peer) <> ETransportResult.Ok Then Throw "Could not begin ENet connection"

	Local connectionDeadline:Int = MilliSecs() + 5000
	Local complete:Int
	While Not complete And MilliSecs() < connectionDeadline
		Local event:SNetEvent
		While transport.Poll(event)
			Select event.Kind()
				Case ENetEventKind.Data
					If event.Packet().Length() = 1 And event.Packet().Data()[0] = 42 Then
						Print "Received the host greeting"
						transport.Disconnect(event.Peer())
						complete = True
					End If
				Case ENetEventKind.Disconnected
					If Not complete Then Throw "Disconnected before greeting"
				Case ENetEventKind.Error
					Throw "ENet client error " + event.Code()
			End Select
		Wend
		Delay 1
	Wend
	If Not complete Then Throw "Timed out waiting for the host greeting"
	browser.Close()
	transport.Close()
End If
