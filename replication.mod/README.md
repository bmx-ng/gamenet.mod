# GameNet.Replication

`GameNet.Replication` provides a GNet-style, schema-based replicated entity
API above `GameNet.Session`. It is intended for developers who want reliable
entity creation and shared state without designing their own packet protocol.

An authority registers entity schemas, creates entities, changes typed fields,
and calls `Flush`. A replica registers the same schemas, routes replication
messages from its session to `Receive`, and drains spawn, update, ownership,
and despawn events through `Poll`.

```blitzmax
Const PLAYER_TYPE:UInt = 1
Const FIELD_X:UInt = 1
Const FIELD_Y:UInt = 2
Const FIELD_NAME:UInt = 3

Local playerSchema:TReplicationSchema = TReplicationSchema.Create(PLAYER_TYPE)
playerSchema.AddFloat32(FIELD_X)
playerSchema.AddFloat32(FIELD_Y)
playerSchema.AddString(FIELD_NAME, 32)
world.RegisterSchema(playerSchema)

Local player:TReplicatedEntity = world.Spawn(PLAYER_TYPE)
player.SetFloat32(FIELD_X, 100.0)
player.SetFloat32(FIELD_Y, 80.0)
player.SetString(FIELD_NAME, "Player one")
world.Flush(tick)
```

The default policy uses reliable ordered changed-field updates. This matches
BRL.GNet's safe and approachable semantics while adding explicit entity types,
schema versions, stable identities with generations, bounded strings,
ownership, late-join state, and malformed-packet rejection.

Movement-heavy entity types can instead use complete unreliable snapshots.
A changed entity is sent immediately and its complete state is
periodically refreshed, so a later packet repairs a lost update without a
reliable backlog:

```blitzmax
Local transformSchema:TReplicationSchema = TReplicationSchema.Create(2)
transformSchema.AddFloat32(FIELD_X)
transformSchema.AddFloat32(FIELD_Y)
transformSchema.SetUpdateMode(EReplicationUpdateMode.UnreliableSnapshots, 30)
world.RegisterSchema(transformSchema)
```

Snapshots use unsequenced unreliable delivery because many entities share a
session channel. Per-entity ticks discard stale packets without allowing a
newer packet for one entity to suppress an unrelated entity's packet.

Applications continue to own `TNetSession` polling. Call `AddPeer` on an
authority after accepting a session peer; it immediately sends that peer the
complete current entity set. On a replica, call `BindAuthority` after joining.

Schemas become immutable when registered. Spawns carry a deterministic
fingerprint of the ordered schema definition and update policy. A receiver
rejects a schema with the same type and version but different fields or policy,
rather than interpreting its payload incorrectly. Increment the application
schema version when deliberately changing a network-visible definition.

Capacity can be budgeted before creating a world:

```blitzmax
Local requirements:SNetMemoryRequirements
If Not TReplicationWorld.MemoryRequirements(config, requirements) Then
	Throw "Invalid replication capacity"
End If

Print requirements.NativeBytes()
Print requirements.ManagedArrayBytes()
```

The estimate covers bounded payload storage. Runtime object and array headers,
associated target objects, and variable string contents are deliberately not
included.

## Per-peer relevance

Entities are visible to every registered peer by default, preserving the
simple GNet-style model. An authority can hide entities which are irrelevant
to one player—for example, distant map regions, private inventory, or objects
inside another match instance:

```blitzmax
world.SetPeerVisible(entity, peer, False, tick)
```

Hiding queues a reliable despawn for that peer but does not destroy the
authority entity. It can continue changing while hidden without sending field
updates. Revealing it later sends a reliable complete spawn with its current
state and the same stable identity:

```blitzmax
world.SetPeerVisible(entity, peer, True, tick)
```

`IsPeerVisible` queries the intended state. Failed visibility transitions are
retained and retried by `Flush`. A newly accepted peer can start with an empty
interest set, avoiding a short-lived download of the entire world. Entities
created later are also hidden from that peer until explicitly revealed:

```blitzmax
world.AddPeer(peer, tick, False)
world.SetPeerVisible(localPlayer, peer, True, tick)
```

`SetPeerDefaultVisible` changes the policy for subsequently spawned entities
without changing the visibility of entities which already exist.

The authority reserves three bytes per entity/peer pair for intended and known
visibility plus pending complete-state catch-up. This is included in
`MemoryRequirements` and does not allocate during ordinary relevance changes.

## Update batching and traffic measurement

`Flush` combines ordinary updates with the same delivery policy and tick into
bounded per-peer packets. Each entity is still decoded and reported as its own
update event. Reliable lifecycle transitions remain separate, so spawning,
hiding, revealing, ownership changes, and destruction retain their ordering
and complete-state guarantees.

Two optional configuration values control the packet shape:

```blitzmax
config.maxUpdatesPerBatch = 64
config.updateBatchCapacity = 1200
```

`updateBatchCapacity` defaults to `packetCapacity` when zero. Reducing it can
reserve headroom for an outer protocol or backend; an individual update which
cannot fit is reported as `PacketTooLarge`. Setting `maxUpdatesPerBatch` to one
uses individual update packets, which can be useful while inspecting traffic.
The effective capacity is also clamped to `TNetSession.MaxPayloadSize`, so the
session header and backend packet limit are accounted for automatically.
`SendCapacity` and `UpdateBatchCapacity` expose the effective values.

After each flush, `LastFlushPackets` and `LastFlushBytes` report successfully
queued replication traffic. They include update batches and any visibility
transitions retried by that flush, but not immediate operations performed
outside it.

Batching does not change delivery semantics. Reliable changed fields and
unreliable full snapshots are placed into separate packets, and relevance is
evaluated independently for every peer.

## Priority and byte budgets

Busy worlds can cap ordinary state traffic independently for each peer and
delivery policy. A zero budget retains the default unlimited behaviour:

```blitzmax
config.reliableUpdateBudgetPerPeer = 800
config.snapshotUpdateBudgetPerPeer = 1000
```

The same limits can be adjusted at runtime with `SetUpdateBudgets`. Packet
framing counts toward each limit. Reliable spawn, despawn, reveal, hide, and
ownership messages remain outside these update budgets so an entity's
lifecycle cannot be stranded behind ordinary movement traffic. Consequently,
the total `LastFlushBytes` may exceed one budget when a flush also carries
lifecycle traffic, multiple peers, or both delivery policies.

When every pending update does not fit, the authority sends higher-priority
entities first:

```blitzmax
localPlayer.SetPriority(UInt(EReplicationPriority.Critical))
projectile.SetPriority(UInt(EReplicationPriority.High))
scenery.SetPriority(UInt(EReplicationPriority.Low))
```

Priorities accept any value from 0 through 255; the enum provides convenient
common values. Equal-priority traversal rotates between flushes so a low slot
number does not win every time.

A deferred or transport-failed peer update is not retained as an obsolete
delta. GameNet records bounded per-peer catch-up state and later sends every
field from the entity's current state. This allows newer changes to coalesce
while guaranteeing that a peer which becomes writable again is repaired.
`LastFlushDeferredUpdates` reports budget deferrals and `LastFlushCatchups`
reports successful complete-state repairs. If a complete entity update is
larger than its configured budget, increase that budget or reduce the schema's
maximum encoded state size.

## One-shot entity messages

Replicated fields describe durable state. Short-lived actions such as firing a
weapon, interacting with an object, requesting an ability, or triggering an
effect can instead use a bounded entity message:

```blitzmax
Local writer:SPacketWriter = New SPacketWriter(buffer, bufferSize)
writer.WriteUInt32(weaponId)
writer.WriteFloat32(direction)

world.SendMessage(player, MSG_FIRE, writer.View(), tick)
```

On a replica, `SendMessage` sends to the bound authority. On an authority it
sends to every peer which currently knows the entity;
`SendMessageToPeer` selects one such peer. Reliable ordered delivery is the
default, while disposable effects may explicitly request unreliable delivery.
The receiving world reports a `Message` event containing the entity, message
identifier, originating peer, tick, and payload.

Message bytes are application-defined rather than part of an entity schema.
The authority should validate every client message according to game rules;
entity ownership metadata is reported but is not treated as authorization.
`maxMessageBytes` defaults to 256. The world reserves that many native bytes
for every event-queue slot and copies incoming data there, avoiding dependence
on a borrowed transport packet. An event payload view remains valid until its
queue slot is reused or the world is closed.

## Custom field codecs

The built-in typed fields remain the simplest option. A bounded codec can be
used when a game already has a useful state object or component representation.
The codec serializes only that field; GameNet continues to own packet framing,
entity identity, compatibility checks, delivery, and lifecycle.

```blitzmax
Type TTransformCodec Implements IReplicationFieldCodec
	Method CodecId:UInt()
		Return $54524e53 ' TRNS
	End Method

	Method CodecVersion:UInt()
		Return 1
	End Method

	Method MaximumBytes:UInt()
		Return 8
	End Method

	Method Encode:Int(value:Object, writer:SPacketWriter Var)
		Local transform:TTransform = TTransform(value)
		If Not transform Then Return False
		Return writer.WriteFloat32(transform.x) And writer.WriteFloat32(transform.y)
	End Method

	Method Decode:Int(reader:SPacketReader Var, value:Object Var)
		Local x:Float, y:Float
		If Not reader.ReadFloat32(x) Or Not reader.ReadFloat32(y) Then Return False
		value = New TTransform(x, y)
		Return True
	End Method
End Type
```

Reserve codec scratch capacity in the world configuration, then add the field:

```blitzmax
Local config:SReplicationConfig = New SReplicationConfig
config.codecCapacity = 64

schema.AddCodec(FIELD_TRANSFORM, New TTransformCodec)
entity.SetCustom(FIELD_TRANSFORM, transform)
```

`CodecId`, `CodecVersion`, and `MaximumBytes` are included in the schema
fingerprint. They must agree on every participant. `Encode` may not exceed its
declared bound, and `Decode` must consume the complete supplied payload. Call
`MarkCustomDirty` after mutating an object in place. A codec returning `False`
causes `Flush` to fail with `EReplicationFailure.CodecFailure`.

This interface is suitable for handwritten compact binary codecs and future
optional adapters such as `Text.MPack`; the core module does not require a
particular object serialization package.

The entity storage API is intentionally independent of BlitzMax game objects
and ECS implementations. `SetTarget` can associate an ordinary game object
with an entity. A future Flecs adapter will map the same stable identities and
schemas to ECS entities and components.
