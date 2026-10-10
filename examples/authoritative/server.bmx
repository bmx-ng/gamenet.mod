SuperStrict

Framework BRL.StandardIO
Import BRL.Math
Import BRL.System
Import GameNet.Session
Import GameNet.ENet
Import GameNet.AuthoritativeSession

Include "protocol.bmx"

Const SNAPSHOT_INTERVAL:Int = 16

Struct SServerPlayer
	Field peer:SNetPeer
	Field active:Int
	Field x:Float
	Field y:Float
	Field inputStarted:Int
End Struct

Global session:TNetSession
Global authoritative:TAuthoritativeServerSession
Global players:SServerPlayer[AUTHORITATIVE_MAX_PLAYERS]
Global sendBuffer:Byte[32]
Global snapshotStateBuffer:Byte[AUTHORITATIVE_SNAPSHOT_STATE_SIZE]
Global serverTick:UInt

Function ApplyInput(x:Float Var, y:Float Var, inputX:Int, inputY:Int)
	Local moveX:Float = Float(inputX) / 127.0
	Local moveY:Float = Float(inputY) / 127.0
	Local magnitudeSquared:Float = moveX * moveX + moveY * moveY
	If magnitudeSquared > 1.0 Then
		Local inverseMagnitude:Float = 1.0 / Sqr(magnitudeSquared)
		moveX :* inverseMagnitude
		moveY :* inverseMagnitude
	End If
	x :+ moveX * AUTHORITATIVE_PLAYER_SPEED * AUTHORITATIVE_SIMULATION_STEP
	y :+ moveY * AUTHORITATIVE_PLAYER_SPEED * AUTHORITATIVE_SIMULATION_STEP
	x = Max(PLAYER_RADIUS, Min(WORLD_WIDTH - PLAYER_RADIUS, x))
	y = Max(PLAYER_RADIUS, Min(WORLD_HEIGHT - PLAYER_RADIUS, y))
End Function

Function PlayerIndexForPeer:Int(peer:SNetPeer)
	For Local index:Int = 0 Until players.Length
		If players[index].peer.IsValid() And players[index].peer.Equals(peer) Then Return index
	Next
	Return -1
End Function

Function AvailablePlayerIndex:Int()
	For Local index:Int = 0 Until players.Length
		If Not players[index].peer.IsValid() Then Return index
	Next
	Return -1
End Function

Function SendSpawn(recipient:SNetPeer, playerIndex:Int)
	Local entityId:UInt = UInt(playerIndex + 1)
	Local length:Size_T = EncodeSpawn(Byte Ptr(sendBuffer), Size_T(sendBuffer.Length), entityId, players[playerIndex].x, players[playerIndex].y)
	session.Send(recipient, MSG_SPAWN, CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(sendBuffer), length)
End Function

Function SendDespawn(recipient:SNetPeer, entityId:UInt)
	Local length:Size_T = EncodeEntity(Byte Ptr(sendBuffer), Size_T(sendBuffer.Length), entityId)
	session.Send(recipient, MSG_DESPAWN, CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(sendBuffer), length)
End Function

Function AnnounceJoinedPlayer(joinedIndex:Int)
	For Local index:Int = 0 Until players.Length
		If players[index].active Then SendSpawn(players[joinedIndex].peer, index)
	Next
	For Local index:Int = 0 Until players.Length
		If index <> joinedIndex And players[index].active Then SendSpawn(players[index].peer, joinedIndex)
	Next
End Function

Function AnnounceLeftPlayer(leftIndex:Int)
	Local entityId:UInt = UInt(leftIndex + 1)
	For Local index:Int = 0 Until players.Length
		If index <> leftIndex And players[index].active Then SendDespawn(players[index].peer, entityId)
	Next
End Function

Function SendSnapshots()
	For Local playerIndex:Int = 0 Until players.Length
		If Not players[playerIndex].active Then Continue
		Local length:Size_T = EncodePositionState(Byte Ptr(snapshotStateBuffer), Size_T(snapshotStateBuffer.Length), players[playerIndex].x, players[playerIndex].y)
		If length = 0 Then Continue
		For Local recipientIndex:Int = 0 Until players.Length
			If players[recipientIndex].active Then authoritative.SendSnapshot(session, recipientIndex, playerIndex, serverTick, Byte Ptr(snapshotStateBuffer), length)
		Next
	Next
End Function

Local transport:TENetTransport = TENetTransport.Listen(AUTHORITATIVE_PORT, AUTHORITATIVE_MAX_PLAYERS, 2)
If Not transport Then Throw "Could not listen on UDP port " + AUTHORITATIVE_PORT

session = TNetSession.CreateHost(transport, AUTHORITATIVE_APP_ID, AUTHORITATIVE_APP_VERSION, AUTHORITATIVE_MAX_PLAYERS, 1200)
If Not session Then Throw "Could not create the host session"
Local authoritativeConfig:SAuthoritativeSessionConfig = New SAuthoritativeSessionConfig(AUTHORITATIVE_MAX_PLAYERS, AUTHORITATIVE_MAX_PLAYERS, AUTHORITATIVE_INPUT_HISTORY_CAPACITY, AUTHORITATIVE_SERVER_INPUT_CAPACITY, AUTHORITATIVE_SNAPSHOT_CAPACITY, AUTHORITATIVE_INPUT_PAYLOAD_SIZE, AUTHORITATIVE_SNAPSHOT_STATE_SIZE, AUTHORITATIVE_REDUNDANT_INPUTS, 60.0, 2.0, 12.0, MSG_INPUT, MSG_SNAPSHOT, GAMEPLAY_CHANNEL)
authoritative = TAuthoritativeServerSession.Create(authoritativeConfig)
If Not authoritative Then Throw "Could not create the authoritative server session"

Local previousTime:Int = MilliSecs()
Local snapshotTime:Int = previousTime
Local accumulator:Float

Print "Authoritative GameNet host listening on UDP port " + AUTHORITATIVE_PORT
Print "Up to " + AUTHORITATIVE_MAX_PLAYERS + " clients can join."

While session.IsOpen()
	Local event:SSessionEvent
	While session.Poll(event)
		Select event.Kind()
			Case ESessionEventKind.JoinRequested
				Local index:Int = AvailablePlayerIndex()
				If index < 0 Then
					session.Reject(event.Peer(), Int(ESessionRejectCode.ServerFull))
				Else
					players[index].peer = event.Peer()
					Local length:Size_T = EncodeEntity(Byte Ptr(sendBuffer), Size_T(sendBuffer.Length), UInt(index + 1))
					If session.Accept(event.Peer(), Byte Ptr(sendBuffer), length) <> ETransportResult.Ok Then players[index] = New SServerPlayer
				End If

			Case ESessionEventKind.Joined
				Local index:Int = PlayerIndexForPeer(event.Peer())
				If index >= 0 Then
					players[index].active = True
					players[index].x = WORLD_WIDTH * (Float(index + 1) / Float(AUTHORITATIVE_MAX_PLAYERS + 1))
					players[index].y = WORLD_HEIGHT * 0.5
					players[index].inputStarted = False
					If authoritative.BindPlayer(index, event.Peer()) Then
						AnnounceJoinedPlayer(index)
						Print "Player " + (index + 1) + " joined"
					Else
						Throw "Could not bind authoritative player " + (index + 1)
					End If
				End If

			Case ESessionEventKind.Message
				Local index:Int = PlayerIndexForPeer(event.Peer())
				If index >= 0 And players[index].active And event.MessageType() = MSG_INPUT And event.Channel() = GAMEPLAY_CHANNEL And event.Delivery() = EDeliveryMode.UnreliableSequenced Then
					If Not authoritative.ReceiveInputs(index, event.Peer(), event.Payload()) Then Print "Rejected input packet from player " + (index + 1)
				End If

			Case ESessionEventKind.Left
				Local index:Int = PlayerIndexForPeer(event.Peer())
				If index >= 0 Then
					If players[index].active Then AnnounceLeftPlayer(index)
					authoritative.UnbindPlayer(index)
					players[index] = New SServerPlayer
					Print "Player " + (index + 1) + " left"
				End If

			Case ESessionEventKind.Error
				Print "Session error: " + event.Code()
		End Select
	Wend

	Local now:Int = MilliSecs()
	Local elapsed:Int = Min(100, Max(0, now - previousTime))
	previousTime = now
	accumulator :+ Float(elapsed) / 1000.0
	While accumulator >= AUTHORITATIVE_SIMULATION_STEP
		accumulator :- AUTHORITATIVE_SIMULATION_STEP
		serverTick :+ 1
		For Local index:Int = 0 Until players.Length
			If Not players[index].active Then Continue
			If Not players[index].inputStarted Then
				If authoritative.InputCount(index) < AUTHORITATIVE_SERVER_INPUT_DELAY Then Continue
				players[index].inputStarted = True
			End If
			Local input:SPredictionInput
			If authoritative.PeekInput(index, input) Then
				Local inputX:Int
				Local inputY:Int
				If DecodeMovementInput(input.Payload(), inputX, inputY) Then
					ApplyInput(players[index].x, players[index].y, inputX, inputY)
					authoritative.AcknowledgeInput(index, input.Sequence())
				End If
			End If
		Next
	Wend

	If now - snapshotTime >= SNAPSHOT_INTERVAL Then
		snapshotTime = now
		SendSnapshots()
	End If

	Delay 1
Wend

session.Close()
