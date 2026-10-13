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

Movement-heavy entity types can instead use complete unreliable-sequenced
snapshots. A changed entity is sent immediately and its complete state is
periodically refreshed, so a later packet repairs a lost update without a
reliable backlog:

```blitzmax
Local transformSchema:TReplicationSchema = TReplicationSchema.Create(2)
transformSchema.AddFloat32(FIELD_X)
transformSchema.AddFloat32(FIELD_Y)
transformSchema.SetUpdateMode(EReplicationUpdateMode.UnreliableSnapshots, 30)
world.RegisterSchema(transformSchema)
```

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

The entity storage API is intentionally independent of BlitzMax game objects
and ECS implementations. `SetTarget` can associate an ordinary game object
with an entity. A future Flecs adapter will map the same stable identities and
schemas to ECS entities and components.
