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
bbdoc: GameKit provider for the optional GameNet.Online service contract.
End Rem
Module GameNet.GameKitOnline

?bmxng2

ModuleInfo "Version: 0.2"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial GameKit online provider"
ModuleInfo "History: 0.2 Added generic operation cancellation support"

?macos Or ios

Import Apple.GameKit
Import GameNet.GameKit
Import GameNet.Online

Const GAMEKIT_ONLINE_EVENT_CAPACITY:Int = 32

Private

Type TGameKitOnlineListener Implements IGameCenterListener, IGameCenterMultiplayerListener, IGameCenterIdentityListener, IGameCenterMetadataListener, IGameCenterChallengeListener, IGameCenterActivityListener, IGameCenterActivityManagementListener, IGameCenterPlayerListener, IGameCenterSavedGameListener
	Field owner:TGameKitOnlineService
	Field previous:IGameCenterListener

	Method OnGameCenterAuthenticationChanged(authenticated:Int, player:TGameCenterPlayer, error:TGameCenterError)
		owner.OnGameCenterAuthenticationChanged(authenticated, player, error)
	End Method

	Method OnGameCenterMatchFound(requestId:Int, match:TGameCenterMatch, error:TGameCenterError)
		owner.OnGameCenterMatchFound(requestId, match, error)
	End Method

	Method OnGameCenterAchievementReported(requestId:Int, identifier:String, error:TGameCenterError)
		owner.OnGameCenterAchievementReported(requestId, identifier, error)
	End Method

	Method OnGameCenterAchievementsLoaded(requestId:Int, result:TGameCenterAchievementResult, error:TGameCenterError)
		owner.OnGameCenterAchievementsLoaded(requestId, result, error)
	End Method

	Method OnGameCenterAchievementsReset(requestId:Int, error:TGameCenterError)
		owner.OnGameCenterAchievementsReset(requestId, error)
	End Method

	Method OnGameCenterScoreSubmitted(requestId:Int, leaderboardIdentifier:String, score:Long, error:TGameCenterError)
		owner.OnGameCenterScoreSubmitted(requestId, leaderboardIdentifier, score, error)
	End Method

	Method OnGameCenterLeaderboardLoaded(requestId:Int, leaderboard:TGameCenterLeaderboardResult, error:TGameCenterError)
		owner.OnGameCenterLeaderboardLoaded(requestId, leaderboard, error)
	End Method

	Method OnGameCenterViewDismissed(view:EGameCenterView)
		owner.OnGameCenterViewDismissed(view)
	End Method

	Method OnGameCenterIdentityVerificationFetched(requestId:Int, verification:TGameCenterIdentityVerification, error:TGameCenterError)
		Local listener:IGameCenterIdentityListener = IGameCenterIdentityListener(previous)
		If listener Then listener.OnGameCenterIdentityVerificationFetched(requestId, verification, error)
	End Method

	Method OnGameCenterAchievementDescriptionsLoaded(requestId:Int, result:TGameCenterAchievementDescriptionResult, error:TGameCenterError)
		Local listener:IGameCenterMetadataListener = IGameCenterMetadataListener(previous)
		If listener Then listener.OnGameCenterAchievementDescriptionsLoaded(requestId, result, error)
	End Method

	Method OnGameCenterLeaderboardsLoaded(requestId:Int, result:TGameCenterLeaderboardInfoResult, error:TGameCenterError)
		Local listener:IGameCenterMetadataListener = IGameCenterMetadataListener(previous)
		If listener Then listener.OnGameCenterLeaderboardsLoaded(requestId, result, error)
	End Method

	Method OnGameCenterLeaderboardSetsLoaded(requestId:Int, result:TGameCenterLeaderboardSetResult, error:TGameCenterError)
		Local listener:IGameCenterMetadataListener = IGameCenterMetadataListener(previous)
		If listener Then listener.OnGameCenterLeaderboardSetsLoaded(requestId, result, error)
	End Method

	Method OnGameCenterResourceImageLoaded(requestId:Int, kind:EGameCenterResourceKind, identifier:String, pngData:Byte[], error:TGameCenterError)
		Local listener:IGameCenterMetadataListener = IGameCenterMetadataListener(previous)
		If listener Then listener.OnGameCenterResourceImageLoaded(requestId, kind, identifier, pngData, error)
	End Method

	Method OnGameCenterChallengeDefinitionsLoaded(requestId:Int, result:TGameCenterChallengeDefinitionResult, error:TGameCenterError)
		Local listener:IGameCenterChallengeListener = IGameCenterChallengeListener(previous)
		If listener Then listener.OnGameCenterChallengeDefinitionsLoaded(requestId, result, error)
	End Method

	Method OnGameCenterChallengeActiveStatusLoaded(requestId:Int, identifier:String, hasActiveChallenges:Int, error:TGameCenterError)
		Local listener:IGameCenterChallengeListener = IGameCenterChallengeListener(previous)
		If listener Then listener.OnGameCenterChallengeActiveStatusLoaded(requestId, identifier, hasActiveChallenges, error)
	End Method

	Method OnGameCenterChallengeViewDismissed(requestId:Int, identifier:String, error:TGameCenterError)
		Local listener:IGameCenterChallengeListener = IGameCenterChallengeListener(previous)
		If listener Then listener.OnGameCenterChallengeViewDismissed(requestId, identifier, error)
	End Method

	Method OnGameCenterPendingActivityChecked(requestId:Int, hasPendingActivity:Int, error:TGameCenterError)
		Local listener:IGameCenterActivityListener = IGameCenterActivityListener(previous)
		If listener Then listener.OnGameCenterPendingActivityChecked(requestId, hasPendingActivity, error)
	End Method

	Method OnGameCenterWantsToPlayActivity:Int(player:TGameCenterPlayer, activity:TGameCenterActivity)
		Local listener:IGameCenterActivityListener = IGameCenterActivityListener(previous)
		If listener Then Return listener.OnGameCenterWantsToPlayActivity(player, activity)
		Return False
	End Method

	Method OnGameCenterActivityDefinitionsLoaded(requestId:Int, result:TGameCenterActivityDefinitionResult, error:TGameCenterError)
		Local listener:IGameCenterActivityManagementListener = IGameCenterActivityManagementListener(previous)
		If listener Then listener.OnGameCenterActivityDefinitionsLoaded(requestId, result, error)
	End Method

	Method OnGameCenterActivityUpdated(requestId:Int, operation:EGameCenterActivityOperation, activity:TGameCenterActivity, error:TGameCenterError)
		Local listener:IGameCenterActivityManagementListener = IGameCenterActivityManagementListener(previous)
		If listener Then listener.OnGameCenterActivityUpdated(requestId, operation, activity, error)
	End Method

	Method OnGameCenterFriendsAuthorizationLoaded(requestId:Int, status:EGameCenterFriendsAuthorization, error:TGameCenterError)
		Local listener:IGameCenterPlayerListener = IGameCenterPlayerListener(previous)
		If listener Then listener.OnGameCenterFriendsAuthorizationLoaded(requestId, status, error)
	End Method

	Method OnGameCenterFriendsLoaded(requestId:Int, result:TGameCenterPlayerResult, error:TGameCenterError)
		Local listener:IGameCenterPlayerListener = IGameCenterPlayerListener(previous)
		If listener Then listener.OnGameCenterFriendsLoaded(requestId, result, error)
	End Method

	Method OnGameCenterPlayerPhotoLoaded(requestId:Int, gamePlayerId:String, size:EGameCenterPhotoSize, pngData:Byte[], error:TGameCenterError)
		Local listener:IGameCenterPlayerListener = IGameCenterPlayerListener(previous)
		If listener Then listener.OnGameCenterPlayerPhotoLoaded(requestId, gamePlayerId, size, pngData, error)
	End Method

	Method OnGameCenterSavedGamesFetched(requestId:Int, result:TGameCenterSavedGameResult, error:TGameCenterError)
		Local listener:IGameCenterSavedGameListener = IGameCenterSavedGameListener(previous)
		If listener Then listener.OnGameCenterSavedGamesFetched(requestId, result, error)
	End Method

	Method OnGameCenterSavedGameSaved(requestId:Int, savedGame:TGameCenterSavedGame, error:TGameCenterError)
		Local listener:IGameCenterSavedGameListener = IGameCenterSavedGameListener(previous)
		If listener Then listener.OnGameCenterSavedGameSaved(requestId, savedGame, error)
	End Method

	Method OnGameCenterSavedGameDataLoaded(requestId:Int, savedGame:TGameCenterSavedGame, data:Byte[], error:TGameCenterError)
		Local listener:IGameCenterSavedGameListener = IGameCenterSavedGameListener(previous)
		If listener Then listener.OnGameCenterSavedGameDataLoaded(requestId, savedGame, data, error)
	End Method

	Method OnGameCenterSavedGamesDeleted(requestId:Int, name:String, error:TGameCenterError)
		Local listener:IGameCenterSavedGameListener = IGameCenterSavedGameListener(previous)
		If listener Then listener.OnGameCenterSavedGamesDeleted(requestId, name, error)
	End Method

	Method OnGameCenterSavedGameConflict(conflictId:Int, result:TGameCenterSavedGameResult)
		Local listener:IGameCenterSavedGameListener = IGameCenterSavedGameListener(previous)
		If listener Then listener.OnGameCenterSavedGameConflict(conflictId, result)
	End Method

	Method OnGameCenterSavedGameConflictResolved(requestId:Int, conflictId:Int, result:TGameCenterSavedGameResult, error:TGameCenterError)
		Local listener:IGameCenterSavedGameListener = IGameCenterSavedGameListener(previous)
		If listener Then listener.OnGameCenterSavedGameConflictResolved(requestId, conflictId, result, error)
	End Method

	Method OnGameCenterSavedGameModified(savedGame:TGameCenterSavedGame)
		Local listener:IGameCenterSavedGameListener = IGameCenterSavedGameListener(previous)
		If listener Then listener.OnGameCenterSavedGameModified(savedGame)
	End Method
End Type

?

Public

Rem
bbdoc: Game Center matchmaking provider for #GameNet.Online.
about: This adapter currently exposes programmatic automatching and a
#TGameKitTransport. Game Center has no portable searchable-lobby model.

Game Center uses one process-wide listener. The adapter remembers the listener
installed when it is created, forwards the core Game Center callbacks while it
is open, and restores that listener when it closes. Create the adapter after
installing any listener used for achievements, leaderboards, or dashboard UI.
End Rem
Type TGameKitOnlineService Implements IOnlineService
	Private
	Field _gameCenter:TGameCenter
	Field _previousListener:IGameCenterListener
	Field _wasStarted:Int
	Field _listener:TGameKitOnlineListener
	Field _state:EOnlineServiceState
	Field _nextRequestId:UInt = 1
	Field _openRequestId:UInt
	Field _matchRequestId:UInt
	Field _finishRequestId:UInt
	Field _nativeMatchRequestId:Int
	Field _minimumPlayers:Int
	Field _maximumPlayers:Int
	Field _pendingMatch:TGameCenterMatch
	Field _pendingLobby:TGameKitMatchmakingLobby
	Field _pendingMemberCount:Int
	Field _readyTransport:TGameKitTransport
	Field _readyRequestId:UInt
	Field _readyMatchInfo:SOnlineMatchInfo
	Field _maximumPeers:Int
	Field _channelCount:Int
	Field _maximumPacketSize:Size_T
	Field _events:SOnlineEvent[] = New SOnlineEvent[GAMEKIT_ONLINE_EVENT_CAPACITY]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _droppedEvents:UInt

	Method New(gameCenter:TGameCenter, maximumPeers:Int, channelCount:Int, maximumPacketSize:Size_T)
		_gameCenter = gameCenter
		_previousListener = gameCenter.listener
		_wasStarted = gameCenter.started
		_maximumPeers = maximumPeers
		_channelCount = channelCount
		_maximumPacketSize = maximumPacketSize
		_listener = New TGameKitOnlineListener
		_listener.owner = Self
		_listener.previous = _previousListener
	End Method

	Method NextRequestId:UInt()
		Local result:UInt = _nextRequestId
		_nextRequestId :+ 1
		If _nextRequestId = 0 Then _nextRequestId = 1
		Return result
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

	Method ErrorDetail:String(error:TGameCenterError)
		If Not error Then Return ""
		Return error.domain + " (" + error.code + "): " + error.message
	End Method

	Method OnlinePlayer:SOnlinePlayer(player:TGameCenterPlayer, local:Int = False)
		If Not player Then Return New SOnlinePlayer
		Return New SOnlinePlayer(player.gamePlayerId, player.displayName, local)
	End Method

	Method BecomeReady(player:TGameCenterPlayer)
		If _state = EOnlineServiceState.Ready Then Return
		_state = EOnlineServiceState.Ready
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceReady, EOnlineOperation.Open, _openRequestId, EOnlineError.None, 0, "", OnlinePlayer(player, True), ""))
	End Method

	Method Fail(operation:EOnlineOperation, requestId:UInt, category:EOnlineError, error:TGameCenterError, detail:String = "")
		Local providerCode:Int
		If error Then
			providerCode = error.code
			detail = ErrorDetail(error)
		End If
		Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, operation, requestId, category, providerCode, "", New SOnlinePlayer, detail))
	End Method

	Public
	Rem
	bbdoc: Creates an online adapter around the process-wide Game Center service.
	End Rem
	Function Create:TGameKitOnlineService(maximumPeers:Int = GAMEKIT_MAX_REMOTE_PEERS, channelCount:Int = 2, maximumPacketSize:Size_T = GAMEKIT_DEFAULT_MAX_PACKET_SIZE, gameCenter:TGameCenter = Null)
		If Not gameCenter Then gameCenter = TGameCenter.Shared()
		If Not gameCenter Or maximumPeers <= 0 Or maximumPeers > GAMEKIT_MAX_REMOTE_PEERS Or channelCount <= 0 Or maximumPacketSize = 0 Then Return Null
		Return New TGameKitOnlineService(gameCenter, maximumPeers, channelCount, maximumPacketSize)
	End Function

	Method ProviderName:String() Override
		Return "GameKit"
	End Method

	Method Capabilities:EOnlineCapability() Override
		Return EOnlineCapability.Matchmaking | EOnlineCapability.MatchTransport
	End Method

	Method State:EOnlineServiceState() Override
		Return _state
	End Method

	Method LocalPlayer:SOnlinePlayer() Override
		If _state <> EOnlineServiceState.Ready Then Return New SOnlinePlayer
		Return OnlinePlayer(_gameCenter.localPlayer, True)
	End Method

	Method Open:UInt() Override
		If _state <> EOnlineServiceState.Closed Then Return 0
		_openRequestId = NextRequestId()
		_state = EOnlineServiceState.Opening
		If Not _gameCenter.IsAvailable() Then
			_state = EOnlineServiceState.Failed
			Fail(EOnlineOperation.Open, _openRequestId, EOnlineError.Unsupported, Null, "Game Center is unavailable")
			Return _openRequestId
		End If
		_gameCenter.Start(_listener)
		If _gameCenter.IsAuthenticated() And _gameCenter.localPlayer Then BecomeReady(_gameCenter.localPlayer)
		Return _openRequestId
	End Method

	Method Pump() Override
		If Not _pendingMatch Or _readyTransport Then Return
		Local memberCount:Int = _pendingMatch.PlayerCount() + 1
		If memberCount <> _pendingMemberCount Then
			_pendingMemberCount = memberCount
			Queue(New SOnlineEvent(EOnlineEventKind.LobbyChanged, EOnlineOperation.StartMatchmaking, _matchRequestId, EOnlineError.None, 0, "gamekit-match", New SOnlinePlayer, ""))
		End If
		If _pendingMatch.ExpectedPlayerCount() <> 0 Then Return
		If _pendingMatch.PlayerCount() < _minimumPlayers - 1 Then Return
		Local hostIndex:Int = GameKitElectedHostIndex(_pendingMatch, _gameCenter.localPlayer)
		If hostIndex < 0 Then
			_pendingMatch.Disconnect()
			_pendingMatch = Null
			Fail(EOnlineOperation.StartMatchmaking, _matchRequestId, EOnlineError.ProviderFailure, Null, "Could not elect the GameNet session host")
			_matchRequestId = 0
			_nativeMatchRequestId = 0
			Return
		End If
		_readyTransport = TGameKitTransport.Create(_pendingMatch, _maximumPeers, _channelCount, _maximumPacketSize)
		If Not _readyTransport Then
			_pendingMatch.Disconnect()
			_pendingMatch = Null
			Fail(EOnlineOperation.StartMatchmaking, _matchRequestId, EOnlineError.ProviderFailure, Null, "Could not create the GameKit transport")
			_matchRequestId = 0
			_nativeMatchRequestId = 0
			Return
		End If
		If hostIndex > 0 And Not _readyTransport.EnableOnlyPlayer(hostIndex) Then
			_readyTransport.Close()
			_readyTransport = Null
			_pendingMatch = Null
			Fail(EOnlineOperation.StartMatchmaking, _matchRequestId, EOnlineError.ProviderFailure, Null, "Could not select the GameKit session host")
			_matchRequestId = 0
			_nativeMatchRequestId = 0
			Return
		End If
		Local hostPeer:SNetPeer
		If hostIndex > 0 Then hostPeer = New SNetPeer(UInt(hostIndex), 1)
		_readyMatchInfo = New SOnlineMatchInfo(_pendingMatch.PlayerCount() + 1, hostIndex = 0, hostPeer)
		_pendingMatch = Null
		Local readyOperation:EOnlineOperation = EOnlineOperation.StartMatchmaking
		_readyRequestId = _matchRequestId
		If _finishRequestId Then
			readyOperation = EOnlineOperation.StartMatch
			_readyRequestId = _finishRequestId
		End If
		Queue(New SOnlineEvent(EOnlineEventKind.MatchReady, readyOperation, _readyRequestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		_matchRequestId = 0
		_finishRequestId = 0
		_nativeMatchRequestId = 0
		_pendingLobby = Null
		_pendingMemberCount = 0
	End Method

	Method Poll:Int(event:SOnlineEvent Var) Override
		If _eventCount = 0 Then
			event = New SOnlineEvent
			Return False
		End If
		event = _events[_eventRead]
		_events[_eventRead] = New SOnlineEvent
		_eventRead = (_eventRead + 1) Mod _events.Length
		_eventCount :- 1
		Return True
	End Method

	Method CreateLobby:UInt(options:TOnlineLobbyOptions) Override
		Return 0
	End Method

	Method FindLobbies:UInt(query:TOnlineLobbyQuery) Override
		Return 0
	End Method

	Method LobbyResultCount:Int(requestId:UInt) Override
		Return 0
	End Method

	Method LobbyResult:IOnlineLobby(requestId:UInt, index:Int) Override
		Return Null
	End Method

	Method CurrentLobby:IOnlineLobby() Override
		Return _pendingLobby
	End Method

	Method JoinLobby:UInt(lobbyId:String) Override
		Return 0
	End Method

	Method LeaveLobby:UInt() Override
		Return 0
	End Method

	Method AcceptInvitation:UInt(invitationId:String) Override
		Return 0
	End Method

	Method StartMatchmaking:UInt(request:TOnlineMatchmakingRequest) Override
		If _state <> EOnlineServiceState.Ready Or Not request Then Return 0
		If _matchRequestId Or _pendingMatch Or _readyTransport Then Return 0
		If request.minPlayers < 2 Or request.maxPlayers < request.minPlayers Or request.maxPlayers > _maximumPeers + 1 Then Return 0
		_matchRequestId = NextRequestId()
		_finishRequestId = 0
		_minimumPlayers = request.minPlayers
		_maximumPlayers = request.maxPlayers
		_nativeMatchRequestId = _gameCenter.FindMatch(request.minPlayers, request.maxPlayers)
		Queue(New SOnlineEvent(EOnlineEventKind.MatchmakingStarted, EOnlineOperation.StartMatchmaking, _matchRequestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return _matchRequestId
	End Method

	Method CancelMatchmaking:UInt(requestId:UInt) Override
		If requestId = 0 Or requestId <> _matchRequestId Then Return 0
		Local cancelRequestId:UInt = NextRequestId()
		_gameCenter.CancelMatchmaking()
		If _pendingMatch Then _pendingMatch.Disconnect()
		_pendingMatch = Null
		_pendingLobby = Null
		_pendingMemberCount = 0
		_matchRequestId = 0
		_finishRequestId = 0
		_nativeMatchRequestId = 0
		Queue(New SOnlineEvent(EOnlineEventKind.MatchmakingCancelled, EOnlineOperation.CancelMatchmaking, cancelRequestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return cancelRequestId
	End Method

	Method CancelOperation:Int(requestId:UInt) Override
		Return CancelMatchmaking(requestId) <> 0
	End Method

	Method StartMatch:UInt() Override
		If Not _pendingMatch Or _finishRequestId Or PendingPlayerCount() < _minimumPlayers Or Not IsPendingLobbyOwner() Then Return 0
		_finishRequestId = NextRequestId()
		_pendingMatch.FinishMatchmaking()
		Return _finishRequestId
	End Method

	Rem
	bbdoc: Returns the number of players currently assembled by Game Center.
	End Rem
	Method PendingPlayerCount:Int()
		If Not _pendingMatch Then Return 0
		Return _pendingMatch.PlayerCount() + 1
	End Method

	Rem
	bbdoc: Returns True when the local player owns the pending matchmaking lobby.
	End Rem
	Method IsPendingLobbyOwner:Int()
		Return _pendingMatch And GameKitElectedHostIndex(_pendingMatch, _gameCenter.localPlayer) = 0
	End Method

	Method PendingLobbyMember:SOnlinePlayer(index:Int)
		If Not _pendingMatch Or index < 0 Or index >= PendingPlayerCount() Then Return New SOnlinePlayer
		If index = 0 Then Return OnlinePlayer(_gameCenter.localPlayer, True)
		Return OnlinePlayer(_pendingMatch.Player(index), False)
	End Method

	Method PendingLobbyOwner:SOnlinePlayer()
		If Not _pendingMatch Then Return New SOnlinePlayer
		Local hostIndex:Int = GameKitElectedHostIndex(_pendingMatch, _gameCenter.localPlayer)
		If hostIndex = 0 Then Return OnlinePlayer(_gameCenter.localPlayer, True)
		If hostIndex > 0 Then Return OnlinePlayer(_pendingMatch.Player(hostIndex), False)
		Return New SOnlinePlayer
	End Method

	Method PendingLobbyJoinable:Int()
		Return _pendingMatch And _finishRequestId = 0 And _pendingMatch.ExpectedPlayerCount() > 0
	End Method

	Method PendingLobbyMaxPlayers:Int()
		Return _maximumPlayers
	End Method

	Method MatchInfo:Int(requestId:UInt, info:SOnlineMatchInfo Var) Override
		If requestId = 0 Or requestId <> _readyRequestId Or Not _readyTransport Then
			info = New SOnlineMatchInfo
			Return False
		End If
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
		_gameCenter.CancelMatchmaking()
		If _pendingMatch Then _pendingMatch.Disconnect()
		If _readyTransport Then _readyTransport.Close()
		_pendingMatch = Null
		_pendingLobby = Null
		_pendingMemberCount = 0
		_readyTransport = Null
		_matchRequestId = 0
		_finishRequestId = 0
		_readyRequestId = 0
		_readyMatchInfo = New SOnlineMatchInfo
		_nativeMatchRequestId = 0
		If _wasStarted Then
			_gameCenter.listener = _previousListener
		Else
			_gameCenter.Stop()
		End If
		_state = EOnlineServiceState.Closed
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceClosed, EOnlineOperation.Close, requestId, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
		Return requestId
	End Method

	Method DroppedEvents:UInt()
		Return _droppedEvents
	End Method

	Method OnGameCenterAuthenticationChanged(authenticated:Int, player:TGameCenterPlayer, error:TGameCenterError)
		If _previousListener Then _previousListener.OnGameCenterAuthenticationChanged(authenticated, player, error)
		If _state <> EOnlineServiceState.Opening And _state <> EOnlineServiceState.Ready Then Return
		If error Then
			_state = EOnlineServiceState.Failed
			Fail(EOnlineOperation.Open, _openRequestId, EOnlineError.Authentication, error)
		Else If authenticated And player Then
			BecomeReady(player)
		Else
			_state = EOnlineServiceState.Failed
			Fail(EOnlineOperation.Open, _openRequestId, EOnlineError.Authentication, Null, "Game Center is not authenticated")
		End If
	End Method

	Method OnGameCenterMatchFound(requestId:Int, match:TGameCenterMatch, error:TGameCenterError)
		If requestId <> _nativeMatchRequestId Or _matchRequestId = 0 Then
			If match Then match.Disconnect()
			Return
		End If
		If error Or Not match Then
			Fail(EOnlineOperation.StartMatchmaking, _matchRequestId, EOnlineError.ProviderFailure, error, "Game Center did not return a match")
			_matchRequestId = 0
			_nativeMatchRequestId = 0
			Return
		End If
		_pendingMatch = match
		_pendingLobby = New TGameKitMatchmakingLobby(Self)
		_pendingMemberCount = match.PlayerCount() + 1
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyJoined, EOnlineOperation.StartMatchmaking, _matchRequestId, EOnlineError.None, 0, "gamekit-match", New SOnlinePlayer, ""))
	End Method

	Method OnGameCenterAchievementReported(requestId:Int, identifier:String, error:TGameCenterError)
		If _previousListener Then _previousListener.OnGameCenterAchievementReported(requestId, identifier, error)
	End Method

	Method OnGameCenterAchievementsLoaded(requestId:Int, result:TGameCenterAchievementResult, error:TGameCenterError)
		If _previousListener Then _previousListener.OnGameCenterAchievementsLoaded(requestId, result, error)
	End Method

	Method OnGameCenterAchievementsReset(requestId:Int, error:TGameCenterError)
		If _previousListener Then _previousListener.OnGameCenterAchievementsReset(requestId, error)
	End Method

	Method OnGameCenterScoreSubmitted(requestId:Int, leaderboardIdentifier:String, score:Long, error:TGameCenterError)
		If _previousListener Then _previousListener.OnGameCenterScoreSubmitted(requestId, leaderboardIdentifier, score, error)
	End Method

	Method OnGameCenterLeaderboardLoaded(requestId:Int, leaderboard:TGameCenterLeaderboardResult, error:TGameCenterError)
		If _previousListener Then _previousListener.OnGameCenterLeaderboardLoaded(requestId, leaderboard, error)
	End Method

	Method OnGameCenterViewDismissed(view:EGameCenterView)
		If _previousListener Then _previousListener.OnGameCenterViewDismissed(view)
	End Method
End Type

Private

Type TGameKitMatchmakingLobby Implements IOnlineLobby
	Field _service:TGameKitOnlineService
	Field _properties:TOnlineProperties = New TOnlineProperties

	Method New(service:TGameKitOnlineService)
		_service = service
	End Method

	Method Id:String()
		Return "gamekit-match"
	End Method

	Method Name:String()
		Return "Game Center Match"
	End Method

	Method Owner:SOnlinePlayer()
		Return _service.PendingLobbyOwner()
	End Method

	Method MaxPlayers:Int()
		Return _service.PendingLobbyMaxPlayers()
	End Method

	Method IsJoinable:Int()
		Return _service.PendingLobbyJoinable()
	End Method

	Method MemberCount:Int()
		Return _service.PendingPlayerCount()
	End Method

	Method Member:SOnlinePlayer(index:Int)
		Return _service.PendingLobbyMember(index)
	End Method

	Method Properties:TOnlineProperties()
		Return _properties
	End Method
End Type
