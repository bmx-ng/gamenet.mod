' Copyright (c) 2026 Bruce A Henderson and contributors
'
' This software is provided 'as-is', without any express or implied warranty.
' Permission is granted to use, alter, and redistribute this software under
' the zlib/libpng licence. This notice must not be removed.

SuperStrict

Rem
bbdoc: Epic Online Services lobby provider for GameNet.Online.
End Rem
Module GameNet.EOSOnline

?bmxng2

ModuleInfo "Version: 0.3"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"
ModuleInfo "History: 0.3 Added compensated cancellation for lobby operations"
ModuleInfo "History: 0.1 Initial EOS lobby and P2P match provider"
ModuleInfo "History: 0.2 Added managed EOS session integration"

?bmxng2 And Not android And Not ios

Import GameNet.Online
Import GameNet.EOSP2P
Import EOS.SDK

Const EOS_ONLINE_EVENT_CAPACITY:Int = 64
Const EOS_ONLINE_NAME_KEY:String = "gamenet.name"
Const EOS_ONLINE_JOINABLE_KEY:String = "gamenet.joinable"
Const EOS_ONLINE_START_KEY:String = "gamenet.start"

Rem
bbdoc: Provider-neutral data copied from an EOS lobby-details handle.
End Rem
Type TEOSOnlineLobbySnapshot
	Field LobbyId:String
	Field Name:String
	Field OwnerId:String
	Field MaximumPlayers:Int
	Field AvailableSlots:Int
	Field Joinable:Int
	' GameNet creates EOS lobbies with invitations enabled and disables them in
	' the same owner update that publishes match start. Unlike custom lobby
	' attributes, EOS exposes this core state reliably to joined members.
	Field StartSignaled:Int
	Field MemberIds:String[] = New String[0]
	Field Properties:TOnlineProperties = New TOnlineProperties
End Type

Type TEOSOnlineLobbyResults
	Field Snapshots:TEOSOnlineLobbySnapshot[] = New TEOSOnlineLobbySnapshot[0]
End Type

Rem
bbdoc: Receives asynchronous work completed by an EOS online backend.
End Rem
Interface IEOSOnlineBackendListener
	Method OnEOSOnlineLobbyCreated(result:EEOSResult, snapshot:TEOSOnlineLobbySnapshot)
	Method OnEOSOnlineLobbySearch(result:EEOSResult, results:TEOSOnlineLobbyResults)
	Method OnEOSOnlineLobbyJoined(result:EEOSResult, snapshot:TEOSOnlineLobbySnapshot)
	Method OnEOSOnlineLobbyLeft(result:EEOSResult, lobbyId:String)
	Method OnEOSOnlineStartPublished(result:EEOSResult, snapshot:TEOSOnlineLobbySnapshot)
	Method OnEOSOnlineLobbyChanged(snapshot:TEOSOnlineLobbySnapshot, targetUserId:String, status:EEOSLobbyMemberStatus)
	Method OnEOSOnlineInvitation(invitationId:String, lobbyId:String, senderUserId:String, accepted:Int)
End Interface

Rem
bbdoc: EOS operations consumed by #TEOSOnlineService.
about: Applications normally use the native implementation created by
#TEOSOnlineService.Create. The interface permits deterministic provider tests.
End Rem
Interface IEOSOnlineBackend
	Method Initialize:Int(listener:IEOSOnlineBackendListener)
	Method Pump()
	Method LocalUserId:String()
	Method LocalDisplayName:String()
	Method CreateLobby:Int(options:TOnlineLobbyOptions, bucketId:String)
	Method FindLobbies:Int(query:TOnlineLobbyQuery, bucketId:String)
	Method JoinLobby:Int(lobbyId:String)
	Method AcceptInvitation:Int(invitationId:String)
	Method LeaveLobby:Int(lobbyId:String, owner:Int)
	Method PublishStart:Int(lobbyId:String)
	Method InvitePlayer:Int(lobbyId:String, productUserId:String)
	Method LobbySnapshot:TEOSOnlineLobbySnapshot(lobbyId:String)
	Method TransportError:String()
	Method CreateTransport:INetTransport(remoteUserIds:String[], socketName:String, channelCount:Int, maxPacketSize:Size_T, initiateConnections:Int)
	Method Shutdown()
End Interface

Type TNativeEOSOnlineBackend Implements IEOSOnlineBackend, IEOSLobbyCreateListener, IEOSLobbyUpdateListener, IEOSLobbySearchFindListener, IEOSLobbyJoinListener, IEOSLobbyLeaveListener, IEOSLobbyDestroyListener, IEOSLobbySendInviteListener, IEOSLobbyUpdateReceivedListener, IEOSLobbyMemberUpdateReceivedListener, IEOSLobbyMemberStatusReceivedListener, IEOSLobbyInviteReceivedListener, IEOSLobbyInviteAcceptedListener
	Private
	Field _platform:TEOSPlatform
	Field _lobby:TEOSLobby
	Field _p2p:TEOSP2P
	Field _localUserId:TEOSProductUserId
	Field _localDisplayName:String
	Field _tickPlatform:Int
	Field _listener:IEOSOnlineBackendListener
	Field _createOptions:TOnlineLobbyOptions
	Field _createLobbyId:String
	Field _createRequest:TEOSLobbyCreateRequest
	Field _updateRequest:TEOSLobbyUpdateRequest
	Field _updatePurpose:Int
	Field _search:TEOSLobbySearch
	Field _searchRequest:TEOSLobbySearchFindRequest
	Field _searchOpenSlots:Int
	Field _searchDetails:TEOSLobbyDetails[] = New TEOSLobbyDetails[0]
	Field _searchSnapshots:TEOSOnlineLobbySnapshot[] = New TEOSOnlineLobbySnapshot[0]
	Field _joinRequest:TEOSLobbyJoinRequest
	Field _joinDetails:TEOSLobbyDetails
	Field _joinOwnsDetails:Int
	Field _leaveRequest:TEOSLobbyLeaveRequest
	Field _destroyRequest:TEOSLobbyDestroyRequest
	Field _inviteRequest:TEOSLobbySendInviteRequest
	Field _lobbyUpdateSubscription:TEOSLobbyUpdateReceivedSubscription
	Field _memberUpdateSubscription:TEOSLobbyMemberUpdateReceivedSubscription
	Field _memberStatusSubscription:TEOSLobbyMemberStatusReceivedSubscription
	Field _inviteReceivedSubscription:TEOSLobbyInviteReceivedSubscription
	Field _inviteAcceptedSubscription:TEOSLobbyInviteAcceptedSubscription
	Field _transportError:String

	Public
	Method New(platform:TEOSPlatform, localUserId:TEOSProductUserId, localDisplayName:String, tickPlatform:Int = True)
		_platform = platform
		_lobby = platform.Lobby()
		_p2p = platform.P2P()
		_localUserId = localUserId
		_localDisplayName = localDisplayName
		_tickPlatform = tickPlatform
	End Method

	Private
	Method CopyOptions:TOnlineLobbyOptions(source:TOnlineLobbyOptions)
		Local result:TOnlineLobbyOptions = New TOnlineLobbyOptions
		result.name = source.name
		result.minPlayers = source.minPlayers
		result.maxPlayers = source.maxPlayers
		result.visibility = source.visibility
		result.joinable = source.joinable
		For Local index:Int = 0 Until source.properties.Count()
			result.properties.Set(source.properties.KeyAt(index), source.properties.ValueAt(index))
		Next
		Return result
	End Method

	Method ReleaseSearch()
		For Local details:TEOSLobbyDetails = EachIn _searchDetails
			If details Then details.Release()
		Next
		_searchDetails = New TEOSLobbyDetails[0]
		_searchSnapshots = New TEOSOnlineLobbySnapshot[0]
		If _search Then _search.Release()
		_search = Null
		_searchRequest = Null
	End Method

	Method Snapshot:TEOSOnlineLobbySnapshot(details:TEOSLobbyDetails)
		If Not details Then Return Null
		Local info:TEOSLobbyInfo
		If details.CopyInfo(info) <> EEOSResult.Success Or Not info Then Return Null
		Local result:TEOSOnlineLobbySnapshot = New TEOSOnlineLobbySnapshot
		result.LobbyId = info.LobbyId
		If info.OwnerUserId Then result.OwnerId = info.OwnerUserId.ToString()
		result.MaximumPlayers = Int(info.MaxMembers)
		result.AvailableSlots = Int(info.AvailableSlots)
		result.Joinable = info.AvailableSlots > 0
		result.StartSignaled = Not info.AllowInvites
		Local memberCount:Int = Int(details.MemberCount())
		result.MemberIds = New String[memberCount]
		For Local index:Int = 0 Until memberCount
			Local memberId:TEOSProductUserId = details.MemberByIndex(UInt(index))
			If memberId Then result.MemberIds[index] = memberId.ToString()
		Next
		For Local index:Int = 0 Until Int(details.AttributeCount())
			Local attribute:TEOSLobbyAttribute
			If details.CopyAttributeByIndex(UInt(index), attribute) <> EEOSResult.Success Or Not attribute Or attribute.ValueType <> EEOSLobbyAttributeType.StringValue Then Continue
			Select attribute.Key
				Case EOS_ONLINE_NAME_KEY
					result.Name = attribute.StringValue
				Case EOS_ONLINE_JOINABLE_KEY
					result.Joinable = attribute.StringValue <> "0" And info.AvailableSlots > 0
					' Keep the owner's explicit value in the internal snapshot too. A
					' full lobby is also not joinable, so Joinable alone cannot tell a
					' waiting client that the owner actually published match start.
					result.Properties.Set(attribute.Key, attribute.StringValue)
				Default
					result.Properties.Set(attribute.Key, attribute.StringValue)
			End Select
		Next
		' Preserve a uniform start marker for the public lobby view even when the
		' joined-member cache omits custom attributes from CopyDetails.
		Local startFound:Int
		If result.Properties.Value(EOS_ONLINE_START_KEY, startFound) = "1" Then result.StartSignaled = True
		If result.StartSignaled And Not startFound Then result.Properties.Set(EOS_ONLINE_START_KEY, "1")
		Return result
	End Method

	Method CurrentSnapshot:TEOSOnlineLobbySnapshot(lobbyId:String)
		Local details:TEOSLobbyDetails
		If _lobby.CopyDetails(_localUserId, lobbyId, details) <> EEOSResult.Success Or Not details Then Return Null
		Local result:TEOSOnlineLobbySnapshot = Snapshot(details)
		details.Release()
		Return result
	End Method

	Method UserText:String(userId:TEOSProductUserId)
		If Not userId Then Return ""
		Return userId.ToString()
	End Method

	Method BeginMetadataUpdate:Int(lobbyId:String, options:TOnlineLobbyOptions)
		Local modification:TEOSLobbyModification
		If _lobby.CreateModification(_localUserId, lobbyId, modification) <> EEOSResult.Success Or Not modification Then Return False
		Local result:EEOSResult = modification.AddStringAttribute(EOS_ONLINE_NAME_KEY, options.name)
		If result = EEOSResult.Success Then result = modification.AddStringAttribute(EOS_ONLINE_JOINABLE_KEY, String(Int(options.joinable <> 0)))
		If result = EEOSResult.Success Then result = modification.AddStringAttribute(EOS_ONLINE_START_KEY, "0")
		For Local index:Int = 0 Until options.properties.Count()
			If result = EEOSResult.Success Then result = modification.AddStringAttribute(options.properties.KeyAt(index), options.properties.ValueAt(index))
		Next
		If result = EEOSResult.Success Then _updateRequest = _lobby.Update(modification, Self)
		modification.Release()
		Return _updateRequest <> Null
	End Method

	Method DetailsForLobby:TEOSLobbyDetails(lobbyId:String)
		For Local index:Int = 0 Until _searchSnapshots.Length
			If _searchSnapshots[index] And _searchSnapshots[index].LobbyId = lobbyId Then Return _searchDetails[index]
		Next
		Return Null
	End Method

	Public
	Method Initialize:Int(listener:IEOSOnlineBackendListener) Override
		If Not listener Or Not _platform Or Not _platform.IsValid() Or Not _lobby Or Not _p2p Or Not _localUserId Or Not _localUserId.IsValid() Then Return False
		_listener = listener
		_lobbyUpdateSubscription = _lobby.AddNotifyLobbyUpdateReceived(Self)
		_memberUpdateSubscription = _lobby.AddNotifyMemberUpdateReceived(Self)
		_memberStatusSubscription = _lobby.AddNotifyMemberStatusReceived(Self)
		_inviteReceivedSubscription = _lobby.AddNotifyInviteReceived(Self)
		_inviteAcceptedSubscription = _lobby.AddNotifyInviteAccepted(Self)
		If Not _lobbyUpdateSubscription Or Not _memberUpdateSubscription Or Not _memberStatusSubscription Or Not _inviteReceivedSubscription Or Not _inviteAcceptedSubscription Then Shutdown(); Return False
		Return True
	End Method

	Method Pump() Override
		If _tickPlatform Then
			_platform.Tick()
		End If
	End Method

	Method LocalUserId:String() Override
		Return _localUserId.ToString()
	End Method

	Method LocalDisplayName:String() Override
		Return _localDisplayName
	End Method

	Method CreateLobby:Int(options:TOnlineLobbyOptions, bucketId:String) Override
		If _createRequest Or _updateRequest Then Return False
		_createOptions = CopyOptions(options)
		Local create:TEOSLobbyCreateOptions = New TEOSLobbyCreateOptions
		create.LocalUserId = _localUserId
		create.MaxMembers = UInt(options.maxPlayers)
		create.BucketId = bucketId
		create.AllowInvites = True
		create.DisableHostMigration = True
		create.PresenceEnabled = True
		Select options.visibility
			Case EOnlineLobbyVisibility.Public create.PermissionLevel = EEOSLobbyPermissionLevel.PublicAdvertised
			Case EOnlineLobbyVisibility.FriendsOnly create.PermissionLevel = EEOSLobbyPermissionLevel.JoinViaPresence
			Default create.PermissionLevel = EEOSLobbyPermissionLevel.InviteOnly
		End Select
		_createRequest = _lobby.Create(create, Self)
		Return _createRequest <> Null
	End Method

	Method FindLobbies:Int(query:TOnlineLobbyQuery, bucketId:String) Override
		If _searchRequest Or _joinRequest Then Return False
		ReleaseSearch()
		Local maximum:Int = query.maximumResults
		If maximum < 1 Then maximum = 1
		If maximum > 200 Then maximum = 200
		If _lobby.CreateSearch(UInt(maximum), _search) <> EEOSResult.Success Or Not _search Then Return False
		If _search.SetStringParameter("bucket", bucketId) <> EEOSResult.Success Then ReleaseSearch(); Return False
		For Local index:Int = 0 Until query.properties.Count()
			If _search.SetStringParameter(query.properties.KeyAt(index), query.properties.ValueAt(index)) <> EEOSResult.Success Then ReleaseSearch(); Return False
		Next
		_searchOpenSlots = query.requiredOpenSlots
		_searchRequest = _search.Find(_localUserId, Self)
		If Not _searchRequest Then ReleaseSearch(); Return False
		Return True
	End Method

	Method JoinLobby:Int(lobbyId:String) Override
		If _joinRequest Then Return False
		_joinDetails = DetailsForLobby(lobbyId)
		If Not _joinDetails Then Return False
		_joinOwnsDetails = False
		Local options:TEOSLobbyJoinOptions = New TEOSLobbyJoinOptions
		options.LocalUserId = _localUserId
		options.Details = _joinDetails
		options.PresenceEnabled = True
		_joinRequest = _lobby.Join(options, Self)
		Return _joinRequest <> Null
	End Method

	Method AcceptInvitation:Int(invitationId:String) Override
		If _joinRequest Then Return False
		If _lobby.CopyDetailsByInviteId(invitationId, _joinDetails) <> EEOSResult.Success Or Not _joinDetails Then Return False
		_joinOwnsDetails = True
		Local options:TEOSLobbyJoinOptions = New TEOSLobbyJoinOptions
		options.LocalUserId = _localUserId
		options.Details = _joinDetails
		options.PresenceEnabled = True
		_joinRequest = _lobby.Join(options, Self)
		Return _joinRequest <> Null
	End Method

	Method LeaveLobby:Int(lobbyId:String, owner:Int) Override
		If _leaveRequest Or _destroyRequest Then Return False
		If owner Then _destroyRequest = _lobby.Destroy(_localUserId, lobbyId, Self) Else _leaveRequest = _lobby.Leave(_localUserId, lobbyId, Self)
		Return _leaveRequest <> Null Or _destroyRequest <> Null
	End Method

	Method PublishStart:Int(lobbyId:String) Override
		If _updateRequest Then Return False
		Local modification:TEOSLobbyModification
		If _lobby.CreateModification(_localUserId, lobbyId, modification) <> EEOSResult.Success Or Not modification Then Return False
		Local result:EEOSResult = modification.SetPermissionLevel(EEOSLobbyPermissionLevel.InviteOnly)
		If result = EEOSResult.Success Then result = modification.SetInvitesAllowed(False)
		If result = EEOSResult.Success Then result = modification.AddStringAttribute(EOS_ONLINE_JOINABLE_KEY, "0")
		If result = EEOSResult.Success Then result = modification.AddStringAttribute(EOS_ONLINE_START_KEY, "1")
		If result = EEOSResult.Success Then
			_updatePurpose = 2
			_updateRequest = _lobby.Update(modification, Self)
		End If
		modification.Release()
		Return _updateRequest <> Null
	End Method

	Method InvitePlayer:Int(lobbyId:String, productUserId:String) Override
		If _inviteRequest Then Return False
		Local target:TEOSProductUserId = TEOSProductUserId.FromString(productUserId)
		If Not target Or Not target.IsValid() Then Return False
		_inviteRequest = _lobby.SendInvite(lobbyId, _localUserId, target, Self)
		Return _inviteRequest <> Null
	End Method

	Method LobbySnapshot:TEOSOnlineLobbySnapshot(lobbyId:String) Override
		Return CurrentSnapshot(lobbyId)
	End Method

	Method CreateTransport:INetTransport(remoteUserIds:String[], socketName:String, channelCount:Int, maxPacketSize:Size_T, initiateConnections:Int) Override
		_transportError = ""
		Local ids:TEOSProductUserId[] = New TEOSProductUserId[remoteUserIds.Length]
		For Local index:Int = 0 Until remoteUserIds.Length
			ids[index] = TEOSProductUserId.FromString(remoteUserIds[index])
			If Not ids[index] Or Not ids[index].IsValid() Then _transportError = "Lobby contained an invalid Product User ID"; Return Null
		Next
		Local transport:INetTransport = TEOSP2PTransport.Create(_platform, _p2p, _localUserId, ids, socketName, channelCount, maxPacketSize, True, initiateConnections)
		If Not transport Then _transportError = EOSP2PTransportCreateError()
		Return transport
	End Method

	Method TransportError:String() Override
		Return _transportError
	End Method

	Method Shutdown() Override
		If _lobbyUpdateSubscription Then _lobbyUpdateSubscription.Remove()
		If _memberUpdateSubscription Then _memberUpdateSubscription.Remove()
		If _memberStatusSubscription Then _memberStatusSubscription.Remove()
		If _inviteReceivedSubscription Then _inviteReceivedSubscription.Remove()
		If _inviteAcceptedSubscription Then _inviteAcceptedSubscription.Remove()
		_lobbyUpdateSubscription = Null; _memberUpdateSubscription = Null; _memberStatusSubscription = Null
		_inviteReceivedSubscription = Null; _inviteAcceptedSubscription = Null
		ReleaseSearch()
		If _joinOwnsDetails And _joinDetails Then _joinDetails.Release()
		_joinDetails = Null
		_joinOwnsDetails = False
		_listener = Null
	End Method

	Method OnEOSLobbyCreate(result:EEOSResult, lobbyId:String) Override
		_createRequest = Null
		If result <> EEOSResult.Success Then Local listener:IEOSOnlineBackendListener = _listener; _createOptions = Null; If listener Then listener.OnEOSOnlineLobbyCreated(result, Null); Return
		_createLobbyId = lobbyId
		_updatePurpose = 1
		If Not BeginMetadataUpdate(lobbyId, _createOptions) Then Local listener:IEOSOnlineBackendListener = _listener; _createOptions = Null; If listener Then listener.OnEOSOnlineLobbyCreated(EEOSResult.ServiceFailure, Null)
	End Method

	Method OnEOSLobbyUpdate(result:EEOSResult, lobbyId:String) Override
		Local purpose:Int = _updatePurpose
		_updatePurpose = 0
		_updateRequest = Null
		Local snapshot:TEOSOnlineLobbySnapshot
		If result = EEOSResult.Success Then snapshot = CurrentSnapshot(lobbyId)
		If purpose = 1 Then
			_createOptions = Null; _createLobbyId = ""
			If _listener Then _listener.OnEOSOnlineLobbyCreated(result, snapshot)
		Else If purpose = 2 Then
			If _listener Then _listener.OnEOSOnlineStartPublished(result, snapshot)
		End If
	End Method

	Method OnEOSLobbySearchFind(result:EEOSResult) Override
		_searchRequest = Null
		If result <> EEOSResult.Success Then
			If _listener Then _listener.OnEOSOnlineLobbySearch(result, New TEOSOnlineLobbyResults)
			Return
		End If
		Local foundDetails:TEOSLobbyDetails[] = New TEOSLobbyDetails[Int(_search.ResultCount())]
		Local foundSnapshots:TEOSOnlineLobbySnapshot[] = New TEOSOnlineLobbySnapshot[foundDetails.Length]
		Local accepted:Int
		For Local index:Int = 0 Until foundDetails.Length
			Local details:TEOSLobbyDetails
			If _search.CopyResultByIndex(UInt(index), details) <> EEOSResult.Success Or Not details Then Continue
			Local snapshot:TEOSOnlineLobbySnapshot = Snapshot(details)
			If Not snapshot Or snapshot.AvailableSlots < _searchOpenSlots Then details.Release(); Continue
			foundDetails[accepted] = details
			foundSnapshots[accepted] = snapshot
			accepted :+ 1
		Next
		_searchDetails = foundDetails[..accepted]
		_searchSnapshots = foundSnapshots[..accepted]
		If _listener Then
			Local results:TEOSOnlineLobbyResults = New TEOSOnlineLobbyResults
			results.Snapshots = _searchSnapshots[..]
			_listener.OnEOSOnlineLobbySearch(result, results)
		End If
	End Method

	Method OnEOSLobbyJoin(result:EEOSResult, lobbyId:String) Override
		_joinRequest = Null
		If _joinOwnsDetails And _joinDetails Then _joinDetails.Release()
		_joinDetails = Null
		_joinOwnsDetails = False
		Local snapshot:TEOSOnlineLobbySnapshot
		If result = EEOSResult.Success Then snapshot = CurrentSnapshot(lobbyId)
		If _listener Then _listener.OnEOSOnlineLobbyJoined(result, snapshot)
	End Method

	Method OnEOSLobbyLeave(result:EEOSResult, lobbyId:String) Override
		_leaveRequest = Null
		If _listener Then _listener.OnEOSOnlineLobbyLeft(result, lobbyId)
	End Method

	Method OnEOSLobbyDestroy(result:EEOSResult, lobbyId:String) Override
		_destroyRequest = Null
		If _listener Then _listener.OnEOSOnlineLobbyLeft(result, lobbyId)
	End Method

	Method OnEOSLobbySendInvite(result:EEOSResult, lobbyId:String) Override
		_inviteRequest = Null
	End Method

	Method OnEOSLobbyUpdateReceived(lobbyId:String) Override
		Local snapshot:TEOSOnlineLobbySnapshot = CurrentSnapshot(lobbyId)
		If snapshot And _listener Then _listener.OnEOSOnlineLobbyChanged(snapshot, "", EEOSLobbyMemberStatus.Joined)
	End Method

	Method OnEOSLobbyMemberUpdateReceived(lobbyId:String, targetUserId:TEOSProductUserId) Override
		Local snapshot:TEOSOnlineLobbySnapshot = CurrentSnapshot(lobbyId)
		If snapshot And _listener Then _listener.OnEOSOnlineLobbyChanged(snapshot, UserText(targetUserId), EEOSLobbyMemberStatus.Joined)
	End Method

	Method OnEOSLobbyMemberStatusReceived(lobbyId:String, targetUserId:TEOSProductUserId, status:EEOSLobbyMemberStatus) Override
		Local snapshot:TEOSOnlineLobbySnapshot = CurrentSnapshot(lobbyId)
		If _listener Then _listener.OnEOSOnlineLobbyChanged(snapshot, UserText(targetUserId), status)
	End Method

	Method OnEOSLobbyInviteReceived(inviteId:String, localUserId:TEOSProductUserId, senderUserId:TEOSProductUserId) Override
		If _listener Then _listener.OnEOSOnlineInvitation(inviteId, "", UserText(senderUserId), False)
	End Method

	Method OnEOSLobbyInviteAccepted(inviteId:String, localUserId:TEOSProductUserId, senderUserId:TEOSProductUserId, lobbyId:String) Override
		If _listener Then _listener.OnEOSOnlineInvitation(inviteId, lobbyId, UserText(senderUserId), True)
	End Method
End Type

Public

Type TEOSOnlineLobby Implements IOnlineLobby
	Field lobbyId:String
	Field lobbyName:String
	Field lobbyOwner:SOnlinePlayer
	Field maximumPlayers:Int
	Field joinable:Int
	Field members:SOnlinePlayer[] = New SOnlinePlayer[0]
	Field metadata:TOnlineProperties = New TOnlineProperties

	Method Id:String() Override Return lobbyId End Method
	Method Name:String() Override Return lobbyName End Method
	Method Owner:SOnlinePlayer() Override Return lobbyOwner End Method
	Method MaxPlayers:Int() Override Return maximumPlayers End Method
	Method IsJoinable:Int() Override Return joinable End Method
	Method MemberCount:Int() Override Return members.Length End Method
	Method Member:SOnlinePlayer(index:Int) Override If index < 0 Or index >= members.Length Then Return New SOnlinePlayer Else Return members[index] End Method
	Method Properties:TOnlineProperties() Override Return metadata End Method
End Type

Type TEOSOnlineService Implements IOnlineService, IEOSOnlineBackendListener
	Private
	Field _backend:IEOSOnlineBackend
	Field _session:TEOSSessionCoordinator
	Field _bucketId:String
	Field _socketName:String
	Field _channelCount:Int
	Field _maxPacketSize:Size_T
	Field _state:EOnlineServiceState
	Field _nextRequestId:UInt = 1
	Field _events:SOnlineEvent[] = New SOnlineEvent[EOS_ONLINE_EVENT_CAPACITY]
	Field _eventRead:Int, _eventWrite:Int, _eventCount:Int
	Field _droppedEvents:UInt
	Field _openRequestId:UInt
	Field _createRequestId:UInt
	Field _cancelCreateRequestId:UInt
	Field _findRequestId:UInt
	Field _cancelFindRequestId:UInt
	Field _findResultsRequestId:UInt
	Field _findResults:IOnlineLobby[] = New IOnlineLobby[0]
	Field _joinRequestId:UInt
	Field _joinOperation:EOnlineOperation
	Field _cancelJoinRequestId:UInt
	Field _cancelCleanupRequestId:UInt
	Field _cancelCleanupOperation:EOnlineOperation
	Field _cancelCleanupLobbyId:String
	Field _leaveRequestId:UInt
	Field _closeRequestId:UInt
	Field _startRequestId:UInt
	Field _readyRequestId:UInt
	Field _readyTransport:INetTransport
	Field _readyMatchInfo:SOnlineMatchInfo
	Field _current:TEOSOnlineLobby
	Field _nextLobbyRefreshAt:Int

	Method New(backend:IEOSOnlineBackend, bucketId:String, socketName:String, channelCount:Int, maxPacketSize:Size_T, session:TEOSSessionCoordinator = Null)
		_backend = backend
		_bucketId = bucketId
		_socketName = socketName
		_channelCount = channelCount
		_maxPacketSize = maxPacketSize
		_session = session
	End Method

	Method NextRequestId:UInt()
		Local result:UInt = _nextRequestId
		_nextRequestId :+ 1
		If _nextRequestId = 0 Then _nextRequestId = 1
		Return result
	End Method

	Method Queue(event:SOnlineEvent)
		If _eventCount = _events.Length Then _droppedEvents :+ 1; Return
		_events[_eventWrite] = event
		_eventWrite = (_eventWrite + 1) Mod _events.Length
		_eventCount :+ 1
	End Method

	Method QueueCancelled(operation:EOnlineOperation, requestId:UInt, subjectId:String = "")
		Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, operation, requestId, EOnlineError.Cancelled, 0, subjectId, New SOnlinePlayer, "Operation cancelled"))
	End Method

	Method BeginCancelledLobbyCleanup(operation:EOnlineOperation, requestId:UInt, snapshot:TEOSOnlineLobbySnapshot)
		_cancelCleanupRequestId = requestId
		_cancelCleanupOperation = operation
		_cancelCleanupLobbyId = snapshot.LobbyId
		Local owner:Int = snapshot.OwnerId = _backend.LocalUserId()
		If Not _backend.LeaveLobby(snapshot.LobbyId, owner) Then
			_cancelCleanupRequestId = 0
			_cancelCleanupOperation = EOnlineOperation.None
			_cancelCleanupLobbyId = ""
			Failure(operation, requestId, EEOSResult.ServiceFailure, snapshot.LobbyId, "EOS could not clean up the cancelled lobby operation")
		End If
	End Method

	Method Player:SOnlinePlayer(id:String)
		If Not id Then Return New SOnlinePlayer
		Local local:Int = id = _backend.LocalUserId()
		Local name:String = id
		If local And _backend.LocalDisplayName() Then name = _backend.LocalDisplayName()
		Return New SOnlinePlayer(id, name, local)
	End Method

	Method Lobby:TEOSOnlineLobby(snapshot:TEOSOnlineLobbySnapshot)
		If Not snapshot Then Return Null
		Local result:TEOSOnlineLobby = New TEOSOnlineLobby
		result.lobbyId = snapshot.LobbyId; result.lobbyName = snapshot.Name
		result.lobbyOwner = Player(snapshot.OwnerId); result.maximumPlayers = snapshot.MaximumPlayers
		result.joinable = snapshot.Joinable
		result.members = New SOnlinePlayer[snapshot.MemberIds.Length]
		For Local index:Int = 0 Until snapshot.MemberIds.Length
			result.members[index] = Player(snapshot.MemberIds[index])
		Next
		For Local index:Int = 0 Until snapshot.Properties.Count()
			result.metadata.Set(snapshot.Properties.KeyAt(index), snapshot.Properties.ValueAt(index))
		Next
		Return result
	End Method

	Method HasStarted:Int(snapshot:TEOSOnlineLobbySnapshot)
		If Not snapshot Then Return False
		If snapshot.StartSignaled Then Return True
		Local found:Int
		If snapshot.Properties.Value(EOS_ONLINE_START_KEY, found) = "1" And found Then Return True
		' PublishStart writes both attributes in one EOS lobby update. Treat the
		' explicit owner-controlled joinable marker as a fallback because EOS can
		' expose that attribute before the start marker in another member's cache.
		Return snapshot.Properties.Value(EOS_ONLINE_JOINABLE_KEY, found) = "0" And found
	End Method

	Method PrepareMatch(snapshot:TEOSOnlineLobbySnapshot)
		If Not snapshot Or Not _startRequestId Or _readyTransport Or snapshot.MemberIds.Length < 2 Then Return
		Local localId:String = _backend.LocalUserId()
		Local host:Int = snapshot.OwnerId = localId
		Local remoteIds:String[]
		If host Then
			remoteIds = New String[snapshot.MemberIds.Length - 1]
			Local target:Int
			For Local id:String = EachIn snapshot.MemberIds
				If id <> localId Then remoteIds[target] = id; target :+ 1
			Next
			If target <> remoteIds.Length Then Return
		Else
			remoteIds = [snapshot.OwnerId]
		End If
		' The owner listens; joining peers initiate. This produces one EOS session
		' per owner/client link instead of competing simultaneous session GUIDs.
		_readyTransport = _backend.CreateTransport(remoteIds, _socketName, _channelCount, _maxPacketSize, Not host)
		If Not _readyTransport Then
			Local detail:String = _backend.TransportError()
			If Not detail Then detail = "Could not create EOS P2P transport"
			Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, EOnlineOperation.StartMatch, _startRequestId, EOnlineError.ProviderFailure, 0, snapshot.LobbyId, New SOnlinePlayer, detail))
			_startRequestId = 0
			Return
		End If
		Local hostPeer:SNetPeer
		If Not host Then hostPeer = New SNetPeer(1, 1)
		_readyMatchInfo = New SOnlineMatchInfo(snapshot.MemberIds.Length, host, hostPeer)
		_readyRequestId = _startRequestId
		_startRequestId = 0
		Queue(New SOnlineEvent(EOnlineEventKind.MatchReady, EOnlineOperation.StartMatch, _readyRequestId, EOnlineError.None, 0, snapshot.LobbyId, New SOnlinePlayer, ""))
	End Method

	Method Failure(operation:EOnlineOperation, requestId:UInt, result:EEOSResult, subject:String, detail:String)
		Local error:EOnlineError = EOnlineError.ProviderFailure
		Select result
			Case EEOSResult.NoConnection, EEOSResult.NetworkDisconnected
				error = EOnlineError.Network
			Case EEOSResult.TimedOut
				error = EOnlineError.Timeout
			Case EEOSResult.AuthExpired, EEOSResult.InvalidAuth, EEOSResult.InvalidUser
				error = EOnlineError.Authentication
			Case EEOSResult.AccessDenied, EEOSResult.MissingPermissions
				error = EOnlineError.Rejected
			Case EEOSResult.InvalidParameters
				error = EOnlineError.InvalidArgument
			Case EEOSResult.Canceled
				error = EOnlineError.Cancelled
		End Select
		Queue(New SOnlineEvent(EOnlineEventKind.OperationFailed, operation, requestId, error, Int(result), subject, New SOnlinePlayer, detail))
	End Method

	Method PropertiesValid:Int(properties:TOnlineProperties)
		If Not properties Then Return True
		For Local index:Int = 0 Until properties.Count()
			Local key:String = properties.KeyAt(index)
			If key = EOS_ONLINE_NAME_KEY Or key = EOS_ONLINE_JOINABLE_KEY Or key = EOS_ONLINE_START_KEY Or key = "bucket" Then Return False
		Next
		Return True
	End Method

	Method FinishClose()
		_backend.Shutdown()
		_current = Null
		_readyTransport = Null
		_state = EOnlineServiceState.Closed
		Local id:UInt = _closeRequestId
		_closeRequestId = 0
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceClosed, EOnlineOperation.Close, id, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
	End Method

	Public
	Function Create:TEOSOnlineService(platform:TEOSPlatform, localUserId:TEOSProductUserId, localDisplayName:String, bucketId:String, socketName:String = "GAMENET", channelCount:Int = 4, maxPacketSize:Size_T = EOS_P2P_DEFAULT_MAX_PACKET_SIZE)
		If Not platform Or Not platform.IsValid() Or Not localUserId Or Not localUserId.IsValid() Then
			Return Null
		End If
		Return CreateForBackend(New TNativeEOSOnlineBackend(platform, localUserId, localDisplayName), bucketId, socketName, channelCount, maxPacketSize)
	End Function

	Rem
	bbdoc: Creates an EOS online service from a ready managed session.
	about: The service pumps the session and observes session loss. The session
	remains responsible for EOS platform ticking, so the native backend does not
	tick the same platform a second time.
	End Rem
	Function Create:TEOSOnlineService(session:TEOSSessionCoordinator, localDisplayName:String, bucketId:String, socketName:String = "GAMENET", channelCount:Int = 4, maxPacketSize:Size_T = EOS_P2P_DEFAULT_MAX_PACKET_SIZE)
		If Not session Or Not session.IsReady() Then
			Return Null
		End If
		Local platform:TEOSPlatform = session.Platform()
		Local localUserId:TEOSProductUserId = session.ProductUserId()
		If Not platform Or Not platform.IsValid() Or Not localUserId Or Not localUserId.IsValid() Then
			Return Null
		End If
		Local backend:IEOSOnlineBackend = New TNativeEOSOnlineBackend(platform, localUserId, localDisplayName, False)
		Return CreateForBackend(backend, bucketId, socketName, channelCount, maxPacketSize, session)
	End Function

	Function CreateForBackend:TEOSOnlineService(backend:IEOSOnlineBackend, bucketId:String, socketName:String = "GAMENET", channelCount:Int = 4, maxPacketSize:Size_T = EOS_P2P_DEFAULT_MAX_PACKET_SIZE, session:TEOSSessionCoordinator = Null)
		If Not backend Or Not bucketId Or socketName.Length < 1 Or socketName.Length > 32 Or channelCount < 1 Or channelCount > 256 Or maxPacketSize < 1 Or maxPacketSize > EOS_P2P_DEFAULT_MAX_PACKET_SIZE Then
			Return Null
		End If
		Return New TEOSOnlineService(backend, bucketId, socketName, channelCount, maxPacketSize, session)
	End Function

	Method ProviderName:String() Override Return "Epic Online Services" End Method
	Method Capabilities:EOnlineCapability() Override Return EOnlineCapability.CreateLobby | EOnlineCapability.FindLobbies | EOnlineCapability.Invitations | EOnlineCapability.MatchTransport End Method
	Method State:EOnlineServiceState() Override Return _state End Method
	Method LocalPlayer:SOnlinePlayer() Override If _state <> EOnlineServiceState.Ready Then Return New SOnlinePlayer Else Return Player(_backend.LocalUserId()) End Method

	Method Open:UInt() Override
		If _state <> EOnlineServiceState.Closed Then
			Return 0
		End If
		_openRequestId = NextRequestId()
		_state = EOnlineServiceState.Opening
		If _session And Not _session.IsUsable() Then
			_state = EOnlineServiceState.Failed
			Failure(EOnlineOperation.Open, _openRequestId, _session.LastResult(), "", "EOS login session is not ready")
			Return _openRequestId
		End If
		If Not _backend.Initialize(Self) Then
			_state = EOnlineServiceState.Failed
			Failure(EOnlineOperation.Open, _openRequestId, EEOSResult.InvalidState, "", "EOS platform, Product User, or Lobby notifications are unavailable")
			Return _openRequestId
		End If
		_state = EOnlineServiceState.Ready
		Queue(New SOnlineEvent(EOnlineEventKind.ServiceReady, EOnlineOperation.Open, _openRequestId, EOnlineError.None, 0, "", Player(_backend.LocalUserId()), ""))
		Return _openRequestId
	End Method

	Method Pump() Override
		If _session Then
			_session.Tick()
			If _state <> EOnlineServiceState.Closed And _state <> EOnlineServiceState.Failed And Not _session.IsUsable() Then
				_backend.Shutdown()
				_current = Null
				_readyTransport = Null
				_state = EOnlineServiceState.Failed
				Failure(EOnlineOperation.None, 0, _session.LastResult(), "", "EOS login session ended")
				Return
			End If
		End If
		If _state = EOnlineServiceState.Closed Then Return
		_backend.Pump()
		If _state = EOnlineServiceState.Ready And _current And MilliSecs() >= _nextLobbyRefreshAt Then
			_nextLobbyRefreshAt = MilliSecs() + 250
			Local snapshot:TEOSOnlineLobbySnapshot = _backend.LobbySnapshot(_current.Id())
			If snapshot Then
				_current = Lobby(snapshot)
				If _startRequestId And HasStarted(snapshot) Then PrepareMatch(snapshot)
			End If
		End If
	End Method
	Method Poll:Int(event:SOnlineEvent Var) Override
		If _eventCount = 0 Then event = New SOnlineEvent; Return False
		event = _events[_eventRead]; _events[_eventRead] = New SOnlineEvent
		_eventRead = (_eventRead + 1) Mod _events.Length; _eventCount :- 1
		Return True
	End Method

	Method CreateLobby:UInt(options:TOnlineLobbyOptions) Override
		If _state <> EOnlineServiceState.Ready Or Not options Or _current Or _createRequestId Or options.maxPlayers < 1 Or options.maxPlayers > 64 Or Not PropertiesValid(options.properties) Then Return 0
		_createRequestId = NextRequestId()
		If Not _backend.CreateLobby(options, _bucketId) Then _createRequestId = 0
		Return _createRequestId
	End Method

	Method FindLobbies:UInt(query:TOnlineLobbyQuery) Override
		If _state <> EOnlineServiceState.Ready Or Not query Or _findRequestId Or _joinRequestId Or query.maximumResults < 1 Or Not PropertiesValid(query.properties) Then Return 0
		_findRequestId = NextRequestId()
		If Not _backend.FindLobbies(query, _bucketId) Then _findRequestId = 0
		Return _findRequestId
	End Method

	Method LobbyResultCount:Int(requestId:UInt) Override If requestId = _findResultsRequestId Then Return _findResults.Length Else Return 0 End Method
	Method LobbyResult:IOnlineLobby(requestId:UInt, index:Int) Override If requestId = _findResultsRequestId And index >= 0 And index < _findResults.Length Then Return _findResults[index] Else Return Null End Method
	Method CurrentLobby:IOnlineLobby() Override Return _current End Method

	Method JoinLobby:UInt(lobbyId:String) Override
		If _state <> EOnlineServiceState.Ready Or _current Or _joinRequestId Or Not lobbyId Then Return 0
		_joinRequestId = NextRequestId(); _joinOperation = EOnlineOperation.JoinLobby
		If Not _backend.JoinLobby(lobbyId) Then _joinRequestId = 0; Return 0
		Return _joinRequestId
	End Method

	Method LeaveLobby:UInt() Override
		If Not _current Or _leaveRequestId Then Return 0
		_leaveRequestId = NextRequestId()
		If Not _backend.LeaveLobby(_current.Id(), _current.Owner().IsLocal()) Then _leaveRequestId = 0; Return 0
		Return _leaveRequestId
	End Method

	Method AcceptInvitation:UInt(invitationId:String) Override
		If _state <> EOnlineServiceState.Ready Or _current Or _joinRequestId Or Not invitationId Then Return 0
		_joinRequestId = NextRequestId(); _joinOperation = EOnlineOperation.AcceptInvitation
		If Not _backend.AcceptInvitation(invitationId) Then _joinRequestId = 0; Return 0
		Return _joinRequestId
	End Method

	Method InvitePlayer:Int(productUserId:String)
		Return _state = EOnlineServiceState.Ready And _current And _backend.InvitePlayer(_current.Id(), productUserId)
	End Method

	Method StartMatchmaking:UInt(request:TOnlineMatchmakingRequest) Override Return 0 End Method
	Method CancelMatchmaking:UInt(requestId:UInt) Override Return 0 End Method

	Method CancelOperation:Int(requestId:UInt) Override
		If requestId = 0 Or _cancelCleanupRequestId Then
			Return False
		End If
		If requestId = _createRequestId And _cancelCreateRequestId = 0 Then
			_cancelCreateRequestId = requestId
			Return True
		End If
		If requestId = _findRequestId And _cancelFindRequestId = 0 Then
			_cancelFindRequestId = requestId
			Return True
		End If
		If requestId = _joinRequestId And _cancelJoinRequestId = 0 Then
			_cancelJoinRequestId = requestId
			Return True
		End If
		Return False
	End Method

	Method StartMatch:UInt() Override
		If Not _current Or _startRequestId Or _readyTransport Or _current.MemberCount() < 2 Then Return 0
		_startRequestId = NextRequestId()
		Local requestId:UInt = _startRequestId
		If _current.Owner().IsLocal() Then
			If Not _backend.PublishStart(_current.Id()) Then _startRequestId = 0; Return 0
		Else
			Local found:Int
			If _current.Properties().Value(EOS_ONLINE_START_KEY, found) = "1" And found Then
				Local snapshot:TEOSOnlineLobbySnapshot = New TEOSOnlineLobbySnapshot
				snapshot.LobbyId = _current.Id(); snapshot.OwnerId = _current.Owner().Id(); snapshot.MemberIds = New String[_current.MemberCount()]
				For Local index:Int = 0 Until _current.MemberCount(); snapshot.MemberIds[index] = _current.Member(index).Id(); Next
				PrepareMatch(snapshot)
			End If
		End If
		Return requestId
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
		_readyTransport = Null; _readyRequestId = 0; _readyMatchInfo = New SOnlineMatchInfo
		Return result
	End Method

	Method Close:UInt() Override
		If _state = EOnlineServiceState.Closed Or _state = EOnlineServiceState.Closing Then Return 0
		_closeRequestId = NextRequestId(); _state = EOnlineServiceState.Closing
		Local requestId:UInt = _closeRequestId
		If _readyTransport Then _readyTransport.Close()
		If _current And _backend.LeaveLobby(_current.Id(), _current.Owner().IsLocal()) Then Return requestId
		FinishClose()
		Return requestId
	End Method

	Method OnEOSOnlineLobbyCreated(result:EEOSResult, snapshot:TEOSOnlineLobbySnapshot) Override
		Local id:UInt = _createRequestId; _createRequestId = 0
		If id And id = _cancelCreateRequestId Then
			_cancelCreateRequestId = 0
			If result = EEOSResult.Success And snapshot Then
				BeginCancelledLobbyCleanup(EOnlineOperation.CreateLobby, id, snapshot)
			Else
				QueueCancelled(EOnlineOperation.CreateLobby, id)
			End If
			Return
		End If
		If result <> EEOSResult.Success Or Not snapshot Then Failure(EOnlineOperation.CreateLobby, id, result, "", "EOS could not create the lobby"); Return
		_current = Lobby(snapshot)
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyCreated, EOnlineOperation.CreateLobby, id, EOnlineError.None, 0, snapshot.LobbyId, New SOnlinePlayer, ""))
	End Method

	Method OnEOSOnlineLobbySearch(result:EEOSResult, results:TEOSOnlineLobbyResults) Override
		Local id:UInt = _findRequestId; _findRequestId = 0
		If id And id = _cancelFindRequestId Then
			_cancelFindRequestId = 0
			_findResults = New IOnlineLobby[0]
			_findResultsRequestId = 0
			QueueCancelled(EOnlineOperation.FindLobbies, id)
			Return
		End If
		If result <> EEOSResult.Success Then Failure(EOnlineOperation.FindLobbies, id, result, "", "EOS lobby search failed"); Return
		Local snapshots:TEOSOnlineLobbySnapshot[] = results.Snapshots
		_findResults = New IOnlineLobby[snapshots.Length]
		For Local index:Int = 0 Until snapshots.Length; _findResults[index] = Lobby(snapshots[index]); Next
		_findResultsRequestId = id
		Queue(New SOnlineEvent(EOnlineEventKind.LobbySearchCompleted, EOnlineOperation.FindLobbies, id, EOnlineError.None, 0, "", New SOnlinePlayer, ""))
	End Method

	Method OnEOSOnlineLobbyJoined(result:EEOSResult, snapshot:TEOSOnlineLobbySnapshot) Override
		Local id:UInt = _joinRequestId; Local operation:EOnlineOperation = _joinOperation
		_joinRequestId = 0; _joinOperation = EOnlineOperation.None
		If id And id = _cancelJoinRequestId Then
			_cancelJoinRequestId = 0
			If result = EEOSResult.Success And snapshot Then
				BeginCancelledLobbyCleanup(operation, id, snapshot)
			Else
				QueueCancelled(operation, id)
			End If
			Return
		End If
		If result <> EEOSResult.Success Or Not snapshot Then Failure(operation, id, result, "", "EOS rejected the lobby join"); Return
		_current = Lobby(snapshot)
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyJoined, operation, id, EOnlineError.None, 0, snapshot.LobbyId, New SOnlinePlayer, ""))
	End Method

	Method OnEOSOnlineLobbyLeft(result:EEOSResult, lobbyId:String) Override
		If _state = EOnlineServiceState.Closing Then
			FinishClose()
			Return
		End If
		If _cancelCleanupRequestId Then
			Local id:UInt = _cancelCleanupRequestId
			Local operation:EOnlineOperation = _cancelCleanupOperation
			Local subjectId:String = _cancelCleanupLobbyId
			_cancelCleanupRequestId = 0
			_cancelCleanupOperation = EOnlineOperation.None
			_cancelCleanupLobbyId = ""
			If result <> EEOSResult.Success Then
				Failure(operation, id, result, subjectId, "EOS could not clean up the cancelled lobby operation")
				Return
			End If
			QueueCancelled(operation, id, subjectId)
			Return
		End If
		Local id:UInt = _leaveRequestId; _leaveRequestId = 0
		If result <> EEOSResult.Success Then Failure(EOnlineOperation.LeaveLobby, id, result, lobbyId, "EOS could not leave the lobby"); Return
		_current = Null
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyLeft, EOnlineOperation.LeaveLobby, id, EOnlineError.None, 0, lobbyId, New SOnlinePlayer, ""))
	End Method

	Method OnEOSOnlineStartPublished(result:EEOSResult, snapshot:TEOSOnlineLobbySnapshot) Override
		If result <> EEOSResult.Success Or Not snapshot Then Local id:UInt = _startRequestId; _startRequestId = 0; Failure(EOnlineOperation.StartMatch, id, result, "", "EOS could not publish the match start"); Return
		_current = Lobby(snapshot); PrepareMatch(snapshot)
	End Method

	Method OnEOSOnlineLobbyChanged(snapshot:TEOSOnlineLobbySnapshot, targetUserId:String, status:EEOSLobbyMemberStatus) Override
		If Not _current Then Return
		If Not snapshot Then
			If targetUserId = _backend.LocalUserId() And status <> EEOSLobbyMemberStatus.Joined Then
				Local lobbyId:String = _current.Id()
				_current = Null
				Queue(New SOnlineEvent(EOnlineEventKind.LobbyLeft, EOnlineOperation.None, 0, EOnlineError.Rejected, Int(status), lobbyId, Player(targetUserId), "EOS lobby membership ended"))
			End If
			Return
		End If
		If snapshot.LobbyId <> _current.Id() Then Return
		_current = Lobby(snapshot)
		Queue(New SOnlineEvent(EOnlineEventKind.LobbyChanged, EOnlineOperation.None, 0, EOnlineError.None, Int(status), snapshot.LobbyId, Player(targetUserId), ""))
		If _startRequestId And HasStarted(snapshot) Then PrepareMatch(snapshot)
	End Method

	Method OnEOSOnlineInvitation(invitationId:String, lobbyId:String, senderUserId:String, accepted:Int) Override
		Local detail:String
		If accepted Then detail = "EOS invitation accepted"
		Queue(New SOnlineEvent(EOnlineEventKind.InvitationReceived, EOnlineOperation.None, 0, EOnlineError.None, 0, invitationId, Player(senderUserId), detail))
	End Method

	Method DroppedEvents:UInt() Return _droppedEvents End Method
End Type

?
