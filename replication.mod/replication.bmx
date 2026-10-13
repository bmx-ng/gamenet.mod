' Copyright (c) 2026 Bruce A Henderson and contributors
'
' This software is provided 'as-is', without any express or implied
' warranty. In no event will the authors be held liable for any damages
' arising from the use of this software.
'
' Permission is granted to anyone to use this software for any purpose,
' including commercial applications, and to alter it and redistribute it
' freely, subject to the following restrictions:
'
' 1. The origin of this software must not be misrepresented; you must not
'    claim that you wrote the original software. If you use this software
'    in a product, an acknowledgment in the product documentation would be
'    appreciated but is not required.
' 2. Altered source versions must be plainly marked as such, and must not be
'    misrepresented as being the original software.
' 3. This notice may not be removed or altered from any source distribution.

SuperStrict

Rem
bbdoc: Schema-based replicated entities above GameNet sessions.
End Rem
Module GameNet.Replication

?bmxng2

ModuleInfo "Version: 0.2"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.2 Add schema fingerprints, memory sizing, and periodic unreliable snapshots"
ModuleInfo "History: 0.1 Initial schema, entity lifecycle, and reliable field replication"

Import GameNet.Core
Import GameNet.Session

Private

Const REPLICATION_PROTOCOL_VERSION:UInt = 2
Const REPLICATION_MINIMUM_PACKET_SIZE:Size_T = 32

Function ReplicationHashByte:ULong(hash:ULong, value:UInt)
	Return (hash ~ ULong(value & $ff:UInt)) * $100000001b3:ULong
End Function

Function ReplicationHashUInt32:ULong(hash:ULong, value:UInt)
	For Local shift:Int = 24 To 0 Step -8
		hash = ReplicationHashByte(hash, value Shr UInt(shift))
	Next
	Return hash
End Function

Enum EReplicationPacketKind:Byte
	Spawn = 1
	Update
	Despawn
	Ownership
End Enum

Public

Struct SReplicationValue
	Field intValue:Int
	Field uintValue:UInt
	Field floatValue:Float
	Field boolValue:Int
	Field stringValue:String
	Field stringBytes:Byte[]
End Struct

Private

Struct SDecodedReplicationField
	Field fieldIndex:Int
	Field fieldType:EReplicationFieldType
	Field intValue:Int
	Field uintValue:UInt
	Field floatValue:Float
	Field boolValue:Int
	Field bytes:SPacketView
End Struct

Public

Rem
bbdoc: The value type stored by one replicated schema field.
End Rem
Enum EReplicationFieldType:Byte
	Int32 = 1
	UInt32
	Float32
	Boolean
	Utf8String
End Enum

Rem
bbdoc: Selects how ordinary entity state changes are delivered.
End Rem
Enum EReplicationUpdateMode:Byte
	ReliableChanges
	UnreliableSnapshots
End Enum

Rem
bbdoc: Whether a replication world originates or receives authoritative state.
End Rem
Enum EReplicationRole:Byte
	Authority
	Replica
End Enum

Rem
bbdoc: A developer-facing replicated entity transition.
End Rem
Enum EReplicationEventKind:Byte
	None
	Spawned
	Updated
	Despawned
	OwnershipChanged
	Error
End Enum

Rem
bbdoc: A durable replication failure or rejected packet reason.
End Rem
Enum EReplicationFailure:Int
	None
	InvalidPacket
	UnknownSchema
	SchemaVersionMismatch
	SchemaFingerprintMismatch
	EntityCapacity
	PacketTooLarge
	WrongAuthority
	EventQueueOverflow
End Enum

Rem
bbdoc: A stable network entity identity.
about: The generation prevents a delayed packet for a destroyed entity from
identifying a new entity which reuses the same numeric slot.
End Rem
Struct SReplicationEntityId
	Private
	Field _id:UInt
	Field _generation:UInt

	Public
	Method New()
	End Method

	Method New(id:UInt, generation:UInt)
		_id = id
		_generation = generation
	End Method

	Method Id:UInt()
		Return _id
	End Method

	Method Generation:UInt()
		Return _generation
	End Method

	Method IsValid:Int()
		Return _id <> 0 And _generation <> 0
	End Method

	Method Equals:Int(other:SReplicationEntityId)
		Return _id = other._id And _generation = other._generation
	End Method
End Struct

Rem
bbdoc: Describes one field in a replicated entity schema.
End Rem
Struct SReplicationField
	Field _id:UInt
	Field _fieldType:EReplicationFieldType
	Field _maxStringBytes:UInt

	Method New()
	End Method

	Method New(id:UInt, fieldType:EReplicationFieldType, maxStringBytes:UInt)
		_id = id
		_fieldType = fieldType
		_maxStringBytes = maxStringBytes
	End Method

	Method Id:UInt()
		Return _id
	End Method

	Method FieldType:EReplicationFieldType()
		Return _fieldType
	End Method

	Method MaxStringBytes:UInt()
		Return _maxStringBytes
	End Method
End Struct

Rem
bbdoc: Defines the typed fields carried by one kind of replicated entity.
about: Schemas are frozen when registered with a replication world. Every
participant must register the same type id, version, field ids, field types,
and string limits before processing that entity type.
End Rem
Type TReplicationSchema
	Field _typeId:UInt
	Field _version:UInt
	Field _fields:SReplicationField[]
	Field _count:Int
	Field _frozen:Int
	Field _updateMode:EReplicationUpdateMode
	Field _fullRefreshTicks:UInt

	Method New(typeId:UInt, version:UInt, maximumFields:Int)
		_typeId = typeId
		_version = version
		_fields = New SReplicationField[maximumFields]
	End Method

	Method AddField:Int(fieldId:UInt, fieldType:EReplicationFieldType, maxStringBytes:UInt)
		If _frozen Or fieldId > 65535 Or _count = _fields.Length Then Return False
		If fieldType < EReplicationFieldType.Int32 Or fieldType > EReplicationFieldType.Utf8String Then Return False
		If fieldType = EReplicationFieldType.Utf8String And maxStringBytes > 65535 Then Return False
		If fieldType <> EReplicationFieldType.Utf8String Then maxStringBytes = 0
		If FindField(fieldId) >= 0 Then Return False
		_fields[_count] = New SReplicationField(fieldId, fieldType, maxStringBytes)
		_count :+ 1
		Return True
	End Method

	Method Freeze()
		_frozen = True
	End Method

	Method CalculateFingerprint:ULong()
		Local hash:ULong = $cbf29ce484222325:ULong
		hash = ReplicationHashUInt32(hash, _typeId)
		hash = ReplicationHashUInt32(hash, _version)
		hash = ReplicationHashUInt32(hash, UInt(_updateMode))
		hash = ReplicationHashUInt32(hash, _fullRefreshTicks)
		hash = ReplicationHashUInt32(hash, UInt(_count))
		For Local index:Int = 0 Until _count
			hash = ReplicationHashUInt32(hash, _fields[index].Id())
			hash = ReplicationHashUInt32(hash, UInt(_fields[index].FieldType()))
			hash = ReplicationHashUInt32(hash, _fields[index].MaxStringBytes())
		Next
		Return hash
	End Method

	Rem
	bbdoc: Creates a schema for @typeId and application-defined @version.
	End Rem
	Function Create:TReplicationSchema(typeId:UInt, version:UInt = 1, maximumFields:Int = 64)
		If typeId = 0 Or maximumFields < 1 Or maximumFields > 65535 Then Return Null
		Return New TReplicationSchema(typeId, version, maximumFields)
	End Function

	Method TypeId:UInt()
		Return _typeId
	End Method

	Method Version:UInt()
		Return _version
	End Method

	Method FieldCount:Int()
		Return _count
	End Method

	Method IsFrozen:Int()
		Return _frozen
	End Method

	Rem
	bbdoc: Returns a deterministic fingerprint of this schema's ordered definition.
	End Rem
	Method Fingerprint:ULong()
		Return CalculateFingerprint()
	End Method

	Method UpdateMode:EReplicationUpdateMode()
		Return _updateMode
	End Method

	Method FullRefreshTicks:UInt()
		Return _fullRefreshTicks
	End Method

	Rem
	bbdoc: Selects reliable changed fields or periodic unreliable full snapshots.
	returns: False after registration or for an invalid mode or refresh interval.
	about: Unreliable snapshots are sent in full whenever a field changes and
	again after @fullRefreshTicks, allowing a later snapshot to repair loss.
	End Rem
	Method SetUpdateMode:Int(mode:EReplicationUpdateMode, fullRefreshTicks:UInt = 30)
		If _frozen Then Return False
		Select mode
			Case EReplicationUpdateMode.ReliableChanges
				_fullRefreshTicks = 0
			Case EReplicationUpdateMode.UnreliableSnapshots
				If fullRefreshTicks = 0 Then Return False
				_fullRefreshTicks = fullRefreshTicks
			Default
				Return False
		End Select
		_updateMode = mode
		Return True
	End Method

	Method Field:SReplicationField(index:Int)
		If index < 0 Or index >= _count Then Return New SReplicationField
		Return _fields[index]
	End Method

	Method FindField:Int(fieldId:UInt)
		For Local index:Int = 0 Until _count
			If _fields[index]._id = fieldId Then Return index
		Next
		Return -1
	End Method

	Method AddInt32:Int(fieldId:UInt)
		Return AddField(fieldId, EReplicationFieldType.Int32, 0)
	End Method

	Method AddUInt32:Int(fieldId:UInt)
		Return AddField(fieldId, EReplicationFieldType.UInt32, 0)
	End Method

	Method AddFloat32:Int(fieldId:UInt)
		Return AddField(fieldId, EReplicationFieldType.Float32, 0)
	End Method

	Method AddBool:Int(fieldId:UInt)
		Return AddField(fieldId, EReplicationFieldType.Boolean, 0)
	End Method

	Method AddString:Int(fieldId:UInt, maximumUtf8Bytes:UInt = 255)
		Return AddField(fieldId, EReplicationFieldType.Utf8String, maximumUtf8Bytes)
	End Method
End Type

Rem
bbdoc: One schema-backed entity managed by #TReplicationWorld.
End Rem
Type TReplicatedEntity
	Field _identity:SReplicationEntityId
	Field _schema:TReplicationSchema
	Field _ownerId:UInt
	Field _target:Object
	Field _values:SReplicationValue[]
	Field _dirty:Byte[]
	Field _active:Int
	Field _writable:Int
	Field _newlySpawned:Int
	Field _lastTick:UInt
	Field _lastSentTick:UInt
	Field _hasSent:Int

	Method New(identity:SReplicationEntityId, schema:TReplicationSchema, ownerId:UInt, writable:Int, newlySpawned:Int)
		_identity = identity
		_schema = schema
		_ownerId = ownerId
		_values = New SReplicationValue[schema.FieldCount()]
		_dirty = New Byte[schema.FieldCount()]
		_active = True
		_writable = writable
		_newlySpawned = newlySpawned
		For Local index:Int = 0 Until _dirty.Length
			_dirty[index] = True
		Next
	End Method

	Method FieldIndex:Int(fieldId:UInt, expected:EReplicationFieldType)
		If Not _active Then Return -1
		Local index:Int = _schema.FindField(fieldId)
		If index < 0 Or _schema._fields[index]._fieldType <> expected Then Return -1
		Return index
	End Method

	Method WritableFieldIndex:Int(fieldId:UInt, expected:EReplicationFieldType)
		If Not _writable Then Return -1
		Return FieldIndex(fieldId, expected)
	End Method

	Method ClearDirty()
		For Local index:Int = 0 Until _dirty.Length
			_dirty[index] = False
		Next
	End Method

	Method HasDirty:Int()
		For Local index:Int = 0 Until _dirty.Length
			If _dirty[index] Then Return True
		Next
		Return False
	End Method

	Method Identity:SReplicationEntityId()
		Return _identity
	End Method

	Method TypeId:UInt()
		Return _schema.TypeId()
	End Method

	Method Schema:TReplicationSchema()
		Return _schema
	End Method

	Method OwnerId:UInt()
		Return _ownerId
	End Method

	Method IsActive:Int()
		Return _active
	End Method

	Method LastTick:UInt()
		Return _lastTick
	End Method

	Method SetTarget(target:Object)
		_target = target
	End Method

	Method Target:Object()
		Return _target
	End Method

	Method SetInt32:Int(fieldId:UInt, value:Int)
		Local index:Int = WritableFieldIndex(fieldId, EReplicationFieldType.Int32)
		If index < 0 Then Return False
		If _values[index].intValue = value Then Return True
		_values[index].intValue = value
		_dirty[index] = True
		Return True
	End Method

	Method GetInt32:Int(fieldId:UInt)
		Local index:Int = FieldIndex(fieldId, EReplicationFieldType.Int32)
		If index < 0 Then Return 0
		Return _values[index].intValue
	End Method

	Method SetUInt32:Int(fieldId:UInt, value:UInt)
		Local index:Int = WritableFieldIndex(fieldId, EReplicationFieldType.UInt32)
		If index < 0 Then Return False
		If _values[index].uintValue = value Then Return True
		_values[index].uintValue = value
		_dirty[index] = True
		Return True
	End Method

	Method GetUInt32:UInt(fieldId:UInt)
		Local index:Int = FieldIndex(fieldId, EReplicationFieldType.UInt32)
		If index < 0 Then Return 0
		Return _values[index].uintValue
	End Method

	Method SetFloat32:Int(fieldId:UInt, value:Float)
		Local index:Int = WritableFieldIndex(fieldId, EReplicationFieldType.Float32)
		If index < 0 Then Return False
		If _values[index].floatValue = value Then Return True
		_values[index].floatValue = value
		_dirty[index] = True
		Return True
	End Method

	Method GetFloat32:Float(fieldId:UInt)
		Local index:Int = FieldIndex(fieldId, EReplicationFieldType.Float32)
		If index < 0 Then Return 0.0
		Return _values[index].floatValue
	End Method

	Method SetBool:Int(fieldId:UInt, value:Int)
		Local index:Int = WritableFieldIndex(fieldId, EReplicationFieldType.Boolean)
		If index < 0 Then Return False
		value = value <> 0
		If _values[index].boolValue = value Then Return True
		_values[index].boolValue = value
		_dirty[index] = True
		Return True
	End Method

	Method GetBool:Int(fieldId:UInt)
		Local index:Int = FieldIndex(fieldId, EReplicationFieldType.Boolean)
		If index < 0 Then Return False
		Return _values[index].boolValue
	End Method

	Method SetString:Int(fieldId:UInt, value:String)
		Local index:Int = WritableFieldIndex(fieldId, EReplicationFieldType.Utf8String)
		If index < 0 Then Return False
		If value = Null Then value = ""
		If _values[index].stringValue = value Then Return True
		Local length:Size_T
		Local bytes:Byte Ptr = value.ToUTF8String(length)
		If length > Size_T(_schema._fields[index]._maxStringBytes) Then
			MemFree(bytes)
			Return False
		End If
		_values[index].stringBytes = New Byte[Int(length)]
		If length Then MemCopy(Byte Ptr(_values[index].stringBytes), bytes, length)
		MemFree(bytes)
		_values[index].stringValue = value
		_dirty[index] = True
		Return True
	End Method

	Method GetString:String(fieldId:UInt)
		Local index:Int = FieldIndex(fieldId, EReplicationFieldType.Utf8String)
		If index < 0 Then Return ""
		Return _values[index].stringValue
	End Method
End Type

Rem
bbdoc: Configuration for a bounded replicated entity world.
End Rem
Struct SReplicationConfig
	Field maxEntities:Int
	Field maxSchemas:Int
	Field maxPeers:Int
	Field maxFieldsPerSchema:Int
	Field eventCapacity:Int
	Field packetCapacity:Size_T
	Field messageType:UInt
	Field channel:UInt

	Method New(maxEntities:Int = 1024, maxSchemas:Int = 64, maxPeers:Int = 16, maxFieldsPerSchema:Int = 64, eventCapacity:Int = 256, packetCapacity:Size_T = 1200, messageType:UInt = 70, channel:UInt = 0)
		Self.maxEntities = maxEntities
		Self.maxSchemas = maxSchemas
		Self.maxPeers = maxPeers
		Self.maxFieldsPerSchema = maxFieldsPerSchema
		Self.eventCapacity = eventCapacity
		Self.packetCapacity = packetCapacity
		Self.messageType = messageType
		Self.channel = channel
	End Method
End Struct

Rem
bbdoc: A spawn, update, despawn, ownership, or error notification.
End Rem
Struct SReplicationEvent
	Private
	Field _kind:EReplicationEventKind
	Field _entity:TReplicatedEntity
	Field _tick:UInt
	Field _reason:Int
	Field _failure:EReplicationFailure

	Method New(kind:EReplicationEventKind, entity:TReplicatedEntity, tick:UInt, reason:Int, failure:EReplicationFailure)
		_kind = kind
		_entity = entity
		_tick = tick
		_reason = reason
		_failure = failure
	End Method

	Public
	Method New()
	End Method

	Method Kind:EReplicationEventKind()
		Return _kind
	End Method

	Method Entity:TReplicatedEntity()
		Return _entity
	End Method

	Method Tick:UInt()
		Return _tick
	End Method

	Method Reason:Int()
		Return _reason
	End Method

	Method Failure:EReplicationFailure()
		Return _failure
	End Method
End Struct

Rem
bbdoc: Manages an authoritative or replica collection of schema-backed entities.
about: The application retains control of #TNetSession polling. Route the
configured replication message type to #Receive. The authority calls #Flush
after changing entity fields. Initial field updates are reliable and ordered,
matching BRL.GNet's safe shared-state semantics.
End Rem
Type TReplicationWorld
	Private
	Field _session:TNetSession
	Field _role:EReplicationRole
	Field _config:SReplicationConfig
	Field _schemas:TReplicationSchema[]
	Field _schemaCount:Int
	Field _entities:TReplicatedEntity[]
	Field _generations:UInt[]
	Field _peers:SNetPeer[]
	Field _peerUsed:Byte[]
	Field _authorityPeer:SNetPeer
	Field _hasAuthorityPeer:Int
	Field _packetBuffer:Byte Ptr
	Field _decoded:SDecodedReplicationField[]
	Field _decodedSeen:Byte[]
	Field _events:SReplicationEvent[]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _droppedEvents:Int
	Field _rejectedPackets:Int
	Field _lastFailure:EReplicationFailure

	Method New(session:TNetSession, role:EReplicationRole, config:SReplicationConfig)
		_session = session
		_role = role
		_config = config
		_schemas = New TReplicationSchema[config.maxSchemas]
		_entities = New TReplicatedEntity[config.maxEntities]
		_generations = New UInt[config.maxEntities]
		_peers = New SNetPeer[config.maxPeers]
		_peerUsed = New Byte[config.maxPeers]
		_packetBuffer = MemAlloc(config.packetCapacity)
		_decoded = New SDecodedReplicationField[config.maxFieldsPerSchema]
		_decodedSeen = New Byte[config.maxFieldsPerSchema]
		_events = New SReplicationEvent[config.eventCapacity]
	End Method

	Function ValidConfigValues:Int(config:SReplicationConfig)
		If config.maxEntities < 1 Or config.maxSchemas < 1 Or config.maxPeers < 1 Then Return False
		If config.maxFieldsPerSchema < 1 Or config.maxFieldsPerSchema > 65535 Then Return False
		If config.eventCapacity < 1 Or config.packetCapacity < REPLICATION_MINIMUM_PACKET_SIZE Then Return False
		If config.messageType > 65535 Then Return False
		Return True
	End Function

	Function ValidConfig:Int(session:TNetSession, config:SReplicationConfig)
		Return session <> Null And ValidConfigValues(config)
	End Function

	Method Fail(failure:EReplicationFailure, entity:TReplicatedEntity = Null, tick:UInt = 0)
		_lastFailure = failure
		QueueEvent(EReplicationEventKind.Error, entity, tick, 0, failure)
	End Method

	Method Reject:Int(failure:EReplicationFailure, entity:TReplicatedEntity = Null, tick:UInt = 0)
		_rejectedPackets :+ 1
		Fail(failure, entity, tick)
		Return False
	End Method

	Method QueueEvent(kind:EReplicationEventKind, entity:TReplicatedEntity, tick:UInt, reason:Int = 0, failure:EReplicationFailure = EReplicationFailure.None)
		If _eventCount = _events.Length Then
			_droppedEvents :+ 1
			_lastFailure = EReplicationFailure.EventQueueOverflow
			Return
		End If
		_events[_eventWrite] = New SReplicationEvent(kind, entity, tick, reason, failure)
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
	End Method

	Method SchemaForType:TReplicationSchema(typeId:UInt)
		For Local index:Int = 0 Until _schemaCount
			If _schemas[index]._typeId = typeId Then Return _schemas[index]
		Next
		Return Null
	End Method

	Method ResolveEntityIndex:Int(identity:SReplicationEntityId)
		If Not identity.IsValid() Or identity.Id() > UInt(_entities.Length) Then Return -1
		Local index:Int = Int(identity.Id()) - 1
		If Not _entities[index] Or Not _entities[index]._active Then Return -1
		If _entities[index]._identity.Generation() <> identity.Generation() Then Return -1
		Return index
	End Method

	Method PeerAllowed:Int(peer:SNetPeer)
		If _role = EReplicationRole.Replica Then Return _hasAuthorityPeer And _authorityPeer.Equals(peer)
		For Local index:Int = 0 Until _peers.Length
			If _peerUsed[index] And _peers[index].Equals(peer) Then Return True
		Next
		Return False
	End Method

	Method WriteValue:Int(writer:SPacketWriter Var, entity:TReplicatedEntity, index:Int)
		Local definition:SReplicationField = entity._schema._fields[index]
		Local value:SReplicationValue = entity._values[index]
		writer.WriteUInt16(definition._id)
		writer.WriteUInt8(UInt(definition._fieldType))
		Select definition._fieldType
			Case EReplicationFieldType.Int32
				writer.WriteUInt32(UInt(value.intValue))
			Case EReplicationFieldType.UInt32
				writer.WriteUInt32(value.uintValue)
			Case EReplicationFieldType.Float32
				writer.WriteFloat32(value.floatValue)
			Case EReplicationFieldType.Boolean
				writer.WriteUInt8(UInt(value.boolValue <> 0))
			Case EReplicationFieldType.Utf8String
				Local length:UInt
				If value.stringBytes Then length = UInt(value.stringBytes.Length)
				writer.WriteUInt16(length)
				If length Then writer.WriteBytes(Byte Ptr(value.stringBytes), Size_T(length))
		End Select
		Return Not writer.Failed()
	End Method

	Method WriteFields:Int(writer:SPacketWriter Var, entity:TReplicatedEntity, allFields:Int)
		Local count:UInt
		For Local index:Int = 0 Until entity._schema._count
			If allFields Or entity._dirty[index] Then count :+ 1
		Next
		If count > 65535 Then Return False
		writer.WriteUInt16(count)
		For Local index:Int = 0 Until entity._schema._count
			If allFields Or entity._dirty[index] Then
				If Not WriteValue(writer, entity, index) Then Return False
			End If
		Next
		Return Not writer.Failed()
	End Method

	Method WriteSpawn:Size_T(entity:TReplicatedEntity, tick:UInt)
		Local writer:SPacketWriter = New SPacketWriter(_packetBuffer, _config.packetCapacity)
		writer.WriteUInt8(REPLICATION_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(EReplicationPacketKind.Spawn))
		writer.WriteUInt32(tick)
		writer.WriteUInt32(entity._identity.Id())
		writer.WriteUInt32(entity._identity.Generation())
		writer.WriteUInt32(entity._schema.TypeId())
		writer.WriteUInt32(entity._schema.Version())
		writer.WriteUInt64(entity._schema.Fingerprint())
		writer.WriteUInt32(entity._ownerId)
		If Not WriteFields(writer, entity, True) Then Return 0
		Return writer.Position()
	End Method

	Method WriteUpdate:Size_T(entity:TReplicatedEntity, tick:UInt, allFields:Int)
		Local writer:SPacketWriter = New SPacketWriter(_packetBuffer, _config.packetCapacity)
		writer.WriteUInt8(REPLICATION_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(EReplicationPacketKind.Update))
		writer.WriteUInt32(tick)
		writer.WriteUInt32(entity._identity.Id())
		writer.WriteUInt32(entity._identity.Generation())
		If Not WriteFields(writer, entity, allFields) Then Return 0
		Return writer.Position()
	End Method

	Method WriteDespawn:Size_T(entity:TReplicatedEntity, tick:UInt, reason:Int)
		Local writer:SPacketWriter = New SPacketWriter(_packetBuffer, _config.packetCapacity)
		writer.WriteUInt8(REPLICATION_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(EReplicationPacketKind.Despawn))
		writer.WriteUInt32(tick)
		writer.WriteUInt32(entity._identity.Id())
		writer.WriteUInt32(entity._identity.Generation())
		writer.WriteUInt32(UInt(reason))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method WriteOwnership:Size_T(entity:TReplicatedEntity, tick:UInt)
		Local writer:SPacketWriter = New SPacketWriter(_packetBuffer, _config.packetCapacity)
		writer.WriteUInt8(REPLICATION_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(EReplicationPacketKind.Ownership))
		writer.WriteUInt32(tick)
		writer.WriteUInt32(entity._identity.Id())
		writer.WriteUInt32(entity._identity.Generation())
		writer.WriteUInt32(entity._ownerId)
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method SendToPeer:ETransportResult(peer:SNetPeer, length:Size_T, delivery:EDeliveryMode = EDeliveryMode.ReliableOrdered)
		If length = 0 Then
			Fail(EReplicationFailure.PacketTooLarge)
			Return ETransportResult.PacketTooLarge
		End If
		Return _session.Send(peer, _config.messageType, _config.channel, delivery, _packetBuffer, length)
	End Method

	Method Broadcast:ETransportResult(length:Size_T, delivery:EDeliveryMode = EDeliveryMode.ReliableOrdered)
		If length = 0 Then
			Fail(EReplicationFailure.PacketTooLarge)
			Return ETransportResult.PacketTooLarge
		End If
		Local result:ETransportResult = ETransportResult.Ok
		For Local index:Int = 0 Until _peers.Length
			If Not _peerUsed[index] Then Continue
			Local sent:ETransportResult = SendToPeer(_peers[index], length, delivery)
			If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
		Next
		Return result
	End Method

	Method ParseFields:Int(reader:SPacketReader Var, schema:TReplicationSchema, fieldCount:UInt, requireComplete:Int)
		If fieldCount > UInt(schema._count) Or fieldCount > UInt(_decoded.Length) Then Return False
		For Local index:Int = 0 Until schema._count
			_decodedSeen[index] = False
		Next
		For Local decodedIndex:Int = 0 Until Int(fieldCount)
			Local fieldId:UInt, typeValue:UInt
			If Not reader.ReadUInt16(fieldId) Or Not reader.ReadUInt8(typeValue) Then Return False
			Local fieldIndex:Int = schema.FindField(fieldId)
			If fieldIndex < 0 Or _decodedSeen[fieldIndex] Then Return False
			Local fieldType:EReplicationFieldType = EReplicationFieldType(typeValue)
			If schema._fields[fieldIndex]._fieldType <> fieldType Then Return False
			_decodedSeen[fieldIndex] = True
			_decoded[decodedIndex] = New SDecodedReplicationField
			_decoded[decodedIndex].fieldIndex = fieldIndex
			_decoded[decodedIndex].fieldType = fieldType
			Select fieldType
				Case EReplicationFieldType.Int32
					Local encoded:UInt
					If Not reader.ReadUInt32(encoded) Then Return False
					_decoded[decodedIndex].intValue = Int(encoded)
				Case EReplicationFieldType.UInt32
					If Not reader.ReadUInt32(_decoded[decodedIndex].uintValue) Then Return False
				Case EReplicationFieldType.Float32
					If Not reader.ReadFloat32(_decoded[decodedIndex].floatValue) Then Return False
				Case EReplicationFieldType.Boolean
					Local encoded:UInt
					If Not reader.ReadUInt8(encoded) Or encoded > 1 Then Return False
					_decoded[decodedIndex].boolValue = encoded <> 0
				Case EReplicationFieldType.Utf8String
					Local length:UInt
					If Not reader.ReadUInt16(length) Or length > schema._fields[fieldIndex]._maxStringBytes Then Return False
					If Size_T(length) > reader.Remaining() Then Return False
					_decoded[decodedIndex].bytes = New SPacketView(reader.RemainingView().Data(), Size_T(length))
					If Not reader.Skip(Size_T(length)) Then Return False
				Default
					Return False
			End Select
		Next
		If requireComplete And fieldCount <> UInt(schema._count) Then Return False
		Return True
	End Method

	Method ApplyFields(entity:TReplicatedEntity, fieldCount:UInt)
		For Local decodedIndex:Int = 0 Until Int(fieldCount)
			Local index:Int = _decoded[decodedIndex].fieldIndex
			Select _decoded[decodedIndex].fieldType
				Case EReplicationFieldType.Int32
					entity._values[index].intValue = _decoded[decodedIndex].intValue
				Case EReplicationFieldType.UInt32
					entity._values[index].uintValue = _decoded[decodedIndex].uintValue
				Case EReplicationFieldType.Float32
					entity._values[index].floatValue = _decoded[decodedIndex].floatValue
				Case EReplicationFieldType.Boolean
					entity._values[index].boolValue = _decoded[decodedIndex].boolValue
				Case EReplicationFieldType.Utf8String
					Local length:Int = Int(_decoded[decodedIndex].bytes.Length())
					entity._values[index].stringBytes = New Byte[length]
					If length Then MemCopy(Byte Ptr(entity._values[index].stringBytes), _decoded[decodedIndex].bytes.Data(), Size_T(length))
					entity._values[index].stringValue = String.FromUTF8Bytes(Byte Ptr(entity._values[index].stringBytes), length)
			End Select
			entity._dirty[index] = True
		Next
	End Method

	Method ReceiveSpawn:Int(reader:SPacketReader Var, tick:UInt)
		Local id:UInt, generation:UInt, typeId:UInt, schemaVersion:UInt, ownerId:UInt, fieldCount:UInt
		Local schemaFingerprint:ULong
		If Not reader.ReadUInt32(id) Or Not reader.ReadUInt32(generation) Or Not reader.ReadUInt32(typeId) Or Not reader.ReadUInt32(schemaVersion) Or Not reader.ReadUInt64(schemaFingerprint) Or Not reader.ReadUInt32(ownerId) Or Not reader.ReadUInt16(fieldCount) Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
		If id = 0 Or id > UInt(_entities.Length) Or generation = 0 Then Return Reject(EReplicationFailure.EntityCapacity, Null, tick)
		Local schema:TReplicationSchema = SchemaForType(typeId)
		If Not schema Then Return Reject(EReplicationFailure.UnknownSchema, Null, tick)
		If schema.Version() <> schemaVersion Then Return Reject(EReplicationFailure.SchemaVersionMismatch, Null, tick)
		If schema.Fingerprint() <> schemaFingerprint Then Return Reject(EReplicationFailure.SchemaFingerprintMismatch, Null, tick)
		If Not ParseFields(reader, schema, fieldCount, True) Or reader.Remaining() <> 0 Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)

		Local index:Int = Int(id) - 1
		Local entity:TReplicatedEntity = _entities[index]
		If entity And entity._active And entity._identity.Generation() = generation Then
			If entity._schema.TypeId() <> typeId Then Return Reject(EReplicationFailure.InvalidPacket, entity, tick)
			ApplyFields(entity, fieldCount)
			entity._ownerId = ownerId
			entity._lastTick = tick
			QueueEvent(EReplicationEventKind.Updated, entity, tick)
			Return True
		End If

		If entity And entity._active Then
			entity._active = False
			QueueEvent(EReplicationEventKind.Despawned, entity, tick)
		End If
		Local identity:SReplicationEntityId = New SReplicationEntityId(id, generation)
		entity = New TReplicatedEntity(identity, schema, ownerId, False, False)
		ApplyFields(entity, fieldCount)
		entity.ClearDirty()
		entity._lastTick = tick
		_entities[index] = entity
		_generations[index] = generation
		QueueEvent(EReplicationEventKind.Spawned, entity, tick)
		Return True
	End Method

	Method ReceiveUpdate:Int(reader:SPacketReader Var, tick:UInt)
		Local id:UInt, generation:UInt, fieldCount:UInt
		If Not reader.ReadUInt32(id) Or Not reader.ReadUInt32(generation) Or Not reader.ReadUInt16(fieldCount) Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
		Local identity:SReplicationEntityId = New SReplicationEntityId(id, generation)
		Local index:Int = ResolveEntityIndex(identity)
		If index < 0 Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
		Local entity:TReplicatedEntity = _entities[index]
		If Not ReplicationTickAfter(tick, entity._lastTick) Then Return True
		If Not ParseFields(reader, entity._schema, fieldCount, False) Or fieldCount = 0 Or reader.Remaining() <> 0 Then Return Reject(EReplicationFailure.InvalidPacket, entity, tick)
		ApplyFields(entity, fieldCount)
		entity._lastTick = tick
		QueueEvent(EReplicationEventKind.Updated, entity, tick)
		Return True
	End Method

	Method ReceiveDespawn:Int(reader:SPacketReader Var, tick:UInt)
		Local id:UInt, generation:UInt, reason:UInt
		If Not reader.ReadUInt32(id) Or Not reader.ReadUInt32(generation) Or Not reader.ReadUInt32(reason) Or reader.Remaining() <> 0 Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
		Local identity:SReplicationEntityId = New SReplicationEntityId(id, generation)
		Local index:Int = ResolveEntityIndex(identity)
		If index < 0 Then Return True
		Local entity:TReplicatedEntity = _entities[index]
		entity._active = False
		entity._lastTick = tick
		_entities[index] = Null
		QueueEvent(EReplicationEventKind.Despawned, entity, tick, Int(reason))
		Return True
	End Method

	Method ReceiveOwnership:Int(reader:SPacketReader Var, tick:UInt)
		Local id:UInt, generation:UInt, ownerId:UInt
		If Not reader.ReadUInt32(id) Or Not reader.ReadUInt32(generation) Or Not reader.ReadUInt32(ownerId) Or reader.Remaining() <> 0 Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
		Local identity:SReplicationEntityId = New SReplicationEntityId(id, generation)
		Local index:Int = ResolveEntityIndex(identity)
		If index < 0 Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
		Local entity:TReplicatedEntity = _entities[index]
		If Not ReplicationTickAfter(tick, entity._lastTick) Then Return True
		entity._ownerId = ownerId
		entity._lastTick = tick
		QueueEvent(EReplicationEventKind.OwnershipChanged, entity, tick)
		Return True
	End Method

	Public
	Rem
	bbdoc: Calculates maximum bounded payload storage for @config without allocating it.
	returns: False for an invalid configuration or Size_T arithmetic overflow.
	about: The managed estimate includes fixed world arrays and per-field arrays
	for every entity slot. Runtime object and array headers, target objects, and
	the variable UTF-8 contents of string fields are not included.
	End Rem
	Function MemoryRequirements:Int(config:SReplicationConfig, requirements:SNetMemoryRequirements Var)
		requirements = New SNetMemoryRequirements
		If Not ValidConfigValues(config) Then Return False
		Local nativeBytes:Size_T = config.packetCapacity
		Local managedBytes:Size_T
		Local entityCount:Size_T = Size_T(config.maxEntities)
		Local schemaCount:Size_T = Size_T(config.maxSchemas)
		Local peerCount:Size_T = Size_T(config.maxPeers)
		Local fieldCount:Size_T = Size_T(config.maxFieldsPerSchema)
		Local eventCount:Size_T = Size_T(config.eventCapacity)
		Local entityFields:Size_T
		If Not NetAccumulateSize(entityFields, entityCount, fieldCount) Then Return False
		If Not NetAccumulateSize(managedBytes, schemaCount, Size_T(SizeOf(Byte Ptr Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, entityCount, Size_T(SizeOf(Byte Ptr Null) + SizeOf(UInt Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, peerCount, Size_T(SizeOf(SNetPeer) + SizeOf(Byte Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, fieldCount, Size_T(SizeOf(SDecodedReplicationField) + SizeOf(Byte Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, eventCount, Size_T(SizeOf(SReplicationEvent))) Then Return False
		If Not NetAccumulateSize(managedBytes, entityFields, Size_T(SizeOf(SReplicationValue) + SizeOf(Byte Null))) Then Return False
		Local totalBytes:Size_T = nativeBytes
		If Not NetAccumulateSize(totalBytes, 1, managedBytes) Then Return False
		requirements = New SNetMemoryRequirements(nativeBytes, managedBytes)
		Return True
	End Function

	Function CreateAuthority:TReplicationWorld(session:TNetSession, config:SReplicationConfig)
		If Not ValidConfig(session, config) Then Return Null
		Return New TReplicationWorld(session, EReplicationRole.Authority, config)
	End Function

	Function CreateAuthority:TReplicationWorld(session:TNetSession)
		Return CreateAuthority(session, New SReplicationConfig)
	End Function

	Function CreateReplica:TReplicationWorld(session:TNetSession, config:SReplicationConfig)
		If Not ValidConfig(session, config) Then Return Null
		Return New TReplicationWorld(session, EReplicationRole.Replica, config)
	End Function

	Function CreateReplica:TReplicationWorld(session:TNetSession)
		Return CreateReplica(session, New SReplicationConfig)
	End Function

	Method Role:EReplicationRole()
		Return _role
	End Method

	Method RegisterSchema:Int(schema:TReplicationSchema)
		If Not schema Or schema._count < 1 Or schema._count > _config.maxFieldsPerSchema Then Return False
		If _schemaCount = _schemas.Length Or SchemaForType(schema._typeId) Then Return False
		If Not schema._frozen Then schema.Freeze()
		_schemas[_schemaCount] = schema
		_schemaCount :+ 1
		Return True
	End Method

	Method AddPeer:ETransportResult(peer:SNetPeer, tick:UInt = 0)
		If _role <> EReplicationRole.Authority Or Not peer.IsValid() Then Return ETransportResult.InvalidPeer
		For Local index:Int = 0 Until _peers.Length
			If _peerUsed[index] And _peers[index].Equals(peer) Then Return ETransportResult.Ok
		Next
		Local freeIndex:Int = -1
		For Local index:Int = 0 Until _peers.Length
			If Not _peerUsed[index] Then freeIndex = index; Exit
		Next
		If freeIndex < 0 Then Return ETransportResult.WouldBlock
		_peers[freeIndex] = peer
		_peerUsed[freeIndex] = True
		Local result:ETransportResult = ETransportResult.Ok
		For Local index:Int = 0 Until _entities.Length
			Local entity:TReplicatedEntity = _entities[index]
			If Not entity Or Not entity._active Then Continue
			Local sent:ETransportResult = SendToPeer(peer, WriteSpawn(entity, tick))
			If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
		Next
		Return result
	End Method

	Method RemovePeer:Int(peer:SNetPeer)
		For Local index:Int = 0 Until _peers.Length
			If _peerUsed[index] And _peers[index].Equals(peer) Then
				_peerUsed[index] = False
				_peers[index] = New SNetPeer
				Return True
			End If
		Next
		Return False
	End Method

	Method BindAuthority:Int(peer:SNetPeer)
		If _role <> EReplicationRole.Replica Or Not peer.IsValid() Then Return False
		_authorityPeer = peer
		_hasAuthorityPeer = True
		Return True
	End Method

	Method Spawn:TReplicatedEntity(typeId:UInt, target:Object = Null, ownerId:UInt = 0)
		If _role <> EReplicationRole.Authority Then Return Null
		Local schema:TReplicationSchema = SchemaForType(typeId)
		If Not schema Then Fail(EReplicationFailure.UnknownSchema); Return Null
		For Local index:Int = 0 Until _entities.Length
			If _entities[index] Then Continue
			_generations[index] :+ 1
			If _generations[index] = 0 Then _generations[index] = 1
			Local identity:SReplicationEntityId = New SReplicationEntityId(UInt(index + 1), _generations[index])
			Local entity:TReplicatedEntity = New TReplicatedEntity(identity, schema, ownerId, True, True)
			entity._target = target
			_entities[index] = entity
			QueueEvent(EReplicationEventKind.Spawned, entity, 0)
			Return entity
		Next
		Fail(EReplicationFailure.EntityCapacity)
		Return Null
	End Method

	Method Entity:TReplicatedEntity(identity:SReplicationEntityId)
		Local index:Int = ResolveEntityIndex(identity)
		If index < 0 Then Return Null
		Return _entities[index]
	End Method

	Rem
	bbdoc: Returns the fixed entity-slot capacity of this world.
	End Rem
	Method EntityCapacity:Int()
		Return _entities.Length
	End Method

	Rem
	bbdoc: Returns the active entity in @slot, or Null when that slot is empty.
	about: This provides allocation-free enumeration when a game needs to visit
	the complete replicated world rather than respond only to transition events.
	End Rem
	Method EntityAt:TReplicatedEntity(slot:Int)
		If slot < 0 Or slot >= _entities.Length Then Return Null
		Return _entities[slot]
	End Method

	Method Flush:ETransportResult(tick:UInt)
		If _role <> EReplicationRole.Authority Then Return ETransportResult.Failed
		Local result:ETransportResult = ETransportResult.Ok
		For Local index:Int = 0 Until _entities.Length
			Local entity:TReplicatedEntity = _entities[index]
			If Not entity Or Not entity._active Then Continue
			Local length:Size_T
			Local delivery:EDeliveryMode = EDeliveryMode.ReliableOrdered
			If entity._newlySpawned Then
				length = WriteSpawn(entity, tick)
			Else
				Select entity._schema.UpdateMode()
					Case EReplicationUpdateMode.ReliableChanges
						If Not entity.HasDirty() Then Continue
						length = WriteUpdate(entity, tick, False)
					Case EReplicationUpdateMode.UnreliableSnapshots
						Local refreshDue:Int = entity._hasSent And UInt(tick - entity._lastSentTick) >= entity._schema.FullRefreshTicks()
						If Not entity.HasDirty() And Not refreshDue Then Continue
						length = WriteUpdate(entity, tick, True)
						delivery = EDeliveryMode.UnreliableSequenced
				End Select
			End If
			Local sent:ETransportResult = Broadcast(length, delivery)
			If sent = ETransportResult.Ok Then
				entity._newlySpawned = False
				entity.ClearDirty()
				entity._lastTick = tick
				entity._lastSentTick = tick
				entity._hasSent = True
			Else If result = ETransportResult.Ok Then
				result = sent
			End If
		Next
		Return result
	End Method

	Method SetOwner:ETransportResult(entity:TReplicatedEntity, ownerId:UInt, tick:UInt)
		If _role <> EReplicationRole.Authority Or Not entity Or ResolveEntityIndex(entity._identity) < 0 Then Return ETransportResult.InvalidPeer
		If entity._ownerId = ownerId Then Return ETransportResult.Ok
		entity._ownerId = ownerId
		Local result:ETransportResult = Broadcast(WriteOwnership(entity, tick))
		If result = ETransportResult.Ok Then
			entity._lastTick = tick
			QueueEvent(EReplicationEventKind.OwnershipChanged, entity, tick)
		End If
		Return result
	End Method

	Method Despawn:ETransportResult(entity:TReplicatedEntity, reason:Int = 0, tick:UInt = 0)
		If _role <> EReplicationRole.Authority Or Not entity Then Return ETransportResult.Failed
		Local index:Int = ResolveEntityIndex(entity._identity)
		If index < 0 Then Return ETransportResult.InvalidPeer
		Local result:ETransportResult = Broadcast(WriteDespawn(entity, tick, reason))
		If result <> ETransportResult.Ok Then Return result
		entity._active = False
		entity._lastTick = tick
		_entities[index] = Null
		QueueEvent(EReplicationEventKind.Despawned, entity, tick, reason)
		Return ETransportResult.Ok
	End Method

	Method Receive:Int(peer:SNetPeer, messageType:UInt, packet:SPacketView)
		If messageType <> _config.messageType Then Return False
		If _role <> EReplicationRole.Replica Or Not PeerAllowed(peer) Then Return Reject(EReplicationFailure.WrongAuthority)
		Local reader:SPacketReader = New SPacketReader(packet)
		Local version:UInt, kindValue:UInt, tick:UInt
		If Not reader.ReadUInt8(version) Or version <> REPLICATION_PROTOCOL_VERSION Or Not reader.ReadUInt8(kindValue) Or Not reader.ReadUInt32(tick) Then Return Reject(EReplicationFailure.InvalidPacket)
		Select EReplicationPacketKind(kindValue)
			Case EReplicationPacketKind.Spawn
				Return ReceiveSpawn(reader, tick)
			Case EReplicationPacketKind.Update
				Return ReceiveUpdate(reader, tick)
			Case EReplicationPacketKind.Despawn
				Return ReceiveDespawn(reader, tick)
			Case EReplicationPacketKind.Ownership
				Return ReceiveOwnership(reader, tick)
		End Select
		Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
	End Method

	Method Poll:Int(event:SReplicationEvent Var)
		If _eventCount = 0 Then
			event = New SReplicationEvent
			Return False
		End If
		event = _events[_eventRead]
		_events[_eventRead] = New SReplicationEvent
		_eventRead = (_eventRead + 1) Mod _events.Length
		_eventCount :- 1
		Return True
	End Method

	Method RejectedPackets:Int()
		Return _rejectedPackets
	End Method

	Method DroppedEvents:Int()
		Return _droppedEvents
	End Method

	Method LastFailure:EReplicationFailure()
		Return _lastFailure
	End Method

	Method Close()
		If _packetBuffer Then MemFree(_packetBuffer)
		_packetBuffer = Null
	End Method

	Method Delete()
		Close()
	End Method
End Type

Rem
bbdoc: Returns True when @candidate is after @reference in modular tick order.
End Rem
Function ReplicationTickAfter:Int(candidate:UInt, reference:UInt)
	Return candidate <> reference And Int(candidate - reference) > 0
End Function

?
