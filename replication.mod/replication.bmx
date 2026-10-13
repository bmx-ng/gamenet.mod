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

ModuleInfo "Version: 0.5"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.5 Add bounded update batching and flush traffic diagnostics"
ModuleInfo "History: 0.4 Add bounded per-peer entity relevance"
ModuleInfo "History: 0.3 Add bounded application field codecs"
ModuleInfo "History: 0.2 Add schema fingerprints, memory sizing, and periodic unreliable snapshots"
ModuleInfo "History: 0.1 Initial schema, entity lifecycle, and reliable field replication"

Import GameNet.Core
Import GameNet.Session

Private

Const REPLICATION_PROTOCOL_VERSION:UInt = 3
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
	UpdateBatch
End Enum

Public

Rem
bbdoc: Encodes and decodes one bounded custom replication field.
about: CodecId and CodecVersion form part of the schema fingerprint and must
be stable across every participant. Encode and Decode operate on bounded
packet views supplied by GameNet; Decode must consume the complete view.
End Rem
Interface IReplicationFieldCodec
	Rem
	bbdoc: Returns a non-zero application-defined identifier for the payload format.
	End Rem
	Method CodecId:UInt()

	Rem
	bbdoc: Returns the application-defined version of the payload format.
	End Rem
	Method CodecVersion:UInt()

	Rem
	bbdoc: Returns the maximum number of bytes produced by #Encode.
	End Rem
	Method MaximumBytes:UInt()

	Rem
	bbdoc: Writes @value and returns True, or returns False when it cannot be encoded.
	End Rem
	Method Encode:Int(value:Object, writer:SPacketWriter Var)

	Rem
	bbdoc: Decodes one complete field payload into @value.
	End Rem
	Method Decode:Int(reader:SPacketReader Var, value:Object Var)
End Interface

Struct SReplicationValue
	Field intValue:Int
	Field uintValue:UInt
	Field floatValue:Float
	Field boolValue:Int
	Field stringValue:String
	Field stringBytes:Byte[]
	Field customValue:Object
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
	Field customValue:Object
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
	Custom
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
	CodecFailure
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
	Field _codec:IReplicationFieldCodec

	Method New()
	End Method

	Method New(id:UInt, fieldType:EReplicationFieldType, maxStringBytes:UInt, codec:IReplicationFieldCodec = Null)
		_id = id
		_fieldType = fieldType
		_maxStringBytes = maxStringBytes
		_codec = codec
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

	Rem
	bbdoc: Returns the maximum encoded byte count for a string or custom field.
	End Rem
	Method MaximumBytes:UInt()
		Return _maxStringBytes
	End Method

	Method Codec:IReplicationFieldCodec()
		Return _codec
	End Method
End Struct

Rem
bbdoc: Defines the typed fields carried by one kind of replicated entity.
about: Schemas are frozen when registered with a replication world. Every
participant must register the same type id, version, field ids, field types,
string limits, and codec definitions before processing that entity type.
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
		If fieldType < EReplicationFieldType.Int32 Or fieldType > EReplicationFieldType.Custom Then Return False
		If fieldType = EReplicationFieldType.Utf8String And maxStringBytes > 65535 Then Return False
		If fieldType = EReplicationFieldType.Custom Then Return False
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
			If _fields[index]._codec Then
				hash = ReplicationHashUInt32(hash, _fields[index]._codec.CodecId())
				hash = ReplicationHashUInt32(hash, _fields[index]._codec.CodecVersion())
			End If
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

	Rem
	bbdoc: Adds a bounded application-defined field encoded by @codec.
	returns: False for an invalid codec, duplicate id, full or frozen schema.
	End Rem
	Method AddCodec:Int(fieldId:UInt, codec:IReplicationFieldCodec)
		If _frozen Or Not codec Or fieldId > 65535 Or _count = _fields.Length Then Return False
		If codec.CodecId() = 0 Or codec.MaximumBytes() = 0 Or codec.MaximumBytes() > 65535 Then Return False
		If FindField(fieldId) >= 0 Then Return False
		_fields[_count] = New SReplicationField(fieldId, EReplicationFieldType.Custom, codec.MaximumBytes(), codec)
		_count :+ 1
		Return True
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

	Rem
	bbdoc: Assigns a custom field value and marks it for replication.
	about: The codec registered for the field determines the accepted runtime
	type. Reassigning the same object also marks it dirty, allowing mutable
	objects to be updated after their contents change.
	End Rem
	Method SetCustom:Int(fieldId:UInt, value:Object)
		Local index:Int = WritableFieldIndex(fieldId, EReplicationFieldType.Custom)
		If index < 0 Then Return False
		_values[index].customValue = value
		_dirty[index] = True
		Return True
	End Method

	Rem
	bbdoc: Returns the most recently assigned or decoded custom field value.
	End Rem
	Method GetCustom:Object(fieldId:UInt)
		Local index:Int = FieldIndex(fieldId, EReplicationFieldType.Custom)
		If index < 0 Then Return Null
		Return _values[index].customValue
	End Method

	Rem
	bbdoc: Marks a mutable custom field dirty without replacing its object.
	End Rem
	Method MarkCustomDirty:Int(fieldId:UInt)
		Local index:Int = WritableFieldIndex(fieldId, EReplicationFieldType.Custom)
		If index < 0 Then Return False
		_dirty[index] = True
		Return True
	End Method
End Type

Rem
bbdoc: Configuration for a bounded replicated entity world.
about: Set codecCapacity to the largest custom field payload accepted by any
registered schema. Leave it at zero when custom field codecs are not used.
maxUpdatesPerBatch limits the entities combined into one update packet; one
disables batching. updateBatchCapacity limits a batch packet and defaults to
packetCapacity when zero.
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
	Field codecCapacity:Size_T
	Field maxUpdatesPerBatch:Int
	Field updateBatchCapacity:Size_T

	Method New(maxEntities:Int = 1024, maxSchemas:Int = 64, maxPeers:Int = 16, maxFieldsPerSchema:Int = 64, eventCapacity:Int = 256, packetCapacity:Size_T = 1200, messageType:UInt = 70, channel:UInt = 0, codecCapacity:Size_T = 0, maxUpdatesPerBatch:Int = 64, updateBatchCapacity:Size_T = 0)
		Self.maxEntities = maxEntities
		Self.maxSchemas = maxSchemas
		Self.maxPeers = maxPeers
		Self.maxFieldsPerSchema = maxFieldsPerSchema
		Self.eventCapacity = eventCapacity
		Self.packetCapacity = packetCapacity
		Self.messageType = messageType
		Self.channel = channel
		Self.codecCapacity = codecCapacity
		Self.maxUpdatesPerBatch = maxUpdatesPerBatch
		Self.updateBatchCapacity = updateBatchCapacity
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
after changing entity fields. Schemas choose reliable changed fields or
periodically refreshed unreliable snapshots.
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
	Field _peerDefaultVisible:Byte[]
	Field _peerVisible:Byte[]
	Field _peerKnown:Byte[]
	Field _authorityPeer:SNetPeer
	Field _hasAuthorityPeer:Int
	Field _packetBuffer:Byte Ptr
	Field _codecBuffer:Byte Ptr
	Field _updateBuffer:Byte Ptr
	Field _sendCapacity:Size_T
	Field _batchCapacity:Size_T
	Field _batchEntities:Int[]
	Field _flushUpdate:Byte[]
	Field _flushFailed:Byte[]
	Field _decoded:SDecodedReplicationField[]
	Field _decodedSeen:Byte[]
	Field _events:SReplicationEvent[]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _droppedEvents:Int
	Field _rejectedPackets:Int
	Field _lastFailure:EReplicationFailure
	Field _writeFailure:EReplicationFailure
	Field _measuringFlush:Int
	Field _lastFlushPackets:Int
	Field _lastFlushBytes:Size_T

	Method New(session:TNetSession, role:EReplicationRole, config:SReplicationConfig)
		_session = session
		_role = role
		_config = config
		_schemas = New TReplicationSchema[config.maxSchemas]
		_entities = New TReplicatedEntity[config.maxEntities]
		_generations = New UInt[config.maxEntities]
		_peers = New SNetPeer[config.maxPeers]
		_peerUsed = New Byte[config.maxPeers]
		_peerDefaultVisible = New Byte[config.maxPeers]
		_peerVisible = New Byte[config.maxEntities * config.maxPeers]
		_peerKnown = New Byte[config.maxEntities * config.maxPeers]
		_packetBuffer = MemAlloc(config.packetCapacity)
		If config.codecCapacity Then _codecBuffer = MemAlloc(config.codecCapacity)
		_updateBuffer = MemAlloc(config.packetCapacity)
		_sendCapacity = EffectiveSendCapacity(session, config)
		_batchCapacity = config.updateBatchCapacity
		If _batchCapacity = 0 Or _batchCapacity > _sendCapacity Then _batchCapacity = _sendCapacity
		_batchEntities = New Int[config.maxUpdatesPerBatch]
		_flushUpdate = New Byte[config.maxEntities]
		_flushFailed = New Byte[config.maxEntities]
		_decoded = New SDecodedReplicationField[config.maxFieldsPerSchema]
		_decodedSeen = New Byte[config.maxFieldsPerSchema]
		_events = New SReplicationEvent[config.eventCapacity]
	End Method

	Function ValidConfigValues:Int(config:SReplicationConfig)
		If config.maxEntities < 1 Or config.maxSchemas < 1 Or config.maxPeers < 1 Then Return False
		If Size_T(config.maxEntities) > Size_T($7fffffff) / Size_T(config.maxPeers) Then Return False
		If config.maxFieldsPerSchema < 1 Or config.maxFieldsPerSchema > 65535 Then Return False
		If config.eventCapacity < 1 Or config.packetCapacity < REPLICATION_MINIMUM_PACKET_SIZE Then Return False
		If config.codecCapacity > 65535 Then Return False
		If config.maxUpdatesPerBatch < 1 Or config.maxUpdatesPerBatch > 65535 Then Return False
		If config.updateBatchCapacity And (config.updateBatchCapacity < REPLICATION_MINIMUM_PACKET_SIZE Or config.updateBatchCapacity > config.packetCapacity) Then Return False
		If config.messageType > 65535 Then Return False
		Return True
	End Function

	Function ValidConfig:Int(session:TNetSession, config:SReplicationConfig)
		If Not session Or Not ValidConfigValues(config) Then Return False
		Return EffectiveSendCapacity(session, config) >= REPLICATION_MINIMUM_PACKET_SIZE
	End Function

	Function EffectiveSendCapacity:Size_T(session:TNetSession, config:SReplicationConfig)
		Local capacity:Size_T = config.packetCapacity
		Local reliableLimit:Size_T = session.MaxPayloadSize(EDeliveryMode.ReliableOrdered)
		Local unreliableLimit:Size_T = session.MaxPayloadSize(EDeliveryMode.Unreliable)
		If reliableLimit And reliableLimit < capacity Then capacity = reliableLimit
		If unreliableLimit And unreliableLimit < capacity Then capacity = unreliableLimit
		Return capacity
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

	Method ResolvePeerIndex:Int(peer:SNetPeer)
		For Local index:Int = 0 Until _peers.Length
			If _peerUsed[index] And _peers[index].Equals(peer) Then Return index
		Next
		Return -1
	End Method

	Method RelevanceIndex:Int(entityIndex:Int, peerIndex:Int)
		Return entityIndex * _peers.Length + peerIndex
	End Method

	Method HasPendingVisibility:Int(entityIndex:Int)
		For Local peerIndex:Int = 0 Until _peers.Length
			If Not _peerUsed[peerIndex] Then Continue
			Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
			If _peerVisible[relevanceIndex] <> _peerKnown[relevanceIndex] Then Return True
		Next
		Return False
	End Method

	Method PeerAllowed:Int(peer:SNetPeer)
		If _role = EReplicationRole.Replica Then Return _hasAuthorityPeer And _authorityPeer.Equals(peer)
		Return ResolvePeerIndex(peer) >= 0
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
			Case EReplicationFieldType.Custom
				If Not definition._codec Or Not _codecBuffer Then
					_writeFailure = EReplicationFailure.CodecFailure
					Return False
				End If
				Local codecWriter:SPacketWriter = New SPacketWriter(_codecBuffer, Size_T(definition._maxStringBytes))
				If Not definition._codec.Encode(value.customValue, codecWriter) Or codecWriter.Failed() Then
					_writeFailure = EReplicationFailure.CodecFailure
					Return False
				End If
				Local encodedLength:Size_T = codecWriter.Position()
				If encodedLength > Size_T(definition._maxStringBytes) Or encodedLength > 65535 Then Return False
				writer.WriteUInt16(UInt(encodedLength))
				If encodedLength Then writer.WriteBytes(_codecBuffer, encodedLength)
			Default
				Return False
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
		_writeFailure = EReplicationFailure.None
		Local writer:SPacketWriter = New SPacketWriter(_packetBuffer, _sendCapacity)
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

	Method WriteUpdateBody:Size_T(entity:TReplicatedEntity, allFields:Int)
		_writeFailure = EReplicationFailure.None
		Local writer:SPacketWriter = New SPacketWriter(_updateBuffer, _sendCapacity)
		writer.WriteUInt32(entity._identity.Id())
		writer.WriteUInt32(entity._identity.Generation())
		If Not WriteFields(writer, entity, allFields) Then Return 0
		Return writer.Position()
	End Method

	Method WriteUpdate:Size_T(entity:TReplicatedEntity, tick:UInt, allFields:Int)
		Local bodyLength:Size_T = WriteUpdateBody(entity, allFields)
		If bodyLength = 0 Then Return 0
		Local writer:SPacketWriter = New SPacketWriter(_packetBuffer, _sendCapacity)
		writer.WriteUInt8(REPLICATION_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(EReplicationPacketKind.Update))
		writer.WriteUInt32(tick)
		writer.WriteBytes(_updateBuffer, bodyLength)
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method WriteDespawn:Size_T(entity:TReplicatedEntity, tick:UInt, reason:Int)
		_writeFailure = EReplicationFailure.None
		Local writer:SPacketWriter = New SPacketWriter(_packetBuffer, _sendCapacity)
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
		_writeFailure = EReplicationFailure.None
		Local writer:SPacketWriter = New SPacketWriter(_packetBuffer, _sendCapacity)
		writer.WriteUInt8(REPLICATION_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(EReplicationPacketKind.Ownership))
		writer.WriteUInt32(tick)
		writer.WriteUInt32(entity._identity.Id())
		writer.WriteUInt32(entity._identity.Generation())
		writer.WriteUInt32(entity._ownerId)
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method ReportWriteFailure:ETransportResult()
		If _writeFailure = EReplicationFailure.CodecFailure Then
			Fail(EReplicationFailure.CodecFailure)
			Return ETransportResult.Failed
		End If
		Fail(EReplicationFailure.PacketTooLarge)
		Return ETransportResult.PacketTooLarge
	End Method

	Method SendToPeer:ETransportResult(peer:SNetPeer, length:Size_T, delivery:EDeliveryMode = EDeliveryMode.ReliableOrdered)
		If length = 0 Then Return ReportWriteFailure()
		Local result:ETransportResult = _session.Send(peer, _config.messageType, _config.channel, delivery, _packetBuffer, length)
		If _measuringFlush And result = ETransportResult.Ok Then
			_lastFlushPackets :+ 1
			_lastFlushBytes :+ length
		End If
		Return result
	End Method

	Method SendToRelevant:ETransportResult(entityIndex:Int, length:Size_T, delivery:EDeliveryMode)
		If length = 0 Then Return ReportWriteFailure()
		Local result:ETransportResult = ETransportResult.Ok
		For Local peerIndex:Int = 0 Until _peers.Length
			If Not _peerUsed[peerIndex] Then Continue
			Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
			If Not _peerVisible[relevanceIndex] Or Not _peerKnown[relevanceIndex] Then Continue
			Local sent:ETransportResult = SendToPeer(_peers[peerIndex], length, delivery)
			If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
		Next
		Return result
	End Method

	Method BeginUpdateBatch(writer:SPacketWriter Var, tick:UInt)
		writer = New SPacketWriter(_packetBuffer, _batchCapacity)
		writer.WriteUInt8(REPLICATION_PROTOCOL_VERSION)
		writer.WriteUInt8(UInt(EReplicationPacketKind.UpdateBatch))
		writer.WriteUInt32(tick)
		writer.WriteUInt16(0)
	End Method

	Method FlushUpdateBatch:ETransportResult(peer:SNetPeer, writer:SPacketWriter Var, count:Int, delivery:EDeliveryMode)
		If count = 0 Then Return ETransportResult.Ok
		_packetBuffer[6] = Byte(UInt(count) Shr 8)
		_packetBuffer[7] = Byte(UInt(count))
		Local result:ETransportResult = SendToPeer(peer, writer.Position(), delivery)
		If result <> ETransportResult.Ok Then
			For Local index:Int = 0 Until count
				_flushFailed[_batchEntities[index]] = True
			Next
		End If
		Return result
	End Method

	Method SendSingleUpdate:ETransportResult(peer:SNetPeer, entity:TReplicatedEntity, entityIndex:Int, tick:UInt, allFields:Int, delivery:EDeliveryMode)
		Local length:Size_T = WriteUpdate(entity, tick, allFields)
		If length = 0 Then
			_flushFailed[entityIndex] = True
			Return ReportWriteFailure()
		End If
		If length > _batchCapacity Then
			_flushFailed[entityIndex] = True
			Fail(EReplicationFailure.PacketTooLarge, entity, tick)
			Return ETransportResult.PacketTooLarge
		End If
		Local result:ETransportResult = SendToPeer(peer, length, delivery)
		If result <> ETransportResult.Ok Then _flushFailed[entityIndex] = True
		Return result
	End Method

	Method SendUpdateBatches:ETransportResult(peerIndex:Int, tick:UInt, delivery:EDeliveryMode)
		Local result:ETransportResult = ETransportResult.Ok
		Local peer:SNetPeer = _peers[peerIndex]
		If _config.maxUpdatesPerBatch = 1 Then
			For Local entityIndex:Int = 0 Until _entities.Length
				If Not _flushUpdate[entityIndex] Then Continue
				Local entity:TReplicatedEntity = _entities[entityIndex]
				Local snapshot:Int = entity._schema.UpdateMode() = EReplicationUpdateMode.UnreliableSnapshots
				If (delivery = EDeliveryMode.Unreliable) <> snapshot Then Continue
				Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
				If Not _peerVisible[relevanceIndex] Or Not _peerKnown[relevanceIndex] Then Continue
				Local sent:ETransportResult = SendSingleUpdate(peer, entity, entityIndex, tick, snapshot, delivery)
				If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
			Next
			Return result
		End If

		Local writer:SPacketWriter
		BeginUpdateBatch(writer, tick)
		Local count:Int
		For Local entityIndex:Int = 0 Until _entities.Length
			If Not _flushUpdate[entityIndex] Then Continue
			Local entity:TReplicatedEntity = _entities[entityIndex]
			Local snapshot:Int = entity._schema.UpdateMode() = EReplicationUpdateMode.UnreliableSnapshots
			If (delivery = EDeliveryMode.Unreliable) <> snapshot Then Continue
			Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
			If Not _peerVisible[relevanceIndex] Or Not _peerKnown[relevanceIndex] Then Continue

			Local bodyLength:Size_T = WriteUpdateBody(entity, snapshot)
			If bodyLength = 0 Then
				Local flushed:ETransportResult = FlushUpdateBatch(peer, writer, count, delivery)
				If result = ETransportResult.Ok And flushed <> ETransportResult.Ok Then result = flushed
				count = 0
				BeginUpdateBatch(writer, tick)
				_flushFailed[entityIndex] = True
				Local failed:ETransportResult = ReportWriteFailure()
				If result = ETransportResult.Ok Then result = failed
				Continue
			End If

			If count = _batchEntities.Length Or bodyLength > 65535 Or writer.Remaining() < 2 Or bodyLength > writer.Remaining() - 2 Then
				Local flushed:ETransportResult = FlushUpdateBatch(peer, writer, count, delivery)
				If result = ETransportResult.Ok And flushed <> ETransportResult.Ok Then result = flushed
				count = 0
				BeginUpdateBatch(writer, tick)
			End If
			If bodyLength > 65535 Or writer.Remaining() < 2 Or bodyLength > writer.Remaining() - 2 Then
				Local sent:ETransportResult = SendSingleUpdate(peer, entity, entityIndex, tick, snapshot, delivery)
				If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
				BeginUpdateBatch(writer, tick)
				Continue
			End If
			writer.WriteUInt16(UInt(bodyLength))
			writer.WriteBytes(_updateBuffer, bodyLength)
			_batchEntities[count] = entityIndex
			count :+ 1
		Next
		Local flushed:ETransportResult = FlushUpdateBatch(peer, writer, count, delivery)
		If result = ETransportResult.Ok And flushed <> ETransportResult.Ok Then result = flushed
		Return result
	End Method

	Method SendToKnown:ETransportResult(entityIndex:Int, length:Size_T)
		If length = 0 Then Return ReportWriteFailure()
		Local result:ETransportResult = ETransportResult.Ok
		For Local peerIndex:Int = 0 Until _peers.Length
			If Not _peerUsed[peerIndex] Then Continue
			Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
			If Not _peerKnown[relevanceIndex] Then Continue
			Local sent:ETransportResult = SendToPeer(_peers[peerIndex], length)
			If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
		Next
		Return result
	End Method

	Method SynchronizeVisibility:ETransportResult(entity:TReplicatedEntity, entityIndex:Int, tick:UInt)
		Local result:ETransportResult = ETransportResult.Ok
		Local spawnLength:Size_T
		For Local peerIndex:Int = 0 Until _peers.Length
			If Not _peerUsed[peerIndex] Then Continue
			Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
			If Not _peerVisible[relevanceIndex] Or _peerKnown[relevanceIndex] Then Continue
			If spawnLength = 0 Then
				spawnLength = WriteSpawn(entity, tick)
				If spawnLength = 0 Then Return ReportWriteFailure()
			End If
			Local sent:ETransportResult = SendToPeer(_peers[peerIndex], spawnLength)
			If sent = ETransportResult.Ok Then
				_peerKnown[relevanceIndex] = True
			Else If result = ETransportResult.Ok Then
				result = sent
			End If
		Next

		Local despawnLength:Size_T
		For Local peerIndex:Int = 0 Until _peers.Length
			If Not _peerUsed[peerIndex] Then Continue
			Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
			If _peerVisible[relevanceIndex] Or Not _peerKnown[relevanceIndex] Then Continue
			If despawnLength = 0 Then
				despawnLength = WriteDespawn(entity, tick, 0)
				If despawnLength = 0 Then Return ReportWriteFailure()
			End If
			Local sent:ETransportResult = SendToPeer(_peers[peerIndex], despawnLength)
			If sent = ETransportResult.Ok Then
				_peerKnown[relevanceIndex] = False
			Else If result = ETransportResult.Ok Then
				result = sent
			End If
		Next
		Return result
	End Method

	Method SynchronizePeer:ETransportResult(peerIndex:Int, tick:UInt)
		Local result:ETransportResult = ETransportResult.Ok
		For Local entityIndex:Int = 0 Until _entities.Length
			Local entity:TReplicatedEntity = _entities[entityIndex]
			If Not entity Or Not entity._active Then Continue
			Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
			If Not _peerVisible[relevanceIndex] Or _peerKnown[relevanceIndex] Then Continue
			Local sent:ETransportResult = SendToPeer(_peers[peerIndex], WriteSpawn(entity, tick))
			If sent = ETransportResult.Ok Then
				_peerKnown[relevanceIndex] = True
			Else If result = ETransportResult.Ok Then
				result = sent
			End If
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
				Case EReplicationFieldType.Custom
					Local encodedLength:UInt
					Local definition:SReplicationField = schema._fields[fieldIndex]
					If Not definition._codec Or Not reader.ReadUInt16(encodedLength) Or encodedLength > definition._maxStringBytes Then Return False
					If Size_T(encodedLength) > reader.Remaining() Then Return False
					Local codecReader:SPacketReader = New SPacketReader(reader.RemainingView().Data(), Size_T(encodedLength))
					Local decodedValue:Object
					If Not definition._codec.Decode(codecReader, decodedValue) Or codecReader.Failed() Or codecReader.Remaining() <> 0 Then Return False
					_decoded[decodedIndex].customValue = decodedValue
					If Not reader.Skip(Size_T(encodedLength)) Then Return False
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
				Case EReplicationFieldType.Custom
					entity._values[index].customValue = _decoded[decodedIndex].customValue
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
		If Not ParseFields(reader, entity._schema, fieldCount, False) Or fieldCount = 0 Then Return Reject(EReplicationFailure.InvalidPacket, entity, tick)
		If reader.Remaining() <> 0 Then Return Reject(EReplicationFailure.InvalidPacket, entity, tick)
		If Not ReplicationTickAfter(tick, entity._lastTick) Then Return True
		ApplyFields(entity, fieldCount)
		entity._lastTick = tick
		QueueEvent(EReplicationEventKind.Updated, entity, tick)
		Return True
	End Method

	Method ReceiveUpdateBatch:Int(reader:SPacketReader Var, tick:UInt)
		Local count:UInt
		If Not reader.ReadUInt16(count) Or count = 0 Or count > UInt(_entities.Length) Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
		For Local index:Int = 0 Until Int(count)
			Local bodyLength:UInt
			If Not reader.ReadUInt16(bodyLength) Or Size_T(bodyLength) > reader.Remaining() Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
			Local itemReader:SPacketReader = New SPacketReader(reader.RemainingView().Data(), Size_T(bodyLength))
			If Not ReceiveUpdate(itemReader, tick) Then Return False
			If Not reader.Skip(Size_T(bodyLength)) Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
		Next
		If reader.Remaining() <> 0 Then Return Reject(EReplicationFailure.InvalidPacket, Null, tick)
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
	the variable UTF-8 contents of string fields are not included. Native bytes
	include the packet and update staging buffers plus optional codec scratch.
	End Rem
	Function MemoryRequirements:Int(config:SReplicationConfig, requirements:SNetMemoryRequirements Var)
		requirements = New SNetMemoryRequirements
		If Not ValidConfigValues(config) Then Return False
		Local nativeBytes:Size_T = config.packetCapacity
		If Not NetAccumulateSize(nativeBytes, 1, config.codecCapacity) Then Return False
		If Not NetAccumulateSize(nativeBytes, 1, config.packetCapacity) Then Return False
		Local managedBytes:Size_T
		Local entityCount:Size_T = Size_T(config.maxEntities)
		Local schemaCount:Size_T = Size_T(config.maxSchemas)
		Local peerCount:Size_T = Size_T(config.maxPeers)
		Local fieldCount:Size_T = Size_T(config.maxFieldsPerSchema)
		Local eventCount:Size_T = Size_T(config.eventCapacity)
		Local entityFields:Size_T
		Local relevanceSlots:Size_T
		If Not NetAccumulateSize(entityFields, entityCount, fieldCount) Then Return False
		If Not NetAccumulateSize(relevanceSlots, entityCount, peerCount) Then Return False
		If Not NetAccumulateSize(managedBytes, schemaCount, Size_T(SizeOf(Byte Ptr Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, entityCount, Size_T(SizeOf(Byte Ptr Null) + SizeOf(UInt Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, peerCount, Size_T(SizeOf(SNetPeer) + SizeOf(Byte Null) * 2)) Then Return False
		If Not NetAccumulateSize(managedBytes, fieldCount, Size_T(SizeOf(SDecodedReplicationField) + SizeOf(Byte Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, eventCount, Size_T(SizeOf(SReplicationEvent))) Then Return False
		If Not NetAccumulateSize(managedBytes, entityFields, Size_T(SizeOf(SReplicationValue) + SizeOf(Byte Null))) Then Return False
		If Not NetAccumulateSize(managedBytes, relevanceSlots, 2) Then Return False
		If Not NetAccumulateSize(managedBytes, entityCount, 2) Then Return False
		If Not NetAccumulateSize(managedBytes, Size_T(config.maxUpdatesPerBatch), Size_T(SizeOf(Int Null))) Then Return False
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

	Rem
	bbdoc: Returns the effective replication payload limit after session transport overhead.
	End Rem
	Method SendCapacity:Size_T()
		Return _sendCapacity
	End Method

	Rem
	bbdoc: Returns the effective maximum update-batch packet size.
	End Rem
	Method UpdateBatchCapacity:Size_T()
		Return _batchCapacity
	End Method

	Method RegisterSchema:Int(schema:TReplicationSchema)
		If Not schema Or schema._count < 1 Or schema._count > _config.maxFieldsPerSchema Then Return False
		If _schemaCount = _schemas.Length Or SchemaForType(schema._typeId) Then Return False
		For Local index:Int = 0 Until schema._count
			Local definition:SReplicationField = schema._fields[index]
			If definition._fieldType = EReplicationFieldType.Custom Then
				If Not definition._codec Or Size_T(definition._maxStringBytes) > _config.codecCapacity Then Return False
			End If
		Next
		If Not schema._frozen Then schema.Freeze()
		_schemas[_schemaCount] = schema
		_schemaCount :+ 1
		Return True
	End Method

	Rem
	bbdoc: Adds an accepted session peer and optionally reveals all existing entities.
	about: Passing False for @initiallyVisible lets an application establish its
	interest set with #SetPeerVisible before sending any entity state, and makes
	future entities hidden from that peer by default. Calling AddPeer again
	retries any complete spawns which previously could not be sent.
	End Rem
	Method AddPeer:ETransportResult(peer:SNetPeer, tick:UInt = 0, initiallyVisible:Int = True)
		If _role <> EReplicationRole.Authority Or Not peer.IsValid() Then Return ETransportResult.InvalidPeer
		For Local index:Int = 0 Until _peers.Length
			If _peerUsed[index] And _peers[index].Equals(peer) Then Return SynchronizePeer(index, tick)
		Next
		Local freeIndex:Int = -1
		For Local index:Int = 0 Until _peers.Length
			If Not _peerUsed[index] Then freeIndex = index; Exit
		Next
		If freeIndex < 0 Then Return ETransportResult.WouldBlock
		_peers[freeIndex] = peer
		_peerUsed[freeIndex] = True
		_peerDefaultVisible[freeIndex] = initiallyVisible <> 0
		For Local entityIndex:Int = 0 Until _entities.Length
			Local relevanceIndex:Int = RelevanceIndex(entityIndex, freeIndex)
			_peerVisible[relevanceIndex] = initiallyVisible <> 0
			_peerKnown[relevanceIndex] = False
		Next
		Return SynchronizePeer(freeIndex, tick)
	End Method

	Method RemovePeer:Int(peer:SNetPeer)
		For Local index:Int = 0 Until _peers.Length
			If _peerUsed[index] And _peers[index].Equals(peer) Then
				For Local entityIndex:Int = 0 Until _entities.Length
					Local relevanceIndex:Int = RelevanceIndex(entityIndex, index)
					_peerVisible[relevanceIndex] = False
					_peerKnown[relevanceIndex] = False
				Next
				_peerUsed[index] = False
				_peerDefaultVisible[index] = False
				_peers[index] = New SNetPeer
				Return True
			End If
		Next
		Return False
	End Method

	Rem
	bbdoc: Reveals or hides @entity for one authority peer.
	returns: Ok after the reliable complete spawn or despawn is queued, or a
	transport failure which #Flush can retry.
	about: Hidden entities continue to exist and may be updated by the authority.
	Revealing one later sends its complete current state with the same stable
	identity. The optional @reason is included in an immediate hide transition.
	End Rem
	Method SetPeerVisible:ETransportResult(entity:TReplicatedEntity, peer:SNetPeer, visible:Int, tick:UInt = 0, reason:Int = 0)
		If _role <> EReplicationRole.Authority Or Not entity Then Return ETransportResult.InvalidPeer
		Local entityIndex:Int = ResolveEntityIndex(entity._identity)
		Local peerIndex:Int = ResolvePeerIndex(peer)
		If entityIndex < 0 Or peerIndex < 0 Then Return ETransportResult.InvalidPeer
		Local relevanceIndex:Int = RelevanceIndex(entityIndex, peerIndex)
		_peerVisible[relevanceIndex] = visible <> 0
		If _peerVisible[relevanceIndex] = _peerKnown[relevanceIndex] Then Return ETransportResult.Ok
		Local sent:ETransportResult
		If visible Then
			sent = SendToPeer(peer, WriteSpawn(entity, tick))
		Else
			sent = SendToPeer(peer, WriteDespawn(entity, tick, reason))
		End If
		If sent = ETransportResult.Ok Then _peerKnown[relevanceIndex] = _peerVisible[relevanceIndex]
		Return sent
	End Method

	Rem
	bbdoc: Returns whether @entity is intended to be visible to @peer.
	End Rem
	Method IsPeerVisible:Int(entity:TReplicatedEntity, peer:SNetPeer)
		If _role <> EReplicationRole.Authority Or Not entity Then Return False
		Local entityIndex:Int = ResolveEntityIndex(entity._identity)
		Local peerIndex:Int = ResolvePeerIndex(peer)
		If entityIndex < 0 Or peerIndex < 0 Then Return False
		Return _peerVisible[RelevanceIndex(entityIndex, peerIndex)] <> 0
	End Method

	Rem
	bbdoc: Selects whether entities spawned later are initially visible to @peer.
	about: Existing entities retain their current visibility. Use #SetPeerVisible
	to alter those explicitly.
	End Rem
	Method SetPeerDefaultVisible:Int(peer:SNetPeer, visible:Int)
		If _role <> EReplicationRole.Authority Then Return False
		Local peerIndex:Int = ResolvePeerIndex(peer)
		If peerIndex < 0 Then Return False
		_peerDefaultVisible[peerIndex] = visible <> 0
		Return True
	End Method

	Rem
	bbdoc: Returns whether entities spawned later default to visible for @peer.
	End Rem
	Method PeerDefaultVisible:Int(peer:SNetPeer)
		If _role <> EReplicationRole.Authority Then Return False
		Local peerIndex:Int = ResolvePeerIndex(peer)
		If peerIndex < 0 Then Return False
		Return _peerDefaultVisible[peerIndex] <> 0
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
			For Local peerIndex:Int = 0 Until _peers.Length
				Local relevanceIndex:Int = RelevanceIndex(index, peerIndex)
				_peerVisible[relevanceIndex] = _peerUsed[peerIndex] And _peerDefaultVisible[peerIndex]
				_peerKnown[relevanceIndex] = False
			Next
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
		_lastFlushPackets = 0
		_lastFlushBytes = 0
		_measuringFlush = True
		Local result:ETransportResult = ETransportResult.Ok

		For Local entityIndex:Int = 0 Until _entities.Length
			_flushUpdate[entityIndex] = False
			_flushFailed[entityIndex] = False
			Local entity:TReplicatedEntity = _entities[entityIndex]
			If Not entity Or Not entity._active Or entity._newlySpawned Then Continue
			Select entity._schema.UpdateMode()
				Case EReplicationUpdateMode.ReliableChanges
					_flushUpdate[entityIndex] = entity.HasDirty()
				Case EReplicationUpdateMode.UnreliableSnapshots
					Local refreshDue:Int = entity._hasSent And UInt(tick - entity._lastSentTick) >= entity._schema.FullRefreshTicks()
					_flushUpdate[entityIndex] = entity.HasDirty() Or refreshDue
			End Select
		Next

		For Local peerIndex:Int = 0 Until _peers.Length
			If Not _peerUsed[peerIndex] Then Continue
			Local sent:ETransportResult = SendUpdateBatches(peerIndex, tick, EDeliveryMode.ReliableOrdered)
			If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
			sent = SendUpdateBatches(peerIndex, tick, EDeliveryMode.Unreliable)
			If result = ETransportResult.Ok And sent <> ETransportResult.Ok Then result = sent
		Next

		For Local entityIndex:Int = 0 Until _entities.Length
			Local entity:TReplicatedEntity = _entities[entityIndex]
			If Not entity Or Not entity._active Then Continue
			Local wasNew:Int = entity._newlySpawned
			If wasNew Or HasPendingVisibility(entityIndex) Then
				Local synchronized:ETransportResult = SynchronizeVisibility(entity, entityIndex, tick)
				If synchronized <> ETransportResult.Ok Then
					_flushFailed[entityIndex] = True
					If result = ETransportResult.Ok Then result = synchronized
				End If
			End If
			If _flushFailed[entityIndex] Then Continue
			If wasNew Then entity._newlySpawned = False
			If wasNew Or _flushUpdate[entityIndex] Then
				entity.ClearDirty()
				entity._lastTick = tick
				entity._lastSentTick = tick
				entity._hasSent = True
			End If
		Next
		_measuringFlush = False
		Return result
	End Method

	Method SetOwner:ETransportResult(entity:TReplicatedEntity, ownerId:UInt, tick:UInt)
		If _role <> EReplicationRole.Authority Or Not entity Then Return ETransportResult.InvalidPeer
		Local entityIndex:Int = ResolveEntityIndex(entity._identity)
		If entityIndex < 0 Then Return ETransportResult.InvalidPeer
		If entity._ownerId = ownerId Then Return ETransportResult.Ok
		entity._ownerId = ownerId
		Local result:ETransportResult = SendToRelevant(entityIndex, WriteOwnership(entity, tick), EDeliveryMode.ReliableOrdered)
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
		Local result:ETransportResult = SendToKnown(index, WriteDespawn(entity, tick, reason))
		If result <> ETransportResult.Ok Then Return result
		For Local peerIndex:Int = 0 Until _peers.Length
			Local relevanceIndex:Int = RelevanceIndex(index, peerIndex)
			_peerVisible[relevanceIndex] = False
			_peerKnown[relevanceIndex] = False
		Next
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
			Case EReplicationPacketKind.UpdateBatch
				Return ReceiveUpdateBatch(reader, tick)
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

	Rem
	bbdoc: Returns the number of successfully queued transport packets in the last #Flush.
	End Rem
	Method LastFlushPackets:Int()
		Return _lastFlushPackets
	End Method

	Rem
	bbdoc: Returns the replication payload bytes successfully queued by the last #Flush.
	End Rem
	Method LastFlushBytes:Size_T()
		Return _lastFlushBytes
	End Method

	Method LastFailure:EReplicationFailure()
		Return _lastFailure
	End Method

	Method Close()
		If _packetBuffer Then MemFree(_packetBuffer)
		If _codecBuffer Then MemFree(_codecBuffer)
		If _updateBuffer Then MemFree(_updateBuffer)
		_packetBuffer = Null
		_codecBuffer = Null
		_updateBuffer = Null
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
