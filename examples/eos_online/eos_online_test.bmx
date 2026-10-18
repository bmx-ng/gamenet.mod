' Copyright (c) 2026 Bruce A Henderson and contributors
' Licensed under the zlib/libpng license.

SuperStrict

Framework Max2D.SDL3RenderMax2D
Import GameNet.EOSOnline
Import BRL.FileSystem
Import BRL.PolledInput
Import BRL.StandardIO
Import BRL.TextStream

Const WINDOW_WIDTH:Int = 860
Const WINDOW_HEIGHT:Int = 480
Const TEST_BUCKET:String = "gamenet-eos-online-test"
Const LOG_PATH:String = "/tmp/gamenet-eos-online.log"

Global statusTitle:String = "Preparing the EOSOnline test..."
Global statusDetail:String = "Both accounts will sign in through the Developer Authentication Tool."
Global eventSummary:String = "Waiting for both Product Users."
Global latestLog:String
Global statusKind:Int
Global done:Int
Global succeeded:Int
Global pendingProductUser:Int
Global logOutput:TStream

Function Log(message:String)
	If Not logOutput Then
		Return
	End If
	WriteLine logOutput, "[" + MilliSecs() + "] " + message
	FlushStream logOutput
End Function

Function SideName:String(hostSide:Int)
	If hostSide Then
		Return "host"
	End If
	Return "client"
End Function

Type TConsoleLogListener Implements IEOSLogListener
	Method OnEOSLog(category:String, message:String, level:EEOSLogLevel)
		latestLog = category + ": " + message
		Log("EOS " + Int(level) + " " + latestLog)
	End Method
End Type

Type TLogin Extends TEOSSessionListener
	Field Manager:TEOSOnlineTest
	Field Number:Int
	Field Credential:String
	Field Session:TEOSSessionCoordinator
	Field ProductUserId:TEOSProductUserId
	Field CreateMissingProductUser:Int

	Method Start:Int(host:String)
		Local credentials:TEOSAuthCredentials = New TEOSAuthCredentials
		credentials.Type = EEOSLoginCredentialType.Developer
		credentials.Id = host
		credentials.Token = Credential
		Local options:TEOSAuthLoginOptions = New TEOSAuthLoginOptions
		options.Credentials = credentials
		options.ScopeFlags = EEOSAuthScopeFlags.BasicProfile | EEOSAuthScopeFlags.FriendsList | EEOSAuthScopeFlags.Presence

		Local sessionOptions:TEOSSessionOptions = New TEOSSessionOptions
		sessionOptions.LoginOptions = options
		Return Session.Start(sessionOptions)
	End Method

	Method OnEOSSessionStateChanged(state:EEOSSessionState) Override
		Log("Account " + Number + " session state=" + Int(state))
	End Method

	Method OnEOSSessionProductUserCreationRequired() Override
		If CreateMissingProductUser Then
			If Not Session.CreateProductUser() Then
				Manager.Fail( ..
					"Account " + Number + " Product User creation failed", ..
					"EOS rejected the request.")
			End If
		Else
			Manager.AskToCreateProductUser(Self)
		End If
	End Method

	Method OnEOSSessionReady(accountId:TEOSEpicAccountId, userId:TEOSProductUserId) Override
		ProductUserId = userId
		Manager.LoginReady(Self)
	End Method

	Method OnEOSSessionError(result:EEOSResult, recoverable:Int) Override
		If recoverable Then
			Log("Account " + Number + " recoverable session error: " + EOSResultString(result))
			Return
		End If
		Manager.Fail("Account " + Number + " login failed", EOSResultString(result))
	End Method
End Type

Type TEOSOnlineTest
	Field Platform:TEOSPlatform
	Field DevAuthHost:String
	Field Logins:TLogin[2]
	Field ReadyCount:Int
	Field PendingLogin:TLogin
	Field Host:TEOSOnlineService
	Field Client:TEOSOnlineService
	Field HostTransport:INetTransport
	Field ClientTransport:INetTransport
	Field ClientHostPeer:SNetPeer
	Field CreateRequest:UInt
	Field FindRequest:UInt
	Field SearchAttempts:Int
	Field NextSearchAt:Int
	Field SearchDeadline:Int
	Field JoinRequest:UInt
	Field HostStartRequest:UInt
	Field ClientStartRequest:UInt
	Field ClientJoined:Int
	Field MatchStarted:Int
	Field NextMatchTraceAt:Int
	Field PingSent:Int
	Field PingObserved:Int
	Field PongObserved:Int

	Method AddLogin:TLogin(number:Int, credential:String, createMissing:Int)
		Local login:TLogin = New TLogin
		login.Manager = Self
		login.Number = number
		login.Credential = credential
		login.CreateMissingProductUser = createMissing
		login.Session = TEOSSessionCoordinator.Create(Platform, login)
		If Not login.Session Then
			Return Null
		End If
		Logins[number - 1] = login
		Return login
	End Method

	Method LoginReady(login:TLogin)
		Log("Account " + login.Number + " Connect ready: " + login.ProductUserId.ToString())
		pendingProductUser = False
		PendingLogin = Null
		ReadyCount :+ 1
		statusTitle = "Account " + login.Number + " connected"
		statusDetail = "Product User: " + login.ProductUserId.ToString()
		If ReadyCount = 1 Then
			statusTitle = "Account 1 connected; signing in account 2..."
			If Not Logins[1].Start(DevAuthHost) Then
				Fail("Account 2 login did not start", "Check the second credential name.")
			End If
			Return
		End If
		If Logins[0].ProductUserId.ToString() = Logins[1].ProductUserId.ToString() Then
			Fail("Both credentials selected the same account", "Use two different Developer Auth credentials.")
			Return
		End If
		Host = TEOSOnlineService.Create(Logins[0].Session, "Account 1", TEST_BUCKET)
		Client = TEOSOnlineService.Create(Logins[1].Session, "Account 2", TEST_BUCKET)
		If Not Host Or Not Client Then
			Fail("Could not create GameNet EOS services", "Check the platform and Product User IDs.")
			Return
		End If
		If Not Host.Open() Or Not Client.Open() Then
			Fail("Could not open GameNet EOS services", "EOS Lobby notifications could not be registered.")
			Return
		End If
		Log("Both EOSOnline services opened")
		statusTitle = "Creating a GameNet lobby..."
		statusDetail = "Account 1 will host; account 2 will discover and join it."
		eventSummary = "GameNet.EOSOnline opened for both Product Users."
	End Method

	Method AskToCreateProductUser(login:TLogin)
		PendingLogin = login
		pendingProductUser = True
		statusKind = 1
		statusTitle = "Account " + login.Number + " needs a Product User"
		statusDetail = "Press C to create its EOS Product User and continue."
	End Method

	Method CreateProductUser()
		If Not PendingLogin Then
			Return
		End If
		pendingProductUser = False
		If Not PendingLogin.Session.CreateProductUser() Then
			Fail("Product User creation did not start", "EOS rejected the request.")
		End If
	End Method

	Method PollOnline(service:TEOSOnlineService, hostSide:Int)
		Local event:SOnlineEvent
		While service.Poll(event)
			Log(SideName(hostSide) + " online event kind=" + Int(event.Kind()) + " operation=" + Int(event.Operation()) + " request=" + event.RequestId() + " provider=" + event.ProviderCode() + " subject=" + event.SubjectId() + " detail=" + event.Detail())
			If event.Kind() = EOnlineEventKind.OperationFailed Then
				Fail("EOSOnline operation failed", event.Detail() + " (" + event.ProviderCode() + ")")
				Return
			End If
			If hostSide Then
				HandleHostEvent(event)
			Else
				HandleClientEvent(event)
			End If
		Wend
	End Method

	Method HandleHostEvent(event:SOnlineEvent)
		Select event.Kind()
			Case EOnlineEventKind.ServiceReady
				If Not CreateRequest Then
					Local options:TOnlineLobbyOptions = New TOnlineLobbyOptions
					options.name = "GameNet EOS Test"
					options.maxPlayers = 2
					options.visibility = EOnlineLobbyVisibility.Public
					options.properties.Set("test", "ping-pong")
					CreateRequest = Host.CreateLobby(options)
					If Not CreateRequest Then
						Fail("Lobby creation did not start", "Check the EOS client policy and lobby configuration.")
					End If
				End If
			Case EOnlineEventKind.LobbyCreated
				statusTitle = "Lobby created; searching from account 2..."
				SearchDeadline = MilliSecs() + 20000
				BeginSearch()
		End Select
	End Method

	Method BeginSearch()
		SearchAttempts :+ 1
		Log("Starting lobby search attempt " + SearchAttempts)
		NextSearchAt = 0
		Local query:TOnlineLobbyQuery = New TOnlineLobbyQuery
		query.maximumResults = 20
		query.properties.Set("test", "ping-pong")
		FindRequest = Client.FindLobbies(query)
		If Not FindRequest Then
			Fail("Lobby search did not start", "EOS rejected the search request.")
		End If
	End Method

	Method HandleClientEvent(event:SOnlineEvent)
		Select event.Kind()
			Case EOnlineEventKind.LobbySearchCompleted
				FindRequest = 0
				If Client.LobbyResultCount(event.RequestId()) < 1 Then
					If MilliSecs() < SearchDeadline Then
						NextSearchAt = MilliSecs() + 750
						statusTitle = "Waiting for the lobby search index..."
						statusDetail = "EOS returned no result yet; retry " + (SearchAttempts + 1) + " will run automatically."
						Return
					End If
					Fail("The new lobby was not found", "EOS returned no matching lobby after " + SearchAttempts + " searches.")
					Return
				End If
				Local lobby:IOnlineLobby = Client.LobbyResult(event.RequestId(), 0)
				JoinRequest = Client.JoinLobby(lobby.Id())
				If Not JoinRequest Then
					Fail("Lobby join did not start", "The search result could not be joined.")
				End If
			Case EOnlineEventKind.LobbyJoined
				ClientJoined = True
				statusTitle = "Both accounts joined; starting the match..."
				eventSummary = "Lobby discovery and membership succeeded."
		End Select
	End Method

	Method TryStartMatch()
		If MatchStarted Or Not ClientJoined Or Not Host.CurrentLobby() Or Host.CurrentLobby().MemberCount() <> 2 Then
			Return
		End If
		MatchStarted = True
		Log("Starting match; host members=" + Host.CurrentLobby().MemberCount() + " client members=" + Client.CurrentLobby().MemberCount())
		ClientStartRequest = Client.StartMatch()
		HostStartRequest = Host.StartMatch()
		If Not ClientStartRequest Or Not HostStartRequest Then
			Fail("Match start did not begin", "The lobby roster or owner state was incomplete.")
		End If
	End Method

	Method PollMatchReady(service:TEOSOnlineService, hostSide:Int)
		Local event:SOnlineEvent
		While service.Poll(event)
			Log(SideName(hostSide) + " match event kind=" + Int(event.Kind()) + " operation=" + Int(event.Operation()) + " request=" + event.RequestId() + " provider=" + event.ProviderCode() + " detail=" + event.Detail())
			If event.Kind() = EOnlineEventKind.OperationFailed Then
				Fail("Match transport failed", event.Detail())
				Return
			End If
			If event.Kind() = EOnlineEventKind.MatchReady Then
				Local info:SOnlineMatchInfo
				If Not service.MatchInfo(event.RequestId(), info) Then
					Fail("Match information was unavailable", "GameNet did not retain the ready match.")
					Return
				End If
				If hostSide Then
					HostTransport = service.TakeMatchTransport(event.RequestId())
				Else
					ClientHostPeer = info.SessionHostPeer()
					ClientTransport = service.TakeMatchTransport(event.RequestId())
				End If
				statusTitle = "Lobby became an EOS P2P match..."
				eventSummary = "Waiting for both GameNet transport connections."
			End If
		Wend
	End Method

	Method TraceMatchState()
		If MilliSecs() < NextMatchTraceAt Then
			Return
		End If
		NextMatchTraceAt = MilliSecs() + 1000
		For Local side:Int = 0 To 1
			Local service:TEOSOnlineService = Client
			If side Then
				service = Host
			End If
			Local lobby:IOnlineLobby = service.CurrentLobby()
			If Not lobby Then
				Log(SideName(side) + " match state: no lobby")
				Continue
			End If
			Local startFound:Int, joinableFound:Int
			Local startValue:String = lobby.Properties().Value(EOS_ONLINE_START_KEY, startFound)
			Local joinableValue:String = lobby.Properties().Value(EOS_ONLINE_JOINABLE_KEY, joinableFound)
			Log(SideName(side) + " match state: members=" + lobby.MemberCount() + " joinable=" + lobby.IsJoinable() + " start=" + startValue + " startFound=" + startFound + " marker=" + joinableValue + " markerFound=" + joinableFound)
		Next
	End Method

	Method PollTransport(transport:INetTransport, hostSide:Int)
		If Not transport Then
			Return
		End If
		Local event:SNetEvent
		While transport.Poll(event)
			Log(SideName(hostSide) + " transport event kind=" + Int(event.Kind()) + " peer=" + event.Peer().Id() + " code=" + event.Code())
			Select event.Kind()
				Case ENetEventKind.Connected
					If Not hostSide And Not PingSent Then
						Local ping:Byte[] = PacketData("PING")
						If transport.Send(ClientHostPeer, 0, EDeliveryMode.ReliableOrdered, Byte Ptr(ping), Size_T(ping.Length)) <> ETransportResult.Ok Then
							Fail("Could not send PING", "EOS P2P rejected the GameNet packet.")
							Return
						End If
						PingSent = True
						eventSummary = "Client connected and sent reliable PING."
					End If
				Case ENetEventKind.Data
					Local text:String = PacketText(event.Packet())
					If hostSide And text = "PING" Then
						PingObserved = True
						Local pong:Byte[] = PacketData("PONG")
						If transport.Send(event.Peer(), 0, EDeliveryMode.ReliableOrdered, Byte Ptr(pong), Size_T(pong.Length)) <> ETransportResult.Ok Then
							Fail("Could not send PONG", "EOS P2P rejected the reply.")
							Return
						End If
						eventSummary = "Host received PING and sent PONG."
					Else If Not hostSide And text = "PONG" Then
						PongObserved = True
						Log("SUCCEEDED: lobby discovery, join, match start, and EOS P2P PING/PONG completed")
						statusKind = 2
						statusTitle = "GameNet EOSOnline test succeeded"
						statusDetail = "Lobby discovery, join, match start, and P2P PING/PONG all worked."
						eventSummary = "EOS lobby membership was converted into a working GameNet transport."
						succeeded = True
						done = True
					End If
				Case ENetEventKind.Error
					Fail("GameNet transport reported an error", "Transport code " + event.Code())
			End Select
		Wend
	End Method

	Method Update()
		If done Then
			Return
		End If
		If ReadyCount < 2 Or Not Host Or Not Client Then
			For Local login:TLogin = EachIn Logins
				If login And login.Session And login.Session.State() <> EEOSSessionState.Stopped Then
					login.Session.Tick()
				End If
			Next
			Return
		End If
		Host.Pump()
		Client.Pump()
		If Not MatchStarted Then
			PollOnline(Host, True)
			PollOnline(Client, False)
			If NextSearchAt And MilliSecs() >= NextSearchAt Then
				BeginSearch()
			End If
			TryStartMatch()
			If ClientJoined And Not MatchStarted And Host.CurrentLobby() And Client.CurrentLobby() Then
				statusDetail = "Roster refresh: host sees " + Host.CurrentLobby().MemberCount() + " member(s); client sees " + Client.CurrentLobby().MemberCount() + "."
			End If
		Else
			TraceMatchState()
			PollMatchReady(Host, True)
			PollMatchReady(Client, False)
			PollTransport(HostTransport, True)
			PollTransport(ClientTransport, False)
		End If
	End Method

	Method Fail(title:String, detail:String)
		If done Then
			Return
		End If
		Log("FAILED: " + title + " -- " + detail)
		statusKind = 3
		statusTitle = title
		statusDetail = detail
		done = True
	End Method

	Method Shutdown()
		If ClientTransport Then
			ClientTransport.Close()
		End If
		If HostTransport Then
			HostTransport.Close()
		End If
		If Client Then
			Client.Close()
		End If
		If Host Then
			Host.Close()
		End If
		Local finish:Int = MilliSecs() + 2000
		While MilliSecs() < finish And ((Client And Client.State() <> EOnlineServiceState.Closed) Or (Host And Host.State() <> EOnlineServiceState.Closed))
			If Client Then
				Client.Pump()
			End If
			If Host Then
				Host.Pump()
			End If
			Delay 10
		Wend

		For Local login:TLogin = EachIn Logins
			If login And login.Session And login.Session.State() <> EEOSSessionState.Stopped Then
				login.Session.Logout()
			End If
		Next
		finish = MilliSecs() + 5000
		Local waiting:Int = True
		While waiting And MilliSecs() < finish
			waiting = False
			For Local login:TLogin = EachIn Logins
				If login And login.Session Then
					If login.Session.State() <> EEOSSessionState.Stopped And login.Session.State() <> EEOSSessionState.Failed Then
						waiting = True
						login.Session.Tick()
					End If
				End If
			Next
			If waiting Then
				Delay 10
			End If
		Wend
		For Local login:TLogin = EachIn Logins
			If login And login.Session Then
				login.Session.Release()
			End If
		Next
	End Method
End Type

Function PacketData:Byte[](text:String)
	Local data:Byte[] = New Byte[text.Length]
	For Local index:Int = 0 Until text.Length
		data[index] = text[index]
	Next
	Return data
End Function

Function PacketText:String(packet:SPacketView)
	Local result:String
	For Local index:Size_T = 0 Until packet.Length()
		result :+ Chr(packet.Data()[index])
	Next
	Return result
End Function

Function ConfigValue:String(config:String, name:String)
	For Local line:String = EachIn config.Replace(Chr(13), "").Split("~n")
		line = line.Trim()
		If Not line Or line.StartsWith("#") Then
			Continue
		End If
		Local separator:Int = line.Find("=")
		If separator >= 0 And line[..separator].Trim() = name Then
			Return line[separator + 1..].Trim()
		End If
	Next
	Return ""
End Function

Function FindConfig:String()
	If AppArgs.Length > 1 And FileType(AppArgs[1]) = FILETYPE_FILE Then
		Return RealPath(AppArgs[1])
	End If
	Local candidate:String = RealPath(AppDir)
	For Local level:Int = 0 Until 9
		Local path:String = candidate + "/eos.mod/sdk.mod/examples/eos.local.conf"
		If FileType(path) = FILETYPE_FILE Then
			Return path
		End If
		path = candidate + "/../eos.mod/sdk.mod/examples/eos.local.conf"
		If FileType(path) = FILETYPE_FILE Then
			Return RealPath(path)
		End If
		Local parent:String = ExtractDir(candidate)
		If parent = candidate Then
			Exit
		End If
		candidate = parent
	Next
	Return ""
End Function

Function DrawScreen()
	Cls
	SetColor 22, 27, 38
	DrawRect 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT
	Select statusKind
		Case 2
			SetColor 75, 201, 126
		Case 3
			SetColor 235, 91, 91
		Default
			SetColor 75, 155, 235
	End Select
	DrawRect 0, 0, WINDOW_WIDTH, 9
	SetColor 245, 247, 250
	SetScale 1.4, 1.4
	DrawText statusTitle, 44, 65
	SetScale 1.0, 1.0
	SetColor 178, 187, 205
	DrawText statusDetail, 46, 120
	SetColor 49, 58, 76
	DrawRect 46, 168, WINDOW_WIDTH - 92, 150
	SetColor 212, 220, 234
	DrawText eventSummary, 70, 205
	If succeeded Then
		DrawText "EOS Lobby -> GameNet.EOSOnline -> GameNet.EOSP2P", 70, 245
		DrawText "Reliable ordered PING -> PONG: verified", 70, 282
	Else If Not done Then
		DrawText "The two accounts run inside this one test application.", 70, 245
	End If
	SetColor 130, 141, 160
	If latestLog Then
		DrawText latestLog[..Min(latestLog.Length, 110)], 46, 370
	End If
	If pendingProductUser Then
		DrawText "Press C to create the Product User, or Escape to cancel.", 46, 425
	Else
		DrawText "Press Escape to close.", 46, 425
	End If
	Flip
End Function

AppTitle = "GameNet EOSOnline Test"
Graphics WINDOW_WIDTH, WINDOW_HEIGHT, 0, 60, GRAPHICS_BACKBUFFER
SetClsColor 22, 27, 38
logOutput = WriteFile(LOG_PATH)
Log("GameNet EOSOnline live test started")

Local initialized:Int
Local platform:TEOSPlatform
Local test:TEOSOnlineTest
Local configPath:String = FindConfig()
If Not configPath Then
	statusKind = 3
	statusTitle = "eos.local.conf was not found"
	statusDetail = "Pass its full path as the first application argument."
	done = True
Else
	Local config:String = LoadText(configPath)
	Local firstCredential:String = ConfigValue(config, "DEV_AUTH_CREDENTIAL")
	Local secondCredential:String = ConfigValue(config, "DEV_AUTH_CREDENTIAL_2")
	If AppArgs.Length > 2 Then
		secondCredential = AppArgs[2]
	End If
	If Not firstCredential Or Not secondCredential Then
		statusKind = 3
		statusTitle = "Two Developer Auth credentials are required"
		statusDetail = "Add DEV_AUTH_CREDENTIAL_2 or pass the second name as argument 2."
		done = True
	Else
		Local initializeOptions:TEOSInitializeOptions = New TEOSInitializeOptions
		initializeOptions.ProductName = "GameNet EOSOnline Test"
		initializeOptions.ProductVersion = "0.1.0"
		Local result:EEOSResult = EOSInitialize(initializeOptions)
		If result <> EEOSResult.Success Then
			statusKind = 3
			statusTitle = "EOS initialization failed"
			statusDetail = EOSResultString(result)
			done = True
		Else
			initialized = True
			TEOSLogging.SetListener(New TConsoleLogListener)
			TEOSLogging.SetLevel(EEOSLogCategory.AllCategories, EEOSLogLevel.Info)
			Local options:TEOSPlatformOptions = New TEOSPlatformOptions
			options.ProductId = ConfigValue(config, "PRODUCT_ID")
			options.SandboxId = ConfigValue(config, "SANDBOX_ID")
			options.DeploymentId = ConfigValue(config, "DEPLOYMENT_ID")
			options.ClientId = ConfigValue(config, "CLIENT_ID")
			options.ClientSecret = ConfigValue(config, "CLIENT_SECRET")
			options.EncryptionKey = ConfigValue(config, "ENCRYPTION_KEY")
			platform = TEOSPlatform.Create(options)
			If Not platform Then
				statusKind = 3
				statusTitle = "EOS platform creation failed"
				statusDetail = "Check the local product configuration."
				done = True
			Else
				test = New TEOSOnlineTest
				test.Platform = platform
				test.DevAuthHost = ConfigValue(config, "DEV_AUTH_HOST")
				Local createMissing:Int = Int(ConfigValue(config, "CREATE_MISSING_PRODUCT_USER"))
				Local first:TLogin = test.AddLogin(1, firstCredential, createMissing)
				Local second:TLogin = test.AddLogin(2, secondCredential, createMissing)
				If Not first Or Not second Then
					test.Fail("Could not create managed EOS sessions", "Auth and Connect are required.")
				Else
					statusTitle = "Signing in both test accounts..."
					If Not first.Start(test.DevAuthHost) Then
						test.Fail("Account 1 login did not start", "Check the first credential name.")
					End If
				End If
			End If
		End If
	End If
End If

Local startedAt:Int = MilliSecs()
While Not KeyHit(KEY_ESCAPE) And Not AppTerminate()
	If test Then
		test.Update()
	End If
	If pendingProductUser And KeyHit(KEY_C) Then
		test.CreateProductUser()
	End If
	If Not done And MilliSecs() - startedAt > 120000 Then
		test.Fail("The EOSOnline test timed out", "Check the Developer Authentication Tool and EOS logs.")
	End If
	DrawScreen()
Wend

If test Then
	test.Shutdown()
End If
If platform Then
	platform.Release()
End If
If initialized Then
	EOSShutdown()
End If
Log("GameNet EOSOnline live test stopped")
If logOutput Then
	CloseStream logOutput
End If
EndGraphics
