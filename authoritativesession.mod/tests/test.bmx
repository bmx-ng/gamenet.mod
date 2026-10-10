SuperStrict

Framework BRL.StandardIO
Import GameNet.AuthoritativeSession
Import GameNet.Loopback

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Function StateValue:Int(view:SPacketView)
	If view.Length() <> 1 Then Return -1
	Return Int(view.Data()[0])
End Function

Function AwaitEvent:Int(session:TNetSession, kind:ESessionEventKind, event:SSessionEvent Var, attempts:Int = 20)
	For Local attempt:Int = 0 Until attempts
		If session.Poll(event) And event.Kind() = kind Then Return True
	Next
	Return False
End Function

Type TTestPrediction Implements IAuthoritativePredictionSimulation
	Field value:Int
	Field loadedTick:UInt
	Field replayed:Int

	Method LoadAuthoritativeState:Int(tick:UInt, state:SPacketView)
		If state.Length() <> 1 Then Return False
		loadedTick = tick
		value = Int(state.Data()[0])
		Return True
	End Method

	Method ReplayInput:Int(sequence:UInt, input:SPacketView)
		If input.Length() <> 1 Then Return False
		value :+ Int(input.Data()[0])
		replayed :+ 1
		Return True
	End Method
End Type

Local config:SAuthoritativeSessionConfig = New SAuthoritativeSessionConfig(2, 2, 8, 8, 4, 2, 4, 4, 60.0, 2.0, 12.0, 10, 11, 1)
Check(TAuthoritativeClientSession.Create(New SAuthoritativeSessionConfig) = Null, "reject invalid client configuration")
Check(TAuthoritativeServerSession.Create(New SAuthoritativeSessionConfig) = Null, "reject invalid server configuration")
Local maximumConfig:SAuthoritativeSessionConfig = New SAuthoritativeSessionConfig(AUTHORITATIVE_SESSION_MAX_PLAYERS, AUTHORITATIVE_SESSION_MAX_PLAYERS, 8, 8, 4, 2, 4)
Check(TAuthoritativeClientSession.Create(maximumConfig) <> Null And TAuthoritativeServerSession.Create(maximumConfig) <> Null, "support sixteen-player authoritative sessions")
Local excessiveConfig:SAuthoritativeSessionConfig = New SAuthoritativeSessionConfig(AUTHORITATIVE_SESSION_MAX_PLAYERS + 1, 1, 8, 8, 4, 2, 4)
Check(TAuthoritativeClientSession.Create(excessiveConfig) = Null And TAuthoritativeServerSession.Create(excessiveConfig) = Null, "reject authoritative sessions above sixteen players")

Local client:TAuthoritativeClientSession = TAuthoritativeClientSession.Create(config)
Local server:TAuthoritativeServerSession = TAuthoritativeServerSession.Create(config)
Check(client <> Null And server <> Null, "create authoritative sessions")
Check(client.SetLocalEntity(0), "set local entity")

Local peer:SNetPeer = New SNetPeer(7, 1)
Check(server.BindPlayer(0, peer), "bind authority player")
Check(server.PlayerForPeer(peer) = 0, "find player by peer")

Local inputA:Byte[1]
Local inputB:Byte[1]
Local inputC:Byte[1]
inputA[0] = 2
inputB[0] = 3
inputC[0] = 4
Check(client.QueueInput(Byte Ptr(inputA), 1) = 1, "queue first predicted input")
Check(client.QueueInput(Byte Ptr(inputB), 1) = 2, "queue second predicted input")

Local packet:Byte[128]
Local length:Size_T = client.WriteInputs(Byte Ptr(packet), Size_T(packet.Length))
Check(length > 0, "write redundant input batch")
Check(server.ReceiveInputs(0, peer, New SPacketView(Byte Ptr(packet), length)), "receive input batch")
Check(server.InputCount(0) = 2, "queue sequenced server inputs")

Local queued:SPredictionInput
Check(server.PeekInput(0, queued) And queued.Sequence() = 1 And StateValue(queued.Payload()) = 2, "peek oldest authority input")
Check(server.AcknowledgeInput(0, 1), "acknowledge applied authority input")
Check(server.AcknowledgedInput(0) = 1 And server.InputCount(0) = 1, "advance authority acknowledgement")

Local state:Byte[1]
state[0] = 10
length = server.WriteSnapshot(0, 0, 50, Byte Ptr(state), 1, Byte Ptr(packet), Size_T(packet.Length))
Check(length > 0, "write local authoritative snapshot")
Local snapshot:SAuthoritativeSnapshot
Check(client.ReceiveSnapshot(New SPacketView(Byte Ptr(packet), length), 1000, snapshot), "receive local authoritative snapshot")
Check(snapshot.Entity() = 0 And snapshot.Tick() = 50 And snapshot.AcknowledgedInput() = 1 And StateValue(snapshot.State()) = 10, "decode snapshot metadata")
Check(client.PendingInputCount() = 1 And client.AcknowledgedInput() = 1, "discard acknowledged prediction input")

Local prediction:TTestPrediction = New TTestPrediction
Check(client.Reconcile(snapshot, prediction), "reconcile local prediction")
Check(prediction.loadedTick = 50 And prediction.replayed = 1 And prediction.value = 13, "restore authority and replay pending input")

' An acknowledgement may not advance beyond an input the client issued.
Local corrupt:Byte[32]
Local corruptWriter:SPacketWriter = New SPacketWriter(Byte Ptr(corrupt), Size_T(corrupt.Length))
corruptWriter.WriteUInt8(AUTHORITATIVE_SESSION_WIRE_VERSION)
corruptWriter.WriteUInt16(0)
corruptWriter.WriteUInt32(51)
corruptWriter.WriteUInt32(99)
corruptWriter.WriteUInt16(1)
corruptWriter.WriteUInt8(12)
Check(Not client.ReceiveSnapshot(corruptWriter.View(), 1010, snapshot), "reject future acknowledgement")
Check(client.PendingInputCount() = 1 And client.AcknowledgedInput() = 1, "future acknowledgement has no side effects")

Check(server.AcknowledgeInput(0, 2), "acknowledge second authority input")
Check(client.QueueInput(Byte Ptr(inputC), 1) = 3, "queue third predicted input")
length = client.WriteInputs(Byte Ptr(packet), Size_T(packet.Length))
Check(server.ReceiveInputs(0, peer, New SPacketView(Byte Ptr(packet), length)), "receive overlapping redundant batch")
Check(server.InputCount(0) = 1 And server.DuplicateInputs() > 0, "ignore duplicate and accept next input")
Check(server.PeekInput(0, queued) And queued.Sequence() = 3, "retain next contiguous input")
Check(server.AcknowledgeInput(0, 3), "acknowledge third authority input")

' A future input is valid but held until redundancy fills the gap.
Local writer:SPacketWriter = New SPacketWriter(Byte Ptr(packet), Size_T(packet.Length))
writer.WriteUInt8(AUTHORITATIVE_SESSION_WIRE_VERSION)
writer.WriteUInt8(1)
writer.WriteUInt32(5)
writer.WriteUInt16(1)
writer.WriteUInt8(9)
Check(server.ReceiveInputs(0, peer, writer.View()), "accept packet containing future gap")
Check(server.InputCount(0) = 0 And server.InputGaps() = 1, "leave gapped input unprocessed")

' Malformed packets never partially mutate queues.
writer = New SPacketWriter(Byte Ptr(packet), Size_T(packet.Length))
writer.WriteUInt8(AUTHORITATIVE_SESSION_WIRE_VERSION)
writer.WriteUInt8(1)
writer.WriteUInt32(4)
writer.WriteUInt16(2)
writer.WriteUInt8(7)
Check(Not server.ReceiveInputs(0, peer, writer.View()), "reject truncated input packet")
Check(server.InputCount(0) = 0 And server.RejectedPackets() = 1, "malformed input has no side effects")

' Store two remote snapshots and interpolate their opaque states.
state[0] = 20
length = server.WriteSnapshot(0, 1, 60, Byte Ptr(state), 1, Byte Ptr(packet), Size_T(packet.Length))
Check(client.ReceiveSnapshot(New SPacketView(Byte Ptr(packet), length), 1100, snapshot), "receive first remote snapshot")
state[0] = 30
length = server.WriteSnapshot(0, 1, 70, Byte Ptr(state), 1, Byte Ptr(packet), Size_T(packet.Length))
Check(client.ReceiveSnapshot(New SPacketView(Byte Ptr(packet), length), 1200, snapshot), "receive second remote snapshot")
Local sample:SSnapshotSample
Check(client.SampleEntity(1, 65.0, sample), "sample remote entity")
Check(sample.IsInterpolated() And sample.FromTick() = 60 And sample.ToTick() = 70 And Abs(sample.Blend() - 0.5) < 0.001, "interpolate between remote snapshots")
Check(StateValue(sample.FromState()) = 20 And StateValue(sample.ToState()) = 30, "retain remote snapshot states")
Check(client.RenderTick(1200) > 0.0 And client.DelayTicks() >= 2.0, "estimate delayed render tick")

' Foreground recovery drops stale presentation history and waits for a local snapshot.
Check(client.BeginRecovery() And client.IsRecovering(), "begin authoritative recovery")
Check(client.QueueInput(Byte Ptr(inputA), 1) = 0, "hold new prediction while recovering")
Local emptySample:SSnapshotSample
Check(Not client.SampleEntity(1, 65.0, emptySample), "clear stale remote snapshots")
state[0] = 40
length = server.WriteSnapshot(0, 1, 80, Byte Ptr(state), 1, Byte Ptr(packet), Size_T(packet.Length))
Check(client.ReceiveSnapshot(New SPacketView(Byte Ptr(packet), length), 1300, snapshot) And client.IsRecovering(), "remote snapshot does not finish recovery")
state[0] = 50
length = server.WriteSnapshot(0, 0, 80, Byte Ptr(state), 1, Byte Ptr(packet), Size_T(packet.Length))
Check(client.ReceiveSnapshot(New SPacketView(Byte Ptr(packet), length), 1300, snapshot) And Not client.IsRecovering(), "local snapshot finishes recovery")
Check(client.QueueInput(Byte Ptr(inputA), 1) > 0, "resume prediction after recovery")

server.UnbindPlayer(0)
Check(Not server.PlayerBound(0) And server.InputCount(0) = 0, "clear unbound player state")
Check(Not client.Failed() And Not server.Failed(), "sessions remain healthy")

' Exercise the public send helpers through a complete GameNet session.
Local pair:TLoopbackPair = TLoopbackPair.Create(32, 1200)
Local hostSession:TNetSession = TNetSession.CreateHost(pair.First(), $41555448:UInt, 1, 1, 1200)
Local clientSession:TNetSession = TNetSession.CreateClient(pair.Second(), $41555448:UInt, 1, Null, 0, 1, 1200)
Local event:SSessionEvent
clientSession.Poll(event)
Check(AwaitEvent(hostSession, ESessionEventKind.JoinRequested, event), "loopback join request")
Local hostPeer:SNetPeer = event.Peer()
Check(hostSession.Accept(hostPeer) = ETransportResult.Ok, "loopback host accepts")
Check(AwaitEvent(hostSession, ESessionEventKind.Joined, event), "loopback host joined")
Check(AwaitEvent(clientSession, ESessionEventKind.Joined, event), "loopback client joined")
Local clientPeer:SNetPeer = event.Peer()

Local networkClient:TAuthoritativeClientSession = TAuthoritativeClientSession.Create(config)
Local networkServer:TAuthoritativeServerSession = TAuthoritativeServerSession.Create(config)
Check(networkClient.SetLocalEntity(0) And networkServer.BindPlayer(0, hostPeer), "bind loopback authoritative sessions")
Check(networkClient.QueueInput(Byte Ptr(inputA), 1) = 1, "queue loopback input")
Check(networkClient.SendInputs(clientSession, clientPeer) = ETransportResult.Ok, "send authoritative input helper")
Check(AwaitEvent(hostSession, ESessionEventKind.Message, event), "receive authoritative input message")
Check(event.MessageType() = config.inputMessageType And event.Channel() = config.channel And event.Delivery() = EDeliveryMode.UnreliableSequenced, "authoritative input routing")
Check(networkServer.ReceiveInputs(0, event.Peer(), event.Payload()), "authority receives helper input")
Check(networkServer.PeekInput(0, queued) And networkServer.AcknowledgeInput(0, queued.Sequence()), "authority applies helper input")

state[0] = 44
Check(networkServer.SendSnapshot(hostSession, 0, 0, 99, Byte Ptr(state), 1) = ETransportResult.Ok, "send authoritative snapshot helper")
Check(AwaitEvent(clientSession, ESessionEventKind.Message, event), "receive authoritative snapshot message")
Check(event.MessageType() = config.snapshotMessageType And event.Channel() = config.channel And event.Delivery() = EDeliveryMode.UnreliableSequenced, "authoritative snapshot routing")
Check(networkClient.ReceiveSnapshot(event.Payload(), 2000, snapshot), "client receives helper snapshot")
Check(snapshot.Tick() = 99 And snapshot.AcknowledgedInput() = 1 And StateValue(snapshot.State()) = 44, "helper snapshot contents")
Check(networkClient.PendingInputCount() = 0, "helper snapshot acknowledges input")
hostSession.Close()
clientSession.Close()

Print "GameNet.AuthoritativeSession tests passed"
