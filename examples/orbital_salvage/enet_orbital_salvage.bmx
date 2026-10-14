SuperStrict

Framework Max2D.SDL3RenderMax2D
Import GameNet.ENet
Import GameNet.Replication
Import GameNet.AuthoritativeSession
Import Max2D.VirtualJoystick
Import BRL.PolledInput
Import BRL.StandardIO

Const SALVAGE_ENET_PORT:Int = 46342

Global serverAddress:String = "192.168.1."
Global localAddress:String
Global editingAddress:Int

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
	statusText = "Hosting on " + HostEndpoint()
	detailText = "Enter this address on the joining device"
End Function

Function HostEndpoint:String()
	If localAddress.Length Then Return localAddress + ":" + SALVAGE_ENET_PORT
	Return "address unavailable, UDP port " + SALVAGE_ENET_PORT
End Function

Function StartENetClient()
	If serverAddress.Length = 0 Then Return
	Local enet:TENetTransport = TENetTransport.CreateClient(1, 2, 0, 0, 900, 900)
	If Not enet Then
		statusText = "Could not create ENet client"
		Return
	End If
	Local pending:SNetPeer
	If enet.Connect(serverAddress, SALVAGE_ENET_PORT, pending) <> ETransportResult.Ok Then
		enet.Close()
		statusText = "Could not connect to " + serverAddress
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
	statusText = "Connecting to " + serverAddress + ":" + SALVAGE_ENET_PORT
	detailText = "Waiting for the LAN host"
End Function

Function InitializeSalvageConnection:Int()
	localAddress = ENetLocalIPv4Address()
	If AppArgs.Length > 1 Then serverAddress = AppArgs[1]
	statusText = "ENet Orbital Salvage"
	detailText = "Host on one device, then enter its Wi-Fi address and join"
	SDLStopTextInput()
	Return True
End Function

Function PollSalvageConnection(now:Int)
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
	If x >= 220 And x < 580 And y >= 142 And y < 194 Then
		editingAddress = True
		SDLStartTextInput(SDL_TEXTINPUT_TYPE_TEXT, SDL_CAPITALIZE_NONE, False, False)
	Else If x >= 90 And x < 370 And y >= 225 And y < 293 Then
		editingAddress = False
		SDLStopTextInput()
		StartENetHost()
	Else If x >= 430 And x < 710 And y >= 225 And y < 293 Then
		editingAddress = False
		SDLStopTextInput()
		StartENetClient()
	Else
		editingAddress = False
		SDLStopTextInput()
	End If
End Function

Function DrawSalvageConnection()
	If editingAddress Then SetColor 52, 128, 210 Else SetColor 45, 59, 82
	DrawRect 220, 142, 360, 52
	SetColor 175, 190, 215
	DrawText "HOST ADDRESS", 232, 151
	SetColor 255, 255, 255
	DrawText serverAddress, 350, 164
	SetColor 31, 105, 170
	DrawRect 90, 225, 280, 68
	SetColor 64, 128, 92
	DrawRect 430, 225, 280, 68
	SetColor 255, 255, 255
	DrawText "HOST GAME", 184, 250
	DrawText "JOIN GAME", 526, 250
	SetColor 165, 180, 205
	DrawText "The host listens on UDP port " + SALVAGE_ENET_PORT, 274, 315
	SetColor 255, 210, 105
	DrawText "THIS DEVICE: " + HostEndpoint(), 265, 345
End Function

Function CloseSalvageConnection()
	SDLStopTextInput()
End Function

Include "orbital_salvage_game.bmx"
