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
bbdoc: Optional backend-neutral online lobby and matchmaking contracts.
End Rem
Module GameNet.Online

?bmxng2

ModuleInfo "Version: 0.1"
ModuleInfo "Author: Bruce A Henderson and contributors"
ModuleInfo "License: zlib/libpng"
ModuleInfo "Copyright: 2026 Bruce A Henderson and contributors"

ModuleInfo "History: 0.1 Initial online service contract"

Import GameNet.Core
Import BRL.Blitz

Rem
bbdoc: Optional facilities advertised by an online service adapter.
End Rem
Enum EOnlineCapability:UInt Flags
	None = 0
	CreateLobby = 1
	FindLobbies = 2
	Invitations = 4
	Matchmaking = 8
	MatchTransport = 16
	HostMigration = 32
	Parties = 64
	AuthoritativeMatch = 128
	DedicatedServer = 256
End Enum

Rem
bbdoc: Returns True when every bit in @required is advertised by @available.
End Rem
Function OnlineHasCapabilities:Int(available:EOnlineCapability, required:EOnlineCapability)
	Return (available & required) = required
End Function

Rem
bbdoc: Current connection state of an online service adapter.
End Rem
Enum EOnlineServiceState:Byte
	Closed
	Opening
	Ready
	Closing
	Failed
End Enum

Rem
bbdoc: Visibility requested for a newly created lobby.
End Rem
Enum EOnlineLobbyVisibility:Byte
	Private
	FriendsOnly
	Public
End Enum

Rem
bbdoc: Backend-neutral operation associated with an online event.
End Rem
Enum EOnlineOperation:Byte
	None
	Open
	CreateLobby
	FindLobbies
	JoinLobby
	LeaveLobby
	AcceptInvitation
	StartMatchmaking
	CancelMatchmaking
	StartMatch
	Close
End Enum

Rem
bbdoc: Portable error category for an online operation.
about: ProviderCode and Detail on #SOnlineEvent retain more precise diagnostics.
End Rem
Enum EOnlineError:Byte
	None
	Unsupported
	InvalidState
	InvalidArgument
	Cancelled
	Authentication
	Network
	Timeout
	Rejected
	ProviderFailure
End Enum

Rem
bbdoc: An application-visible online service event.
End Rem
Enum EOnlineEventKind:Byte
	None
	ServiceReady
	ServiceClosed
	LobbyCreated
	LobbySearchCompleted
	LobbyJoined
	LobbyChanged
	LobbyLeft
	InvitationReceived
	MatchmakingStarted
	MatchmakingCancelled
	MatchReady
	OperationFailed
End Enum

Rem
bbdoc: A provider-independent online player identity.
about: Id is opaque and meaningful only to the provider named by the service.
End Rem
Struct SOnlinePlayer
	Private
	Field _id:String
	Field _displayName:String
	Field _local:Int

	Public
	Method New()
	End Method

	Method New(id:String, displayName:String, local:Int = False)
		_id = id
		_displayName = displayName
		_local = local
	End Method

	Method Id:String()
		Return _id
	End Method

	Method DisplayName:String()
		Return _displayName
	End Method

	Method IsLocal:Int()
		Return _local
	End Method

	Method IsValid:Int()
		Return _id.Length > 0
	End Method
End Struct

Rem
bbdoc: Small string property collection used for provider lobby metadata.
about: Providers may impose stricter key, value, count, or indexing limits.
Applications should use short keys and values and consult provider documentation.
End Rem
Type TOnlineProperties
	Private
	Field _keys:String[] = New String[0]
	Field _values:String[] = New String[0]

	Public
	Method Count:Int()
		Return _keys.Length
	End Method

	Method Set:Int(key:String, value:String)
		If key.Length = 0 Then Return False
		For Local index:Int = 0 Until _keys.Length
			If _keys[index] = key Then
				_values[index] = value
				Return True
			End If
		Next
		Local count:Int = _keys.Length
		_keys = _keys[..count + 1]
		_values = _values[..count + 1]
		_keys[count] = key
		_values[count] = value
		Return True
	End Method

	Method Contains:Int(key:String)
		For Local existing:String = EachIn _keys
			If existing = key Then Return True
		Next
		Return False
	End Method

	Method Value:String(key:String, found:Int Var)
		For Local index:Int = 0 Until _keys.Length
			If _keys[index] = key Then
				found = True
				Return _values[index]
			End If
		Next
		found = False
		Return ""
	End Method

	Method KeyAt:String(index:Int)
		If index < 0 Or index >= _keys.Length Then Return ""
		Return _keys[index]
	End Method

	Method ValueAt:String(index:Int)
		If index < 0 Or index >= _values.Length Then Return ""
		Return _values[index]
	End Method

	Method Clear()
		_keys = New String[0]
		_values = New String[0]
	End Method
End Type

Rem
bbdoc: Options shared by providers which can create lobbies.
End Rem
Type TOnlineLobbyOptions
	Field name:String
	Field minPlayers:Int = 1
	Field maxPlayers:Int = 2
	Field visibility:EOnlineLobbyVisibility = EOnlineLobbyVisibility.Private
	Field joinable:Int = True
	Field properties:TOnlineProperties = New TOnlineProperties
End Type

Rem
bbdoc: Portable filters for finding existing lobbies.
about: Properties are exact-match filters. A provider may support further
filtering through its backend-specific adapter API.
End Rem
Type TOnlineLobbyQuery
	Field requiredOpenSlots:Int = 1
	Field maximumResults:Int = 20
	Field properties:TOnlineProperties = New TOnlineProperties
End Type

Rem
bbdoc: Portable request for automatic matchmaking.
about: Properties describe game-defined criteria such as mode or ruleset.
Provider-specific adapters may expose skill, latency, team, or region controls.
End Rem
Type TOnlineMatchmakingRequest
	Field minPlayers:Int = 2
	Field maxPlayers:Int = 2
	Field properties:TOnlineProperties = New TOnlineProperties
End Type

Rem
bbdoc: Read-only snapshot of one provider lobby.
about: Returned players and properties are snapshots owned by the provider.
End Rem
Interface IOnlineLobby
	Method Id:String()
	Method Name:String()
	Method Owner:SOnlinePlayer()
	Method MaxPlayers:Int()
	Method IsJoinable:Int()
	Method MemberCount:Int()
	Method Member:SOnlinePlayer(index:Int)
	Method Properties:TOnlineProperties()
End Interface

Rem
bbdoc: Describes how a connected transport enters a host/client GameNet session.
about: When IsSessionHost is True, SessionHostPeer is invalid and the game
creates a host session. Otherwise it creates a client session connected to
SessionHostPeer. PlayerCount includes the local player.
End Rem
Struct SOnlineMatchInfo
	Private
	Field _playerCount:Int
	Field _sessionHost:Int
	Field _sessionHostPeer:SNetPeer

	Public
	Method New()
	End Method

	Method New(playerCount:Int, sessionHost:Int, sessionHostPeer:SNetPeer)
		_playerCount = playerCount
		_sessionHost = sessionHost
		_sessionHostPeer = sessionHostPeer
	End Method

	Method IsValid:Int()
		Return _playerCount > 0 And (_sessionHost Or _sessionHostPeer.IsValid())
	End Method

	Method PlayerCount:Int()
		Return _playerCount
	End Method

	Method IsSessionHost:Int()
		Return _sessionHost
	End Method

	Method SessionHostPeer:SNetPeer()
		Return _sessionHostPeer
	End Method
End Struct

Rem
bbdoc: One asynchronous online-service notification.
about: RequestId correlates completion with the nonzero value returned when the
operation began. SubjectId contains a lobby, invitation, or match identifier as
appropriate. ProviderCode is backend-defined and Error is portable.
End Rem
Struct SOnlineEvent
	Private
	Field _kind:EOnlineEventKind
	Field _operation:EOnlineOperation
	Field _requestId:UInt
	Field _error:EOnlineError
	Field _providerCode:Int
	Field _subjectId:String
	Field _player:SOnlinePlayer
	Field _detail:String

	Public
	Method New()
	End Method

	Method New(kind:EOnlineEventKind, operation:EOnlineOperation, requestId:UInt, error:EOnlineError, providerCode:Int, subjectId:String, player:SOnlinePlayer, detail:String)
		_kind = kind
		_operation = operation
		_requestId = requestId
		_error = error
		_providerCode = providerCode
		_subjectId = subjectId
		_player = player
		_detail = detail
	End Method

	Method Kind:EOnlineEventKind()
		Return _kind
	End Method

	Method Operation:EOnlineOperation()
		Return _operation
	End Method

	Method RequestId:UInt()
		Return _requestId
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

	Method Detail:String()
		Return _detail
	End Method
End Struct

Rem
bbdoc: A configured online-service adapter such as GameKit, Steam, Nakama, or EOS.
about: All remote operations are asynchronous. A nonzero request id means the
operation was accepted; completion is reported by #Poll. Zero means it could
not begin. Call #Pump regularly so providers can dispatch callbacks.

Lobby and matchmaking services are optional and independent from direct LAN or
known-address connections. When MatchReady is emitted, #TakeMatchTransport
transfers ownership of the corresponding transport to the application. It may
be called once for that request id.
End Rem
Interface IOnlineService
	Method ProviderName:String()
	Method Capabilities:EOnlineCapability()
	Method State:EOnlineServiceState()
	Method LocalPlayer:SOnlinePlayer()
	Method Open:UInt()
	Method Pump()
	Method Poll:Int(event:SOnlineEvent Var)
	Method CreateLobby:UInt(options:TOnlineLobbyOptions)
	Method FindLobbies:UInt(query:TOnlineLobbyQuery)
	Method LobbyResultCount:Int(requestId:UInt)
	Method LobbyResult:IOnlineLobby(requestId:UInt, index:Int)
	Method CurrentLobby:IOnlineLobby()
	Method JoinLobby:UInt(lobbyId:String)
	Method LeaveLobby:UInt()
	Method AcceptInvitation:UInt(invitationId:String)
	Method StartMatchmaking:UInt(request:TOnlineMatchmakingRequest)
	Method CancelMatchmaking:UInt(requestId:UInt)
	Method StartMatch:UInt()
	Method MatchInfo:Int(requestId:UInt, info:SOnlineMatchInfo Var)
	Method TakeMatchTransport:INetTransport(requestId:UInt)
	Method Close:UInt()
End Interface
