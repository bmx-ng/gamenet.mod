SuperStrict

Framework BRL.StandardIO
Import GameNet.Loopback
Import GameNet.Replication

Include "protocol.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Function RouteReplication(session:TNetSession, world:TReplicationWorld, now:UInt)
	Local event:SSessionEvent
	While session.PollAt(event, now)
		If event.Kind() = ESessionEventKind.Message Then Check(world.Receive(event.Peer(), event.MessageType(), event.Payload()), "route replication packet")
	Wend
End Function

Local movementState:Byte[SALVAGE_MOVEMENT_STATE_SIZE]
Local movementLength:Size_T = EncodeSalvageMovementState(Byte Ptr(movementState), Size_T(movementState.Length), 10.0, 20.0, 30.0, 40.0)
Local movementX:Float, movementY:Float
Check(movementLength = SALVAGE_MOVEMENT_STATE_SIZE, "encode atomic movement snapshot")
Check(DecodeSalvageMovementPlayer(New SPacketView(Byte Ptr(movementState), movementLength), 0, movementX, movementY) And movementX = 10.0 And movementY = 20.0, "decode first player from movement snapshot")
Check(DecodeSalvageMovementPlayer(New SPacketView(Byte Ptr(movementState), movementLength), 1, movementX, movementY) And movementX = 30.0 And movementY = 40.0, "decode second player from movement snapshot")

Local pair:TLoopbackPair = TLoopbackPair.Create(128, 1200)
Local hostSession:TNetSession = TNetSession.CreateHost(pair.First(), SALVAGE_APP_ID, SALVAGE_APP_VERSION, 1, 1200)
Local clientSession:TNetSession = TNetSession.CreateClient(pair.Second(), SALVAGE_APP_ID, SALVAGE_APP_VERSION, Null, 0, 1, 1200)
Check(hostSession <> Null And clientSession <> Null, "create sessions")

Local sessionEvent:SSessionEvent
clientSession.PollAt(sessionEvent, 0)
Check(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.JoinRequested, "receive join request")
Local hostPeer:SNetPeer = sessionEvent.Peer()
Check(hostSession.Accept(hostPeer) = ETransportResult.Ok, "accept client")
Check(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "host joined")
Check(clientSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "client joined")
Local clientPeer:SNetPeer = sessionEvent.Peer()

Local config:SReplicationConfig = New SReplicationConfig(16, 3, 1, 3, 64, 1200, SALVAGE_REPLICATION_MESSAGE, SALVAGE_REPLICATION_CHANNEL, 0, 16, 0, 900, 900, 32)
Local authority:TReplicationWorld = TReplicationWorld.CreateAuthority(hostSession, config)
Local replica:TReplicationWorld = TReplicationWorld.CreateReplica(clientSession, config)
Check(authority <> Null And replica <> Null, "create replication worlds")
Check(RegisterSalvageSchemas(authority) And RegisterSalvageSchemas(replica), "register salvage schemas")
Check(authority.AddPeer(hostPeer) = ETransportResult.Ok, "add authority peer")
Check(replica.BindAuthority(clientPeer), "bind authority")

Local game:TSalvageAuthority = TSalvageAuthority.Create(authority)
Check(game <> Null And game.Start(), "start salvage simulation")
Check(authority.Flush(1) = ETransportResult.Ok, "flush initial world")
RouteReplication(clientSession, replica, 1)

Local remotePlayerOne:TReplicatedEntity
Local remoteMatch:TReplicatedEntity
Local spawned:Int
Local replicationEvent:SReplicationEvent
While replica.Poll(replicationEvent)
	If replicationEvent.Kind() <> EReplicationEventKind.Spawned Then Continue
	spawned :+ 1
	If replicationEvent.Entity().TypeId() = SALVAGE_PLAYER_TYPE And replicationEvent.Entity().OwnerId() = 2 Then remotePlayerOne = replicationEvent.Entity()
	If replicationEvent.Entity().TypeId() = SALVAGE_MATCH_TYPE Then remoteMatch = replicationEvent.Entity()
Wend
Check(spawned = 7 And remotePlayerOne <> Null And remoteMatch <> Null, "replicate complete initial game world")

Local inputBuffer:Byte[3]
Local inputLength:Size_T = EncodeSalvageInput(Byte Ptr(inputBuffer), Size_T(inputBuffer.Length), -127, 0, False)
Local initialX:Float = game.players[1].GetFloat32(SALVAGE_FIELD_X)
Check(replica.SendMessage(remotePlayerOne, SALVAGE_MESSAGE_INPUT, New SPacketView(Byte Ptr(inputBuffer), inputLength), 2, EDeliveryMode.Unreliable) = ETransportResult.Ok, "send client input")
RouteReplication(hostSession, authority, 2)
While authority.Poll(replicationEvent)
	If replicationEvent.Kind() = EReplicationEventKind.Message Then Check(game.ReceiveMessage(replicationEvent), "decode client input")
Wend
game.Step(2)
Check(game.players[1].GetFloat32(SALVAGE_FIELD_X) < initialX, "apply client input on authority")
Check(authority.Flush(2) = ETransportResult.Ok, "flush simulated movement")
RouteReplication(clientSession, replica, 2)
While replica.Poll(replicationEvent)
Wend
Check(remotePlayerOne.GetFloat32(SALVAGE_FIELD_X) < initialX, "replicate simulated movement")

game.SetInput(0, 0, 0, False)
game.SetInput(1, 0, 0, False)
game.players[0].SetFloat32(SALVAGE_FIELD_X, 380.0)
game.players[0].SetFloat32(SALVAGE_FIELD_Y, 225.0)
game.players[1].SetFloat32(SALVAGE_FIELD_X, 430.0)
game.players[1].SetFloat32(SALVAGE_FIELD_Y, 225.0)
game.cores[0].SetFloat32(SALVAGE_FIELD_X, 380.0)
game.cores[0].SetFloat32(SALVAGE_FIELD_Y, 225.0)
game.Step(3)
Check(game.cores[0].GetUInt32(SALVAGE_FIELD_CARRIER) = 1, "pick up salvage core")
game.SetInput(1, 0, 0, True)
game.Step(4)
Check(game.cores[0].GetUInt32(SALVAGE_FIELD_CARRIER) = 0, "pulse drops nearby opponent core")

game.players[0].SetFloat32(SALVAGE_FIELD_X, 40.0)
game.players[0].SetFloat32(SALVAGE_FIELD_Y, 225.0)
game.cores[1].SetFloat32(SALVAGE_FIELD_X, 40.0)
game.cores[1].SetFloat32(SALVAGE_FIELD_Y, 225.0)
game.Step(5)
Check(game.Score(0) = 1 And game.cores[1] = Null, "deposit core and update reliable score")
Check(authority.Flush(5) = ETransportResult.Ok, "flush score and despawn")
RouteReplication(clientSession, replica, 5)
While replica.Poll(replicationEvent)
Wend
Check(remoteMatch.GetInt32(SALVAGE_FIELD_SCORE_0) = 1, "replicate reliable score")

authority.Close()
replica.Close()
hostSession.Close()
clientSession.Close()
Print "Orbital Salvage protocol tests passed"
