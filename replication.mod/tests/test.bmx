SuperStrict

Framework BRL.StandardIO
Import GameNet.Replication
Import GameNet.Loopback

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Type TTestTarget
End Type

Const APP_ID:UInt = $52504c43 ' RPLC
Const APP_VERSION:UInt = 1
Const REPLICATION_MESSAGE:UInt = 70
Const PLAYER_TYPE:UInt = 1
Const FIELD_SCORE:UInt = 1
Const FIELD_X:UInt = 2
Const FIELD_ALIVE:UInt = 3
Const FIELD_NAME:UInt = 4

Function CreatePlayerSchema:TReplicationSchema()
	Local schema:TReplicationSchema = TReplicationSchema.Create(PLAYER_TYPE, 3, 8)
	Check(schema <> Null, "create player schema")
	Check(schema.AddInt32(FIELD_SCORE), "add score")
	Check(schema.AddFloat32(FIELD_X), "add position")
	Check(schema.AddBool(FIELD_ALIVE), "add alive")
	Check(schema.AddString(FIELD_NAME, 32), "add name")
	Check(Not schema.AddUInt32(FIELD_SCORE), "reject duplicate field")
	Return schema
End Function

Function RouteReplication(session:TNetSession, world:TReplicationWorld, nowMillis:UInt)
	Local event:SSessionEvent
	While session.PollAt(event, nowMillis)
		If event.Kind() = ESessionEventKind.Message Then Check(world.Receive(event.Peer(), event.MessageType(), event.Payload()), "route replication packet")
	Wend
End Function

Local pair:TLoopbackPair = TLoopbackPair.Create(64, 1200)
Local hostSession:TNetSession = TNetSession.CreateHost(pair.First(), APP_ID, APP_VERSION, 1, 1200)
Local clientSession:TNetSession = TNetSession.CreateClient(pair.Second(), APP_ID, APP_VERSION, Null, 0, 1, 1200)
Check(hostSession <> Null And clientSession <> Null, "create sessions")

Local sessionEvent:SSessionEvent
clientSession.PollAt(sessionEvent, 0)
Check(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.JoinRequested, "host join request")
Local hostPeer:SNetPeer = sessionEvent.Peer()
Check(hostSession.Accept(hostPeer) = ETransportResult.Ok, "accept client")
Check(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "host joined")
Check(clientSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "client joined")
Local clientPeer:SNetPeer = sessionEvent.Peer()

Local config:SReplicationConfig = New SReplicationConfig(8, 4, 2, 8, 32, 1200, REPLICATION_MESSAGE, 1)
Local authority:TReplicationWorld = TReplicationWorld.CreateAuthority(hostSession, config)
Local replica:TReplicationWorld = TReplicationWorld.CreateReplica(clientSession, config)
Check(authority <> Null And replica <> Null, "create replication worlds")
Check(authority.RegisterSchema(CreatePlayerSchema()), "register authority schema")
Check(replica.RegisterSchema(CreatePlayerSchema()), "register replica schema")
Check(authority.AddPeer(hostPeer) = ETransportResult.Ok, "add authority peer")
Check(replica.BindAuthority(clientPeer), "bind replica authority")

Local target:Object = New TTestTarget
Local player:TReplicatedEntity = authority.Spawn(PLAYER_TYPE, target, 7)
Check(player <> Null And player.Target() = target, "spawn and bind target")
Check(player.SetInt32(FIELD_SCORE, -12), "set signed field")
Check(player.SetFloat32(FIELD_X, 42.5), "set float field")
Check(player.SetBool(FIELD_ALIVE, True), "set bool field")
Check(player.SetString(FIELD_NAME, "Blåbær"), "set bounded UTF-8 string")
Check(Not player.SetString(FIELD_NAME, "This name is much too long for its schema"), "reject oversized string")
Check(authority.Flush(10) = ETransportResult.Ok, "flush spawn")
RouteReplication(clientSession, replica, 10)

Local event:SReplicationEvent
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Spawned, "replica spawn event")
Local remote:TReplicatedEntity = event.Entity()
Check(remote <> Null And remote.OwnerId() = 7, "replicate owner")
Check(remote.GetInt32(FIELD_SCORE) = -12, "replicate signed field")
Check(remote.GetFloat32(FIELD_X) = 42.5, "replicate float field")
Check(remote.GetBool(FIELD_ALIVE), "replicate bool field")
Check(remote.GetString(FIELD_NAME) = "Blåbær", "replicate UTF-8 string")
Check(Not remote.SetFloat32(FIELD_X, 99.0), "replica entity is read-only")
Check(replica.EntityAt(Int(remote.Identity().Id()) - 1) = remote, "enumerate fixed entity slots")

Check(authority.RemovePeer(hostPeer), "remove authority peer")
Check(authority.AddPeer(hostPeer, 10) = ETransportResult.Ok, "send complete late-join state")
RouteReplication(clientSession, replica, 10)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Updated, "duplicate full state updates existing entity")
Check(event.Entity() = remote And remote.GetString(FIELD_NAME) = "Blåbær", "late-join state remains complete")

Check(player.SetFloat32(FIELD_X, 81.25), "change one field")
Check(authority.Flush(11) = ETransportResult.Ok, "flush changed fields")
RouteReplication(clientSession, replica, 11)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Updated, "replica update event")
Check(event.Entity() = remote And remote.GetFloat32(FIELD_X) = 81.25, "apply changed field")
Check(remote.GetString(FIELD_NAME) = "Blåbær", "retain unchanged field")

Check(authority.SetOwner(player, 9, 12) = ETransportResult.Ok, "change ownership")
RouteReplication(clientSession, replica, 12)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.OwnershipChanged, "ownership event")
Check(remote.OwnerId() = 9, "replicate ownership")

Local firstIdentity:SReplicationEntityId = player.Identity()
Check(authority.Despawn(player, 44, 13) = ETransportResult.Ok, "despawn entity")
RouteReplication(clientSession, replica, 13)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Despawned, "despawn event")
Check(event.Reason() = 44 And Not remote.IsActive(), "despawn reason and state")

Local replacement:TReplicatedEntity = authority.Spawn(PLAYER_TYPE)
Check(replacement.Identity().Id() = firstIdentity.Id(), "reuse entity slot")
Check(replacement.Identity().Generation() <> firstIdentity.Generation(), "advance entity generation")

Local malformed:Byte[2]
malformed[0] = 255
Check(Not replica.Receive(clientPeer, REPLICATION_MESSAGE, New SPacketView(Byte Ptr(malformed), Size_T(malformed.Length))), "reject malformed packet")
Check(replica.RejectedPackets() = 1 And replica.LastFailure() = EReplicationFailure.InvalidPacket, "report malformed packet")

Check(ReplicationTickAfter(1, $ffffffff:UInt), "tick comparison wraps")
Check(Not ReplicationTickAfter(9, 9), "equal tick is not newer")
Check(authority.DroppedEvents() = 0 And replica.DroppedEvents() = 0, "event queues remain bounded")

authority.Close()
replica.Close()
hostSession.Close()
clientSession.Close()
Print "GameNet.Replication tests passed"
