SuperStrict

Framework BRL.StandardIO
Import GameNet.Nakama
Import GameNet.Session

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Function DrainReady:Int(service:TNakamaOnlineService, requestId:UInt)
	Local event:SOnlineEvent
	While service.Poll(event)
		If event.Kind() = EOnlineEventKind.OperationFailed Then Throw "Nakama operation failed: " + event.Detail() + " (" + event.ProviderCode() + ")"
		If event.Kind() = EOnlineEventKind.MatchReady And event.RequestId() = requestId Then Return True
	Wend
	Return False
End Function

Local first:TNakamaOnlineService = TNakamaOnlineService.Create("127.0.0.1", 7350, "defaultkey", "blitzmax-gamenet-nakama-a", "gamenet_a")
Local second:TNakamaOnlineService = TNakamaOnlineService.Create("127.0.0.1", 7350, "defaultkey", "blitzmax-gamenet-nakama-b", "gamenet_b")
Check(first And second, "create Nakama online services")
Check(first.Capabilities() = (EOnlineCapability.Matchmaking | EOnlineCapability.MatchTransport), "Nakama capabilities")
Check(first.Open() And second.Open(), "start Nakama services")

Local deadline:Int = MilliSecs() + 10000
While (first.State() = EOnlineServiceState.Opening Or second.State() = EOnlineServiceState.Opening) And MilliSecs() < deadline
	first.Pump(); second.Pump(); Delay 1
Wend
Check(first.State() = EOnlineServiceState.Ready, "first Nakama service ready")
Check(second.State() = EOnlineServiceState.Ready, "second Nakama service ready")
Check(first.LocalPlayer().IsValid() And second.LocalPlayer().IsValid(), "authenticated local players")

Local request:TOnlineMatchmakingRequest = New TOnlineMatchmakingRequest
request.minPlayers = 2; request.maxPlayers = 2

' Exercise cancellation before a ticket has necessarily arrived.
Local cancelledRequest:UInt = first.StartMatchmaking(request)
Check(cancelledRequest And first.CancelOperation(cancelledRequest), "cancel pending Nakama matchmaking")
Local cancelled:Int
deadline = MilliSecs() + 5000
While Not cancelled And MilliSecs() < deadline
	first.Pump()
	Local cancelEvent:SOnlineEvent
	While first.Poll(cancelEvent)
		If cancelEvent.Kind() = EOnlineEventKind.OperationFailed Then Throw "Nakama cancellation failed: " + cancelEvent.Detail()
		If cancelEvent.Kind() = EOnlineEventKind.MatchmakingCancelled And cancelEvent.RequestId() = cancelledRequest Then cancelled = True
	Wend
	Delay 1
Wend
Check(cancelled, "Nakama matchmaking cancellation event")

Local firstRequest:UInt = first.StartMatchmaking(request)
Local secondRequest:UInt = second.StartMatchmaking(request)
Check(firstRequest And secondRequest, "start GameNet matchmaking")

Local firstReady:Int, secondReady:Int
deadline = MilliSecs() + 15000
While (Not firstReady Or Not secondReady) And MilliSecs() < deadline
	first.Pump(); second.Pump()
	If Not firstReady Then firstReady = DrainReady(first, firstRequest)
	If Not secondReady Then secondReady = DrainReady(second, secondRequest)
	Delay 1
Wend
Check(firstReady And secondReady, "both GameNet services received MatchReady")

Local firstInfo:SOnlineMatchInfo, secondInfo:SOnlineMatchInfo
Check(first.MatchInfo(firstRequest, firstInfo), "first match information")
Check(second.MatchInfo(secondRequest, secondInfo), "second match information")
Check(firstInfo.PlayerCount() = 2 And secondInfo.PlayerCount() = 2, "two-player match roster")
Check(firstInfo.IsSessionHost() <> secondInfo.IsSessionHost(), "one deterministic session host")

Local firstTransport:INetTransport = first.TakeMatchTransport(firstRequest)
Local secondTransport:INetTransport = second.TakeMatchTransport(secondRequest)
Check(firstTransport And secondTransport, "take Nakama match transports")

' Closing each service must leave its handed-off transport usable.
Check(first.Close() And second.Close(), "close online services after transport handoff")

Local host:TNetSession
Local client:TNetSession
If firstInfo.IsSessionHost() Then
	host = TNetSession.CreateHost(firstTransport, $4E414B41, 1, 1, 900)
	client = TNetSession.CreateClient(secondTransport, $4E414B41, 1, Null, 0, 1, 900)
Else
	host = TNetSession.CreateHost(secondTransport, $4E414B41, 1, 1, 900)
	client = TNetSession.CreateClient(firstTransport, $4E414B41, 1, Null, 0, 1, 900)
End If
Check(host And client, "create GameNet sessions over Nakama")

Local hostJoined:Int, clientJoined:Int
Local clientPeer:SNetPeer
Local sessionEvent:SSessionEvent
deadline = MilliSecs() + 10000
While (Not hostJoined Or Not clientJoined) And MilliSecs() < deadline
	If host.Poll(sessionEvent) Then
		Select sessionEvent.Kind()
			Case ESessionEventKind.JoinRequested
				Check(host.Accept(sessionEvent.Peer()) = ETransportResult.Ok, "host accepts Nakama peer")
			Case ESessionEventKind.Joined
				hostJoined = True
			Case ESessionEventKind.Error
				Throw "host session error " + sessionEvent.Code()
		End Select
	End If
	If client.Poll(sessionEvent) Then
		Select sessionEvent.Kind()
			Case ESessionEventKind.Joined
				clientJoined = True; clientPeer = sessionEvent.Peer()
			Case ESessionEventKind.Error
				Throw "client session error " + sessionEvent.Code()
		End Select
	End If
	Delay 1
Wend
Check(hostJoined And clientJoined And clientPeer.IsValid(), "GameNet session handshake over Nakama")

Local payload:Byte[4]
payload[0] = 10; payload[1] = 20; payload[2] = 30; payload[3] = 40
Check(client.Send(clientPeer, 77, 2, EDeliveryMode.UnreliableSequenced, Byte Ptr(payload), Size_T(payload.Length)) = ETransportResult.Ok, "send GameNet message over Nakama")

Local received:Int
deadline = MilliSecs() + 5000
While Not received And MilliSecs() < deadline
	If host.Poll(sessionEvent) Then
		If sessionEvent.Kind() = ESessionEventKind.Error Then Throw "host receive error " + sessionEvent.Code()
		If sessionEvent.Kind() = ESessionEventKind.Message Then
			Check(sessionEvent.MessageType() = 77, "GameNet message type")
			Check(sessionEvent.Channel() = 2, "GameNet logical channel")
			Check(sessionEvent.Delivery() = EDeliveryMode.UnreliableSequenced, "GameNet delivery metadata")
			Check(sessionEvent.Payload().Length() = 4 And sessionEvent.Payload().Data()[3] = 40, "GameNet message payload")
			received = True
		End If
	End If
	client.Poll(sessionEvent)
	Delay 1
Wend
Check(received, "host received GameNet message over Nakama")

host.Close(); client.Close()
Print "GameNet.Nakama matchmaking, handoff, session handshake, and message exchange passed"
