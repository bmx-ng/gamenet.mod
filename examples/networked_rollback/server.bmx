SuperStrict

Framework BRL.StandardIO
Import BRL.System
Import GameNet.Session
Import GameNet.ENet
Import GameNet.Impairment

Include "protocol.bmx"

Struct SRelayPlayer
	Field peer:SNetPeer
	Field active:Int
End Struct

Global relaySession:TNetSession
Global relayPlayers:SRelayPlayer[ROLLBACK_PLAYER_COUNT]
Global relayBuffer:Byte[64]
Global relayMatchId:UInt
Global relayDelayMillis:Int
Global relayJitterMillis:Int
Global relayLossPercent:Int
Global relaySeed:UInt = 1

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
	ForwardRelayMessage(player, event)
End Function

Local port:Int = ROLLBACK_PORT
If AppArgs.Length > 1 Then port = Int(AppArgs[1])
If AppArgs.Length > 2 Then relayDelayMillis = Max(0, Int(AppArgs[2]))
If AppArgs.Length > 3 Then relayLossPercent = Min(100, Max(0, Int(AppArgs[3])))
If AppArgs.Length > 4 Then relayJitterMillis = Max(0, Int(AppArgs[4]))
If AppArgs.Length > 5 Then relaySeed = UInt(AppArgs[5])
Local backend:TENetTransport = TENetTransport.Listen(port, ROLLBACK_PLAYER_COUNT, 2)
If Not backend Then Throw "Could not listen on UDP port " + port
Local impairmentConfig:SImpairmentConfig = New SImpairmentConfig(UInt(relayDelayMillis), UInt(relayJitterMillis), UInt(relayLossPercent * 100), 0, 0, 0, 0, IMPAIRMENT_DELIVERY_UNRELIABLE | IMPAIRMENT_DELIVERY_UNRELIABLE_SEQUENCED)
Local transport:TImpairedTransport = TImpairedTransport.Create(backend, 512, 1200, impairmentConfig, relaySeed)
If Not transport Then Throw "Could not create impaired relay transport"
relaySession = TNetSession.CreateHost(transport, ROLLBACK_APP_ID, ROLLBACK_APP_VERSION, ROLLBACK_PLAYER_COUNT, 1200)
If Not relaySession Then Throw "Could not create rollback relay session"
If Not relaySession.ConfigureHealth(New SSessionHealthConfig(10000, 15000, 500, 2000)) Then Throw "Could not configure relay connection health"

Print "Networked rollback relay listening on UDP port " + port
Print "Outbound unreliable traffic: " + relayDelayMillis + " ms latency, " + relayJitterMillis + " ms jitter, " + relayLossPercent + "% loss; seed " + relaySeed
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

					Case ROLLBACK_MSG_STATE_SYNC_REQUEST
						If player <> 0 And event.Channel() = ROLLBACK_CONTROL_CHANNEL And event.Delivery() = EDeliveryMode.ReliableOrdered And event.Payload().Length() = 13 Then ForwardRelayMessage(player, event)

					Case ROLLBACK_MSG_STATE_SYNC_RESPONSE
						If player = 0 And event.Channel() = ROLLBACK_CONTROL_CHANNEL And event.Delivery() = EDeliveryMode.ReliableOrdered And event.Payload().Length() >= 18 Then ForwardRelayMessage(player, event)

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
	Delay 1
Wend

relaySession.Close()
