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
bbdoc: Versioned sessions and framed messages above GameNet transports.
End Rem
Module GameNet.Session

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial handshake and application messages"

Import GameNet.Core
Import BRL.Blitz

Rem
bbdoc: Identifies whether a session accepts or initiates peer joins.
End Rem
Enum ESessionRole:Byte
	Host
	Client
End Enum

Rem
bbdoc: Identifies an event returned by #TNetSession.Poll.
End Rem
Enum ESessionEventKind:Byte
	None
	JoinRequested
	Joined
	Rejected
	Left
	Message
	Error
End Enum

Rem
bbdoc: Standard rejection codes sent by the session protocol.
about: Application-defined rejection codes should begin at
#SESSION_REJECT_APPLICATION_BASE.
End Rem
Enum ESessionRejectCode:Int
	MalformedHandshake = 1
	ApplicationMismatch
	VersionMismatch
	ServerFull
	ProtocolViolation
End Enum

Const SESSION_REJECT_APPLICATION_BASE:Int = 1024

Rem
bbdoc: One session lifecycle, application message, or error event.
about: Payload is a borrowed view which remains valid until the next call to
#TNetSession.Poll on the same session.
End Rem
Struct SSessionEvent
	Private
	Field _kind:ESessionEventKind
	Field _peer:SNetPeer
	Field _channel:UInt
	Field _delivery:EDeliveryMode
	Field _messageType:UInt
	Field _payload:SPacketView
	Field _code:Int

	Method New(kind:ESessionEventKind, peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, messageType:UInt, payload:SPacketView, code:Int)
		_kind = kind
		_peer = peer
		_channel = channel
		_delivery = delivery
		_messageType = messageType
		_payload = payload
		_code = code
	End Method

	Public
	Method New()
	End Method

	Function JoinRequested:SSessionEvent(peer:SNetPeer, payload:SPacketView)
		Return New SSessionEvent(ESessionEventKind.JoinRequested, peer, 0, EDeliveryMode.ReliableOrdered, 0, payload, 0)
	End Function

	Function Joined:SSessionEvent(peer:SNetPeer)
		Return New SSessionEvent(ESessionEventKind.Joined, peer, 0, EDeliveryMode.ReliableOrdered, 0, New SPacketView, 0)
	End Function

	Function Joined:SSessionEvent(peer:SNetPeer, payload:SPacketView)
		Return New SSessionEvent(ESessionEventKind.Joined, peer, 0, EDeliveryMode.ReliableOrdered, 0, payload, 0)
	End Function

	Function Rejected:SSessionEvent(peer:SNetPeer, code:Int, payload:SPacketView)
		Return New SSessionEvent(ESessionEventKind.Rejected, peer, 0, EDeliveryMode.ReliableOrdered, 0, payload, code)
	End Function

	Function Left:SSessionEvent(peer:SNetPeer, code:Int)
		Return New SSessionEvent(ESessionEventKind.Left, peer, 0, EDeliveryMode.Unreliable, 0, New SPacketView, code)
	End Function

	Function Message:SSessionEvent(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, messageType:UInt, payload:SPacketView)
		Return New SSessionEvent(ESessionEventKind.Message, peer, channel, delivery, messageType, payload, 0)
	End Function

	Function Error:SSessionEvent(peer:SNetPeer, code:Int)
		Return New SSessionEvent(ESessionEventKind.Error, peer, 0, EDeliveryMode.Unreliable, 0, New SPacketView, code)
	End Function

	Method Kind:ESessionEventKind()
		Return _kind
	End Method

	Method Peer:SNetPeer()
		Return _peer
	End Method

	Method Channel:UInt()
		Return _channel
	End Method

	Method Delivery:EDeliveryMode()
		Return _delivery
	End Method

	Method MessageType:UInt()
		Return _messageType
	End Method

	Method Payload:SPacketView()
		Return _payload
	End Method

	Method Code:Int()
		Return _code
	End Method
End Struct

Private

Const SESSION_MAGIC:UInt = $474e5331:UInt ' GNS1
Const SESSION_WIRE_VERSION:UInt = 1
Const SESSION_BASE_HEADER_SIZE:Size_T = 6
Const SESSION_USER_HEADER_SIZE:Size_T = 8
Const SESSION_HELLO_HEADER_SIZE:Size_T = 14
Const SESSION_REJECT_HEADER_SIZE:Size_T = 10
Const SESSION_DEFAULT_SEND_CAPACITY:Size_T = 64 * 1024

Enum ESessionFrameKind:Byte
	Hello = 1
	Accept
	Reject
	User
End Enum

Enum ESessionPeerPhase:Byte
	Empty
	AwaitingHello
	AwaitingAcceptance
	AwaitingDecision
	Active
	Rejecting
	Rejected
End Enum

Struct SSessionPeerSlot
	Field peer:SNetPeer
	Field phase:ESessionPeerPhase
End Struct

Public

Rem
bbdoc: A versioned game session layered over an #INetTransport.
about: A session owns the transport passed to its factory and closes it when
the session closes. Polling and sending within configured bounds use reusable
storage and do not inherently create managed garbage.
End Rem
Type TNetSession
	Private
	Field _transport:INetTransport
	Field _role:ESessionRole
	Field _applicationId:UInt
	Field _applicationVersion:UInt
	Field _peers:SSessionPeerSlot[]
	Field _localEvents:SSessionEvent[]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _sendBuffer:Byte Ptr
	Field _sendCapacity:Size_T
	Field _helloData:Byte Ptr
	Field _helloLength:Size_T
	Field _open:Int = True

	Method New(transport:INetTransport, role:ESessionRole, applicationId:UInt, applicationVersion:UInt, maxPeers:Int, sendCapacity:Size_T, helloData:Byte Ptr, helloLength:Size_T)
		_transport = transport
		_role = role
		_applicationId = applicationId
		_applicationVersion = applicationVersion
		_peers = New SSessionPeerSlot[maxPeers]
		_localEvents = New SSessionEvent[maxPeers]
		_sendCapacity = sendCapacity
		_sendBuffer = MemAlloc(sendCapacity)
		_helloLength = helloLength
		If helloLength > 0 Then
			_helloData = MemAlloc(helloLength)
			MemCopy(_helloData, helloData, helloLength)
		End If
	End Method

	Method PeerIndex:Int(peer:SNetPeer)
		If Not peer.IsValid() Then Return -1
		For Local index:Int = 0 Until _peers.Length
			If _peers[index].phase <> ESessionPeerPhase.Empty And _peers[index].peer.Equals(peer) Then Return index
		Next
		Return -1
	End Method

	Method RegisterPeer:Int(peer:SNetPeer, phase:ESessionPeerPhase)
		If Not peer.IsValid() Then Return -1
		If PeerIndex(peer) >= 0 Then Return -1
		For Local index:Int = 0 Until _peers.Length
			If _peers[index].phase = ESessionPeerPhase.Empty Then
				_peers[index].peer = peer
				_peers[index].phase = phase
				Return index
			End If
		Next
		Return -1
	End Method

	Method ClearPeer(index:Int)
		_peers[index].peer = New SNetPeer
		_peers[index].phase = ESessionPeerPhase.Empty
	End Method

	Method QueueLocal:Int(event:SSessionEvent)
		If _eventCount = _localEvents.Length Then Return False
		_localEvents[_eventWrite] = event
		_eventWrite :+ 1
		If _eventWrite = _localEvents.Length Then _eventWrite = 0
		_eventCount :+ 1
		Return True
	End Method

	Method PollLocal:Int(event:SSessionEvent Var)
		If _eventCount = 0 Then Return False
		event = _localEvents[_eventRead]
		_eventRead :+ 1
		If _eventRead = _localEvents.Length Then _eventRead = 0
		_eventCount :- 1
		Return True
	End Method

	Method BeginFrame:SPacketWriter(kind:ESessionFrameKind)
		Local writer:SPacketWriter = New SPacketWriter(_sendBuffer, _sendCapacity)
		writer.WriteUInt32(SESSION_MAGIC)
		writer.WriteUInt8(SESSION_WIRE_VERSION)
		writer.WriteUInt8(UInt(kind))
		Return writer
	End Method

	Method SendWriter:ETransportResult(peer:SNetPeer, writer:SPacketWriter, channel:UInt = 0, delivery:EDeliveryMode = EDeliveryMode.ReliableOrdered)
		If writer.Failed() Then Return ETransportResult.PacketTooLarge
		Return _transport.Send(peer, channel, delivery, writer.View().Data(), writer.View().Length())
	End Method

	Method SendHello:ETransportResult(peer:SNetPeer)
		Local writer:SPacketWriter = BeginFrame(ESessionFrameKind.Hello)
		writer.WriteUInt32(_applicationId)
		writer.WriteUInt32(_applicationVersion)
		writer.WriteBytes(_helloData, _helloLength)
		Return SendWriter(peer, writer)
	End Method

	Method SendAccept:ETransportResult(peer:SNetPeer, data:Byte Ptr, length:Size_T)
		Local writer:SPacketWriter = BeginFrame(ESessionFrameKind.Accept)
		writer.WriteBytes(data, length)
		Return SendWriter(peer, writer)
	End Method

	Method SendReject:ETransportResult(peer:SNetPeer, code:Int, data:Byte Ptr = Null, length:Size_T = 0)
		Local writer:SPacketWriter = BeginFrame(ESessionFrameKind.Reject)
		writer.WriteUInt32(UInt(code))
		writer.WriteBytes(data, length)
		Return SendWriter(peer, writer)
	End Method

	Method RejectAndDisconnect(peer:SNetPeer, index:Int, code:Int)
		SendReject(peer, code)
		_peers[index].phase = ESessionPeerPhase.Rejecting
		_transport.Disconnect(peer, code)
	End Method

	Method ProtocolError:Int(peer:SNetPeer, index:Int, event:SSessionEvent Var, code:Int = Int(ESessionRejectCode.ProtocolViolation))
		If index >= 0 Then
			If _role = ESessionRole.Host Then
				RejectAndDisconnect(peer, index, code)
			Else
				_transport.Disconnect(peer, code)
			End If
		Else
			_transport.Disconnect(peer, code)
		End If
		event = SSessionEvent.Error(peer, code)
		Return True
	End Method

	Method HandleConnected:Int(peer:SNetPeer, event:SSessionEvent Var)
		Local phase:ESessionPeerPhase
		If _role = ESessionRole.Host Then
			phase = ESessionPeerPhase.AwaitingHello
		Else
			phase = ESessionPeerPhase.AwaitingAcceptance
		End If

		Local index:Int = RegisterPeer(peer, phase)
		If index < 0 Then
			SendReject(peer, Int(ESessionRejectCode.ServerFull))
			_transport.Disconnect(peer, Int(ESessionRejectCode.ServerFull))
			event = SSessionEvent.Error(peer, Int(ESessionRejectCode.ServerFull))
			Return True
		End If

		If _role = ESessionRole.Client Then
			Local result:ETransportResult = SendHello(peer)
			If result <> ETransportResult.Ok Then
				_transport.Disconnect(peer, Int(result))
				event = SSessionEvent.Error(peer, Int(result))
				Return True
			End If
		End If
		Return False
	End Method

	Method HandleHello:Int(peer:SNetPeer, index:Int, reader:SPacketReader, event:SSessionEvent Var)
		If _role <> ESessionRole.Host Or _peers[index].phase <> ESessionPeerPhase.AwaitingHello Then
			Return ProtocolError(peer, index, event)
		End If

		Local applicationId:UInt
		Local applicationVersion:UInt
		If Not reader.ReadUInt32(applicationId) Or Not reader.ReadUInt32(applicationVersion) Then
			Return ProtocolError(peer, index, event, Int(ESessionRejectCode.MalformedHandshake))
		End If
		If applicationId <> _applicationId Then
			RejectAndDisconnect(peer, index, Int(ESessionRejectCode.ApplicationMismatch))
			Return False
		End If
		If applicationVersion <> _applicationVersion Then
			RejectAndDisconnect(peer, index, Int(ESessionRejectCode.VersionMismatch))
			Return False
		End If

		_peers[index].phase = ESessionPeerPhase.AwaitingDecision
		event = SSessionEvent.JoinRequested(peer, reader.RemainingView())
		Return True
	End Method

	Method HandleData:Int(raw:SNetEvent, event:SSessionEvent Var)
		Local peer:SNetPeer = raw.Peer()
		Local index:Int = PeerIndex(peer)
		If index < 0 Then Return ProtocolError(peer, index, event)

		Local reader:SPacketReader = New SPacketReader(raw.Packet())
		Local magic:UInt
		Local wireVersion:UInt
		Local frameKindValue:UInt
		If Not reader.ReadUInt32(magic) Or Not reader.ReadUInt8(wireVersion) Or Not reader.ReadUInt8(frameKindValue) Then
			Return ProtocolError(peer, index, event)
		End If
		If magic <> SESSION_MAGIC Or wireVersion <> SESSION_WIRE_VERSION Then
			Return ProtocolError(peer, index, event)
		End If

		Local frameKind:ESessionFrameKind = ESessionFrameKind(frameKindValue)
		If frameKind <> ESessionFrameKind.User Then
			If raw.Channel() <> 0 Or raw.Delivery() <> EDeliveryMode.ReliableOrdered Then
				Return ProtocolError(peer, index, event)
			End If
		End If

		Select frameKind
			Case ESessionFrameKind.Hello
				Return HandleHello(peer, index, reader, event)

			Case ESessionFrameKind.Accept
				If _role <> ESessionRole.Client Or _peers[index].phase <> ESessionPeerPhase.AwaitingAcceptance Then
					Return ProtocolError(peer, index, event)
				End If
				_peers[index].phase = ESessionPeerPhase.Active
				event = SSessionEvent.Joined(peer, reader.RemainingView())
				Return True

			Case ESessionFrameKind.Reject
				If _role <> ESessionRole.Client Or _peers[index].phase <> ESessionPeerPhase.AwaitingAcceptance Then
					Return ProtocolError(peer, index, event)
				End If
				Local code:UInt
				If Not reader.ReadUInt32(code) Then Return ProtocolError(peer, index, event)
				_peers[index].phase = ESessionPeerPhase.Rejected
				event = SSessionEvent.Rejected(peer, Int(code), reader.RemainingView())
				Return True

			Case ESessionFrameKind.User
				If _peers[index].phase <> ESessionPeerPhase.Active Then Return ProtocolError(peer, index, event)
				Local messageType:UInt
				If Not reader.ReadUInt16(messageType) Then Return ProtocolError(peer, index, event)
				event = SSessionEvent.Message(peer, raw.Channel(), raw.Delivery(), messageType, reader.RemainingView())
				Return True
		End Select

		Return ProtocolError(peer, index, event)
	End Method

	Method HandleDisconnected:Int(peer:SNetPeer, code:Int, event:SSessionEvent Var)
		Local index:Int = PeerIndex(peer)
		If index < 0 Then Return False
		Local phase:ESessionPeerPhase = _peers[index].phase
		ClearPeer(index)
		If phase = ESessionPeerPhase.Rejecting Or phase = ESessionPeerPhase.Rejected Then Return False
		event = SSessionEvent.Left(peer, code)
		Return True
	End Method

	Function ValidCapacity:Size_T(transport:INetTransport, requested:Size_T)
		Local reliableLimit:Size_T = transport.MaxPacketSize(EDeliveryMode.ReliableOrdered)
		If reliableLimit > 0 And requested > reliableLimit Then requested = reliableLimit
		Return requested
	End Function

	Public
	Rem
	bbdoc: Creates a host session which owns @transport.
	End Rem
	Function CreateHost:TNetSession(transport:INetTransport, applicationId:UInt, applicationVersion:UInt, maxPeers:Int = 32, sendCapacity:Size_T = SESSION_DEFAULT_SEND_CAPACITY)
		If Not transport Or maxPeers < 1 Then Return Null
		sendCapacity = ValidCapacity(transport, sendCapacity)
		If sendCapacity < SESSION_HELLO_HEADER_SIZE Then Return Null
		Return New TNetSession(transport, ESessionRole.Host, applicationId, applicationVersion, maxPeers, sendCapacity, Null, 0)
	End Function

	Rem
	bbdoc: Creates a client session which owns @transport and sends optional opaque hello data.
	End Rem
	Function CreateClient:TNetSession(transport:INetTransport, applicationId:UInt, applicationVersion:UInt, helloData:Byte Ptr = Null, helloLength:Size_T = 0, maxPeers:Int = 1, sendCapacity:Size_T = SESSION_DEFAULT_SEND_CAPACITY)
		If Not transport Or maxPeers < 1 Then Return Null
		If helloLength > 0 And Not helloData Then Return Null
		sendCapacity = ValidCapacity(transport, sendCapacity)
		If sendCapacity < SESSION_HELLO_HEADER_SIZE Or helloLength > sendCapacity - SESSION_HELLO_HEADER_SIZE Then Return Null
		Return New TNetSession(transport, ESessionRole.Client, applicationId, applicationVersion, maxPeers, sendCapacity, helloData, helloLength)
	End Function

	Rem
	bbdoc: Returns the host or client role of this session.
	End Rem
	Method Role:ESessionRole()
		Return _role
	End Method

	Rem
	bbdoc: Accepts a pending host-side join and optionally returns opaque data to the client.
	End Rem
	Method Accept:ETransportResult(peer:SNetPeer, data:Byte Ptr = Null, length:Size_T = 0)
		If Not _open Then Return ETransportResult.Closed
		If _role <> ESessionRole.Host Then Return ETransportResult.Failed
		If length > 0 And Not data Then Return ETransportResult.Failed
		Local index:Int = PeerIndex(peer)
		If index < 0 Or _peers[index].phase <> ESessionPeerPhase.AwaitingDecision Then Return ETransportResult.InvalidPeer
		If _eventCount = _localEvents.Length Then Return ETransportResult.WouldBlock
		Local result:ETransportResult = SendAccept(peer, data, length)
		If result <> ETransportResult.Ok Then Return result
		_peers[index].phase = ESessionPeerPhase.Active
		QueueLocal(SSessionEvent.Joined(peer))
		Return ETransportResult.Ok
	End Method

	Rem
	bbdoc: Rejects a pending host-side join with an application code and optional data.
	End Rem
	Method Reject:ETransportResult(peer:SNetPeer, code:Int, data:Byte Ptr = Null, length:Size_T = 0)
		If Not _open Then Return ETransportResult.Closed
		If _role <> ESessionRole.Host Then Return ETransportResult.Failed
		If length > 0 And Not data Then Return ETransportResult.Failed
		Local index:Int = PeerIndex(peer)
		If index < 0 Or _peers[index].phase <> ESessionPeerPhase.AwaitingDecision Then Return ETransportResult.InvalidPeer
		Local result:ETransportResult = SendReject(peer, code, data, length)
		If result <> ETransportResult.Ok Then Return result
		_peers[index].phase = ESessionPeerPhase.Rejecting
		_transport.Disconnect(peer, code)
		Return ETransportResult.Ok
	End Method

	Rem
	bbdoc: Sends one framed application message to an active peer.
	End Rem
	Method Send:ETransportResult(peer:SNetPeer, messageType:UInt, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr = Null, length:Size_T = 0)
		If Not _open Then Return ETransportResult.Closed
		If messageType > 65535 Then Return ETransportResult.Failed
		If length > 0 And Not data Then Return ETransportResult.Failed
		Local index:Int = PeerIndex(peer)
		If index < 0 Or _peers[index].phase <> ESessionPeerPhase.Active Then Return ETransportResult.InvalidPeer
		Local writer:SPacketWriter = BeginFrame(ESessionFrameKind.User)
		writer.WriteUInt16(messageType)
		writer.WriteBytes(data, length)
		Return SendWriter(peer, writer, channel, delivery)
	End Method

	Rem
	bbdoc: Returns the maximum application payload accepted for @delivery.
	End Rem
	Method MaxPayloadSize:Size_T(delivery:EDeliveryMode)
		Local limit:Size_T = _transport.MaxPacketSize(delivery)
		If limit = 0 Or limit > _sendCapacity Then limit = _sendCapacity
		If limit <= SESSION_USER_HEADER_SIZE Then Return 0
		Return limit - SESSION_USER_HEADER_SIZE
	End Method

	Rem
	bbdoc: Writes the next session event and returns True, or returns False when idle.
	End Rem
	Method Poll:Int(event:SSessionEvent Var)
		If PollLocal(event) Then Return True
		If Not _open Then
			event = New SSessionEvent
			Return False
		End If

		Repeat
			Local raw:SNetEvent
			If Not _transport.Poll(raw) Then
				event = New SSessionEvent
				Return False
			End If
			Select raw.Kind()
				Case ENetEventKind.Connected
					If HandleConnected(raw.Peer(), event) Then Return True
				Case ENetEventKind.Disconnected
					If HandleDisconnected(raw.Peer(), raw.Code(), event) Then Return True
				Case ENetEventKind.Data
					If HandleData(raw, event) Then Return True
				Case ENetEventKind.Error
					event = SSessionEvent.Error(raw.Peer(), raw.Code())
					Return True
			End Select
		Forever
	End Method

	Method IsOpen:Int()
		Return _open And _transport And _transport.IsOpen()
	End Method

	Method Close()
		If Not _open Then Return
		_open = False
		If _transport Then _transport.Close()
		If _sendBuffer Then MemFree(_sendBuffer)
		If _helloData Then MemFree(_helloData)
		_sendBuffer = Null
		_helloData = Null
	End Method

	Method Delete()
		Close()
	End Method
End Type
