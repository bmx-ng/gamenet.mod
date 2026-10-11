SuperStrict

Framework BRL.StandardIO
Import GameNet.Online

Type TContractService Implements IOnlineService
	Method ProviderName:String() Override Return "test" End Method
	Method Capabilities:EOnlineCapability() Override Return EOnlineCapability.None End Method
	Method State:EOnlineServiceState() Override Return EOnlineServiceState.Closed End Method
	Method LocalPlayer:SOnlinePlayer() Override Return New SOnlinePlayer End Method
	Method Open:UInt() Override Return 0 End Method
	Method Pump() Override End Method
	Method Poll:Int(event:SOnlineEvent Var) Override Return False End Method
	Method CreateLobby:UInt(options:TOnlineLobbyOptions) Override Return 0 End Method
	Method FindLobbies:UInt(query:TOnlineLobbyQuery) Override Return 0 End Method
	Method LobbyResultCount:Int(requestId:UInt) Override Return 0 End Method
	Method LobbyResult:IOnlineLobby(requestId:UInt, index:Int) Override Return Null End Method
	Method CurrentLobby:IOnlineLobby() Override Return Null End Method
	Method JoinLobby:UInt(lobbyId:String) Override Return 0 End Method
	Method LeaveLobby:UInt() Override Return 0 End Method
	Method AcceptInvitation:UInt(invitationId:String) Override Return 0 End Method
	Method StartMatchmaking:UInt(request:TOnlineMatchmakingRequest) Override Return 0 End Method
	Method CancelMatchmaking:UInt(requestId:UInt) Override Return 0 End Method
	Method StartMatch:UInt() Override Return 0 End Method
	Method MatchInfo:Int(requestId:UInt, info:SOnlineMatchInfo Var) Override Return False End Method
	Method TakeMatchTransport:INetTransport(requestId:UInt) Override Return Null End Method
	Method Close:UInt() Override Return 0 End Method
End Type

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local capabilities:EOnlineCapability = EOnlineCapability.CreateLobby | EOnlineCapability.Matchmaking | EOnlineCapability.MatchTransport
Local contract:IOnlineService = New TContractService
Check(contract.ProviderName() = "test", "service contract")
Check(OnlineHasCapabilities(capabilities, EOnlineCapability.CreateLobby), "single capability")
Check(OnlineHasCapabilities(capabilities, EOnlineCapability.CreateLobby | EOnlineCapability.MatchTransport), "combined capabilities")
Check(Not OnlineHasCapabilities(capabilities, EOnlineCapability.FindLobbies), "missing capability")

Local player:SOnlinePlayer = New SOnlinePlayer("player-1", "Player One", True)
Check(player.IsValid(), "valid player")
Check(player.Id() = "player-1" And player.DisplayName() = "Player One" And player.IsLocal(), "player values")

Local properties:TOnlineProperties = New TOnlineProperties
Check(Not properties.Set("", "invalid"), "empty property key rejected")
Check(properties.Set("mode", "duel"), "set property")
Check(properties.Set("map", "arena"), "set second property")
Check(properties.Set("mode", "teams"), "replace property")
Check(properties.Count() = 2, "property count")
Local found:Int
Check(properties.Value("mode", found) = "teams" And found, "property value")
Check(properties.Value("missing", found) = "" And Not found, "missing property")
Check(properties.KeyAt(1) = "map" And properties.ValueAt(1) = "arena", "indexed property")
properties.Clear()
Check(properties.Count() = 0, "clear properties")

Local event:SOnlineEvent = New SOnlineEvent(EOnlineEventKind.MatchReady, EOnlineOperation.StartMatchmaking, 17, EOnlineError.None, 0, "match-1", player, "")
Check(event.Kind() = EOnlineEventKind.MatchReady, "event kind")
Check(event.Operation() = EOnlineOperation.StartMatchmaking And event.RequestId() = 17, "event correlation")
Check(event.SubjectId() = "match-1" And event.Player().Id() = "player-1", "event subject")

Local hostInfo:SOnlineMatchInfo = New SOnlineMatchInfo(2, True, New SNetPeer)
Check(hostInfo.IsValid() And hostInfo.IsSessionHost() And hostInfo.PlayerCount() = 2, "host match info")
Local clientInfo:SOnlineMatchInfo = New SOnlineMatchInfo(2, False, New SNetPeer(1, 1))
Check(clientInfo.IsValid() And Not clientInfo.IsSessionHost() And clientInfo.SessionHostPeer().IsValid(), "client match info")

Print "GameNet.Online tests passed"
