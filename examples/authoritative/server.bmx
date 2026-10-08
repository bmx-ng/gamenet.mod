SuperStrict

Framework BRL.StandardIO
Import BRL.Math
Import BRL.System
Import GameNet.Session
Import GameNet.ENet

Include "protocol.bmx"

Const MAX_PLAYERS:Int = 1
Const SIMULATION_STEP:Float = 1.0 / 60.0
Const SNAPSHOT_INTERVAL:Int = 50
Const PLAYER_SPEED:Float = 180.0

Local transport:TENetTransport = TENetTransport.Listen(AUTHORITATIVE_PORT, MAX_PLAYERS, 2)
If Not transport Then Throw "Could not listen on UDP port " + AUTHORITATIVE_PORT

Local session:TNetSession = TNetSession.CreateHost(transport, AUTHORITATIVE_APP_ID, AUTHORITATIVE_APP_VERSION, MAX_PLAYERS, 1200)
If Not session Then Throw "Could not create the host session"

Local playerPeer:SNetPeer
Local playerActive:Int
Local playerX:Float = WORLD_WIDTH * 0.5
Local playerY:Float = WORLD_HEIGHT * 0.5
Local inputX:Int
Local inputY:Int
Local lastInputSequence:UInt
Local serverTick:UInt
Local sendBuffer:Byte[32]
Local previousTime:Int = MilliSecs()
Local snapshotTime:Int = previousTime
Local accumulator:Float

Print "Authoritative GameNet host listening on UDP port " + AUTHORITATIVE_PORT
Print "Run client.bmx and move with WASD, the arrow keys, or the on-screen stick."

While session.IsOpen()
	Local event:SSessionEvent
	While session.Poll(event)
		Select event.Kind()
			Case ESessionEventKind.JoinRequested
				If playerActive Or playerPeer.IsValid() Then
					session.Reject(event.Peer(), Int(ESessionRejectCode.ServerFull))
				Else
					Local candidate:SNetPeer = event.Peer()
					If session.Accept(candidate) = ETransportResult.Ok Then playerPeer = candidate
				End If

			Case ESessionEventKind.Joined
				If event.Peer().Equals(playerPeer) Then
					playerActive = True
					playerX = WORLD_WIDTH * 0.5
					playerY = WORLD_HEIGHT * 0.5
					inputX = 0
					inputY = 0
					lastInputSequence = 0
					Local length:Size_T = EncodeSpawn(Byte Ptr(sendBuffer), Size_T(sendBuffer.Length), PLAYER_ENTITY_ID, playerX, playerY)
					session.Send(playerPeer, MSG_SPAWN, CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(sendBuffer), length)
					Print "Player joined"
				End If

			Case ESessionEventKind.Message
				If playerActive And event.Peer().Equals(playerPeer) And event.MessageType() = MSG_INPUT Then
					Local sequence:UInt
					Local newInputX:Int
					Local newInputY:Int
					If event.Channel() = GAMEPLAY_CHANNEL And event.Delivery() = EDeliveryMode.UnreliableSequenced And DecodeInput(event.Payload(), sequence, newInputX, newInputY) Then
						lastInputSequence = sequence
						inputX = Max(-127, Min(127, newInputX))
						inputY = Max(-127, Min(127, newInputY))
					End If
				End If

			Case ESessionEventKind.Left
				If event.Peer().Equals(playerPeer) Then
					playerActive = False
					playerPeer = New SNetPeer
					inputX = 0
					inputY = 0
					Print "Player left"
				End If

			Case ESessionEventKind.Error
				Print "Session error: " + event.Code()
		End Select
	Wend

	Local now:Int = MilliSecs()
	Local elapsed:Int = Min(100, Max(0, now - previousTime))
	previousTime = now
	accumulator :+ Float(elapsed) / 1000.0

	While accumulator >= SIMULATION_STEP
		accumulator :- SIMULATION_STEP
		serverTick :+ 1
		If playerActive Then
			Local moveX:Float = Float(inputX) / 127.0
			Local moveY:Float = Float(inputY) / 127.0
			Local magnitudeSquared:Float = moveX * moveX + moveY * moveY
			If magnitudeSquared > 1.0 Then
				Local inverseMagnitude:Float = 1.0 / Sqr(magnitudeSquared)
				moveX :* inverseMagnitude
				moveY :* inverseMagnitude
			End If
			playerX :+ moveX * PLAYER_SPEED * SIMULATION_STEP
			playerY :+ moveY * PLAYER_SPEED * SIMULATION_STEP
			playerX = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, playerX))
			playerY = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, playerY))
		End If
	Wend

	If playerActive And now - snapshotTime >= SNAPSHOT_INTERVAL Then
		snapshotTime = now
		Local length:Size_T = EncodeSnapshot(Byte Ptr(sendBuffer), Size_T(sendBuffer.Length), serverTick, lastInputSequence, playerX, playerY)
		session.Send(playerPeer, MSG_SNAPSHOT, GAMEPLAY_CHANNEL, EDeliveryMode.UnreliableSequenced, Byte Ptr(sendBuffer), length)
	End If

	Delay 1
Wend

session.Close()
