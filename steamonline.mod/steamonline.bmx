' Copyright (c) 2026 Bruce A Henderson and contributors
'
' This software is provided 'as-is', without any express or implied warranty.
' Permission is granted to use, alter, and redistribute this software under
' the zlib/libpng licence. This notice must not be removed.

SuperStrict

Rem
bbdoc: Steam lobby provider for GameNet.Online.
End Rem
Module GameNet.SteamOnline

?bmxng2

ModuleInfo "Version: 0.4"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"
ModuleInfo "History: 0.4 Added known dedicated-server routing through Steam lobbies"
ModuleInfo "History: 0.3 Added an optional Steam Networking Sockets transport"
ModuleInfo "History: 0.2 Added a testable Steam backend boundary and provider flow tests"
ModuleInfo "History: 0.1 Initial Steam lobby provider"

?bmxng2 And Not android And Not ios

Import GameNet.Online
Import GameNet.Steam
Import GameNet.SteamSockets
Import Steam.SteamSDK

Const STEAM_ONLINE_EVENT_CAPACITY:Int = 64
Const STEAM_ONLINE_NAME_KEY:String = "gamenet.name"
Const STEAM_ONLINE_START_KEY:String = "gamenet.start"
Const STEAM_ONLINE_JOINABLE_KEY:String = "gamenet.joinable"
Const STEAM_ONLINE_DEDICATED_KEY:String = "gamenet.dedicated"

Rem
bbdoc: Steam networking implementation used for a lobby match.
about: NetworkingMessages preserves the original peer-message transport.
NetworkingSockets gives the lobby owner a P2P listen socket and connects every
other member to it through Steam's connection-oriented networking API.
End Rem
Enum ESteamOnlineTransportKind:Byte
	NetworkingMessages
	NetworkingSockets
End Enum

Rem
bbdoc: Steam operations consumed by #TSteamOnlineService.
about: Applications normally use the built-in implementation. The interface is
public so provider behaviour can be tested without a running Steam client.
End Rem
Interface ISteamOnlineBackend
	Method Initialize:Int()
	Method Pump()
	Method SetListener(listener:ISteamMatchmakingListener)
	Method LocalSteamId:ULong()
	Method PersonaName:String(steamId:ULong, local:Int)
	Method LaunchCommandLine:String()
	Method CreateLobby(lobbyType:ELobbyType, maximumPlayers:Int)
	Method AddStringFilter(key:String, value:String)
	Method AddSlotsFilter(openSlots:Int)
	Method AddResultCountFilter(maximumResults:Int)
	Method RequestLobbyList()
	Method LobbyByIndex:ULong(index:Int)
	Method LobbyData:String(lobbyId:ULong, key:String)
	Method LobbyDataCount:Int(lobbyId:ULong)
	Method LobbyDataByIndex:Int(lobbyId:ULong, index:Int, key:String Var, value:String Var)
	Method SetLobbyData:Int(lobbyId:ULong, key:String, value:String)
	Method LobbyOwner:ULong(lobbyId:ULong)
	Method LobbyMemberLimit:Int(lobbyId:ULong)
	Method LobbyMemberCount:Int(lobbyId:ULong)
	Method LobbyMember:ULong(lobbyId:ULong, index:Int)
	Method SetLobbyJoinable:Int(lobbyId:ULong, joinable:Int)
	Method InviteUser:Int(lobbyId:ULong, steamId:ULong)
	Method JoinLobby(lobbyId:ULong)
	Method LeaveLobby(lobbyId:ULong)
	Method ShowInviteDialog(lobbyId:ULong)
	Method SetLobbyGameServer(lobbyId:ULong, ip:UInt, port:Short, steamId:ULong)
	Method GetLobbyGameServer:Int(lobbyId:ULong, ip:UInt Var, port:Short Var, steamId:ULong Var)
	Method CreateTransport:INetTransport(steamIds:ULong[], host:Int, channelCount:Int, maxPacketSize:Size_T)
	Method CreateDedicatedTransport:INetTransport(ip:UInt, port:Int, steamId:ULong, channelCount:Int, maxPacketSize:Size_T)
End Interface

Private

Function SteamIPv4String:String(ip:UInt)
	Return ((ip Shr 24) & 255) + "." + ((ip Shr 16) & 255) + "." + ((ip Shr 8) & 255) + "." + (ip & 255)
End Function

Type TNativeSteamOnlineBackend Implements ISteamOnlineBackend
	Field client:TSteamClient
	Field user:TSteamUser
	Field apps:TSteamApps
	Field friends:TSteamFriends
	Field matchmaking:TSteamMatchmaking
	Field networkingUtils:TSteamNetworkingUtils
	Field transportKind:ESteamOnlineTransportKind

	Method New(transportKind:ESteamOnlineTransportKind)
		Self.transportKind = transportKind
	End Method

	Method Initialize:Int()
		If Not SteamInit(False) Then Return False
		SteamSetAutoRunCallbacks(False)
		client = New TSteamClient
		user = client.GetISteamUser()
		apps = client.GetISteamApps()
		friends = client.GetISteamFriends()
		matchmaking = client.GetISteamMatchmaking()
		If transportKind = ESteamOnlineTransportKind.NetworkingSockets Then
			networkingUtils = TSteamNetworkingUtils.Create()
			If networkingUtils Then networkingUtils.InitRelayNetworkAccess()
		End If
		Return user And apps And friends And matchmaking And user.BLoggedOn()
	End Method

	Method Pump()
		SteamRunCallbacks()
	End Method
	Method SetListener(listener:ISteamMatchmakingListener)
		If matchmaking Then matchmaking.SetListener(listener)
	End Method
	Method LocalSteamId:ULong()
		Return user.GetSteamID()
	End Method
	Method PersonaName:String(steamId:ULong, local:Int)
		If local Then Return friends.GetPersonaName()
		Return friends.GetFriendPersonaName(steamId)
	End Method
	Method LaunchCommandLine:String()
		Return apps.GetLaunchCommandLine()
	End Method

	Method CreateLobby(lobbyType:ELobbyType, maximumPlayers:Int)
		matchmaking.CreateLobby(lobbyType, maximumPlayers)
	End Method

	Method AddStringFilter(key:String, value:String)
		matchmaking.AddRequestLobbyListStringFilter(key, value)
	End Method

	Method AddSlotsFilter(openSlots:Int)
		matchmaking.AddRequestLobbyListFilterSlotsAvailable(openSlots)
	End Method

	Method AddResultCountFilter(maximumResults:Int)
		matchmaking.AddRequestLobbyListResultCountFilter(maximumResults)
	End Method

	Method RequestLobbyList()
		matchmaking.RequestLobbyList()
	End Method

	Method LobbyByIndex:ULong(index:Int)
		Return matchmaking.GetLobbyByIndex(index)
	End Method

	Method LobbyData:String(lobbyId:ULong, key:String)
		Return matchmaking.GetLobbyData(lobbyId, key)
	End Method

	Method LobbyDataCount:Int(lobbyId:ULong)
		Return matchmaking.GetLobbyDataCount(lobbyId)
	End Method

	Method LobbyDataByIndex:Int(lobbyId:ULong, index:Int, key:String Var, value:String Var)
		Return matchmaking.GetLobbyDataByIndex(lobbyId, index, key, value)
	End Method

	Method SetLobbyData:Int(lobbyId:ULong, key:String, value:String)
		Return matchmaking.SetLobbyData(lobbyId, key, value)
	End Method

	Method LobbyOwner:ULong(lobbyId:ULong)
		Return matchmaking.GetLobbyOwner(lobbyId)
	End Method

	Method LobbyMemberLimit:Int(lobbyId:ULong)
		Return matchmaking.GetLobbyMemberLimit(lobbyId)
	End Method

	Method LobbyMemberCount:Int(lobbyId:ULong)
		Return matchmaking.GetNumLobbyMembers(lobbyId)
	End Method

	Method LobbyMember:ULong(lobbyId:ULong, index:Int)
		Return matchmaking.GetLobbyMemberByIndex(lobbyId, index)
	End Method

	Method SetLobbyJoinable:Int(lobbyId:ULong, joinable:Int)
		Return matchmaking.SetLobbyJoinable(lobbyId, joinable)
	End Method

	Method InviteUser:Int(lobbyId:ULong, steamId:ULong)
		Return matchmaking.InviteUserToLobby(lobbyId, steamId)
	End Method

	Method JoinLobby(lobbyId:ULong)
		matchmaking.JoinLobby(lobbyId)
	End Method

	Method LeaveLobby(lobbyId:ULong)
		matchmaking.LeaveLobby(lobbyId)
	End Method
	Method ShowInviteDialog(lobbyId:ULong)
		If friends Then friends.ActivateGameOverlayInviteDialog(lobbyId)
	End Method
	Method SetLobbyGameServer(lobbyId:ULong, ip:UInt, port:Short, steamId:ULong)
		matchmaking.SetLobbyGameServer(lobbyId, ip, port, steamId)
	End Method
	Method GetLobbyGameServer:Int(lobbyId:ULong, ip:UInt Var, port:Short Var, steamId:ULong Var)
		Return matchmaking.GetLobbyGameServer(lobbyId, ip, port, steamId)
	End Method
	Method CreateTransport:INetTransport(steamIds:ULong[], host:Int, channelCount:Int, maxPacketSize:Size_T)
		If transportKind = ESteamOnlineTransportKind.NetworkingSockets Then
			If host Then
				Return TSteamSocketsTransport.ListenP2P(0, steamIds.Length, channelCount, maxPacketSize)
			End If
			If steamIds.Length <> 1 Then Return Null
			Return TSteamSocketsTransport.ConnectP2P(steamIds[0], 0, channelCount, maxPacketSize)
		End If
		Return TSteamTransport.Create(steamIds, channelCount, maxPacketSize)
	End Method
	Method CreateDedicatedTransport:INetTransport(ip:UInt, port:Int, steamId:ULong, channelCount:Int, maxPacketSize:Size_T)
		If ip Then
			Return TSteamSocketsTransport.ConnectIP(SteamIPv4String(ip), port, channelCount, maxPacketSize)
		End If
		If steamId Then
			Return TSteamSocketsTransport.ConnectP2P(steamId, 0, channelCount, maxPacketSize)
		End If
		Return Null
	End Method
End Type

Public

Type TSteamOnlineLobby Implements IOnlineLobby
	Field lobbyId:String
	Field lobbyName:String
	Field lobbyOwner:SOnlinePlayer
	Field maximumPlayers:Int
	Field joinable:Int
	Field members:SOnlinePlayer[] = New SOnlinePlayer[0]
	Field metadata:TOnlineProperties = New TOnlineProperties

	Method Id:String() Override
		Return lobbyId
	End Method

	Method Name:String() Override
		Return lobbyName
	End Method

	Method Owner:SOnlinePlayer() Override
		Return lobbyOwner
	End Method

	Method MaxPlayers:Int() Override
		Return maximumPlayers
	End Method

	Method IsJoinable:Int() Override
		Return joinable
	End Method

	Method MemberCount:Int() Override
		Return members.Length
	End Method
	Method Member:SOnlinePlayer(index:Int) Override
		If index < 0 Or index >= members.Length Then Return New SOnlinePlayer
		Return members[index]
	End Method
	Method Properties:TOnlineProperties() Override
		Return metadata
	End Method
End Type

Type TSteamOnlineService Implements IOnlineService, ISteamMatchmakingListener
	Private
	Field _state:EOnlineServiceState
	Field _nextRequestId:UInt = 1
	Field _openRequestId:UInt
	Field _backend:ISteamOnlineBackend
	Field _localSteamId:ULong
	Field _events:SOnlineEvent[] = New SOnlineEvent[STEAM_ONLINE_EVENT_CAPACITY]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _droppedEvents:UInt
	Field _createRequestId:UInt
	Field _createOptions:TOnlineLobbyOptions
	Field _findRequestId:UInt
	Field _findResults:IOnlineLobby[] = New IOnlineLobby[0]
	Field _findResultsRequestId:UInt
	Field _joinRequestId:UInt
	Field _leaveRequestId:UInt
	Field _currentLobbyId:ULong
	Field _currentLobby:IOnlineLobby
	Field _startRequestId:UInt
	Field _readyRequestId:UInt
	Field _readyTransport:INetTransport
	Field _readyMatchInfo:SOnlineMatchInfo
	Field _channelCount:Int
	Field _maxPacketSize:Size_T

	Method New(backend:ISteamOnlineBackend, channelCount:Int, maxPacketSize:Size_T)
		_backend = backend
		_channelCount = channelCount
		_maxPacketSize = maxPacketSize
	End Method

	Method NextRequestId:UInt()
		Local result:UInt = _nextRequestId
		_nextRequestId :+ 1
		If _nextRequestId = 0 Then _nextRequestId = 1
		Return result
	End Method

	Method LaunchLobbyId:ULong(commandLine:String)
		Const marker:String = "+connect_lobby"
		Local start:Int = commandLine.Find(marker)
		If start < 0 Then Return 0
		start :+ marker.Length
		While start < commandLine.Length And commandLine[start] <= 32
			start :+ 1
		Wend
		Local finish:Int = start
		While finish < commandLine.Length And commandLine[finish] >= 48 And commandLine[finish] <= 57
			finish :+ 1
		Wend
		If finish = start Then Return 0
		Return commandLine[start..finish].ToULong()
	End Method

	Method Queue(event:SOnlineEvent)
		If _eventCount = _events.Length Then
			_droppedEvents :+ 1
			Return
		End If
		_events[_eventWrite] = event
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
	End Method

	Method SteamPlayer:SOnlinePlayer(steamId:ULong, local:Int = False)
		If steamId = 0 Then Return New SOnlinePlayer
		Return New SOnlinePlayer(String(steamId), _backend.PersonaName(steamId, local), local)
	End Method

	Method SnapshotLobby:TSteamOnlineLobby(lobbyId:ULong)
		If lobbyId = 0 Then Return Null
		Local result:TSteamOnlineLobby = New TSteamOnlineLobby
		result.lobbyId = String(lobbyId)
		result.lobbyName = _backend.LobbyData(lobbyId, STEAM_ONLINE_NAME_KEY)
		result.maximumPlayers = _backend.LobbyMemberLimit(lobbyId)
		result.joinable = _backend.LobbyData(lobbyId, STEAM_ONLINE_JOINABLE_KEY) <> "0"
		Local ownerId:ULong = _backend.LobbyOwner(lobbyId)
		result.lobbyOwner = SteamPlayer(ownerId, ownerId = _localSteamId)
		Local count:Int = _backend.LobbyMemberCount(lobbyId)
		result.members = New SOnlinePlayer[count]
		For Local index:Int = 0 Until count
			Local memberId:ULong = _backend.LobbyMember(lobbyId, index)
			result.members[index] = SteamPlayer(memberId, memberId = _localSteamId)
		Next
		Local propertyCount:Int = _backend.LobbyDataCount(lobbyId)
		For Local index:Int = 0 Until propertyCount
			Local key:String
			Local value:String
			If _backend.LobbyDataByIndex(lobbyId, index, key, value) Then result.metadata.Set(key, value)
		Next
		Return result
	End Method

	Method RefreshCurrentLobby()
		If _currentLobbyId Then _currentLobby = SnapshotLobby(_currentLobbyId) Else _currentLobby = Null
	End Method

	Method PrepareMatch(requestId:UInt)
		If requestId = 0 Or _currentLobbyId = 0 Or _readyTransport Then Return
		Local memberCount:Int = _backend.LobbyMemberCount(_currentLobbyId)
		If memberCount < 1 Then Return
		Local serverIP:UInt
		Local serverPort:Short
		Local serverSteamId:ULong
		Local startMode:String = _backend.LobbyData(_currentLobbyId, STEAM_ONLINE_START_KEY)
		Local dedicated:Int = _backend.LobbyData(_currentLobbyId, STEAM_ONLINE_DEDICATED_KEY) = "1" Or startMode = "dedicated"
		If dedicated Then
			If Not _backend.GetLobbyGameServer(_currentLobbyId, serverIP, serverPort, serverSteamId) Then Return
			If Not serverIP And Not serverSteamId Then Return
			_readyTransport = _backend.CreateDedicatedTransport(serverIP, Int(serverPort) & $ffff, serverSteamId, _channelCount, _maxPacketSize)
			If Not _readyTransport Then
				Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, EOnlineOperation.StartMatch, requestId, EOnlineError.ProviderFailure, 0, String(_currentLobbyId), New SOnlinePlayer, "Could not connect to the Steam dedicated server"))
				_startRequestId = 0
				Return
			End If
			_readyMatchInfo = New SOnlineMatchInfo(memberCount, False, New SNetPeer(1, 1))
			_readyRequestId = requestId
			_startRequestId = 0
			Queue(New SOnlineEvent(EOnlineEventKind.MatchReady, EOnlineOperation.StartMatch, requestId, EOnlineError.None, 0, String(_currentLobbyId), New SOnlinePlayer, ""))
			Return
		End If
		Local ownerId:ULong = _backend.LobbyOwner(_currentLobbyId)
		If ownerId = 0 Or memberCount < 2 Then Return
		Local host:Int = ownerId = _localSteamId
		Local remoteIds:ULong[]
		If host Then
			remoteIds = New ULong[memberCount - 1]
			Local remoteIndex:Int
			For Local index:Int = 0 Until memberCount
				Local memberId:ULong = _backend.LobbyMember(_currentLobbyId, index)
				If memberId <> _localSteamId Then
					remoteIds[remoteIndex] = memberId
					remoteIndex :+ 1
				End If
			Next
		Else
			remoteIds = [ownerId]
		End If
		_readyTransport = _backend.CreateTransport(remoteIds, host, _channelCount, _maxPacketSize)
		If Not _readyTransport Then
			Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, EOnlineOperation.StartMatch, requestId, EOnlineError.ProviderFailure, 0, String(_currentLobbyId), New SOnlinePlayer, "Could not create Steam transport"))
			_startRequestId = 0
			Return
		End If
		Local hostPeer:SNetPeer
		If Not host Then hostPeer = New SNetPeer(1, 1)
		_readyMatchInfo = New SOnlineMatchInfo(memberCount, host, hostPeer)
		_readyRequestId = requestId
		_startRequestId = 0
		Queue(New SOnlineEvent(EOnlineEventKind.MatchReady, EOnlineOperation.StartMatch, requestId, EOnlineError.None, 0, String(_currentLobbyId), New SOnlinePlayer, ""))
	End Method

	Public
	Function Create:TSteamOnlineService(channelCount:Int = 4, maxPacketSize:Size_T = STEAM_DEFAULT_MAX_PACKET_SIZE, transportKind:ESteamOnlineTransportKind = ESteamOnlineTransportKind.NetworkingMessages)
		If channelCount < 1 Or channelCount > 65536 Or maxPacketSize < 1 Then Return Null
		Return New TSteamOnlineService(New TNativeSteamOnlineBackend(transportKind), channelCount, maxPacketSize)
	End Function

	Rem
	bbdoc: Creates a Steam online service using a supplied backend.
	about: This is primarily useful for deterministic provider tests.
	End Rem
	Function CreateForBackend:TSteamOnlineService(backend:ISteamOnlineBackend, channelCount:Int = 4, maxPacketSize:Size_T = STEAM_DEFAULT_MAX_PACKET_SIZE)
		If Not backend Or channelCount < 1 Or channelCount > 65536 Or maxPacketSize < 1 Then Return Null
		Return New TSteamOnlineService(backend, channelCount, maxPacketSize)
	End Function

	Method ProviderName:String() Override
		Return "Steam"
	End Method

	Method Capabilities:EOnlineCapability() Override
		Return EOnlineCapability.CreateLobby | EOnlineCapability.FindLobbies | EOnlineCapability.Invitations | EOnlineCapability.MatchTransport | EOnlineCapability.DedicatedServer
	End Method

	Method State:EOnlineServiceState() Override
		Return _state
	End Method
	Method LocalPlayer:SOnlinePlayer() Override
		If _state <> EOnlineServiceState.Ready Or _localSteamId = 0 Then Return New SOnlinePlayer
		Return SteamPlayer(_localSteamId, True)
	End Method

	Method Open:UInt() Override
		If _state <> EOnlineServiceState.Closed Then Return 0
		_openRequestId = NextRequestId()
		_state = EOnlineServiceState.Opening
		If Not _backend.Initialize() Then
			_state = EOnlineServiceState.Failed
			Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, EOnlineOperation.Open, _openRequestId, EOnlineError.Authentication, 0, "", New SOnlinePlayer, "Steam is not running or the application is unavailable"))
			Return _openRequestId
		End If
		_backend.SetListener(Self)
		_localSteamId = _backend.LocalSteamId()
		_state = EOnlineServiceState.Ready
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceReady, EOnlineOperation.Open, _openRequestId, EOnlineError.None, 0, "", SteamPlayer(_localSteamId, True), ""))
		Local launchedLobbyId:ULong = LaunchLobbyId(_backend.LaunchCommandLine())
		If launchedLobbyId Then Queue(New SOnlineEvent(EOnlineEventKind.InvitationReceived, EOnlineOperation.None, 0, EOnlineError.None, 0, String(launchedLobbyId), New SOnlinePlayer, "Steam launch invitation accepted"))
		Return _openRequestId
	End Method

	Method Pump() Override
		If _state <> EOnlineServiceState.Closed Then _backend.Pump()
		If _startRequestId And _currentLobbyId And _backend.LobbyOwner(_currentLobbyId) <> _localSteamId Then
			Local startMode:String = _backend.LobbyData(_currentLobbyId, STEAM_ONLINE_START_KEY)
			If startMode = "1" Or startMode = "dedicated" Then PrepareMatch(_startRequestId)
		End If
	End Method

	Method Poll:Int(event:SOnlineEvent Var) Override
		If _eventCount = 0 Then event = New SOnlineEvent; Return False
		event = _events[_eventRead]
		_events[_eventRead] = New SOnlineEvent
		_eventRead = (_eventRead + 1) Mod _events.Length
		_eventCount :- 1
		Return True
	End Method

	Method CreateLobby:UInt(options:TOnlineLobbyOptions) Override
		If _state <> EOnlineServiceState.Ready Or Not options Or _currentLobbyId Or _createRequestId Or options.maxPlayers < 1 Or options.maxPlayers > 250 Then Return 0
		_createRequestId = NextRequestId()
		_createOptions = options
		Local lobbyType:ELobbyType = ELobbyType.k_ELobbyTypePrivate
		Select options.visibility
			Case EOnlineLobbyVisibility.FriendsOnly lobbyType = ELobbyType.k_ELobbyTypeFriendsOnly
			Case EOnlineLobbyVisibility.Public lobbyType = ELobbyType.k_ELobbyTypePublic
		End Select
		_backend.CreateLobby(lobbyType, options.maxPlayers)
		Return _createRequestId
	End Method

	Method FindLobbies:UInt(query:TOnlineLobbyQuery) Override
		If _state <> EOnlineServiceState.Ready Or Not query Or _findRequestId Then Return 0
		_findRequestId = NextRequestId()
		For Local index:Int = 0 Until query.properties.Count()
			_backend.AddStringFilter(query.properties.KeyAt(index), query.properties.ValueAt(index))
		Next
		If query.requiredOpenSlots > 0 Then _backend.AddSlotsFilter(query.requiredOpenSlots)
		_backend.AddResultCountFilter(query.maximumResults)
		_backend.RequestLobbyList()
		Return _findRequestId
	End Method

	Method LobbyResultCount:Int(requestId:UInt) Override
		If requestId = _findResultsRequestId Then Return _findResults.Length
		Return 0
	End Method

	Method LobbyResult:IOnlineLobby(requestId:UInt, index:Int) Override
		If requestId = _findResultsRequestId And index >= 0 And index < _findResults.Length Then Return _findResults[index]
		Return Null
	End Method

	Method CurrentLobby:IOnlineLobby() Override
		Return _currentLobby
	End Method

	Rem
	bbdoc: Opens Steam's friend invitation overlay for the current lobby.
	End Rem
	Method ShowInviteDialog:Int()
		If _state <> EOnlineServiceState.Ready Or _currentLobbyId = 0 Then Return False
		_backend.ShowInviteDialog(_currentLobbyId)
		Return True
	End Method

	Rem
	bbdoc: Invites a known Steam player to the current lobby without opening the overlay.
	End Rem
	Method InvitePlayer:Int(playerId:String)
		If _state <> EOnlineServiceState.Ready Or _currentLobbyId = 0 Then Return False
		Local steamId:ULong = playerId.ToULong()
		If steamId = 0 Then Return False
		Return _backend.InviteUser(_currentLobbyId, steamId)
	End Method

	Rem
	bbdoc: Publishes a known dedicated server for the current lobby.
	about: Only the lobby owner may call this. @address must be a numeric IPv4
	address when supplied. Use an empty address with a nonzero Steam game-server
	identity for a P2P Sockets server. Server allocation and hosted-SDR tickets
	remain the responsibility of an external hosting or coordination service.
	End Rem
	Method SetDedicatedServer:Int(address:String, port:Int, steamId:ULong = 0)
		If _state <> EOnlineServiceState.Ready Or _currentLobbyId = 0 Or _backend.LobbyOwner(_currentLobbyId) <> _localSteamId Then Return False
		If port < 0 Or port > 65535 Then Return False
		Local ip:UInt
		If address.Length Then
			Local parts:String[] = address.Split(".")
			If parts.Length <> 4 Then Return False
			For Local part:String = EachIn parts
				If part.Length = 0 Then Return False
				For Local index:Int = 0 Until part.Length
					If part[index] < 48 Or part[index] > 57 Then Return False
				Next
				Local component:Int = part.ToInt()
				If component < 0 Or component > 255 Then Return False
				ip = (ip Shl 8) | UInt(component)
			Next
			If ip = 0 Or port = 0 Then Return False
		Else If steamId = 0 Then
			Return False
		End If
		If Not _backend.SetLobbyData(_currentLobbyId, STEAM_ONLINE_DEDICATED_KEY, "1") Then Return False
		_backend.SetLobbyGameServer(_currentLobbyId, ip, Short(port), steamId)
		Return True
	End Method

	Method JoinLobby:UInt(lobbyId:String) Override
		If _state <> EOnlineServiceState.Ready Or _currentLobbyId Or _joinRequestId Then Return 0
		Local nativeId:ULong = lobbyId.ToULong()
		If nativeId = 0 Then Return 0
		_joinRequestId = NextRequestId()
		_backend.JoinLobby(nativeId)
		Return _joinRequestId
	End Method

	Method LeaveLobby:UInt() Override
		If _currentLobbyId = 0 Then Return 0
		Local requestId:UInt = NextRequestId()
		Local subject:String = String(_currentLobbyId)
		_backend.LeaveLobby(_currentLobbyId)
		_currentLobbyId = 0
		_currentLobby = Null
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyLeft, EOnlineOperation.LeaveLobby, requestId, EOnlineError.None, 0, subject, New SOnlinePlayer, ""))
		Return requestId
	End Method

	Method AcceptInvitation:UInt(invitationId:String) Override
		Return JoinLobby(invitationId)
	End Method

	Method StartMatchmaking:UInt(request:TOnlineMatchmakingRequest) Override
		Return 0
	End Method

	Method CancelMatchmaking:UInt(requestId:UInt) Override
		Return 0
	End Method

	Method StartMatch:UInt() Override
		If _currentLobbyId = 0 Or _startRequestId Or _readyTransport Then Return 0
		Local requestId:UInt = NextRequestId()
		_startRequestId = requestId
		If _backend.LobbyOwner(_currentLobbyId) = _localSteamId Then
			_backend.SetLobbyJoinable(_currentLobbyId, False)
			_backend.SetLobbyData(_currentLobbyId, STEAM_ONLINE_JOINABLE_KEY, "0")
			Local startMode:String = "1"
			If _backend.LobbyData(_currentLobbyId, STEAM_ONLINE_DEDICATED_KEY) = "1" Then startMode = "dedicated"
			_backend.SetLobbyData(_currentLobbyId, STEAM_ONLINE_START_KEY, startMode)
			PrepareMatch(_startRequestId)
		Else
			Local startMode:String = _backend.LobbyData(_currentLobbyId, STEAM_ONLINE_START_KEY)
			If startMode = "1" Or startMode = "dedicated" Then PrepareMatch(_startRequestId)
		End If
		Return requestId
	End Method

	Method MatchInfo:Int(requestId:UInt, info:SOnlineMatchInfo Var) Override
		If requestId = 0 Or requestId <> _readyRequestId Or Not _readyTransport Then info = New SOnlineMatchInfo; Return False
		info = _readyMatchInfo
		Return True
	End Method

	Method TakeMatchTransport:INetTransport(requestId:UInt) Override
		If requestId = 0 Or requestId <> _readyRequestId Or Not _readyTransport Then Return Null
		Local result:INetTransport = _readyTransport
		_readyTransport = Null
		_readyRequestId = 0
		_readyMatchInfo = New SOnlineMatchInfo
		Return result
	End Method

	Method Close:UInt() Override
		If _state = EOnlineServiceState.Closed Or _state = EOnlineServiceState.Closing Then Return 0
		Local requestId:UInt = NextRequestId()
		_state = EOnlineServiceState.Closing
		If _readyTransport Then _readyTransport.Close()
		If _currentLobbyId Then _backend.LeaveLobby(_currentLobbyId)
		_backend.SetListener(Null)
		_currentLobbyId = 0
		_currentLobby = Null
		_readyTransport = Null
		_state = EOnlineServiceState.Closed
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceClosed, EOnlineOperation.Close, requestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return requestId
	End Method

	Method OnLobbyCreated(result:EResult, steamIDLobby:ULong, ioFailure:Int) Override
		Local requestId:UInt = _createRequestId
		_createRequestId = 0
		If ioFailure Or result <> EResult.k_EResultOK Or steamIDLobby = 0 Then
			Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, EOnlineOperation.CreateLobby, requestId, EOnlineError.ProviderFailure, Int(result), "", New SOnlinePlayer, "Steam could not create the lobby"))
			_createOptions = Null
			Return
		End If
		_currentLobbyId = steamIDLobby
		_backend.SetLobbyData(steamIDLobby, STEAM_ONLINE_NAME_KEY, _createOptions.name)
		_backend.SetLobbyJoinable(steamIDLobby, _createOptions.joinable)
		_backend.SetLobbyData(steamIDLobby, STEAM_ONLINE_JOINABLE_KEY, String(Int(_createOptions.joinable <> 0)))
		For Local index:Int = 0 Until _createOptions.properties.Count()
			_backend.SetLobbyData(steamIDLobby, _createOptions.properties.KeyAt(index), _createOptions.properties.ValueAt(index))
		Next
		RefreshCurrentLobby()
		_createOptions = Null
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyCreated, EOnlineOperation.CreateLobby, requestId, EOnlineError.None, 0, String(steamIDLobby), New SOnlinePlayer, ""))
	End Method

	Method OnLobbyMatchList(lobbyCount:UInt, ioFailure:Int) Override
		Local requestId:UInt = _findRequestId
		_findRequestId = 0
		If ioFailure Then
			Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, EOnlineOperation.FindLobbies, requestId, EOnlineError.Network, 0, "", New SOnlinePlayer, "Steam lobby search failed"))
			Return
		End If
		_findResults = New IOnlineLobby[Int(lobbyCount)]
		For Local index:Int = 0 Until Int(lobbyCount)
			_findResults[index] = SnapshotLobby(_backend.LobbyByIndex(index))
		Next
		_findResultsRequestId = requestId
		Queue(New SOnlineEvent(EOnlineEventKind.LobbySearchCompleted, EOnlineOperation.FindLobbies, requestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
	End Method

	Method OnLobbyEnter(steamIDLobby:ULong, locked:Int, response:EChatRoomEnterResponse) Override
		If response <> EChatRoomEnterResponse.k_EChatRoomEnterResponseSuccess Then
			Local requestId:UInt = _joinRequestId
			_joinRequestId = 0
			Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, EOnlineOperation.JoinLobby, requestId, EOnlineError.Rejected, Int(response), String(steamIDLobby), New SOnlinePlayer, "Steam rejected the lobby join"))
			Return
		End If
		_currentLobbyId = steamIDLobby
		RefreshCurrentLobby()
		If _joinRequestId Then
			Local requestId:UInt = _joinRequestId
			_joinRequestId = 0
			Queue(New SOnlineEvent(EOnlineEventKind.LobbyJoined, EOnlineOperation.JoinLobby, requestId, EOnlineError.None, 0, String(steamIDLobby), New SOnlinePlayer, ""))
		End If
	End Method

	Method OnLobbyDataUpdate(steamIDLobby:ULong, steamIDMember:ULong, success:Int) Override
		If steamIDLobby <> _currentLobbyId Then Return
		RefreshCurrentLobby()
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyChanged, EOnlineOperation.None, 0, EOnlineError.None, 0, String(steamIDLobby), SteamPlayer(steamIDMember, steamIDMember = _localSteamId), ""))
	End Method

	Method OnLobbyChatUpdate(steamIDLobby:ULong, steamIDUserChanged:ULong, steamIDMakingChange:ULong, stateChange:EChatMemberStateChange) Override
		If steamIDLobby <> _currentLobbyId Then Return
		RefreshCurrentLobby()
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyChanged, EOnlineOperation.None, 0, EOnlineError.None, Int(stateChange), String(steamIDLobby), SteamPlayer(steamIDUserChanged, steamIDUserChanged = _localSteamId), ""))
	End Method

	Method OnLobbyChatMessage(steamIDLobby:ULong, steamIDUser:ULong, chatEntryType:EChatEntryType, chatID:UInt) Override
	End Method

	Method OnLobbyGameCreated(steamIDLobby:ULong, steamIDGameServer:ULong, ip:UInt, port:Short) Override
		If steamIDLobby <> _currentLobbyId Then Return
		RefreshCurrentLobby()
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyChanged, EOnlineOperation.None, 0, EOnlineError.None, 0, String(steamIDLobby), New SOnlinePlayer, "Dedicated server assigned"))
	End Method

	Method OnLobbyInvite(steamIDUser:ULong, steamIDLobby:ULong, gameID:ULong) Override
		Queue(New SOnlineEvent(EOnlineEventKind.InvitationReceived, EOnlineOperation.None, 0, EOnlineError.None, 0, String(steamIDLobby), SteamPlayer(steamIDUser), ""))
	End Method

	Method OnLobbyJoinRequested(steamIDLobby:ULong, steamIDFriend:ULong) Override
		Queue(New SOnlineEvent(EOnlineEventKind.InvitationReceived, EOnlineOperation.None, 0, EOnlineError.None, 0, String(steamIDLobby), SteamPlayer(steamIDFriend), "Steam invitation accepted"))
	End Method

	Method DroppedEvents:UInt()
		Return _droppedEvents
	End Method
End Type

?
