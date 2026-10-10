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

Rem
bbdoc: Identifies the local validation which most recently rejected a session frame.
about: This diagnostic is not sent on the wire and does not replace the stable
#ESessionRejectCode returned by session events.
End Rem
Enum ESessionProtocolError:Int
	None
	UnknownPeer
	MalformedHeader
	HeaderMismatch
	DeliveryMismatch
	UnexpectedHello
	MalformedHello
	UnexpectedAccept
	UnexpectedReject
	MalformedReject
	UserBeforeActive
	MalformedUser
	ProbeBeforeActive
	MalformedProbe
	ProbeReplyBeforeActive
	MalformedProbeReply
	UnknownFrameKind
End Enum

Const SESSION_REJECT_APPLICATION_BASE:Int = 1024

Rem
bbdoc: Session-owned disconnect reasons produced by connection health policy.
End Rem
Enum ESessionDisconnectCode:Int
	HandshakeTimeout = 1
	IdleTimeout
End Enum

Rem
bbdoc: Optional timeout and active connection probe policy.
about: Zero disables the corresponding feature. Probe loss measures GameNet
health probes, not arbitrary application packets.
End Rem
Struct SSessionHealthConfig
	Field handshakeTimeoutMillis:UInt
	Field idleTimeoutMillis:UInt
	Field probeIntervalMillis:UInt
	Field probeTimeoutMillis:UInt

	Method New(handshakeTimeoutMillis:UInt = 0, idleTimeoutMillis:UInt = 0, probeIntervalMillis:UInt = 0, probeTimeoutMillis:UInt = 0)
		Self.handshakeTimeoutMillis = handshakeTimeoutMillis
		Self.idleTimeoutMillis = idleTimeoutMillis
		Self.probeIntervalMillis = probeIntervalMillis
		Self.probeTimeoutMillis = probeTimeoutMillis
	End Method
End Struct

Rem
bbdoc: An allocation-free snapshot of one session peer's connection health.
End Rem
Struct SSessionPeerHealth
	Private
	Field _active:Int
	Field _idleMillis:UInt
	Field _hasRoundTrip:Int
	Field _roundTripMillis:UInt
	Field _jitterMillis:UInt
	Field _probesSent:UInt
	Field _probesReceived:UInt
	Field _probesLost:UInt
	Field _framesSent:ULong
	Field _framesReceived:ULong
	Field _bytesSent:ULong
	Field _bytesReceived:ULong

	Method New(active:Int, idleMillis:UInt, hasRoundTrip:Int, roundTripMillis:UInt, jitterMillis:UInt, probesSent:UInt, probesReceived:UInt, probesLost:UInt, framesSent:ULong, framesReceived:ULong, bytesSent:ULong, bytesReceived:ULong)
		_active = active
		_idleMillis = idleMillis
		_hasRoundTrip = hasRoundTrip
		_roundTripMillis = roundTripMillis
		_jitterMillis = jitterMillis
		_probesSent = probesSent
		_probesReceived = probesReceived
		_probesLost = probesLost
		_framesSent = framesSent
		_framesReceived = framesReceived
		_bytesSent = bytesSent
		_bytesReceived = bytesReceived
	End Method

	Public
	Method New()
	End Method

	Method IsActive:Int()
		Return _active
	End Method

	Method IdleMillis:UInt()
		Return _idleMillis
	End Method

	Method HasRoundTrip:Int()
		Return _hasRoundTrip
	End Method

	Method RoundTripMillis:UInt()
		Return _roundTripMillis
	End Method

	Method JitterMillis:UInt()
		Return _jitterMillis
	End Method

	Method ProbesSent:UInt()
		Return _probesSent
	End Method

	Method ProbesReceived:UInt()
		Return _probesReceived
	End Method

	Method ProbesLost:UInt()
		Return _probesLost
	End Method

	Method FramesSent:ULong()
		Return _framesSent
	End Method

	Method FramesReceived:ULong()
		Return _framesReceived
	End Method

	Method BytesSent:ULong()
		Return _bytesSent
	End Method

	Method BytesReceived:ULong()
		Return _bytesReceived
	End Method
End Struct

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
	Probe
	ProbeReply
End Enum

Enum ESessionPeerPhase:Byte
	Empty
	AwaitingHello
	AwaitingAcceptance
	AwaitingDecision
	Active
	Rejecting
	Rejected
	Disconnecting
End Enum

Struct SSessionPeerSlot
	Field peer:SNetPeer
	Field phase:ESessionPeerPhase
	Field connectedAt:UInt
	Field lastReceiveAt:UInt
	Field lastProbeAt:UInt
	Field probeToken:UInt
	Field probeSentAt:UInt
	Field probeOutstanding:Int
	Field probesSent:UInt
	Field probesReceived:UInt
	Field probesLost:UInt
	Field hasRoundTrip:Int
	Field roundTripMillis:UInt
	Field jitterMillis:UInt
	Field framesSent:ULong
	Field framesReceived:ULong
	Field bytesSent:ULong
	Field bytesReceived:ULong
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
	Field _healthConfig:SSessionHealthConfig
	Field _nowMillis:UInt
	Field _open:Int = True
	Field _lastProtocolError:ESessionProtocolError

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
				_peers[index].connectedAt = _nowMillis
				_peers[index].lastReceiveAt = _nowMillis
				_peers[index].lastProbeAt = _nowMillis
				Return index
			End If
		Next
		Return -1
	End Method

	Method ClearPeer(index:Int)
		_peers[index] = New SSessionPeerSlot
	End Method

	Function ElapsedMillis:UInt(nowMillis:UInt, thenMillis:UInt)
		Return nowMillis - thenMillis
	End Function

	Function AbsoluteDelta:UInt(first:UInt, second:UInt)
		If first >= second Then Return first - second
		Return second - first
	End Function

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
		Local result:ETransportResult = _transport.Send(peer, channel, delivery, writer.View().Data(), writer.View().Length())
		If result = ETransportResult.Ok Then
			Local index:Int = PeerIndex(peer)
			If index >= 0 Then
				_peers[index].framesSent :+ 1
				_peers[index].bytesSent :+ ULong(writer.View().Length())
			End If
		End If
		Return result
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

	Method SendProbe:ETransportResult(index:Int)
		Local writer:SPacketWriter = BeginFrame(ESessionFrameKind.Probe)
		_peers[index].probeToken :+ 1
		writer.WriteUInt32(_peers[index].probeToken)
		Local result:ETransportResult = SendWriter(_peers[index].peer, writer, 0, EDeliveryMode.Unreliable)
		If result = ETransportResult.Ok Then
			_peers[index].lastProbeAt = _nowMillis
			_peers[index].probeSentAt = _nowMillis
			_peers[index].probeOutstanding = True
			_peers[index].probesSent :+ 1
		End If
		Return result
	End Method

	Method SendProbeReply:ETransportResult(index:Int, token:UInt)
		Local writer:SPacketWriter = BeginFrame(ESessionFrameKind.ProbeReply)
		writer.WriteUInt32(token)
		Return SendWriter(_peers[index].peer, writer, 0, EDeliveryMode.Unreliable)
	End Method

	Method MaintainHealth:Int()
		For Local index:Int = 0 Until _peers.Length
			Local phase:ESessionPeerPhase = _peers[index].phase
			If phase = ESessionPeerPhase.Empty Or phase = ESessionPeerPhase.Rejecting Or phase = ESessionPeerPhase.Rejected Or phase = ESessionPeerPhase.Disconnecting Then Continue

			If phase <> ESessionPeerPhase.Active Then
				If _healthConfig.handshakeTimeoutMillis > 0 And ElapsedMillis(_nowMillis, _peers[index].connectedAt) >= _healthConfig.handshakeTimeoutMillis Then
					If _transport.Disconnect(_peers[index].peer, Int(ESessionDisconnectCode.HandshakeTimeout)) = ETransportResult.Ok Then
						_peers[index].phase = ESessionPeerPhase.Disconnecting
						Return True
					End If
				End If
				Continue
			End If

			If _healthConfig.idleTimeoutMillis > 0 And ElapsedMillis(_nowMillis, _peers[index].lastReceiveAt) >= _healthConfig.idleTimeoutMillis Then
				If _transport.Disconnect(_peers[index].peer, Int(ESessionDisconnectCode.IdleTimeout)) = ETransportResult.Ok Then
					_peers[index].phase = ESessionPeerPhase.Disconnecting
					Return True
				End If
				Continue
			End If

			If _healthConfig.probeIntervalMillis > 0 Then
				If _peers[index].probeOutstanding And ElapsedMillis(_nowMillis, _peers[index].probeSentAt) >= _healthConfig.probeTimeoutMillis Then
					_peers[index].probeOutstanding = False
					_peers[index].probesLost :+ 1
				End If
				If Not _peers[index].probeOutstanding And ElapsedMillis(_nowMillis, _peers[index].lastProbeAt) >= _healthConfig.probeIntervalMillis Then SendProbe(index)
			End If
		Next
		Return False
	End Method

	Method RejectAndDisconnect(peer:SNetPeer, index:Int, code:Int)
		SendReject(peer, code)
		_peers[index].phase = ESessionPeerPhase.Rejecting
		_transport.Disconnect(peer, code)
	End Method

	Method ProtocolError:Int(peer:SNetPeer, index:Int, event:SSessionEvent Var, code:Int = Int(ESessionRejectCode.ProtocolViolation), detail:ESessionProtocolError = ESessionProtocolError.UnknownFrameKind)
		_lastProtocolError = detail
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
			Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.UnexpectedHello)
		End If

		Local applicationId:UInt
		Local applicationVersion:UInt
		If Not reader.ReadUInt32(applicationId) Or Not reader.ReadUInt32(applicationVersion) Then
			Return ProtocolError(peer, index, event, Int(ESessionRejectCode.MalformedHandshake), ESessionProtocolError.MalformedHello)
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
		If index < 0 Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.UnknownPeer)
		_peers[index].lastReceiveAt = _nowMillis
		_peers[index].framesReceived :+ 1
		_peers[index].bytesReceived :+ ULong(raw.Packet().Length())

		Local reader:SPacketReader = New SPacketReader(raw.Packet())
		Local magic:UInt
		Local wireVersion:UInt
		Local frameKindValue:UInt
		If Not reader.ReadUInt32(magic) Or Not reader.ReadUInt8(wireVersion) Or Not reader.ReadUInt8(frameKindValue) Then
			Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.MalformedHeader)
		End If
		If magic <> SESSION_MAGIC Or wireVersion <> SESSION_WIRE_VERSION Then
			Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.HeaderMismatch)
		End If

		Local frameKind:ESessionFrameKind = ESessionFrameKind(frameKindValue)
		If frameKind = ESessionFrameKind.Probe Or frameKind = ESessionFrameKind.ProbeReply Then
			If raw.Channel() <> 0 Or raw.Delivery() <> EDeliveryMode.Unreliable Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.DeliveryMismatch)
		Else If frameKind <> ESessionFrameKind.User Then
			If raw.Channel() <> 0 Or raw.Delivery() <> EDeliveryMode.ReliableOrdered Then
				Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.DeliveryMismatch)
			End If
		End If

		Select frameKind
			Case ESessionFrameKind.Hello
				Return HandleHello(peer, index, reader, event)

			Case ESessionFrameKind.Accept
				If _role <> ESessionRole.Client Or _peers[index].phase <> ESessionPeerPhase.AwaitingAcceptance Then
					Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.UnexpectedAccept)
				End If
				_peers[index].phase = ESessionPeerPhase.Active
				event = SSessionEvent.Joined(peer, reader.RemainingView())
				Return True

			Case ESessionFrameKind.Reject
				If _role <> ESessionRole.Client Or _peers[index].phase <> ESessionPeerPhase.AwaitingAcceptance Then
					Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.UnexpectedReject)
				End If
				Local code:UInt
				If Not reader.ReadUInt32(code) Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.MalformedReject)
				_peers[index].phase = ESessionPeerPhase.Rejected
				event = SSessionEvent.Rejected(peer, Int(code), reader.RemainingView())
				Return True

			Case ESessionFrameKind.User
				If _peers[index].phase <> ESessionPeerPhase.Active Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.UserBeforeActive)
				Local messageType:UInt
				If Not reader.ReadUInt16(messageType) Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.MalformedUser)
				event = SSessionEvent.Message(peer, raw.Channel(), raw.Delivery(), messageType, reader.RemainingView())
				Return True

			Case ESessionFrameKind.Probe
				If _peers[index].phase <> ESessionPeerPhase.Active Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.ProbeBeforeActive)
				Local token:UInt
				If Not reader.ReadUInt32(token) Or reader.Remaining() <> 0 Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.MalformedProbe)
				SendProbeReply(index, token)
				Return False

			Case ESessionFrameKind.ProbeReply
				If _peers[index].phase <> ESessionPeerPhase.Active Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.ProbeReplyBeforeActive)
				Local token:UInt
				If Not reader.ReadUInt32(token) Or reader.Remaining() <> 0 Then Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.MalformedProbeReply)
				If _peers[index].probeOutstanding And token = _peers[index].probeToken Then
					Local sample:UInt = ElapsedMillis(_nowMillis, _peers[index].probeSentAt)
					If _peers[index].hasRoundTrip Then
						Local delta:UInt = AbsoluteDelta(sample, _peers[index].roundTripMillis)
						_peers[index].jitterMillis = (_peers[index].jitterMillis * 3 + delta) / 4
						_peers[index].roundTripMillis = (_peers[index].roundTripMillis * 7 + sample) / 8
					Else
						_peers[index].roundTripMillis = sample
						_peers[index].jitterMillis = 0
						_peers[index].hasRoundTrip = True
					End If
					_peers[index].probeOutstanding = False
					_peers[index].probesReceived :+ 1
				End If
				Return False
		End Select

		Return ProtocolError(peer, index, event, Int(ESessionRejectCode.ProtocolViolation), ESessionProtocolError.UnknownFrameKind)
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
	bbdoc: Configures connection health before any peer has been registered.
	returns: False for an invalid policy or after connection processing begins.
	End Rem
	Method ConfigureHealth:Int(config:SSessionHealthConfig)
		If (config.probeIntervalMillis = 0) <> (config.probeTimeoutMillis = 0) Then Return False
		For Local index:Int = 0 Until _peers.Length
			If _peers[index].phase <> ESessionPeerPhase.Empty Then Return False
		Next
		_healthConfig = config
		Return True
	End Method

	Rem
	bbdoc: Returns a snapshot of connection health for @peer at @nowMillis.
	End Rem
	Method GetPeerHealth:Int(peer:SNetPeer, nowMillis:UInt, health:SSessionPeerHealth Var)
		Local index:Int = PeerIndex(peer)
		If index < 0 Then
			health = New SSessionPeerHealth
			Return False
		End If
		health = New SSessionPeerHealth(_peers[index].phase = ESessionPeerPhase.Active, ElapsedMillis(nowMillis, _peers[index].lastReceiveAt), _peers[index].hasRoundTrip, _peers[index].roundTripMillis, _peers[index].jitterMillis, _peers[index].probesSent, _peers[index].probesReceived, _peers[index].probesLost, _peers[index].framesSent, _peers[index].framesReceived, _peers[index].bytesSent, _peers[index].bytesReceived)
		Return True
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
	Method PollAt:Int(event:SSessionEvent Var, nowMillis:UInt)
		_nowMillis = nowMillis
		If PollLocal(event) Then Return True
		If Not _open Then
			event = New SSessionEvent
			Return False
		End If

		Repeat
			Local raw:SNetEvent
			If Not _transport.Poll(raw) Then
				If MaintainHealth() Then Continue
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

	Rem
	bbdoc: Writes the next session event using the process monotonic clock.
	End Rem
	Method Poll:Int(event:SSessionEvent Var)
		Return PollAt(event, UInt(MilliSecs()))
	End Method

	Method IsOpen:Int()
		Return _open And _transport And _transport.IsOpen()
	End Method

	Rem
	bbdoc: Returns the most recent local session-frame validation failure.
	End Rem
	Method LastProtocolError:ESessionProtocolError()
		Return _lastProtocolError
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
