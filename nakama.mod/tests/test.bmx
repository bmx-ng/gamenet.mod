SuperStrict

Framework GameNet.Nakama
Import BRL.StandardIO

Function Check(condition:Int, message:String)
	If Not condition Then Throw "FAILED: " + message
End Function

Type TMockNakamaBackend Implements INakamaOnlineBackend
	Field events:SNakamaEvent[] = New SNakamaEvent[0]
	Field players:SNakamaMatchPlayer[] = New SNakamaMatchPlayer[0]
	Field authenticationResult:Int = NAKAMA_AUTHENTICATION_SUCCEEDED
	Field authenticationState:Int = NAKAMA_AUTHENTICATION_IDLE
	Field errorCode:Int
	Field errorMessage:String
	Field userId:String = "local-user"
	Field username:String = "Local"
	Field authenticateStarted:Int
	Field socketStarted:Int
	Field addMatchmakerResult:Int = True
	Field cancelMatchmakerResult:Int = True
	Field requestedMin:Int
	Field requestedMax:Int
	Field requestedQuery:String
	Field requestedKeys:String[] = New String[0]
	Field requestedValues:String[] = New String[0]
	Field cancelCount:Int
	Field selfSessionId:String = "session-local"
	Field sentOpCode:Long
	Field sentData:Byte[] = New Byte[0]
	Field sentTarget:String
	Field leaveCount:Int
	Field disconnectCount:Int
	Field shutdownCount:Int

	Method QueueNative(event:SNakamaEvent)
		events :+ [event]
	End Method

	Method Pump() Override
	End Method

	Method AuthenticateDevice:Int(deviceId:String, requestedUsername:String, create:Int) Override
		authenticateStarted = True
		authenticationState = authenticationResult
		Return True
	End Method

	Method AuthenticationState:Int() Override Return authenticationState End Method
	Method ErrorCode:Int() Override Return errorCode End Method
	Method ErrorMessage:String() Override Return errorMessage End Method
	Method UserId:String() Override Return userId End Method
	Method Username:String() Override Return username End Method

	Method ConnectSocket:Int() Override
		socketStarted = True
		Local event:SNakamaEvent
		event.kind = ENakamaEventKind.SocketConnected
		QueueNative(event)
		Return True
	End Method

	Method AddMatchmaker:Int(minCount:Int, maxCount:Int, query:String, propertyKeys:String[], propertyValues:String[]) Override
		requestedMin = minCount; requestedMax = maxCount
		requestedQuery = query; requestedKeys = propertyKeys[..]; requestedValues = propertyValues[..]
		Return addMatchmakerResult
	End Method

	Method CancelMatchmaker:Int() Override
		cancelCount :+ 1
		Return cancelMatchmakerResult
	End Method

	Method MatchSelfSessionId:String() Override Return selfSessionId End Method
	Method MatchPlayerCount:Int() Override Return players.Length End Method
	Method MatchPlayer:SNakamaMatchPlayer(index:Int) Override Return players[index] End Method

	Method SendMatchDataBytes:Int(opCode:Long, data:Byte Ptr, length:Size_T, targetSessionId:String) Override
		sentOpCode = opCode; sentTarget = targetSessionId
		sentData = New Byte[Int(length)]
		If length Then MemCopy(Byte Ptr(sentData), data, length)
		Return True
	End Method

	Method LeaveMatch:Int() Override
		leaveCount :+ 1
		Return True
	End Method
	Method DisconnectSocket() Override
		disconnectCount :+ 1
	End Method

	Method Poll:Int(event:SNakamaEvent Var) Override
		If events.Length = 0 Then event = New SNakamaEvent; Return False
		event = events[0]
		events = events[1..]
		Return True
	End Method
	Method DroppedEvents:ULong() Override Return 0 End Method

	Method Shutdown() Override
		shutdownCount :+ 1
	End Method
End Type

Function NextOnline:SOnlineEvent(service:TNakamaOnlineService, expected:EOnlineEventKind)
	Local event:SOnlineEvent
	Check(service.Poll(event), "expected online event")
	Check(event.Kind() = expected, "expected online event " + Int(expected) + ", got " + Int(event.Kind()))
	Return event
End Function

Function Player:SNakamaMatchPlayer(userId:String, sessionId:String, username:String)
	Local result:SNakamaMatchPlayer
	result.userId = userId; result.sessionId = sessionId; result.username = username
	Return result
End Function

Function MatchEvent:SNakamaEvent(kind:ENakamaEventKind, subject:String = "")
	Local result:SNakamaEvent
	result.kind = kind; result.subject = subject
	Return result
End Function

Function DataEvent:SNakamaEvent(sessionId:String, sequence:UInt, value:Byte)
	Local buffer:Byte[32]
	Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(buffer), Size_T(buffer.Length))
	writer.WriteUInt32(NAKAMA_FRAME_MAGIC)
	writer.WriteUInt8(NAKAMA_FRAME_VERSION)
	writer.WriteUInt8(UInt(EDeliveryMode.UnreliableSequenced))
	writer.WriteUInt16(2)
	writer.WriteUInt32(sequence)
	writer.WriteUInt8(value)
	Local result:SNakamaEvent
	result.kind = ENakamaEventKind.MatchData
	result.opCode = NAKAMA_GAMENET_OPCODE
	result.sessionId = sessionId
	result.data = buffer[..Int(writer.Position())]
	Return result
End Function

Check(Not TNakamaOnlineService.CreateForBackend(Null), "reject missing backend")
Check(Not TNakamaOnlineService.CreateForBackend(New TMockNakamaBackend, "", "", 4, 1200), "reject empty device id")
Check(Not TNakamaOnlineService.CreateForBackend(New TMockNakamaBackend, "device", "", 0, 1200), "reject zero channels")

' Matchmaking produces a deterministic host and a handed-off transport.
' Both sessions deliberately use the same account id: session id, not user id,
' is the identity that distinguishes realtime match peers.
Local backend:TMockNakamaBackend = New TMockNakamaBackend
backend.players = [Player("shared-user", "session-z", "Local"), Player("shared-user", "session-a", "Remote")]
backend.userId = "shared-user"
backend.selfSessionId = "session-z"
Local service:TNakamaOnlineService = TNakamaOnlineService.CreateForBackend(backend, "device-a", "Local", 4, 1200)
Local openRequest:UInt = service.Open()
Check(openRequest And backend.authenticateStarted, "start device authentication")
Local pendingOnline:SOnlineEvent
Check(Not service.Poll(pendingOnline), "open remains asynchronous")
service.Pump()
service.Pump()
Local onlineEvent:SOnlineEvent = NextOnline(service, EOnlineEventKind.ServiceReady)
Check(onlineEvent.RequestId() = openRequest And backend.socketStarted, "connect realtime socket and correlate open")
Check(service.LocalPlayer().Id() = "shared-user", "publish local Nakama identity")
Check(service.DroppedEvents() = 0, "online queues report no loss")

Local matchmaking:TOnlineMatchmakingRequest = New TOnlineMatchmakingRequest
matchmaking.minPlayers = 2; matchmaking.maxPlayers = 4
matchmaking.properties.Set("game-mode", "capture flag:2")
Local invalidMatchmaking:TOnlineMatchmakingRequest = New TOnlineMatchmakingRequest
invalidMatchmaking.properties.Set("bad.key", "value")
Check(service.StartMatchmaking(invalidMatchmaking) = 0, "reject unsafe Nakama property key")
Local matchRequest:UInt = service.StartMatchmaking(matchmaking)
onlineEvent = NextOnline(service, EOnlineEventKind.MatchmakingStarted)
Check(onlineEvent.RequestId() = matchRequest And backend.requestedMin = 2 And backend.requestedMax = 4, "forward matchmaking counts")
Check(backend.requestedKeys.Length = 1 And backend.requestedKeys[0] = "game-mode" And backend.requestedValues[0] = "capture flag:2", "forward matchmaking properties")
Check(backend.requestedQuery = "+properties.game-mode:capture\ flag\:2", "build escaped exact-match query")
backend.QueueNative(MatchEvent(ENakamaEventKind.MatchJoined, "match-1"))
service.Pump()
onlineEvent = NextOnline(service, EOnlineEventKind.MatchReady)
Check(onlineEvent.RequestId() = matchRequest And onlineEvent.SubjectId() = "match-1", "correlate ready match")
Local info:SOnlineMatchInfo
Check(service.MatchInfo(matchRequest, info), "return match information")
Check(info.PlayerCount() = 2 And Not info.IsSessionHost() And info.SessionHostPeer().IsValid(), "lowest session id is host")
Local transport:INetTransport = service.TakeMatchTransport(matchRequest)
Check(transport And Not service.TakeMatchTransport(matchRequest), "one-shot transport handoff")
Check(TNakamaTransport(transport).DroppedEvents() = 0, "transport queues report no loss")
Check(service.Close() <> 0, "close service after handoff")
NextOnline(service, EOnlineEventKind.ServiceClosed)
Check(backend.shutdownCount = 0, "handed-off transport retains backend")

Local netEvent:SNetEvent
Check(transport.Poll(netEvent) And netEvent.Kind() = ENetEventKind.Connected, "same-account remote session remains a peer")
Local remotePeer:SNetPeer = netEvent.Peer()
Local outbound:Byte[3]
outbound[0] = 7; outbound[1] = 8; outbound[2] = 9
Check(transport.Send(remotePeer, 2, EDeliveryMode.UnreliableSequenced, Byte Ptr(outbound), Size_T(outbound.Length)) = ETransportResult.Ok, "send framed Nakama packet")
Check(backend.sentTarget = "session-a" And backend.sentOpCode = NAKAMA_GAMENET_OPCODE, "direct packet to remote session")
Local reader:SPacketReader = New SPacketReader(Byte Ptr(backend.sentData), Size_T(backend.sentData.Length))
Local magic:UInt, version:UInt, delivery:UInt, channel:UInt, sequence:UInt
reader.ReadUInt32(magic); reader.ReadUInt8(version); reader.ReadUInt8(delivery); reader.ReadUInt16(channel); reader.ReadUInt32(sequence)
Check(Not reader.Failed() And magic = NAKAMA_FRAME_MAGIC And version = NAKAMA_FRAME_VERSION, "Nakama frame header")
Check(delivery = UInt(EDeliveryMode.UnreliableSequenced) And channel = 2 And sequence = 1, "Nakama frame metadata")
Check(reader.Remaining() = 3 And reader.RemainingView().Data()[2] = 9, "Nakama frame payload")

backend.QueueNative(DataEvent("session-a", 2, 42))
Check(transport.Poll(netEvent) And netEvent.Kind() = ENetEventKind.Data, "receive framed Nakama data")
Check(netEvent.Peer().Equals(remotePeer) And netEvent.Channel() = 2 And netEvent.Delivery() = EDeliveryMode.UnreliableSequenced, "restore GameNet metadata")
Check(netEvent.Packet().Length() = 1 And netEvent.Packet().Data()[0] = 42, "restore GameNet payload")
backend.QueueNative(DataEvent("session-a", 1, 99))
Check(Not transport.Poll(netEvent), "drop stale unreliable-sequenced packet")

Check(transport.Disconnect(remotePeer, 73) = ETransportResult.Ok, "send cooperative disconnect")
Check(transport.Poll(netEvent) And netEvent.Kind() = ENetEventKind.Disconnected And netEvent.Code() = 73, "report local disconnect")
transport.Close()
Check(backend.leaveCount = 1 And backend.disconnectCount = 1 And backend.shutdownCount = 1, "release shared backend after transport closes")

' Native cancellation completes asynchronously against the original request.
Local cancelBackend:TMockNakamaBackend = New TMockNakamaBackend
Local cancelService:TNakamaOnlineService = TNakamaOnlineService.CreateForBackend(cancelBackend)
cancelService.Open(); cancelService.Pump(); cancelService.Pump(); NextOnline(cancelService, EOnlineEventKind.ServiceReady)
Local cancelRequest:UInt = cancelService.StartMatchmaking(matchmaking)
NextOnline(cancelService, EOnlineEventKind.MatchmakingStarted)
Check(cancelService.CancelOperation(cancelRequest) And cancelBackend.cancelCount = 1, "request native matchmaking cancellation")
cancelBackend.QueueNative(MatchEvent(ENakamaEventKind.MatchmakingCancelled))
cancelService.Pump()
onlineEvent = NextOnline(cancelService, EOnlineEventKind.MatchmakingCancelled)
Check(onlineEvent.RequestId() = cancelRequest And onlineEvent.Operation() = EOnlineOperation.CancelMatchmaking, "complete native matchmaking cancellation")
cancelService.Close()

' Portable authentication diagnostics remain correlated with Open.
Local failedBackend:TMockNakamaBackend = New TMockNakamaBackend
failedBackend.authenticationResult = NAKAMA_AUTHENTICATION_FAILED
failedBackend.errorCode = 401; failedBackend.errorMessage = "bad credentials"
Local failed:TNakamaOnlineService = TNakamaOnlineService.CreateForBackend(failedBackend)
openRequest = failed.Open(); failed.Pump()
onlineEvent = NextOnline(failed, EOnlineEventKind.OperationFailed)
Check(onlineEvent.RequestId() = openRequest And onlineEvent.Operation() = EOnlineOperation.Open, "correlate authentication failure")
Check(onlineEvent.Error() = EOnlineError.Authentication And onlineEvent.ProviderCode() = 401, "map authentication failure")
Check(failed.State() = EOnlineServiceState.Failed And Not failed.LocalPlayer().IsValid(), "failed service state")
failed.Close()

Print "GameNet.Nakama tests passed"
