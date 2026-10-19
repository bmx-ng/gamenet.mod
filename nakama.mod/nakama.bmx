' Copyright (c) 2026 Bruce A Henderson and contributors
'
' This software is provided 'as-is', without any express or implied
' warranty. Permission is granted to use, alter, and redistribute this
' software under the zlib/libpng licence. This notice must not be removed.

SuperStrict

Rem
bbdoc: Nakama matchmaking and realtime match transport for GameNet.
End Rem
Module GameNet.Nakama

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"
ModuleInfo "History: 0.1 Initial Nakama matchmaking and match transport"

Import GameNet.Online
Import Nakama.SDK

Const NAKAMA_ONLINE_EVENT_CAPACITY:Int = 64
Const NAKAMA_TRANSPORT_EVENT_CAPACITY:Int = 256
Const NAKAMA_DEFAULT_MAX_PACKET_SIZE:Size_T = 1200
Const NAKAMA_FRAME_HEADER_SIZE:Size_T = 12
Const NAKAMA_FRAME_MAGIC:UInt = $474E4E4B ' GNNK
Const NAKAMA_FRAME_VERSION:UInt = 1
Const NAKAMA_CONTROL_DELIVERY:UInt = 255
Const NAKAMA_GAMENET_OPCODE:Long = $474E4554 ' GNET

Enum ENakamaTransportError:Int
	InvalidFrame = 1
	IncomingPacketTooLarge = 2
	UnknownPeer = 3
	SocketClosed = 4
	ProviderFailure = 5
End Enum

Private

Type TNakamaNativeEventQueue
	Field events:SNakamaEvent[]
	Field readIndex:Int
	Field writeIndex:Int
	Field count:Int
	Field dropped:UInt

	Method New(capacity:Int)
		events = New SNakamaEvent[capacity]
	End Method

	Method Push(event:SNakamaEvent)
		If count = events.Length Then dropped :+ 1; Return
		events[writeIndex] = event
		writeIndex = (writeIndex + 1) Mod events.Length
		count :+ 1
	End Method

	Method Poll:Int(event:SNakamaEvent Var)
		If count = 0 Then event = New SNakamaEvent; Return False
		event = events[readIndex]
		events[readIndex] = New SNakamaEvent
		readIndex = (readIndex + 1) Mod events.Length
		count :- 1
		Return True
	End Method
End Type

Public

' Shared internally by the online-service and handed-off transport lifetimes.
Type TNakamaSharedContext
	Private
	Field client:TNakamaClient
	Field serviceEvents:TNakamaNativeEventQueue = New TNakamaNativeEventQueue(NAKAMA_TRANSPORT_EVENT_CAPACITY)
	Field transportEvents:TNakamaNativeEventQueue = New TNakamaNativeEventQueue(NAKAMA_TRANSPORT_EVENT_CAPACITY)
	Field serviceAttached:Int = True
	Field transportAttached:Int
	Field pumping:Int
	Field closed:Int

	Public
	Method New(client:TNakamaClient)
		Self.client = client
	End Method

	Method Client:TNakamaClient()
		Return client
	End Method

	Method PollService:Int(event:SNakamaEvent Var)
		Return serviceEvents.Poll(event)
	End Method

	Method PollTransport:Int(event:SNakamaEvent Var)
		Return transportEvents.Poll(event)
	End Method

	Method Pump()
		If closed Or pumping Or Not client Then Return
		pumping = True
		client.Tick()
		Local event:SNakamaEvent
		While client.Poll(event)
			Select event.kind
				Case ENakamaEventKind.MatchData, ENakamaEventKind.MatchPresenceJoined, ENakamaEventKind.MatchPresenceLeft, ENakamaEventKind.MatchLeft
					If transportAttached Then transportEvents.Push(event)
				Case ENakamaEventKind.SocketDisconnected, ENakamaEventKind.Error
					If serviceAttached Then serviceEvents.Push(event)
					If transportAttached Then transportEvents.Push(event)
				Default
					If serviceAttached Then serviceEvents.Push(event)
			End Select
		Wend
		pumping = False
	End Method

	Method AttachTransport()
		transportAttached = True
	End Method

	Method ReleaseService()
		serviceAttached = False
		ShutdownIfUnused()
	End Method

	Method ReleaseTransport()
		If transportAttached And client Then client.LeaveMatch()
		transportAttached = False
		ShutdownIfUnused()
	End Method

	Method ShutdownIfUnused()
		If closed Or serviceAttached Or transportAttached Then Return
		closed = True
		If client Then
			client.DisconnectSocket()
			client.Free()
			client = Null
		End If
	End Method
End Type

Private

Type TNakamaPeerState
	Field userId:String
	Field sessionId:String
	Field username:String
	Field generation:UInt = 1
	Field active:Int = True
End Type

Public

Rem
bbdoc: Adapts one Nakama realtime match to #INetTransport.
about: Nakama carries every frame over its reliable WebSocket. The framing
retains GameNet delivery metadata and rejects stale UnreliableSequenced data.
End Rem
Type TNakamaTransport Implements INetTransport
	Private
	Field _context:TNakamaSharedContext
	Field _peers:TNakamaPeerState[] = New TNakamaPeerState[0]
	Field _channelCount:Int
	Field _maxPacketSize:Size_T
	Field _sendBuffer:Byte[]
	Field _receiveBuffer:Byte[]
	Field _sendSequence:UInt[]
	Field _receiveSequence:UInt[]
	Field _receiveSequenceSeen:Byte[]
	Field _connectIndex:Int
	Field _events:SNetEvent[] = New SNetEvent[NAKAMA_TRANSPORT_EVENT_CAPACITY]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _open:Int = True

	Public
	Method New(context:TNakamaSharedContext, players:SNakamaMatchPlayer[], localUserId:String, channelCount:Int, maxPacketSize:Size_T)
		_context = context
		_channelCount = channelCount
		_maxPacketSize = maxPacketSize
		_sendBuffer = New Byte[Int(maxPacketSize + NAKAMA_FRAME_HEADER_SIZE)]
		_receiveBuffer = New Byte[Int(maxPacketSize)]
		For Local player:SNakamaMatchPlayer = EachIn players
			If player.sessionId And player.userId <> localUserId Then AddPeer(player)
		Next
		SortPeers()
		_sendSequence = New UInt[channelCount]
		_receiveSequence = New UInt[_peers.Length * channelCount]
		_receiveSequenceSeen = New Byte[_peers.Length * channelCount]
		_context.AttachTransport()
	End Method

	Method PeerForSession:SNetPeer(sessionId:String)
		Local index:Int = PeerIndexForSession(sessionId)
		If index < 0 Then Return New SNetPeer
		Return PeerForIndex(index)
	End Method

	Private
	Method AddPeer(player:SNakamaMatchPlayer)
		Local peer:TNakamaPeerState = New TNakamaPeerState
		peer.userId = player.userId; peer.sessionId = player.sessionId; peer.username = player.username
		_peers :+ [peer]
	End Method

	Method SortPeers()
		For Local index:Int = 1 Until _peers.Length
			Local value:TNakamaPeerState = _peers[index]
			Local position:Int = index
			While position > 0 And _peers[position - 1].sessionId.Compare(value.sessionId) > 0
				_peers[position] = _peers[position - 1]
				position :- 1
			Wend
			_peers[position] = value
		Next
	End Method

	Method Queue(event:SNetEvent)
		If _eventCount = _events.Length Then Return
		_events[_eventWrite] = event
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
	End Method

	Method Queued:Int(event:SNetEvent Var)
		If _eventCount = 0 Then Return False
		event = _events[_eventRead]; _events[_eventRead] = New SNetEvent
		_eventRead = (_eventRead + 1) Mod _events.Length; _eventCount :- 1
		Return True
	End Method

	Method PeerForIndex:SNetPeer(index:Int)
		Return New SNetPeer(UInt(index + 1), _peers[index].generation)
	End Method

	Method PeerIndex:Int(peer:SNetPeer)
		If Not peer.IsValid() Or peer.Id() < 1 Or peer.Id() > UInt(_peers.Length) Then Return -1
		Local index:Int = Int(peer.Id()) - 1
		If peer.Generation() <> _peers[index].generation Then Return -1
		Return index
	End Method

	Method PeerIndexForSession:Int(sessionId:String)
		For Local index:Int = 0 Until _peers.Length
			If _peers[index].sessionId = sessionId Then Return index
		Next
		Return -1
	End Method

	Method SequenceIndex:Int(peerIndex:Int, channel:UInt)
		Return peerIndex * _channelCount + Int(channel)
	End Method

	Method HandleNative(event:SNakamaEvent)
		Select event.kind
			Case ENakamaEventKind.MatchData
				If event.opCode <> NAKAMA_GAMENET_OPCODE Then Return
				Local peerIndex:Int = PeerIndexForSession(event.sessionId)
				If peerIndex < 0 Then Queue(SNetEvent.Error(New SNetPeer, Int(ENakamaTransportError.UnknownPeer))); Return
				If event.data.Length < Int(NAKAMA_FRAME_HEADER_SIZE) Then Queue(SNetEvent.Error(PeerForIndex(peerIndex), Int(ENakamaTransportError.InvalidFrame))); Return
				Local reader:SPacketReader = New SPacketReader(Byte Ptr(event.data), Size_T(event.data.Length))
				Local magic:UInt, version:UInt, deliveryValue:UInt, channel:UInt, sequence:UInt
				reader.ReadUInt32(magic); reader.ReadUInt8(version); reader.ReadUInt8(deliveryValue); reader.ReadUInt16(channel); reader.ReadUInt32(sequence)
				If reader.Failed() Or magic <> NAKAMA_FRAME_MAGIC Or version <> NAKAMA_FRAME_VERSION Or channel >= UInt(_channelCount) Then Queue(SNetEvent.Error(PeerForIndex(peerIndex), Int(ENakamaTransportError.InvalidFrame))); Return
				If deliveryValue = NAKAMA_CONTROL_DELIVERY Then
					Local code:UInt; reader.ReadUInt32(code)
					If reader.Failed() Then Queue(SNetEvent.Error(PeerForIndex(peerIndex), Int(ENakamaTransportError.InvalidFrame))); Return
					Deactivate(peerIndex, Int(code)); Return
				End If
				If deliveryValue > UInt(EDeliveryMode.ReliableOrdered) Then Queue(SNetEvent.Error(PeerForIndex(peerIndex), Int(ENakamaTransportError.InvalidFrame))); Return
				Local length:Size_T = reader.Remaining()
				If length > _maxPacketSize Then Queue(SNetEvent.Error(PeerForIndex(peerIndex), Int(ENakamaTransportError.IncomingPacketTooLarge))); Return
				Local delivery:EDeliveryMode = EDeliveryMode(deliveryValue)
				If delivery = EDeliveryMode.UnreliableSequenced Then
					Local sequenceIndex:Int = SequenceIndex(peerIndex, channel)
					If _receiveSequenceSeen[sequenceIndex] And Int(sequence - _receiveSequence[sequenceIndex]) <= 0 Then Return
					_receiveSequenceSeen[sequenceIndex] = True; _receiveSequence[sequenceIndex] = sequence
				End If
				If length Then MemCopy(Byte Ptr(_receiveBuffer), reader.RemainingView().Data(), length)
				Queue(SNetEvent.Data(PeerForIndex(peerIndex), channel, delivery, New SPacketView(Byte Ptr(_receiveBuffer), length)))
			Case ENakamaEventKind.MatchPresenceLeft
				Local leftIndex:Int = PeerIndexForSession(event.sessionId)
				If leftIndex >= 0 Then Deactivate(leftIndex, 0)
			Case ENakamaEventKind.MatchPresenceJoined
				Local joinedIndex:Int = PeerIndexForSession(event.sessionId)
				If joinedIndex >= 0 And Not _peers[joinedIndex].active Then
					_peers[joinedIndex].generation :+ 1; _peers[joinedIndex].active = True
					Queue(SNetEvent.Connected(PeerForIndex(joinedIndex)))
				End If
			Case ENakamaEventKind.SocketDisconnected, ENakamaEventKind.MatchLeft
				For Local index:Int = 0 Until _peers.Length; Deactivate(index, Int(ENakamaTransportError.SocketClosed)); Next
				_open = False
			Case ENakamaEventKind.Error
				Queue(SNetEvent.Error(New SNetPeer, event.code))
		End Select
	End Method

	Method Deactivate(index:Int, code:Int)
		If index < 0 Or index >= _peers.Length Or Not _peers[index].active Then Return
		_peers[index].active = False
		Queue(SNetEvent.Disconnected(PeerForIndex(index), code))
	End Method

	Public
	Method Poll:Int(event:SNetEvent Var) Override
		If Queued(event) Then Return True
		While _connectIndex < _peers.Length
			Local index:Int = _connectIndex; _connectIndex :+ 1
			If _peers[index].active Then event = SNetEvent.Connected(PeerForIndex(index)); Return True
		Wend
		If _context Then _context.Pump()
		Local nativeEvent:SNakamaEvent
		While _context And _context.PollTransport(nativeEvent)
			HandleNative(nativeEvent)
			If Queued(event) Then Return True
		Wend
		event = New SNetEvent
		Return False
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T) Override
		If Not _open Or Not _context Or Not _context.Client() Then Return ETransportResult.Closed
		Local peerIndex:Int = PeerIndex(peer)
		If peerIndex < 0 Or Not _peers[peerIndex].active Then Return ETransportResult.InvalidPeer
		If channel >= UInt(_channelCount) Then Return ETransportResult.InvalidChannel
		If length > _maxPacketSize Then Return ETransportResult.PacketTooLarge
		If length > 0 And Not data Then Return ETransportResult.Failed
		Local sequence:UInt
		If delivery = EDeliveryMode.UnreliableSequenced Then _sendSequence[Int(channel)] :+ 1; sequence = _sendSequence[Int(channel)]
		Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(_sendBuffer), Size_T(_sendBuffer.Length))
		writer.WriteUInt32(NAKAMA_FRAME_MAGIC); writer.WriteUInt8(NAKAMA_FRAME_VERSION); writer.WriteUInt8(UInt(delivery)); writer.WriteUInt16(channel); writer.WriteUInt32(sequence); writer.WriteBytes(data, length)
		If writer.Failed() Then Return ETransportResult.PacketTooLarge
		If Not _context.Client().SendMatchDataBytes(NAKAMA_GAMENET_OPCODE, Byte Ptr(_sendBuffer), writer.Position(), _peers[peerIndex].sessionId) Then Return ETransportResult.Failed
		Return ETransportResult.Ok
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0) Override
		If Not _open Or Not _context Or Not _context.Client() Then Return ETransportResult.Closed
		Local peerIndex:Int = PeerIndex(peer)
		If peerIndex < 0 Or Not _peers[peerIndex].active Then Return ETransportResult.InvalidPeer
		Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(_sendBuffer), Size_T(_sendBuffer.Length))
		writer.WriteUInt32(NAKAMA_FRAME_MAGIC); writer.WriteUInt8(NAKAMA_FRAME_VERSION); writer.WriteUInt8(NAKAMA_CONTROL_DELIVERY); writer.WriteUInt16(0); writer.WriteUInt32(0); writer.WriteUInt32(UInt(code))
		If Not _context.Client().SendMatchDataBytes(NAKAMA_GAMENET_OPCODE, Byte Ptr(_sendBuffer), writer.Position(), _peers[peerIndex].sessionId) Then Return ETransportResult.Failed
		Deactivate(peerIndex, code)
		Return ETransportResult.Ok
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode) Override Return _maxPacketSize End Method
	Method IsOpen:Int() Override Return _open Or _eventCount > 0 End Method

	Method Close() Override
		If Not _open And Not _context Then Return
		_open = False
		If _context Then _context.ReleaseTransport()
		_context = Null
	End Method

	Method Delete()
		Close()
	End Method
End Type

Rem
bbdoc: Nakama implementation of #IOnlineService.
about: The initial adapter exposes native matchmaking and a realtime match
transport. Nakama storage, RPC, chat, parties and authoritative matches remain
available through the lower-level Nakama.SDK module.
End Rem
Type TNakamaOnlineService Implements IOnlineService
	Private
	Field _state:EOnlineServiceState
	Field _context:TNakamaSharedContext
	Field _deviceId:String
	Field _requestedUsername:String
	Field _nextRequestId:UInt = 1
	Field _openRequestId:UInt
	Field _matchmakingRequestId:UInt
	Field _closeRequestId:UInt
	Field _connectStarted:Int
	Field _events:SOnlineEvent[] = New SOnlineEvent[NAKAMA_ONLINE_EVENT_CAPACITY]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _readyRequestId:UInt
	Field _readyTransport:INetTransport
	Field _readyInfo:SOnlineMatchInfo
	Field _channelCount:Int
	Field _maxPacketSize:Size_T

	Method New(client:TNakamaClient, deviceId:String, username:String, channelCount:Int, maxPacketSize:Size_T)
		_context = New TNakamaSharedContext(client)
		_deviceId = deviceId; _requestedUsername = username
		_channelCount = channelCount; _maxPacketSize = maxPacketSize
	End Method

	Method NextRequestId:UInt()
		Local result:UInt = _nextRequestId; _nextRequestId :+ 1; If _nextRequestId = 0 Then _nextRequestId = 1
		Return result
	End Method

	Method Queue(event:SOnlineEvent)
		If _eventCount = _events.Length Then Return
		_events[_eventWrite] = event; _eventWrite = (_eventWrite + 1) Mod _events.Length; _eventCount :+ 1
	End Method

	Method Failure(operation:EOnlineOperation, requestId:UInt, code:Int, detail:String)
		Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, operation, requestId, EOnlineError.ProviderFailure, code, "", New SOnlinePlayer, detail))
	End Method

	Method PrepareMatch(matchId:String)
		Local count:Int = _context.Client().MatchPlayerCount()
		If count < 1 Then Failure(EOnlineOperation.StartMatchmaking, _matchmakingRequestId, 0, "Nakama returned an empty match roster"); _matchmakingRequestId = 0; Return
		Local players:SNakamaMatchPlayer[] = New SNakamaMatchPlayer[count]
		Local localUserId:String = _context.Client().UserId()
		Local localSessionId:String
		Local hostSessionId:String
		For Local index:Int = 0 Until count
			players[index] = _context.Client().MatchPlayer(index)
			If players[index].userId = localUserId Then localSessionId = players[index].sessionId
			If Not hostSessionId Or players[index].sessionId.Compare(hostSessionId) < 0 Then hostSessionId = players[index].sessionId
		Next
		If Not localSessionId Or Not hostSessionId Then Failure(EOnlineOperation.StartMatchmaking, _matchmakingRequestId, 0, "Nakama match roster has no local session"); _matchmakingRequestId = 0; Return
		Local transport:TNakamaTransport = New TNakamaTransport(_context, players, localUserId, _channelCount, _maxPacketSize)
		Local host:Int = localSessionId = hostSessionId
		Local hostPeer:SNetPeer
		If Not host Then hostPeer = transport.PeerForSession(hostSessionId)
		_readyRequestId = _matchmakingRequestId; _matchmakingRequestId = 0
		_readyTransport = transport; _readyInfo = New SOnlineMatchInfo(count, host, hostPeer)
		Queue(New SOnlineEvent(EOnlineEventKind.MatchReady, EOnlineOperation.StartMatchmaking, _readyRequestId, EOnlineError.None, 0, matchId, New SOnlinePlayer, ""))
	End Method

	Public
	Function Create:TNakamaOnlineService(host:String, port:Int, serverKey:String, deviceId:String, username:String = "", useSSL:Int = False, timeoutMs:Int = 10000, channelCount:Int = 4, maxPacketSize:Size_T = NAKAMA_DEFAULT_MAX_PACKET_SIZE)
		If Not host Or port < 1 Or port > 65535 Or Not serverKey Or Not deviceId Or timeoutMs < 1 Or channelCount < 1 Or channelCount > 65536 Or maxPacketSize < 1 Or maxPacketSize > Size_T($7FFFFFFF) - NAKAMA_FRAME_HEADER_SIZE Then Return Null
		Local client:TNakamaClient = TNakamaClient.Create(host, port, serverKey, useSSL, timeoutMs)
		If Not client Then Return Null
		Return New TNakamaOnlineService(client, deviceId, username, channelCount, maxPacketSize)
	End Function

	Method ProviderName:String() Override Return "Nakama" End Method
	Method Capabilities:EOnlineCapability() Override Return EOnlineCapability.Matchmaking | EOnlineCapability.MatchTransport End Method
	Method State:EOnlineServiceState() Override Return _state End Method
	Method LocalPlayer:SOnlinePlayer() Override
		If _state <> EOnlineServiceState.Ready Or Not _context Or Not _context.Client() Then Return New SOnlinePlayer
		Return New SOnlinePlayer(_context.Client().UserId(), _context.Client().Username(), True)
	End Method

	Method Open:UInt() Override
		If _state <> EOnlineServiceState.Closed Or Not _context Or Not _context.Client() Then Return 0
		_openRequestId = NextRequestId(); _state = EOnlineServiceState.Opening
		If Not _context.Client().AuthenticateDevice(_deviceId, _requestedUsername, True) Then
			_state = EOnlineServiceState.Failed; Failure(EOnlineOperation.Open, _openRequestId, _context.Client().ErrorCode(), _context.Client().ErrorMessage())
		End If
		Return _openRequestId
	End Method

	Method Pump() Override
		If _state = EOnlineServiceState.Closed Or Not _context Then Return
		_context.Pump()
		If _state = EOnlineServiceState.Opening And _context.Client() Then
			Select _context.Client().AuthenticationState()
				Case NAKAMA_AUTHENTICATION_SUCCEEDED
					If Not _connectStarted Then
						_connectStarted = True
						If Not _context.Client().ConnectSocket() Then _state = EOnlineServiceState.Failed; Failure(EOnlineOperation.Open, _openRequestId, _context.Client().ErrorCode(), _context.Client().ErrorMessage())
					End If
				Case NAKAMA_AUTHENTICATION_FAILED
					_state = EOnlineServiceState.Failed; Failure(EOnlineOperation.Open, _openRequestId, _context.Client().ErrorCode(), _context.Client().ErrorMessage())
			End Select
		End If
		Local event:SNakamaEvent
		While _context.PollService(event)
			Select event.kind
				Case ENakamaEventKind.SocketConnected
					If _state = EOnlineServiceState.Opening Then _state = EOnlineServiceState.Ready; Queue(New SOnlineEvent(EOnlineEventKind.ServiceReady, EOnlineOperation.Open, _openRequestId, EOnlineError.None, 0, "", LocalPlayer(), ""))
				Case ENakamaEventKind.MatchJoined
					If _matchmakingRequestId Then PrepareMatch(event.subject)
				Case ENakamaEventKind.MatchmakingCancelled
					If _matchmakingRequestId Then Local id:UInt = _matchmakingRequestId; _matchmakingRequestId = 0; Queue(New SOnlineEvent(EOnlineEventKind.MatchmakingCancelled, EOnlineOperation.CancelMatchmaking, id, EOnlineError.Cancelled, 0, "", New SOnlinePlayer, ""))
				Case ENakamaEventKind.Error
					If _state = EOnlineServiceState.Opening Then _state = EOnlineServiceState.Failed; Failure(EOnlineOperation.Open, _openRequestId, event.code, event.subject) Else If _matchmakingRequestId Then Local id:UInt = _matchmakingRequestId; _matchmakingRequestId = 0; Failure(EOnlineOperation.StartMatchmaking, id, event.code, event.subject)
				Case ENakamaEventKind.SocketDisconnected
					If _state <> EOnlineServiceState.Closing Then _state = EOnlineServiceState.Failed; Failure(EOnlineOperation.None, 0, event.code, "Nakama realtime socket disconnected")
			End Select
		Wend
	End Method

	Method Poll:Int(event:SOnlineEvent Var) Override
		If _eventCount = 0 Then event = New SOnlineEvent; Return False
		event = _events[_eventRead]; _events[_eventRead] = New SOnlineEvent
		_eventRead = (_eventRead + 1) Mod _events.Length; _eventCount :- 1
		Return True
	End Method

	Method CreateLobby:UInt(options:TOnlineLobbyOptions) Override Return 0 End Method
	Method FindLobbies:UInt(query:TOnlineLobbyQuery) Override Return 0 End Method
	Method LobbyResultCount:Int(requestId:UInt) Override Return 0 End Method
	Method LobbyResult:IOnlineLobby(requestId:UInt, index:Int) Override Return Null End Method
	Method CurrentLobby:IOnlineLobby() Override Return Null End Method
	Method JoinLobby:UInt(lobbyId:String) Override Return 0 End Method
	Method LeaveLobby:UInt() Override Return 0 End Method
	Method AcceptInvitation:UInt(invitationId:String) Override Return 0 End Method

	Method StartMatchmaking:UInt(request:TOnlineMatchmakingRequest) Override
		If _state <> EOnlineServiceState.Ready Or Not request Or _matchmakingRequestId Or _readyTransport Or request.minPlayers < 2 Or request.maxPlayers < request.minPlayers Then Return 0
		_matchmakingRequestId = NextRequestId()
		If Not _context.Client().AddMatchmaker(request.minPlayers, request.maxPlayers) Then _matchmakingRequestId = 0; Return 0
		Queue(New SOnlineEvent(EOnlineEventKind.MatchmakingStarted, EOnlineOperation.StartMatchmaking, _matchmakingRequestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return _matchmakingRequestId
	End Method

	Method CancelOperation:Int(requestId:UInt) Override
		If requestId = 0 Or requestId <> _matchmakingRequestId Then Return False
		Return _context.Client().CancelMatchmaker()
	End Method

	Method CancelMatchmaking:UInt(requestId:UInt) Override
		If Not CancelOperation(requestId) Then Return 0
		Return requestId
	End Method

	Method StartMatch:UInt() Override Return 0 End Method

	Method MatchInfo:Int(requestId:UInt, info:SOnlineMatchInfo Var) Override
		If requestId = 0 Or requestId <> _readyRequestId Or Not _readyTransport Then info = New SOnlineMatchInfo; Return False
		info = _readyInfo; Return True
	End Method

	Method TakeMatchTransport:INetTransport(requestId:UInt) Override
		If requestId = 0 Or requestId <> _readyRequestId Or Not _readyTransport Then Return Null
		Local result:INetTransport = _readyTransport
		_readyTransport = Null; _readyRequestId = 0; _readyInfo = New SOnlineMatchInfo
		Return result
	End Method

	Method Close:UInt() Override
		If _state = EOnlineServiceState.Closed Or _state = EOnlineServiceState.Closing Then Return 0
		_closeRequestId = NextRequestId(); _state = EOnlineServiceState.Closing
		If _readyTransport Then _readyTransport.Close(); _readyTransport = Null
		If _context Then _context.ReleaseService()
		_state = EOnlineServiceState.Closed
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceClosed, EOnlineOperation.Close, _closeRequestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return _closeRequestId
	End Method

	Method Delete()
		If _state <> EOnlineServiceState.Closed Then Close()
	End Method
End Type

?
