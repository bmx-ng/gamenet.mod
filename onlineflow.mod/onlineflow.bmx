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
bbdoc: Reusable orchestration from an online service to a ready GameNet match.
End Rem
Module GameNet.OnlineFlow

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial online-flow coordinator"

Import GameNet.Online
Import BRL.Blitz

Rem
bbdoc: Current stage of an online flow.
End Rem
Enum EOnlineFlowState:Byte
	Closed
	Opening
	Ready
	Searching
	Creating
	Joining
	Matchmaking
	WaitingForPlayers
	StartingMatch
	MatchReady
	InMatch
	Leaving
	Closing
	Failed
End Enum

Rem
bbdoc: Determines when the coordinator asks the provider to start a waiting match.
End Rem
Enum EOnlineFlowStartPolicy:Byte
	Manual
	WhenMinimumPlayers
	WhenLobbyFull
End Enum

Rem
bbdoc: Application-visible events produced by an online-flow coordinator.
End Rem
Enum EOnlineFlowEventKind:Byte
	None
	Opening
	Ready
	Searching
	Creating
	Joining
	Matchmaking
	WaitingForPlayers
	StartingMatch
	InvitationReceived
	NoMatchFound
	MatchReady
	Cancelled
	Left
	Closed
	Failed
End Enum

Private

Enum EOnlineFlowAction:Byte
	None
	Host
	FindAndJoin
	QuickPlay
	Join
	AcceptInvitation
End Enum

Public

Rem
bbdoc: Policy and provider-neutral options for one host, search, or quick-play flow.
about: Quick Play uses native matchmaking when it is preferred and available.
Otherwise it searches for the first joinable lobby and optionally creates one
when no suitable result exists.
End Rem
Type TOnlineFlowRequest
	Field lobbyOptions:TOnlineLobbyOptions = New TOnlineLobbyOptions
	Field lobbyQuery:TOnlineLobbyQuery = New TOnlineLobbyQuery
	Field matchmakingRequest:TOnlineMatchmakingRequest = New TOnlineMatchmakingRequest
	Field preferMatchmaking:Int = True
	Field createIfNoLobby:Int = True
	Field startPolicy:EOnlineFlowStartPolicy = EOnlineFlowStartPolicy.WhenMinimumPlayers
End Type

Rem
bbdoc: A ready match and the transport whose ownership has passed to the application.
End Rem
Type TOnlineMatchLaunch
	Private
	Field _info:SOnlineMatchInfo
	Field _transport:INetTransport

	Public
	Method New(info:SOnlineMatchInfo, transport:INetTransport)
		_info = info
		_transport = transport
	End Method

	Method IsValid:Int()
		Return _info.IsValid() And _transport <> Null
	End Method

	Method Info:SOnlineMatchInfo()
		Return _info
	End Method

	Method Transport:INetTransport()
		Return _transport
	End Method
End Type

Rem
bbdoc: One high-level online-flow notification.
End Rem
Struct SOnlineFlowEvent
	Private
	Field _kind:EOnlineFlowEventKind
	Field _state:EOnlineFlowState
	Field _error:EOnlineError
	Field _providerCode:Int
	Field _subjectId:String
	Field _player:SOnlinePlayer
	Field _playerCount:Int
	Field _detail:String

	Public
	Method New()
	End Method

	Method New(kind:EOnlineFlowEventKind, state:EOnlineFlowState, error:EOnlineError, providerCode:Int, subjectId:String, player:SOnlinePlayer, playerCount:Int, detail:String)
		_kind = kind
		_state = state
		_error = error
		_providerCode = providerCode
		_subjectId = subjectId
		_player = player
		_playerCount = playerCount
		_detail = detail
	End Method

	Method Kind:EOnlineFlowEventKind()
		Return _kind
	End Method

	Method State:EOnlineFlowState()
		Return _state
	End Method

	Method Error:EOnlineError()
		Return _error
	End Method

	Method ProviderCode:Int()
		Return _providerCode
	End Method

	Method SubjectId:String()
		Return _subjectId
	End Method

	Method Player:SOnlinePlayer()
		Return _player
	End Method

	Method PlayerCount:Int()
		Return _playerCount
	End Method

	Method Detail:String()
		Return _detail
	End Method
End Struct

Rem
bbdoc: Converts player-facing online intentions into provider operations.
about: The coordinator owns request correlation and the find, join, create,
wait, and start state machine. Call #Pump regularly. After MatchReady, call
#TakeMatch once to transfer the provider transport to the application.
End Rem
Type TOnlineFlowCoordinator
	Private
	Const EVENT_CAPACITY:Int = 64

	Field _service:IOnlineService
	Field _state:EOnlineFlowState = EOnlineFlowState.Closed
	Field _action:EOnlineFlowAction
	Field _request:TOnlineFlowRequest
	Field _usingMatchmaking:Int
	Field _operationRequestId:UInt
	Field _matchmakingRequestId:UInt
	Field _readyRequestId:UInt
	Field _readyInfo:SOnlineMatchInfo
	Field _events:SOnlineFlowEvent[]
	Field _eventRead:Int
	Field _eventWrite:Int
	Field _eventCount:Int
	Field _droppedEvents:UInt

	Method New(service:IOnlineService)
		_service = service
		_events = New SOnlineFlowEvent[EVENT_CAPACITY]
	End Method

	Method Queue(kind:EOnlineFlowEventKind, error:EOnlineError, providerCode:Int, subjectId:String, player:SOnlinePlayer, playerCount:Int, detail:String)
		If _eventCount = _events.Length Then
			_eventRead = (_eventRead + 1) Mod _events.Length
			_eventCount :- 1
			_droppedEvents :+ 1
		End If
		_events[_eventWrite] = New SOnlineFlowEvent(kind, _state, error, providerCode, subjectId, player, playerCount, detail)
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
	End Method

	Method SetState(state:EOnlineFlowState, kind:EOnlineFlowEventKind, detail:String = "")
		_state = state
		Queue(kind, EOnlineError.None, 0, "", New SOnlinePlayer, CurrentPlayerCount(), detail)
	End Method

	Method Fail(error:EOnlineError, providerCode:Int, detail:String)
		_state = EOnlineFlowState.Failed
		_operationRequestId = 0
		_matchmakingRequestId = 0
		Queue(EOnlineFlowEventKind.Failed, error, providerCode, "", New SOnlinePlayer, CurrentPlayerCount(), detail)
	End Method

	Method ClearAction()
		_action = EOnlineFlowAction.None
		_request = Null
		_usingMatchmaking = False
	End Method

	Method DiscardReadyTransport()
		If _readyRequestId Then
			Local transport:INetTransport = _service.TakeMatchTransport(_readyRequestId)
			If transport Then
				transport.Close()
			End If
		End If
		_readyRequestId = 0
		_readyInfo = New SOnlineMatchInfo
	End Method

	Method CurrentPlayerCount:Int()
		Local lobby:IOnlineLobby = _service.CurrentLobby()
		If Not lobby Then
			Return 0
		End If
		Return lobby.MemberCount()
	End Method

	Method MinimumPlayers:Int()
		If _request Then
			If _usingMatchmaking Then
				If _request.matchmakingRequest Then
					Return _request.matchmakingRequest.minPlayers
				End If
			End If
			If _request.lobbyOptions Then
				Return _request.lobbyOptions.minPlayers
			End If
		End If
		Return 1
	End Method

	Method BeginCreate:Int()
		_usingMatchmaking = False
		If Not OnlineHasCapabilities(_service.Capabilities(), EOnlineCapability.CreateLobby) Then
			Fail(EOnlineError.Unsupported, 0, "This provider cannot create lobbies")
			Return False
		End If
		If Not _request Or Not _request.lobbyOptions Then
			Fail(EOnlineError.InvalidArgument, 0, "Lobby options are required")
			Return False
		End If
		_operationRequestId = _service.CreateLobby(_request.lobbyOptions)
		If _operationRequestId = 0 Then
			Fail(EOnlineError.InvalidState, 0, "The provider could not begin creating a lobby")
			Return False
		End If
		SetState(EOnlineFlowState.Creating, EOnlineFlowEventKind.Creating)
		Return True
	End Method

	Method BeginFind:Int()
		_usingMatchmaking = False
		If Not OnlineHasCapabilities(_service.Capabilities(), EOnlineCapability.FindLobbies) Then
			Fail(EOnlineError.Unsupported, 0, "This provider cannot find lobbies")
			Return False
		End If
		If Not _request Or Not _request.lobbyQuery Then
			Fail(EOnlineError.InvalidArgument, 0, "A lobby query is required")
			Return False
		End If
		_operationRequestId = _service.FindLobbies(_request.lobbyQuery)
		If _operationRequestId = 0 Then
			Fail(EOnlineError.InvalidState, 0, "The provider could not begin searching for lobbies")
			Return False
		End If
		SetState(EOnlineFlowState.Searching, EOnlineFlowEventKind.Searching)
		Return True
	End Method

	Method BeginJoin:Int(lobbyId:String, invitation:Int = False)
		If lobbyId.Length = 0 Then
			Fail(EOnlineError.InvalidArgument, 0, "A lobby or invitation identifier is required")
			Return False
		End If
		If invitation Then
			_operationRequestId = _service.AcceptInvitation(lobbyId)
		Else
			_operationRequestId = _service.JoinLobby(lobbyId)
		End If
		If _operationRequestId = 0 Then
			Fail(EOnlineError.InvalidState, 0, "The provider could not begin joining the lobby")
			Return False
		End If
		SetState(EOnlineFlowState.Joining, EOnlineFlowEventKind.Joining)
		Return True
	End Method

	Method BeginMatchmaking:Int()
		If Not OnlineHasCapabilities(_service.Capabilities(), EOnlineCapability.Matchmaking) Then
			Fail(EOnlineError.Unsupported, 0, "This provider does not provide matchmaking")
			Return False
		End If
		If Not _request Or Not _request.matchmakingRequest Then
			Fail(EOnlineError.InvalidArgument, 0, "A matchmaking request is required")
			Return False
		End If
		_matchmakingRequestId = _service.StartMatchmaking(_request.matchmakingRequest)
		If _matchmakingRequestId = 0 Then
			Fail(EOnlineError.InvalidState, 0, "The provider could not begin matchmaking")
			Return False
		End If
		_usingMatchmaking = True
		SetState(EOnlineFlowState.Matchmaking, EOnlineFlowEventKind.Matchmaking)
		Return True
	End Method

	Method BeginStart:Int()
		If _operationRequestId Or _readyRequestId Then
			Return False
		End If
		_operationRequestId = _service.StartMatch()
		If _operationRequestId = 0 Then
			Return False
		End If
		SetState(EOnlineFlowState.StartingMatch, EOnlineFlowEventKind.StartingMatch)
		Return True
	End Method

	Method ShouldStart:Int(lobby:IOnlineLobby)
		If Not lobby Or Not _request Then
			Return False
		End If
		Select _request.startPolicy
			Case EOnlineFlowStartPolicy.WhenMinimumPlayers
				Return lobby.MemberCount() >= MinimumPlayers()
			Case EOnlineFlowStartPolicy.WhenLobbyFull
				Return lobby.MaxPlayers() > 0 And lobby.MemberCount() >= lobby.MaxPlayers()
		End Select
		Return False
	End Method

	Method WaitForPlayers(detail:String = "")
		_state = EOnlineFlowState.WaitingForPlayers
		Local lobby:IOnlineLobby = _service.CurrentLobby()
		Local subjectId:String
		If lobby Then
			subjectId = lobby.Id()
		End If
		Queue(EOnlineFlowEventKind.WaitingForPlayers, EOnlineError.None, 0, subjectId, New SOnlinePlayer, CurrentPlayerCount(), detail)
		If ShouldStart(lobby) Then
			BeginStart()
		End If
	End Method

	Method HandleSearchCompleted(event:SOnlineEvent)
		If event.RequestId() <> _operationRequestId Then
			Return
		End If
		Local requestId:UInt = _operationRequestId
		_operationRequestId = 0
		Local count:Int = _service.LobbyResultCount(requestId)
		For Local index:Int = 0 Until count
			Local lobby:IOnlineLobby = _service.LobbyResult(requestId, index)
			If lobby And lobby.IsJoinable() Then
				BeginJoin(lobby.Id())
				Return
			End If
		Next
		If _action = EOnlineFlowAction.QuickPlay And _request And _request.createIfNoLobby And OnlineHasCapabilities(_service.Capabilities(), EOnlineCapability.CreateLobby) Then
			BeginCreate()
			Return
		End If
		ClearAction()
		_state = EOnlineFlowState.Ready
		Queue(EOnlineFlowEventKind.NoMatchFound, EOnlineError.None, 0, "", New SOnlinePlayer, 0, "")
	End Method

	Method HandleMatchReady(event:SOnlineEvent)
		Local info:SOnlineMatchInfo
		If Not _service.MatchInfo(event.RequestId(), info) Or Not info.IsValid() Then
			Fail(EOnlineError.ProviderFailure, event.ProviderCode(), "The provider reported a match without valid session information")
			Return
		End If
		_operationRequestId = 0
		_matchmakingRequestId = 0
		_readyRequestId = event.RequestId()
		_readyInfo = info
		_state = EOnlineFlowState.MatchReady
		Queue(EOnlineFlowEventKind.MatchReady, EOnlineError.None, event.ProviderCode(), event.SubjectId(), event.Player(), info.PlayerCount(), event.Detail())
	End Method

	Method HandleProviderEvent(event:SOnlineEvent)
		Select event.Kind()
			Case EOnlineEventKind.ServiceReady
				If _state = EOnlineFlowState.Opening And event.RequestId() = _operationRequestId Then
					_operationRequestId = 0
					SetState(EOnlineFlowState.Ready, EOnlineFlowEventKind.Ready)
				End If

			Case EOnlineEventKind.LobbySearchCompleted
				HandleSearchCompleted(event)

			Case EOnlineEventKind.LobbyCreated, EOnlineEventKind.LobbyJoined
				If event.RequestId() = _operationRequestId Or event.RequestId() = _matchmakingRequestId Then
					_operationRequestId = 0
					WaitForPlayers()
				End If

			Case EOnlineEventKind.LobbyChanged
				If _state = EOnlineFlowState.WaitingForPlayers Then
					WaitForPlayers(event.Detail())
				End If

			Case EOnlineEventKind.InvitationReceived
				Queue(EOnlineFlowEventKind.InvitationReceived, EOnlineError.None, event.ProviderCode(), event.SubjectId(), event.Player(), CurrentPlayerCount(), event.Detail())

			Case EOnlineEventKind.MatchmakingStarted
				If event.RequestId() = _matchmakingRequestId Then
					_state = EOnlineFlowState.Matchmaking
				End If

			Case EOnlineEventKind.MatchmakingCancelled
				If _state = EOnlineFlowState.Matchmaking Then
					_matchmakingRequestId = 0
					SetState(EOnlineFlowState.Ready, EOnlineFlowEventKind.Cancelled)
				End If

			Case EOnlineEventKind.MatchReady
				If event.RequestId() = _operationRequestId Or event.RequestId() = _matchmakingRequestId Then
					HandleMatchReady(event)
				End If

			Case EOnlineEventKind.LobbyLeft
				_operationRequestId = 0
				DiscardReadyTransport()
				ClearAction()
				SetState(EOnlineFlowState.Ready, EOnlineFlowEventKind.Left)

			Case EOnlineEventKind.ServiceClosed
				_operationRequestId = 0
				_matchmakingRequestId = 0
				_readyRequestId = 0
				_readyInfo = New SOnlineMatchInfo
				ClearAction()
				SetState(EOnlineFlowState.Closed, EOnlineFlowEventKind.Closed)

			Case EOnlineEventKind.OperationFailed
				If event.RequestId() = 0 Or event.RequestId() = _operationRequestId Or event.RequestId() = _matchmakingRequestId Then
					Fail(event.Error(), event.ProviderCode(), event.Detail())
				End If
		End Select
	End Method

	Public
	Rem
	bbdoc: Creates a coordinator around an online service.
	End Rem
	Function Create:TOnlineFlowCoordinator(service:IOnlineService)
		If Not service Then
			Return Null
		End If
		Return New TOnlineFlowCoordinator(service)
	End Function

	Method Service:IOnlineService()
		Return _service
	End Method

	Method ProviderName:String()
		Return _service.ProviderName()
	End Method

	Method Capabilities:EOnlineCapability()
		Return _service.Capabilities()
	End Method

	Method LocalPlayer:SOnlinePlayer()
		Return _service.LocalPlayer()
	End Method

	Method State:EOnlineFlowState()
		Return _state
	End Method

	Method CurrentLobby:IOnlineLobby()
		Return _service.CurrentLobby()
	End Method

	Method Open:Int()
		If _state <> EOnlineFlowState.Closed Then
			Return False
		End If
		_operationRequestId = _service.Open()
		If _operationRequestId = 0 Then
			Fail(EOnlineError.InvalidState, 0, "The online service could not be opened")
			Return False
		End If
		SetState(EOnlineFlowState.Opening, EOnlineFlowEventKind.Opening)
		Return True
	End Method

	Method Host:Int(request:TOnlineFlowRequest)
		If _state <> EOnlineFlowState.Ready Or Not request Then
			Return False
		End If
		_action = EOnlineFlowAction.Host
		_request = request
		Return BeginCreate()
	End Method

	Method FindAndJoin:Int(request:TOnlineFlowRequest)
		If _state <> EOnlineFlowState.Ready Or Not request Then
			Return False
		End If
		_action = EOnlineFlowAction.FindAndJoin
		_request = request
		Return BeginFind()
	End Method

	Method QuickPlay:Int(request:TOnlineFlowRequest)
		If _state <> EOnlineFlowState.Ready Or Not request Then
			Return False
		End If
		_action = EOnlineFlowAction.QuickPlay
		_request = request
		If request.preferMatchmaking And OnlineHasCapabilities(_service.Capabilities(), EOnlineCapability.Matchmaking) Then
			Return BeginMatchmaking()
		End If
		If OnlineHasCapabilities(_service.Capabilities(), EOnlineCapability.FindLobbies) Then
			Return BeginFind()
		End If
		If request.createIfNoLobby And OnlineHasCapabilities(_service.Capabilities(), EOnlineCapability.CreateLobby) Then
			Return BeginCreate()
		End If
		Fail(EOnlineError.Unsupported, 0, "This provider cannot satisfy the Quick Play policy")
		Return False
	End Method

	Method Join:Int(lobbyId:String, request:TOnlineFlowRequest = Null)
		If _state <> EOnlineFlowState.Ready Then
			Return False
		End If
		If Not request Then
			request = New TOnlineFlowRequest
		End If
		_action = EOnlineFlowAction.Join
		_request = request
		Return BeginJoin(lobbyId)
	End Method

	Method AcceptInvitation:Int(invitationId:String, request:TOnlineFlowRequest = Null)
		If _state <> EOnlineFlowState.Ready Then
			Return False
		End If
		If Not OnlineHasCapabilities(_service.Capabilities(), EOnlineCapability.Invitations) Then
			Fail(EOnlineError.Unsupported, 0, "This provider cannot accept invitations")
			Return False
		End If
		If Not request Then
			request = New TOnlineFlowRequest
		End If
		_action = EOnlineFlowAction.AcceptInvitation
		_request = request
		Return BeginJoin(invitationId, True)
	End Method

	Method StartMatch:Int()
		If _state <> EOnlineFlowState.WaitingForPlayers Then
			Return False
		End If
		Return BeginStart()
	End Method

	Rem
	bbdoc: Cancels native matchmaking, or leaves a lobby while waiting for a match.
	about: The common provider interface does not currently expose cancellation
	for an in-flight lobby search, create, or join operation.
	End Rem
	Method Cancel:Int()
		If _state = EOnlineFlowState.Matchmaking And _matchmakingRequestId Then
			Local cancelRequestId:UInt = _service.CancelMatchmaking(_matchmakingRequestId)
			Return cancelRequestId <> 0
		End If
		If (_state = EOnlineFlowState.WaitingForPlayers Or _state = EOnlineFlowState.StartingMatch) And _service.CurrentLobby() Then
			Return Leave()
		End If
		Return False
	End Method

	Method Leave:Int()
		If _state = EOnlineFlowState.Leaving Or _state = EOnlineFlowState.Closing Or _state = EOnlineFlowState.Closed Then
			Return False
		End If
		If Not _service.CurrentLobby() Then
			DiscardReadyTransport()
			ClearAction()
			SetState(EOnlineFlowState.Ready, EOnlineFlowEventKind.Left)
			Return True
		End If
		_operationRequestId = _service.LeaveLobby()
		If _operationRequestId = 0 Then
			Return False
		End If
		_state = EOnlineFlowState.Leaving
		Return True
	End Method

	Method Reset:Int()
		If _state <> EOnlineFlowState.Failed Then
			Return False
		End If
		ClearAction()
		_operationRequestId = 0
		_matchmakingRequestId = 0
		_readyRequestId = 0
		_readyInfo = New SOnlineMatchInfo
		If _service.State() = EOnlineServiceState.Ready Then
			SetState(EOnlineFlowState.Ready, EOnlineFlowEventKind.Ready)
			Return True
		End If
		If _service.State() = EOnlineServiceState.Closed Then
			_state = EOnlineFlowState.Closed
			Return True
		End If
		Return False
	End Method

	Method Pump()
		_service.Pump()
		Local event:SOnlineEvent
		While _service.Poll(event)
			HandleProviderEvent(event)
		Wend
	End Method

	Method Poll:Int(event:SOnlineFlowEvent Var)
		If _eventCount = 0 Then
			event = New SOnlineFlowEvent
			Return False
		End If
		event = _events[_eventRead]
		_events[_eventRead] = New SOnlineFlowEvent
		_eventRead = (_eventRead + 1) Mod _events.Length
		_eventCount :- 1
		Return True
	End Method

	Method MatchInfo:Int(info:SOnlineMatchInfo Var)
		If _state <> EOnlineFlowState.MatchReady Or _readyRequestId = 0 Then
			info = New SOnlineMatchInfo
			Return False
		End If
		info = _readyInfo
		Return True
	End Method

	Method TakeMatch:TOnlineMatchLaunch()
		If _state <> EOnlineFlowState.MatchReady Or _readyRequestId = 0 Then
			Return Null
		End If
		Local transport:INetTransport = _service.TakeMatchTransport(_readyRequestId)
		If Not transport Then
			Fail(EOnlineError.ProviderFailure, 0, "The provider did not return the ready match transport")
			Return Null
		End If
		Local launch:TOnlineMatchLaunch = New TOnlineMatchLaunch(_readyInfo, transport)
		_readyRequestId = 0
		_readyInfo = New SOnlineMatchInfo
		_state = EOnlineFlowState.InMatch
		Return launch
	End Method

	Method Close:Int()
		If _state = EOnlineFlowState.Closed Or _state = EOnlineFlowState.Closing Then
			Return False
		End If
		_operationRequestId = _service.Close()
		If _operationRequestId = 0 Then
			Return False
		End If
		_state = EOnlineFlowState.Closing
		Return True
	End Method

	Method DroppedEvents:UInt()
		Return _droppedEvents
	End Method
End Type

?
