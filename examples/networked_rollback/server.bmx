SuperStrict

Framework BRL.StandardIO
Import BRL.System
Import GameNet.Session
Import GameNet.ENet

Include "protocol.bmx"

Const RELAY_DELAY_SLOTS:Int = 256
Const RELAY_DELAY_PACKET_SIZE:Int = 128

Struct SRelayPlayer
	Field peer:SNetPeer
	Field active:Int
End Struct

Global relaySession:TNetSession
Global relayPlayers:SRelayPlayer[ROLLBACK_PLAYER_COUNT]
Global relayBuffer:Byte[64]
Global relayMatchId:UInt
Global relayInputPacketCount:UInt
Global relayDelayMillis:Int
Global relayDropEvery:Int
Global relayDelayedValid:Byte[RELAY_DELAY_SLOTS]
Global relayDelayedAt:Int[RELAY_DELAY_SLOTS]
Global relayDelayedPeer:SNetPeer[RELAY_DELAY_SLOTS]
Global relayDelayedLength:Size_T[RELAY_DELAY_SLOTS]
Global relayDelayedStorage:Byte[RELAY_DELAY_SLOTS * RELAY_DELAY_PACKET_SIZE]

Function RelayPlayerForPeer:Int(peer:SNetPeer)
	For Local player:Int = 0 Until relayPlayers.Length
		If relayPlayers[player].peer.IsValid() And relayPlayers[player].peer.Equals(peer) Then Return player
	Next
	Return -1
End Function

Function AvailableRelayPlayer:Int()
	For Local player:Int = 0 Until relayPlayers.Length
		If Not relayPlayers[player].peer.IsValid() Then Return player
	Next
	Return -1
End Function

Function ActiveRelayPlayers:Int()
	Local count:Int
	For Local player:Int = 0 Until relayPlayers.Length
		If relayPlayers[player].active Then count :+ 1
	Next
	Return count
End Function

Function OtherRelayPlayer:Int(player:Int)
	Return 1 - player
End Function

Function StartRelayMatch()
	If ActiveRelayPlayers() <> ROLLBACK_PLAYER_COUNT Then Return
	relayMatchId :+ 1
	If relayMatchId = 0 Then relayMatchId = 1
	Local length:Size_T = EncodeMatch(Byte Ptr(relayBuffer), Size_T(relayBuffer.Length), relayMatchId)
	For Local player:Int = 0 Until relayPlayers.Length
		relaySession.Send(relayPlayers[player].peer, ROLLBACK_MSG_START, ROLLBACK_CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(relayBuffer), length)
	Next
	Print "Started rollback match " + relayMatchId
End Function

Function ForwardRelayMessage(player:Int, event:SSessionEvent)
	Local other:Int = OtherRelayPlayer(player)
	If other < 0 Or other >= relayPlayers.Length Or Not relayPlayers[other].active Then Return
	relaySession.Send(relayPlayers[other].peer, event.MessageType(), event.Channel(), event.Delivery(), event.Payload().Data(), event.Payload().Length())
End Function

Function ForwardRelayInput(player:Int, event:SSessionEvent)
	Local other:Int = OtherRelayPlayer(player)
	If other < 0 Or other >= relayPlayers.Length Or Not relayPlayers[other].active Then Return
	relayInputPacketCount :+ 1
	If relayDropEvery > 0 And relayInputPacketCount Mod UInt(relayDropEvery) = 0 Then Return
	If relayDelayMillis <= 0 Then
		ForwardRelayMessage(player, event)
		Return
	End If
	If event.Payload().Length() > Size_T(RELAY_DELAY_PACKET_SIZE) Then Return
	For Local slot:Int = 0 Until RELAY_DELAY_SLOTS
		If relayDelayedValid[slot] Then Continue
		relayDelayedValid[slot] = True
		relayDelayedAt[slot] = MilliSecs() + relayDelayMillis
		relayDelayedPeer[slot] = relayPlayers[other].peer
		relayDelayedLength[slot] = event.Payload().Length()
		MemCopy(Byte Ptr(relayDelayedStorage) + Size_T(slot * RELAY_DELAY_PACKET_SIZE), event.Payload().Data(), event.Payload().Length())
		Return
	Next
End Function

Function FlushDelayedInputs()
	Local now:Int = MilliSecs()
	For Local slot:Int = 0 Until RELAY_DELAY_SLOTS
		If Not relayDelayedValid[slot] Or now < relayDelayedAt[slot] Then Continue
		relaySession.Send(relayDelayedPeer[slot], ROLLBACK_MSG_INPUT, ROLLBACK_GAMEPLAY_CHANNEL, EDeliveryMode.UnreliableSequenced, Byte Ptr(relayDelayedStorage) + Size_T(slot * RELAY_DELAY_PACKET_SIZE), relayDelayedLength[slot])
		relayDelayedValid[slot] = False
	Next
End Function

Local port:Int = ROLLBACK_PORT
If AppArgs.Length > 1 Then port = Int(AppArgs[1])
If AppArgs.Length > 2 Then relayDelayMillis = Max(0, Int(AppArgs[2]))
If AppArgs.Length > 3 Then relayDropEvery = Max(0, Int(AppArgs[3]))
Local transport:TENetTransport = TENetTransport.Listen(port, ROLLBACK_PLAYER_COUNT, 2)
If Not transport Then Throw "Could not listen on UDP port " + port
relaySession = TNetSession.CreateHost(transport, ROLLBACK_APP_ID, ROLLBACK_APP_VERSION, ROLLBACK_PLAYER_COUNT, 1200)
If Not relaySession Then Throw "Could not create rollback relay session"

Print "Networked rollback relay listening on UDP port " + port
Print "Input delay " + relayDelayMillis + " ms; drop every " + relayDropEvery + " packets (zero disables)"
Print "Waiting for two players..."

While relaySession.IsOpen()
	Local event:SSessionEvent
	While relaySession.Poll(event)
		Select event.Kind()
			Case ESessionEventKind.JoinRequested
				Local player:Int = AvailableRelayPlayer()
				If player < 0 Then
					relaySession.Reject(event.Peer(), Int(ESessionRejectCode.ServerFull))
				Else
					relayPlayers[player].peer = event.Peer()
					Local length:Size_T = EncodePlayerAssignment(Byte Ptr(relayBuffer), Size_T(relayBuffer.Length), player)
					If relaySession.Accept(event.Peer(), Byte Ptr(relayBuffer), length) <> ETransportResult.Ok Then relayPlayers[player] = New SRelayPlayer
				End If

			Case ESessionEventKind.Joined
				Local player:Int = RelayPlayerForPeer(event.Peer())
				If player >= 0 Then
					relayPlayers[player].active = True
					Print "Player " + (player + 1) + " joined"
					StartRelayMatch()
				End If

			Case ESessionEventKind.Message
				Local player:Int = RelayPlayerForPeer(event.Peer())
				If player < 0 Or Not relayPlayers[player].active Then Continue
				Select event.MessageType()
					Case ROLLBACK_MSG_INPUT
						If event.Channel() = ROLLBACK_GAMEPLAY_CHANNEL And event.Delivery() = EDeliveryMode.UnreliableSequenced And event.Payload().Length() >= 12 Then ForwardRelayInput(player, event)

					Case ROLLBACK_MSG_HASH
						If event.Channel() = ROLLBACK_CONTROL_CHANNEL And event.Delivery() = EDeliveryMode.ReliableOrdered And event.Payload().Length() = 8 Then ForwardRelayMessage(player, event)

					Case ROLLBACK_MSG_PING
						Local token:UInt
						If DecodePing(event.Payload(), token) Then
							relaySession.Send(event.Peer(), ROLLBACK_MSG_PONG, ROLLBACK_CONTROL_CHANNEL, EDeliveryMode.UnreliableSequenced, event.Payload().Data(), event.Payload().Length())
						End If
				End Select

			Case ESessionEventKind.Left
				Local player:Int = RelayPlayerForPeer(event.Peer())
				If player >= 0 Then
					Local other:Int = OtherRelayPlayer(player)
					If relayPlayers[other].active Then
						Local length:Size_T = EncodePlayerAssignment(Byte Ptr(relayBuffer), Size_T(relayBuffer.Length), player)
						relaySession.Send(relayPlayers[other].peer, ROLLBACK_MSG_STOP, ROLLBACK_CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(relayBuffer), length)
					End If
					relayPlayers[player] = New SRelayPlayer
					Print "Player " + (player + 1) + " left"
				End If

			Case ESessionEventKind.Error
				Print "Session error: " + event.Code()
		End Select
	Wend
	FlushDelayedInputs()
	Delay 1
Wend

relaySession.Close()
