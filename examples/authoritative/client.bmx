SuperStrict

Framework Max2D.SDL3RenderMax2D
Import BRL.PolledInput
Import Max2D.VirtualJoystick
Import GameNet.Session
Import GameNet.ENet

Include "protocol.bmx"

Const INPUT_INTERVAL:Int = 33

Local serverAddress:String = "127.0.0.1"
Local serverPort:Int = AUTHORITATIVE_PORT
If AppArgs.Length > 1 Then serverAddress = AppArgs[1]
If AppArgs.Length > 2 Then serverPort = Int(AppArgs[2])

Local transport:TENetTransport = TENetTransport.CreateClient(1, 2)
If Not transport Then Throw "Could not create the ENet client"
Local pendingPeer:SNetPeer
If transport.Connect(serverAddress, serverPort, pendingPeer) <> ETransportResult.Ok Then Throw "Could not begin connecting to " + serverAddress

Local session:TNetSession = TNetSession.CreateClient(transport, AUTHORITATIVE_APP_ID, AUTHORITATIVE_APP_VERSION, Null, 0, 1, 1200)
If Not session Then Throw "Could not create the client session"

Graphics 960, 540, 0
SetVirtualResolution(Int(WORLD_WIDTH), Int(WORLD_HEIGHT), VIRTUAL_LETTERBOX)
SetVirtualBarColor 6, 9, 16
SetClsColor 12, 18, 30

Local controls:TVirtualJoystick = TVirtualJoystick.Create(0)
Local hostPeer:SNetPeer
Local status:String = "Connecting to " + serverAddress + ":" + serverPort + "..."
Local spawned:Int
Local entityId:UInt
Local playerX:Float = WORLD_WIDTH * 0.5
Local playerY:Float = WORLD_HEIGHT * 0.5
Local inputSequence:UInt
Local acknowledgedInput:UInt
Local serverTick:UInt
Local inputBuffer:Byte[16]
Local nextInputTime:Int = MilliSecs()

While Not KeyDown(KEY_ESCAPE) And Not AppTerminate()
	Local event:SSessionEvent
	While session.Poll(event)
		Select event.Kind()
			Case ESessionEventKind.Joined
				hostPeer = event.Peer()
				status = "Joined; waiting for the server to spawn the player"

			Case ESessionEventKind.Rejected
				status = "Join rejected (code " + event.Code() + ")"

			Case ESessionEventKind.Left
				status = "Disconnected (code " + event.Code() + ")"
				spawned = False
				hostPeer = New SNetPeer

			Case ESessionEventKind.Message
				Select event.MessageType()
					Case MSG_SPAWN
						If event.Channel() = CONTROL_CHANNEL And event.Delivery() = EDeliveryMode.ReliableOrdered Then
							If DecodeSpawn(event.Payload(), entityId, playerX, playerY) Then
								spawned = True
								status = "Connected"
							End If
						End If

					Case MSG_SNAPSHOT
						If event.Channel() = GAMEPLAY_CHANNEL And event.Delivery() = EDeliveryMode.UnreliableSequenced Then
							DecodeSnapshot(event.Payload(), serverTick, acknowledgedInput, playerX, playerY)
						End If
				End Select

			Case ESessionEventKind.Error
				status = "Session error (code " + event.Code() + ")"
		End Select
	Wend

	Local axisX:Float = controls.X()
	Local axisY:Float = controls.Y()
	axisX :+ Float(KeyDown(KEY_D) Or KeyDown(KEY_RIGHT))
	axisX :- Float(KeyDown(KEY_A) Or KeyDown(KEY_LEFT))
	axisY :+ Float(KeyDown(KEY_S) Or KeyDown(KEY_DOWN))
	axisY :- Float(KeyDown(KEY_W) Or KeyDown(KEY_UP))
	axisX = Max(-1.0, Min(1.0, axisX))
	axisY = Max(-1.0, Min(1.0, axisY))

	Local now:Int = MilliSecs()
	If spawned And hostPeer.IsValid() And now >= nextInputTime Then
		nextInputTime = now + INPUT_INTERVAL
		inputSequence :+ 1
		Local length:Size_T = EncodeInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), inputSequence, Int(axisX * 127.0), Int(axisY * 127.0))
		session.Send(hostPeer, MSG_INPUT, GAMEPLAY_CHANNEL, EDeliveryMode.UnreliableSequenced, Byte Ptr(inputBuffer), length)
	End If

	Cls
	SetColor 25, 38, 57
	For Local x:Int = 0 Until Int(WORLD_WIDTH) Step 40
		DrawLine x, 0, x, WORLD_HEIGHT
	Next
	For Local y:Int = 0 Until Int(WORLD_HEIGHT) Step 40
		DrawLine 0, y, WORLD_WIDTH, y
	Next

	If spawned Then
		SetColor 55, 170, 240
		DrawOval playerX - PLAYER_RADIUS, playerY - PLAYER_RADIUS, PLAYER_RADIUS * 2.0, PLAYER_RADIUS * 2.0
	End If

	SetColor 255, 255, 255
	DrawText status, 12, 12
	DrawText "Server-authoritative position", 12, 32
	DrawText "Input " + inputSequence + "  acknowledged " + acknowledgedInput + "  server tick " + serverTick, 12, 52
	DrawText "WASD / arrows / on-screen stick", 12, 72
	controls.Render()
	Flip
Wend

controls.Free()
session.Close()
EndGraphics
