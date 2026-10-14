SuperStrict

Framework GameNet.MatchRoom
Import GameNet.Loopback
Import BRL.StandardIO

Function CheckRoom(condition:Int, message:String)
	If Not condition Then RuntimeError "Match room test failed: " + message
End Function

Function PumpRooms(hostSession:TNetSession, clientSession:TNetSession, hostRoom:TMatchRoom, clientRoom:TMatchRoom, nowMillis:UInt)
	For Local pass:Int = 0 Until 16
		Local handled:Int
		Local event:SSessionEvent
		While hostSession.PollAt(event, nowMillis)
			handled = True
			If event.Kind() = ESessionEventKind.Message Then CheckRoom(hostRoom.Receive(event.Peer(), event.MessageType(), event.Payload()), "host accepts room message")
		Wend
		While clientSession.PollAt(event, nowMillis)
			handled = True
			If event.Kind() = ESessionEventKind.Message Then CheckRoom(clientRoom.Receive(event.Peer(), event.MessageType(), event.Payload()), "client accepts room message")
		Wend
		If Not handled Then Exit
	Next
End Function

Local pair:TLoopbackPair = TLoopbackPair.Create(64, 900)
Local hostSession:TNetSession = TNetSession.CreateHost(pair.First(), $524f4f4d, 1, 1, 900)
Local clientSession:TNetSession = TNetSession.CreateClient(pair.Second(), $524f4f4d, 1, Null, 0, 1, 900)
Local sessionEvent:SSessionEvent
clientSession.PollAt(sessionEvent, 0)
CheckRoom(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.JoinRequested, "host receives join request")
Local hostPeer:SNetPeer = sessionEvent.Peer()
CheckRoom(hostSession.Accept(hostPeer) = ETransportResult.Ok, "host accepts peer")
CheckRoom(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "host session joined")
CheckRoom(clientSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "client session joined")
Local clientPeer:SNetPeer = sessionEvent.Peer()

Local roomConfig:SMatchRoomConfig = New SMatchRoomConfig(2, 65000, 65001, 0, 32, 32)
Local hostRoom:TMatchRoom = TMatchRoom.CreateHost(hostSession, roomConfig)
Local clientRoom:TMatchRoom = TMatchRoom.CreateClient(clientSession, clientPeer, roomConfig)
CheckRoom(hostRoom <> Null And clientRoom <> Null, "create rooms")
CheckRoom(hostRoom.PlayerJoined(hostPeer) = ETransportResult.Ok, "host adds client")
CheckRoom(clientRoom.PlayerJoined(clientPeer) = ETransportResult.Ok, "client binds host")
PumpRooms(hostSession, clientSession, hostRoom, clientRoom, 1)
CheckRoom(hostRoom.LocalPlayer() = 0 And clientRoom.LocalPlayer() = 1, "stable player slots")
CheckRoom(hostRoom.MemberCount() = 2 And clientRoom.MemberCount() = 2, "synchronized roster")
CheckRoom(hostRoom.IsInRoom(0) And hostRoom.IsInRoom(1), "players begin in staging")

Local gameConfiguration:Byte[4]
gameConfiguration[0] = 2
gameConfiguration[1] = 5
gameConfiguration[2] = 0
gameConfiguration[3] = 1
CheckRoom(hostRoom.SetConfiguration(New SPacketView(Byte Ptr(gameConfiguration), Size_T(gameConfiguration.Length))) = ETransportResult.Ok, "host sets configuration")
PumpRooms(hostSession, clientSession, hostRoom, clientRoom, 2)
CheckRoom(clientRoom.Configuration().Length() = Size_T(gameConfiguration.Length), "client receives configuration")
CheckRoom(clientRoom.Configuration().Data()[1] = 5, "configuration contents")

CheckRoom(hostRoom.SetLocalReady(True) = ETransportResult.Ok, "host ready")
CheckRoom(clientRoom.SetLocalReady(True) = ETransportResult.Ok, "client sends ready")
PumpRooms(hostSession, clientSession, hostRoom, clientRoom, 3)
CheckRoom(hostRoom.AllPresentReady() And clientRoom.AllPresentReady(), "all ready")
CheckRoom(hostRoom.BeginMatch($123456789abcdef0:ULong) = ETransportResult.Ok, "host begins match")
PumpRooms(hostSession, clientSession, hostRoom, clientRoom, 4)
CheckRoom(hostRoom.Phase() = EMatchRoomPhase.Playing And clientRoom.Phase() = EMatchRoomPhase.Playing, "coordinated match start")
CheckRoom(clientRoom.Round() = 1 And clientRoom.Seed() = $123456789abcdef0:ULong, "shared round and seed")

CheckRoom(hostRoom.FinishMatch() = ETransportResult.Ok, "host finishes match")
PumpRooms(hostSession, clientSession, hostRoom, clientRoom, 5)
CheckRoom(clientRoom.Phase() = EMatchRoomPhase.Results, "results synchronized")
CheckRoom(clientRoom.ReturnToRoom() = ETransportResult.Ok, "client returns independently")
PumpRooms(hostSession, clientSession, hostRoom, clientRoom, 6)
CheckRoom(hostRoom.Phase() = EMatchRoomPhase.Results And hostRoom.IsInRoom(1) And Not hostRoom.IsInRoom(0), "host may remain on results")
CheckRoom(hostRoom.ReturnToRoom() = ETransportResult.Ok, "host returns")
PumpRooms(hostSession, clientSession, hostRoom, clientRoom, 7)
CheckRoom(hostRoom.Phase() = EMatchRoomPhase.Staging And clientRoom.Phase() = EMatchRoomPhase.Staging, "room reopens when all return")

CheckRoom(hostRoom.SetLocalReady(True) = ETransportResult.Ok, "host ready for second round")
CheckRoom(clientRoom.SetLocalReady(True) = ETransportResult.Ok, "client ready for second round")
PumpRooms(hostSession, clientSession, hostRoom, clientRoom, 8)
CheckRoom(hostRoom.BeginMatch(99) = ETransportResult.Ok, "second match starts")
CheckRoom(hostRoom.PlayerLeft(hostPeer, 77) = ETransportResult.Ok, "host handles participant loss")
CheckRoom(hostRoom.Phase() = EMatchRoomPhase.Staging And hostRoom.MemberCount() = 1, "participant loss safely reopens staging")
CheckRoom(clientRoom.PlayerLeft(clientPeer, 77) = ETransportResult.Ok And clientRoom.Phase() = EMatchRoomPhase.Closed, "client handles authority loss")

hostSession.Close()
clientSession.Close()

Print "Match room tests passed"
