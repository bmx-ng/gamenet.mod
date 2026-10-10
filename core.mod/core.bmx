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
bbdoc: Transport-independent game networking primitives.
End Rem
Module GameNet.Core

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial transport contract and packet codecs"

Import BRL.Blitz

Rem
bbdoc: Conservative packet size which avoids IP fragmentation on common Internet paths.
about: This is guidance rather than a transport limit. Applications must still
query #INetTransport.MaxPacketSize and account for protocol headers.
End Rem
Const GAMENET_RECOMMENDED_INTERNET_PACKET_SIZE:Size_T = 1200

Rem
bbdoc: Reports storage reserved by a bounded GameNet configuration before it is created.
about: NativeBytes covers MemAlloc-backed payload buffers. ManagedArrayBytes
covers array element storage, but deliberately excludes runtime-specific object
and array headers. TotalPayloadBytes is therefore suitable for comparing
configurations, not as an exact process-memory measurement.
End Rem
Struct SNetMemoryRequirements
	Private
	Field _nativeBytes:Size_T
	Field _managedArrayBytes:Size_T

	Public
	Method New()
	End Method

	Method New(nativeBytes:Size_T, managedArrayBytes:Size_T)
		_nativeBytes = nativeBytes
		_managedArrayBytes = managedArrayBytes
	End Method

	Method NativeBytes:Size_T()
		Return _nativeBytes
	End Method

	Method ManagedArrayBytes:Size_T()
		Return _managedArrayBytes
	End Method

	Method TotalPayloadBytes:Size_T()
		Return _nativeBytes + _managedArrayBytes
	End Method
End Struct

Rem
bbdoc: Safely adds @count elements of @elementSize to a byte total.
returns: False when the multiplication or addition would overflow Size_T.
End Rem
Function NetAccumulateSize:Int(total:Size_T Var, count:Size_T, elementSize:Size_T)
	Local maximum:Size_T = Size_T(-1)
	If count > 0 And elementSize > maximum / count Then Return False
	Local amount:Size_T = count * elementSize
	If amount > maximum - total Then Return False
	total :+ amount
	Return True
End Function

Rem
bbdoc: Specifies the delivery guarantees requested for a game message.
End Rem
Enum EDeliveryMode:Byte
	Unreliable
	UnreliableSequenced
	ReliableOrdered
End Enum

Rem
bbdoc: Identifies an event returned by #INetTransport.Poll.
End Rem
Enum ENetEventKind:Byte
	None
	Connected
	Disconnected
	Data
	Error
End Enum

Rem
bbdoc: Reports the immediate result of a transport operation.
End Rem
Enum ETransportResult:Byte
	Ok
	WouldBlock
	InvalidPeer
	InvalidChannel
	PacketTooLarge
	Closed
	Failed
End Enum

Rem
bbdoc: A transport-local handle for one remote peer.
about: A default SNetPeer is invalid. The generation prevents a stale handle
from identifying a newly connected peer which reuses the same numeric id.
End Rem
Struct SNetPeer
	Private
	Field _id:UInt
	Field _generation:UInt

	Public
	Rem
	bbdoc: Creates an invalid peer handle.
	End Rem
	Method New()
	End Method

	Rem
	bbdoc: Creates a peer handle from a transport-local id and generation.
	End Rem
	Method New(id:UInt, generation:UInt)
		_id = id
		_generation = generation
	End Method

	Rem
	bbdoc: Returns the transport-local numeric peer id.
	End Rem
	Method Id:UInt()
		Return _id
	End Method

	Rem
	bbdoc: Returns the generation associated with this peer id.
	End Rem
	Method Generation:UInt()
		Return _generation
	End Method

	Rem
	bbdoc: Returns True when this handle can identify a peer.
	End Rem
	Method IsValid:Int()
		Return _id <> 0 And _generation <> 0
	End Method

	Rem
	bbdoc: Returns True when @other identifies the same peer generation.
	End Rem
	Method Equals:Int(other:SNetPeer)
		Return _id = other._id And _generation = other._generation
	End Method
End Struct

Rem
bbdoc: A non-owning view of contiguous packet bytes.
about: A transport event's packet view remains valid until the next call to
#INetTransport.Poll on that transport. Copy bytes which must be retained.
End Rem
Struct SPacketView
	Private
	Field _data:Byte Ptr
	Field _length:Size_T

	Public
	Rem
	bbdoc: Creates an empty packet view.
	End Rem
	Method New()
	End Method

	Rem
	bbdoc: Creates a view over @length bytes beginning at @data.
	End Rem
	Method New(data:Byte Ptr, length:Size_T)
		_data = data
		_length = length
	End Method

	Rem
	bbdoc: Returns the address of the first viewed byte, or Null when empty.
	End Rem
	Method Data:Byte Ptr()
		Return _data
	End Method

	Rem
	bbdoc: Returns the number of viewed bytes.
	End Rem
	Method Length:Size_T()
		Return _length
	End Method

	Rem
	bbdoc: Returns True when the view contains no bytes.
	End Rem
	Method IsEmpty:Int()
		Return _length = 0
	End Method
End Struct

Rem
bbdoc: One connection, disconnection, data, or transport error event.
End Rem
Struct SNetEvent
	Private
	Field _kind:ENetEventKind
	Field _peer:SNetPeer
	Field _channel:UInt
	Field _delivery:EDeliveryMode
	Field _packet:SPacketView
	Field _code:Int

	Method New(kind:ENetEventKind, peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, packet:SPacketView, code:Int)
		_kind = kind
		_peer = peer
		_channel = channel
		_delivery = delivery
		_packet = packet
		_code = code
	End Method

	Public
	Rem
	bbdoc: Creates an empty event.
	End Rem
	Method New()
	End Method

	Rem
	bbdoc: Creates a connected event for @peer.
	End Rem
	Function Connected:SNetEvent(peer:SNetPeer)
		Return New SNetEvent(ENetEventKind.Connected, peer, 0, EDeliveryMode.Unreliable, New SPacketView, 0)
	End Function

	Rem
	bbdoc: Creates a disconnected event for @peer with an optional application @code.
	End Rem
	Function Disconnected:SNetEvent(peer:SNetPeer, code:Int = 0)
		Return New SNetEvent(ENetEventKind.Disconnected, peer, 0, EDeliveryMode.Unreliable, New SPacketView, code)
	End Function

	Rem
	bbdoc: Creates a data event.
	End Rem
	Function Data:SNetEvent(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, packet:SPacketView)
		Return New SNetEvent(ENetEventKind.Data, peer, channel, delivery, packet, 0)
	End Function

	Rem
	bbdoc: Creates a transport error event with a backend-defined @code.
	End Rem
	Function Error:SNetEvent(peer:SNetPeer, code:Int)
		Return New SNetEvent(ENetEventKind.Error, peer, 0, EDeliveryMode.Unreliable, New SPacketView, code)
	End Function

	Rem
	bbdoc: Returns the kind of event.
	End Rem
	Method Kind:ENetEventKind()
		Return _kind
	End Method

	Rem
	bbdoc: Returns the peer associated with the event, if any.
	End Rem
	Method Peer:SNetPeer()
		Return _peer
	End Method

	Rem
	bbdoc: Returns the logical channel carrying a data event.
	End Rem
	Method Channel:UInt()
		Return _channel
	End Method

	Rem
	bbdoc: Returns the delivery mode of a data event.
	End Rem
	Method Delivery:EDeliveryMode()
		Return _delivery
	End Method

	Rem
	bbdoc: Returns the packet carried by a data event.
	End Rem
	Method Packet:SPacketView()
		Return _packet
	End Method

	Rem
	bbdoc: Returns an application disconnect code or backend-defined error code.
	End Rem
	Method Code:Int()
		Return _code
	End Method
End Struct

Rem
bbdoc: A backend which exchanges game messages with remote peers.
about: Poll writes into a caller-owned value and does not require a managed
allocation. Backend-specific modules are responsible for creating and
configuring transports. Packet views returned by Poll remain valid until the
next Poll call on the same transport.
End Rem
Interface INetTransport
	Rem
	bbdoc: Writes the next available event and returns True, or returns False when idle.
	End Rem
	Method Poll:Int(event:SNetEvent Var)

	Rem
	bbdoc: Sends one message to @peer on a logical @channel.
	End Rem
	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T)

	Rem
	bbdoc: Begins disconnecting @peer with an optional application @code.
	End Rem
	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0)

	Rem
	bbdoc: Returns the maximum accepted message length for @delivery, or zero if unknown.
	End Rem
	Method MaxPacketSize:Size_T(delivery:EDeliveryMode)

	Rem
	bbdoc: Returns True while the transport can be polled or used to send.
	End Rem
	Method IsOpen:Int()

	Rem
	bbdoc: Stops the transport and releases its backend resources.
	End Rem
	Method Close()
End Interface

Rem
bbdoc: A bounded, non-owning writer for a caller-supplied packet buffer.
about: Multi-byte values use network byte order. Once a write fails, Failed
remains True and Position remains at the last successfully written byte.
End Rem
Struct SPacketWriter
	Private
	Field _data:Byte Ptr
	Field _capacity:Size_T
	Field _position:Size_T
	Field _failed:Int

	Method Reserve:Int(length:Size_T)
		If _failed Then Return False
		If _position > _capacity Or length > _capacity - _position Then
			_failed = True
			Return False
		End If
		If length > 0 And Not _data Then
			_failed = True
			Return False
		End If
		Return True
	End Method

	Public
	Rem
	bbdoc: Creates an empty writer which cannot accept data.
	End Rem
	Method New()
	End Method

	Rem
	bbdoc: Creates a writer over @capacity bytes beginning at @data.
	End Rem
	Method New(data:Byte Ptr, capacity:Size_T)
		_data = data
		_capacity = capacity
	End Method

	Rem
	bbdoc: Returns the number of successfully written bytes.
	End Rem
	Method Position:Size_T()
		Return _position
	End Method

	Rem
	bbdoc: Returns the number of bytes which can still be written.
	End Rem
	Method Remaining:Size_T()
		If _position > _capacity Then Return 0
		Return _capacity - _position
	End Method

	Rem
	bbdoc: Returns True after any write exceeds the buffer or uses a Null source.
	End Rem
	Method Failed:Int()
		Return _failed
	End Method

	Rem
	bbdoc: Returns a view of the successfully written prefix.
	End Rem
	Method View:SPacketView()
		Return New SPacketView(_data, _position)
	End Method

	Rem
	bbdoc: Writes the low eight bits of @value.
	End Rem
	Method WriteUInt8:Int(value:UInt)
		If Not Reserve(1) Then Return False
		_data[_position] = Byte(value)
		_position :+ 1
		Return True
	End Method

	Rem
	bbdoc: Writes the low sixteen bits of @value in network byte order.
	End Rem
	Method WriteUInt16:Int(value:UInt)
		If Not Reserve(2) Then Return False
		_data[_position] = Byte(value Shr 8)
		_data[_position + 1] = Byte(value)
		_position :+ 2
		Return True
	End Method

	Rem
	bbdoc: Writes @value in network byte order.
	End Rem
	Method WriteUInt32:Int(value:UInt)
		If Not Reserve(4) Then Return False
		_data[_position] = Byte(value Shr 24)
		_data[_position + 1] = Byte(value Shr 16)
		_data[_position + 2] = Byte(value Shr 8)
		_data[_position + 3] = Byte(value)
		_position :+ 4
		Return True
	End Method

	Rem
	bbdoc: Writes @value in network byte order.
	End Rem
	Method WriteUInt64:Int(value:ULong)
		If Not Reserve(8) Then Return False
		For Local index:Int = 0 Until 8
			_data[_position + Size_T(index)] = Byte(value Shr UInt(56 - index * 8))
		Next
		_position :+ 8
		Return True
	End Method

	Rem
	bbdoc: Writes the bit representation of @value in network byte order.
	End Rem
	Method WriteFloat32:Int(value:Float)
		Return WriteUInt32((UInt Ptr Varptr value)[0])
	End Method

	Rem
	bbdoc: Copies @length bytes from @source.
	End Rem
	Method WriteBytes:Int(source:Byte Ptr, length:Size_T)
		If Not Reserve(length) Then Return False
		If length > 0 Then MemCopy(_data + _position, source, length)
		_position :+ length
		Return True
	End Method
End Struct

Rem
bbdoc: A bounded, non-owning reader over packet bytes.
about: Multi-byte values use network byte order. Once a read fails, Failed
remains True and Position remains at the last successfully read byte.
End Rem
Struct SPacketReader
	Private
	Field _data:Byte Ptr
	Field _length:Size_T
	Field _position:Size_T
	Field _failed:Int

	Method Reserve:Int(length:Size_T)
		If _failed Then Return False
		If _position > _length Or length > _length - _position Then
			_failed = True
			Return False
		End If
		If length > 0 And Not _data Then
			_failed = True
			Return False
		End If
		Return True
	End Method

	Public
	Rem
	bbdoc: Creates an empty reader.
	End Rem
	Method New()
	End Method

	Rem
	bbdoc: Creates a reader over @length bytes beginning at @data.
	End Rem
	Method New(data:Byte Ptr, length:Size_T)
		_data = data
		_length = length
	End Method

	Rem
	bbdoc: Creates a reader over @packet.
	End Rem
	Method New(packet:SPacketView)
		_data = packet.Data()
		_length = packet.Length()
	End Method

	Rem
	bbdoc: Returns the current read offset.
	End Rem
	Method Position:Size_T()
		Return _position
	End Method

	Rem
	bbdoc: Returns the number of unread bytes.
	End Rem
	Method Remaining:Size_T()
		If _position > _length Then Return 0
		Return _length - _position
	End Method

	Rem
	bbdoc: Returns a borrowed view of all unread bytes.
	End Rem
	Method RemainingView:SPacketView()
		Local data:Byte Ptr
		If _data Then data = _data + _position
		Return New SPacketView(data, Remaining())
	End Method

	Rem
	bbdoc: Returns True after a read exceeds the packet or uses a Null destination.
	End Rem
	Method Failed:Int()
		Return _failed
	End Method

	Rem
	bbdoc: Reads one unsigned byte into @value.
	End Rem
	Method ReadUInt8:Int(value:UInt Var)
		If Not Reserve(1) Then Return False
		value = UInt(_data[_position]) & $ff:UInt
		_position :+ 1
		Return True
	End Method

	Rem
	bbdoc: Reads one network-order unsigned sixteen-bit value into @value.
	End Rem
	Method ReadUInt16:Int(value:UInt Var)
		If Not Reserve(2) Then Return False
		value = (UInt(_data[_position]) & $ff:UInt) Shl 8
		value :| UInt(_data[_position + 1]) & $ff:UInt
		_position :+ 2
		Return True
	End Method

	Rem
	bbdoc: Reads one network-order unsigned thirty-two-bit value into @value.
	End Rem
	Method ReadUInt32:Int(value:UInt Var)
		If Not Reserve(4) Then Return False
		value = (UInt(_data[_position]) & $ff:UInt) Shl 24
		value :| (UInt(_data[_position + 1]) & $ff:UInt) Shl 16
		value :| (UInt(_data[_position + 2]) & $ff:UInt) Shl 8
		value :| UInt(_data[_position + 3]) & $ff:UInt
		_position :+ 4
		Return True
	End Method

	Rem
	bbdoc: Reads one network-order unsigned sixty-four-bit value into @value.
	End Rem
	Method ReadUInt64:Int(value:ULong Var)
		If Not Reserve(8) Then Return False
		value = 0
		For Local index:Int = 0 Until 8
			value :| (ULong(_data[_position + Size_T(index)]) & $ff:ULong) Shl UInt(56 - index * 8)
		Next
		_position :+ 8
		Return True
	End Method

	Rem
	bbdoc: Reads one network-order Float bit representation into @value.
	End Rem
	Method ReadFloat32:Int(value:Float Var)
		Local bits:UInt
		If Not ReadUInt32(bits) Then Return False
		value = (Float Ptr Varptr bits)[0]
		Return True
	End Method

	Rem
	bbdoc: Copies @length bytes into @destination.
	End Rem
	Method ReadBytes:Int(destination:Byte Ptr, length:Size_T)
		If Not Reserve(length) Then Return False
		If length > 0 And Not destination Then
			_failed = True
			Return False
		End If
		If length > 0 Then MemCopy(destination, _data + _position, length)
		_position :+ length
		Return True
	End Method

	Rem
	bbdoc: Advances by @length bytes without copying them.
	End Rem
	Method Skip:Int(length:Size_T)
		If Not Reserve(length) Then Return False
		_position :+ length
		Return True
	End Method
End Struct
