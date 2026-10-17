SuperStrict

Framework GameNet.EOSOnline
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

Type TMockEOSOnlineBackend Implements IEOSOnlineBackend
	Field listener:IEOSOnlineBackendListener
	Field initializeResult:Int = True
	Field localId:String = "local-puid"
	Field displayName:String = "Local"
	Field created:Int
	Field searched:Int
	Field joinedLobbyId:String
	Field acceptedInviteId:String
	Field leftLobbyId:String
	Field leftAsOwner:Int
	Field startLobbyId:String
	Field invitedId:String
	Field transportIds:String[] = New String[0]
	Field transport:TMockTransport
	Field shutdownCalled:Int
	Field pumpCount:Int

	Method Initialize:Int(value:IEOSOnlineBackendListener)
		listener = value
		Return initializeResult
	End Method
	Method Pump()
		pumpCount :+ 1
	End Method
	Method LocalUserId:String()
		Return localId
	End Method
	Method LocalDisplayName:String()
		Return displayName
	End Method
	Method CreateLobby:Int(options:TOnlineLobbyOptions, bucketId:String)
		created = bucketId = "duel"
		Return created
	End Method
	Method FindLobbies:Int(query:TOnlineLobbyQuery, bucketId:String)
		searched = bucketId = "duel"
		Return searched
	End Method
	Method JoinLobby:Int(lobbyId:String)
		joinedLobbyId = lobbyId
		Return True
	End Method
	Method AcceptInvitation:Int(invitationId:String)
		acceptedInviteId = invitationId
		Return True
	End Method
	Method LeaveLobby:Int(lobbyId:String, owner:Int)
		leftLobbyId = lobbyId
		leftAsOwner = owner
		Return True
	End Method
	Method PublishStart:Int(lobbyId:String)
		startLobbyId = lobbyId
		Return True
	End Method
	Method InvitePlayer:Int(lobbyId:String, productUserId:String)
		invitedId = productUserId
		Return True
	End Method
	Method CreateTransport:INetTransport(remoteUserIds:String[], socketName:String, channelCount:Int, maxPacketSize:Size_T)
		transportIds = remoteUserIds[..]
		transport = New TMockTransport
		Return transport
	End Method
	Method Shutdown()
		shutdownCalled = True
		listener = Null
	End Method
End Type

Function Snapshot:TEOSOnlineLobbySnapshot(localId:String, ownerId:String, started:Int = False)
	Local result:TEOSOnlineLobbySnapshot = New TEOSOnlineLobbySnapshot
	result.LobbyId = "lobby-1"
	result.Name = "Test lobby"
	result.OwnerId = ownerId
	result.MaximumPlayers = 4
	result.AvailableSlots = 2
	result.Joinable = Not started
	result.MemberIds = [ownerId, localId]
	result.Properties.Set("mode", "duel")
	result.Properties.Set(EOS_ONLINE_START_KEY, String(Int(started <> 0)))
	Return result
End Function

Function NextEvent:SOnlineEvent(service:TEOSOnlineService, expected:EOnlineEventKind)
	Local event:SOnlineEvent
	Check(service.Poll(event), "expected online event")
	Check(event.Kind() = expected, "expected event " + Int(expected) + ", got " + Int(event.Kind()))
	Return event
End Function

' Lobby owner creates a lobby, publishes start, and receives all remote peers.
Local hostBackend:TMockEOSOnlineBackend = New TMockEOSOnlineBackend
Local host:TEOSOnlineService = TEOSOnlineService.CreateForBackend(hostBackend, "duel", "GAMENET", 2, 900)
Check(host <> Null, "create EOS service")
Local openRequest:UInt = host.Open()
Local event:SOnlineEvent = NextEvent(host, EOnlineEventKind.ServiceReady)
Check(event.RequestId() = openRequest And event.Player().Id() = "local-puid" And event.Player().DisplayName() = "Local", "open existing EOS identity")

Local options:TOnlineLobbyOptions = New TOnlineLobbyOptions
options.name = "Test lobby"
options.maxPlayers = 4
options.visibility = EOnlineLobbyVisibility.Public
options.properties.Set("mode", "duel")
Local createRequest:UInt = host.CreateLobby(options)
Check(createRequest <> 0 And hostBackend.created, "begin EOS lobby creation")
host.OnEOSOnlineLobbyCreated(EEOSResult.Success, Snapshot("remote-puid", "local-puid"))
event = NextEvent(host, EOnlineEventKind.LobbyCreated)
Check(event.RequestId() = createRequest And host.CurrentLobby().Name() = "Test lobby", "publish created lobby")
Check(host.InvitePlayer("remote-puid") And hostBackend.invitedId = "remote-puid", "invite Product User")

Local startRequest:UInt = host.StartMatch()
Check(startRequest <> 0 And hostBackend.startLobbyId = "lobby-1", "publish owner start")
host.OnEOSOnlineStartPublished(EEOSResult.Success, Snapshot("remote-puid", "local-puid", True))
event = NextEvent(host, EOnlineEventKind.MatchReady)
Local info:SOnlineMatchInfo
Check(event.RequestId() = startRequest And host.MatchInfo(startRequest, info), "correlate host match")
Check(info.IsSessionHost() And info.PlayerCount() = 2, "host match information")
Check(hostBackend.transportIds.Length = 1 And hostBackend.transportIds[0] = "remote-puid", "host transport contains remote member")
Check(host.TakeMatchTransport(startRequest) <> Null, "take host transport")

' A client discovers and joins the lobby, then waits for the owner's start flag.
Local clientBackend:TMockEOSOnlineBackend = New TMockEOSOnlineBackend
clientBackend.localId = "remote-puid"
Local client:TEOSOnlineService = TEOSOnlineService.CreateForBackend(clientBackend, "duel", "GAMENET", 2, 900)
client.Open()
NextEvent(client, EOnlineEventKind.ServiceReady)
Local query:TOnlineLobbyQuery = New TOnlineLobbyQuery
query.properties.Set("mode", "duel")
Local findRequest:UInt = client.FindLobbies(query)
Check(findRequest <> 0 And clientBackend.searched, "begin EOS lobby search")
Local results:TEOSOnlineLobbyResults = New TEOSOnlineLobbyResults
results.Snapshots = [Snapshot("remote-puid", "local-puid")]
client.OnEOSOnlineLobbySearch(EEOSResult.Success, results)
event = NextEvent(client, EOnlineEventKind.LobbySearchCompleted)
Check(event.RequestId() = findRequest And client.LobbyResultCount(findRequest) = 1, "publish EOS search results")
Local joinRequest:UInt = client.JoinLobby("lobby-1")
Check(joinRequest <> 0 And clientBackend.joinedLobbyId = "lobby-1", "join discovered lobby")
client.OnEOSOnlineLobbyJoined(EEOSResult.Success, Snapshot("remote-puid", "local-puid"))
event = NextEvent(client, EOnlineEventKind.LobbyJoined)
Check(event.RequestId() = joinRequest, "correlate EOS lobby join")
startRequest = client.StartMatch()
Local pending:SOnlineEvent
Check(startRequest <> 0 And Not client.Poll(pending), "wait for EOS owner start")
client.OnEOSOnlineLobbyChanged(Snapshot("remote-puid", "local-puid", True), "local-puid", EEOSLobbyMemberStatus.Joined)
NextEvent(client, EOnlineEventKind.LobbyChanged)
event = NextEvent(client, EOnlineEventKind.MatchReady)
Check(client.MatchInfo(startRequest, info) And Not info.IsSessionHost() And info.SessionHostPeer().IsValid(), "publish client match information")
Check(clientBackend.transportIds.Length = 1 And clientBackend.transportIds[0] = "local-puid", "client transport targets lobby owner")

client.OnEOSOnlineInvitation("invite-7", "lobby-7", "friend-puid", False)
event = NextEvent(client, EOnlineEventKind.InvitationReceived)
Check(event.SubjectId() = "invite-7" And event.Player().Id() = "friend-puid", "report EOS invitation")

Local closeRequest:UInt = client.Close()
Check(closeRequest <> 0 And clientBackend.leftLobbyId = "lobby-1" And Not clientBackend.leftAsOwner, "leave lobby while closing")
client.OnEOSOnlineLobbyLeft(EEOSResult.Success, "lobby-1")
event = NextEvent(client, EOnlineEventKind.ServiceClosed)
Check(event.RequestId() = closeRequest And clientBackend.shutdownCalled, "close EOS provider cleanly")

' Reserved adapter metadata cannot be overwritten by application properties.
Local invalidOptions:TOnlineLobbyOptions = New TOnlineLobbyOptions
invalidOptions.properties.Set(EOS_ONLINE_START_KEY, "1")
Local invalidBackend:TMockEOSOnlineBackend = New TMockEOSOnlineBackend
Local invalid:TEOSOnlineService = TEOSOnlineService.CreateForBackend(invalidBackend, "duel")
invalid.Open(); NextEvent(invalid, EOnlineEventKind.ServiceReady)
Check(invalid.CreateLobby(invalidOptions) = 0, "reject reserved lobby property")

' Invitation acceptance preserves the invitation request rather than treating
' the provider's lobby id as a portable invitation id.
Local inviteBackend:TMockEOSOnlineBackend = New TMockEOSOnlineBackend
inviteBackend.localId = "remote-puid"
Local inviteService:TEOSOnlineService = TEOSOnlineService.CreateForBackend(inviteBackend, "duel")
inviteService.Open(); NextEvent(inviteService, EOnlineEventKind.ServiceReady)
Local acceptRequest:UInt = inviteService.AcceptInvitation("invite-9")
Check(acceptRequest <> 0 And inviteBackend.acceptedInviteId = "invite-9", "accept EOS invitation")
inviteService.OnEOSOnlineLobbyJoined(EEOSResult.Success, Snapshot("remote-puid", "local-puid"))
event = NextEvent(inviteService, EOnlineEventKind.LobbyJoined)
Check(event.RequestId() = acceptRequest And event.Operation() = EOnlineOperation.AcceptInvitation, "correlate accepted invitation")

Print "GameNet.EOSOnline tests passed"
