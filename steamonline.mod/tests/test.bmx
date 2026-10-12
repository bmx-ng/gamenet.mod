SuperStrict

Framework GameNet.SteamOnline
Import BRL.StandardIO

Function Check(condition:Int, message:String)
	If Not condition Then Throw "FAILED: " + message
End Function

Type TMockTransport Implements INetTransport
	Field open:Int = True

	Method Poll:Int(event:SNetEvent Var)
		event = New SNetEvent
		Return False
	End Method

	Method Send:ETransportResult(peer:SNetPeer, channel:UInt, delivery:EDeliveryMode, data:Byte Ptr, length:Size_T)
		Return ETransportResult.Ok
	End Method

	Method Disconnect:ETransportResult(peer:SNetPeer, code:Int = 0)
		Return ETransportResult.Ok
	End Method

	Method MaxPacketSize:Size_T(delivery:EDeliveryMode)
		Return 900
	End Method

	Method IsOpen:Int()
		Return open
	End Method

	Method Close()
		open = False
	End Method
End Type

Type TMockSteamOnlineBackend Implements ISteamOnlineBackend
	Field listener:ISteamMatchmakingListener
	Field initializeResult:Int = True
	Field localId:ULong = 10
	Field ownerId:ULong = 10
	Field memberIds:ULong[] = [ULong(10), ULong(20)]
	Field lobbyId:ULong = 500
	Field maximumPlayers:Int = 4
	Field joinable:Int = True
	Field properties:TOnlineProperties = New TOnlineProperties
	Field requestedLobbyType:ELobbyType
	Field requestedMaximumPlayers:Int
	Field joinedLobbyId:ULong
	Field leftLobbyId:ULong
	Field invitedSteamId:ULong
	Field inviteDialogLobbyId:ULong
	Field searchLobbyIds:ULong[] = [ULong(500)]
	Field transportIds:ULong[] = New ULong[0]
	Field transport:TMockTransport
	Field pumpCount:Int
	Field commandLine:String

	Method Initialize:Int()
		Return initializeResult
	End Method

	Method Pump()
		pumpCount :+ 1
	End Method

	Method SetListener(value:ISteamMatchmakingListener)
		listener = value
	End Method

	Method LocalSteamId:ULong()
		Return localId
	End Method
	Method PersonaName:String(steamId:ULong, local:Int)
		If local Then Return "Local"
		Return "Player " + steamId
	End Method
	Method LaunchCommandLine:String()
		Return commandLine
	End Method
	Method CreateLobby(lobbyType:ELobbyType, playerLimit:Int)
		requestedLobbyType = lobbyType
		requestedMaximumPlayers = playerLimit
	End Method
	Method AddStringFilter(key:String, value:String)
	End Method

	Method AddSlotsFilter(openSlots:Int)
	End Method

	Method AddResultCountFilter(maximumResults:Int)
	End Method

	Method RequestLobbyList()
	End Method
	Method LobbyByIndex:ULong(index:Int)
		If index < 0 Or index >= searchLobbyIds.Length Then Return 0
		Return searchLobbyIds[index]
	End Method
	Method LobbyData:String(id:ULong, key:String)
		Local found:Int
		Return properties.Value(key, found)
	End Method
	Method LobbyDataCount:Int(id:ULong)
		Return properties.Count()
	End Method
	Method LobbyDataByIndex:Int(id:ULong, index:Int, key:String Var, value:String Var)
		If index < 0 Or index >= properties.Count() Then Return False
		key = properties.KeyAt(index)
		value = properties.ValueAt(index)
		Return True
	End Method
	Method SetLobbyData:Int(id:ULong, key:String, value:String)
		Return properties.Set(key, value)
	End Method
	Method LobbyOwner:ULong(id:ULong)
		Return ownerId
	End Method

	Method LobbyMemberLimit:Int(id:ULong)
		Return maximumPlayers
	End Method

	Method LobbyMemberCount:Int(id:ULong)
		Return memberIds.Length
	End Method
	Method LobbyMember:ULong(id:ULong, index:Int)
		If index < 0 Or index >= memberIds.Length Then Return 0
		Return memberIds[index]
	End Method
	Method SetLobbyJoinable:Int(id:ULong, value:Int)
		joinable = value
		Return True
	End Method
	Method InviteUser:Int(id:ULong, steamId:ULong)
		invitedSteamId = steamId
		Return True
	End Method
	Method JoinLobby(id:ULong)
		joinedLobbyId = id
	End Method

	Method LeaveLobby(id:ULong)
		leftLobbyId = id
	End Method

	Method ShowInviteDialog(id:ULong)
		inviteDialogLobbyId = id
	End Method
	Method CreateTransport:INetTransport(steamIds:ULong[], channelCount:Int, maxPacketSize:Size_T)
		transportIds = steamIds[..]
		transport = New TMockTransport
		Return transport
	End Method
End Type

Function NextEvent:SOnlineEvent(service:TSteamOnlineService, expected:EOnlineEventKind)
	Local event:SOnlineEvent
	Check(service.Poll(event), "expected online event")
	Check(event.Kind() = expected, "expected event " + Int(expected) + ", got " + Int(event.Kind()))
	Return event
End Function

' Exercise the lobby-owner flow.
Local hostBackend:TMockSteamOnlineBackend = New TMockSteamOnlineBackend
Local host:TSteamOnlineService = TSteamOnlineService.CreateForBackend(hostBackend, 2, 900)
Check(host <> Null, "create service with test backend")
Local openRequest:UInt = host.Open()
Local event:SOnlineEvent = NextEvent(host, EOnlineEventKind.ServiceReady)
Check(event.RequestId() = openRequest And event.Player().Id() = "10", "open Steam identity")

Local options:TOnlineLobbyOptions = New TOnlineLobbyOptions
options.name = "Test lobby"
options.maxPlayers = 4
options.visibility = EOnlineLobbyVisibility.Public
options.properties.Set("mode", "duel")
Local createRequest:UInt = host.CreateLobby(options)
Check(createRequest <> 0 And hostBackend.requestedLobbyType = ELobbyType.k_ELobbyTypePublic, "request public lobby")
host.OnLobbyCreated(EResult.k_EResultOK, hostBackend.lobbyId, False)
event = NextEvent(host, EOnlineEventKind.LobbyCreated)
Check(event.RequestId() = createRequest, "correlate lobby creation")
Check(host.CurrentLobby().Name() = "Test lobby" And host.CurrentLobby().MemberCount() = 2, "snapshot created lobby")
Check(host.ShowInviteDialog() And hostBackend.inviteDialogLobbyId = hostBackend.lobbyId, "show invite dialog")
Check(host.InvitePlayer("20") And hostBackend.invitedSteamId = 20, "invite known player")

Local startRequest:UInt = host.StartMatch()
event = NextEvent(host, EOnlineEventKind.MatchReady)
Local info:SOnlineMatchInfo
Check(event.RequestId() = startRequest And host.MatchInfo(startRequest, info), "publish host match")
Check(info.IsSessionHost() And info.PlayerCount() = 2, "host match information")
Check(hostBackend.transportIds.Length = 1 And hostBackend.transportIds[0] = 20, "host transport contains remote members")
Check(host.TakeMatchTransport(startRequest) <> Null, "take host transport")

' Exercise discovery and the joined-client start signal.
Local clientBackend:TMockSteamOnlineBackend = New TMockSteamOnlineBackend
clientBackend.localId = 20
clientBackend.ownerId = 10
clientBackend.properties.Set(STEAM_ONLINE_NAME_KEY, "Test lobby")
clientBackend.properties.Set(STEAM_ONLINE_JOINABLE_KEY, "1")
Local client:TSteamOnlineService = TSteamOnlineService.CreateForBackend(clientBackend, 2, 900)
client.Open()
NextEvent(client, EOnlineEventKind.ServiceReady)
Local query:TOnlineLobbyQuery = New TOnlineLobbyQuery
Local findRequest:UInt = client.FindLobbies(query)
client.OnLobbyMatchList(1, False)
event = NextEvent(client, EOnlineEventKind.LobbySearchCompleted)
Check(event.RequestId() = findRequest And client.LobbyResultCount(findRequest) = 1, "return lobby search results")
Local joinRequest:UInt = client.JoinLobby("500")
Check(clientBackend.joinedLobbyId = 500, "request lobby join")
client.OnLobbyEnter(500, False, EChatRoomEnterResponse.k_EChatRoomEnterResponseSuccess)
event = NextEvent(client, EOnlineEventKind.LobbyJoined)
Check(event.RequestId() = joinRequest, "correlate lobby join")
startRequest = client.StartMatch()
client.Pump()
Local pending:SOnlineEvent
Check(Not client.Poll(pending), "wait for owner start signal")
clientBackend.properties.Set(STEAM_ONLINE_START_KEY, "1")
client.Pump()
event = NextEvent(client, EOnlineEventKind.MatchReady)
Check(client.MatchInfo(startRequest, info) And Not info.IsSessionHost(), "publish client match")
Check(info.SessionHostPeer().IsValid(), "identify client session host")
Check(clientBackend.transportIds.Length = 1 And clientBackend.transportIds[0] = 10, "client transport targets lobby owner")

client.OnLobbyInvite(30, 700, 0)
event = NextEvent(client, EOnlineEventKind.InvitationReceived)
Check(event.SubjectId() = "700" And event.Player().Id() = "30", "report Steam invitation")

client.Close()
NextEvent(client, EOnlineEventKind.ServiceClosed)
Check(clientBackend.leftLobbyId = 500 And clientBackend.listener = Null, "close provider cleanly")

' Authentication and provider failures remain correlated and recoverable.
Local failedBackend:TMockSteamOnlineBackend = New TMockSteamOnlineBackend
failedBackend.initializeResult = False
Local failed:TSteamOnlineService = TSteamOnlineService.CreateForBackend(failedBackend)
openRequest = failed.Open()
event = NextEvent(failed, EOnlineEventKind.OperationFailed)
Check(event.RequestId() = openRequest And event.Operation() = EOnlineOperation.Open And event.Error() = EOnlineError.Authentication, "report Steam authentication failure")
Check(Not failed.LocalPlayer().IsValid(), "hide local identity when opening failed")
Check(failed.Close() <> 0, "close failed provider")
NextEvent(failed, EOnlineEventKind.ServiceClosed)

Local createFailureBackend:TMockSteamOnlineBackend = New TMockSteamOnlineBackend
Local createFailure:TSteamOnlineService = TSteamOnlineService.CreateForBackend(createFailureBackend)
createFailure.Open()
NextEvent(createFailure, EOnlineEventKind.ServiceReady)
createRequest = createFailure.CreateLobby(New TOnlineLobbyOptions)
createFailure.OnLobbyCreated(EResult.k_EResultFail, 0, False)
event = NextEvent(createFailure, EOnlineEventKind.OperationFailed)
Check(event.RequestId() = createRequest And event.Operation() = EOnlineOperation.CreateLobby, "report lobby creation failure")

Print "GameNet.SteamOnline tests passed"
