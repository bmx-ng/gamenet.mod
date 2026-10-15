SuperStrict

Framework Max2D.TileMap
Import GameNet.Loopback
Import GameNet.Session
Import BRL.StandardIO

Include "rules.bmx"
Include "maps.bmx"
Include "protocol.bmx"

Function CheckProtocol(condition:Int, message:String)
	If Not condition Then RuntimeError "Counter Cascade protocol test failed: " + message
End Function

Local packet:Byte[64]
Local config:SCascadeMatchConfig = New SCascadeMatchConfig(ECascadeBoardLayout.Square, 5, 2, 1)
config.SetPlayerColour(0, 4)
config.SetPlayerColour(1, 5)
CheckProtocol(config.IsValid(), "valid square configuration")
CheckProtocol(EncodeCascadeConfig(Byte Ptr(packet), Size_T(packet.Length), config) = CASCADE_CONFIG_PACKET_SIZE, "encode configuration")
Local decodedConfig:SCascadeMatchConfig
CheckProtocol(DecodeCascadeConfig(New SPacketView(Byte Ptr(packet), CASCADE_CONFIG_PACKET_SIZE), decodedConfig), "decode configuration")
CheckProtocol(decodedConfig.layout = config.layout And decodedConfig.size = config.size And decodedConfig.playerCount = config.playerCount And decodedConfig.startingPlayer = config.startingPlayer, "configuration values")
CheckProtocol(decodedConfig.PlayerColour(0) = 4 And decodedConfig.PlayerColour(1) = 5, "configuration colours")
CheckProtocol(decodedConfig.CreateBoard() <> Null, "configuration creates board")

Local invalidConfig:SCascadeMatchConfig = New SCascadeMatchConfig(ECascadeBoardLayout.Hexagon, 3, 4)
CheckProtocol(Not invalidConfig.IsValid(), "reject invalid regular hex roster")
CheckProtocol(EncodeCascadeConfig(Byte Ptr(packet), Size_T(packet.Length), invalidConfig) = 0, "do not encode invalid configuration")
Local invalidStarter:SCascadeMatchConfig = New SCascadeMatchConfig(ECascadeBoardLayout.Square, 5, 2, 2)
CheckProtocol(Not invalidStarter.IsValid(), "reject invalid starting player")
Local duplicateColours:SCascadeMatchConfig = New SCascadeMatchConfig(ECascadeBoardLayout.Square, 5, 2)
duplicateColours.SetPlayerColour(1, duplicateColours.PlayerColour(0))
CheckProtocol(Not duplicateColours.IsValid(), "reject duplicate player colours")
packet[0] = 99
CheckProtocol(Not DecodeCascadeConfig(New SPacketView(Byte Ptr(packet), CASCADE_CONFIG_PACKET_SIZE), decodedConfig), "reject configuration version")

CheckProtocol(EncodeCascadeColourRequest(Byte Ptr(packet), Size_T(packet.Length)) = CASCADE_COLOUR_REQUEST_PACKET_SIZE, "encode colour request")
CheckProtocol(DecodeCascadeColourRequest(New SPacketView(Byte Ptr(packet), CASCADE_COLOUR_REQUEST_PACKET_SIZE)), "decode colour request")
CheckProtocol(Not DecodeCascadeColourRequest(New SPacketView(Byte Ptr(packet), 0)), "reject truncated colour request")

Local request:SCascadeMoveRequest = New SCascadeMoveRequest(42, 17)
CheckProtocol(EncodeCascadeMoveRequest(Byte Ptr(packet), Size_T(packet.Length), request) = CASCADE_MOVE_REQUEST_PACKET_SIZE, "encode move request")
Local decodedRequest:SCascadeMoveRequest
CheckProtocol(DecodeCascadeMoveRequest(New SPacketView(Byte Ptr(packet), CASCADE_MOVE_REQUEST_PACKET_SIZE), decodedRequest), "decode move request")
CheckProtocol(decodedRequest.turn = request.turn And decodedRequest.cell = request.cell, "move request values")
CheckProtocol(Not DecodeCascadeMoveRequest(New SPacketView(Byte Ptr(packet), CASCADE_MOVE_REQUEST_PACKET_SIZE - 1), decodedRequest), "reject truncated move request")

Local host:TCascadeGame = TCascadeGame.Create(config.CreateBoard())
Local client:TCascadeGame = TCascadeGame.Create(config.CreateBoard())
host.Reset(config.startingPlayer)
client.Reset(config.startingPlayer)
Local cells:Int[4]
cells[0] = host.board.starts[1]
cells[1] = host.board.starts[0]
cells[2] = host.board.starts[1]
cells[3] = host.board.starts[0]

For Local index:Int = 0 Until cells.Length
	Local turn:UInt = host.turn
	Local player:Int = host.currentPlayer
	Local result:ECascadeMoveResult = host.ApplyMove(player, cells[index])
	CheckProtocol(result = ECascadeMoveResult.Accepted, "host accepts deterministic move")
	Local applied:SCascadeAppliedMove = New SCascadeAppliedMove(turn, player, cells[index], result, host.StateHash())
	CheckProtocol(EncodeCascadeAppliedMove(Byte Ptr(packet), Size_T(packet.Length), applied) = CASCADE_MOVE_APPLIED_PACKET_SIZE, "encode applied move")
	Local decodedMove:SCascadeAppliedMove
	CheckProtocol(DecodeCascadeAppliedMove(New SPacketView(Byte Ptr(packet), CASCADE_MOVE_APPLIED_PACKET_SIZE), decodedMove), "decode applied move")
	CheckProtocol(decodedMove.turn = client.turn And decodedMove.player = client.currentPlayer, "applied move ordering")
	CheckProtocol(client.ApplyMove(decodedMove.player, decodedMove.cell) = decodedMove.result, "client applies canonical move")
	CheckProtocol(client.StateHash() = decodedMove.stateHash, "post-move state hash")
Next

packet[CASCADE_MOVE_APPLIED_PACKET_SIZE] = 1
Local trailing:SCascadeAppliedMove
CheckProtocol(Not DecodeCascadeAppliedMove(New SPacketView(Byte Ptr(packet), CASCADE_MOVE_APPLIED_PACKET_SIZE + 1), trailing), "reject trailing applied-move data")

Local rejectedMove:SCascadeAppliedMove = New SCascadeAppliedMove(7, 1, 3, ECascadeMoveResult.Invalid, $1234:ULong)
CheckProtocol(EncodeCascadeAppliedMove(Byte Ptr(packet), Size_T(packet.Length), rejectedMove) = CASCADE_MOVE_APPLIED_PACKET_SIZE, "encode rejected move response")
CheckProtocol(DecodeCascadeAppliedMove(New SPacketView(Byte Ptr(packet), CASCADE_MOVE_APPLIED_PACKET_SIZE), rejectedMove) And rejectedMove.result = ECascadeMoveResult.Invalid, "decode rejected move response")

Local statePacket:Byte[1024]
Local stateLength:Size_T = EncodeCascadeState(Byte Ptr(statePacket), Size_T(statePacket.Length), host)
CheckProtocol(stateLength = CascadeStatePacketSize(host.board.CellCount()), "encode full match state")
Local recoveryGame:TCascadeGame = TCascadeGame.Create(config.CreateBoard())
Local recoveryHash:ULong = recoveryGame.StateHash()
CheckProtocol(Not DecodeCascadeState(New SPacketView(Byte Ptr(statePacket), stateLength - 1), recoveryGame), "reject truncated full state")
CheckProtocol(recoveryGame.StateHash() = recoveryHash, "truncated state does not mutate game")
statePacket[CASCADE_STATE_HEADER_SIZE] = 99
CheckProtocol(Not DecodeCascadeState(New SPacketView(Byte Ptr(statePacket), stateLength), recoveryGame), "reject invalid full-state owner")
CheckProtocol(recoveryGame.StateHash() = recoveryHash, "invalid state does not mutate game")
stateLength = EncodeCascadeState(Byte Ptr(statePacket), Size_T(statePacket.Length), host)
CheckProtocol(DecodeCascadeState(New SPacketView(Byte Ptr(statePacket), stateLength), recoveryGame), "decode full match state")
CheckProtocol(recoveryGame.StateHash() = host.StateHash() And recoveryGame.lastTopples = host.lastTopples, "full state restores authoritative game")

' Exercise the same reliable session path used by GameKit and other transports.
Local pair:TLoopbackPair = TLoopbackPair.Create(32, 900)
Local hostSession:TNetSession = TNetSession.CreateHost(pair.First(), CASCADE_APP_ID, CASCADE_APP_VERSION, 1, 900)
Local clientSession:TNetSession = TNetSession.CreateClient(pair.Second(), CASCADE_APP_ID, CASCADE_APP_VERSION, Null, 0, 1, 900)
Local sessionEvent:SSessionEvent
clientSession.PollAt(sessionEvent, 0)
CheckProtocol(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.JoinRequested, "host receives join request")
Local hostPeer:SNetPeer = sessionEvent.Peer()
CheckProtocol(hostSession.Accept(hostPeer) = ETransportResult.Ok, "host accepts session peer")
CheckProtocol(hostSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "host session joins")
CheckProtocol(clientSession.PollAt(sessionEvent, 0) And sessionEvent.Kind() = ESessionEventKind.Joined, "client session joins")
Local clientPeer:SNetPeer = sessionEvent.Peer()

Local networkConfig:SCascadeMatchConfig = New SCascadeMatchConfig(ECascadeBoardLayout.Square, 5, 2, 1)
Local configLength:Size_T = EncodeCascadeConfig(Byte Ptr(packet), Size_T(packet.Length), networkConfig)
Local lobbySelection:SCascadeMatchConfig
CheckProtocol(DecodeCascadeConfig(New SPacketView(Byte Ptr(packet), configLength), lobbySelection) And lobbySelection.layout = networkConfig.layout, "decode room configuration payload")

Local networkHost:TCascadeGame = TCascadeGame.Create(networkConfig.CreateBoard())
Local networkClient:TCascadeGame = TCascadeGame.Create(networkConfig.CreateBoard())
networkHost.Reset(networkConfig.startingPlayer)
networkClient.Reset(networkConfig.startingPlayer)
Local networkRequest:SCascadeMoveRequest = New SCascadeMoveRequest(networkClient.turn, networkClient.board.starts[1])
Local requestLength:Size_T = EncodeCascadeMoveRequest(Byte Ptr(packet), Size_T(packet.Length), networkRequest)
CheckProtocol(clientSession.Send(clientPeer, CASCADE_MSG_MOVE_REQUEST, CASCADE_GAME_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(packet), requestLength) = ETransportResult.Ok, "client sends move request")
CheckProtocol(hostSession.PollAt(sessionEvent, 3) And sessionEvent.Kind() = ESessionEventKind.Message And sessionEvent.MessageType() = CASCADE_MSG_MOVE_REQUEST, "host receives move request")
CheckProtocol(DecodeCascadeMoveRequest(sessionEvent.Payload(), networkRequest), "host decodes move request")
Local networkResult:ECascadeMoveResult = networkHost.ApplyMove(1, networkRequest.cell)
Local networkMove:SCascadeAppliedMove = New SCascadeAppliedMove(networkRequest.turn, 1, networkRequest.cell, networkResult, networkHost.StateHash())
Local appliedLength:Size_T = EncodeCascadeAppliedMove(Byte Ptr(packet), Size_T(packet.Length), networkMove)
CheckProtocol(hostSession.Send(hostPeer, CASCADE_MSG_MOVE_APPLIED, CASCADE_GAME_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(packet), appliedLength) = ETransportResult.Ok, "host acknowledges move")
CheckProtocol(clientSession.PollAt(sessionEvent, 4) And sessionEvent.Kind() = ESessionEventKind.Message And sessionEvent.MessageType() = CASCADE_MSG_MOVE_APPLIED, "client receives authoritative move")
CheckProtocol(DecodeCascadeAppliedMove(sessionEvent.Payload(), networkMove), "client decodes authoritative move")
CheckProtocol(networkClient.ApplyMove(networkMove.player, networkMove.cell) = networkMove.result And networkClient.StateHash() = networkMove.stateHash, "session move keeps both games identical")

CheckProtocol(clientSession.Send(clientPeer, CASCADE_MSG_STATE_REQUEST, CASCADE_CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered) = ETransportResult.Ok, "client requests full state")
CheckProtocol(hostSession.PollAt(sessionEvent, 5) And sessionEvent.Kind() = ESessionEventKind.Message And sessionEvent.MessageType() = CASCADE_MSG_STATE_REQUEST And sessionEvent.Payload().Length() = 0, "host receives full-state request")
stateLength = EncodeCascadeState(Byte Ptr(statePacket), Size_T(statePacket.Length), networkHost)
CheckProtocol(hostSession.Send(hostPeer, CASCADE_MSG_STATE, CASCADE_CONTROL_CHANNEL, EDeliveryMode.ReliableOrdered, Byte Ptr(statePacket), stateLength) = ETransportResult.Ok, "host sends full state")
CheckProtocol(clientSession.PollAt(sessionEvent, 6) And sessionEvent.Kind() = ESessionEventKind.Message And sessionEvent.MessageType() = CASCADE_MSG_STATE, "client receives full state")
networkClient.counters[0] :+ 1
CheckProtocol(DecodeCascadeState(sessionEvent.Payload(), networkClient) And networkClient.StateHash() = networkHost.StateHash(), "full state repairs deliberate divergence")

hostSession.Close()
clientSession.Close()

Print "Counter Cascade protocol tests passed"
