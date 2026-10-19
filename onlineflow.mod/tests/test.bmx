SuperStrict

Framework BRL.StandardIO
Import GameNet.OnlineFlow

Function Check(condition:Int, message:String)
	If Not condition Then
		Throw "FAILED: " + message
	End If
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

Type TMockLobby Implements IOnlineLobby
	Field lobbyId:String = "lobby-1"
	Field lobbyName:String = "Test lobby"
	Field owner:SOnlinePlayer = New SOnlinePlayer("local", "Local", True)
	Field maximumPlayers:Int = 2
	Field joinable:Int = True
	Field members:SOnlinePlayer[] = [owner]
	Field properties:TOnlineProperties = New TOnlineProperties

	Method Id:String()
		Return lobbyId
	End Method

	Method Name:String()
		Return lobbyName
	End Method

	Method Owner:SOnlinePlayer()
		Return owner
	End Method

	Method MaxPlayers:Int()
		Return maximumPlayers
	End Method

	Method IsJoinable:Int()
		Return joinable
	End Method

	Method MemberCount:Int()
		Return members.Length
	End Method

	Method Member:SOnlinePlayer(index:Int)
		If index < 0 Or index >= members.Length Then
			Return New SOnlinePlayer
		End If
		Return members[index]
	End Method

	Method Properties:TOnlineProperties()
		Return properties
	End Method

	Method AddRemote()
		members = [owner, New SOnlinePlayer("remote", "Remote", False)]
	End Method
End Type

Type TMockOnlineService Implements IOnlineService
	Field capabilities:EOnlineCapability
	Field state:EOnlineServiceState = EOnlineServiceState.Closed
	Field nextRequestId:UInt = 1
	Field events:SOnlineEvent[] = New SOnlineEvent[0]
	Field results:IOnlineLobby[] = New IOnlineLobby[0]
	Field resultsRequestId:UInt
	Field current:TMockLobby
	Field findCount:Int
	Field createCount:Int
	Field joinCount:Int
	Field matchmakingCount:Int
	Field acceptedInvitation:String
	Field startRequestId:UInt
	Field matchmakingRequestId:UInt
	Field readyRequestId:UInt
	Field readyInfo:SOnlineMatchInfo
	Field readyTransport:INetTransport

	Method New(value:EOnlineCapability)
		capabilities = value
	End Method

	Method NextId:UInt()
		Local result:UInt = nextRequestId
		nextRequestId :+ 1
		Return result
	End Method

	Method Queue(event:SOnlineEvent)
		events = events[..events.Length + 1]
		events[events.Length - 1] = event
	End Method

	Method ProviderName:String() Override
		Return "mock"
	End Method

	Method Capabilities:EOnlineCapability() Override
		Return capabilities
	End Method

	Method State:EOnlineServiceState() Override
		Return state
	End Method

	Method LocalPlayer:SOnlinePlayer() Override
		Return New SOnlinePlayer("local", "Local", True)
	End Method

	Method Open:UInt() Override
		If state <> EOnlineServiceState.Closed Then
			Return 0
		End If
		Local requestId:UInt = NextId()
		state = EOnlineServiceState.Ready
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceReady, EOnlineOperation.Open, requestId, EOnlineError.None, 0, "", LocalPlayer(), ""))
		Return requestId
	End Method

	Method Pump() Override
	End Method

	Method Poll:Int(event:SOnlineEvent Var) Override
		If events.Length = 0 Then
			event = New SOnlineEvent
			Return False
		End If
		event = events[0]
		events = events[1..]
		Return True
	End Method

	Method CreateLobby:UInt(options:TOnlineLobbyOptions) Override
		createCount :+ 1
		Local requestId:UInt = NextId()
		current = New TMockLobby
		current.maximumPlayers = options.maxPlayers
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyCreated, EOnlineOperation.CreateLobby, requestId, EOnlineError.None, 0, current.Id(), New SOnlinePlayer, ""))
		Return requestId
	End Method

	Method FindLobbies:UInt(query:TOnlineLobbyQuery) Override
		findCount :+ 1
		resultsRequestId = NextId()
		Return resultsRequestId
	End Method

	Method CompleteSearch(value:IOnlineLobby[])
		results = value
		Queue(New SOnlineEvent(EOnlineEventKind.LobbySearchCompleted, EOnlineOperation.FindLobbies, resultsRequestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
	End Method

	Method LobbyResultCount:Int(requestId:UInt) Override
		If requestId <> resultsRequestId Then
			Return 0
		End If
		Return results.Length
	End Method

	Method LobbyResult:IOnlineLobby(requestId:UInt, index:Int) Override
		If requestId <> resultsRequestId Or index < 0 Or index >= results.Length Then
			Return Null
		End If
		Return results[index]
	End Method

	Method CurrentLobby:IOnlineLobby() Override
		Return current
	End Method

	Method JoinLobby:UInt(lobbyId:String) Override
		joinCount :+ 1
		Local requestId:UInt = NextId()
		current = New TMockLobby
		current.lobbyId = lobbyId
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyJoined, EOnlineOperation.JoinLobby, requestId, EOnlineError.None, 0, lobbyId, New SOnlinePlayer, ""))
		Return requestId
	End Method

	Method LeaveLobby:UInt() Override
		If Not current Then
			Return 0
		End If
		Local requestId:UInt = NextId()
		Local lobbyId:String = current.Id()
		current = Null
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyLeft, EOnlineOperation.LeaveLobby, requestId, EOnlineError.None, 0, lobbyId, New SOnlinePlayer, ""))
		Return requestId
	End Method

	Method AcceptInvitation:UInt(invitationId:String) Override
		acceptedInvitation = invitationId
		Local requestId:UInt = JoinLobby("invited-lobby")
		Return requestId
	End Method

	Method StartMatchmaking:UInt(request:TOnlineMatchmakingRequest) Override
		matchmakingCount :+ 1
		matchmakingRequestId = NextId()
		Queue(New SOnlineEvent(EOnlineEventKind.MatchmakingStarted, EOnlineOperation.StartMatchmaking, matchmakingRequestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return matchmakingRequestId
	End Method

	Method CancelMatchmaking:UInt(requestId:UInt) Override
		If requestId <> matchmakingRequestId Then
			Return 0
		End If
		Local cancelRequestId:UInt = NextId()
		Queue(New SOnlineEvent(EOnlineEventKind.MatchmakingCancelled, EOnlineOperation.CancelMatchmaking, cancelRequestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return cancelRequestId
	End Method

	Method StartMatch:UInt() Override
		startRequestId = NextId()
		Return startRequestId
	End Method

	Method CompleteMatch(requestId:UInt, sessionHost:Int = True)
		readyRequestId = requestId
		Local hostPeer:SNetPeer
		If Not sessionHost Then
			hostPeer = New SNetPeer(1, 1)
		End If
		readyInfo = New SOnlineMatchInfo(2, sessionHost, hostPeer)
		readyTransport = New TMockTransport
		Queue(New SOnlineEvent(EOnlineEventKind.MatchReady, EOnlineOperation.StartMatch, requestId, EOnlineError.None, 0, "match-1", New SOnlinePlayer, ""))
	End Method

	Method MatchInfo:Int(requestId:UInt, info:SOnlineMatchInfo Var) Override
		If requestId <> readyRequestId Then
			info = New SOnlineMatchInfo
			Return False
		End If
		info = readyInfo
		Return True
	End Method

	Method TakeMatchTransport:INetTransport(requestId:UInt) Override
		If requestId <> readyRequestId Then
			Return Null
		End If
		Local result:INetTransport = readyTransport
		readyTransport = Null
		readyRequestId = 0
		Return result
	End Method

	Method Close:UInt() Override
		Local requestId:UInt = NextId()
		state = EOnlineServiceState.Closed
		current = Null
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceClosed, EOnlineOperation.Close, requestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return requestId
	End Method

	Method AddRemotePlayer()
		current.AddRemote()
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyChanged, EOnlineOperation.None, 0, EOnlineError.None, 0, current.Id(), New SOnlinePlayer, ""))
	End Method

	Method SendInvitation(invitationId:String)
		Queue(New SOnlineEvent(EOnlineEventKind.InvitationReceived, EOnlineOperation.None, 0, EOnlineError.None, 0, invitationId, New SOnlinePlayer("friend", "Friend", False), ""))
	End Method
End Type

Function OpenFlow(flow:TOnlineFlowCoordinator)
	Check(flow.Open(), "open flow")
	Check(flow.State() = EOnlineFlowState.Opening, "opening state")
	flow.Pump()
	Check(flow.State() = EOnlineFlowState.Ready, "ready state")
End Function

Function HasFlowEvent:Int(flow:TOnlineFlowCoordinator, kind:EOnlineFlowEventKind)
	Local event:SOnlineFlowEvent
	While flow.Poll(event)
		If event.Kind() = kind Then
			Return True
		End If
	Wend
	Return False
End Function

Local lobbyCapabilities:EOnlineCapability = EOnlineCapability.CreateLobby | EOnlineCapability.FindLobbies | EOnlineCapability.Invitations | EOnlineCapability.MatchTransport
Local lobbyService:TMockOnlineService = New TMockOnlineService(lobbyCapabilities)
Local lobbyFlow:TOnlineFlowCoordinator = TOnlineFlowCoordinator.Create(lobbyService)
OpenFlow(lobbyFlow)

Local request:TOnlineFlowRequest = New TOnlineFlowRequest
request.lobbyOptions.minPlayers = 2
request.lobbyOptions.maxPlayers = 2
Check(lobbyFlow.QuickPlay(request), "begin lobby quick play")
Check(lobbyFlow.State() = EOnlineFlowState.Searching, "quick play searches")
lobbyService.CompleteSearch(New IOnlineLobby[0])
lobbyFlow.Pump()
Check(lobbyService.findCount = 1, "search provider once")
Check(lobbyService.createCount = 1, "create after empty search")
Check(lobbyFlow.State() = EOnlineFlowState.WaitingForPlayers, "wait in created lobby")

lobbyService.AddRemotePlayer()
lobbyFlow.Pump()
Check(lobbyFlow.State() = EOnlineFlowState.StartingMatch, "start at minimum players")
Check(lobbyService.startRequestId <> 0, "provider match start")
lobbyService.CompleteMatch(lobbyService.startRequestId)
lobbyFlow.Pump()
Check(lobbyFlow.State() = EOnlineFlowState.MatchReady, "lobby match ready")
Check(HasFlowEvent(lobbyFlow, EOnlineFlowEventKind.MatchReady), "match-ready event")
Local launch:TOnlineMatchLaunch = lobbyFlow.TakeMatch()
Check(launch And launch.IsValid(), "take ready launch")
Check(launch.Info().IsSessionHost(), "host match information")
Check(lobbyFlow.TakeMatch() = Null, "take match only once")
Check(lobbyFlow.State() = EOnlineFlowState.InMatch, "in-match state")

Local matchmakingCapabilities:EOnlineCapability = EOnlineCapability.CreateLobby | EOnlineCapability.FindLobbies | EOnlineCapability.Matchmaking | EOnlineCapability.MatchTransport
Local matchmakingService:TMockOnlineService = New TMockOnlineService(matchmakingCapabilities)
Local matchmakingFlow:TOnlineFlowCoordinator = TOnlineFlowCoordinator.Create(matchmakingService)
OpenFlow(matchmakingFlow)
Check(matchmakingFlow.QuickPlay(New TOnlineFlowRequest), "begin native matchmaking")
Check(matchmakingService.matchmakingCount = 1, "prefer native matchmaking")
Check(matchmakingService.findCount = 0, "do not search when matchmaking is preferred")
matchmakingService.CompleteMatch(matchmakingService.matchmakingRequestId, False)
matchmakingFlow.Pump()
launch = matchmakingFlow.TakeMatch()
Check(launch And Not launch.Info().IsSessionHost(), "matchmaking client launch")

Local cancelService:TMockOnlineService = New TMockOnlineService(EOnlineCapability.Matchmaking | EOnlineCapability.MatchTransport)
Local cancelFlow:TOnlineFlowCoordinator = TOnlineFlowCoordinator.Create(cancelService)
OpenFlow(cancelFlow)
Check(cancelFlow.QuickPlay(New TOnlineFlowRequest), "begin cancellable matchmaking")
cancelFlow.Pump()
Check(cancelFlow.Cancel(), "cancel native matchmaking")
cancelFlow.Pump()
Check(cancelFlow.State() = EOnlineFlowState.Ready, "cancel returns to ready")
Check(HasFlowEvent(cancelFlow, EOnlineFlowEventKind.Cancelled), "cancel event")

Local manualService:TMockOnlineService = New TMockOnlineService(lobbyCapabilities)
Local manualFlow:TOnlineFlowCoordinator = TOnlineFlowCoordinator.Create(manualService)
OpenFlow(manualFlow)
Local manualRequest:TOnlineFlowRequest = New TOnlineFlowRequest
manualRequest.lobbyOptions.minPlayers = 2
manualRequest.lobbyOptions.maxPlayers = 2
manualRequest.startPolicy = EOnlineFlowStartPolicy.Manual
Check(manualFlow.Host(manualRequest), "host manual-start lobby")
manualFlow.Pump()
manualService.AddRemotePlayer()
manualFlow.Pump()
Check(manualFlow.State() = EOnlineFlowState.WaitingForPlayers, "manual policy keeps waiting")
Check(manualService.startRequestId = 0, "manual policy does not start provider")
Check(manualFlow.StartMatch(), "manual match start")
Check(manualFlow.State() = EOnlineFlowState.StartingMatch, "manual starting state")

Local findService:TMockOnlineService = New TMockOnlineService(EOnlineCapability.FindLobbies | EOnlineCapability.MatchTransport)
Local findFlow:TOnlineFlowCoordinator = TOnlineFlowCoordinator.Create(findService)
OpenFlow(findFlow)
Local findRequest:TOnlineFlowRequest = New TOnlineFlowRequest
findRequest.createIfNoLobby = False
Check(findFlow.FindAndJoin(findRequest), "begin find-only flow")
findService.CompleteSearch(New IOnlineLobby[0])
findFlow.Pump()
Check(findFlow.State() = EOnlineFlowState.Ready, "empty search returns to ready")
Check(HasFlowEvent(findFlow, EOnlineFlowEventKind.NoMatchFound), "empty search event")

Local inviteService:TMockOnlineService = New TMockOnlineService(lobbyCapabilities)
Local inviteFlow:TOnlineFlowCoordinator = TOnlineFlowCoordinator.Create(inviteService)
OpenFlow(inviteFlow)
inviteService.SendInvitation("invite-1")
inviteFlow.Pump()
Check(HasFlowEvent(inviteFlow, EOnlineFlowEventKind.InvitationReceived), "forward invitation")
Local inviteRequest:TOnlineFlowRequest = New TOnlineFlowRequest
inviteRequest.lobbyOptions.minPlayers = 2
Check(inviteFlow.AcceptInvitation("invite-1", inviteRequest), "accept invitation")
inviteFlow.Pump()
Check(inviteService.acceptedInvitation = "invite-1", "provider invitation identifier")
Check(inviteFlow.State() = EOnlineFlowState.WaitingForPlayers, "accepted invitation joins lobby")

Print "GameNet.OnlineFlow tests passed"
