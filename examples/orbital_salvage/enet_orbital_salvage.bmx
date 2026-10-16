SuperStrict

Framework Max2D.SDL3RenderMax2D
Import GameNet.ENet
Import GameNet.LANDiscovery
Import GameNet.Replication
Import GameNet.AuthoritativeSession
Import Max2D.VirtualJoystick
Import BRL.PolledInput
Import BRL.StandardIO

Const SALVAGE_ENET_PORT:Int = 46342
Const SALVAGE_LAN_GAME_ID:String = "net.bmx-ng.gamenet.orbital-salvage"
Const SALVAGE_VISIBLE_LAN_GAMES:Int = 3

Global serverAddress:String = "192.168.1."
Global serverPort:Int = SALVAGE_ENET_PORT
Global localAddress:String
Global editingAddress:Int
Global lanAdvertiser:TLANDiscoveryHost
Global lanBrowser:TLANDiscoveryBrowser

Function StartENetHost()
	Local enet:TENetTransport = TENetTransport.Listen(SALVAGE_ENET_PORT, 1, 2, ENET_HOST_ANY, 0, 0, 900, 900)
	If Not enet Then
		statusText = "Could not host UDP port " + SALVAGE_ENET_PORT
		Return
	End If
	transport = enet
	isAuthority = True
	localPlayer = 0
	session = TNetSession.CreateHost(transport, SALVAGE_APP_ID, SALVAGE_APP_VERSION, 1, 900)
	If Not session Or Not CreateReplicationWorld() Then
		statusText = "Could not create ENet host world"
		If session Then session.Close()
		session = Null
		Return
	End If
	Local advertisement:SLANAdvertisement = New SLANAdvertisement(SALVAGE_LAN_GAME_ID, SALVAGE_APP_VERSION, "Orbital Salvage", SALVAGE_ENET_PORT, 1, 2)
	lanAdvertiser = TLANDiscoveryHost.Create(advertisement)
	If lanBrowser Then lanBrowser.Close()
	lanBrowser = Null
	statusText = "Hosting on " + HostEndpoint()
	If lanAdvertiser Then
		detailText = "Waiting for another pilot on the local network"
	Else
		detailText = "Discovery unavailable; enter this address on the joining device"
	End If
End Function

Function HostEndpoint:String()
	If localAddress.Length Then Return localAddress + ":" + SALVAGE_ENET_PORT
	Return "address unavailable, UDP port " + SALVAGE_ENET_PORT
End Function

Function StartENetClient(address:String = "", port:Int = SALVAGE_ENET_PORT)
	If address.Length = 0 Then address = serverAddress
	If address.Length = 0 Or port < 1 Or port > 65535 Then Return
	Local enet:TENetTransport = TENetTransport.CreateClient(1, 2, 0, 0, 900, 900)
	If Not enet Then
		statusText = "Could not create ENet client"
		Return
	End If
	Local pending:SNetPeer
	If enet.Connect(address, port, pending) <> ETransportResult.Ok Then
		enet.Close()
		statusText = "Could not connect to " + address
		Return
	End If
	transport = enet
	isAuthority = False
	localPlayer = 1
	session = TNetSession.CreateClient(transport, SALVAGE_APP_ID, SALVAGE_APP_VERSION, Null, 0, 1, 900)
	If Not session Or Not CreateReplicationWorld() Then
		statusText = "Could not create ENet client world"
		If session Then session.Close()
		session = Null
		Return
	End If
	serverAddress = address
	serverPort = port
	If lanBrowser Then lanBrowser.Close()
	lanBrowser = Null
	statusText = "Connecting to " + serverAddress + ":" + serverPort
	detailText = "Waiting for the LAN host"
End Function

Function InitializeSalvageConnection:Int()
	localAddress = ENetLocalIPv4Address()
	If AppArgs.Length > 1 Then serverAddress = AppArgs[1]
	statusText = "ENet Orbital Salvage"
	detailText = "Choose a discovered game, or host one for another pilot"
	lanBrowser = TLANDiscoveryBrowser.Create(SALVAGE_LAN_GAME_ID, SALVAGE_APP_VERSION)
	If Not lanBrowser Then detailText = "LAN discovery unavailable; host or enter an address manually"
	SDLStopTextInput()
	Return True
End Function

Function PollSalvageConnection(now:Int)
	If lanAdvertiser Then
		If joined Then
			lanAdvertiser.Close()
			lanAdvertiser = Null
		Else
			lanAdvertiser.Update()
		End If
	Else If lanBrowser And Not session Then
		lanBrowser.UpdateAt(UInt(now))
	End If
End Function

Function HandleSalvageConnectionInput()
	If session Then Return
	If editingAddress Then
		Local character:Int = GetChar()
		While character
			Select character
				Case 8, 127
					If serverAddress.Length Then serverAddress = serverAddress[..serverAddress.Length - 1]
				Case 13
					editingAddress = False
					SDLStopTextInput()
				Default
					If (character >= Asc("0") And character <= Asc("9")) Or character = Asc(".") Then
						If serverAddress.Length < 45 Then serverAddress :+ Chr(character)
					End If
			End Select
			character = GetChar()
		Wend
	End If
	If Not MouseHit(1) Then Return
	Local x:Float = VirtualMouseX()
	Local y:Float = VirtualMouseY()
	If lanBrowser And x >= 110 And x < 690 And y >= 145 And y < 297 Then
		Local gameIndex:Int = Int((y - 145) / 52)
		If gameIndex >= 0 And gameIndex < Min(lanBrowser.Count(), SALVAGE_VISIBLE_LAN_GAMES) Then
			Local game:TLANDiscoveredGame = lanBrowser.Game(gameIndex)
			If game Then
				editingAddress = False
				SDLStopTextInput()
				StartENetClient(game.Address(), game.Port())
			End If
		End If
	Else If x >= 220 And x < 580 And y >= 325 And y < 377 Then
		editingAddress = True
		SDLStartTextInput(SDL_TEXTINPUT_TYPE_TEXT, SDL_CAPITALIZE_NONE, False, False)
	Else If x >= 90 And x < 370 And y >= 405 And y < 473 Then
		editingAddress = False
		SDLStopTextInput()
		StartENetHost()
	Else If x >= 430 And x < 710 And y >= 405 And y < 473 Then
		editingAddress = False
		SDLStopTextInput()
		StartENetClient()
	Else
		editingAddress = False
		SDLStopTextInput()
	End If
End Function

Function DrawSalvageConnection()
	SetColor 175, 190, 215
	DrawText "GAMES ON THIS NETWORK", 110, 120
	If lanBrowser And lanBrowser.Count() > 0 Then
		For Local index:Int = 0 Until Min(lanBrowser.Count(), SALVAGE_VISIBLE_LAN_GAMES)
			Local game:TLANDiscoveredGame = lanBrowser.Game(index)
			Local y:Int = 145 + index * 52
			SetColor 38, 85, 112
			DrawRect 110, y, 580, 44
			SetColor 255, 255, 255
			DrawText game.Name(), 126, y + 7
			SetColor 155, 220, 190
			Local joinText:String = "JOIN  " + game.Address() + ":" + game.Port()
			DrawText joinText, 674 - TextWidth(joinText), y + 7
		Next
	Else
		SetColor 29, 42, 62
		DrawRect 110, 145, 580, 44
		SetColor 155, 170, 195
		DrawText "Searching for compatible Orbital Salvage games...", 126, 157
	End If

	If editingAddress Then SetColor 52, 128, 210 Else SetColor 45, 59, 82
	DrawRect 220, 325, 360, 52
	SetColor 175, 190, 215
	DrawText "MANUAL ADDRESS", 232, 334
	SetColor 255, 255, 255
	DrawText serverAddress, 370, 347
	SetColor 31, 105, 170
	DrawRect 90, 405, 280, 68
	SetColor 64, 128, 92
	DrawRect 430, 405, 280, 68
	SetColor 255, 255, 255
	DrawText "HOST GAME", 184, 430
	DrawText "JOIN MANUALLY", 505, 430
	SetColor 165, 180, 205
	DrawText "Discovery finds compatible hosts; manual join remains available", 204, 495
	SetColor 255, 210, 105
	DrawText "THIS DEVICE: " + HostEndpoint(), 265, 525
End Function

Function CloseSalvageConnection()
	SDLStopTextInput()
	If lanAdvertiser Then lanAdvertiser.Close()
	lanAdvertiser = Null
	If lanBrowser Then lanBrowser.Close()
	lanBrowser = Null
End Function

Include "orbital_salvage_game.bmx"
