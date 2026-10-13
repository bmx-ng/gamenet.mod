SuperStrict

Framework GameNet.SteamSockets
Import BRL.StandardIO

Const GAME_PORT:Int = 27015
Const QUERY_PORT:Int = 27016

Local runMilliseconds:Int = 30000
If AppArgs.Length > 1 Then runMilliseconds = Max(1, Int(AppArgs[1])) * 1000

Local errorMessage:String
Local initResult:ESteamAPIInitResult = SteamGameServerInit(0, GAME_PORT, QUERY_PORT, EServerMode.eServerModeNoAuthentication, "1.0.0.0", errorMessage)
If initResult <> ESteamAPIInitResult.k_ESteamAPIInitResult_OK Then
	Throw "Steam game-server initialization failed: " + errorMessage
End If

Local gameServer:TSteamGameServer = TSteamGameServer.Create()
If Not gameServer Then
	SteamGameServerShutdown()
	Throw "Could not acquire the Steam game-server interface"
End If

gameServer.SetProduct("gamenet_example")
gameServer.SetGameDescription("GameNet dedicated-server example")
gameServer.SetModDir("gamenet_example")
gameServer.SetDedicatedServer(True)
gameServer.SetMaxPlayerCount(32)
gameServer.SetServerName("GameNet echo server")
gameServer.SetMapName("echo")
gameServer.SetPasswordProtected(False)
gameServer.LogOnAnonymous()
gameServer.SetAdvertiseServerActive(True)

Local sockets:TSteamNetworkingSockets = TSteamNetworkingSockets.Create(True)
If Not sockets Then
	gameServer.LogOff()
	SteamGameServerShutdown()
	Throw "Could not acquire the game-server networking interface"
End If

Local transport:TSteamSocketsTransport = TSteamSocketsTransport.ListenIP(GAME_PORT, 32, 8, "", STEAM_SOCKETS_DEFAULT_MAX_PACKET_SIZE, sockets)
If Not transport Then
	gameServer.LogOff()
	SteamGameServerShutdown()
	Throw "Could not listen on the game port"
End If

Print "Listening on UDP port " + GAME_PORT + " for " + (runMilliseconds / 1000) + " seconds"
Local deadline:Int = MilliSecs() + runMilliseconds
While MilliSecs() < deadline
	Local event:SNetEvent
	While transport.Poll(event)
		Select event.Kind()
			Case ENetEventKind.Connected
				Print "Peer connected: " + event.Peer().Id()
			Case ENetEventKind.Data
				Local packet:SPacketView = event.Packet()
				transport.Send(event.Peer(), event.Channel(), event.Delivery(), packet.Data(), packet.Length())
			Case ENetEventKind.Disconnected
				Print "Peer disconnected: " + event.Peer().Id()
			Case ENetEventKind.Error
				Print "Transport error: " + event.Code()
		End Select
	Wend
	Delay 1
Wend

transport.Close()
gameServer.SetAdvertiseServerActive(False)
gameServer.LogOff()
SteamGameServerShutdown()
Print "Server stopped"
