SuperStrict

Import GameNet.Core
Import Apple.GameKit
Import BRL.Blitz

Const GAMEKIT_FRAME_MAGIC:UInt = $474e474b ' GNGK
Const GAMEKIT_FRAME_VERSION:UInt = 1
Const GAMEKIT_FRAME_HEADER_SIZE:Size_T = 12
Const GAMEKIT_DEFAULT_MAX_PACKET_SIZE:Size_T = 900

Rem
bbdoc: Adapter-owned failures reported through #SNetEvent.Error.
End Rem
Enum EGameKitTransportError:Int
	MatchFailed = 1
	IncomingPacketTooLarge
	InvalidFrame
	InvalidPlayer
End Enum

Rem
bbdoc: Low-level match operations consumed by #TGameKitTransport.
about: Applications normally use #TGameKitTransport.Create with a
#TGameCenterMatch. This interface is public so transport framing and session
code can be tested with a deterministic match implementation.
End Rem
Interface IGameKitMatchBackend
	Method Poll:Int(event:SGameCenterMatchEvent Var, data:Byte Ptr, dataCapacity:Size_T)
	Method Send:Int(playerIndex:Int, mode:EGameCenterMatchSendMode, data:Byte Ptr, length:Size_T, error:TGameCenterError Var)
	Method IsOpen:Int()
	Method Disconnect()
End Interface

Private

Type TAppleGameKitMatchBackend Implements IGameKitMatchBackend
	Field match:TGameCenterMatch

	Function Create:TAppleGameKitMatchBackend(match:TGameCenterMatch)
		If Not match Then Return Null
		Local backend:TAppleGameKitMatchBackend = New TAppleGameKitMatchBackend
		backend.match = match
		Return backend
	End Function

	Method Poll:Int(event:SGameCenterMatchEvent Var, data:Byte Ptr, dataCapacity:Size_T) Override
		Return match.Poll(event, data, dataCapacity)
	End Method

	Method Send:Int(playerIndex:Int, mode:EGameCenterMatchSendMode, data:Byte Ptr, length:Size_T, error:TGameCenterError Var) Override
		Return match.Send(playerIndex, mode, data, length, error)
	End Method

	Method IsOpen:Int() Override
		Return match And match.IsOpen()
	End Method

	Method Disconnect() Override
		If match Then match.Disconnect()
		match = Null
	End Method
End Type

Public

Rem
bbdoc: Adapts one real-time Game Center match to #INetTransport.
about: GameKit supplies reliable and unreliable packets but no logical
channels or unreliable-sequenced mode. This adapter adds a small frame header
and discards stale sequenced packets. Storage is allocated by #Create; Send and
Poll perform no managed allocation in the successful packet path.

Game Center cannot disconnect only one participant from a peer-to-peer match.
Consequently #Disconnect ends the entire match and reports every active peer
as disconnected locally.
End Rem
Type TGameKitTransport Implements INetTransport
	Private
	Field _backend:IGameKitMatchBackend
	Field _maximumPeers:Int
	Field _channelCount:Int
	Field _maxPacketSize:Size_T
	Field _wireCapacity:Size_T
	Field _receiveBuffer:Byte Ptr
	Field _sendBuffer:Byte Ptr
	Field _active:Byte[]
	Field _pendingDisconnect:Byte[]
	Field _pendingDisconnectCode:Int[]
	Field _sendSequence:UInt[]
	Field _receiveSequence:UInt[]
	Field _receiveSequenceSeen:Byte[]
	Field _open:Int = True
	Field _lastError:TGameCenterError

	Method New(backend:IGameKitMatchBackend, maximumPeers:Int, channelCount:Int, maxPacketSize:Size_T)
		_backend = backend
		_maximumPeers = maximumPeers
		_channelCount = channelCount
		_maxPacketSize = maxPacketSize
		_wireCapacity = maxPacketSize + GAMEKIT_FRAME_HEADER_SIZE
		_receiveBuffer = MemAlloc(_wireCapacity)
		_sendBuffer = MemAlloc(_wireCapacity)
		_active = New Byte[maximumPeers]
		_pendingDisconnect = New Byte[maximumPeers]
		_pendingDisconnectCode = New Int[maximumPeers]
		_sendSequence = New UInt[channelCount]
		_receiveSequence = New UInt[maximumPeers * channelCount]
		_receiveSequenceSeen = New Byte[maximumPeers * channelCount]
	End Method

	Method PeerForIndex:SNetPeer(playerIndex:Int)
		Return New SNetPeer(UInt(playerIndex), 1)
	End Method

	Method PlayerIndex:Int(peer:SNetPeer)
		If Not peer.IsValid() Or peer.Generation() <> 1 Or peer.Id() < 1 Or peer.Id() > UInt(_maximumPeers) Then Return -1
		Return Int(peer.Id())
	End Method

	Method SequenceIndex:Int(playerIndex:Int, channel:UInt)
		Return (playerIndex - 1) * _channelCount + Int(channel)
	End Method

	Method NextPendingDisconnect:Int()
		For Local index:Int = 0 Until _maximumPeers
			If _pendingDisconnect[index] Then Return index
		Next
		Return -1
	End Method

	Method EndMatch(code:Int)
		If Not _open Then Return
		_open = False
		For Local index:Int = 0 Until _maximumPeers
			If _active[index] Then
				_active[index] = False
				_pendingDisconnect[index] = True
				_pendingDisconnectCode[index] = code
			End If
		Next
		_backend.Disconnect()
	End Method

	Public
	Method Delete()
		Close()
		If _receiveBuffer Then MemFree(_receiveBuffer)
		If _sendBuffer Then MemFree(_sendBuffer)
		_receiveBuffer = Null
		_sendBuffer = Null
	End Method

	Rem
	bbdoc: Creates a GameNet transport which owns @match until #Close.
	End Rem
	Function Create:TGameKitTransport(match:TGameCenterMatch, maximumPeers:Int = 8, channelCount:Int = 4, maxPacketSize:Size_T = GAMEKIT_DEFAULT_MAX_PACKET_SIZE)
		Return CreateForBackend(TAppleGameKitMatchBackend.Create(match), maximumPeers, channelCount, maxPacketSize)
	End Function

	Rem
	bbdoc: Creates a transport over a custom low-level match implementation.
	about: This extension point primarily supports deterministic transport tests.
	End Rem
	Function CreateForBackend:TGameKitTransport(backend:IGameKitMatchBackend, maximumPeers:Int = 8, channelCount:Int = 4, maxPacketSize:Size_T = GAMEKIT_DEFAULT_MAX_PACKET_SIZE)
		If Not backend Or maximumPeers < 1 Or channelCount < 1 Or channelCount > 65536 Or maxPacketSize < 1 Then Return Null
		Return New TGameKitTransport(backend, maximumPeers, channelCount, maxPacketSize)
	End Function

	Rem
	bbdoc: Returns the most recent native Game Center send or match error.
	End Rem
	Method LastGameCenterError:TGameCenterError()
		Return _lastError
	End Method

	Method Poll:Int(event:SNetEvent Var) Override
		Local pendingIndex:Int = NextPendingDisconnect()
		If pendingIndex >= 0 Then
			_pendingDisconnect[pendingIndex] = False
			event = SNetEvent.Disconnected(PeerForIndex(pendingIndex + 1), _pendingDisconnectCode[pendingIndex])
			Return True
		End If

		While _open
			Local matchEvent:SGameCenterMatchEvent
			If Not _backend.Poll(matchEvent, _receiveBuffer, _wireCapacity) Then
				event = New SNetEvent
				Return False
			End If
			Local playerIndex:Int = matchEvent.PlayerIndex()
			Select matchEvent.Kind()
				Case EGameCenterMatchEventKind.PlayerConnected
					If playerIndex < 1 Or playerIndex > _maximumPeers Then
						event = SNetEvent.Error(New SNetPeer, Int(EGameKitTransportError.InvalidPlayer))
						Return True
					End If
					_active[playerIndex - 1] = True
					event = SNetEvent.Connected(PeerForIndex(playerIndex))
					Return True

				Case EGameCenterMatchEventKind.PlayerDisconnected
					If playerIndex < 1 Or playerIndex > _maximumPeers Then
						event = SNetEvent.Error(New SNetPeer, Int(EGameKitTransportError.InvalidPlayer))
						Return True
					End If
					_active[playerIndex - 1] = False
					event = SNetEvent.Disconnected(PeerForIndex(playerIndex))
					Return True

				Case EGameCenterMatchEventKind.Failed
					_lastError = matchEvent.Error()
					EndMatch(0)
					event = SNetEvent.Error(New SNetPeer, Int(EGameKitTransportError.MatchFailed))
					Return True

				Case EGameCenterMatchEventKind.Data
					If matchEvent.DataLength() > _wireCapacity Then
						event = SNetEvent.Error(PeerForIndex(playerIndex), Int(EGameKitTransportError.IncomingPacketTooLarge))
						Return True
					End If
					If playerIndex < 1 Or playerIndex > _maximumPeers Or Not _active[playerIndex - 1] Or matchEvent.DataLength() < GAMEKIT_FRAME_HEADER_SIZE Then
						event = SNetEvent.Error(New SNetPeer, Int(EGameKitTransportError.InvalidFrame))
						Return True
					End If
					Local reader:SPacketReader = New SPacketReader(_receiveBuffer, matchEvent.DataLength())
					Local magic:UInt
					Local version:UInt
					Local deliveryValue:UInt
					Local channel:UInt
					Local sequence:UInt
					reader.ReadUInt32(magic)
					reader.ReadUInt8(version)
					reader.ReadUInt8(deliveryValue)
					reader.ReadUInt16(channel)
					reader.ReadUInt32(sequence)
					If reader.Failed() Or magic <> GAMEKIT_FRAME_MAGIC Or version <> GAMEKIT_FRAME_VERSION Or deliveryValue > UInt(EDeliveryMode.ReliableOrdered) Or channel >= UInt(_channelCount) Then
						event = SNetEvent.Error(PeerForIndex(playerIndex), Int(EGameKitTransportError.InvalidFrame))
						Return True
					End If
					Local delivery:EDeliveryMode = EDeliveryMode(deliveryValue)
					If delivery = EDeliveryMode.UnreliableSequenced Then
						Local sequenceIndex:Int = SequenceIndex(playerIndex, channel)
						If _receiveSequenceSeen[sequenceIndex] And Int(sequence - _receiveSequence[sequenceIndex]) <= 0 Then Continue
						_receiveSequenceSeen[sequenceIndex] = True
						_receiveSequence[sequenceIndex] = sequence
					End If
					Local payloadLength:Size_T = matchEvent.DataLength() - GAMEKIT_FRAME_HEADER_SIZE
					event = SNetEvent.Data(PeerForIndex(playerIndex), channel, delivery, New SPacketView(_receiveBuffer + GAMEKIT_FRAME_HEADER_SIZE, payloadLength))
					Return True
			End Select
		Wend

		event = New SNetEvent
		Return False
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T) Override
		If Not _open Or Not _backend.IsOpen() Then Return ETransportResult.Closed
		Local playerIndex:Int = PlayerIndex(peer)
		If playerIndex < 1 Or Not _active[playerIndex - 1] Then Return ETransportResult.InvalidPeer
		If channel >= UInt(_channelCount) Then Return ETransportResult.InvalidChannel
		If Int(delivery) < Int(EDeliveryMode.Unreliable) Or Int(delivery) > Int(EDeliveryMode.ReliableOrdered) Then Return ETransportResult.Failed
		If length > _maxPacketSize Then Return ETransportResult.PacketTooLarge
		If length > 0 And Not data Then Return ETransportResult.Failed

		Local sequence:UInt
		If delivery = EDeliveryMode.UnreliableSequenced Then
			_sendSequence[Int(channel)] :+ 1
			sequence = _sendSequence[Int(channel)]
		End If
		Local writer:SPacketWriter = New SPacketWriter(_sendBuffer, _wireCapacity)
		writer.WriteUInt32(GAMEKIT_FRAME_MAGIC)
		writer.WriteUInt8(GAMEKIT_FRAME_VERSION)
		writer.WriteUInt8(UInt(delivery))
		writer.WriteUInt16(channel)
		writer.WriteUInt32(sequence)
		writer.WriteBytes(data, length)
		If writer.Failed() Then Return ETransportResult.PacketTooLarge

		Local mode:EGameCenterMatchSendMode = EGameCenterMatchSendMode.Unreliable
		If delivery = EDeliveryMode.ReliableOrdered Then mode = EGameCenterMatchSendMode.Reliable
		_lastError = Null
		If Not _backend.Send(playerIndex, mode, _sendBuffer, writer.Position(), _lastError) Then Return ETransportResult.Failed
		Return ETransportResult.Ok
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0) Override
		Local playerIndex:Int = PlayerIndex(peer)
		If playerIndex < 1 Or Not _active[playerIndex - 1] Then Return ETransportResult.InvalidPeer
		EndMatch(code)
		Return ETransportResult.Ok
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode) Override
		Return _maxPacketSize
	End Method

	Method IsOpen:Int() Override
		Return _open Or NextPendingDisconnect() >= 0
	End Method

	Method Close() Override
		If _open Then EndMatch(0)
		For Local index:Int = 0 Until _maximumPeers
			_pendingDisconnect[index] = False
		Next
	End Method
End Type
