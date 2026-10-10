SuperStrict

Framework BRL.StandardIO
Import GameNet.RollbackSession
Import GameNet.Replay

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Function WriteSingleInputBatch:Size_T(buffer:Byte Ptr, capacity:Size_T, simulatedFrame:UInt, inputFrame:UInt, value:Byte)
	Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
	writer.WriteUInt32(simulatedFrame)
	writer.WriteUInt8(1)
	writer.WriteUInt32(inputFrame)
	writer.WriteUInt16(1)
	writer.WriteUInt8(UInt(value) & $ff:UInt)
	If writer.Failed() Then Return 0
	Return writer.Position()
End Function

Function RecordConfirmedFrames:Int(tape:TReplayTape, session:TRollbackSession, nextFrame:UInt Var, inputs:SPacketView[])
	If inputs.Length <> session.PlayerCount() Then Return False
	While session.HasConfirmedFrame() And Not RollbackFrameAfter(nextFrame, session.ConfirmedFrame()) And RollbackFrameAfter(session.CurrentFrame(), nextFrame)
		For Local player:Int = 0 Until inputs.Length
			If Not session.GetConfirmedInput(player, nextFrame, inputs[player]) Then Return False
		Next
		If Not tape.Append(nextFrame, inputs) Then Return False
		nextFrame :+ 1
	Wend
	Return True
End Function

Type TTestSimulation Implements IRollbackSimulation, IRollbackEffectSimulation
	Field position0:Int
	Field position1:Int
	Field corruptFrame:Int = -1

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(UInt(position0))
		writer.WriteUInt32(UInt(position1))
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method LoadState:Int(state:SPacketView)
		Local reader:SPacketReader = New SPacketReader(state)
		Local value0:UInt
		Local value1:UInt
		If Not reader.ReadUInt32(value0) Or Not reader.ReadUInt32(value1) Or reader.Remaining() <> 0 Then Return False
		position0 = Int(value0)
		position1 = Int(value1)
		Return True
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If capacity < 1 Then Return 0
		buffer[0] = 0
		If Not previous.IsEmpty() Then buffer[0] = previous.Data()[0]
		Return 1
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		Return SimulateFrame(frame, inputs, Null)
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[], effects:IRollbackEffectWriter)
		If inputs.Length <> 2 Or inputs[0].Payload().Length() <> 1 Or inputs[1].Payload().Length() <> 1 Then Return False
		position0 :+ Int(Byte(inputs[0].Payload().Data()[0]))
		position1 :+ Int(Byte(inputs[1].Payload().Data()[0]))
		If corruptFrame >= 0 And frame = UInt(corruptFrame) Then position0 :+ 1000
		Local payload:Byte[1]
		payload[0] = Byte(frame & $ff)
		If effects Then Return effects.Emit(1, Byte Ptr(payload), 1)
		Return True
	End Method
End Type

Type TPlainSimulation Implements IRollbackSimulation
	Field value:UInt

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		writer.WriteUInt32(value)
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method LoadState:Int(state:SPacketView)
		Local reader:SPacketReader = New SPacketReader(state)
		Return reader.ReadUInt32(value) And reader.Remaining() = 0
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If capacity < 1 Then Return 0
		buffer[0] = 0
		Return 1
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		value :+ 1
		Return True
	End Method
End Type

Type TMultiSimulation Implements IRollbackSimulation
	Field positions:Int[3]
	Field corruptFrame:Int = -1

	Method SaveState:Size_T(buffer:Byte Ptr, capacity:Size_T)
		Local writer:SPacketWriter = New SPacketWriter(buffer, capacity)
		For Local player:Int = 0 Until positions.Length
			writer.WriteUInt32(UInt(positions[player]))
		Next
		If writer.Failed() Then Return 0
		Return writer.Position()
	End Method

	Method LoadState:Int(state:SPacketView)
		Local reader:SPacketReader = New SPacketReader(state)
		For Local player:Int = 0 Until positions.Length
			Local value:UInt
			If Not reader.ReadUInt32(value) Then Return False
			positions[player] = Int(value)
		Next
		Return reader.Remaining() = 0
	End Method

	Method PredictInput:Size_T(player:Int, frame:UInt, previous:SPacketView, buffer:Byte Ptr, capacity:Size_T)
		If capacity < 1 Then Return 0
		buffer[0] = 0
		If Not previous.IsEmpty() Then buffer[0] = previous.Data()[0]
		Return 1
	End Method

	Method SimulateFrame:Int(frame:UInt, inputs:SRollbackInput[])
		If inputs.Length <> positions.Length Then Return False
		For Local player:Int = 0 Until positions.Length
			If inputs[player].Payload().Length() <> 1 Then Return False
			positions[player] :+ Int(Byte(inputs[player].Payload().Data()[0]))
		Next
		If corruptFrame >= 0 And frame = UInt(corruptFrame) Then positions[2] :+ 2000
		Return True
	End Method
End Type

Local invalid:SRollbackSessionConfig = New SRollbackSessionConfig(1, 0, 32, 8, 1)
Check(TRollbackSession.Create(New TTestSimulation, invalid) = Null, "reject one-player session")
Local tooManyPlayers:SRollbackSessionConfig = New SRollbackSessionConfig(ROLLBACK_SESSION_MAX_PLAYERS + 1, 0, 32, 8, 1)
Check(TRollbackSession.Create(New TTestSimulation, tooManyPlayers) = Null, "reject session above supported player limit")

Local plainSimulation:TPlainSimulation = New TPlainSimulation
Local plainConfig:SRollbackSessionConfig = New SRollbackSessionConfig(2, 0, 32, 4, 1)
Local plainSession:TRollbackSession = TRollbackSession.Create(plainSimulation, plainConfig)
Local plainNeutral:Byte[1]
Check(plainSession.Start(Byte Ptr(plainNeutral), 1), "start simulation without effect source")
Check(plainSession.Step(Byte Ptr(plainNeutral), 1), "advance simulation without effect source")
Check(plainSession.PendingConfirmedEffects() = 0, "effect support remains optional")
Check(plainSession.FailureReason() = ERollbackSessionFailure.None, "healthy session has no failure reason")

Local invalidStartSession:TRollbackSession = TRollbackSession.Create(New TPlainSimulation, plainConfig)
Check(Not invalidStartSession.Start(Null, 0), "reject invalid initial input")
Check(invalidStartSession.Failed() And invalidStartSession.FailureReason() = ERollbackSessionFailure.InvalidStartInput, "report invalid start failure")
Check(invalidStartSession.StepStatus() = ERollbackStepStatus.Failed, "failed step status")

Local stalledSimulation:TPlainSimulation = New TPlainSimulation
Local stalledConfig:SRollbackSessionConfig = New SRollbackSessionConfig(3, 0, 32, 4, 1, 1, 2, 4, 0, 4)
Local stalledSession:TRollbackSession = TRollbackSession.Create(stalledSimulation, stalledConfig)
Check(stalledSession.Start(Byte Ptr(plainNeutral), 1), "start stall diagnostic session")
For Local frame:Int = 0 Until 3
	Check(stalledSession.StepStatus() = ERollbackStepStatus.Ready, "prediction budget initially ready")
	Check(stalledSession.Step(Byte Ptr(plainNeutral), 1), "consume prediction budget")
Next
Local stalledInfo:SRollbackStepInfo = stalledSession.StepInfo()
Check(stalledInfo.Status() = ERollbackStepStatus.WaitingForInputs And stalledInfo.CurrentFrame() = 3, "report input stall")
Check(stalledInfo.InputFrame() = 0 And stalledInfo.PredictionLead() = 3, "report stalled prediction frontier")
Check(stalledInfo.UnconfirmedPlayersMask() = 6 And stalledInfo.UnconfirmedPlayerCount() = 2, "report all blocking players")
Check(stalledInfo.IsPlayerUnconfirmed(1) And stalledInfo.IsPlayerUnconfirmed(2) And Not stalledInfo.IsPlayerUnconfirmed(0), "query blocking player")
Local stalledPacket:Byte[32]
Local stalledLength:Size_T = WriteSingleInputBatch(Byte Ptr(stalledPacket), Size_T(stalledPacket.Length), 3, 0, 0)
Check(stalledSession.ReceiveInputs(1, New SPacketView(Byte Ptr(stalledPacket), stalledLength)), "receive first blocking input")
stalledInfo = stalledSession.StepInfo()
Check(stalledInfo.Status() = ERollbackStepStatus.WaitingForInputs And stalledInfo.UnconfirmedPlayersMask() = 4, "identify remaining blocking player")
Check(stalledSession.ReceiveInputs(2, New SPacketView(Byte Ptr(stalledPacket), stalledLength)), "receive final blocking input")
stalledInfo = stalledSession.StepInfo()
Check(stalledInfo.Status() = ERollbackStepStatus.Ready And stalledInfo.InputFrame() = 1 And stalledInfo.PredictionLead() = 2, "input confirmation releases stall")
stalledSession.Stop()
Check(stalledSession.StepStatus() = ERollbackStepStatus.Stopped, "stopped step status")

' A resumed non-authority can request recovery before a hash mismatch is observed.
Local recoverySimulation:TPlainSimulation = New TPlainSimulation
Local recoveryConfig:SRollbackSessionConfig = New SRollbackSessionConfig(2, 1, 32, 4, 1)
Local recoverySession:TRollbackSession = TRollbackSession.Create(recoverySimulation, recoveryConfig)
Check(recoverySession.Start(Byte Ptr(plainNeutral), 1), "start lifecycle recovery session")
Check(recoverySession.RequestStateSync() And recoverySession.NeedsStateSync(), "request explicit state sync")
Check(recoverySession.StateSyncMismatchFrame() = recoverySession.CurrentFrame(), "tag explicit recovery frame")
Check(recoverySession.WriteStateSyncRequest(Byte Ptr(stalledPacket), Size_T(stalledPacket.Length)) > 0, "write explicit state sync request")
Local authorityRecovery:TRollbackSession = TRollbackSession.Create(New TPlainSimulation, plainConfig)
Check(authorityRecovery.Start(Byte Ptr(plainNeutral), 1), "start authority lifecycle session")
Check(Not authorityRecovery.RequestStateSync(), "authority cannot request its own state")

Local simulation0:TTestSimulation = New TTestSimulation
Local simulation1:TTestSimulation = New TTestSimulation
simulation1.corruptFrame = 70
Local config0:SRollbackSessionConfig = New SRollbackSessionConfig(2, 0, 128, 8, 1, 3, 8, 12, 10, 16)
Local config1:SRollbackSessionConfig = New SRollbackSessionConfig(2, 1, 128, 8, 1, 3, 8, 12, 10, 16)
Local session0:TRollbackSession = TRollbackSession.Create(simulation0, config0)
Local session1:TRollbackSession = TRollbackSession.Create(simulation1, config1)
Check(session0 <> Null And session1 <> Null, "create rollback sessions")

Local neutral:Byte[1]
Check(session0.Start(Byte Ptr(neutral), 1) And session1.Start(Byte Ptr(neutral), 1), "start rollback sessions")
Local packet0:Byte[256]
Local packet1:Byte[256]
Local effectCount0:Int
Local effectCount1:Int
Local lastEffectFrame0:UInt
Local lastEffectFrame1:UInt
Local observedStateSync:Int
Local replayTape:TReplayTape = TReplayTape.Create(2, 151, 8, 1)
Local replayInitialState:Byte[8]
Check(replayTape.Begin(0, Byte Ptr(replayInitialState), Size_T(replayInitialState.Length)), "begin rollback replay recording")
Local replayInputs:SPacketView[2]
Local nextReplayFrame:UInt

For Local frame:Int = 0 Until 150
	Local input0:Byte[1]
	Local input1:Byte[1]
	If (frame / 11) Mod 2 = 0 Then input0[0] = 1 Else input0[0] = Byte(-1)
	If (frame / 13) Mod 2 = 0 Then input1[0] = Byte(-1) Else input1[0] = 1
	Check(session0.CanStep() And session1.CanStep(), "sessions can advance")
	Check(session0.Step(Byte Ptr(input0), 1) And session1.Step(Byte Ptr(input1), 1), "advance sessions")

	' Deliver every fourth frame so both peers must predict and occasionally roll back.
	If frame Mod 4 = 3 Then
		Local length0:Size_T = session0.WriteInputs(Byte Ptr(packet0), Size_T(packet0.Length))
		Local length1:Size_T = session1.WriteInputs(Byte Ptr(packet1), Size_T(packet1.Length))
		Check(length0 > 0 And length1 > 0, "write redundant inputs")
		Check(session1.ReceiveInputs(0, New SPacketView(Byte Ptr(packet0), length0)), "receive player zero inputs")
		Check(session0.ReceiveInputs(1, New SPacketView(Byte Ptr(packet1), length1)), "receive player one inputs")
	End If

	Local hashLength0:Size_T = session0.WriteReadyHash(Byte Ptr(packet0), Size_T(packet0.Length))
	If hashLength0 > 0 Then Check(session1.ReceiveHash(New SPacketView(Byte Ptr(packet0), hashLength0)), "receive player zero hash")
	Local hashLength1:Size_T = session1.WriteReadyHash(Byte Ptr(packet1), Size_T(packet1.Length))
	If hashLength1 > 0 Then Check(session0.ReceiveHash(New SPacketView(Byte Ptr(packet1), hashLength1)), "receive player one hash")

	If session1.NeedsStateSync() Then
		observedStateSync = True
		Check(session1.StepInfo().NeedsStateSync() And session1.StepInfo().StateSyncMismatchFrame() = session1.StateSyncMismatchFrame(), "step info reports state recovery")
		Local requestLength:Size_T = session1.WriteStateSyncRequest(Byte Ptr(packet1), Size_T(packet1.Length))
		Check(requestLength > 0, "write state-sync request")
		Local responseLength:Size_T = session0.WriteStateSyncResponse(New SPacketView(Byte Ptr(packet1), requestLength), Byte Ptr(packet0), Size_T(packet0.Length))
		Check(responseLength > 0, "write authoritative state-sync response")
		packet0[Int(responseLength) - 1] :~ 1
		Check(Not session1.ReceiveStateSync(New SPacketView(Byte Ptr(packet0), responseLength)), "reject corrupt state-sync response")
		Check(session1.NeedsStateSync() And Not session1.Failed(), "corrupt response does not change session state")
		packet0[Int(responseLength) - 1] :~ 1
		Check(session1.ReceiveStateSync(New SPacketView(Byte Ptr(packet0), responseLength)), "apply authoritative state sync")
	End If
	Check(RecordConfirmedFrames(replayTape, session0, nextReplayFrame, replayInputs), "record newly confirmed rollback frames")

	Local effect:SRollbackEffect
	While session0.PollConfirmedEffect(effect)
		Check(effect.Kind() = 1 And effect.Payload().Length() = 1, "player zero confirmed effect")
		If effectCount0 > 0 Then Check(RollbackFrameAfter(effect.Frame(), lastEffectFrame0), "player zero effect order")
		lastEffectFrame0 = effect.Frame()
		effectCount0 :+ 1
	Wend
	While session1.PollConfirmedEffect(effect)
		Check(effect.Kind() = 1 And effect.Payload().Length() = 1, "player one confirmed effect")
		If effectCount1 > 0 Then Check(RollbackFrameAfter(effect.Frame(), lastEffectFrame1), "player one effect order")
		lastEffectFrame1 = effect.Frame()
		effectCount1 :+ 1
	Wend
Next

' Deliver the final batch and run one frame to apply any pending rollback.
Local finalLength0:Size_T = session0.WriteInputs(Byte Ptr(packet0), Size_T(packet0.Length))
Local finalLength1:Size_T = session1.WriteInputs(Byte Ptr(packet1), Size_T(packet1.Length))
Check(session1.ReceiveInputs(0, New SPacketView(Byte Ptr(packet0), finalLength0)), "receive final player zero inputs")
Check(session0.ReceiveInputs(1, New SPacketView(Byte Ptr(packet1), finalLength1)), "receive final player one inputs")
Local zero:Byte[1]
Check(session0.Step(Byte Ptr(zero), 1) And session1.Step(Byte Ptr(zero), 1), "resolve final rollback")
Check(RecordConfirmedFrames(replayTape, session0, nextReplayFrame, replayInputs), "record final confirmed rollback frames")

Local finalEffect:SRollbackEffect
While session0.PollConfirmedEffect(finalEffect)
	lastEffectFrame0 = finalEffect.Frame()
	effectCount0 :+ 1
Wend
While session1.PollConfirmedEffect(finalEffect)
	lastEffectFrame1 = finalEffect.Frame()
	effectCount1 :+ 1
Wend

Check(simulation0.position0 = simulation1.position0 And simulation0.position1 = simulation1.position1, "converged deterministic state")
Check(session0.RollbackCount() > 0 And session1.RollbackCount() > 0, "rollback occurred")
Check(session0.PredictionMismatches() > 0 And session1.PredictionMismatches() > 0, "prediction mismatch detected")
Check(session0.HashesChecked() > 0 And session1.HashesChecked() > 0, "confirmed hashes checked")
Check(observedStateSync And session1.StateSyncCount() = 1 And Not session1.NeedsStateSync(), "deterministic desync recovered without restart")
Check(session0.HashMismatches() > 0 And session1.HashMismatches() > 0, "deterministic desync detected by both peers")
Check(effectCount0 = 151 And effectCount1 = 151, "confirmed effects released once")
Check(lastEffectFrame0 = 150 And lastEffectFrame1 = 150, "confirmed effects cover simulated frames")
Check(session0.DroppedConfirmedEffects() = 0 And session1.DroppedConfirmedEffects() = 0, "confirmed effect queue did not overflow")
Check(Not session0.Failed() And Not session1.Failed(), "sessions remained healthy")
Check(session0.FailureReason() = ERollbackSessionFailure.None And session1.FailureReason() = ERollbackSessionFailure.None, "recovered sessions have no fatal failure")
Check(replayTape.FrameCount() = 151, "record every confirmed rollback frame")

' Exercise a complete explicit foreground recovery without manufacturing a hash mismatch.
Check(session1.RequestStateSync(), "request foreground state sync")
Local resumeRequestLength:Size_T = session1.WriteStateSyncRequest(Byte Ptr(packet1), Size_T(packet1.Length))
Local resumeResponseLength:Size_T = session0.WriteStateSyncResponse(New SPacketView(Byte Ptr(packet1), resumeRequestLength), Byte Ptr(packet0), Size_T(packet0.Length))
Check(resumeRequestLength > 0 And resumeResponseLength > 0, "exchange foreground state sync")
Check(session1.ReceiveStateSync(New SPacketView(Byte Ptr(packet0), resumeResponseLength)), "apply foreground state sync")
Check(Not session1.NeedsStateSync() And session1.StateSyncCount() = 2, "complete explicit foreground recovery")

Local replaySimulation:TTestSimulation = New TTestSimulation
Local recordedInitialState:SPacketView
Check(replayTape.InitialState(recordedInitialState) And replaySimulation.LoadState(recordedInitialState), "restore recorded initial state")
Local replayCursor:SReplayCursor = replayTape.Cursor()
Local replayFrame:SReplayFrame
Local simulatedInputs:SRollbackInput[2]
While replayCursor.Next(replayFrame)
	For Local player:Int = 0 Until simulatedInputs.Length
		Local replayInput:SPacketView
		Check(replayFrame.Input(player, replayInput), "read recorded rollback input")
		simulatedInputs[player] = New SRollbackInput(replayFrame.Frame(), player, ERollbackInputStatus.Confirmed, replayInput)
	Next
	Check(replaySimulation.SimulateFrame(replayFrame.Frame(), simulatedInputs), "play recorded rollback frame")
Wend
Check(replaySimulation.position0 = simulation0.position0 And replaySimulation.position1 = simulation0.position1, "replay reproduces final rollback state")

' Exercise the same orchestration with three peers. Inputs travel all-to-all,
' while hashes and recovery use player zero as a hub/authority.
Local multiSimulations:TMultiSimulation[3]
Local multiSessions:TRollbackSession[3]
For Local player:Int = 0 Until multiSessions.Length
	multiSimulations[player] = New TMultiSimulation
	Local multiConfig:SRollbackSessionConfig = New SRollbackSessionConfig(3, player, 128, 12, 1, 2, 8, 10, 10, 16)
	multiSessions[player] = TRollbackSession.Create(multiSimulations[player], multiConfig)
	Check(multiSessions[player] <> Null And multiSessions[player].Start(Byte Ptr(neutral), 1), "start three-player rollback session")
Next
multiSimulations[2].corruptFrame = 45

Local multiPacket:Byte[256]
Local multiResponse:Byte[256]
For Local frame:Int = 0 Until 120
	For Local player:Int = 0 Until multiSessions.Length
		Local input:Byte[1]
		If ((frame / (7 + player)) + player) Mod 2 = 0 Then input[0] = 1 Else input[0] = Byte(-1)
		Check(multiSessions[player].CanStep(), "three-player session can advance")
		Check(multiSessions[player].Step(Byte Ptr(input), 1), "advance three-player session")
	Next

	If frame Mod 3 = 2 Then
		For Local source:Int = 0 Until multiSessions.Length
			Local length:Size_T = multiSessions[source].WriteInputs(Byte Ptr(multiPacket), Size_T(multiPacket.Length))
			Check(length > 0, "write three-player input batch")
			For Local receiver:Int = 0 Until multiSessions.Length
				If receiver <> source Then Check(multiSessions[receiver].ReceiveInputs(source, New SPacketView(Byte Ptr(multiPacket), length)), "receive three-player input batch")
			Next
		Next
	End If

	' Player zero broadcasts its hash. Other players send theirs to player zero.
	For Local source:Int = 0 Until multiSessions.Length
		Local hashLength:Size_T = multiSessions[source].WriteReadyHash(Byte Ptr(multiPacket), Size_T(multiPacket.Length))
		If hashLength > 0 Then
			If source = 0 Then
				For Local receiver:Int = 1 Until multiSessions.Length
					Check(multiSessions[receiver].ReceiveHash(source, New SPacketView(Byte Ptr(multiPacket), hashLength)), "receive authority hash")
				Next
			Else
				Check(multiSessions[0].ReceiveHash(source, New SPacketView(Byte Ptr(multiPacket), hashLength)), "authority receives player hash")
			End If
		End If
	Next

	For Local player:Int = 1 Until multiSessions.Length
		If multiSessions[player].NeedsStateSync() Then
			Local requestLength:Size_T = multiSessions[player].WriteStateSyncRequest(Byte Ptr(multiPacket), Size_T(multiPacket.Length))
			Local responseLength:Size_T = multiSessions[0].WriteStateSyncResponse(New SPacketView(Byte Ptr(multiPacket), requestLength), Byte Ptr(multiResponse), Size_T(multiResponse.Length))
			Check(requestLength > 0 And responseLength > 0, "exchange three-player state sync")
			Check(multiSessions[player].ReceiveStateSync(New SPacketView(Byte Ptr(multiResponse), responseLength)), "apply three-player state sync")
		End If
	Next
Next

' Flush the final redundant input batch and resolve any last rollback.
For Local source:Int = 0 Until multiSessions.Length
	Local length:Size_T = multiSessions[source].WriteInputs(Byte Ptr(multiPacket), Size_T(multiPacket.Length))
	For Local receiver:Int = 0 Until multiSessions.Length
		If receiver <> source Then Check(multiSessions[receiver].ReceiveInputs(source, New SPacketView(Byte Ptr(multiPacket), length)), "receive final three-player inputs")
	Next
Next
For Local player:Int = 0 Until multiSessions.Length
	Check(multiSessions[player].Step(Byte Ptr(zero), 1), "resolve final three-player rollback")
Next

For Local player:Int = 1 Until multiSessions.Length
	For Local position:Int = 0 Until 3
		Check(multiSimulations[player].positions[position] = multiSimulations[0].positions[position], "three-player deterministic state converged: peer " + player + ", position " + position + ", expected " + multiSimulations[0].positions[position] + ", got " + multiSimulations[player].positions[position])
	Next
	Check(multiSessions[player].HasRemoteFrame(0), "per-player remote progress available")
Next
Check(multiSessions[0].HasRemoteFrame() And multiSessions[0].RemoteSimulationFrame() > 0, "aggregate remote progress available")
Check(multiSessions[2].StateSyncCount() = 1 And multiSessions[2].HashMismatches() > 0, "divergent third player recovered")
Check(multiSessions[1].StateSyncCount() = 0 And multiSessions[1].HashMismatches() = 0, "healthy third player did not resynchronise")
For Local player:Int = 0 Until multiSessions.Length
	Check(Not multiSessions[player].Failed(), "three-player session remained healthy")
Next

Print "GameNet.RollbackSession tests passed"
