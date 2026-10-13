SuperStrict

Framework BRL.StandardIO
Import GameNet.Replication
Import GameNet.Loopback

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Type TTestTarget
End Type

Type TPositionState
	Field x:Float
	Field y:Float

	Method New(x:Float, y:Float)
		Self.x = x
		Self.y = y
	End Method
End Type

Type TPositionCodec Implements IReplicationFieldCodec
	Method CodecId:UInt()
		Return $504f5332 ' POS2
	End Method

	Method CodecVersion:UInt()
		Return 1
	End Method

	Method MaximumBytes:UInt()
		Return 8
	End Method

	Method Encode:Int(value:Object, writer:SPacketWriter Var)
		Local position:TPositionState = TPositionState(value)
		If Not position Then Return False
		Return writer.WriteFloat32(position.x) And writer.WriteFloat32(position.y)
	End Method

	Method Decode:Int(reader:SPacketReader Var, value:Object Var)
		Local x:Float, y:Float
		If Not reader.ReadFloat32(x) Or Not reader.ReadFloat32(y) Then Return False
		value = New TPositionState(x, y)
		Return True
	End Method
End Type

Const APP_ID:UInt = $52504c43 ' RPLC
Const APP_VERSION:UInt = 1
Const REPLICATION_MESSAGE:UInt = 70
Const PLAYER_TYPE:UInt = 1
Const FIELD_SCORE:UInt = 1
Const FIELD_X:UInt = 2
Const FIELD_ALIVE:UInt = 3
Const FIELD_NAME:UInt = 4
Const SNAPSHOT_TYPE:UInt = 2
Const FIELD_SNAPSHOT_X:UInt = 1
Const MISMATCH_TYPE:UInt = 3
Const FIELD_MISMATCH_VALUE:UInt = 1
Const CODEC_TYPE:UInt = 4
Const FIELD_POSITION:UInt = 1

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

Function CreateSnapshotSchema:TReplicationSchema()
	Local schema:TReplicationSchema = TReplicationSchema.Create(SNAPSHOT_TYPE, 1, 2)
	Check(schema <> Null, "create snapshot schema")
	Check(schema.AddFloat32(FIELD_SNAPSHOT_X), "add snapshot position")
	Check(schema.SetUpdateMode(EReplicationUpdateMode.UnreliableSnapshots, 3), "select periodic snapshots")
	Return schema
End Function

Function CreateMismatchSchema:TReplicationSchema(useUnsigned:Int)
	Local schema:TReplicationSchema = TReplicationSchema.Create(MISMATCH_TYPE, 1, 1)
	Check(schema <> Null, "create mismatch schema")
	If useUnsigned Then
		Check(schema.AddUInt32(FIELD_MISMATCH_VALUE), "add unsigned mismatch field")
	Else
		Check(schema.AddInt32(FIELD_MISMATCH_VALUE), "add signed mismatch field")
	End If
	Return schema
End Function

Function CreateCodecSchema:TReplicationSchema()
	Local schema:TReplicationSchema = TReplicationSchema.Create(CODEC_TYPE, 1, 1)
	Check(schema <> Null, "create codec schema")
	Check(schema.AddCodec(FIELD_POSITION, New TPositionCodec), "add custom codec field")
	Return schema
End Function

Function RouteReplication(session:TNetSession, world:TReplicationWorld, nowMillis:UInt)
	Local event:SSessionEvent
	While session.PollAt(event, nowMillis)
		If event.Kind() = ESessionEventKind.Message Then Check(world.Receive(event.Peer(), event.MessageType(), event.Payload()), "route replication packet")
	Wend
End Function

Function DiscardSessionMessages(session:TNetSession, nowMillis:UInt)
	Local event:SSessionEvent
	While session.PollAt(event, nowMillis)
	Wend
End Function

Function PollEntityEvent:Int(world:TReplicationWorld, entity:TReplicatedEntity, kind:EReplicationEventKind, event:SReplicationEvent Var)
	Local found:Int
	While world.Poll(event)
		If event.Entity() = entity And event.Kind() = kind Then found = True
	Wend
	Return found
End Function

Function PollMessageEvent:Int(world:TReplicationWorld, messageId:UInt, event:SReplicationEvent Var)
	While world.Poll(event)
		If event.Kind() = EReplicationEventKind.Message And event.MessageId() = messageId Then Return True
	Wend
	Return False
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

Local config:SReplicationConfig = New SReplicationConfig(8, 4, 2, 8, 32, 1200, REPLICATION_MESSAGE, 1, 64, 2)
Local requirements:SNetMemoryRequirements
Check(TReplicationWorld.MemoryRequirements(config, requirements), "calculate replication memory requirements")
Check(requirements.NativeBytes() = 10656 And requirements.ManagedArrayBytes() > 0, "report native and managed storage")
Local invalidConfig:SReplicationConfig = New SReplicationConfig(0, 4, 2, 8, 32, 1200, REPLICATION_MESSAGE, 1)
Check(Not TReplicationWorld.MemoryRequirements(invalidConfig, requirements), "reject invalid memory configuration")
Local invalidBatchConfig:SReplicationConfig = New SReplicationConfig(8, 4, 2, 8, 32, 1200, REPLICATION_MESSAGE, 1, 0, 0)
Check(Not TReplicationWorld.MemoryRequirements(invalidBatchConfig, requirements), "reject invalid update batch configuration")
Local invalidMessageConfig:SReplicationConfig = config
invalidMessageConfig.maxMessageBytes = 1200
Check(Not TReplicationWorld.MemoryRequirements(invalidMessageConfig, requirements), "reject message payload larger than packet capacity")

Local authority:TReplicationWorld = TReplicationWorld.CreateAuthority(hostSession, config)
Local replica:TReplicationWorld = TReplicationWorld.CreateReplica(clientSession, config)
Check(authority <> Null And replica <> Null, "create replication worlds")
Check(authority.SendCapacity() = 1192 And authority.UpdateBatchCapacity() = 1192, "clamp replication payload to session capacity")
Local noCodecConfig:SReplicationConfig = New SReplicationConfig(1, 1, 1, 1, 4, 1200, REPLICATION_MESSAGE, 1)
Local noCodecWorld:TReplicationWorld = TReplicationWorld.CreateAuthority(hostSession, noCodecConfig)
Check(noCodecWorld <> Null And Not noCodecWorld.RegisterSchema(CreateCodecSchema()), "require configured codec scratch capacity")
noCodecWorld.Close()
Local authorityPlayerSchema:TReplicationSchema = CreatePlayerSchema()
Local replicaPlayerSchema:TReplicationSchema = CreatePlayerSchema()
Check(authorityPlayerSchema.Fingerprint() = replicaPlayerSchema.Fingerprint(), "matching schemas have matching fingerprints")
Local changedPlayerSchema:TReplicationSchema = TReplicationSchema.Create(PLAYER_TYPE, 3, 8)
changedPlayerSchema.AddFloat32(FIELD_X)
Check(changedPlayerSchema.Fingerprint() <> authorityPlayerSchema.Fingerprint(), "schema changes alter the fingerprint")
Check(authority.RegisterSchema(authorityPlayerSchema), "register authority schema")
Check(replica.RegisterSchema(replicaPlayerSchema), "register replica schema")
Check(Not authorityPlayerSchema.SetUpdateMode(EReplicationUpdateMode.UnreliableSnapshots, 3), "registered schema is immutable")
Check(authority.RegisterSchema(CreateSnapshotSchema()), "register authority snapshot schema")
Check(replica.RegisterSchema(CreateSnapshotSchema()), "register replica snapshot schema")
Check(authority.RegisterSchema(CreateMismatchSchema(False)), "register authority mismatch schema")
Check(replica.RegisterSchema(CreateMismatchSchema(True)), "register replica mismatch schema")
Check(authority.RegisterSchema(CreateCodecSchema()), "register authority codec schema")
Check(replica.RegisterSchema(CreateCodecSchema()), "register replica codec schema")
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
Check(Not remote.SetPriority(UInt(EReplicationPriority.High)), "replica cannot change scheduling priority")
Check(replica.EntityAt(Int(remote.Identity().Id()) - 1) = remote, "enumerate fixed entity slots")

Local messageBytes:Byte[3]
messageBytes[0] = 17
messageBytes[1] = 34
messageBytes[2] = 51
Local messagePayload:SPacketView = New SPacketView(Byte Ptr(messageBytes), Size_T(messageBytes.Length))
Check(authority.SendMessage(player, 900, messagePayload, 10) = ETransportResult.Ok, "send authority entity message")
RouteReplication(clientSession, replica, 10)
Check(PollMessageEvent(replica, 900, event), "receive authority entity message")
Check(event.Entity() = remote And event.Peer().Equals(clientPeer), "report authority message target and peer")
Check(event.Payload().Length() = 3 And event.Payload().Data()[0] = 17 And event.Payload().Data()[2] = 51, "copy authority message payload")
Check(replica.SendMessage(remote, 901, messagePayload, 10) = ETransportResult.Ok, "send replica entity message")
RouteReplication(hostSession, authority, 10)
Check(PollMessageEvent(authority, 901, event), "receive replica entity message")
Check(event.Entity() = player And event.Peer().Equals(hostPeer), "report replica message target and peer")
Check(event.Payload().Length() = 3 And event.Payload().Data()[1] = 34, "copy replica message payload")
Local oversizedMessage:Byte[257]
Check(authority.SendMessage(player, 902, New SPacketView(Byte Ptr(oversizedMessage), Size_T(oversizedMessage.Length)), 10) = ETransportResult.PacketTooLarge, "reject oversized entity message")

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
Check(authority.Despawn(replacement, 0, 14) = ETransportResult.Ok, "remove replacement entity")
RouteReplication(clientSession, replica, 14)

Local snapshotEntity:TReplicatedEntity = authority.Spawn(SNAPSHOT_TYPE)
Check(snapshotEntity <> Null And snapshotEntity.SetFloat32(FIELD_SNAPSHOT_X, 10.0), "create snapshot entity")
Check(authority.Flush(20) = ETransportResult.Ok, "flush reliable snapshot spawn")
RouteReplication(clientSession, replica, 20)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Spawned, "snapshot entity spawn event")
Local remoteSnapshot:TReplicatedEntity = event.Entity()
Check(remoteSnapshot.GetFloat32(FIELD_SNAPSHOT_X) = 10.0, "replicate initial snapshot value")

Check(snapshotEntity.SetFloat32(FIELD_SNAPSHOT_X, 77.0), "change snapshot field")
Check(authority.Flush(21) = ETransportResult.Ok, "flush unreliable snapshot")
DiscardSessionMessages(clientSession, 21)
Check(remoteSnapshot.GetFloat32(FIELD_SNAPSHOT_X) = 10.0, "discarded snapshot leaves old value")
Check(authority.Flush(22) = ETransportResult.Ok, "skip early periodic refresh")
RouteReplication(clientSession, replica, 22)
Check(Not replica.Poll(event), "no refresh before configured interval")
Check(authority.Flush(23) = ETransportResult.Ok, "continue before periodic refresh")
RouteReplication(clientSession, replica, 23)
Check(Not replica.Poll(event), "still no early refresh")
Check(authority.Flush(24) = ETransportResult.Ok, "send periodic full snapshot")
RouteReplication(clientSession, replica, 24)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Updated, "periodic snapshot repairs loss")
Check(event.Entity() = remoteSnapshot And remoteSnapshot.GetFloat32(FIELD_SNAPSHOT_X) = 77.0, "repaired snapshot contains complete state")

Local mismatchEntity:TReplicatedEntity = authority.Spawn(MISMATCH_TYPE)
Check(mismatchEntity <> Null And mismatchEntity.SetInt32(FIELD_MISMATCH_VALUE, -1), "create mismatched entity")
Check(authority.Flush(25) = ETransportResult.Ok, "flush mismatched spawn")
Check(clientSession.PollAt(sessionEvent, 25) And sessionEvent.Kind() = ESessionEventKind.Message, "receive mismatched spawn")
Check(Not replica.Receive(sessionEvent.Peer(), sessionEvent.MessageType(), sessionEvent.Payload()), "reject mismatched schema on the wire")
Check(replica.LastFailure() = EReplicationFailure.SchemaFingerprintMismatch, "report schema fingerprint mismatch")
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Error, "queue schema mismatch error")

Check(authority.SetPeerDefaultVisible(hostPeer, False), "hide future entities by default")
Check(Not authority.PeerDefaultVisible(hostPeer), "report hidden default")
Local codecEntity:TReplicatedEntity = authority.Spawn(CODEC_TYPE)
Local position:TPositionState = New TPositionState(12.5, -8.25)
Check(codecEntity <> Null And codecEntity.SetCustom(FIELD_POSITION, position), "assign custom codec value")
Check(Not authority.IsPeerVisible(codecEntity, hostPeer), "new entity follows peer visibility default")
Check(authority.Flush(26) = ETransportResult.Ok, "flush hidden custom codec spawn")
RouteReplication(clientSession, replica, 26)
Check(Not replica.Poll(event), "hidden new entity sends no spawn")
Check(authority.SetPeerDefaultVisible(hostPeer, True), "restore visible default")
Check(authority.PeerDefaultVisible(hostPeer), "report visible default")
Check(authority.SetPeerVisible(codecEntity, hostPeer, True, 26) = ETransportResult.Ok, "reveal initially hidden entity")
RouteReplication(clientSession, replica, 26)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Spawned, "custom codec spawn event")
Local remoteCodecEntity:TReplicatedEntity = event.Entity()
Local remotePosition:TPositionState = TPositionState(remoteCodecEntity.GetCustom(FIELD_POSITION))
Check(remotePosition <> Null And remotePosition.x = 12.5 And remotePosition.y = -8.25, "decode custom codec value")
position.x = 91.0
position.y = 42.0
Check(codecEntity.MarkCustomDirty(FIELD_POSITION), "mark mutable custom value dirty")
Check(authority.Flush(27) = ETransportResult.Ok, "flush custom codec update")
RouteReplication(clientSession, replica, 27)
Check(PollEntityEvent(replica, remoteCodecEntity, EReplicationEventKind.Updated, event), "custom codec update event")
remotePosition = TPositionState(remoteCodecEntity.GetCustom(FIELD_POSITION))
Check(remotePosition.x = 91.0 And remotePosition.y = 42.0, "update custom codec value")
Check(authority.IsPeerVisible(codecEntity, hostPeer), "entity is visible by default")
Check(authority.SetPeerVisible(codecEntity, hostPeer, False, 28, 55) = ETransportResult.Ok, "hide entity from peer")
Check(Not authority.IsPeerVisible(codecEntity, hostPeer), "report hidden entity")
RouteReplication(clientSession, replica, 28)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Despawned, "hidden entity despawn event")
Check(event.Entity() = remoteCodecEntity And event.Reason() = 55, "preserve hide reason")
position.x = -14.0
position.y = 6.5
Check(codecEntity.MarkCustomDirty(FIELD_POSITION), "update hidden entity")
Check(authority.Flush(29) = ETransportResult.Ok, "flush while entity is hidden")
RouteReplication(clientSession, replica, 29)
Check(Not replica.Poll(event), "hidden entity sends no ordinary update")
Check(authority.SetPeerVisible(codecEntity, hostPeer, True, 30) = ETransportResult.Ok, "reveal entity to peer")
Check(authority.IsPeerVisible(codecEntity, hostPeer), "report revealed entity")
RouteReplication(clientSession, replica, 30)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Spawned, "revealed entity spawn event")
remoteCodecEntity = event.Entity()
remotePosition = TPositionState(remoteCodecEntity.GetCustom(FIELD_POSITION))
Check(remotePosition.x = -14.0 And remotePosition.y = 6.5, "reveal complete current state")
Check(remoteCodecEntity.Identity().Equals(codecEntity.Identity()), "reveal preserves stable identity")

Check(authority.SetPeerVisible(snapshotEntity, hostPeer, False, 31) = ETransportResult.Ok, "hide snapshot entity before batch test")
RouteReplication(clientSession, replica, 31)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Despawned, "hide snapshot entity for batch test")
Local batchA:TReplicatedEntity = authority.Spawn(PLAYER_TYPE)
Local batchB:TReplicatedEntity = authority.Spawn(PLAYER_TYPE)
Check(batchA.SetInt32(FIELD_SCORE, 1) And batchB.SetInt32(FIELD_SCORE, 2), "create batch entities")
Check(batchA.SetPriority(UInt(EReplicationPriority.Low)), "set low update priority")
Check(batchB.SetPriority(UInt(EReplicationPriority.High)), "set high update priority")
Check(batchA.Priority() = UInt(EReplicationPriority.Low) And batchB.Priority() = UInt(EReplicationPriority.High), "report update priorities")
Check(Not batchA.SetPriority(256), "reject invalid update priority")
Check(authority.Flush(31) = ETransportResult.Ok, "flush batch entity spawns")
RouteReplication(clientSession, replica, 31)
Local remoteBatchA:TReplicatedEntity
Local remoteBatchB:TReplicatedEntity
While replica.Poll(event)
	If event.Kind() <> EReplicationEventKind.Spawned Then Continue
	If event.Entity().GetInt32(FIELD_SCORE) = 1 Then remoteBatchA = event.Entity()
	If event.Entity().GetInt32(FIELD_SCORE) = 2 Then remoteBatchB = event.Entity()
Wend
Check(remoteBatchA <> Null And remoteBatchB <> Null, "receive batch entity spawns")
Check(batchA.SetInt32(FIELD_SCORE, 11) And batchB.SetInt32(FIELD_SCORE, 22), "change two reliable entities")
authority.SetUpdateBudgets(44, 0)
Check(authority.ReliableUpdateBudgetPerPeer() = 44 And authority.SnapshotUpdateBudgetPerPeer() = 0, "configure independent update budgets")
Check(authority.Flush(32) = ETransportResult.Ok, "flush priority-limited reliable updates")
Check(authority.LastFlushPackets() = 1 And authority.LastFlushBytes() <= 44, "respect per-peer reliable byte budget")
Check(authority.LastFlushDeferredUpdates() = 1 And authority.LastFlushCatchups() = 0, "report one deferred update")
RouteReplication(clientSession, replica, 32)
Local batchUpdateCount:Int
While replica.Poll(event)
	If event.Kind() = EReplicationEventKind.Updated Then batchUpdateCount :+ 1
Wend
Check(batchUpdateCount = 1, "send only one update within the budget")
Check(remoteBatchA.GetInt32(FIELD_SCORE) = 1 And remoteBatchB.GetInt32(FIELD_SCORE) = 22, "send higher-priority update first")
Check(authority.Flush(33) = ETransportResult.Ok, "flush deferred complete-state catch-up")
Check(authority.LastFlushPackets() = 1 And authority.LastFlushBytes() <= 44, "keep catch-up within byte budget")
Check(authority.LastFlushDeferredUpdates() = 0 And authority.LastFlushCatchups() = 1, "report completed catch-up")
RouteReplication(clientSession, replica, 33)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Updated, "receive deferred catch-up")
Check(event.Entity() = remoteBatchA And remoteBatchA.GetInt32(FIELD_SCORE) = 11, "catch-up carries complete current state")
authority.SetUpdateBudgets(0, 0)

Local budgetSnapshot:TReplicatedEntity = authority.Spawn(SNAPSHOT_TYPE)
Check(budgetSnapshot <> Null And budgetSnapshot.SetFloat32(FIELD_SNAPSHOT_X, 5.0), "create budgeted snapshot entity")
authority.SetUpdateBudgets(0, 1)
Check(authority.Flush(34) = ETransportResult.Ok, "send lifecycle state outside snapshot budget")
RouteReplication(clientSession, replica, 34)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Spawned, "receive budgeted snapshot spawn")
Local remoteBudgetSnapshot:TReplicatedEntity = event.Entity()
Check(remoteBudgetSnapshot.GetFloat32(FIELD_SNAPSHOT_X) = 5.0, "spawn carries complete snapshot state")
Check(budgetSnapshot.SetFloat32(FIELD_SNAPSHOT_X, 9.0), "change budgeted snapshot")
Check(authority.Flush(35) = ETransportResult.Ok, "defer snapshot update below packet size")
Check(authority.LastFlushPackets() = 0 And authority.LastFlushDeferredUpdates() = 1, "apply snapshot budget independently")
RouteReplication(clientSession, replica, 35)
Check(Not replica.Poll(event) And remoteBudgetSnapshot.GetFloat32(FIELD_SNAPSHOT_X) = 5.0, "leave deferred snapshot unchanged")
authority.SetUpdateBudgets(0, 27)
Check(authority.Flush(36) = ETransportResult.Ok, "repair deferred snapshot state")
Check(authority.LastFlushCatchups() = 1, "report snapshot catch-up")
RouteReplication(clientSession, replica, 36)
Check(replica.Poll(event) And event.Kind() = EReplicationEventKind.Updated, "receive snapshot catch-up")
Check(event.Entity() = remoteBudgetSnapshot And remoteBudgetSnapshot.GetFloat32(FIELD_SNAPSHOT_X) = 9.0, "apply complete snapshot catch-up")
authority.SetUpdateBudgets(0, 0)

Check(codecEntity.SetCustom(FIELD_POSITION, Null), "allow codec to validate a custom value")
Check(authority.Flush(37) = ETransportResult.Failed, "surface custom codec encoding failure")
Check(authority.LastFailure() = EReplicationFailure.CodecFailure, "report custom codec failure")

Local malformed:Byte[2]
malformed[0] = 255
Local rejectedBefore:Int = replica.RejectedPackets()
Check(Not replica.Receive(clientPeer, REPLICATION_MESSAGE, New SPacketView(Byte Ptr(malformed), Size_T(malformed.Length))), "reject malformed packet")
Check(replica.RejectedPackets() = rejectedBefore + 1 And replica.LastFailure() = EReplicationFailure.InvalidPacket, "report malformed packet")

Check(ReplicationTickAfter(1, $ffffffff:UInt), "tick comparison wraps")
Check(Not ReplicationTickAfter(9, 9), "equal tick is not newer")
Check(authority.DroppedEvents() = 0 And replica.DroppedEvents() = 0, "event queues remain bounded")

authority.Close()
replica.Close()
hostSession.Close()
clientSession.Close()
Print "GameNet.Replication tests passed"
